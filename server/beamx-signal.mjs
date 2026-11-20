#!/usr/bin/env node
// BeamX internet relay server.
//
// Helps two BeamX devices find each other over the internet and passes their
// connection-setup messages along. It never sees screen content: video,
// sound, files and input go directly between devices (or through TURN),
// end-to-end encrypted by WebRTC. The setup messages are authenticated by
// the devices themselves, so this server can't alter them unnoticed.
//
// No dependencies: Node.js 20+ only. Put it behind a TLS proxy (Caddy) so
// devices connect with wss://.
//
// Environment:
//   PORT         HTTP port to listen on (default 8080)
//   DATA_DIR     where device registrations are kept (default ./data)
//   TURN_URLS    comma-separated TURN URLs, e.g. turn:1.2.3.4:3478?transport=udp
//   TURN_SECRET  shared secret configured in coturn (static-auth-secret)
//   STUN_URLS    comma-separated STUN URLs (default: TURN host as STUN)

import { createServer } from 'node:http';
import { createHash, createHmac, timingSafeEqual } from 'node:crypto';
import { mkdirSync, readFileSync, writeFileSync, renameSync } from 'node:fs';
import { join } from 'node:path';

const PORT = Number(process.env.PORT ?? 8080);
const DATA_DIR = process.env.DATA_DIR ?? './data';
const TURN_URLS = (process.env.TURN_URLS ?? '').split(',').map((s) => s.trim()).filter(Boolean);
const TURN_SECRET = process.env.TURN_SECRET ?? '';
const STUN_URLS = (process.env.STUN_URLS ?? '').split(',').map((s) => s.trim()).filter(Boolean);

const MAX_MESSAGE = 64 * 1024;
const MAX_SESSIONS_PER_DEVICE = 4;
const MAX_MSGS_PER_SECOND = 200;
const MAX_CONNECTIONS_PER_IP = 20;
const TURN_TTL_SECONDS = 12 * 3600;
const PROTOCOL = 1;

// ---------- Device registrations (who owns which ID) ----------

mkdirSync(DATA_DIR, { recursive: true });
const REG_FILE = join(DATA_DIR, 'registrations.json');
/** @type {Record<string, string>} device id -> sha256(registration key) */
let registrations = {};
try {
  registrations = JSON.parse(readFileSync(REG_FILE, 'utf8'));
} catch {
  registrations = {};
}
let saveTimer = null;
function saveRegistrations() {
  clearTimeout(saveTimer);
  saveTimer = setTimeout(() => {
    const tmp = REG_FILE + '.tmp';
    writeFileSync(tmp, JSON.stringify(registrations));
    renameSync(tmp, REG_FILE);
  }, 500);
}

const sha256 = (s) => createHash('sha256').update(s).digest();

/** The 9-digit "Internet ID" people type. Must match the app's formula. */
export function shortIdFor(id) {
  return (sha256(id).readBigUInt64BE(0) % 1000000000n).toString().padStart(9, '0');
}

function iceServersFor(id) {
  const servers = [];
  const stun = STUN_URLS.length
    ? STUN_URLS
    : TURN_URLS.map((u) => u.replace(/^turns?:/, 'stun:').replace(/\?.*$/, ''));
  if (stun.length) servers.push({ urls: [...new Set(stun)] });
  if (TURN_URLS.length && TURN_SECRET) {
    // coturn "TURN REST API" credentials, valid for TURN_TTL_SECONDS.
    const username = `${Math.floor(Date.now() / 1000) + TURN_TTL_SECONDS}:${shortIdFor(id)}`;
    const credential = createHmac('sha1', TURN_SECRET).update(username).digest('base64');
    servers.push({ urls: TURN_URLS, username, credential });
  }
  return servers;
}

// ---------- Minimal WebSocket server (RFC 6455, text frames only) ----------

const GUID = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';

