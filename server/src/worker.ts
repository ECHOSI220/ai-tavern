import type { Env } from "./env";
import { protocolVersion } from "./env";
import { authenticate } from "./auth/supabase-auth";
import { GameRoomDurableObject } from "./durable/game-room";
import { createRoomRequestSchema, joinRoomRequestSchema } from "./protocol/schema";
import type { PlayerCredentials } from "./rooms/types";
import { SupabaseAdmin } from "./services/supabase";
import { errorResponse, ServerError } from "./utils/errors";
import { logError, logEvent } from "./utils/logging";
import { enforceRateLimit } from "./utils/rate-limit";

export { GameRoomDurableObject };

const corsHeaders = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization,content-type,x-client-version",
  "access-control-allow-methods": "GET,POST,PUT,DELETE,OPTIONS",
  "access-control-max-age": "86400",
};

function withCors(response: Response, requestId: string): Response {
  const headers = new Headers(response.headers);
  for (const [key, value] of Object.entries(corsHeaders)) headers.set(key, value);
  headers.set("x-request-id", requestId);
  headers.set("x-content-type-options", "nosniff");
  return new Response(response.body, { status: response.status, statusText: response.statusText, headers, webSocket: response.webSocket });
}

async function readJson(request: Request, limit: number): Promise<unknown> {
  const reader = request.body?.getReader();
  if (!reader) throw new ServerError('INVALID_JSON', '请求内容为空', 400);
  const chunks: Uint8Array[] = []; let length = 0;
  try {
    while (true) {
      const part = await reader.read(); if (part.done) break;
      length += part.value.byteLength;
      if (length > limit) { await reader.cancel(); throw new ServerError('BODY_TOO_LARGE', '请求体积超过限制', 413); }
      chunks.push(part.value);
    }
  } finally { reader.releaseLock(); }
  const bytes = new Uint8Array(length); let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
  const body = new TextDecoder().decode(bytes);
  try { return JSON.parse(body); } catch { throw new ServerError("INVALID_JSON", "请求不是有效 JSON", 400); }
}

function roomCode(): string {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  const bytes = new Uint8Array(6); crypto.getRandomValues(bytes);
  return [...bytes].map((value) => alphabet[value % alphabet.length]).join("");
}

function socketUrl(request: Request, roomId: string, credentials: PlayerCredentials): string {
  const url = new URL(request.url); url.protocol = url.protocol === "https:" ? "wss:" : "ws:";
  url.pathname = `/v1/rooms/${roomId}/socket`; url.search = new URLSearchParams({ playerSessionId: credentials.playerSessionId, reconnectToken: credentials.reconnectToken }).toString();
  return url.toString();
}

