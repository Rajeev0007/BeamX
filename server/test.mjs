// End-to-end test of the relay server using Node's built-in WebSocket client.
// Run: node --test server/test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

process.env.DATA_DIR = mkdtempSync(join(tmpdir(), 'beamx-'));
process.env.TURN_URLS = 'turn:203.0.113.5:3478?transport=udp';
process.env.TURN_SECRET = 'test-secret';
const { server, shortIdFor } = await import('./beamx-signal.mjs');

await new Promise((r) => server.listen(0, r));
const url = `ws://127.0.0.1:${server.address().port}/beamx`;
const hex = (n) => [...crypto.getRandomValues(new Uint8Array(n))].map((b) => b.toString(16).padStart(2, '0')).join('');

function client() {
  const ws = new WebSocket(url);
  const queue = [];
  const waiters = [];
  let closed = null;
  ws.onmessage = (e) => {
    const m = JSON.parse(e.data);
    const w = waiters.shift();
    w ? w(m) : queue.push(m);
  };
  ws.onclose = (e) => {
    closed = e.reason || String(e.code);
    while (waiters.length) waiters.shift()({ t: 'closed', reason: closed });
  };
  return {
    ws,
    open: new Promise((r) => (ws.onopen = r)),
    send: (m) => ws.send(JSON.stringify(m)),
    next: () =>
      queue.length
        ? Promise.resolve(queue.shift())
        : closed
          ? Promise.resolve({ t: 'closed', reason: closed })
          : new Promise((r) => waiters.push(r)),
  };
}

async function registered(id = hex(16), key = hex(32)) {
  const c = client();
  await c.open;
  c.send({ t: 'hello', v: 1, id, key });
  const w = await c.next();
  return { c, w, id, key };
}

test('register, dial, relay both ways, hang up', async () => {
  const host = await registered();
  const caller = await registered();
  assert.equal(host.w.t, 'welcome');
  assert.equal(host.w.shortId, shortIdFor(host.id));
  assert.match(host.w.shortId, /^\d{9}$/);
  // TURN credentials follow coturn's REST API format.
  const turn = host.w.ice.find((s) => s.username);
  assert.ok(turn && turn.credential && turn.urls[0].startsWith('turn:'));
  assert.ok(host.w.ice.some((s) => s.urls[0].startsWith('stun:')));

  const sid = hex(8);
  caller.c.send({ t: 'dial', sid, to: host.w.shortId });
  assert.deepEqual(await caller.c.next(), { t: 'ringing', sid });
  assert.deepEqual(await host.c.next(), { t: 'ring', sid, from: caller.w.shortId });

  host.c.send({ t: 'relay', sid, d: '{"t":"challenge"}' });
  assert.deepEqual(await caller.c.next(), { t: 'relay', sid, d: '{"t":"challenge"}' });
  caller.c.send({ t: 'relay', sid, d: '{"t":"hello"}' });
  assert.deepEqual(await host.c.next(), { t: 'relay', sid, d: '{"t":"hello"}' });

  caller.c.send({ t: 'hangup', sid });
  assert.deepEqual(await host.c.next(), { t: 'hangup', sid });
  host.c.ws.close();
  caller.c.ws.close();
});

test('dialing an offline ID reports offline', async () => {
  const a = await registered();
  const sid = hex(8);
  a.c.send({ t: 'dial', sid, to: '000000000' });
  assert.deepEqual(await a.c.next(), { t: 'hangup', sid, reason: 'offline' });
  a.c.ws.close();
});

test('another device cannot take over a registered ID', async () => {
  const owner = await registered();
  owner.c.ws.close();
  await new Promise((r) => setTimeout(r, 100));
  const thief = await registered(owner.id, hex(32));
  assert.equal(thief.w.t, 'closed');
  assert.match(thief.w.reason, /another device/);
  // The real owner can come back with its key.
  const back = await registered(owner.id, owner.key);
  assert.equal(back.w.t, 'welcome');
  back.c.ws.close();
});

test('a third device cannot inject into a session', async () => {
  const host = await registered();
  const caller = await registered();
  const intruder = await registered();
  const sid = hex(8);
  caller.c.send({ t: 'dial', sid, to: host.w.shortId });
  await caller.c.next();
  await host.c.next();
  intruder.c.send({ t: 'relay', sid, d: 'evil' });
  intruder.c.send({ t: 'hangup', sid });
  caller.c.send({ t: 'relay', sid, d: 'real' });
  assert.deepEqual(await host.c.next(), { t: 'relay', sid, d: 'real' });
  for (const x of [host, caller, intruder]) x.c.ws.close();
});

test('closing a device ends its sessions', async () => {
  const host = await registered();
  const caller = await registered();
  const sid = hex(8);
  caller.c.send({ t: 'dial', sid, to: host.w.shortId });
  await caller.c.next();
  await host.c.next();
  caller.c.ws.close();
  assert.deepEqual(await host.c.next(), { t: 'hangup', sid });
  host.c.ws.close();
});

test('invalid hello is rejected', async () => {
  const c = client();
  await c.open;
  c.send({ t: 'hello', v: 1, id: 'not-hex', key: hex(32) });
  assert.equal((await c.next()).t, 'closed');
});

test('messages over 64 KB close the connection', async () => {
  const a = await registered();
  a.c.send({ t: 'relay', sid: hex(8), d: 'x'.repeat(70 * 1024) });
  assert.equal((await a.c.next()).t, 'closed');
});

test.after(() => server.close());
