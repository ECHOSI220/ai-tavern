import 'trpg_models.dart';
import 'social_models.dart';

const multiplayerProtocolVersion = 3;

const _multiplayerUnset = Object();

enum MultiplayerVisibility { public, player, gm, selectedPlayers }

enum MultiplayerRoomStatus {
  lobby,
  starting,
  playing,
  paused,
  finished,
  closed,
}

enum MultiplayerTurnPhase {
  collecting,
  resolving,
  gmResponding,
  applyingTools,
  completed,
  cancelled,
}

enum MultiplayerTurnStatus { active, resolved, cancelled }

enum MultiplayerTurnMode { freeformGroup, combatInitiative }

class PlayerTurnAction {
  const PlayerTurnAction({
    required this.actionId,
    required this.turnId,
    required this.playerId,
    required this.playerDisplayName,
    required this.characterId,
    required this.characterName,
    required this.content,
    required this.confirmed,
    required this.isPass,
    required this.submittedAt,
    this.confirmedAt,
    this.metadata = const {},
  });

  final String actionId,
      turnId,
      playerId,
      playerDisplayName,
      characterId,
      characterName,
      content;
  final bool confirmed, isPass;
  final DateTime submittedAt;
  final DateTime? confirmedAt;
  final Map<String, Object?> metadata;

  PlayerTurnAction copyWith({
    String? content,
    bool? confirmed,
    bool? isPass,
    DateTime? confirmedAt,
    Map<String, Object?>? metadata,
  }) => PlayerTurnAction(
    actionId: actionId,
    turnId: turnId,
    playerId: playerId,
    playerDisplayName: playerDisplayName,
    characterId: characterId,
    characterName: characterName,
    content: content ?? this.content,
    confirmed: confirmed ?? this.confirmed,
    isPass: isPass ?? this.isPass,
    submittedAt: submittedAt,
    confirmedAt: confirmedAt ?? this.confirmedAt,
    metadata: metadata ?? this.metadata,
  );

  PlayerTurnAction redacted() => PlayerTurnAction(
    actionId: actionId,
    turnId: turnId,
    playerId: playerId,
    playerDisplayName: playerDisplayName,
    characterId: characterId,
    characterName: characterName,
    content: '',
    confirmed: confirmed,
    isPass: isPass,
    submittedAt: submittedAt,
    confirmedAt: confirmedAt,
    metadata: const {},
  );

  Map<String, Object?> toJson() => {
    'actionId': actionId,
    'turnId': turnId,
    'playerId': playerId,
    'playerDisplayName': playerDisplayName,
    'characterId': characterId,
    'characterName': characterName,
    'content': content,
    'confirmed': confirmed,
    'isPass': isPass,
    'submittedAt': submittedAt.toIso8601String(),
    'confirmedAt': confirmedAt?.toIso8601String(),
    'metadata': metadata,
  };

  factory PlayerTurnAction.fromJson(Map<String, Object?> json) =>
      PlayerTurnAction(
        actionId: json['actionId'] as String? ?? '',
        turnId: json['turnId'] as String? ?? '',
        playerId: json['playerId'] as String? ?? '',
        playerDisplayName: json['playerDisplayName'] as String? ?? '',
        characterId: json['characterId'] as String? ?? '',
        characterName: json['characterName'] as String? ?? '',
        content: json['content'] as String? ?? '',
        confirmed: json['confirmed'] as bool? ?? false,
        isPass: json['isPass'] as bool? ?? false,
        submittedAt:
            DateTime.tryParse(json['submittedAt'] as String? ?? '') ??
            DateTime.now(),
        confirmedAt: DateTime.tryParse(json['confirmedAt'] as String? ?? ''),
        metadata: json['metadata'] is Map
            ? (json['metadata'] as Map).cast<String, Object?>()
            : const {},
      );
}

class MultiplayerTurn {
  const MultiplayerTurn({
    required this.turnId,
    required this.roundNumber,
    required this.startedAt,
    this.phase = MultiplayerTurnPhase.collecting,
    this.status = MultiplayerTurnStatus.active,
    this.mode = MultiplayerTurnMode.freeformGroup,
    this.playerActions = const {},
    this.confirmedPlayerIds = const [],
    this.expectedPlayerIds = const [],
    this.resolvedAt,
    this.resolutionRequestId,
    this.settlementDeadline,
  });

