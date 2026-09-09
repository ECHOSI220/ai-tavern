import { DurableObject } from "cloudflare:workers";
import type { Env } from "../env";
import { maxMessageBytes, protocolVersion } from "../env";
import { parseEnvelope, envelope, type NetworkEnvelope } from "../protocol/schema";
import { RoomEngine } from "../rooms/room-engine";
import type { PlayerCredentials, RoomState } from "../rooms/types";
import { errorResponse, ServerError } from "../utils/errors";
import { logEvent } from "../utils/logging";
import { publicRoom } from '../rooms/public-room';

interface SocketAttachment { playerId: string; userId: string; sessionId: string; retired?: boolean; publicViewer?: boolean }

export class GameRoomDurableObject extends DurableObject<Env> {
  private engine: RoomEngine | undefined;
  private readonly socketRate = new Map<string, number[]>();
  private pending: Promise<unknown> = Promise.resolve();
  private lastPublicPayload = '';
  // Awaiting crypto/auth/storage must not let two commands mutate one state.
  private serial<T>(action: () => Promise<T>): Promise<T> {
    const next = this.pending.then(action);
    this.pending = next.catch(() => {});
    return next;
  }
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    this.ctx.setWebSocketAutoResponse(new WebSocketRequestResponsePair("__ping__", "__pong__"));
    this.ctx.storage.sql.exec('CREATE TABLE IF NOT EXISTS room_state_chunks (position INTEGER PRIMARY KEY, content TEXT NOT NULL)');
  }

  private async readState(): Promise<RoomState | undefined> {
    const chunks = this.ctx.storage.sql.exec<{ content: string }>('SELECT content FROM room_state_chunks ORDER BY position').toArray();
    if (chunks.length) return JSON.parse(chunks.map((row) => row.content).join('')) as RoomState;
    // Keep the initial development format readable during migration.
    return this.ctx.storage.get<RoomState>('roomState');
  }

  private async load(): Promise<RoomEngine> {
    if (this.engine) return this.engine;
    const state = await this.readState();
    if (!state) throw new ServerError("ROOM_NOT_FOUND", "房间不存在或已关闭", 404);
    this.engine = new RoomEngine(state);
    // Repair snapshots written by older deployments (or a worker restart)
    // before exposing them to a client.  This also causes save() to install a
    // heartbeat alarm for the recovered request.
    const recovery = this.engine.recoverStalledTurn();
    if (recovery.changed) await this.save();
    return this.engine;
  }
  private async save(): Promise<void> {
    if (!this.engine) return;
    const json = JSON.stringify(this.engine.state);
    // Persist atomically in bounded SQL rows, not one oversized KV value.
    this.ctx.storage.transactionSync(() => {
      this.ctx.storage.sql.exec('DELETE FROM room_state_chunks');
      for (let offset = 0, position = 0; offset < json.length; position++) {
        let end = Math.min(offset + 16_384, json.length);
        const last = json.charCodeAt(end - 1);
        if (end < json.length && last >= 0xd800 && last <= 0xdbff) end--;
        this.ctx.storage.sql.exec('INSERT INTO room_state_chunks(position, content) VALUES (?, ?)', position, json.slice(offset, end));
        offset = end;
      }
    });
    const alarms: number[] = [];
    if (this.engine.aiDeadline !== undefined) alarms.push(this.engine.aiDeadline);
    if (this.engine.state.aiHost.status === 'active' && this.engine.state.status !== 'closed') {
      const heartbeat = Date.parse(this.engine.state.aiHost.heartbeatAt ?? '');
      alarms.push((Number.isFinite(heartbeat) ? heartbeat : Date.now()) + 60_000);
    }
    const settlement = Date.parse(this.engine.state.currentTurn?.settlementDeadline ?? '');
    if (Number.isFinite(settlement)) alarms.push(settlement);
    if (alarms.length) {
      await this.ctx.storage.setAlarm(Math.max(Date.now() + 100, Math.min(...alarms)));
    } else {
      await this.ctx.storage.deleteAlarm();
    }
  }

  async alarm(): Promise<void> {
    await this.serial(async () => {
      try {
        const engine = await this.load();
        const aiExpired = engine.expireAIRequest();
        const hostExpired = engine.expireHost();
        const countdown = engine.finalizeTurnCountdown();
        await this.save();
        for (const event of countdown.events) this.broadcast(event);
        for (const event of aiExpired.events) this.broadcast(event);
        if (hostExpired || countdown.changed || aiExpired.changed) this.sendStatePatches(countdown.changed || aiExpired.changed);
      } catch (error) {
        this.engine = undefined;
        throw error;
      }
    });
  }

  async fetch(request: Request): Promise<Response> {
    return this.serial(() => this.handleFetch(request));
  }

  private async handleFetch(request: Request): Promise<Response> {
    try {
      const url = new URL(request.url);
      if (request.method === "POST" && url.pathname === "/initialize") {
        if (await this.readState()) throw new ServerError("ROOM_EXISTS", "房间已经初始化", 409);
        const input = await request.json<Parameters<typeof RoomEngine.create>[0]>();
        const created = await RoomEngine.create(input); this.engine = created.engine; await this.save();
        return Response.json({ credentials: created.credentials, revision: created.engine.state.revision });
      }
      if (request.method === "POST" && url.pathname === "/join") {
        const engine = await this.load(); const input = await request.json<{ userId: string; playerName: string }>();
        const credentials = await engine.addPlayer(input.userId, input.playerName); await this.save();
        this.sendPublicState();
        return Response.json({ credentials, revision: engine.state.revision });
      }
      if (request.method === "GET" && url.pathname === "/socket") return this.connectSocket(request);
      if (request.method === 'GET' && url.pathname === '/public-state') return Response.json(publicRoom((await this.load()).state));
      if (request.method === 'GET' && url.pathname === '/public-socket') return this.connectPublicSocket(request);
      if (request.method === "GET" && url.pathname === "/state") return Response.json((await this.load()).state);
      if (request.method === "POST" && url.pathname === "/checkpoint") {
        const engine = await this.load();
        if (request.headers.get("x-ai-tavern-user-id") !== engine.state.ownerUserId) throw new ServerError("OWNER_REQUIRED", "仅房主可以保存房间", 403);
        return Response.json(engine.state);
      }
      if (request.method === "POST" && url.pathname === "/close") {
        const engine = await this.load();
        if (request.headers.get("x-ai-tavern-user-id") !== engine.state.ownerUserId) throw new ServerError("OWNER_REQUIRED", "仅房主可以关闭房间", 403);
        const expected = request.headers.get('x-expected-revision');
        if (expected !== null && Number(expected) !== engine.state.revision) throw new ServerError('REVISION_CONFLICT', '房间在保存期间有新行动，请重试关闭', 409);
        engine.close(); await this.save();
        for (const socket of this.ctx.getWebSockets()) socket.close(1000, "room_closed");
        return Response.json(engine.state);
      }
      return errorResponse(new ServerError("NOT_FOUND", "接口不存在", 404), crypto.randomUUID());
    } catch (error) { this.engine = undefined; return errorResponse(error, crypto.randomUUID()); }
  }

  private async connectPublicSocket(request: Request): Promise<Response> {
    if (request.headers.get('Upgrade')?.toLowerCase() !== 'websocket') throw new ServerError('UPGRADE_REQUIRED','需要 WebSocket',426);
    const engine = await this.load();
    if (['closed','finished'].includes(engine.state.status)) throw new ServerError('ROOM_CLOSED','房间已结束',410);
    if (this.ctx.getWebSockets('public-viewer').length >= 100) throw new ServerError('VIEWERS_FULL','邀请页访问人数过多，请稍后重试',429);
    const [client,server] = Object.values(new WebSocketPair()) as [WebSocket,WebSocket];
    server.serializeAttachment({playerId:'',userId:'',sessionId:crypto.randomUUID(),publicViewer:true} satisfies SocketAttachment);
    this.ctx.acceptWebSocket(server,['public-viewer']);
    server.send(JSON.stringify({type:'publicRoomState',room:publicRoom(engine.state)}));
    return new Response(null,{status:101,webSocket:client});
  }

  private sendPublicState(): void {
    if (!this.engine) return;
    const payload=JSON.stringify({type:'publicRoomState',room:publicRoom(this.engine.state)});
    if (payload===this.lastPublicPayload) return;
    this.lastPublicPayload=payload;
    for(const socket of this.ctx.getWebSockets('public-viewer')) try {socket.send(payload);} catch {/* no game state mutation */}
  }

  private async connectSocket(request: Request): Promise<Response> {
    if (request.headers.get("Upgrade")?.toLowerCase() !== "websocket") throw new ServerError("UPGRADE_REQUIRED", "此接口需要 WebSocket", 426);
    const url = new URL(request.url); const userId = request.headers.get("x-ai-tavern-user-id") ?? "";
    const sessionId = url.searchParams.get("playerSessionId") ?? ""; const token = url.searchParams.get("reconnectToken") ?? "";
    const engine = await this.load(); const player = await engine.authenticate(userId, sessionId, token);
    // Reconnecting with the same authenticated provider identity is enough to
    // resume hosting.  Older builds left the room in `unavailable` after a
    // transient socket drop and never showed the provider another accept
    // prompt, which made the turn look permanently stuck.
    if (engine.state.aiHost.providerPlayerId === player.playerId &&
        engine.state.aiHost.status === 'unavailable') {
      engine.state.aiHost.status = 'active';
      engine.state.aiHost.heartbeatAt = new Date().toISOString();
      engine.state.revision++;
      engine.state.updatedAt = new Date().toISOString();
      engine.state.lastActivityAt = engine.state.updatedAt;
    }
    engine.recoverStalledTurn();
    const snapshot = envelope("snapshot", engine.state.roomId, { snapshot: engine.snapshot(player.playerId), sessionToken: token, playerId: player.playerId, playerSessionId: sessionId }, engine.state.revision, ++engine.state.sequenceNumber, { visibility: "player", recipientPlayerIds: [player.playerId] });
    const joined = envelope("playerJoined", engine.state.roomId, { playerId: player.playerId, displayName: player.displayName, reconnected: true }, engine.state.revision, ++engine.state.sequenceNumber);
    // Persist the authenticated connection heartbeat as well as any recovery.
    await this.save();
    // Retire the replaced socket before its asynchronous close callback runs.
    for (const old of this.ctx.getWebSockets(player.playerId)) {
      const attachment = old.deserializeAttachment() as SocketAttachment | null;
      if (attachment) old.serializeAttachment({ ...attachment, retired: true });
      try { old.close(1000, 'connection_replaced'); } catch { /* already closed */ }
    }
    const pair = new WebSocketPair(); const [client, server] = Object.values(pair) as [WebSocket, WebSocket];
    const attachment: SocketAttachment = { playerId: player.playerId, userId, sessionId }; server.serializeAttachment(attachment);
    this.ctx.acceptWebSocket(server, [player.playerId]);
    server.send(JSON.stringify(snapshot));
    // A host can reconnect after the request was sent while its socket was
    // down.  The request id is kept stable so a delayed response is still
    // accepted, while the provider gets the full request again here.
    const pendingAI = engine.pendingAIRequestFor(player.playerId);
    if (pendingAI) server.send(JSON.stringify(pendingAI));
    this.broadcast(joined);
    this.sendStatePatches(false);
    return new Response(null, { status: 101, webSocket: client });
  }

  async webSocketMessage(socket: WebSocket, message: string | ArrayBuffer): Promise<void> {
    return this.serial(() => this.handleSocketMessage(socket, message));
  }
  private async handleSocketMessage(socket: WebSocket, message: string | ArrayBuffer): Promise<void> {
    const attachment = socket.deserializeAttachment() as SocketAttachment | null;
    if (!attachment) { socket.close(1008, "missing_session"); return; }
    if (attachment.retired) return;
    // Public sockets are read-only and can never reach RoomEngine.handle.
    if (attachment.publicViewer) { socket.close(1008,'read_only_invitation'); return; }
    try {
      const timestamp = Date.now();
      const rate = (this.socketRate.get(attachment.sessionId) ?? []).filter((value) => value > timestamp - 10_000);
      if (rate.length >= 40) throw new ServerError("SOCKET_RATE_LIMITED", "消息发送过于频繁", 429);
      rate.push(timestamp); this.socketRate.set(attachment.sessionId, rate);
      const raw = typeof message === "string" ? message : new TextDecoder().decode(message);
      if (new TextEncoder().encode(raw).byteLength > maxMessageBytes(this.env)) throw new ServerError("MESSAGE_TOO_LARGE", "消息体积超过限制", 413);
      const command = parseEnvelope(raw, protocolVersion(this.env));
      const engine = await this.load();
      if (command.roomId && command.roomId !== engine.state.roomId) throw new ServerError("WRONG_ROOM", "消息房间不匹配", 400);
      const previous = structuredClone(engine.state);
      const result = engine.handle(attachment.playerId, command);
      try { if (result.changed) await this.save(); }
      catch (error) { this.engine = new RoomEngine(previous); throw error; }
      for (const event of result.events) this.broadcast(event);
      if (result.changed) this.sendStatePatches(true, command.commandId);
    } catch (error) {
      const engine = this.engine; const status = error instanceof ServerError ? error.code : "INTERNAL_ERROR";
      logEvent("socket_command_failed", { status, playerId: attachment.playerId });
      socket.send(JSON.stringify(envelope("error", engine?.state.roomId ?? crypto.randomUUID(), { code: status, message: error instanceof ServerError ? error.message : "服务器处理消息失败" }, engine?.state.revision ?? 0, engine?.state.sequenceNumber ?? 0, { visibility: "player", recipientPlayerIds: [attachment.playerId] })));
    }
  }

  async webSocketClose(socket: WebSocket): Promise<void> { await this.serial(() => this.onDisconnect(socket)); }
  async webSocketError(socket: WebSocket): Promise<void> { await this.serial(() => this.onDisconnect(socket)); }
  private async onDisconnect(socket: WebSocket): Promise<void> {
    const attachment = socket.deserializeAttachment() as SocketAttachment | null;
    if (!attachment || attachment.retired || attachment.publicViewer) return;
    socket.serializeAttachment({ ...attachment, retired: true });
    this.socketRate.delete(attachment.sessionId);
    try {
      const engine = await this.load();
      if (!engine.state.players[attachment.playerId]?.connected) return;
      engine.disconnect(attachment.playerId);
      const event = envelope("playerLeft", engine.state.roomId, { playerId: attachment.playerId, aiProviderOffline: engine.state.aiHost.status === "unavailable" }, engine.state.revision, ++engine.state.sequenceNumber);
      await this.save(); this.broadcast(event); this.sendStatePatches(false);
    } catch { this.engine = undefined; }
  }
  private broadcast(event: NetworkEnvelope): void {
    if (!this.engine) return;
    const encoded = JSON.stringify(event);
    for (const socket of this.ctx.getWebSockets()) { const attachment = socket.deserializeAttachment() as SocketAttachment | null; if (attachment && !attachment.retired && !attachment.publicViewer && this.engine.canSee(event, attachment.playerId)) try { socket.send(encoded); } catch { /* close callback handles state */ } }
  }
  private sendStatePatches(includeSession: boolean, commandId?: string | null): void {
    if (!this.engine) return;
    this.sendPublicState();
    for (const socket of this.ctx.getWebSockets()) {
      const attachment = socket.deserializeAttachment() as SocketAttachment | null; if (!attachment || attachment.retired || attachment.publicViewer) continue;
      if (!this.engine.state.players[attachment.playerId]) { socket.close(1008, 'removed_from_room'); continue; }
      const snapshot = this.engine.snapshot(attachment.playerId) as { room: Record<string, unknown>; session: Record<string, unknown> };
      const payload: Record<string, unknown> = { room: snapshot.room };
      if (includeSession) payload.session = snapshot.session;
      const patch = envelope("statePatch", this.engine.state.roomId, payload, this.engine.state.revision, this.engine.state.sequenceNumber, { commandId: commandId ?? null, visibility: "player", recipientPlayerIds: [attachment.playerId] });
      try { socket.send(JSON.stringify(patch)); } catch { /* disconnect callback handles state */ }
    }
  }
}
