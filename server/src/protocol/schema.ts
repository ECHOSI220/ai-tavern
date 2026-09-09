import { z } from "zod";

export const PROTOCOL_VERSION = 3;

export const eventTypes = [
  "hello",
  "createRoom",
  "roomCreated",
  "joinRoom",
  "reconnect",
  "snapshot",
  "statePatch",
  "playerJoined",
  "playerLeft",
  "playerReady",
  "selectCharacter",
  "hostRequested",
  "hostAccepted",
  "hostDeclined",
  "hostChanged",
  "hostHeartbeat",
  "gameStarted",
  "playerAction",
  "turnStarted",
  "turnActionConfirm",
  "turnActionUnconfirm",
  "turnPlayerStatus",
  "turnAllConfirmed",
  "turnResolving",
  "turnResolved",
  "turnCancelled",
  "turnSkipPlayer",
  "secretAction",
  "playerChat",
  "privateMessage",
  "privateRoll",
  "revealInformation",
  "presentationEvent",
  "gmProcessing",
  "aiRequest",
  "aiResponse",
  "toolCall",
  "toolResult",
  "gmMessage",
  "pauseGame",
  "resumeGame",
  "retryAction",
  "requestSnapshot",
  "kickPlayer",
  "error",
  "ping",
  "pong",
  "deviceCapability",
  "campaignAnnouncement",
] as const;

export const visibilitySchema = z.enum([
  "public",
  "player",
  "gm",
  "selectedPlayers",
]);

export const networkEnvelopeSchema = z
  .object({
    protocolVersion: z.number().int().positive(),
    type: z.enum(eventTypes),
    messageId: z.string().uuid().optional(),
    commandId: z.string().min(1).max(128).nullable().optional(),
    roomId: z.string().uuid().nullable().optional(),
    playerSessionId: z.string().uuid().nullable().optional(),
    senderPlayerId: z.string().uuid().nullable().optional(),
    token: z.string().max(512).nullable().optional(),
    timestamp: z.string().datetime().optional(),
    sequenceNumber: z.number().int().nonnegative().default(0),
    revision: z.number().int().nonnegative().default(0),
    payload: z.record(z.string(), z.unknown()).default({}),
    visibility: visibilitySchema.default("public"),
    recipientPlayerIds: z.array(z.string().uuid()).max(16).default([]),
  })
  .strict();

export type NetworkEnvelope = z.infer<typeof networkEnvelopeSchema>;
export type EventType = (typeof eventTypes)[number];
export type Visibility = z.infer<typeof visibilitySchema>;

export const createRoomRequestSchema = z
  .object({
    campaignId: z.string().min(1).max(128),
    roomName: z.string().min(1).max(80).default("公网跑团房间"),
    playerName: z.string().min(1).max(40),
    maxPlayers: z.number().int().min(2).max(8).default(4),
    gameMode: z.string().min(1).max(64).default("trpg"),
    rulePackId: z.string().min(1).max(128).default("simple_trpg"),
    privacy: z.enum(["private", "invite_only"]).default("private"),
    campaignSnapshot: z.record(z.string(), z.unknown()).optional(),
    allowPlayerPrivateChat: z.boolean().default(true),
    settings: z.record(z.string(), z.unknown()).default({}),
  })
  .strict();

export const joinRoomRequestSchema = z
  .object({
    roomCode: z.string().regex(/^[A-HJ-NP-Z2-9]{5,8}$/),
    playerName: z.string().min(1).max(40),
  })
  .strict();

export const roomBootstrapSchema = z
  .object({
    roomId: z.string().uuid(),
    roomCode: z.string(),
    playerId: z.string().uuid(),
    playerSessionId: z.string().uuid(),
    reconnectToken: z.string().min(32),
    socketUrl: z.string().url(),
    revision: z.number().int().nonnegative(),
  })
  .strict();

export function parseEnvelope(raw: string, expectedVersion: number): NetworkEnvelope {
  const parsed = networkEnvelopeSchema.parse(JSON.parse(raw));
  if (parsed.protocolVersion !== expectedVersion) {
    throw new Error(`UNSUPPORTED_PROTOCOL:${parsed.protocolVersion}`);
  }
  return parsed;
}

export function envelope(
  type: EventType,
  roomId: string,
  payload: Record<string, unknown>,
  revision: number,
  sequenceNumber: number,
  options: Partial<Pick<NetworkEnvelope, "visibility" | "recipientPlayerIds" | "commandId">> = {},
): NetworkEnvelope {
  return {
    protocolVersion: PROTOCOL_VERSION,
    messageId: crypto.randomUUID(),
    type,
    commandId: options.commandId ?? null,
    roomId,
    timestamp: new Date().toISOString(),
    sequenceNumber,
    revision,
    payload,
    visibility: options.visibility ?? "public",
    recipientPlayerIds: options.recipientPlayerIds ?? [],
  };
}