  final String turnId;
  final int roundNumber;
  final MultiplayerTurnPhase phase;
  final MultiplayerTurnStatus status;
  final MultiplayerTurnMode mode;
  final DateTime startedAt;
  final DateTime? resolvedAt;
  final DateTime? settlementDeadline;
  final Map<String, PlayerTurnAction> playerActions;
  final List<String> confirmedPlayerIds, expectedPlayerIds;
  final String? resolutionRequestId;

  bool get allConfirmed =>
      expectedPlayerIds.isNotEmpty &&
      expectedPlayerIds.every(confirmedPlayerIds.contains);

  MultiplayerTurn copyWith({
    MultiplayerTurnPhase? phase,
    MultiplayerTurnStatus? status,
    MultiplayerTurnMode? mode,
    Map<String, PlayerTurnAction>? playerActions,
    List<String>? confirmedPlayerIds,
    List<String>? expectedPlayerIds,
    Object? resolvedAt = _multiplayerUnset,
    Object? resolutionRequestId = _multiplayerUnset,
    Object? settlementDeadline = _multiplayerUnset,
  }) => MultiplayerTurn(
    turnId: turnId,
    roundNumber: roundNumber,
    phase: phase ?? this.phase,
    status: status ?? this.status,
    mode: mode ?? this.mode,
    startedAt: startedAt,
    resolvedAt: identical(resolvedAt, _multiplayerUnset)
        ? this.resolvedAt
        : resolvedAt as DateTime?,
    playerActions: playerActions ?? this.playerActions,
    confirmedPlayerIds: confirmedPlayerIds ?? this.confirmedPlayerIds,
    expectedPlayerIds: expectedPlayerIds ?? this.expectedPlayerIds,
    resolutionRequestId: identical(resolutionRequestId, _multiplayerUnset)
        ? this.resolutionRequestId
        : resolutionRequestId as String?,
    settlementDeadline: identical(settlementDeadline, _multiplayerUnset)
        ? this.settlementDeadline
        : settlementDeadline as DateTime?,
  );

  MultiplayerTurn forViewer(String? playerId, {bool isGm = false}) => copyWith(
    playerActions: playerActions.map(
      (id, action) =>
          MapEntry(id, isGm || id == playerId ? action : action.redacted()),
    ),
  );

  Map<String, Object?> toJson() => {
    'turnId': turnId,
    'roundNumber': roundNumber,
    'phase': phase.name,
    'status': status.name,
    'mode': mode.name,
    'startedAt': startedAt.toIso8601String(),
    'resolvedAt': resolvedAt?.toIso8601String(),
    'playerActions': playerActions.map(
      (key, value) => MapEntry(key, value.toJson()),
    ),
    'confirmedPlayerIds': confirmedPlayerIds,
    'expectedPlayerIds': expectedPlayerIds,
    'resolutionRequestId': resolutionRequestId,
    'settlementDeadline': settlementDeadline?.toIso8601String(),
  };

  factory MultiplayerTurn.fromJson(Map<String, Object?> json) =>
      MultiplayerTurn(
        turnId: json['turnId'] as String? ?? '',
        roundNumber: (json['roundNumber'] as num?)?.toInt() ?? 1,
        phase: MultiplayerTurnPhase.values.firstWhere(
          (value) => value.name == json['phase'],
          orElse: () => MultiplayerTurnPhase.collecting,
        ),
        status: MultiplayerTurnStatus.values.firstWhere(
          (value) => value.name == json['status'],
          orElse: () => MultiplayerTurnStatus.active,
        ),
        mode: MultiplayerTurnMode.values.firstWhere(
          (value) => value.name == json['mode'],
          orElse: () => MultiplayerTurnMode.freeformGroup,
        ),
        startedAt:
            DateTime.tryParse(json['startedAt'] as String? ?? '') ??
            DateTime.now(),
        resolvedAt: DateTime.tryParse(json['resolvedAt'] as String? ?? ''),
        playerActions: ((json['playerActions'] as Map?) ?? const {}).map(
          (key, value) => MapEntry(
            key.toString(),
            PlayerTurnAction.fromJson((value as Map).cast<String, Object?>()),
          ),
        ),
        confirmedPlayerIds: (json['confirmedPlayerIds'] as List? ?? const [])
            .map((value) => value.toString())
            .toList(),
        expectedPlayerIds: (json['expectedPlayerIds'] as List? ?? const [])
            .map((value) => value.toString())
            .toList(),
        resolutionRequestId: json['resolutionRequestId'] as String?,
        settlementDeadline: DateTime.tryParse(
          json['settlementDeadline'] as String? ?? '',
        ),
      );
}

