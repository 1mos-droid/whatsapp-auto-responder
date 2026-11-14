require('dotenv').config({ path: require('node:path').join(__dirname, '.env'), quiet: true });
const path = require('node:path');
const pino = require('pino');
const Groq = require('groq-sdk');
const qrcode = require('qrcode-terminal');
const { ConfigStore } = require('./src/config-store');
const { createApp } = require('./src/api');
const { Responder } = require('./src/responder');
const { WhatsAppConnection } = require('./src/connection');

async function main() {
  for (const name of ['GROQ_API_KEY', 'CONTROL_API_KEY']) {
    if (!process.env[name]?.trim()) throw new Error(`${name} must be set in .env before starting.`);
  }
  const port = Number(process.env.PORT || 3000);
  if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error('PORT must be an integer between 1 and 65535.');
  const logger = pino({ level: process.env.LOG_LEVEL || 'info' });
  const store = await new ConfigStore(path.join(__dirname, 'config.json')).load();
  const baileys = await import('@whiskeysockets/baileys');
  const groq = new Groq({ apiKey: process.env.GROQ_API_KEY, timeout: 30000, maxRetries: 1 });
  const inference = new AbortController();
  const responder = new Responder({
    store, logger, normalize: baileys.normalizeMessageContent,
    generate: async (text, prompt) => {
      const completion = await groq.chat.completions.create({
        model: process.env.GROQ_MODEL || 'openai/gpt-oss-20b',
        messages: [{ role: 'system', content: prompt }, { role: 'user', content: text }],
        max_completion_tokens: 2048,
      }, { signal: inference.signal });
      return completion.choices[0]?.message?.content;
    },
  });
  const connection = new WhatsAppConnection({
    baileys, responder, authPath: path.join(__dirname, 'auth_info'), logger,
    onQr: qr => { logger.info('[WhatsApp] Scan the QR code with Linked devices.'); qrcode.generate(qr, { small: true }); },
  });
  const app = createApp({ store, apiKey: process.env.CONTROL_API_KEY, getRuntime: () => connection.status(), logger, origins: (process.env.CONTROL_ALLOWED_ORIGINS || '').split(',').map(value => value.trim()).filter(Boolean) });
  const host = process.env.HOST || '127.0.0.1';
  const server = await new Promise((resolve, reject) => {
    const listener = app.listen(port, host, () => resolve(listener));
    listener.once('error', reject);
  });
  logger.info(`[API] Listening on ${host}:${port}`);
  let stopping = false;
  const shutdown = async () => {
    if (stopping) return;
    stopping = true;
    logger.info('[Server] Shutting down.');
    const deadline = setTimeout(() => process.exit(1), 10000);
    deadline.unref();
    const closed = new Promise(resolve => server.close(resolve));
    server.closeIdleConnections();
    inference.abort();
    await connection.stop();
    await Promise.all([responder.idle(), store.pending, closed]);
    clearTimeout(deadline);
  };
  process.once('SIGINT', () => { void shutdown(); });
  process.once('SIGTERM', () => { void shutdown(); });
  void connection.connect();
  return { server, connection, responder, store, shutdown };
}
if (require.main === module) main().catch(error => {
  console.error(`[Startup] ${error.message}`);
  process.exitCode = 1;
});
module.exports = { main };
