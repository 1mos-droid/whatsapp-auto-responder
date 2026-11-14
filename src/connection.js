class WhatsAppConnection {
  constructor({ baileys, responder, authPath, logger, onQr, timers = { setTimeout, clearTimeout } }) {
    Object.assign(this, { baileys, responder, authPath, logger, onQr, timers });
    this.state = 'disconnected';
    this.socket = null;
    this.timer = null;
    this.stopped = false;
    this.attempts = 0;
    this.starting = false;
    this.credentials = Promise.resolve();
  }
  status() { return { connection: this.state, reconnectAttempts: this.attempts, ...this.responder.status() }; }
  schedule() {
    if (this.stopped || this.timer) return;
    this.state = 'reconnecting';
    const delay = Math.min(1000 * 2 ** Math.min(this.attempts++, 5), 30000);
    this.timer = this.timers.setTimeout(() => { this.timer = null; void this.connect(); }, delay);
  }
  async connect() {
    if (this.stopped || this.starting || this.socket) return;
    this.starting = true;
    this.state = 'connecting';
    try {
      await this.credentials;
      const { state, saveCreds } = await this.baileys.useMultiFileAuthState(this.authPath);
      if (this.stopped) return;
      const socket = this.baileys.default({ auth: state, logger: this.logger, markOnlineOnConnect: false, syncFullHistory: false, shouldSyncHistoryMessage: () => false });
      this.socket = socket;
      socket.ev.on('creds.update', () => {
        this.credentials = this.credentials.then(saveCreds).catch(() => { this.logger.error('[WhatsApp] Unable to persist credentials. Check auth directory storage.'); });
      });
      socket.ev.on('messages.upsert', event => {
        if (this.socket === socket && this.state === 'open') this.responder.enqueue(event);
      });
      socket.ev.on('connection.update', update => {
        if (this.stopped || this.socket !== socket) return;
        if (update.qr) { this.state = 'awaiting_qr'; this.onQr(update.qr); }
        if (update.connection === 'open') {
          this.state = 'open';
          this.attempts = 0;
          this.responder.setSocket(socket);
          this.logger.info('[WhatsApp] Connected.');
        }
        if (update.connection === 'close') {
          this.responder.setSocket(null);
          this.socket = null;
          socket.ev.removeAllListeners();
          const code = update.lastDisconnect?.error?.output?.statusCode;
          const reasons = this.baileys.DisconnectReason;
          const terminal = [reasons.loggedOut, reasons.badSession, reasons.connectionReplaced, reasons.multideviceMismatch, reasons.forbidden].filter(value => value !== undefined);
          if (terminal.includes(code)) {
            this.state = code === reasons.loggedOut ? 'logged_out' : 'action_required';
            this.logger.warn('[WhatsApp] Session needs attention. Resolve the session issue and restart.');
          } else this.schedule();
        }
      });
    } catch {
      this.logger.error('[WhatsApp] Connection attempt failed. Retrying with backoff.');
      this.schedule();
    } finally { this.starting = false; }
  }
  async stop() {
    this.stopped = true;
    this.state = 'stopped';
    if (this.timer) this.timers.clearTimeout(this.timer);
    this.responder.stop();
    const socket = this.socket;
    this.socket = null;
    if (socket) { socket.ev.removeAllListeners(); await socket.end(new Error('Server shutting down')); }
    await this.credentials;
  }
}
module.exports = { WhatsAppConnection };
