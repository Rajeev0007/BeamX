// Live check of the public PeerJS server with BeamX's message format.
// Run in CI: node server/peerjs-check.mjs
// Verifies: OPEN on connect, BeamX messages (wrapped as PeerJS candidates)
// pass through unchanged up to the part size, and the server sets `src`.
import assert from 'node:assert/strict';

const rand = () => [...crypto.getRandomValues(new Uint8Array(12))].map((b) => b.toString(16).padStart(2, '0')).join('');
const nine = () => String(Math.floor(Math.random() * 1e9)).padStart(9, '0');

function peer(id) {
  const ws = new WebSocket(`wss://0.peerjs.com/peerjs?key=peerjs&id=${id}&token=${rand()}&version=1.5.4`);
  const queue = [];
  const waiters = [];
  ws.onmessage = (e) => {
    const m = JSON.parse(e.data);
    const w = waiters.shift();
    w ? w(m) : queue.push(m);
  };
  const next = (ms = 10000) =>
    queue.length
      ? Promise.resolve(queue.shift())
      : new Promise((res, rej) => {
          const t = setTimeout(() => rej(new Error('timeout waiting for message')), ms);
          waiters.push((m) => (clearTimeout(t), res(m)));
        });
  const hb = setInterval(() => ws.readyState === 1 && ws.send(JSON.stringify({ type: 'HEARTBEAT' })), 5000);
  return { ws, next, close: () => (clearInterval(hb), ws.close()) };
}

// Same wrapping as app/lib/services/peerjs_relay.dart.
const wrap = (dst, msg) => JSON.stringify({
  type: 'CANDIDATE',
  dst,
  payload: {
    candidate: { candidate: JSON.stringify({ beamx: 1, ...msg }), sdpMid: '0', sdpMLineIndex: 0 },
    type: 'data',
    connectionId: 'dc_beamx',
  },
});

const aId = `beamx1-${nine()}`;
const bId = `beamx1-${nine()}`;
const a = peer(aId);
const b = peer(bId);
assert.equal((await a.next()).type, 'OPEN');
assert.equal((await b.next()).type, 'OPEN');
console.log('✓ both peers registered (OPEN)');

for (const size of [100, 12000]) {
  const msg = { k: 'relay', sid: 'a1b2c3d4e5f60718', d: 'y'.repeat(size) };
  a.ws.send(wrap(bId, msg));
  const got = await b.next();
  assert.equal(got.type, 'CANDIDATE');
  assert.equal(got.src, aId, 'server must set src');
  assert.deepEqual(JSON.parse(got.payload.candidate.candidate), { beamx: 1, ...msg });
  console.log(`✓ ${size}-character message passed through unchanged`);
}

a.close();
b.close();
console.log('PeerJS public server works with BeamX');
process.exit(0);