class Socket {
  constructor(sock, ip) {
    this.sock = sock;
    this.ip = ip;
    this.buf = Buffer.alloc(0);
    this.closed = false;
    this.alive = true;
    this.onmessage = () => {};
    this.onclose = () => {};
    sock.setNoDelay(true);
    sock.on('data', (d) => this.#onData(d));
    sock.on('close', () => this.#finish());
    sock.on('error', () => this.#finish());
  }

  #onData(chunk) {
    this.buf = Buffer.concat([this.buf, chunk]);
    if (this.buf.length > MAX_MESSAGE + 16) return this.close(1009, 'too big');
    for (;;) {
      if (this.buf.length < 2) return;
      const b0 = this.buf[0], b1 = this.buf[1];
      const fin = (b0 & 0x80) !== 0;
      const op = b0 & 0x0f;
      const masked = (b1 & 0x80) !== 0;
      let len = b1 & 0x7f;
      let off = 2;
      if (len === 126) {
        if (this.buf.length < 4) return;
        len = this.buf.readUInt16BE(2);
        off = 4;
      } else if (len === 127) {
        return this.close(1009, 'too big');
      }
      if (!masked) return this.close(1002, 'unmasked');
      if (len > MAX_MESSAGE) return this.close(1009, 'too big');
      if (this.buf.length < off + 4 + len) return;
      const mask = this.buf.subarray(off, off + 4);
      const data = Buffer.from(this.buf.subarray(off + 4, off + 4 + len));
      for (let i = 0; i < data.length; i++) data[i] ^= mask[i & 3];
      this.buf = this.buf.subarray(off + 4 + len);
      if (!fin || op === 0x0) return this.close(1003, 'fragmented');
      if (op === 0x1) this.onmessage(data.toString('utf8'));
      else if (op === 0x8) return this.close(1000, 'bye');
      else if (op === 0x9) this.#frame(0xa, data);
      else if (op === 0xa) this.alive = true;
      else return this.close(1003, 'unsupported');
    }
  }

  #frame(op, payload) {
    if (this.closed) return;
    const len = payload.length;
    const head = len < 126 ? Buffer.from([0x80 | op, len]) : Buffer.from([0x80 | op, 126, len >> 8, len & 0xff]);
    this.sock.write(Buffer.concat([head, payload]));
  }

  send(obj) {
    const p = Buffer.from(JSON.stringify(obj), 'utf8');
    if (p.length <= 0xffff) this.#frame(0x1, p);
  }

  ping() {
    this.#frame(0x9, Buffer.alloc(0));
  }

  close(code = 1000, reason = '') {
    if (this.closed) return;
    const r = Buffer.from(reason.slice(0, 100), 'utf8');
    const p = Buffer.alloc(2 + r.length);
    p.writeUInt16BE(code, 0);
    r.copy(p, 2);
    this.#frame(0x8, p);
    this.sock.end();
    this.#finish();
  }

  #finish() {
    if (this.closed) return;
    this.closed = true;
    this.sock.destroy();
    this.onclose();
  }
}

// ---------- Relay logic ----------

/** shortId -> Device */
const online = new Map();
/** sid -> { a: Device, b: Device } */
const sessions = new Map();
const connectionsPerIp = new Map();

class Device {
  constructor(ws) {
    this.ws = ws;
    this.id = null;
    this.shortId = null;
    this.sids = new Set();
    this.windowStart = Date.now();
    this.count = 0;
  }
}

function endSession(sid, notify) {
  const s = sessions.get(sid);
  if (!s) return;
  sessions.delete(sid);
  s.a.sids.delete(sid);
  s.b.sids.delete(sid);
  if (notify) for (const d of [s.a, s.b]) if (d !== notify) d.ws.send({ t: 'hangup', sid });
}

