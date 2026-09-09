import type { NetworkEnvelope } from "../protocol/schema";

export type RoomStatus = "lobby" | "starting" | "playing" | "paused" | "finished" | "closed";

export interface PlayerState {
  playerId: string;
  userId: string;
  sessionId: string;
  reconnectTokenHash: string;
  displayName: string;
  role: "owner" | "player" | "spectator";
  ready: boolean;
  connected: boolean;
  joinedAt: string;
  lastSeenAt: string;
  character?: Record<string, unknown>;
  capability?: Record<string, unknown>;
  permissions: string[];
}

export interface TurnAction {
  actionId: string;
  turnId: string;
  playerId: string;
  playerDisplayName: string;
  characterId: string;
  characterName: string;
  content: string;
  confirmed: boolean;
  isPass: boolean;
  submittedAt: string;
  confirmedAt: string;
  metadata: Record<string, unknown>;
}

export interface TurnState {
  turnId: string;
  roundNumber: number;
  phase: "collecting" | "resolving" | "gmResponding" | "applyingTools" | "completed" | "cancelled";
  status: "active" | "resolved" | "cancelled";
  mode: "freeformGroup" | "combatInitiative";
  startedAt: string;
  resolvedAt?: string;
  playerActions: Record<string, TurnAction>;
  confirmedPlayerIds: string[];
  expectedPlayerIds: string[];
  resolutionRequestId?: string;
  settlementDeadline?: string;
}

export interface AIHostState {
  status: "none" | "offered" | "active" | "unavailable";
  providerPlayerId?: string;
  requestedByPlayerId?: string;
  providerType?: string;
  modelId?: string;
  requestId?: string;
  messages?: Record<string, unknown>[];
  toolRounds?: number;
  heartbeatAt?: string;
}

export interface RoomState {
  roomId: string;
  roomCode: string;
  roomName: string;
  campaignId: string;
  rulePackId: string;
  ownerPlayerId: string;
  ownerUserId: string;
  maxPlayers: number;
  status: RoomStatus;
  createdAt: string;
  startedAt?: string;
  lastActivityAt: string;
  updatedAt: string;
  revision: number;
  sequenceNumber: number;
  allowPlayerPrivateChat: boolean;
  settings: Record<string, unknown>;
  spectators: Record<string, PlayerState>;
  snapshotVersion: number;
  gameMode: string;
  campaignTime: number;
  campaignSnapshot?: Record<string, unknown>;
  players: Record<string, PlayerState>;
  currentTurn?: TurnState;
  session: Record<string, unknown>;
  aiHost: AIHostState;
  processedCommandIds: string[];
  processedActionIds: string[];
  processedToolCallIds: string[];
  processedRollIds: Record<string, { formula: string; rolls: number[]; total: number; modifier: number; reason: string }>;
  eventTail: NetworkEnvelope[];
}

export interface PlayerCredentials {
  playerId: string;
  playerSessionId: string;
  reconnectToken: string;
}

export interface CommandResult {
  events: NetworkEnvelope[];
  changed: boolean;
}

export interface RandomSource {
  integer(minInclusive: number, maxInclusive: number): number;
}

export const cryptoRandom: RandomSource = {
  integer(minInclusive, maxInclusive) {
    const span = maxInclusive - minInclusive + 1;
    const limit = 0x1_0000_0000 - (0x1_0000_0000 % span);
    const words = new Uint32Array(1);
    do crypto.getRandomValues(words); while (words[0]! >= limit);
    return minInclusive + (words[0]! % span);
  },
};