class RoundActionBundle {
  const RoundActionBundle({
    required this.turnId,
    required this.roundNumber,
    required this.actions,
    required this.timestamp,
    this.sceneState = const {},
    this.combatState = const {},
    this.partyState = const {},
  });

  final String turnId;
  final int roundNumber;
  final List<PlayerTurnAction> actions;
  final DateTime timestamp;
  final Map<String, Object?> sceneState, combatState, partyState;

  Map<String, Object?> toJson() => {
    'turnId': turnId,
    'roundNumber': roundNumber,
    'actions': actions.map((value) => value.toJson()).toList(),
    'sceneState': sceneState,
    'combatState': combatState,
    'partyState': partyState,
    'timestamp': timestamp.toIso8601String(),
  };
}

enum MultiplayerEventType {
  hello,
  createRoom,
  roomCreated,
  joinRoom,
  reconnect,
  snapshot,
  statePatch,
  playerJoined,
  playerLeft,
  playerReady,
  selectCharacter,
  hostRequested,
  hostAccepted,
  hostDeclined,
  hostChanged,
  hostHeartbeat,
  gameStarted,
  playerAction,
  turnStarted,
  turnActionConfirm,
  turnActionUnconfirm,
  turnPlayerStatus,
  turnAllConfirmed,
  turnResolving,
  turnResolved,
  turnCancelled,
  turnSkipPlayer,
  secretAction,
  playerChat,
  privateMessage,
  privateRoll,
  revealInformation,
  presentationEvent,
  gmProcessing,
  aiRequest,
  aiResponse,
  toolCall,
  toolResult,
  gmMessage,
  pauseGame,
  resumeGame,
  retryAction,
  requestSnapshot,
  kickPlayer,
  error,
  ping,
  pong,
  deviceCapability,
  campaignAnnouncement,
}

class MultiplayerEnvelope {
  const MultiplayerEnvelope({
    required this.type,
    this.commandId,
    this.roomId,
    this.token,
    this.sequenceNumber = 0,
    this.revision = 0,
    this.payload = const {},
    this.visibility = MultiplayerVisibility.public,
    this.recipientPlayerIds = const [],
  });
  final MultiplayerEventType type;
  final String? commandId, roomId, token;
  final int sequenceNumber, revision;
  final Map<String, Object?> payload;
  final MultiplayerVisibility visibility;
  final List<String> recipientPlayerIds;

  Map<String, Object?> toJson() => {
    'protocolVersion': multiplayerProtocolVersion,
    'type': type.name,
    'commandId': commandId,
    'roomId': roomId,
    'token': token,
    'sequenceNumber': sequenceNumber,
    'revision': revision,
    'payload': payload,
    'visibility': visibility.name,
    'recipientPlayerIds': recipientPlayerIds,
  };

  factory MultiplayerEnvelope.fromJson(Map<String, Object?> json) {
    final version = (json['protocolVersion'] as num?)?.toInt() ?? 0;
    if (version != multiplayerProtocolVersion) {
      throw FormatException('Unsupported protocol version: $version');
    }
    return MultiplayerEnvelope(
      type: MultiplayerEventType.values.firstWhere(
        (item) => item.name == json['type'],
        orElse: () => MultiplayerEventType.error,
      ),
      commandId: json['commandId'] as String?,
      roomId: json['roomId'] as String?,
      token: json['token'] as String?,
      sequenceNumber: (json['sequenceNumber'] as num?)?.toInt() ?? 0,
      revision: (json['revision'] as num?)?.toInt() ?? 0,
      payload: json['payload'] is Map
          ? (json['payload'] as Map).cast<String, Object?>()
          : const {},
      visibility: MultiplayerVisibility.values.firstWhere(
        (value) => value.name == json['visibility'],
        orElse: () => MultiplayerVisibility.public,
      ),
      recipientPlayerIds: (json['recipientPlayerIds'] as List? ?? const [])
          .map((value) => value.toString())
          .toList(),
    );
  }
}