async function route(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  if (request.method === "GET" && (url.pathname === "/health" || url.pathname === "/v1/health")) return Response.json({ ok: true, environment: env.SERVER_ENV, version: env.SERVER_VERSION, protocolVersion: protocolVersion(env), time: new Date().toISOString() });
  if (request.method === "GET" && ["/version", "/v1/version"].includes(url.pathname)) return Response.json({ serverVersion: env.SERVER_VERSION, protocolVersion: protocolVersion(env), minimumClientProtocol: 3 });

  const invitation = /^\/v1\/public\/rooms\/([A-HJ-NP-Z2-9]{6})(\/socket)?$/.exec(url.pathname);
  const download = /^\/v1\/public\/shares\/([0-9a-f-]{36})\/download$/i.exec(url.pathname);
  if(request.method==='GET' && download){
    enforceRateLimit(`public-download:${request.headers.get('cf-connecting-ip')??'unknown'}`,30);
    const viewer=request.headers.has('authorization')?await authenticate(request,env):undefined;
    return Response.json(await new SupabaseAdmin(env).shareDownload(download[1]!,viewer?.id),{headers:{'cache-control':'no-store'}});
  }
  if (request.method==='GET' && invitation) {
    enforceRateLimit(`public-invite:${request.headers.get('cf-connecting-ip')??'unknown'}`,30);
    const room=await new SupabaseAdmin(env).findRoomByCode(invitation[1]!);
    if(!room) throw new ServerError('ROOM_NOT_FOUND','房间不存在或已结束',404);
    const headers=new Headers();
    if(request.headers.get('Upgrade')?.toLowerCase()==='websocket')headers.set('Upgrade','websocket');
    return env.GAME_ROOMS.get(env.GAME_ROOMS.idFromName(room.room_id)).fetch(new Request(`https://room.internal/${invitation[2]?'public-socket':'public-state'}`,{headers}));
  }

  const user = await authenticate(request, env);
  enforceRateLimit(`${user.id}:${url.pathname.endsWith('/socket') ? 'socket' : 'api'}`, url.pathname.endsWith('/socket') ? 20 : 60);
  const database = new SupabaseAdmin(env);

  if (request.method === "POST" && ["/rooms", "/v1/rooms"].includes(url.pathname)) {
    const input = createRoomRequestSchema.parse(await readJson(request, 1_000_000));
    const roomId = crypto.randomUUID(); const code = roomCode(); const id = env.GAME_ROOMS.idFromName(roomId); const stub = env.GAME_ROOMS.get(id);
    const init = await stub.fetch("https://room.internal/initialize", { method: "POST", body: JSON.stringify({ roomId, roomCode: code, roomName: input.roomName, campaignId: input.campaignId, rulePackId: input.rulePackId, ownerUserId: user.id, ownerName: input.playerName, maxPlayers: input.maxPlayers, allowPlayerPrivateChat: input.allowPlayerPrivateChat, settings: input.settings, ...(input.campaignSnapshot ? { campaignSnapshot: input.campaignSnapshot } : {}) }) });
    if (!init.ok) throw await internalError(init);
    const result = await init.json<{ credentials: PlayerCredentials; revision: number }>();
    const state = await (await stub.fetch("https://room.internal/state")).json<import("./rooms/types").RoomState>();
    try { await database.createRoom(state); } catch (error) {
      await stub.fetch('https://room.internal/close', { method: 'POST', headers: { 'x-ai-tavern-user-id': user.id } }).catch(() => {});
      logError("room_metadata_create_failed", { roomId }); throw error;
    }
    logEvent("room_created", { roomId, ownerUserId: user.id });
    return Response.json({ roomId, roomCode: code, ...result.credentials, socketUrl: socketUrl(request, roomId, result.credentials), revision: result.revision }, { status: 201 });
  }

  if (request.method === "POST" && ["/rooms/join", "/v1/rooms/join"].includes(url.pathname)) {
    const input = joinRoomRequestSchema.parse(await readJson(request, 16_384));
    const metadata = await database.findRoomByCode(input.roomCode); if (!metadata) throw new ServerError("ROOM_NOT_FOUND", "未找到可加入的房间", 404);
    const stub = env.GAME_ROOMS.get(env.GAME_ROOMS.idFromName(metadata.room_id));
    const joined = await stub.fetch("https://room.internal/join", { method: "POST", body: JSON.stringify({ userId: user.id, playerName: input.playerName }) });
    if (!joined.ok) throw await internalError(joined);
    const result = await joined.json<{ credentials: PlayerCredentials; revision: number }>();
    return Response.json({ roomId: metadata.room_id, roomCode: metadata.room_code, ...result.credentials, socketUrl: socketUrl(request, metadata.room_id, result.credentials), revision: result.revision });
  }

  const socketMatch = /^\/v1\/rooms\/([0-9a-f-]{36})\/socket$/i.exec(url.pathname);
  if (request.method === "GET" && socketMatch) {
    const roomId = socketMatch[1]!; const headers = new Headers(request.headers);
    headers.delete("x-ai-tavern-user-id"); headers.set("x-ai-tavern-user-id", user.id);
    const target = new URL("https://room.internal/socket"); target.search = url.search;
    return env.GAME_ROOMS.get(env.GAME_ROOMS.idFromName(roomId)).fetch(new Request(target, { method: "GET", headers }));
  }

  const lifecycleMatch = /^\/v1\/rooms\/([0-9a-f-]{36})\/(checkpoint|close)$/i.exec(url.pathname);
  if (request.method === "POST" && lifecycleMatch) {
    const roomId = lifecycleMatch[1]!; const action = lifecycleMatch[2]!.toLowerCase();
    const stub = env.GAME_ROOMS.get(env.GAME_ROOMS.idFromName(roomId));
    const result = await stub.fetch('https://room.internal/checkpoint', { method: "POST", headers: { "x-ai-tavern-user-id": user.id } });
    if (!result.ok) throw await internalError(result);
    let state = await result.json<import("./rooms/types").RoomState>();
    await database.checkpoint(state);
    if (action === 'close') {
      const closed = await stub.fetch('https://room.internal/close', { method: 'POST', headers: { 'x-ai-tavern-user-id': user.id, 'x-expected-revision': String(state.revision) } });
      if (!closed.ok) throw await internalError(closed);
      state = await closed.json<import('./rooms/types').RoomState>();
      await database.checkpoint(state);
    }
    await database.updateRoom(state);
    return Response.json({ ok: true, roomId, revision: state.revision, status: state.status });
  }

  if (request.method === "GET" && url.pathname === "/v1/campaigns") return Response.json({ campaigns: await database.listCampaigns(user.id) });
  const campaignMatch = /^\/v1\/campaigns\/([0-9a-f-]{36})$/i.exec(url.pathname);
  if (request.method === 'GET' && campaignMatch) {
    const campaign = await database.getCampaign(user.id, campaignMatch[1]!);
    if (!campaign) throw new ServerError('SAVE_NOT_FOUND', '存档不存在或无权访问', 404);
    return Response.json({ campaign });
  }
  if (request.method === "POST" && url.pathname === "/v1/campaigns") {
    const input = await readJson(request, 2_000_000); if (!input || typeof input !== "object" || Array.isArray(input)) throw new ServerError("INVALID_INPUT", "存档数据格式错误", 400);
    return Response.json({ campaign: await database.saveCampaign(user.id, input as Record<string, unknown>) }, { status: 201 });
  }
  throw new ServerError("NOT_FOUND", "接口不存在", 404);
}

async function internalError(response: Response): Promise<ServerError> {
  const data: { error?: { code?: string; message?: string; recoverable?: boolean } } = await response.json<{ error?: { code?: string; message?: string; recoverable?: boolean } }>().catch(() => ({}));
  return new ServerError(data.error?.code ?? "ROOM_SERVICE_ERROR", data.error?.message ?? "房间服务暂时不可用", response.status, data.error?.recoverable ?? false);
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const requestId = request.headers.get("x-request-id")?.slice(0, 80) || crypto.randomUUID();
    if (request.method === "OPTIONS") return withCors(new Response(null, { status: 204 }), requestId);
    try { return withCors(await route(request, env), requestId); }
    catch (error) {
      logError("request_failed", { requestId, method: request.method, errorCode: error instanceof ServerError ? error.code : 'REQUEST_REJECTED' });
      return withCors(errorResponse(error, requestId), requestId);
    }
  },
} satisfies ExportedHandler<Env>;
