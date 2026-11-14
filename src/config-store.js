const fs = require('node:fs/promises');
const path = require('node:path');
const { randomUUID } = require('node:crypto');
const { isDeepStrictEqual } = require('node:util');

const DEFAULT_CONFIG = { isActive: false, systemPrompt: 'You are a helpful assistant.', allowedChats: [] };
const JID_PATTERN = /^(?:[1-9]\d{4,19}@s\.whatsapp\.net|[1-9]\d{4,19}(?:-\d{1,20})?@g\.us|[1-9]\d{4,19}@lid)$/;

class ValidationError extends Error {}
function validateConfig(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value) ||
      typeof value.isActive !== 'boolean' || typeof value.systemPrompt !== 'string' ||
      !value.systemPrompt.trim() || value.systemPrompt.length > 8000 ||
      !Array.isArray(value.allowedChats) || value.allowedChats.length > 1000 ||
      value.allowedChats.some(jid => typeof jid !== 'string' || !JID_PATTERN.test(jid))) {
    throw new ValidationError('Invalid configuration: use a boolean active state, a 1–8000 character prompt, and valid WhatsApp chat IDs (maximum 1000).');
  }
  return { isActive: value.isActive, systemPrompt: value.systemPrompt.trim(), allowedChats: [...new Set(value.allowedChats)] };
}

class ConfigStore {
  constructor(filename) {
    this.filename = filename;
    this.value = structuredClone(DEFAULT_CONFIG);
    this.allowedChats = new Set();
    this.revision = 0;
    this.pending = Promise.resolve();
  }
  async load() {
    try {
      this.value = validateConfig(JSON.parse(await fs.readFile(this.filename, 'utf8')));
    } catch (error) {
      if (error.code !== 'ENOENT') throw new Error('Cannot load config.json; repair it before starting.', { cause: error });
    }
    this.allowedChats = new Set(this.value.allowedChats);
    return this;
  }
  get() { return structuredClone(this.value); }
  allows(jid) { return this.value.isActive && this.allowedChats.has(jid); }
  update(change) {
    const operation = this.pending.then(async () => {
      const next = validateConfig(change(this.get()));
      if (isDeepStrictEqual(next, this.value)) return this.get();
      const temporary = `${this.filename}.${randomUUID()}.tmp`;
      try {
        await fs.mkdir(path.dirname(this.filename), { recursive: true });
        const handle = await fs.open(temporary, 'wx', 0o600);
        try {
          await handle.writeFile(`${JSON.stringify(next, null, 2)}\n`);
          await handle.sync();
        } finally { await handle.close(); }
        await fs.rename(temporary, this.filename);
      } finally { await fs.unlink(temporary).catch(() => {}); }
      // Publish only after the new configuration is safely written.
      this.value = next;
      this.allowedChats = new Set(next.allowedChats);
      this.revision++;
      return this.get();
    });
    this.pending = operation.catch(() => {});
    return operation;
  }
}
module.exports = { ConfigStore, ValidationError, validateConfig, JID_PATTERN };
