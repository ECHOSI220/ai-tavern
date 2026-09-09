import { describe, expect, it } from "vitest";
import { envelope } from "../src/protocol/schema";
import { RoomEngine } from "../src/rooms/room-engine";
import type { RandomSource } from "../src/rooms/types";

const fixedRandom: RandomSource = { integer: () => 7 };
async function room(playerCount = 3) {
  const created = await RoomEngine.create({ roomId: crypto.randomUUID(), roomCode: "ABC234", roomName: "测试房间", campaignId: "campaign", rulePackId: "simple_trpg", ownerUserId: "user-owner", ownerName: "房主", maxPlayers: 6, allowPlayerPrivateChat: true, settings: {} });
  const engine = new RoomEngine(created.engine.state, fixedRandom);
  for (let index = 1; index < playerCount; index++) await engine.addPlayer(`user-${index}`, `玩家${index}`);
  return engine;
}
function command(engine: RoomEngine, type: Parameters<typeof envelope>[0], payload: Record<string, unknown>, id = crypto.randomUUID()) {
  return envelope(type, engine.state.roomId, payload, engine.state.revision, 0, { commandId: id });
}

describe("RoomEngine authoritative flow", () => {
  it('expires a silent host and resumes committed tools on another device without exposing context in the offer', async () => {
    const engine = await room(2); const [owner, next] = Object.keys(engine.state.players);
    engine.handle(owner!, command(engine, 'hostRequested', { providerPlayerId: owner }));
    engine.handle(owner!, command(engine, 'hostAccepted', { modelId: 'test' }));
    for (const id of Object.keys(engine.state.players)) engine.handle(id, command(engine, 'playerReady', { ready: true }));
    engine.handle(owner!, command(engine, 'gameStarted', {}));
    for (const id of Object.keys(engine.state.players)) engine.handle(id, command(engine, 'turnActionConfirm', { content: '调查' }));
    engine.finalizeTurnCountdown(Date.now() + 5_001);
    engine.handle(owner!, command(engine, 'aiResponse', { requestId: engine.state.aiHost.requestId, response: { toolCalls: [
      { id: 'clock-1', type: 'function', function: { name: 'advance_time', arguments: JSON.stringify({ minutes: 5 }) } },
    ] } }));
    const messages = structuredClone(engine.state.aiHost.messages);
    const previousRequest = engine.state.aiHost.requestId;
    const heartbeat = Date.parse(engine.state.aiHost.heartbeatAt!);
    expect(engine.expireHost(heartbeat + 59_999)).toBe(false);
    expect(engine.expireHost(heartbeat + 60_000)).toBe(true);
    expect(engine.state.aiHost.requestId).toBeUndefined();
    expect(engine.expireHost(heartbeat + 70_000)).toBe(false);
    const offer = engine.handle(owner!, command(engine, 'hostRequested', { providerPlayerId: next }));
    expect(offer.events[0]!.payload).not.toHaveProperty('messages');
    const accepted = engine.handle(next!, command(engine, 'hostAccepted', { modelId: 'next' }));
    expect(accepted.events.find(event => event.type === 'aiRequest')?.payload.messages).toEqual(messages);
    expect(engine.state.aiHost.requestId).not.toBe(previousRequest);
    expect(engine.state.campaignTime).toBe(5);
    expect(() => engine.handle(owner!, command(engine, 'aiResponse', { requestId: previousRequest, response: { content: '迟到的回复' } }))).toThrow();
    expect(engine.state.campaignTime).toBe(5);
  });
  it('retains private chat and dice across snapshots without exposing them to a third player', async () => {
    const engine = await room(3); const [owner, recipient, outsider] = Object.keys(engine.state.players);
    engine.handle(owner!, command(engine, 'privateMessage', { content: 'private-canary', recipientPlayerIds: [recipient] }));
    engine.handle(owner!, command(engine, 'privateRoll', { formula: '1d20', checkId: 'stable' }));
    engine.handle(owner!, command(engine, 'privateRoll', { formula: '99d9999', checkId: 'stable' }));
    expect(JSON.stringify(engine.snapshot(recipient!))).toContain('private-canary');
    expect(JSON.stringify(engine.snapshot(outsider!))).not.toContain('private-canary');
    const own = engine.snapshot(owner!) as { session: { chatHistory: unknown[]; immersionState: { privateMessages: unknown[] } } };
    expect(own.session.chatHistory).toHaveLength(0);
    expect(own.session.immersionState.privateMessages).toHaveLength(1);
  });

  it('does not let one player consume another player action id', async () => {
    const engine = await room(2); const ids = Object.keys(engine.state.players);
    for (const id of ids) engine.handle(id, command(engine, 'playerReady', { ready: true }));
    engine.handle(ids[0]!, command(engine, 'gameStarted', {}));
    for (const id of ids) engine.handle(id, command(engine, 'turnActionConfirm', { actionId: 'same-id', turnId: engine.state.currentTurn?.turnId, content: id }));
    expect(engine.state.currentTurn?.confirmedPlayerIds).toHaveLength(2);
  });

  it('rolls back state and dedup markers when the last tool in a batch fails', async () => {
    const engine = await room(1); const owner = engine.state.ownerPlayerId;
    engine.handle(owner, command(engine, 'selectCharacter', { character: { name: '调查员' } }));
    engine.handle(owner, command(engine, 'hostRequested', { providerPlayerId: owner }));
    engine.handle(owner, command(engine, 'hostAccepted', { modelId: 'test' }));
    engine.handle(owner, command(engine, 'playerReady', { ready: true }));
    engine.handle(owner, command(engine, 'gameStarted', {}));
    engine.handle(owner, command(engine, 'turnActionConfirm', { content: '调查' }));
    engine.finalizeTurnCountdown(Date.now() + 5_001);
    const before = structuredClone(engine.state);
    const id = engine.state.players[owner]!.character!.id;
    expect(() => engine.handle(owner, command(engine, 'aiResponse', { requestId: engine.state.aiHost.requestId, response: { toolCalls: [
      { id: 'damage', function: { name: 'damage_character', arguments: JSON.stringify({ characterId: id, amount: 5 }) } },
      { id: 'invalid', function: { name: 'run_shell', arguments: '{}' } },
    ] } }))).toThrow();
    expect(engine.state).toEqual(before);
  });
  it("rejects duplicate users and refuses to start before everyone is ready", async () => {
    const engine = await room(2); const [owner] = Object.keys(engine.state.players);
    await expect(engine.addPlayer("user-1", "重复玩家")).rejects.toMatchObject({ code: "ALREADY_JOINED" });
    expect(() => engine.handle(owner!, command(engine, "gameStarted", {}))).toThrow("仍有玩家未准备");
  });

  it("runs a three-player collect-confirm-resolve loop", async () => {
    const engine = await room(3); const ids = Object.keys(engine.state.players);
    for (const id of ids) engine.handle(id, command(engine, "playerReady", { ready: true }));
    engine.handle(ids[0]!, command(engine, "gameStarted", {}));
    expect(engine.state.currentTurn?.expectedPlayerIds).toHaveLength(3);
    for (const [index, id] of ids.entries()) engine.handle(id, command(engine, "turnActionConfirm", { turnId: engine.state.currentTurn?.turnId, actionId: crypto.randomUUID(), content: `行动${index}` }));
    expect(engine.state.currentTurn?.phase).toBe("collecting");
    expect(engine.state.currentTurn?.settlementDeadline).toBeTruthy();
    engine.finalizeTurnCountdown(Date.now() + 5_001);
    expect(engine.state.currentTurn?.phase).toBe("resolving");
    engine.handle(ids[0]!, command(engine, "turnResolved", { narration: "三人的行动得到了结算。" }));
    expect(engine.state.currentTurn?.roundNumber).toBe(2);
    expect((engine.state.session.chatHistory as unknown[])).toHaveLength(2);
  });

  it('keeps a five-second withdrawal window and resolves an all-pass turn once', async () => {
    const engine = await room(2); const [owner, provider] = Object.keys(engine.state.players);
    engine.handle(owner!, command(engine, 'hostRequested', { providerPlayerId: provider }));
    engine.handle(provider!, command(engine, 'hostAccepted', { modelId: 'test' }));
    for (const id of [owner!, provider!]) engine.handle(id, command(engine, 'playerReady', { ready: true }));
    engine.handle(owner!, command(engine, 'gameStarted', {}));
    const turnId = engine.state.currentTurn!.turnId;
    engine.handle(owner!, command(engine, 'turnActionConfirm', { turnId, content: '', isPass: true }));
    engine.handle(provider!, command(engine, 'turnActionConfirm', { turnId, content: '', isPass: true }));
    expect(engine.state.currentTurn?.phase).toBe('collecting');
    expect(engine.state.currentTurn?.settlementDeadline).toBeTruthy();

    engine.handle(owner!, command(engine, 'turnActionUnconfirm', { turnId }));
    expect(engine.state.currentTurn?.settlementDeadline).toBeUndefined();
    expect(engine.finalizeTurnCountdown(Date.now() + 10_000).changed).toBe(false);
    expect(engine.state.currentTurn?.phase).toBe('collecting');

    engine.handle(owner!, command(engine, 'turnActionConfirm', { turnId, content: '', isPass: true }));
    const settled = engine.finalizeTurnCountdown(Date.now() + 5_001);
    expect(settled.events.filter((event) => event.type === 'aiRequest')).toHaveLength(1);
    expect(engine.state.currentTurn?.phase).toBe('gmResponding');
    expect(Object.values(engine.state.currentTurn!.playerActions).every((action) => action.isPass)).toBe(true);
    expect(engine.finalizeTurnCountdown(Date.now() + 10_000).changed).toBe(false);
  });

  it("deduplicates an authoritative private dice check and hides it from others", async () => {
    const engine = await room(2); const [owner, other] = Object.keys(engine.state.players);
    const id = crypto.randomUUID(); const first = engine.handle(owner!, command(engine, "privateRoll", { formula: "2d20+3", checkId: "same-check" }, id));
    const repeated = engine.handle(owner!, command(engine, "privateRoll", { formula: "2d20+3", checkId: "same-check" }, id));
    expect(first.events[0]?.payload).toMatchObject({ rolls: [7, 7], total: 17 });
    expect(repeated.changed).toBe(false);
    expect(engine.canSee(first.events[0]!, owner!)).toBe(true);
    expect(engine.canSee(first.events[0]!, other!)).toBe(false);
  });

  it("persists state and rejects a forged player session", async () => {
    const engine = await room(1); const stored = structuredClone(engine.state);
    const restored = new RoomEngine(stored, fixedRandom);
    await expect(restored.authenticate("attacker", Object.values(stored.players)[0]!.sessionId, "wrong-token")).rejects.toMatchObject({ code: "INVALID_SESSION" });
    expect(restored.snapshot(stored.ownerPlayerId)).toHaveProperty("room.roomCode", "ABC234");
  });

  it("marks a disconnected AI provider unavailable without deleting the player", async () => {
    const engine = await room(2); const [owner, provider] = Object.keys(engine.state.players);
    engine.handle(owner!, command(engine, "hostRequested", { providerPlayerId: provider }));
    engine.handle(provider!, command(engine, "hostAccepted", { modelId: "local" }));
    engine.disconnect(provider!);
    expect(engine.state.aiHost.status).toBe("unavailable");
    expect(engine.state.players[provider!]?.connected).toBe(false);
  });

  it("keeps private messages and knowledge out of another player's network payload", async () => {
    const engine = await room(2); const [owner, other] = Object.keys(engine.state.players);
    const message = engine.handle(owner!, command(engine, "privateMessage", { content: "秘密", recipientPlayerIds: [owner] })).events[0]!;
    expect(engine.canSee(message, other!)).toBe(false);
    engine.handle(owner!, command(engine, "revealInformation", { playerId: owner, knowledgeId: "hidden-room", knowledge: { text: "墙后有门" } }));
    const otherSnapshot = engine.snapshot(other!) as { session: { privateKnowledge?: Record<string, unknown> } };
    expect(otherSnapshot.session.privateKnowledge).toBeUndefined();
  });

  it("deduplicates actionId even when the network commandId changes", async () => {
    const engine = await room(1); const [owner] = Object.keys(engine.state.players);
    engine.handle(owner!, command(engine, "playerReady", { ready: true })); engine.handle(owner!, command(engine, "gameStarted", {}));
    const actionId = crypto.randomUUID();
    const first = engine.handle(owner!, command(engine, "turnActionConfirm", { actionId, turnId: engine.state.currentTurn?.turnId, content: "调查" }));
    const duplicate = engine.handle(owner!, command(engine, "turnActionConfirm", { actionId, turnId: engine.state.currentTurn?.turnId, content: "重复调查" }));
    expect(first.changed).toBe(true); expect(duplicate.changed).toBe(false);
  });

  it("only delivers an AI resolution request to the accepted host", async () => {
    const engine = await room(2); const [owner, provider] = Object.keys(engine.state.players);
    engine.handle(owner!, command(engine, "hostRequested", { providerPlayerId: provider, providerType: "openai-compatible", modelId: "local-model" }));
    engine.handle(provider!, command(engine, "hostAccepted", { providerType: "openai-compatible", modelId: "local-model" }));
    engine.handle(owner!, command(engine, "playerReady", { ready: true }));
    engine.handle(provider!, command(engine, "playerReady", { ready: true }));
    engine.handle(owner!, command(engine, "gameStarted", {}));
    engine.handle(owner!, command(engine, "turnActionConfirm", { turnId: engine.state.currentTurn?.turnId, content: "前进" }));
    engine.handle(provider!, command(engine, "turnActionConfirm", { turnId: engine.state.currentTurn?.turnId, content: "观察" }));
    const events = engine.finalizeTurnCountdown(Date.now() + 5_001).events;
    const aiRequest = events.find((event) => event.type === "aiRequest");
    expect(aiRequest?.recipientPlayerIds).toEqual([provider]);
    expect(engine.canSee(aiRequest!, owner!)).toBe(false);
  });

  it('repairs a persisted resolving turn and replays an in-flight request on host reconnect', async () => {
    const engine = await room(2); const [owner, provider] = Object.keys(engine.state.players);
    engine.handle(owner!, command(engine, 'hostRequested', { providerPlayerId: provider }));
    engine.handle(provider!, command(engine, 'hostAccepted', { modelId: 'device-model' }));
    for (const id of [owner!, provider!]) engine.handle(id, command(engine, 'playerReady', { ready: true }));
    engine.handle(owner!, command(engine, 'gameStarted', {}));
    const turnId = engine.state.currentTurn!.turnId;
    for (const id of [owner!, provider!]) engine.handle(id, command(engine, 'turnActionConfirm', { turnId, content: '观察' }));
    engine.finalizeTurnCountdown(Date.now() + 5_001);
    const original = engine.state.aiHost.requestId!;
    expect(engine.pendingAIRequestFor(provider!)).not.toBeNull();

    // Simulate a legacy snapshot written after the socket/request was lost.
    delete engine.state.aiHost.requestId;
    delete engine.state.aiHost.messages;
    engine.state.currentTurn!.phase = 'resolving';
    const repaired = engine.recoverStalledTurn();
    expect(repaired.events[0]?.type).toBe('aiRequest');
    expect(engine.state.currentTurn?.phase).toBe('gmResponding');
    expect(engine.state.aiHost.requestId).toBeTruthy();
    expect(engine.state.aiHost.requestId).not.toBe(original);
    expect(engine.pendingAIRequestFor(provider!)).not.toBeNull();
  });

  it("validates AI tools on the server and preserves split character locations", async () => {
    const engine = await room(3); const [owner, provider, third] = Object.keys(engine.state.players);
    engine.state.campaignSnapshot = { locations: [{ id: 'basement' }, { id: 'roof' }, { id: 'lobby' }] };
    for (const id of [owner!, provider!, third!]) engine.handle(id, command(engine, 'selectCharacter', { character: { name: id } }));
    const a = engine.state.players[owner!]!.character!.id as string;
    const b = engine.state.players[provider!]!.character!.id as string;
    const c = engine.state.players[third!]!.character!.id as string;
    engine.handle(owner!, command(engine, "hostRequested", { providerPlayerId: provider }));
    engine.handle(provider!, command(engine, "hostAccepted", { modelId: "device-model" }));
    for (const id of [owner!, provider!, third!]) engine.handle(id, command(engine, "playerReady", { ready: true }));
    engine.handle(owner!, command(engine, "gameStarted", {}));
    for (const [id, content] of [[owner!, "去地下室"], [provider!, "去屋顶"], [third!, "留在大厅"]]) {
      engine.handle(id!, command(engine, "turnActionConfirm", { actionId: crypto.randomUUID(), turnId: engine.state.currentTurn?.turnId, content }));
    }
    engine.finalizeTurnCountdown(Date.now() + 5_001);
    const requestId = engine.state.aiHost.requestId!;
    engine.handle(provider!, command(engine, "aiResponse", { requestId, response: { narration: "三人分别抵达目标位置。", toolCalls: [
      { id: "move-a", function: { name: "move_character", arguments: JSON.stringify({ characterId: a, locationId: "basement" }) } },
      { id: "move-b", function: { name: "move_character", arguments: JSON.stringify({ characterId: b, locationId: "roof" }) } },
      { id: "move-c", function: { name: "move_character", arguments: JSON.stringify({ characterId: c, locationId: "lobby" }) } },
    ] } }));
    expect(engine.state.session.characterLocations).toMatchObject({ [a]: { locationId: "basement" }, [b]: { locationId: "roof" }, [c]: { locationId: "lobby" } });
    expect(() => engine.handle(provider!, command(engine, "aiResponse", { requestId: engine.state.aiHost.requestId, response: { narration: "非法修改", toolCalls: [{ id: "evil", name: "run_shell", arguments: {} }] } }))).toThrow();
  });
});
