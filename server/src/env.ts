import type { GameRoomDurableObject } from "./durable/game-room";

export interface Env {
  GAME_ROOMS: DurableObjectNamespace<GameRoomDurableObject>;
  SUPABASE_URL: string;
  SUPABASE_ANON_KEY: string;
  SUPABASE_SERVICE_ROLE_KEY: string;
  SERVER_ENV: string;
  SERVER_VERSION: string;
  PROTOCOL_VERSION: string;
  MAX_MESSAGE_BYTES: string;
  RECONNECT_GRACE_SECONDS: string;
}

export function protocolVersion(env: Env): number {
  const value = Number.parseInt(env.PROTOCOL_VERSION || "3", 10);
  return Number.isFinite(value) ? value : 3;
}

export function maxMessageBytes(env: Env): number {
  const value = Number.parseInt(env.MAX_MESSAGE_BYTES || "65536", 10);
  return Number.isFinite(value) ? Math.max(4096, value) : 65536;
}