class TRPGRoom {
  const TRPGRoom({
    required this.roomId,
    required this.roomCode,
    required this.roomName,
    required this.ownerPlayerId,
    required this.campaignId,
    required this.createdAt,
    required this.updatedAt,
    this.status = MultiplayerRoomStatus.lobby,
    this.ruleSystemId = 'simple_trpg',
    this.maxPlayers = 4,
    this.players = const [],
    this.sessionId,
    this.gmMode = AIHostMode.selectedPlayer,
    this.aiHostConfig = const AIHostConfig(status: AIHostStatus.none),
    this.allowJoinInProgress = false,
    this.revision = 0,
    this.sequenceNumber = 0,
    this.gmWaiting = false,
    this.kind = CampaignRoomKind.temporary,
    this.persistentCampaignRoomId,
    this.ownerUserId,
    this.campaignMemberRoles = const {},
    this.currentTurn,
  });
  final String roomId,
      roomCode,
      roomName,
      ownerPlayerId,
      campaignId,
      ruleSystemId;
  final DateTime createdAt, updatedAt;
  final MultiplayerRoomStatus status;
  final int maxPlayers, revision, sequenceNumber;
  final List<TRPGPlayer> players;
  final String? sessionId;
  final AIHostMode gmMode;
  final AIHostConfig aiHostConfig;
  final bool allowJoinInProgress, gmWaiting;
  final CampaignRoomKind kind;
  final String? persistentCampaignRoomId, ownerUserId;
  final Map<String, CampaignMemberRole> campaignMemberRoles;
  final MultiplayerTurn? currentTurn;

  TRPGRoom copyWith({
    String? ownerPlayerId,
    MultiplayerRoomStatus? status,
    List<TRPGPlayer>? players,
    String? sessionId,
    AIHostMode? gmMode,
    AIHostConfig? aiHostConfig,
    int? revision,
    int? sequenceNumber,
    bool? gmWaiting,
    DateTime? updatedAt,
    CampaignRoomKind? kind,
    String? persistentCampaignRoomId,
    String? ownerUserId,
    Map<String, CampaignMemberRole>? campaignMemberRoles,
    MultiplayerTurn? currentTurn,
  }) => TRPGRoom(
    roomId: roomId,
    roomCode: roomCode,
    roomName: roomName,
    ownerPlayerId: ownerPlayerId ?? this.ownerPlayerId,
    campaignId: campaignId,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    status: status ?? this.status,
    ruleSystemId: ruleSystemId,
    maxPlayers: maxPlayers,
    players: players ?? this.players,
    sessionId: sessionId ?? this.sessionId,
    gmMode: gmMode ?? this.gmMode,
    aiHostConfig: aiHostConfig ?? this.aiHostConfig,
    allowJoinInProgress: allowJoinInProgress,
    revision: revision ?? this.revision,
    sequenceNumber: sequenceNumber ?? this.sequenceNumber,
    gmWaiting: gmWaiting ?? this.gmWaiting,
    kind: kind ?? this.kind,
    persistentCampaignRoomId:
        persistentCampaignRoomId ?? this.persistentCampaignRoomId,
    ownerUserId: ownerUserId ?? this.ownerUserId,
    campaignMemberRoles: campaignMemberRoles ?? this.campaignMemberRoles,
    currentTurn: currentTurn ?? this.currentTurn,
  );

