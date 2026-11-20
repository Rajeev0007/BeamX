const rand = () => [...crypto.getRandomValues(new Uint8Array(12))].map((b) => b.toString(16).padStart(2, '0')).join('');
const nine = () => String(Math.floor(Math.random() * 1e9)).padStart(9, '0');
function peer(id, host) {
  const ws = new WebSocket(`wss://${host}/peerjs?key=peerjs&id=${id}&token=${rand()}&version=1.5.4`);
  ws.onmessage = (e) => console.log(`[${id.slice(-4)}] <-`, String(e.data).slice(0, 160));
  ws.onclose = (e) => console.log(`[${id.slice(-4)}] closed`, e.code, e.reason);
  setInterval(() => ws.readyState === 1 && ws.send('{"type":"HEARTBEAT"}'), 5000).unref();
  return new Promise((r) => (ws.onopen = () => r(ws)));
}
const wait = (ms) => new Promise((r) => setTimeout(r, ms));
for (const host of ['0.peerjs.com']) {
  console.log('=== host', host);
  const aId = `beamx1-${nine()}`, bId = `beamx1-${nine()}`;
  const a = await peer(aId, host), b = await peer(bId, host);
  await wait(2000);
  const variants = [
    ['OFFER small', { type: 'OFFER', dst: bId, payload: { sdp: { type: 'offer', sdp: 'v=0' }, type: 'media', connectionId: 'mc_1' } }],
    ['CANDIDATE small', { type: 'CANDIDATE', dst: bId, payload: { beamx: 1, k: 'dial', sid: '0123456789abcdef' } }],
    ['CANDIDATE with src', { type: 'CANDIDATE', src: aId, dst: bId, payload: { beamx: 1, k: 'x' } }],
    ['CANDIDATE 4KB', { type: 'CANDIDATE', dst: bId, payload: { beamx: 1, d: 'y'.repeat(4000) } }],
    ['ANSWER small', { type: 'ANSWER', dst: bId, payload: { beamx: 1 } }],
  ];
  for (const [name, m] of variants) {
    console.log('->', name);
    a.send(JSON.stringify(m));
    await wait(3000);
  }
  a.close(); b.close();
}
await wait(1000);
process.exit(0);
