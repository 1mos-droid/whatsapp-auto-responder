const { setTimeout: sleep } = require('node:timers/promises');
const isDirectJid = jid => typeof jid === 'string' && /@(?:s\.whatsapp\.net|lid)$/.test(jid);

class Responder {
  constructor({ store, generate, normalize = x => x, logger = console, delay = () => sleep(1000 + Math.random() * 1500), now = Date.now, maxPending = 100, concurrency = 3 }) {
    Object.assign(this, { store, generate, normalize, logger, delay, now, maxPending, concurrency });
    this.socket = null;
    this.queue = [];
    this.busyChats = new Set();
    this.seen = new Map();
    this.running = new Set();
    this.stats = { received: 0, sent: 0, failed: 0, skipped: 0 };
  }
  setSocket(socket) { this.socket = socket; }
  status() { return { ...this.stats, pending: this.queue.length + this.running.size }; }
  enqueue(event) {
    if (event.type !== 'notify' || !this.socket) return;
    const time = this.now();
    for (const [key, expires] of this.seen) if (expires <= time) this.seen.delete(key);
    for (const message of event.messages || []) {
      const { remoteJid: jid, remoteJidAlt, fromMe, id, participant } = message.key || {};
      if (fromMe || !id) continue;
      // Baileys may deliver the same direct chat under a linked ID or phone ID.
      // A group participant's alternate ID never authorizes the group itself.
      const accessJid = this.store.allows(jid) ? jid :
        isDirectJid(jid) && isDirectJid(remoteJidAlt) && this.store.allows(remoteJidAlt) ? remoteJidAlt : null;
      if (!accessJid) continue;
      const content = this.normalize(message.message);
      const text = content?.conversation || content?.extendedTextMessage?.text;
      if (typeof text !== 'string' || !text.trim() || text.length > 16000) continue;
      const timestamp = Number(message.messageTimestamp);
      if (Number.isFinite(timestamp) && timestamp > 0 && time - timestamp * 1000 > 120000) continue;
      const key = JSON.stringify([accessJid, participant, id]);
      if (this.seen.has(key)) continue;
      if (this.queue.length + this.running.size >= this.maxPending) { this.stats.skipped++; continue; }
      // Bounded suppression cache; do not retry uncertain sends automatically.
      this.seen.set(key, time + 600000);
      if (this.seen.size > 10000) this.seen.delete(this.seen.keys().next().value);
      this.stats.received++;
      this.queue.push({ message, text, jid, accessJid, socket: this.socket, revision: this.store.revision, enqueuedAt: time });
    }
    this.pump();
  }
  valid(job) {
    return this.socket === job.socket && this.store.allows(job.accessJid) && this.store.revision === job.revision && this.now() - job.enqueuedAt < 120000;
  }
  pump() {
    while (this.running.size < this.concurrency) {
      const index = this.queue.findIndex(job => !this.busyChats.has(job.jid));
      if (index === -1) break;
      const [job] = this.queue.splice(index, 1);
      this.busyChats.add(job.jid);
      const task = this.process(job).finally(() => {
        this.running.delete(task);
        this.busyChats.delete(job.jid);
        this.pump();
      });
      this.running.add(task);
    }
  }
  async process(job) {
    let composing = false;
    try {
      if (!this.valid(job)) { this.stats.skipped++; return; }
      const reply = await this.generate(job.text, this.store.get().systemPrompt);
      if (typeof reply !== 'string' || !reply.trim() || reply.length > 16000) throw new Error('Empty or oversized AI response');
      if (!this.valid(job)) { this.stats.skipped++; return; }
      // Presence is cosmetic: failure must not discard an otherwise valid reply.
      await job.socket.sendPresenceUpdate('composing', job.jid).then(() => { composing = true; }).catch(() => {});
      await this.delay();
      if (!this.valid(job)) { this.stats.skipped++; return; }
      await job.socket.sendMessage(job.jid, { text: reply.trim() }, { quoted: job.message });
      this.stats.sent++;
    } catch {
      this.stats.failed++;
      this.logger.error('[Responder] Reply failed. No automatic retry was attempted.');
    } finally {
      if (composing && this.socket === job.socket) await job.socket.sendPresenceUpdate('paused', job.jid).catch(() => {});
    }
  }
  async idle() { while (this.running.size) await Promise.all([...this.running]); }
  stop() { this.socket = null; this.stats.skipped += this.queue.length; this.queue = []; }
}
module.exports = { Responder };
