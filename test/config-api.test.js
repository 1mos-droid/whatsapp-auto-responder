const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { ConfigStore } = require('../src/config-store');
const { createApp } = require('../src/api');
const jid = '15551234567@s.whatsapp.net';
async function fixture(t) {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), 'responder-'));
  t.after(() => fs.rm(dir, { recursive: true, force: true }));
  return { dir, store: await new ConfigStore(path.join(dir, 'config.json')).load() };
}
test('missing config starts disabled; callers cannot mutate the cache', async t => {
  const { store } = await fixture(t);
  const copy = store.get(); copy.isActive = true; copy.allowedChats.push(jid);
  assert.equal(store.get().isActive, false);
  assert.deepEqual(store.get().allowedChats, []);
});
test('parallel updates preserve every change and survive reload', async t => {
  const { store } = await fixture(t);
  await Promise.all([
    store.update(c => ({ ...c, allowedChats: [...c.allowedChats, jid] })),
    store.update(c => ({ ...c, systemPrompt: 'Be concise.' })),
    store.update(c => ({ ...c, isActive: true })),
  ]);
  const loaded = await new ConfigStore(store.filename).load();
  assert.deepEqual(loaded.get(), { isActive: true, systemPrompt: 'Be concise.', allowedChats: [jid] });
  assert.equal(store.revision, 3);
  assert.equal((await fs.stat(store.filename)).mode & 0o777, 0o600);
});
test('invalid stored config fails startup instead of silently resetting settings', async t => {
  const { store } = await fixture(t);
  await fs.writeFile(store.filename, '{broken');
  await assert.rejects(() => store.load(), /Cannot load/);
});
test('failed persistence never publishes a change and the queue recovers', async t => {
  const { store, dir } = await fixture(t);
  store.filename = dir; // Atomic rename onto a directory must fail.
  await assert.rejects(store.update(c => ({ ...c, isActive: true })));
  assert.equal(store.get().isActive, false);
  assert.equal(store.revision, 0);
  store.filename = path.join(dir, 'config.json');
  await store.update(c => ({ ...c, isActive: true }));
  assert.equal(store.get().isActive, true);
  assert.deepEqual((await fs.readdir(dir)), ['config.json']);
});
test('API refuses to initialize without authentication', async t => {
  const { store } = await fixture(t);
  assert.throws(() => createApp({ store }), /CONTROL_API_KEY/);
});
async function api(t) {
  const { store } = await fixture(t);
  const app = createApp({ store, apiKey: 'test-secret', getRuntime: () => ({ connection: 'open' }), logger: { error() {} } });
  const server = await new Promise(resolve => { const s = app.listen(0, '127.0.0.1', () => resolve(s)); });
  t.after(() => new Promise(resolve => { server.close(resolve); server.closeAllConnections(); }));
  const request = (url, body, headers = {}) => fetch(`http://127.0.0.1:${server.address().port}${url}`, {
    method: body === undefined ? 'GET' : 'POST',
    headers: { 'x-api-key': 'test-secret', 'content-type': 'application/json', ...headers },
    body: body === undefined ? undefined : typeof body === 'string' ? body : JSON.stringify(body),
  });
  return { store, request };
}
test('API requires key and reports runtime without caching sensitive settings', async t => {
  const { request } = await api(t);
  assert.equal((await request('/status', undefined, { 'x-api-key': '' })).status, 401);
  const response = await request('/status');
  assert.equal(response.headers.get('cache-control'), 'no-store');
  assert.equal((await response.json()).runtime.connection, 'open');
  assert.equal(response.headers.get('access-control-allow-origin'), null);
});
test('explicit active state is idempotent across repeated requests', async t => {
  const { request, store } = await api(t);
  for (let i = 0; i < 2; i++) assert.equal((await request('/toggle', { isActive: true })).status, 200);
  assert.equal(store.get().isActive, true);
  assert.equal(store.revision, 1, 'retries must not cancel pending replies or rewrite the same settings');
  assert.equal((await request('/toggle', {})).status, 400);
});
test('API rejects malformed input and does not mutate saved settings', async t => {
  const { request, store } = await api(t);
  for (const [route, payload] of [
    ['/prompt', { newPrompt: '' }], ['/prompt', { newPrompt: 7 }],
    ['/prompt', { newPrompt: 'a'.repeat(8001) }], ['/chats/add', {}],
    ['/chats/add', { jid: 'status@broadcast' }], ['/chats/remove', { jid: [] }],
    ['/toggle', { isActive: 'true' }], ['/prompt', 'null'], ['/prompt', '{bad'],
  ]) assert.equal((await request(route, payload)).status, 400, route);
  assert.equal(store.revision, 0);
  assert.equal((await request('/prompt', { newPrompt: 'x'.repeat(40000) })).status, 413);
  assert.equal((await request('/unknown')).status, 404);
});
test('chat addition is deduplicated, removal works, and prompts are trimmed', async t => {
  const { request, store } = await api(t);
  await request('/chats/add', { jid }); await request('/chats/add', { jid });
  assert.deepEqual(store.get().allowedChats, [jid]);
  await request('/prompt', { newPrompt: '  Be kind.  ' });
  assert.equal(store.get().systemPrompt, 'Be kind.');
  await request('/chats/remove', { jid });
  assert.deepEqual(store.get().allowedChats, []);
});
test('API persistence failures return 500 and preserve the active state', async t => {
  const { request, store } = await api(t);
  store.filename = path.dirname(store.filename);
  const response = await request('/toggle', { isActive: true });
  assert.equal(response.status, 500);
  assert.equal(store.get().isActive, false);
});