function handle(dev, raw) {
  const now = Date.now();
  if (now - dev.windowStart > 1000) {
    dev.windowStart = now;
    dev.count = 0;
  }
  if (++dev.count > MAX_MSGS_PER_SECOND) return dev.ws.close(1008, 'rate limit');

  let m;
  try {
    m = JSON.parse(raw);
  } catch {
    return dev.ws.close(1003, 'bad json');
  }
  if (typeof m !== 'object' || m === null || typeof m.t !== 'string') return dev.ws.close(1003, 'bad message');

  if (m.t === 'hello') {
    if (dev.id) return;
    const { id, key, v } = m;
    if (v !== PROTOCOL) return dev.ws.close(1008, 'Update BeamX to use this server');
    if (typeof id !== 'string' || !/^[0-9a-f]{32}$/.test(id)) return dev.ws.close(1008, 'bad id');
    if (typeof key !== 'string' || !/^[0-9a-f]{64}$/.test(key)) return dev.ws.close(1008, 'bad key');
    // The first device to register an ID owns it (trust on first use).
    const keyHash = sha256(key).toString('hex');
    const known = registrations[id];
    if (known && !timingSafeEqual(Buffer.from(known, 'hex'), Buffer.from(keyHash, 'hex'))) {
      return dev.ws.close(1008, 'This ID belongs to another device');
    }
    if (!known) {
      registrations[id] = keyHash;
      saveRegistrations();
    }
    const shortId = shortIdFor(id);
    const previous = online.get(shortId);
    if (previous && previous.id !== id) return dev.ws.close(1008, 'ID collision');
    if (previous) previous.ws.close(1000, 'replaced by a new connection');
    dev.id = id;
    dev.shortId = shortId;
    online.set(shortId, dev);
    return dev.ws.send({ t: 'welcome', shortId, ice: iceServersFor(id) });
  }

  if (!dev.id) return dev.ws.close(1008, 'say hello first');
  const sid = m.sid;
  if (typeof sid !== 'string' || !/^[0-9a-f]{16,32}$/.test(sid)) return;

  switch (m.t) {
    case 'dial': {
      const target = typeof m.to === 'string' ? online.get(m.to) : undefined;
      if (!target || target === dev) return dev.ws.send({ t: 'hangup', sid, reason: 'offline' });
      if (sessions.has(sid)) return;
      if (dev.sids.size >= MAX_SESSIONS_PER_DEVICE || target.sids.size >= MAX_SESSIONS_PER_DEVICE) {
        return dev.ws.send({ t: 'hangup', sid, reason: 'busy' });
      }
      sessions.set(sid, { a: dev, b: target });
      dev.sids.add(sid);
      target.sids.add(sid);
      target.ws.send({ t: 'ring', sid, from: dev.shortId });
      return dev.ws.send({ t: 'ringing', sid });
    }
    case 'relay': {
      const s = sessions.get(sid);
      if (!s || (s.a !== dev && s.b !== dev) || typeof m.d !== 'string') return;
      const other = s.a === dev ? s.b : s.a;
      return other.ws.send({ t: 'relay', sid, d: m.d });
    }
    case 'hangup': {
      const s = sessions.get(sid);
      if (s && (s.a === dev || s.b === dev)) endSession(sid, dev);
      return;
    }
  }
}

const server = createServer((req, res) => {
  if (req.url === '/health') {
    res.writeHead(200, { 'content-type': 'text/plain' });
    return res.end(`ok ${online.size} devices online\n`);
  }
  res.writeHead(404);
  res.end();
});

server.on('upgrade', (req, sock) => {
  const ip = (req.headers['x-forwarded-for']?.split(',')[0] ?? req.socket.remoteAddress ?? '').trim();
  const key = req.headers['sec-websocket-key'];
  const n = (connectionsPerIp.get(ip) ?? 0) + 1;
  if (!req.url?.startsWith('/beamx') || typeof key !== 'string' || n > MAX_CONNECTIONS_PER_IP) {
    sock.end('HTTP/1.1 400 Bad Request\r\n\r\n');
    return;
  }
  connectionsPerIp.set(ip, n);
  const accept = createHash('sha1').update(key + GUID).digest('base64');
  sock.write(
    'HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n' +
      `Sec-WebSocket-Accept: ${accept}\r\n\r\n`,
  );
  const ws = new Socket(sock, ip);
  const dev = new Device(ws);
  ws.onmessage = (raw) => handle(dev, raw);
  ws.onclose = () => {
    const left = (connectionsPerIp.get(ip) ?? 1) - 1;
    left > 0 ? connectionsPerIp.set(ip, left) : connectionsPerIp.delete(ip);
    for (const sid of [...dev.sids]) endSession(sid, dev);
    if (dev.shortId && online.get(dev.shortId) === dev) online.delete(dev.shortId);
  };
  // Hello must arrive quickly.
  setTimeout(() => !dev.id && ws.close(1008, 'timeout'), 10000).unref();
  allSockets.add(ws);
  ws.onclose = ((orig) => () => {
    allSockets.delete(ws);
    orig();
  })(ws.onclose);
});

// Keep-alive: drop connections that stop answering pings.
const allSockets = new Set();
setInterval(() => {
  for (const ws of allSockets) {
    if (!ws.alive) {
      ws.close(1001, 'ping timeout');
      continue;
    }
    ws.alive = false;
    ws.ping();
  }
}, 20000).unref();

if (process.argv[1] && import.meta.url.endsWith(process.argv[1].split('/').pop())) {
  server.listen(PORT, () => console.log(`BeamX relay listening on :${PORT}`));
}

export { server };
