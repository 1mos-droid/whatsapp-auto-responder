const express = require('express');
const cors = require('cors');
const { timingSafeEqual, createHash } = require('node:crypto');
const { ValidationError, JID_PATTERN } = require('./config-store');

function createApp({ store, apiKey, getRuntime = () => ({}), origins = [], logger = console }) {
  if (!apiKey?.trim()) throw new Error('CONTROL_API_KEY is required.');
  const secret = createHash('sha256').update(apiKey).digest();
  const app = express();
  app.disable('x-powered-by');
  app.use((_req, res, next) => {
    res.set({ 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' });
    next();
  });
  if (origins.length) app.use(cors({ origin: origins, methods: ['GET', 'POST'], allowedHeaders: ['Content-Type', 'x-api-key'] }));
  app.use((req, res, next) => {
    const supplied = createHash('sha256').update(req.get('x-api-key') || '').digest();
    if (!timingSafeEqual(secret, supplied)) return res.status(401).json({ error: 'Unauthorized. Check the control API key.' });
    next();
  });
  app.use(express.json({ limit: '32kb', strict: true }));
  const body = req => {
    if (!req.body || typeof req.body !== 'object' || Array.isArray(req.body)) throw new ValidationError('A JSON object is required.');
    return req.body;
  };
  app.get('/status', (_req, res) => res.json({ ...store.get(), runtime: getRuntime() }));
  app.post('/toggle', async (req, res) => {
    const input = body(req);
    if (typeof input.isActive !== 'boolean') throw new ValidationError('isActive must be a boolean.');
    const config = await store.update(current => ({ ...current, isActive: input.isActive }));
    res.json({ success: true, isActive: config.isActive });
  });
  app.post('/prompt', async (req, res) => {
    const { newPrompt } = body(req);
    if (typeof newPrompt !== 'string' || !newPrompt.trim() || newPrompt.length > 8000) throw new ValidationError('Prompt must contain 1–8000 characters.');
    const config = await store.update(current => ({ ...current, systemPrompt: newPrompt }));
    res.json({ success: true, systemPrompt: config.systemPrompt });
  });
  for (const action of ['add', 'remove']) {
    app.post(`/chats/${action}`, async (req, res) => {
      const { jid } = body(req);
      if (typeof jid !== 'string' || !JID_PATTERN.test(jid)) throw new ValidationError('Enter a valid WhatsApp chat ID, such as 15551234567@s.whatsapp.net.');
      const config = await store.update(current => ({
        ...current,
        allowedChats: action === 'add' ? [...new Set([...current.allowedChats, jid])] : current.allowedChats.filter(id => id !== jid),
      }));
      res.json({ success: true, allowedChats: config.allowedChats });
    });
  }
  app.use((_req, res) => res.status(404).json({ error: 'Endpoint not found.' }));
  app.use((error, _req, res, _next) => {
    if (error instanceof ValidationError || error.type === 'entity.parse.failed') return res.status(400).json({ error: error instanceof ValidationError ? error.message : 'Invalid JSON body.' });
    if (error.type === 'entity.too.large') return res.status(413).json({ error: 'Request body is too large.' });
    logger.error('[API] Request failed; configuration was not changed.');
    res.status(500).json({ error: 'Unable to save settings. Check server storage and retry.' });
  });
  return app;
}
module.exports = { createApp };
