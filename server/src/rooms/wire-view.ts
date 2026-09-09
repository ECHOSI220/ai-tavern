import type { PlayerState, RoomState } from './types';

export function playerView(player: PlayerState): Record<string, unknown> {
  return {
    playerId: player.playerId, displayName: player.displayName,
    role: player.role === 'owner' ? 'roomOwner' : 'player',
    characterId: player.character?.id ?? null,
    connectionStatus: player.connected ? 'online' : 'offline',
    isReady: player.ready, joinedAt: player.joinedAt,
  };
}

export function hostView(state: RoomState): Record<string, unknown> {
  const host = state.aiHost;
  return {
    mode: 'selectedPlayer', providerPlayerId: host.providerPlayerId ?? null,
    providerType: host.providerType ?? 'openai-compatible', modelId: host.modelId ?? null,
    status: host.status === 'active' ? (host.lastError ? 'error' : host.requestId ? 'busy' : 'ready')
      : host.status === 'offered' ? 'pending' : host.status === 'unavailable' ? 'offline' : 'none',
    lastHeartbeat: host.heartbeatAt ?? null,
  };
}

// Construct the public view from an allowlist. The canonical campaign and GM
// context must never be copied into ordinary snapshots, including the provider's.
export function sessionView(state: RoomState, viewerId: string): Record<string, unknown> {
  const source = state.session;
  const history = Array.isArray(source.chatHistory) ? source.chatHistory : [];
  const immersion = source.immersionState && typeof source.immersionState === 'object' && !Array.isArray(source.immersionState)
    ? source.immersionState as Record<string, unknown> : {};
  const storedPrivate = Array.isArray(immersion.privateMessages) ? immersion.privateMessages : [];
  // Older server revisions stored private chat as recipient-scoped public chat
  // entries. Migrate those entries into the mailbox view and never render them
  // in the public timeline.
  const legacyPrivate = history.filter((value) => {
    const entry = value as Record<string, unknown>;
    return entry.messageType === 'playerMessage' && Array.isArray(entry.recipientPlayerIds);
  }).map((value) => {
    const entry = value as Record<string, unknown>;
    return {
      id: entry.id, senderId: entry.playerId ?? 'system',
      recipientIds: entry.recipientPlayerIds, content: entry.content,
      createdAt: entry.createdAt, toGm: false,
    };
  });
  const privateMessages = [...storedPrivate, ...legacyPrivate].filter((value) => {
    const entry = value as Record<string, unknown>;
    const recipients = entry.recipientIds;
    return entry.senderId === viewerId || (Array.isArray(recipients) && recipients.includes(viewerId));
  });
  const player = state.players[viewerId];
  const locations = source.characterLocations as Record<string, unknown> | undefined;
  return {
    schemaVersion: 11, id: source.id, title: state.roomName, mode: 'multiplayer',
    createdAt: state.createdAt, updatedAt: state.updatedAt,
    status: state.status === 'playing' ? 'active' : state.status === 'closed' ? 'completed' : state.status === 'paused' ? 'paused' : 'preparing',
    campaignId: state.campaignId, ruleSystemId: state.rulePackId,
    roomOwnerPlayerId: state.ownerPlayerId,
    players: Object.values(state.players).map(playerView),
    playerCharacters: player?.character ? [structuredClone(player.character)] : [],
    characterLocations: player?.character && locations ? { [String(player.character.id)]: locations[String(player.character.id)] } : {},
    aiHostConfig: hostView(state),
    chatHistory: history.filter((value) => {
      const entry = value as Record<string, unknown>;
      const recipients = entry.recipientPlayerIds;
      return !Array.isArray(recipients);
    }).map((value) => {
      const entry = { ...value as Record<string, unknown> }; delete entry.recipientPlayerIds; return entry;
    }),
    currentScene: source.currentScene ?? '',
    immersionState: {
      allowPlayerPrivateChat: state.allowPlayerPrivateChat,
      privateMessages,
    },
    // This field is only populated by server-validated public changes.
    worldState: {},
  };
}
