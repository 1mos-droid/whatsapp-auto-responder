const { test } = require('node:test');
const assert = require('node:assert/strict');
const { Responder } = require('../src/responder');
const jid = '15551234567@s.whatsapp.net';
const other = '15557654321@s.whatsapp.net';
const message = (id, extra = {}) => ({ key: { remoteJid: jid, id }, message: { conversation: id }, ...extra });
const deferred = () => { let resolve; const promise = new Promise(r => { resolve = r; }); return { promise, resolve }; };
function fixture(options = {}) {
  const sent = [];
  const presence = [];
  const config = { isActive: true, systemPrompt: 'Be kind.', allowedChats: [jid, other] };
  const store = { revision: 0, get: () => config, allows: id => config.isActive && config.allowedChats.includes(id) };
  const socket = { sendPresenceUpdate: async (...args) => { presence.push(args); }, sendMessage: async (...args) => { sent.push(args); } };
  const responder = new Responder({ store, generate: async text => `Reply ${text}`, delay: async () => {}, logger: { error() {} }, ...options });
  responder.setSocket(socket);
  return { responder, socket, config, store, sent, presence };
}
test('every batched message is processed in order; duplicates are suppressed', async () => {
  const { responder, sent } = fixture();
  responder.enqueue({ type: 'notify', messages: [message('one'), message('two'), message('one')] });
  await responder.idle();
  assert.deepEqual(sent.map(([, content]) => content.text), ['Reply one', 'Reply two']);
  assert.equal(responder.status().sent, 2);
});
test('history, own messages, nonallowed chats, empty content and stale messages never generate replies', async () => {
  const { responder, sent } = fixture();
  responder.enqueue({ type: 'append', messages: [message('history')] });
  responder.enqueue({ type: 'notify', messages: [
    {}, message('own', { key: { remoteJid: jid, id: 'own', fromMe: true } }),
    message('stranger', { key: { remoteJid: 'status@broadcast', id: 'x' } }),
    message('image', { message: { imageMessage: {} } }),
    message('old', { messageTimestamp: 1 }), message('large', { message: { conversation: 'x'.repeat(16001) } }),
  ] });
  await responder.idle(); assert.equal(sent.length, 0);
});
for (const mode of ['pause', 'remove', 'revision', 'disconnect']) {
  test(`${mode} during generation cancels the pending reply`, async () => {
    const gate = deferred();
    const { responder, config, store, sent } = fixture({ generate: () => gate.promise });
    responder.enqueue({ type: 'notify', messages: [message('one')] });
    if (mode === 'pause') config.isActive = false;
    if (mode === 'remove') config.allowedChats = [];
    if (mode === 'revision') store.revision++;
    if (mode === 'disconnect') responder.setSocket(null);
    gate.resolve('Hello'); await responder.idle(); assert.equal(sent.length, 0);
  });
}
test('pausing during typing cancels send and clears composing presence', async () => {
  const { responder, config, sent, presence } = fixture({ delay: async () => { config.isActive = false; } });
  responder.enqueue({ type: 'notify', messages: [message('one')] });
  await responder.idle();
  assert.equal(sent.length, 0);
  assert.deepEqual(presence.map(([state]) => state), ['composing', 'paused']);
});
test('AI failures send no fallback text and do not block the next reply', async () => {
  const { responder, sent } = fixture({ generate: async text => { if (text === 'one') throw new Error('API down'); return 'Recovered'; } });
  responder.enqueue({ type: 'notify', messages: [message('one'), message('two')] });
  await responder.idle(); assert.equal(sent.length, 1); assert.equal(responder.status().failed, 1);
});
test('blank completions are never sent', async () => {
  const { responder, sent } = fixture({ generate: async () => '   ' });
  responder.enqueue({ type: 'notify', messages: [message('one')] });
  await responder.idle(); assert.equal(sent.length, 0); assert.equal(responder.status().failed, 1);
});
test('presence errors do not discard replies; send errors are contained', async () => {
  const { responder, socket, sent } = fixture();
  socket.sendPresenceUpdate = async () => { throw new Error('presence failed'); };
  responder.enqueue({ type: 'notify', messages: [message('one')] });
  await responder.idle(); assert.equal(sent.length, 1);
  socket.sendMessage = async () => { throw new Error('send failed'); };
  responder.enqueue({ type: 'notify', messages: [message('two')] });
  await responder.idle(); assert.equal(responder.status().failed, 1);
});
test('global concurrency and backlog stay bounded while separate chats progress', async () => {
  const gate = deferred(); let count = 0;
  const { responder } = fixture({ concurrency: 2, maxPending: 3, generate: async () => { count++; await gate.promise; return 'hi'; } });
  responder.enqueue({ type: 'notify', messages: [message('one'), message('two'), message('other', { key: { remoteJid: other, id: 'other' } }), message('overflow')] });
  assert.equal(count, 2); assert.equal(responder.status().pending, 3); assert.equal(responder.status().skipped, 1);
  gate.resolve(); await responder.idle(); assert.equal(count, 3);
});
test('same IDs from different group participants are distinct', async () => {
  const { responder, sent } = fixture();
  responder.enqueue({ type: 'notify', messages: ['a', 'b'].map(participant => message('same', { key: { remoteJid: jid, id: 'same', participant } })) });
  await responder.idle(); assert.equal(sent.length, 2);
});
test('queued work expires instead of sending old replies', async () => {
  let time = Date.now();
  const { responder, sent } = fixture({ now: () => time, delay: async () => { time += 120001; } });
  responder.enqueue({ type: 'notify', messages: [message('one'), message('two')] });
  await responder.idle(); assert.equal(sent.length, 0); assert.equal(responder.status().skipped, 2);
});
test('installed Baileys normalizes wrapped and extended live text', async () => {
  const { normalizeMessageContent } = await import('@whiskeysockets/baileys');
  const { responder, sent } = fixture({ normalize: normalizeMessageContent });
  responder.enqueue({ type: 'notify', messages: [
    message('wrapped', { message: { ephemeralMessage: { message: { conversation: 'wrapped text' } } } }),
    message('extended', { message: { extendedTextMessage: { text: 'extended text' } } }),
  ] });
  await responder.idle();
  assert.deepEqual(sent.map(([, content]) => content.text), ['Reply wrapped text', 'Reply extended text']);
});
test('verified direct-chat alternate IDs match the phone allowlist and suppress replay', async () => {
  const { responder, sent } = fixture();
  responder.enqueue({ type: 'notify', messages: [message('same', { key: { remoteJid: '998877665544@lid', remoteJidAlt: jid, id: 'same' } }), message('same')] });
  await responder.idle();
  assert.equal(sent.length, 1); assert.equal(sent[0][0], '998877665544@lid');
});
test('removing an allowed alternate ID cancels pending direct replies', async () => {
  const gate = deferred();
  const { responder, config, sent } = fixture({ generate: () => gate.promise });
  responder.enqueue({ type: 'notify', messages: [message('one', { key: { remoteJid: '998877665544@lid', remoteJidAlt: jid, id: 'one' } })] });
  config.allowedChats = [];
  gate.resolve('Hello'); await responder.idle(); assert.equal(sent.length, 0);
});
test('a group never inherits permission from an alternate direct chat ID', async () => {
  const { responder, sent } = fixture();
  responder.enqueue({ type: 'notify', messages: [message('one', { key: { remoteJid: '120363123456789@g.us', remoteJidAlt: jid, participantAlt: jid, id: 'one' } })] });
  await responder.idle(); assert.equal(sent.length, 0);
});
