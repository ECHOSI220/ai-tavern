import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { writeFile, mkdir, mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

// Resolve the exact runtime bundled with the project's pinned Wrangler.
const require = createRequire(import.meta.url);
const wranglerRequire = createRequire(require.resolve('wrangler/package.json'));
const { build } = wranglerRequire('esbuild');
const { Miniflare, Log, LogLevel, convertV4MiniflareOptions } = wranglerRequire('miniflare');
const built = await build({ entryPoints: ['test/runtime-entry.ts'], bundle: true, format: 'esm', write: false, external: ['cloudflare:workers'], target: 'esnext' });
const persistence = await mkdtemp(join(tmpdir(), 'tavern-runtime-test-'));
const options = convertV4MiniflareOptions({ name: 'runtime-test-worker', modules: true, script: built.outputFiles[0].text,
  compatibilityDate: '2026-09-03', log: new Log(LogLevel.ERROR),
  durableObjects: { GAME_ROOMS: { className: 'GameRoomDurableObject', useSQLite: true } },
  bindings: { PROTOCOL_VERSION: '3', MAX_MESSAGE_BYTES: '262144' },
});
options.resourcePersistencePath = persistence;
let mf = new Miniflare(options);
const roomId = crypto.randomUUID();
const sockets = [];
const json = async (path, body, headers = {}) => {
  const response = await mf.dispatchFetch(`http://test.local${path}`, { method: body === undefined ? 'GET' : 'POST', headers, ...(body === undefined ? {} : { body: JSON.stringify(body) }) });
  const data = await response.json();
  assert.equal(response.ok, true, JSON.stringify(data));
  return data;
};
async function connect(credentials, userId) {
  const query = new URLSearchParams({ playerSessionId: credentials.playerSessionId, reconnectToken: credentials.reconnectToken });
  const response = await mf.dispatchFetch(`http://test.local/socket?${query}`, { headers: { Upgrade: 'websocket', 'x-ai-tavern-user-id': userId } });
  assert.equal(response.status, 101);
  const socket = response.webSocket; sockets.push(socket);
  const events = []; const listeners = new Set();
  socket.addEventListener('message', (event) => { const message = JSON.parse(event.data); events.push(message); for (const notify of listeners) notify(); });
  socket.accept();
  const wait = (predicate, start = 0) => new Promise((resolve, reject) => {
    const check = () => { const found = events.slice(start).find(predicate); if (found) { clearTimeout(timer); listeners.delete(check); resolve(found); } };
    const timer = setTimeout(() => { listeners.delete(check); reject(new Error(`Timed out: ${events.slice(-3).map((e) => e.type)}`)); }, 9000);
    listeners.add(check); check();
  });
  await wait((e) => e.type === 'snapshot');
  return { socket, events, wait, credentials,
    async send(type, payload) {
      const start = events.length;
      const commandId = crypto.randomUUID();
      socket.send(JSON.stringify({ protocolVersion: 3, type, roomId, commandId, token: credentials.reconnectToken, sequenceNumber: 0, revision: 0, payload, visibility: 'public', recipientPlayerIds: [] }));
      // DO publishes a statePatch after committed commands. An error fails fast.
      const result = await wait((e) => (e.type === 'statePatch' && e.commandId === commandId) || e.type === 'error', start);
      assert.notEqual(result.type, 'error', JSON.stringify(result.payload));
      return result;
    },
  };
}
try {
  const longText = '世界🙂'.repeat(40000);
  const created = await json('/initialize', { roomId, roomCode: 'ABC234', roomName: '三人运行时验收', campaignId: 'test', rulePackId: 'simple_trpg', ownerUserId: 'owner', ownerName: '房主', maxPlayers: 3, allowPlayerPrivateChat: true, settings: {}, campaignSnapshot: { opening: '旧旅店的钟在午夜敲响。你们是受邀前来的调查员。', longText, secrets: ['GM_ONLY_CANARY'], locations: [{ id: 'hall' }] } });
  const joins = await Promise.all(['second', 'third'].map((userId) => json('/join', { userId, playerName: userId })));
  const invitationResponse = await mf.dispatchFetch('http://test.local/public-socket', {headers:{Upgrade:'websocket'}});
  assert.equal(invitationResponse.status,101);
  const invitationSocket=invitationResponse.webSocket; sockets.push(invitationSocket);
  const invitationEvents=[];
  invitationSocket.addEventListener('message',event=>invitationEvents.push(JSON.parse(event.data)));
  invitationSocket.accept();
  const clients = [];
  for (const [index, credentials] of [created.credentials, ...joins.map((j) => j.credentials)].entries()) clients.push(await connect(credentials, ['owner', 'second', 'third'][index]));
  const [owner, provider, other] = clients;
  for (const client of clients) {
    await client.send('selectCharacter', { character: { name: '调查员', hp: 99999 } });
    await client.send('playerReady', { ready: true });
  }
  await owner.send('hostRequested', { providerPlayerId: provider.credentials.playerId });
  await provider.send('hostAccepted', { modelId: 'test-tool-provider' });
  await owner.send('gameStarted', {});
  await owner.send('privateMessage', { content: 'PRIVATE_MESSAGE_CANARY', recipientPlayerIds: [provider.credentials.playerId] });
  await owner.send('privateRoll', { formula: '1d20', checkId: 'PRIVATE_ROLL_CANARY' });
  const state = await json('/state');
  for (const [index, client] of clients.entries()) await client.send('turnActionConfirm', { turnId: state.currentTurn.turnId, actionId: crypto.randomUUID(), content: `ACTION_CANARY_${index}`, secret: true });
  const request = await provider.wait((e) => e.type === 'aiRequest');
  assert.ok(request.payload.messages.length >= 2); assert.ok(request.payload.tools.length >= 4);
  assert.match(JSON.stringify(request), /GM_ONLY_CANARY/);
  const characterId = state.players[owner.credentials.playerId].character.id;
  await provider.send('aiResponse', { requestId: request.payload.requestId, response: { content: null, toolCalls: [{ id: 'move-1', type: 'function', function: { name: 'move_character', arguments: JSON.stringify({ characterId, locationId: 'hall' }) } }] } });
  const continuation = [...provider.events].reverse().find((e) => e.type === 'aiRequest');
  assert.notEqual(continuation.payload.requestId, request.payload.requestId);
  assert.ok(continuation.payload.messages.some((m) => m.role === 'tool'));
  await provider.send('aiResponse', { requestId: continuation.payload.requestId, response: { content: '你们来到大厅，门后响起脚步声。', toolCalls: [] } });
  const resolved = await json('/state');
  assert.equal(resolved.currentTurn.roundNumber, 2);
  assert.ok(invitationEvents.length>0);
  assert.ok(invitationEvents.every(event=>event.type==='publicRoomState'));
  assert.doesNotMatch(JSON.stringify(invitationEvents), /GM_ONLY_CANARY|PRIVATE_MESSAGE_CANARY|PRIVATE_ROLL_CANARY|ACTION_CANARY|sessionId|reconnectToken|permissions/);
  const beforePublicCommand=resolved.revision;
  invitationSocket.send(JSON.stringify({type:'gameStarted',payload:{}}));
  await new Promise(resolve=>setTimeout(resolve,100));
  assert.equal((await json('/state')).revision,beforePublicCommand);
  assert.equal(resolved.players[owner.credentials.playerId].character.hp, 20);
  assert.equal(resolved.session.characterLocations[characterId].locationId, 'hall');
  for (const client of [owner, other]) assert.doesNotMatch(JSON.stringify(client.events), /GM_ONLY_CANARY/);
  assert.doesNotMatch(JSON.stringify(other.events), /PRIVATE_MESSAGE_CANARY|PRIVATE_ROLL_CANARY|ACTION_CANARY_0|ACTION_CANARY_1/);
  const resumed = await connect(owner.credentials, 'owner');
  await resumed.send('playerChat', { content: '重连后继续' });
  assert.equal((await json('/state')).players[owner.credentials.playerId].connected, true);
  const finalPatch = await other.send('playerChat', { content: '第三位仍在房间' });
  // This is generated by the actual workerd runtime, then consumed by Dart tests.
  await mkdir('../shared/protocol/fixtures', { recursive: true });
  await writeFile('../shared/protocol/fixtures/public-room-snapshot.json', JSON.stringify(finalPatch.payload, null, 2) + '\n');
  for (const socket of sockets) try { socket.close(); } catch {}
  await mf.dispose();
  mf = new Miniflare(options);
  const restored = await json('/state');
  assert.equal(restored.currentTurn.roundNumber, 2);
  assert.equal(restored.campaignSnapshot.longText, longText);
  console.log('PASS workerd/SQLite DO: 3 sockets, private isolation, AI tool continuation, authoritative HP, round 2, replacement reconnect, large Unicode snapshot survives restart, Dart fixture');
} finally {
  for (const socket of sockets) try { socket.close(); } catch {}
  await mf.dispose();
  // Only the unique directory created by this test is removed.
  await rm(persistence, { recursive: true, force: true });
}
