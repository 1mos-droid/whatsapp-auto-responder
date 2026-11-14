const { test } = require('node:test');
const assert = require('node:assert/strict');
const { EventEmitter } = require('node:events');
const { WhatsAppConnection } = require('../src/connection');
function fixture() {
  const sockets = []; const timers = [];
  const responder = { socket: null, setSocket(s) { this.socket = s; }, status: () => ({}), enqueue() {}, stop() { this.socket = null; } };
  const baileys = {
    useMultiFileAuthState: async () => ({ state: {}, saveCreds: async () => {} }),
    default: () => { const socket = { ev: new EventEmitter(), end() {} }; sockets.push(socket); return socket; },
    DisconnectReason: { loggedOut: 401, connectionReplaced: 440, badSession: 500, forbidden: 403, restartRequired: 515 },
  };
  const connection = new WhatsAppConnection({ baileys, responder, authPath: '/unused', onQr() {}, logger: { info() {}, warn() {}, error() {} }, timers: { setTimeout: (fn, ms) => { const timer = { fn, ms }; timers.push(timer); return timer; }, clearTimeout: timer => { timer.cleared = true; } } });
  return { connection, sockets, timers, responder, baileys };
}
test('connection allows only one socket, retries on close, and resets backoff on open', async () => {
  const { connection, sockets, timers, responder } = fixture();
  await Promise.all([connection.connect(), connection.connect()]);
  assert.equal(sockets.length, 1);
  sockets[0].ev.emit('connection.update', { connection: 'open' });
  assert.equal(responder.socket, sockets[0]);
  sockets[0].ev.emit('connection.update', { connection: 'close' });
  assert.equal(responder.socket, null); assert.equal(timers.length, 1); assert.equal(timers[0].ms, 1000);
  timers[0].fn(); await new Promise(setImmediate);
  assert.equal(sockets.length, 2);
  sockets[1].ev.emit('connection.update', { connection: 'open' });
  assert.equal(connection.attempts, 0);
  await connection.stop();
});
test('setup failure retries; shutdown cancels pending reconnection', async () => {
  const { connection, baileys, timers } = fixture();
  baileys.useMultiFileAuthState = async () => { throw new Error('temporary storage issue'); };
  await connection.connect();
  assert.equal(timers.length, 1); assert.equal(connection.state, 'reconnecting');
  await connection.stop(); assert.equal(timers[0].cleared, true);
  timers[0].fn(); assert.equal(connection.state, 'stopped');
});
for (const code of [401, 440, 500, 403]) {
  test(`terminal session code ${code} does not reconnect in a loop`, async () => {
    const { connection, sockets, timers } = fixture();
    await connection.connect();
    sockets[0].ev.emit('connection.update', { connection: 'close', lastDisconnect: { error: { output: { statusCode: code } } } });
    assert.equal(timers.length, 0);
    assert.ok(['logged_out', 'action_required'].includes(connection.state));
    await connection.stop();
  });
}
