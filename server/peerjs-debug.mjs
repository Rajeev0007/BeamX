const rand = () => [...crypto.getRandomValues(new Uint8Array(12))].map((b) => b.toString(16).padStart(2, '0')).join('');
const nine = () => String(Math.floor(Math.random() * 1e9)).padStart(9, '0');
const wait = (ms) => new Promise((r) => setTimeout(r, ms));
function peer(tag, id) {
  const ws = new WebSocket(`wss://0.peerjs.com/peerjs?key=peerjs&id=${id}&token=${rand()}&version=1.5.4`);
  ws.onmessage = (e) => { const m = JSON.parse(e.data); const c = m.payload?.candidate?.candidate; console.log(`${tag} <-`, m.type, c ? `len=${c.length} head=${c.slice(0,30)}` : JSON.stringify(m).slice(0,100)); };
  ws.onclose = (e) => console.log(`${tag} closed`, e.code, e.reason);
  setInterval(() => ws.readyState === 1 && ws.send('{"type":"HEARTBEAT"}'), 5000).unref();
  return new Promise((r) => (ws.onopen = () => r(ws)));
}
const cand = (dst, data, sid) => JSON.stringify({ type: 'CANDIDATE', dst,
  payload: { candidate: { candidate: data, sdpMid: '0', sdpMLineIndex: 0 }, type: 'data', connectionId: 'dc_' + sid } });
for (const prefix of ['beamx1-', 'beamx1']) {
  console.log('=== prefix', prefix);
  const aId = prefix + nine(), bId = prefix + nine();
  const a = await peer('A', aId), b = await peer('B', bId);
  await wait(3000);
  for (const n of [100, 4000, 16000, 60000]) {
    console.log('-> send', n);
    if (a.readyState === 1) a.send(cand(bId, '{"t":"x","d":"' + 'y'.repeat(n) + '"}', 'a1b2c3d4e5f60718'));
    await wait(2500);
  }
  console.log('-> to offline');
  if (a.readyState === 1) a.send(cand(prefix + '000000001', 'hi', 'ffffffffffffffff'));
  await wait(9000);
  a.close(); b.close();
  await wait(1000);
}
process.exit(0);