  Map<String, Object?> toJson() => {
    'roomId': roomId,
    'roomCode': roomCode,
    'roomName': roomName,
    'ownerPlayerId': ownerPlayerId,
    'status': status.name,
    'campaignId': campaignId,
    'ruleSystemId': ruleSystemId,
    'maxPlayers': maxPlayers,
    'players': players.map((item) => item.toJson()).toList(),
    'sessionId': sessionId,
    'gmMode': gmMode.name,
    'aiHostConfig': aiHostConfig.toJson(),
    'allowJoinInProgress': allowJoinInProgress,
    'revision': revision,
    'sequenceNumber': sequenceNumber,
    'gmWaiting': gmWaiting,
    'kind': kind.name,
    'persistentCampaignRoomId': persistentCampaignRoomId,
    'ownerUserId': ownerUserId,
    'campaignMemberRoles': campaignMemberRoles.map(
      (key, value) => MapEntry(key, value.name),
    ),
    'currentTurn': currentTurn?.toJson(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory TRPGRoom.fromJson(Map<String, Object?> json) => TRPGRoom(
    roomId: json['roomId'] as String,
    roomCode: json['roomCode'] as String,
    roomName: json['roomName'] as String,
    ownerPlayerId: json['ownerPlayerId'] as String,
    status: MultiplayerRoomStatus.values.firstWhere(
      (item) => item.name == json['status'],
      orElse: () => MultiplayerRoomStatus.lobby,
    ),
    campaignId: json['campaignId'] as String? ?? 'mist_harbor_test',
    ruleSystemId: json['ruleSystemId'] as String? ?? 'simple_trpg',
    maxPlayers: (json['maxPlayers'] as num?)?.toInt() ?? 4,
    players: (json['players'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => TRPGPlayer.fromJson(item.cast<String, Object?>()))
        .toList(),
    sessionId: json['sessionId'] as String?,
    gmMode: AIHostMode.values.firstWhere(
      (item) => item.name == json['gmMode'],
      orElse: () => AIHostMode.selectedPlayer,
    ),
    aiHostConfig: AIHostConfig.fromJson(
      json['aiHostConfig'] is Map
          ? (json['aiHostConfig'] as Map).cast<String, Object?>()
          : const {},
    ),
    allowJoinInProgress: json['allowJoinInProgress'] as bool? ?? false,
    revision: (json['revision'] as num?)?.toInt() ?? 0,
    sequenceNumber: (json['sequenceNumber'] as num?)?.toInt() ?? 0,
    gmWaiting: json['gmWaiting'] as bool? ?? false,
    kind: CampaignRoomKind.values.firstWhere(
      (value) => value.name == json['kind'],
      orElse: () => CampaignRoomKind.temporary,
    ),
    persistentCampaignRoomId: json['persistentCampaignRoomId'] as String?,
    ownerUserId: json['ownerUserId'] as String?,
    campaignMemberRoles: ((json['campaignMemberRoles'] as Map?) ?? const {})
        .map(
          (key, value) => MapEntry(
            key.toString(),
            CampaignMemberRole.values.firstWhere(
              (role) => role.name == value,
              orElse: () => CampaignMemberRole.player,
            ),
          ),
        ),
    currentTurn: json['currentTurn'] is Map
        ? MultiplayerTurn.fromJson(
            (json['currentTurn'] as Map).cast<String, Object?>(),
          )
        : null,
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
  );
}

class MultiplayerSnapshot {
  const MultiplayerSnapshot({required this.room, this.session});
  final TRPGRoom room;
  final TRPGSession? session;
  Map<String, Object?> toJson() => {
    'room': room.toJson(),
    'session': session?.toJson(),
  };
  factory MultiplayerSnapshot.fromJson(Map<String, Object?> json) =>
      MultiplayerSnapshot(
        room: TRPGRoom.fromJson((json['room'] as Map).cast<String, Object?>()),
        session: json['session'] is Map
            ? TRPGSession.fromJson(
                (json['session'] as Map).cast<String, Object?>(),
              )
            : null,
      );
}

class MultiplayerCredentials {
  const MultiplayerCredentials({
    required this.endpoint,
    required this.roomId,
    required this.playerId,
    required this.sessionToken,
    this.lastRevision = 0,
    this.playerSessionId,
  });
  final String endpoint, roomId, playerId, sessionToken;
  final String? playerSessionId;
  final int lastRevision;
  Map<String, Object?> toJson() => {
    'endpoint': endpoint,
    'roomId': roomId,
    'playerId': playerId,
    'sessionToken': sessionToken,
    'playerSessionId': playerSessionId,
    'lastRevision': lastRevision,
  };
  factory MultiplayerCredentials.fromJson(Map<String, Object?> json) =>
      MultiplayerCredentials(
        endpoint: json['endpoint'] as String,
        roomId: json['roomId'] as String,
        playerId: json['playerId'] as String,
        sessionToken: json['sessionToken'] as String,
        playerSessionId: json['playerSessionId'] as String?,
        lastRevision: (json['lastRevision'] as num?)?.toInt() ?? 0,
      );
}
