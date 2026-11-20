const rand = () => [...crypto.getRandomValues(new Uint8Array(12))].map((b) => b.toString(16).padStart(2, '0')).join('');
const nine = () => String(Math.floor(Math.random() * 1e9)).padStart(9, '0');
const wait = (ms) => new Promise((r) => setTimeout(r, ms));
function peer(tag, id, headers) {
  const url = `wss://0.peerjs.com/peerjs?key=peerjs&id=${id}&token=${rand()}&version=1.5.4`;
  const ws = headers ? new WebSocket(url, { headers }) : new WebSocket(url);
  ws.onmessage = (e) => console.log(`${tag} <-`, String(e.data).slice(0, 140));
  ws.onclose = (e) => console.log(`${tag} closed`, e.code, e.reason);
  setInterval(() => ws.readyState === 1 && ws.send('{"type":"HEARTBEAT"}'), 5000).unref();
  return new Promise((r) => (ws.onopen = () => r(ws)));
}
const offer = (dst) => ({
  type: 'OFFER', dst,
  payload: { sdp: { type: 'offer', sdp: 'v=0\r\n' }, type: 'data', connectionId: 'dc_' + rand().slice(0, 10),
    label: 'dc_x', serialization: 'binary', reliable: true, metadata: { beamx: 1 }, browser: 'chrome' },
});
for (const [name, headers] of [
  ['no-origin', null],
  ['origin', { Origin: 'https://peerjs.com', 'User-Agent': 'Mozilla/5.0 Chrome/130' }],
]) {
  console.log('=== variant', name);
  const aId = `p${nine()}${rand().slice(0, 4)}`, bId = `p${nine()}${rand().slice(0, 4)}`;
  const a = await peer('A', aId, headers), b = await peer('B', bId, headers);
  await wait(6000);
  console.log('-> A sends OFFER');
  a.send(JSON.stringify(offer(bId)));
  await wait(4000);
  console.log('-> A sends CANDIDATE');
  if (a.readyState === 1) a.send(JSON.stringify({ type: 'CANDIDATE', dst: bId, payload: { candidate: { candidate: 'x', sdpMid: '0', sdpMLineIndex: 0 }, type: 'data', connectionId: 'dc_1' } }));
  await wait(4000);
  a.close(); b.close();
  await wait(1000);
}
process.exit(0);
