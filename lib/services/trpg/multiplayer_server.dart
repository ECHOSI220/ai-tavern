// ignore_for_file: curly_braces_in_flow_control_structures

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:uuid/uuid.dart';

import '../../models/multiplayer_models.dart';
import '../../models/campaign_models.dart';
import '../../models/trpg_game_models.dart';
import '../../models/trpg_models.dart';
import '../../models/trpg_presentation_models.dart';
import '../../models/trpg_memory_models.dart';
import '../../models/trpg_party_models.dart';
import '../../models/trpg_world_generator_models.dart';
import '../../models/social_models.dart';
import '../../models/trpg_dice_models.dart';
import '../../models/trpg_gameplay_models.dart';
import '../ai/openai_compatible_provider.dart';
import 'ai_gm_prompt_builder.dart';
import 'ai_gm_tool_registry.dart';
import 'campaign_service.dart';
import 'campaign_template_service.dart';
import 'dice_service.dart';
import '../trpg_memory/trpg_long_term_memory_service.dart';
import 'social_backend_service.dart';
import 'social_http_api.dart';
import 'room_permission_service.dart';
import 'living_npc_service.dart';
import 'world_generator.dart';
import 'faction_simulation_service.dart';
import 'holy_grail_war_manager.dart';
import 'campaign_opening_briefing.dart';
import 'trpg_check_pipeline.dart';

class MultiplayerServerConfig {
  const MultiplayerServerConfig({
    this.address = '0.0.0.0',
    this.port = 8765,
    this.aiRequestTimeout = const Duration(seconds: 120),
    this.offlineGrace = const Duration(seconds: 60),
    this.settlementGrace = const Duration(seconds: 5),
    this.persistenceDirectory = 'multiplayer_data',
  });
  final String address, persistenceDirectory;
  final int port;
  final Duration aiRequestTimeout, offlineGrace, settlementGrace;
}

class MultiplayerAuthoritativeServer {
  MultiplayerAuthoritativeServer({
    this.config = const MultiplayerServerConfig(),
    AIGMToolRegistry? tools,
    AIGMPromptBuilder promptBuilder = const AIGMPromptBuilder(),
  }) : _tools = tools ?? AIGMToolRegistry(),
       _prompts = promptBuilder,
       _checks = TRPGCheckPipeline(),
       _social = SocialBackendService(
         directory:
             '${config.persistenceDirectory}${Platform.pathSeparator}social',
       );

  final MultiplayerServerConfig config;
  final AIGMToolRegistry _tools;
  final AIGMPromptBuilder _prompts;
  final TRPGCheckPipeline _checks;
  final _rooms = <String, _ServerRoom>{};
  final _roomCodes = <String, String>{};
  final _tokens = <String, _Identity>{};
  final _connections = <WebSocket, _Identity?>{};
  final _uuid = const Uuid();
  final _dice = DiceService();
  final _longTermMemory = const TRPGLongTermMemoryService();
  final SocialBackendService _social;
  late final SocialHttpApi _socialApi = SocialHttpApi(
    backend: _social,
    assetDirectory:
        '${config.persistenceDirectory}${Platform.pathSeparator}assets',
    sessionSnapshotProvider: _campaignSessionSnapshot,
    sessionRestoreHandler: _restoreCampaignSession,
  );
  HttpServer? _httpServer;
  Timer? _heartbeatTimer;

  int get port => _httpServer?.port ?? config.port;
  Iterable<TRPGRoom> get rooms => _rooms.values.map((item) => item.room);

  Future<void> start() async {
    await _social.initialize();
    await _restoreRooms();
    _httpServer = await HttpServer.bind(config.address, config.port);
    _httpServer!.listen(_handleHttp);
    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _checkOfflineHosts(),
    );
  }

  Future<void> stop() async {
    _heartbeatTimer?.cancel();
    for (final room in _rooms.values) {
      room.settlementTimer?.cancel();
    }
    for (final socket in _connections.keys.toList()) {
      await socket.close(WebSocketStatus.goingAway, 'server_shutdown');
    }
    await _httpServer?.close(force: true);
    _httpServer = null;
  }

  Future<void> _handleHttp(HttpRequest request) async {
    if (request.uri.path == '/health') {
      request.response
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'ok': true,
            'protocolVersion': multiplayerProtocolVersion,
          }),
        );
      await request.response.close();
      return;
    }
    if (request.method == 'GET' &&
        request.uri.path.startsWith('/api/assets/')) {
      final name = request.uri.pathSegments.last;
      if (!RegExp(r'^[a-f0-9]{64}\.[A-Za-z0-9]+$').hasMatch(name)) {
        request.response.statusCode = HttpStatus.badRequest;
        await request.response.close();
        return;
      }
      final file = File(
        '${config.persistenceDirectory}${Platform.pathSeparator}assets'
        '${Platform.pathSeparator}$name',
      );
      if (!await file.exists()) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      request.response.headers.set(
        HttpHeaders.cacheControlHeader,
        'public, max-age=31536000, immutable',
      );
      await request.response.addStream(file.openRead());
      await request.response.close();
      return;
    }
    if (await _socialApi.handle(request)) return;
    if (request.uri.path != '/ws' ||
        !WebSocketTransformer.isUpgradeRequest(request)) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    final socket = await WebSocketTransformer.upgrade(request);
    _connections[socket] = null;
    socket.listen(
      (data) => _handleSocketMessage(socket, data),
      onDone: () => _handleDisconnect(socket),
      onError: (_) => _handleDisconnect(socket),
      cancelOnError: true,
    );
    _send(socket, const MultiplayerEnvelope(type: MultiplayerEventType.hello));
  }

  Future<void> _handleSocketMessage(WebSocket socket, Object? data) async {
    MultiplayerEnvelope command;
    try {
      final raw = jsonDecode(data.toString());
      command = MultiplayerEnvelope.fromJson(
        (raw as Map).cast<String, Object?>(),
      );
    } catch (error) {
      _error(socket, 'invalid_message', error.toString());
      return;
    }
    try {
      switch (command.type) {
        case MultiplayerEventType.createRoom:
          await _createRoom(socket, command);
        case MultiplayerEventType.joinRoom:
          await _joinRoom(socket, command);
        case MultiplayerEventType.reconnect:
          await _reconnect(socket, command);
        case MultiplayerEventType.ping:
          _send(
            socket,
            const MultiplayerEnvelope(type: MultiplayerEventType.pong),
          );
        default:
          final identity = _authenticate(socket, command.token);
          final serverRoom = _rooms[identity.roomId];
          if (serverRoom == null) throw StateError('Room no longer exists');
          if (command.commandId != null &&
              serverRoom.executedCommandIds.contains(command.commandId)) {
            _sendSnapshot(socket, serverRoom);
            return;
          }
          if (command.commandId != null) {
            serverRoom.executedCommandIds.add(command.commandId!);
            while (serverRoom.executedCommandIds.length > 500) {
              serverRoom.executedCommandIds.remove(
                serverRoom.executedCommandIds.first,
              );
            }
          }
          await _execute(serverRoom, identity, command);
      }
    } catch (error) {
      _error(
        socket,
        'command_rejected',
        error.toString(),
        commandId: command.commandId,
      );
    }
  }

  Future<void> _createRoom(
    WebSocket socket,
    MultiplayerEnvelope command,
  ) async {
    final account = _optionalAccount(command.payload);
    final requestedPersistentId =
        command.payload['persistentCampaignRoomId'] as String?;
    if (account != null && requestedPersistentId != null) {
      final existing = _rooms.values
          .where(
            (value) =>
                value.room.persistentCampaignRoomId == requestedPersistentId,
          )
          .firstOrNull;
      if (existing != null) {
        await _joinPersistentRoom(socket, command, existing, account);
        return;
      }
    }
    final name =
        account?.displayName ?? _requiredString(command.payload, 'playerName');
    final now = DateTime.now();
    final playerId = _uuid.v4();
    final token = _newToken();
    final roomId = _uuid.v4();
    final roomCode = _newRoomCode();
    final requestedGmMode =
        AIHostMode.values
            .where((item) => item.name == command.payload['gmMode'])
            .firstOrNull ??
        AIHostMode.selectedPlayer;
    final player = TRPGPlayer(
      playerId: playerId,
      displayName: name,
      role: requestedGmMode == AIHostMode.humanGm
          ? TRPGPlayerRole.humanGm
          : TRPGPlayerRole.roomOwner,
      joinedAt: now,
    );
    var room = TRPGRoom(
      roomId: roomId,
      roomCode: roomCode,
      roomName: command.payload['roomName'] as String? ?? '$name 的房间',
      ownerPlayerId: playerId,
      campaignId:
          command.payload['campaignId'] as String? ?? 'mist_harbor_test',
      ruleSystemId: command.payload['ruleSystemId'] as String? ?? 'simple_trpg',
      maxPlayers: ((command.payload['maxPlayers'] as num?)?.toInt() ?? 4).clamp(
        2,
        6,
      ),
      players: [player],
      gmMode: requestedGmMode,
      allowJoinInProgress:
          command.payload['allowJoinInProgress'] as bool? ?? false,
      createdAt: now,
      updatedAt: now,
      kind:
          CampaignRoomKind.values
              .where((value) => value.name == command.payload['kind'])
              .firstOrNull ??
          CampaignRoomKind.temporary,
      persistentCampaignRoomId:
          command.payload['persistentCampaignRoomId'] as String?,
      ownerUserId: account?.userId,
    );
    if (room.kind == CampaignRoomKind.persistent) {
      if (account == null || room.persistentCampaignRoomId == null) {
        throw StateError('永久战役需要登录账号与 Campaign Room ID');
      }
      final campaign = _social.campaignFor(
        account.userId,
        room.persistentCampaignRoomId!,
      );
      const RoomPermissionService().require(
        campaign,
        account.userId,
        RoomPermission.start,
      );
      room = room.copyWith(ownerUserId: campaign.ownerUserId);
      room = room.copyWith(
        campaignMemberRoles: {playerId: campaign.member(account.userId)!.role},
      );
    }
    final campaignSnapshot = command.payload['campaignSnapshot'] is Map
        ? (command.payload['campaignSnapshot'] as Map).cast<String, Object?>()
        : null;
    if (campaignSnapshot != null) {
      final document = CampaignDocument.fromJson(campaignSnapshot);
      if (document.id != room.campaignId) {
        throw StateError('Campaign Snapshot 与 campaignId 不匹配');
      }
    }
    final serverRoom = _ServerRoom(
      room: room,
      campaignSnapshot: campaignSnapshot,
      allowPlayerPrivateChat:
          command.payload['allowPlayerPrivateChat'] as bool? ?? true,
    );
    _rooms[roomId] = serverRoom;
    _roomCodes[roomCode] = roomId;
    final identity = _Identity(
      roomId: roomId,
      playerId: playerId,
      token: token,
      userId: account?.userId,
      deviceSessionId: account == null
          ? null
          : _social
                .authenticate(_requiredString(command.payload, 'accessToken'))
                .deviceSession
                .id,
    );
    _tokens[token] = identity;
    _connections[socket] = identity;
    serverRoom.sockets[playerId] = socket;
    await _persist(serverRoom);
    _send(
      socket,
      MultiplayerEnvelope(
        type: MultiplayerEventType.roomCreated,
        roomId: roomId,
        token: token,
        payload: {
          'playerId': playerId,
          'sessionToken': token,
          'snapshot': _safeSnapshotForPlayer(serverRoom, playerId).toJson(),
        },
      ),
    );
  }

  Future<void> _joinRoom(WebSocket socket, MultiplayerEnvelope command) async {
    final persistentId = command.payload['persistentCampaignRoomId'] as String?;
    final code = command.payload['roomCode'] is String
        ? (command.payload['roomCode'] as String).trim().toUpperCase()
        : '';
    final roomId = persistentId == null
        ? _roomCodes[code]
        : _rooms.values
              .where(
                (value) => value.room.persistentCampaignRoomId == persistentId,
              )
              .firstOrNull
              ?.room
              .roomId;
    final serverRoom = roomId == null ? null : _rooms[roomId];
    if (serverRoom == null) throw StateError('房间码不存在');
    final account = _optionalAccount(command.payload);
    PersistentCampaignRoom? persistentCampaign;
    if (serverRoom.room.kind == CampaignRoomKind.persistent) {
      if (account == null) throw StateError('永久战役需要账号登录');
      persistentCampaign = _social.campaignFor(
        account.userId,
        serverRoom.room.persistentCampaignRoomId!,
      );
    }
    if (serverRoom.room.players.length >= serverRoom.room.maxPlayers)
      throw StateError('房间已满');
    if (serverRoom.room.status != MultiplayerRoomStatus.lobby &&
        !serverRoom.room.allowJoinInProgress) {
      throw StateError('房间已经开始，未允许中途加入');
    }
    final now = DateTime.now();
    final playerId = _uuid.v4();
    final token = _newToken();
    final player = TRPGPlayer(
      playerId: playerId,
      displayName:
          account?.displayName ??
          _requiredString(command.payload, 'playerName'),
      joinedAt: now,
    );
    serverRoom.room = serverRoom.room.copyWith(
      players: [...serverRoom.room.players, player],
      revision: serverRoom.room.revision + 1,
      updatedAt: now,
      campaignMemberRoles: {
        ...serverRoom.room.campaignMemberRoles,
        if (account != null && persistentCampaign != null)
          playerId: persistentCampaign.member(account.userId)!.role,
      },
    );
    final identity = _Identity(
      roomId: roomId!,
      playerId: playerId,
      token: token,
      userId: account?.userId,
      deviceSessionId: account == null
          ? null
          : _social
                .authenticate(_requiredString(command.payload, 'accessToken'))
                .deviceSession
                .id,
    );
    _tokens[token] = identity;
    _connections[socket] = identity;
    serverRoom.sockets[playerId] = socket;
    await _persist(serverRoom);
    _send(
      socket,
      MultiplayerEnvelope(
        type: MultiplayerEventType.snapshot,
        roomId: roomId,
        token: token,
        revision: serverRoom.room.revision,
        payload: {
          'playerId': playerId,
          'sessionToken': token,
          ..._safeSnapshotForPlayer(serverRoom, playerId).toJson(),
        },
      ),
    );
    _broadcastRoomPatch(serverRoom, MultiplayerEventType.playerJoined, {
      'player': player.toJson(),
    });
  }

  Future<void> _joinPersistentRoom(
    WebSocket socket,
    MultiplayerEnvelope command,
    _ServerRoom serverRoom,
    UserAccount account,
  ) async {
    final priorIdentity = _tokens.values
        .where(
          (value) =>
              value.roomId == serverRoom.room.roomId &&
              value.userId == account.userId,
        )
        .firstOrNull;
    if (priorIdentity != null) {
      final activeIdentity = _Identity(
        roomId: priorIdentity.roomId,
        playerId: priorIdentity.playerId,
        token: priorIdentity.token,
        userId: account.userId,
        deviceSessionId: _social
            .authenticate(_requiredString(command.payload, 'accessToken'))
            .deviceSession
            .id,
      );
      _tokens[activeIdentity.token] = activeIdentity;
      _connections[socket] = activeIdentity;
      serverRoom.sockets[priorIdentity.playerId]?.close(
        WebSocketStatus.normalClosure,
        'replaced_by_account_device',
      );
      serverRoom.sockets[priorIdentity.playerId] = socket;
      _setConnection(
        serverRoom,
        priorIdentity.playerId,
        TRPGConnectionStatus.online,
      );
      _send(
        socket,
        MultiplayerEnvelope(
          type: MultiplayerEventType.snapshot,
          roomId: serverRoom.room.roomId,
          token: activeIdentity.token,
          revision: serverRoom.room.revision,
          payload: {
            'playerId': priorIdentity.playerId,
            'sessionToken': activeIdentity.token,
            ..._safeSnapshotForPlayer(
              serverRoom,
              priorIdentity.playerId,
            ).toJson(),
          },
        ),
      );
      return;
    }
    // The account is a valid persistent campaign member; join the existing
    // realtime room without requiring or exposing its temporary room code.
    final forwarded = MultiplayerEnvelope(
      type: MultiplayerEventType.joinRoom,
      payload: {
        ...command.payload,
        'persistentCampaignRoomId': serverRoom.room.persistentCampaignRoomId,
        'playerName': account.displayName,
      },
    );
    await _joinRoom(socket, forwarded);
  }

  Future<void> _reconnect(WebSocket socket, MultiplayerEnvelope command) async {
    final token =
        command.token ?? _requiredString(command.payload, 'sessionToken');
    final identity = _tokens[token];
    if (identity == null) throw StateError('重连凭证无效');
    final room = _rooms[identity.roomId];
    if (room == null) throw StateError('房间已经关闭');
    _connections[socket] = identity;
    room.sockets[identity.playerId]?.close(
      WebSocketStatus.normalClosure,
      'replaced',
    );
    room.sockets[identity.playerId] = socket;
    _setConnection(room, identity.playerId, TRPGConnectionStatus.online);
    if (room.room.aiHostConfig.providerPlayerId == identity.playerId) {
      room.room = room.room.copyWith(
        status:
            room.room.status == MultiplayerRoomStatus.paused &&
                room.room.gmWaiting
            ? MultiplayerRoomStatus.playing
            : room.room.status,
        gmWaiting: false,
        aiHostConfig: room.room.aiHostConfig.copyWith(
          status: AIHostStatus.ready,
          lastHeartbeat: DateTime.now(),
        ),
      );
      await _resumePendingTurn(room);
      await _recoverStalledTurn(room);
      if (room.activeAction != null) _sendAIRequest(room);
    }
    _sendSnapshot(socket, room);
    _broadcastRoomPatch(room, MultiplayerEventType.playerJoined, {
      'playerId': identity.playerId,
      'reconnected': true,
    });
  }

  Future<void> _execute(
    _ServerRoom room,
    _Identity actor,
    MultiplayerEnvelope command,
  ) async {
    switch (command.type) {
      case MultiplayerEventType.playerReady:
        if (room.room.status != MultiplayerRoomStatus.lobby)
          throw StateError('游戏开始后不能修改 Ready');
        final ready = command.payload['ready'] as bool? ?? false;
        room.room = room.room.copyWith(
          players: room.room.players
              .map(
                (player) => player.playerId == actor.playerId
                    ? player.copyWith(isReady: ready)
                    : player,
              )
              .toList(),
        );
        await _commitRoom(room, MultiplayerEventType.playerReady, {
          'playerId': actor.playerId,
          'ready': ready,
        });
      case MultiplayerEventType.selectCharacter:
        await _selectCharacter(room, actor, command.payload);
      case MultiplayerEventType.hostRequested:
        _requireManagement(room, actor, RoomPermission.changeHost);
        await _requestHost(
          room,
          _requiredString(command.payload, 'providerPlayerId'),
          command.payload,
        );
      case MultiplayerEventType.hostAccepted:
        await _acceptHost(room, actor, command.payload);
      case MultiplayerEventType.hostDeclined:
        await _declineHost(room, actor);
      case MultiplayerEventType.hostHeartbeat:
        _requireHost(room, actor);
        room.room = room.room.copyWith(
          aiHostConfig: room.room.aiHostConfig.copyWith(
            status: room.activeAction == null
                ? AIHostStatus.ready
                : AIHostStatus.busy,
            lastHeartbeat: DateTime.now(),
          ),
        );
      case MultiplayerEventType.deviceCapability:
        if (actor.userId == null || actor.deviceSessionId == null) {
          throw StateError('游客不能登记 AI Host 设备能力');
        }
        final providerTypes =
            (command.payload['providerTypes'] as List? ?? const [])
                .map((value) => value.toString())
                .toList();
        final verified =
            command.payload['toolCallingVerified'] as bool? ?? false;
        await _social.updateDeviceCapability(
          actor.deviceSessionId!,
          supportsAIHost: command.payload['supportsAIHost'] as bool? ?? false,
          providerTypes: providerTypes,
          toolCallingVerified: verified,
        );
        room.capabilities[actor.playerId] = DeviceAIProviderCapability(
          userId: actor.userId!,
          connectionId: actor.playerId,
          deviceSessionId: actor.deviceSessionId!,
          updatedAt: DateTime.now(),
          supportsAIHost: command.payload['supportsAIHost'] as bool? ?? false,
          providerTypes: providerTypes,
          toolCallingVerified: verified,
          autoAcceptForCampaign:
              command.payload['autoAcceptForCampaign'] as bool? ?? false,
        );
      case MultiplayerEventType.gameStarted:
        _requireManagement(room, actor, RoomPermission.start);
        await _startGame(room);
      case MultiplayerEventType.playerAction:
        await _submitAction(room, actor, command);
      case MultiplayerEventType.turnActionConfirm:
        await _confirmTurnAction(room, actor, command);
      case MultiplayerEventType.turnActionUnconfirm:
        await _unconfirmTurnAction(room, actor, command);
      case MultiplayerEventType.turnSkipPlayer:
        await _skipTurnPlayer(room, actor, command);
      case MultiplayerEventType.turnResolved:
        await _resolveHumanGmTurn(room, actor, command);
      case MultiplayerEventType.secretAction:
        await _submitAction(room, actor, command, secret: true);
      case MultiplayerEventType.playerChat:
        await _submitChat(room, actor, command);
      case MultiplayerEventType.privateMessage:
        await _submitPrivateMessage(room, actor, command);
      case MultiplayerEventType.privateRoll:
        await _privateRoll(room, actor, command);
      case MultiplayerEventType.revealInformation:
        await _revealInformation(room, actor, command);
      case MultiplayerEventType.presentationEvent:
        await _handlePresentationEvent(room, actor, command);
      case MultiplayerEventType.aiResponse:
        _requireHost(room, actor);
        await _handleAIResponse(room, actor, command);
      case MultiplayerEventType.retryAction:
        if (room.activeAction == null) throw StateError('没有等待重试的行动');
        if (actor.playerId != room.room.ownerPlayerId &&
            actor.playerId != room.activeAction!.action.playerId)
          throw StateError('无权重试');
        room.room = room.room.copyWith(
          status: MultiplayerRoomStatus.playing,
          gmWaiting: false,
          aiHostConfig: room.room.aiHostConfig.copyWith(
            status: AIHostStatus.busy,
          ),
        );
        await _commitRoom(room, MultiplayerEventType.statePatch, const {});
        _sendAIRequest(room);
      case MultiplayerEventType.pauseGame:
        _requireManagement(room, actor, RoomPermission.pause);
        room.room = room.room.copyWith(status: MultiplayerRoomStatus.paused);
        await _commitRoom(room, MultiplayerEventType.pauseGame, const {});
      case MultiplayerEventType.resumeGame:
        _requireManagement(room, actor, RoomPermission.start);
        if (room.room.aiHostConfig.status != AIHostStatus.ready)
          throw StateError('AI Host 未就绪');
        room.room = room.room.copyWith(
          status: MultiplayerRoomStatus.playing,
          gmWaiting: false,
        );
        await _commitRoom(room, MultiplayerEventType.resumeGame, const {});
        await _resumePendingTurn(room);
        await _recoverStalledTurn(room);
        if (room.activeAction != null) {
          _sendAIRequest(room);
        }
        _processNext(room);
      case MultiplayerEventType.requestSnapshot:
        final socket = room.sockets[actor.playerId];
        if (socket != null) _sendSnapshot(socket, room);
      case MultiplayerEventType.kickPlayer:
        _requireManagement(room, actor, RoomPermission.kick);
        await _kick(room, _requiredString(command.payload, 'playerId'));
      default:
        throw StateError('Unsupported command: ${command.type.name}');
    }
  }

  Future<void> _selectCharacter(
    _ServerRoom room,
    _Identity actor,
    Map<String, Object?> payload,
  ) async {
    final characterJson = payload['character'];
    if (characterJson is! Map) throw StateError('缺少角色数据');
    var character = PlayerCharacter.fromJson(
      characterJson.cast<String, Object?>(),
    );
    if (room.room.players.any(
      (p) => p.playerId != actor.playerId && p.characterId == character.id,
    )) {
      throw StateError('该角色已经被其他玩家选择');
    }
    character = PlayerCharacter.fromJson({
      ...character.toJson(),
      'playerId': actor.playerId,
    });
    if (room.room.kind == CampaignRoomKind.persistent && actor.userId != null) {
      final campaign = _social.campaignFor(
        actor.userId!,
        room.room.persistentCampaignRoomId!,
      );
      await _social.bindCharacter(
        actor.userId!,
        campaign.id,
        character.id,
        expectedRevision: campaign.revision,
      );
    }
    room.pendingCharacters[actor.playerId] = character;
    room.room = room.room.copyWith(
      players: room.room.players
          .map(
            (p) => p.playerId == actor.playerId
                ? p.copyWith(characterId: character.id)
                : p,
          )
          .toList(),
    );
    await _commitRoom(room, MultiplayerEventType.selectCharacter, {
      'playerId': actor.playerId,
      'character': character.toJson(),
    });
  }

  Future<void> _requestHost(
    _ServerRoom room,
    String playerId,
    Map<String, Object?> payload,
  ) async {
    final player = room.room.players
        .where((item) => item.playerId == playerId)
        .firstOrNull;
    if (player == null ||
        player.connectionStatus != TRPGConnectionStatus.online)
      throw StateError('只能指定在线房间成员');
    if (room.room.kind == CampaignRoomKind.persistent) {
      final capability = room.capabilities[playerId];
      if (capability == null || !capability.supportsAIHost) {
        throw StateError('该设备没有可用的 AI Provider');
      }
    }
    room.previousHostId = room.room.aiHostConfig.providerPlayerId;
    room.room = room.room.copyWith(
      aiHostConfig: AIHostConfig(
        mode: AIHostMode.selectedPlayer,
        providerPlayerId: playerId,
        providerType: payload['providerType'] as String? ?? 'openai-compatible',
        modelId: payload['modelId'] as String?,
        status: AIHostStatus.pending,
        maxRequests: (payload['maxRequests'] as num?)?.toInt() ?? 0,
        maxTokens: (payload['maxTokens'] as num?)?.toInt() ?? 0,
      ),
      gmWaiting: true,
    );
    await _commitRoom(room, MultiplayerEventType.hostRequested, {
      'providerPlayerId': playerId,
      'modelId': room.room.aiHostConfig.modelId,
      'privacyNotice': '本局由指定玩家的 AI 服务处理主持请求；API Key 不会上传服务器或广播。',
    });
  }

  Future<void> _acceptHost(
    _ServerRoom room,
    _Identity actor,
    Map<String, Object?> payload,
  ) async {
    if (room.room.aiHostConfig.providerPlayerId != actor.playerId ||
        room.room.aiHostConfig.status != AIHostStatus.pending) {
      throw StateError('没有等待你确认的主持请求');
    }
    room.room = room.room.copyWith(
      status:
          room.session != null &&
              room.room.status == MultiplayerRoomStatus.paused
          ? MultiplayerRoomStatus.playing
          : room.room.status,
      gmWaiting: false,
      aiHostConfig: room.room.aiHostConfig.copyWith(
        providerType: payload['providerType'] as String? ?? 'openai-compatible',
        modelId:
            payload['modelId'] as String? ?? room.room.aiHostConfig.modelId,
        status: AIHostStatus.ready,
        acceptedAt: DateTime.now(),
        lastHeartbeat: DateTime.now(),
      ),
    );
    if (room.session != null) {
      room.session = room.session!.copyWith(
        aiHostConfig: room.room.aiHostConfig,
        gmStateSnapshot: _createHostSnapshot(room.session!),
      );
    }
    final eventType =
        room.previousHostId != null && room.previousHostId != actor.playerId
        ? MultiplayerEventType.hostChanged
        : MultiplayerEventType.hostAccepted;
    await _commitRoom(room, eventType, {
      'previousProviderPlayerId': room.previousHostId,
      'providerPlayerId': actor.playerId,
      'modelId': room.room.aiHostConfig.modelId,
    });
    if (room.room.kind == CampaignRoomKind.persistent && actor.userId != null) {
      await _social.recordHistory(
        room.room.persistentCampaignRoomId!,
        type: 'ai_host_changed',
        message: '新的 AI Host 已确认接管',
        actorUserId: actor.userId!,
        metadata: {'providerPlayerId': actor.playerId},
      );
    }
    room.previousHostId = null;
    await _resumePendingTurn(room);
    await _recoverStalledTurn(room);
    if (room.activeAction != null) {
      _sendAIRequest(room);
    } else {
      _processNext(room);
    }
  }

  /// Rebuild the in-memory AI queue after the local server process was
  /// restarted while a turn was resolving.  Room JSON deliberately stores the
  /// authoritative turn/session, but the transient prompt queue is recreated
  /// from that state when the host comes back online.
  Future<void> _recoverStalledTurn(_ServerRoom room) async {
    if (room.activeAction != null || room.session == null) return;
    final turn = room.room.currentTurn;
    if (turn == null ||
        (turn.phase != MultiplayerTurnPhase.resolving &&
            turn.phase != MultiplayerTurnPhase.gmResponding))
      return;
    final actions = turn.expectedPlayerIds
        .map((id) => turn.playerActions[id])
        .whereType<PlayerTurnAction>()
        .toList();
    if (actions.isEmpty) return;

    // If the crash happened before _beginTurnResolution committed the
    // session, let the normal path perform checks and append the action log.
    final actionIds = room.session!.eventLog
        .where((event) => event.type == TRPGEventType.playerAction)
        .map((event) => event.id)
        .toSet();
    if (turn.phase == MultiplayerTurnPhase.resolving &&
        actions.any((action) => !actionIds.contains(action.actionId))) {
      await _beginTurnResolution(room);
      return;
    }

    final bundle = RoundActionBundle(
      turnId: turn.turnId,
      roundNumber: turn.roundNumber,
      actions: actions,
      sceneState: room.session!.worldState.currentScene.toJson(),
      combatState: room.session!.ruleState.toJson(),
      partyState: {
        'characters': room.session!.playerCharacters
            .map((value) => value.toJson())
            .toList(),
      },
      timestamp: DateTime.now(),
    );
    final structured = _formatRoundActionBundle(bundle);
    room.activeAction = _ActiveAction(
      action: _QueuedAction(
        actionId: 'turn-${turn.turnId}',
        playerId: room.room.ownerPlayerId,
        characterId: actions.first.characterId,
        content: structured,
        createdAt: DateTime.now(),
        turnId: turn.turnId,
        roundBundle: bundle,
      ),
      messages: _prompts.build(
        session: room.session!,
        action: structured,
        actingPlayerId: room.room.ownerPlayerId,
        multiplayerBundle: bundle,
      ),
    );
    room.room = room.room.copyWith(
      gmWaiting: false,
      aiHostConfig: room.room.aiHostConfig.copyWith(status: AIHostStatus.busy),
      currentTurn: turn.phase == MultiplayerTurnPhase.gmResponding
          ? turn
          : turn.copyWith(phase: MultiplayerTurnPhase.gmResponding),
    );
    await _commitRoom(room, MultiplayerEventType.gmProcessing, {
      'actionId': room.activeAction!.action.actionId,
      'turnId': turn.turnId,
      'recovered': true,
    });
  }

  /// Re-arm the five-second settlement timer after a process restart or a
  /// paused-room resume. Older snapshots may have all confirmations but no
  /// deadline, so they receive a fresh short window instead of hanging.
  Future<void> _resumePendingTurn(_ServerRoom room) async {
    final turn = room.room.currentTurn;
    if (room.room.status != MultiplayerRoomStatus.playing ||
        turn == null ||
        turn.phase != MultiplayerTurnPhase.collecting ||
        !turn.allConfirmed)
      return;
    final deadline =
        turn.settlementDeadline ?? DateTime.now().add(config.settlementGrace);
    if (turn.settlementDeadline == null) {
      room.room = room.room.copyWith(
        currentTurn: turn.copyWith(settlementDeadline: deadline),
      );
      await _commitRoom(room, MultiplayerEventType.turnAllConfirmed, {
        'turnId': turn.turnId,
        'recovered': true,
        'settlementDeadline': deadline.toIso8601String(),
      });
    }
    _scheduleTurnSettlement(room, turn.turnId, deadline);
  }

  Future<void> _declineHost(_ServerRoom room, _Identity actor) async {
    if (room.room.aiHostConfig.providerPlayerId != actor.playerId)
      throw StateError('没有等待你确认的主持请求');
    room.room = room.room.copyWith(
      gmWaiting: true,
      aiHostConfig: room.room.aiHostConfig.copyWith(
        status: AIHostStatus.declined,
      ),
    );
    await _commitRoom(room, MultiplayerEventType.hostDeclined, {
      'providerPlayerId': actor.playerId,
    });
  }

  Future<void> _startGame(_ServerRoom room) async {
    if (room.room.status != MultiplayerRoomStatus.lobby)
      throw StateError('房间不在 Lobby');
    if (room.room.players
        .where((player) => player.role != TRPGPlayerRole.humanGm)
        .any((player) => !player.isReady || player.characterId == null))
      throw StateError('所有玩家必须 Ready 并选择角色');
    if (room.room.gmMode != AIHostMode.humanGm &&
        room.room.aiHostConfig.status != AIHostStatus.ready)
      throw StateError('AI Host 尚未就绪');
    final session = _createServerSession(room);
    room.session = session;
    room.room = room.room.copyWith(
      status: MultiplayerRoomStatus.playing,
      sessionId: session.id,
      aiHostConfig: room.room.aiHostConfig,
    );
    if (room.room.kind == CampaignRoomKind.persistent) {
      final participantUserIds = _tokens.values
          .where(
            (value) =>
                value.roomId == room.room.roomId &&
                value.userId != null &&
                room.sockets.containsKey(value.playerId),
          )
          .map((value) => value.userId!)
          .toSet()
          .toList();
      await _social.startPlaySession(
        room.room.persistentCampaignRoomId!,
        sessionId: session.id,
        participantUserIds: participantUserIds,
        startingRevision: room.room.revision,
      );
    }
    await _commitSession(room, MultiplayerEventType.gameStarted, {
      'sessionId': session.id,
    });
    if (room.room.gmMode != AIHostMode.humanGm) {
      final holyGrail = const HolyGrailWarManager().isHolyGrailCampaign(
        session,
      );
      room.pendingActions.add(
        _QueuedAction(
          actionId: 'opening-${session.id}',
          playerId: room.room.ownerPlayerId,
          characterId: room.room.players
              .firstWhere((player) => player.characterId != null)
              .characterId!,
          content: holyGrail
              ? '圣杯战争的御主能力、个人卷入事件与英灵契约已经由服务器生成并分别私发。请只生成不泄露任何个人属性、英灵真名、宝具、位置或私信内容的公共召唤之夜开场，并引导所有玩家开始第一轮公开或秘密行动。'
              : '请根据当前剧本和全部玩家角色生成多人跑团开场。',
          createdAt: DateTime.now(),
          isOpening: true,
        ),
      );
      _processNext(room);
    } else {
      await _startNextTurn(room);
    }
  }

  TRPGSession _createServerSession(_ServerRoom room) {
    final campaignDocument = room.campaignSnapshot != null
        ? CampaignDocument.fromJson(room.campaignSnapshot!)
        : room.room.campaignId == 'mist_harbor_test'
        ? const CampaignTemplateService().mistHarbor()
        : CampaignDocument.fromLegacy(
            const CampaignService().getById(room.room.campaignId),
          );
    final campaign = campaignDocument.toLegacy();
    final holyGrail =
        campaignDocument.campaignType == CampaignType.holyGrailWar;
    final now = DateTime.now();
    final characters = room.room.players
        .where((player) => player.role != TRPGPlayerRole.humanGm)
        .map((player) => room.pendingCharacters[player.playerId]!)
        .toList();
    final openingBriefing = const CampaignOpeningBriefing().build(
      campaign: campaign,
      document: campaignDocument,
      playerCharacters: characters.map((character) => character.name).toList(),
    );
    final initialLocations = {
      for (final character in characters)
        character.id: CharacterLocationState(
          characterId: character.id,
          sceneId: holyGrail ? 'hgw_summoning_night' : 'mist_harbor_arrival',
          locationId: holyGrail ? 'fuyuki_city' : 'old_harbor',
          enteredAt: now,
        ),
    };
    final session = TRPGSession(
      id: _uuid.v4(),
      title: room.room.roomName,
      mode: TRPGMode.multiplayer,
      createdAt: now,
      updatedAt: now,
      lastPlayedAt: now,
      status: TRPGSessionStatus.active,
      campaignId: campaign.id,
      ruleSystemId: room.room.ruleSystemId,
      roomOwnerPlayerId: room.room.ownerPlayerId,
      players: room.room.players,
      playerCharacters: characters,
      characterLocations: initialLocations,
      partyGroups: const PartyGroupManager().rebuild(
        initialLocations,
        now: now,
      ),
      currentScene: campaign.opening,
      worldState: holyGrail
          ? const WorldState(
              time: '召唤之夜',
              weather: '阴云与灵脉震荡',
              location: '冬木市',
              currentScene: SceneState(
                sceneId: 'hgw_summoning_night',
                locationId: 'fuyuki_city',
                title: '冬木市 · 召唤之夜',
                description: '七处互不相通的召唤阵在同一夜启动。',
                atmosphere: '隐秘、紧张、魔力涌动',
              ),
            )
          : const WorldState(
              time: '午夜',
              weather: '细雨与浓雾',
              location: '雾港旧港区',
              currentScene: SceneState(
                sceneId: 'mist_harbor_arrival',
                locationId: 'old_harbor',
                title: '雾港旧港区',
                description: '浓雾笼罩码头，封锁线在雨中发亮。',
                atmosphere: '潮湿、警戒、未知',
                npcIds: ['guard_hale'],
              ),
              npcs: [
                NPCState(
                  npcId: 'guard_hale',
                  name: '守卫哈勒',
                  locationId: 'old_harbor',
                  knownToPlayer: true,
                ),
              ],
            ),
      campaignState: CampaignState(
        currentLocationId: holyGrail ? 'fuyuki_city' : 'old_harbor',
        activeQuests: holyGrail
            ? const ['hgw_summon']
            : const ['missing_investigator'],
        quests: holyGrail
            ? [
                QuestState(
                  questId: 'hgw_summon',
                  title: '召唤之夜',
                  description: '确认自己的能力与英灵契约，然后在不泄密的前提下开始行动。',
                  objectives: const [
                    QuestObjective(id: 'read_dossier', description: '查看私密档案'),
                    QuestObjective(id: 'first_action', description: '决定第一轮行动'),
                  ],
                  status: QuestStatus.active,
                  discoveredAt: now,
                ),
              ]
            : [
                QuestState(
                  questId: 'missing_investigator',
                  title: '寻找失踪的调查员',
                  description: '查清调查员在旧港失踪的原因。',
                  objectives: const [
                    QuestObjective(id: 'find_clue', description: '找到旧港线索'),
                  ],
                  status: QuestStatus.active,
                  discoveredAt: now,
                ),
              ],
        clues: holyGrail
            ? const []
            : const [
                ClueState(
                  clueId: 'muddy_bootprints',
                  name: '泥泞脚印',
                  description: '指向仓库侧门的脚印。',
                ),
              ],
      ),
      gmState: GMState(privateNotes: campaign.secrets.join('\n')),
      aiHostConfig: room.room.aiHostConfig,
      immersionState: TRPGImmersionState(
        campaignSnapshot: campaignDocument.toJson(),
        npcInstances: campaignDocument.npcs
            .map(
              (npc) => NPCInstanceState(
                npcId: npc.npcId,
                sourceCharacterId: npc.sourceCharacterId,
                relationship: npc.relationship,
                locationId: npc.locationId,
                knownToPlayers: npc.knownToPlayers,
                inventory: npc.inventory,
              ),
            )
            .toList(),
        timeline: [
          SessionTimelineEntry(
            id: _uuid.v4(),
            title: '多人开团导语',
            detail: openingBriefing,
            createdAt: now,
          ),
        ],
        allowPlayerPrivateChat: room.allowPlayerPrivateChat,
      ),
      chatHistory: [
        TRPGMessage(
          id: _uuid.v4(),
          messageType: TRPGMessageType.gmMessage,
          content: openingBriefing,
          createdAt: now,
        ),
      ],
      eventLog: [
        TRPGEvent(
          id: _uuid.v4(),
          type: TRPGEventType.sceneChange,
          timestamp: now,
          payload: {
            'scene': {
              'id': holyGrail ? 'hgw_summoning_night' : 'mist_harbor_arrival',
              'title': holyGrail ? '冬木市 · 召唤之夜' : '雾港旧港区',
              'description': campaign.opening,
            },
          },
        ),
      ],
    );
    final withGeneratedWorld = const WorldGenerationRuntime().initializeSession(
      session,
      campaignDocument,
    );
    final withLivingNpcs = const LivingNPCService().ensureInitialized(
      withGeneratedWorld,
    );
    final withFactions = const FactionManager().ensureInitialized(
      withLivingNpcs,
    );
    const holyGrailManager = HolyGrailWarManager();
    return holyGrailManager.prepareOpening(
      holyGrailManager.initialize(withFactions, campaign: campaignDocument),
    );
  }

  GMStateSnapshot _createHostSnapshot(TRPGSession session) => GMStateSnapshot(
    campaignSummary: session.gmState.campaignSummary,
    currentScene: session.currentScene,
    worldStateSummary:
        '${session.worldState.time} ${session.worldState.weather} ${session.worldState.location}'
            .trim(),
    playersSummary: session.playerCharacters
        .map((item) => '${item.name} HP ${item.hp}/${item.maxHp}')
        .join('\n'),
    activeQuestSummary: session.campaignState.activeQuests.join('\n'),
    hiddenGmNotes: session.gmState.privateNotes,
    recentEvents: session.eventLog.reversed
        .take(20)
        .map((item) => item.type.name)
        .toList()
        .reversed
        .toList(),
    recentMessages: session.chatHistory.reversed
        .take(20)
        .map((item) => item.content)
        .toList()
        .reversed
        .toList(),
    longTermMemory: session.memoryState.entries
        .where((memory) => memory.importance >= 6 || memory.pinned)
        .take(80)
        .map(
          (memory) => memory.summary.isEmpty ? memory.content : memory.summary,
        )
        .toList(),
    npcMemorySummaries: session.memoryState.companionSummaries,
    worldMemorySummary: session.memoryState.sessionSummary,
  );

  Future<void> _submitAction(
    _ServerRoom room,
    _Identity actor,
    MultiplayerEnvelope command, {
    bool secret = false,
  }) async {
    if (room.session?.ruleState.combatActive != true &&
        room.room.currentTurn?.mode == MultiplayerTurnMode.freeformGroup) {
      await _confirmTurnAction(
        room,
        actor,
        MultiplayerEnvelope(
          type: MultiplayerEventType.turnActionConfirm,
          commandId: command.commandId,
          payload: {
            ...command.payload,
            'turnId': room.room.currentTurn!.turnId,
            'secret': secret,
            'isPass': false,
          },
        ),
      );
      return;
    }
    if (room.room.status != MultiplayerRoomStatus.playing)
      throw StateError('当前不能提交行动');
    final player = room.room.players.firstWhere(
      (p) => p.playerId == actor.playerId,
    );
    if (player.characterId == null) throw StateError('尚未选择角色');
    final content = _requiredString(command.payload, 'content');
    final actionId =
        command.payload['actionId'] as String? ??
        command.commandId ??
        _uuid.v4();
    if (room.session!.chatHistory.any((m) => m.id == actionId) ||
        room.session!.immersionState.timeline.any((e) => e.id == actionId) ||
        room.pendingActions.any((a) => a.actionId == actionId))
      return;
    final action = _QueuedAction(
      actionId: actionId,
      playerId: actor.playerId,
      characterId: player.characterId!,
      content: content,
      createdAt: DateTime.now(),
      visibility: secret
          ? MultiplayerVisibility.player
          : MultiplayerVisibility.public,
      recipientPlayerIds: secret ? [actor.playerId] : const [],
    );
    room.session = room.session!.copyWith(
      chatHistory: secret
          ? room.session!.chatHistory
          : [
              ...room.session!.chatHistory,
              TRPGMessage(
                id: actionId,
                messageType: TRPGMessageType.playerMessage,
                content: content,
                playerId: actor.playerId,
                createdAt: action.createdAt,
              ),
            ],
      eventLog: secret
          ? room.session!.eventLog
          : [
              ...room.session!.eventLog,
              TRPGEvent(
                id: _uuid.v4(),
                type: TRPGEventType.playerAction,
                timestamp: action.createdAt,
                actorId: actor.playerId,
                payload: {'actionId': actionId, 'content': content},
              ),
            ],
      immersionState: secret
          ? room.session!.immersionState.copyWith(
              timeline: [
                ...room.session!.immersionState.timeline,
                SessionTimelineEntry(
                  id: actionId,
                  title: '秘密行动',
                  detail: content,
                  createdAt: action.createdAt,
                  visibility: InformationVisibility.playerPrivate,
                  ownerPlayerIds: [actor.playerId],
                ),
              ],
            )
          : room.session!.immersionState,
      updatedAt: action.createdAt,
      lastPlayedAt: action.createdAt,
    );
    if (secret) {
      final privateMemory = MemoryEntry(
        id: _uuid.v4(),
        sessionId: room.session!.id,
        type: MemoryType.privateMemory,
        title: '玩家秘密行动',
        content: content,
        importance: 6,
        confidence: MemoryConfidence.confirmed,
        createdAt: action.createdAt,
        updatedAt: action.createdAt,
        sourceEventIds: [actionId],
        relatedEntityIds: [actor.playerId, player.characterId!],
        tags: const ['secret_action'],
        visibility: MemoryVisibility.playerPrivate,
        ownerPlayerId: actor.playerId,
        canonPriority: CanonPriority.confirmedEvent,
      );
      room.session = room.session!.copyWith(
        memoryState: room.session!.memoryState.copyWith(
          entries: [...room.session!.memoryState.entries, privateMemory],
        ),
      );
    }
    room.pendingActions.add(action);
    await _commitSession(
      room,
      secret
          ? MultiplayerEventType.secretAction
          : MultiplayerEventType.playerAction,
      {
        'actionId': actionId,
        'playerId': actor.playerId,
        'content': content,
        'queuePosition':
            room.pendingActions.length + (room.activeAction == null ? 0 : 1),
      },
      visibility: action.visibility,
      recipientPlayerIds: action.recipientPlayerIds,
    );
    _processNext(room);
  }

  List<String> _expectedTurnPlayers(_ServerRoom room) => room.room.players
      .where(
        (player) =>
            player.role != TRPGPlayerRole.humanGm &&
            player.characterId != null &&
            player.connectionStatus == TRPGConnectionStatus.online,
      )
      .map((player) => player.playerId)
      .toList();

  Future<void> _startNextTurn(_ServerRoom room) async {
    if (room.room.status != MultiplayerRoomStatus.playing) return;
    room.settlementTimer?.cancel();
    room.settlementTimer = null;
    final previous = room.room.currentTurn;
    final mode = room.session?.ruleState.combatActive == true
        ? MultiplayerTurnMode.combatInitiative
        : MultiplayerTurnMode.freeformGroup;
    final turn = MultiplayerTurn(
      turnId: _uuid.v4(),
      roundNumber: (previous?.roundNumber ?? 0) + 1,
      startedAt: DateTime.now(),
      expectedPlayerIds: _expectedTurnPlayers(room),
      mode: mode,
    );
    room.room = room.room.copyWith(currentTurn: turn);
    await _commitRoom(room, MultiplayerEventType.turnStarted, {
      'turnId': turn.turnId,
      'roundNumber': turn.roundNumber,
      'expectedPlayerIds': turn.expectedPlayerIds,
      'mode': turn.mode.name,
    });
  }

  Future<void> _confirmTurnAction(
    _ServerRoom room,
    _Identity actor,
    MultiplayerEnvelope command,
  ) async {
    if (room.room.status != MultiplayerRoomStatus.playing) {
      throw StateError('当前不能确认回合行动');
    }
    final turn = room.room.currentTurn;
    if (turn == null || turn.mode != MultiplayerTurnMode.freeformGroup) {
      throw StateError('当前不是多人行动收集回合');
    }
    if (command.payload['turnId'] != turn.turnId) {
      throw StateError('行动属于旧回合，请重新输入');
    }
    if (!turn.expectedPlayerIds.contains(actor.playerId)) {
      throw StateError('你不是本回合需要行动的玩家');
    }
    final existing = turn.playerActions[actor.playerId];
    final actionId =
        command.payload['actionId'] as String? ??
        command.commandId ??
        _uuid.v4();
    if (existing?.actionId == actionId && existing?.confirmed == true) return;
    if (turn.phase != MultiplayerTurnPhase.collecting) {
      throw StateError('本回合已经锁定，不能再修改行动');
    }
    if (existing?.confirmed == true) {
      throw StateError('请先点击“修改行动”再重新确认');
    }
    final player = room.room.players.firstWhere(
      (value) => value.playerId == actor.playerId,
    );
    final character = room.session!.playerCharacters.firstWhere(
      (value) => value.id == player.characterId,
    );
    final content = (command.payload['content'] as String? ?? '').trim();
    final isPass = command.payload['isPass'] == true || content.isEmpty;
    final now = DateTime.now();
    final action = PlayerTurnAction(
      actionId: actionId,
      turnId: turn.turnId,
      playerId: actor.playerId,
      playerDisplayName: player.displayName,
      characterId: character.id,
      characterName: character.name,
      content: isPass ? '' : content,
      confirmed: true,
      isPass: isPass,
      submittedAt: now,
      confirmedAt: now,
      metadata: {
        'secret': command.payload['secret'] == true,
        'locationId':
            character.metadata['locationId'] ??
            room.session!.worldState.currentScene.locationId,
      },
    );
    final actions = {...turn.playerActions, actor.playerId: action};
    final confirmed = {...turn.confirmedPlayerIds, actor.playerId}.toList();
    var next = turn.copyWith(
      playerActions: actions,
      confirmedPlayerIds: confirmed,
    );
    final allConfirmed = next.allConfirmed;
    if (allConfirmed) {
      final deadline = DateTime.now().add(config.settlementGrace);
      next = next.copyWith(settlementDeadline: deadline);
      _scheduleTurnSettlement(room, turn.turnId, deadline);
    }
    room.room = room.room.copyWith(currentTurn: next);
    await _commitRoom(room, MultiplayerEventType.turnPlayerStatus, {
      'turnId': turn.turnId,
      'playerId': actor.playerId,
      'confirmed': true,
      'isPass': isPass,
      'confirmedCount': confirmed.length,
      'expectedCount': turn.expectedPlayerIds.length,
    });
  }

  Future<void> _unconfirmTurnAction(
    _ServerRoom room,
    _Identity actor,
    MultiplayerEnvelope command,
  ) async {
    final turn = room.room.currentTurn;
    if (turn == null || command.payload['turnId'] != turn.turnId) {
      throw StateError('回合不存在或已经结束');
    }
    if (turn.phase != MultiplayerTurnPhase.collecting) {
      throw StateError('主持人已经开始结算，不能撤回');
    }
    final action = turn.playerActions[actor.playerId];
    if (action == null || !action.confirmed) return;
    room.room = room.room.copyWith(
      currentTurn: turn.copyWith(
        playerActions: {
          ...turn.playerActions,
          actor.playerId: action.copyWith(confirmed: false),
        },
        confirmedPlayerIds: turn.confirmedPlayerIds
            .where((id) => id != actor.playerId)
            .toList(),
        settlementDeadline: null,
      ),
    );
    room.settlementTimer?.cancel();
    room.settlementTimer = null;
    await _commitRoom(room, MultiplayerEventType.turnPlayerStatus, {
      'turnId': turn.turnId,
      'playerId': actor.playerId,
      'confirmed': false,
    });
  }

  Future<void> _skipTurnPlayer(
    _ServerRoom room,
    _Identity actor,
    MultiplayerEnvelope command,
  ) async {
    _requireManagement(room, actor, RoomPermission.pause);
    final turn = room.room.currentTurn;
    if (turn == null || turn.phase != MultiplayerTurnPhase.collecting) {
      throw StateError('当前回合不能设置跳过');
    }
    final targetId = _requiredString(command.payload, 'playerId');
    if (!turn.expectedPlayerIds.contains(targetId)) {
      throw StateError('目标玩家不在本回合中');
    }
    final target = room.room.players.firstWhere(
      (value) => value.playerId == targetId,
    );
    final character = room.session!.playerCharacters.firstWhere(
      (value) => value.id == target.characterId,
    );
    final now = DateTime.now();
    final action = PlayerTurnAction(
      actionId: _uuid.v4(),
      turnId: turn.turnId,
      playerId: targetId,
      playerDisplayName: target.displayName,
      characterId: character.id,
      characterName: character.name,
      content: '',
      confirmed: true,
      isPass: true,
      submittedAt: now,
      confirmedAt: now,
      metadata: const {'hostSkipped': true},
    );
    var next = turn.copyWith(
      playerActions: {...turn.playerActions, targetId: action},
      confirmedPlayerIds: {...turn.confirmedPlayerIds, targetId}.toList(),
    );
    final allConfirmed = next.allConfirmed;
    if (allConfirmed) {
      final deadline = DateTime.now().add(config.settlementGrace);
      next = next.copyWith(settlementDeadline: deadline);
      _scheduleTurnSettlement(room, turn.turnId, deadline);
    }
    room.room = room.room.copyWith(currentTurn: next);
    await _commitRoom(room, MultiplayerEventType.turnPlayerStatus, {
      'turnId': turn.turnId,
      'playerId': targetId,
      'confirmed': true,
      'isPass': true,
      'hostSkipped': true,
    });
  }

  void _scheduleTurnSettlement(
    _ServerRoom room,
    String turnId,
    DateTime deadline,
  ) {
    room.settlementTimer?.cancel();
    final delay = deadline.difference(DateTime.now());
    room.settlementTimer = Timer(
      delay.isNegative ? Duration.zero : delay,
      () => unawaited(_finalizeTurnSettlement(room, turnId)),
    );
  }

  Future<void> _finalizeTurnSettlement(_ServerRoom room, String turnId) async {
    final turn = room.room.currentTurn;
    if (turn == null ||
        turn.turnId != turnId ||
        turn.phase != MultiplayerTurnPhase.collecting ||
        !turn.allConfirmed) {
      return;
    }
    final deadline = turn.settlementDeadline;
    if (deadline != null && DateTime.now().isBefore(deadline)) {
      _scheduleTurnSettlement(room, turnId, deadline);
      return;
    }
    room.settlementTimer = null;
    room.room = room.room.copyWith(
      currentTurn: turn.copyWith(
        phase: MultiplayerTurnPhase.resolving,
        resolutionRequestId: '${turn.turnId}:resolve',
        settlementDeadline: null,
      ),
    );
    await _commitRoom(room, MultiplayerEventType.turnResolving, {
      'turnId': turn.turnId,
      'roundNumber': turn.roundNumber,
    });
    await _beginTurnResolution(room);
  }

  Future<void> _beginTurnResolution(_ServerRoom room) async {
    final turn = room.room.currentTurn;
    if (turn == null || turn.phase != MultiplayerTurnPhase.resolving) return;
    if (room.activeAction != null ||
        room.resolvingTurnIds.contains(turn.turnId)) {
      return;
    }
    room.resolvingTurnIds.add(turn.turnId);
    final actions = turn.expectedPlayerIds
        .map((id) => turn.playerActions[id])
        .whereType<PlayerTurnAction>()
        .toList();
    final now = DateTime.now();
    final bundle = RoundActionBundle(
      turnId: turn.turnId,
      roundNumber: turn.roundNumber,
      actions: actions,
      sceneState: room.session!.worldState.currentScene.toJson(),
      combatState: room.session!.ruleState.toJson(),
      partyState: {
        'characters': room.session!.playerCharacters
            .map((value) => value.toJson())
            .toList(),
      },
      timestamp: now,
    );
    room.session = room.session!.copyWith(
      chatHistory: [
        ...room.session!.chatHistory,
        ...actions
            .where((action) => action.metadata['secret'] != true)
            .map(
              (action) => TRPGMessage(
                id: action.actionId,
                messageType: TRPGMessageType.playerMessage,
                content: action.isPass ? '本回合保持观察。' : action.content,
                playerId: action.playerId,
                createdAt: action.submittedAt,
              ),
            ),
      ],
      eventLog: [
        ...room.session!.eventLog,
        ...actions.map(
          (action) => TRPGEvent(
            id: action.actionId,
            type: TRPGEventType.playerAction,
            timestamp: action.submittedAt,
            actorId: action.playerId,
            payload: {
              'turnId': turn.turnId,
              'actionId': action.actionId,
              'playerId': action.playerId,
              'characterId': action.characterId,
              'characterName': action.characterName,
              'content': action.content,
              'isPass': action.isPass,
              'visibility': action.metadata['secret'] == true
                  ? RollVisibility.playerPrivate.name
                  : RollVisibility.public.name,
              'visibilityPlayerIds': action.metadata['secret'] == true
                  ? [action.playerId]
                  : const <String>[],
            },
            visibleToAi: true,
          ),
        ),
      ],
      updatedAt: now,
      lastPlayedAt: now,
    );
    final activeActions = actions.where((value) => !value.isPass).toList();
    room.session = _checks
        .resolveGroup(
          session: room.session!,
          actionsByPlayer: {
            for (final action in activeActions) action.playerId: action.content,
          },
          actionIdsByPlayer: {
            for (final action in activeActions)
              action.playerId: action.actionId,
          },
          characterIdsByPlayer: {
            for (final action in activeActions)
              action.playerId: action.characterId,
          },
          targetIdsByPlayer: {
            for (final action in activeActions)
              if (action.metadata['targetId'] is String)
                action.playerId: action.metadata['targetId'] as String,
          },
          visibilityByPlayer: {
            for (final action in activeActions)
              action.playerId: action.metadata['secret'] == true
                  ? RollVisibility.playerPrivate
                  : RollVisibility.public,
          },
          turnId: turn.turnId,
        )
        .session;
    room.room = room.room.copyWith(
      currentTurn: turn.copyWith(phase: MultiplayerTurnPhase.gmResponding),
    );
    await _commitSession(room, MultiplayerEventType.turnAllConfirmed, {
      'turnId': turn.turnId,
      'roundNumber': turn.roundNumber,
      'actionCount': actions.length,
    });
    if (room.room.gmMode == AIHostMode.humanGm) return;
    final structured = _formatRoundActionBundle(bundle);
    room.pendingActions.add(
      _QueuedAction(
        actionId: 'turn-${turn.turnId}',
        playerId: room.room.ownerPlayerId,
        characterId: actions.first.characterId,
        content: structured,
        createdAt: now,
        turnId: turn.turnId,
        roundBundle: bundle,
      ),
    );
    _processNext(room);
  }

  String _formatRoundActionBundle(RoundActionBundle bundle) {
    final buffer = StringBuffer('【行动轮次 ${bundle.roundNumber}】\n');
    for (var index = 0; index < bundle.actions.length; index++) {
      final action = bundle.actions[index];
      buffer
        ..writeln('\n${index + 1}.')
        ..writeln('playerId: ${action.playerId}')
        ..writeln('玩家：${action.playerDisplayName}')
        ..writeln('characterId: ${action.characterId}')
        ..writeln('角色：${action.characterName}')
        ..writeln('位置：${action.metadata['locationId'] ?? '未知'}')
        ..writeln('actionId: ${action.actionId}')
        ..writeln(action.isPass ? '行动：本回合无主动行动，保持观察。' : '行动：${action.content}');
    }
    return buffer.toString();
  }

  Future<void> _submitPrivateMessage(
    _ServerRoom room,
    _Identity actor,
    MultiplayerEnvelope command,
  ) async {
    final content = _requiredString(command.payload, 'content');
    final toGm = command.payload['toGm'] as bool? ?? false;
    final recipients =
        (command.payload['recipientPlayerIds'] as List? ?? const [])
            .map((value) => value.toString())
            .toSet();
    if (!toGm && !room.session!.immersionState.allowPlayerPrivateChat) {
      throw StateError('本房间未允许玩家私聊');
    }
    final roomIds = room.room.players.map((value) => value.playerId).toSet();
    if (!recipients.every(roomIds.contains)) throw StateError('私聊目标不在当前房间');
    recipients.add(actor.playerId);
    final message = TRPGPrivateMessage(
      id: command.commandId ?? _uuid.v4(),
      senderId: actor.playerId,
      recipientIds: recipients.toList(),
      content: content,
      createdAt: DateTime.now(),
      toGm: toGm,
    );
    room.session = room.session!.copyWith(
      immersionState: room.session!.immersionState.copyWith(
        privateMessages: [
          ...room.session!.immersionState.privateMessages,
          message,
        ],
      ),
    );
    final authorized = {...recipients};
    final humanGm = room.room.players
        .where((value) => value.role == TRPGPlayerRole.humanGm)
        .firstOrNull;
    if (toGm && humanGm != null) authorized.add(humanGm.playerId);
    await _commitSession(
      room,
      MultiplayerEventType.privateMessage,
      {'message': message.toJson()},
      visibility: MultiplayerVisibility.selectedPlayers,
      recipientPlayerIds: authorized.toList(),
    );
  }

  Future<void> _privateRoll(
    _ServerRoom room,
    _Identity actor,
    MultiplayerEnvelope command,
  ) async {
    final sides = ((command.payload['sides'] as num?)?.toInt() ?? 20);
    final formula = command.payload['formula']?.toString().trim();
    if ((formula == null || formula.isEmpty) &&
        !DiceService.supportedSides.contains(sides)) {
      throw StateError('不支持 D$sides');
    }
    final reason = command.payload['reason']?.toString() ?? '';
    final roll = _dice.rollResult(
      formula: formula == null || formula.isEmpty ? '1D$sides' : formula,
      playerId: actor.playerId,
      action: '私密投骰',
      reason: reason,
      visibility: DiceVisibility.playerPrivate,
      ownerPlayerIds: [actor.playerId],
    );
    final now = DateTime.now();
    final history = [...room.session!.ruleState.diceHistory2, roll];
    room.session = room.session!.copyWith(
      ruleState: room.session!.ruleState.copyWith(
        diceHistory2: history.length > 50
            ? history.sublist(history.length - 50)
            : history,
      ),
      immersionState: room.session!.immersionState.copyWith(
        timeline: [
          ...room.session!.immersionState.timeline,
          SessionTimelineEntry(
            id: command.commandId ?? _uuid.v4(),
            title: '私密投骰 ${roll.diceFormula} = ${roll.finalResult}',
            detail: reason,
            createdAt: now,
            visibility: InformationVisibility.playerPrivate,
            ownerPlayerIds: [actor.playerId],
          ),
        ],
      ),
    );
    await _commitSession(
      room,
      MultiplayerEventType.privateRoll,
      {'roll': roll.toJson(), 'reason': reason},
      visibility: MultiplayerVisibility.player,
      recipientPlayerIds: [actor.playerId],
    );
  }

  Future<void> _revealInformation(
    _ServerRoom room,
    _Identity actor,
    MultiplayerEnvelope command,
  ) async {
    final id = _requiredString(command.payload, 'knowledgeId');
    final knowledge = room.session!.immersionState.privateKnowledge
        .where((value) => value.id == id)
        .firstOrNull;
    if (knowledge == null) throw StateError('私人信息不存在');
    if (!knowledge.ownerPlayerIds.contains(actor.playerId))
      throw StateError('你无权公开该信息');
    room.session = room.session!.copyWith(
      immersionState: room.session!.immersionState.copyWith(
        privateKnowledge: room.session!.immersionState.privateKnowledge
            .map(
              (value) => value.id == id
                  ? value.copyWith(
                      visibility: InformationVisibility.public,
                      ownerPlayerIds: const [],
                      revealed: true,
                    )
                  : value,
            )
            .toList(),
        timeline: [
          ...room.session!.immersionState.timeline,
          SessionTimelineEntry(
            id: _uuid.v4(),
            title: '公开线索：${knowledge.title}',
            detail: knowledge.content,
            createdAt: DateTime.now(),
          ),
        ],
      ),
    );
    await _commitSession(room, MultiplayerEventType.revealInformation, {
      'knowledge': {
        ...knowledge.toJson(),
        'visibility': InformationVisibility.public.name,
      },
    });
  }

  Future<void> _handlePresentationEvent(
    _ServerRoom room,
    _Identity actor,
    MultiplayerEnvelope command,
  ) async {
    final actorPlayer = room.room.players
        .where((value) => value.playerId == actor.playerId)
        .firstOrNull;
    if (actor.playerId != room.room.ownerPlayerId &&
        actorPlayer?.role != TRPGPlayerRole.humanGm) {
      throw StateError('只有 GM 或房主可以同步演出事件');
    }
    final raw = command.payload['event'];
    if (raw is! Map) throw const FormatException('演出事件格式无效');
    final session = room.session;
    if (session == null) throw StateError('跑团尚未开始');
    final event = raw.cast<String, Object?>();
    final sequence = (event['sequenceNumber'] as num?)?.toInt() ?? 0;
    if (sequence <= session.presentationState.sequenceNumber) return;
    final state = event['state'] is Map
        ? CurrentPresentationState.fromJson(
            (event['state'] as Map).cast<String, Object?>(),
          )
        : session.presentationState.copyWith(sequenceNumber: sequence);
    room.session = session.copyWith(presentationState: state);
    await _commitSession(room, MultiplayerEventType.presentationEvent, {
      'event': event,
    });
  }

  Future<void> _submitChat(
    _ServerRoom room,
    _Identity actor,
    MultiplayerEnvelope command,
  ) async {
    final content = _requiredString(command.payload, 'content');
    final now = DateTime.now();
    room.session = room.session?.copyWith(
      chatHistory: [
        ...room.session!.chatHistory,
        TRPGMessage(
          id: command.commandId ?? _uuid.v4(),
          messageType: TRPGMessageType.playerMessage,
          content: '/ooc $content',
          playerId: actor.playerId,
          createdAt: now,
        ),
      ],
    );
    await _commitSession(room, MultiplayerEventType.playerChat, {
      'playerId': actor.playerId,
      'content': content,
    });
  }

  void _processNext(_ServerRoom room) {
    if (room.activeAction != null ||
        room.pendingActions.isEmpty ||
        room.room.status != MultiplayerRoomStatus.playing)
      return;
    if (room.room.aiHostConfig.status != AIHostStatus.ready) {
      room.room = room.room.copyWith(gmWaiting: true);
      return;
    }
    final action = room.pendingActions.removeAt(0);
    final messages = _prompts.build(
      session: room.session!,
      action: action.content,
      actingPlayerId: action.playerId,
      privateInteraction: action.visibility != MultiplayerVisibility.public,
      multiplayerBundle: action.roundBundle,
    );
    room.activeAction = _ActiveAction(action: action, messages: messages);
    room.room = room.room.copyWith(
      aiHostConfig: room.room.aiHostConfig.copyWith(status: AIHostStatus.busy),
    );
    final processing = MultiplayerEnvelope(
      type: MultiplayerEventType.gmProcessing,
      roomId: room.room.roomId,
      revision: room.room.revision,
      sequenceNumber: room.room.sequenceNumber,
      payload: {
        'actionId': action.actionId,
        'turnId': action.turnId,
        if (action.turnId != null)
          'phase': MultiplayerTurnPhase.gmResponding.name,
      },
      visibility: action.visibility,
      recipientPlayerIds: action.recipientPlayerIds,
    );
    if (action.visibility == MultiplayerVisibility.public) {
      _broadcast(room, processing);
    } else {
      _sendToPlayers(
        room,
        action.recipientPlayerIds,
        processing,
        includeHumanGm: true,
      );
    }
    _sendAIRequest(room);
  }

  void _sendAIRequest(_ServerRoom room) {
    final active = room.activeAction;
    if (active == null) return;
    final hostId = room.room.aiHostConfig.providerPlayerId;
    final socket = hostId == null ? null : room.sockets[hostId];
    if (socket == null || socket.readyState != WebSocket.open) {
      _markHostOffline(room);
      return;
    }
    active.timeout?.cancel();
    final requestId =
        '${active.action.actionId}-round-${active.round}-${const Uuid().v4()}';
    active.requestId = requestId;
    _send(
      socket,
      MultiplayerEnvelope(
        type: MultiplayerEventType.aiRequest,
        roomId: room.room.roomId,
        revision: room.room.revision,
        payload: {
          'requestId': requestId,
          'sessionId': room.session!.id,
          'actionId': active.action.actionId,
          'turnId': active.action.turnId,
          'roundActionBundle': active.action.roundBundle?.toJson(),
          'messages': active.messages,
          'tools': _tools.schemas,
          'timeoutSeconds': config.aiRequestTimeout.inSeconds,
          'modelId': room.room.aiHostConfig.modelId,
        },
      ),
    );
    active.timeout = Timer(config.aiRequestTimeout, () {
      room.room = room.room.copyWith(
        gmWaiting: true,
        aiHostConfig: room.room.aiHostConfig.copyWith(
          status: AIHostStatus.error,
          errorCount: room.room.aiHostConfig.errorCount + 1,
        ),
      );
      _broadcastRoomPatch(room, MultiplayerEventType.error, {
        'code': 'ai_timeout',
        'actionId': active.action.actionId,
        'message': 'AI 主持响应超时，可以重试或更换 Host。',
      });
    });
  }

  Future<void> _handleAIResponse(
    _ServerRoom room,
    _Identity actor,
    MultiplayerEnvelope command,
  ) async {
    final active = room.activeAction;
    if (active == null || command.payload['requestId'] != active.requestId)
      throw StateError('AI request 已过期');
    active.timeout?.cancel();
    final hostError = command.payload['error'];
    if (hostError is String && hostError.isNotEmpty) {
      room.room = room.room.copyWith(
        status: MultiplayerRoomStatus.paused,
        gmWaiting: true,
        aiHostConfig: room.room.aiHostConfig.copyWith(
          status: AIHostStatus.error,
          errorCount: room.room.aiHostConfig.errorCount + 1,
        ),
      );
      await _commitRoom(room, MultiplayerEventType.error, {
        'code': 'ai_host_error',
        'actionId': active.action.actionId,
        'message': 'AI 主持暂时无法响应：$hostError',
      });
      return;
    }
    final responseJson = command.payload['response'];
    if (responseJson is! Map) throw StateError('AI response 格式无效');
    final response = OpenAIChatResponse.fromTransportJson(
      responseJson.cast<String, Object?>(),
    );
    room.room = room.room.copyWith(
      aiHostConfig: room.room.aiHostConfig.copyWith(
        requestCount: room.room.aiHostConfig.requestCount + 1,
        inputTokens:
            room.room.aiHostConfig.inputTokens +
            ((command.payload['inputTokens'] as num?)?.toInt() ?? 0),
        outputTokens:
            room.room.aiHostConfig.outputTokens +
            ((command.payload['outputTokens'] as num?)?.toInt() ?? 0),
        lastHeartbeat: DateTime.now(),
      ),
    );
    if (room.room.aiHostConfig.maxRequests > 0 &&
        room.room.aiHostConfig.requestCount >=
            room.room.aiHostConfig.maxRequests) {
      room.room = room.room.copyWith(
        gmWaiting: true,
        aiHostConfig: room.room.aiHostConfig.copyWith(
          status: AIHostStatus.error,
        ),
      );
      _broadcastRoomPatch(room, MultiplayerEventType.error, {
        'code': 'host_limit',
        'message': 'AI 主持模型已达到提供者设置的使用上限。',
      });
      return;
    }
    if (room.room.aiHostConfig.maxTokens > 0 &&
        room.room.aiHostConfig.inputTokens +
                room.room.aiHostConfig.outputTokens >=
            room.room.aiHostConfig.maxTokens) {
      room.room = room.room.copyWith(
        status: MultiplayerRoomStatus.paused,
        gmWaiting: true,
        aiHostConfig: room.room.aiHostConfig.copyWith(
          status: AIHostStatus.error,
        ),
      );
      _broadcastRoomPatch(room, MultiplayerEventType.error, {
        'code': 'host_token_limit',
        'message': 'AI 主持模型已达到提供者设置的 Token 上限。',
      });
      return;
    }
    if (response.toolCalls.isEmpty) {
      final narration = response.content.trim();
      if (narration.isEmpty) throw StateError('AI 没有返回主持内容');
      final now = DateTime.now();
      final secret = active.action.visibility != MultiplayerVisibility.public;
      room.session = room.session!.copyWith(
        chatHistory: secret
            ? room.session!.chatHistory
            : [
                ...room.session!.chatHistory,
                TRPGMessage(
                  id: _uuid.v4(),
                  messageType: TRPGMessageType.gmMessage,
                  content: narration,
                  createdAt: now,
                ),
              ],
        eventLog: secret
            ? room.session!.eventLog
            : [
                ...room.session!.eventLog,
                TRPGEvent(
                  id: _uuid.v4(),
                  type: TRPGEventType.gmNarration,
                  timestamp: now,
                  payload: {
                    'actionId': active.action.actionId,
                    'content': narration,
                  },
                ),
              ],
        immersionState: secret
            ? room.session!.immersionState.copyWith(
                timeline: [
                  ...room.session!.immersionState.timeline,
                  SessionTimelineEntry(
                    id: _uuid.v4(),
                    title: '秘密行动结果',
                    detail: narration,
                    createdAt: now,
                    visibility: InformationVisibility.playerPrivate,
                    ownerPlayerIds: active.action.recipientPlayerIds,
                  ),
                ],
              )
            : room.session!.immersionState,
        updatedAt: now,
      );
      if (secret) {
        final ownerId = active.action.recipientPlayerIds.firstOrNull;
        final resultMemory = MemoryEntry(
          id: _uuid.v4(),
          sessionId: room.session!.id,
          type: MemoryType.privateMemory,
          title: '秘密行动结果',
          content: narration,
          importance: 7,
          confidence: MemoryConfidence.confirmed,
          createdAt: now,
          updatedAt: now,
          sourceEventIds: [active.action.actionId],
          relatedEntityIds: [?ownerId, active.action.characterId],
          tags: const ['secret_action_result'],
          visibility: MemoryVisibility.playerPrivate,
          ownerPlayerId: ownerId,
          canonPriority: CanonPriority.confirmedEvent,
        );
        room.session = room.session!.copyWith(
          memoryState: room.session!.memoryState.copyWith(
            entries: [...room.session!.memoryState.entries, resultMemory],
          ),
        );
      }
      // The server is authoritative: the API host only returns narration/tool
      // candidates. Long-term memory is validated and committed here.
      room.session = _longTermMemory.process(room.session!, force: true);
      final completedTurnId = active.action.turnId;
      final wasOpening = active.action.isOpening;
      if (completedTurnId != null &&
          room.room.currentTurn?.turnId == completedTurnId) {
        room.room = room.room.copyWith(
          currentTurn: room.room.currentTurn!.copyWith(
            phase: MultiplayerTurnPhase.completed,
            status: MultiplayerTurnStatus.resolved,
            resolvedAt: now,
          ),
        );
        room.resolvingTurnIds.remove(completedTurnId);
      }
      room.activeAction = null;
      room.room = room.room.copyWith(
        gmWaiting: false,
        aiHostConfig: room.room.aiHostConfig.copyWith(
          status: AIHostStatus.ready,
        ),
      );
      await _commitSession(
        room,
        MultiplayerEventType.gmMessage,
        {
          'actionId': active.action.actionId,
          'turnId': completedTurnId,
          'content': narration,
        },
        visibility: active.action.visibility,
        recipientPlayerIds: active.action.recipientPlayerIds,
      );
      if (completedTurnId != null) {
        await _commitRoom(room, MultiplayerEventType.turnResolved, {
          'turnId': completedTurnId,
          'resolutionRequestId': 'turn-$completedTurnId',
        });
      }
      if (completedTurnId != null || wasOpening) {
        await _startNextTurn(room);
      } else if (room.room.currentTurn?.mode ==
              MultiplayerTurnMode.combatInitiative &&
          room.session?.ruleState.combatActive != true) {
        await _startNextTurn(room);
      } else {
        _processNext(room);
      }
      return;
    }
    if (active.round >= 8) {
      room.room = room.room.copyWith(
        gmWaiting: true,
        aiHostConfig: room.room.aiHostConfig.copyWith(
          status: AIHostStatus.error,
        ),
      );
      _broadcastRoomPatch(room, MultiplayerEventType.error, {
        'code': 'tool_loop_limit',
        'actionId': active.action.actionId,
      });
      return;
    }
    active.messages.add({
      'role': 'assistant',
      'content': response.content,
      if (response.reasoningContent != null)
        'reasoning_content': response.reasoningContent,
      'tool_calls': response.toolCalls
          .map((call) => call.toAssistantJson())
          .toList(),
    });
    if (active.action.turnId != null &&
        room.room.currentTurn?.turnId == active.action.turnId) {
      room.room = room.room.copyWith(
        currentTurn: room.room.currentTurn!.copyWith(
          phase: MultiplayerTurnPhase.applyingTools,
        ),
      );
    }
    for (final originalCall in response.toolCalls) {
      OpenAIToolCall call;
      try {
        call = _attributeRoundToolCall(active, originalCall);
      } on StateError catch (error) {
        final failure = {
          'success': false,
          'error': error.message,
          'turnId': active.action.turnId,
        };
        active.messages.add({
          'role': 'tool',
          'tool_call_id': originalCall.id,
          'name': originalCall.name,
          'content': jsonEncode(failure),
        });
        await _commitSession(
          room,
          MultiplayerEventType.toolResult,
          {
            'actionId': active.action.actionId,
            'turnId': active.action.turnId,
            'toolCallId': originalCall.id,
            'toolName': originalCall.name,
            ...failure,
          },
          visibility: active.action.visibility,
          recipientPlayerIds: active.action.recipientPlayerIds,
        );
        continue;
      }
      final outcome = await _tools.execute(
        session: room.session!,
        actionId: active.action.actionId,
        call: call,
      );
      room.session = outcome.session;
      active.messages.add({
        'role': 'tool',
        'tool_call_id': call.id,
        'name': call.name,
        'content': jsonEncode(outcome.result),
      });
      await _commitSession(
        room,
        MultiplayerEventType.toolResult,
        {
          'actionId': active.action.actionId,
          'turnId': active.action.turnId,
          'actorPlayerId': call.arguments['actorPlayerId'],
          'actorCharacterId':
              call.arguments['actorCharacterId'] ??
              call.arguments['characterId'],
          'toolCallId': call.id,
          'toolName': call.name,
          'success': outcome.record.succeeded,
          'result': outcome.result,
        },
        visibility: active.action.visibility,
        recipientPlayerIds: active.action.recipientPlayerIds,
      );
    }
    active.round++;
    if (active.action.turnId != null &&
        room.room.currentTurn?.turnId == active.action.turnId) {
      room.room = room.room.copyWith(
        currentTurn: room.room.currentTurn!.copyWith(
          phase: MultiplayerTurnPhase.gmResponding,
        ),
      );
    }
    _sendAIRequest(room);
  }

  OpenAIToolCall _attributeRoundToolCall(
    _ActiveAction active,
    OpenAIToolCall call,
  ) {
    final bundle = active.action.roundBundle;
    if (bundle == null ||
        !const {
          'roll_dice',
          'skill_check',
          'attack_check',
          'move_character',
        }.contains(call.name)) {
      return call;
    }
    final args = <String, Object?>{...call.arguments};
    final providedTurnId = args['turnId'] as String?;
    if (providedTurnId != null && providedTurnId != bundle.turnId) {
      throw StateError('工具 turnId 与当前多人回合不匹配');
    }
    args['turnId'] = bundle.turnId;
    final characterId =
        args['actorCharacterId'] as String? ??
        args['characterId'] as String? ??
        args['attackerId'] as String?;
    final candidates = characterId == null
        ? bundle.actions
        : bundle.actions
              .where((action) => action.characterId == characterId)
              .toList();
    if (candidates.length != 1) {
      throw StateError('多人工具必须明确唯一 actorCharacterId');
    }
    final action = candidates.single;
    final providedPlayerId = args['actorPlayerId'] as String?;
    if (providedPlayerId != null && providedPlayerId != action.playerId) {
      throw StateError('工具 actorPlayerId 与角色归属不匹配');
    }
    final providedActionId = args['actionId'] as String?;
    if (providedActionId != null && providedActionId != action.actionId) {
      throw StateError('工具 actionId 与玩家本回合行动不匹配');
    }
    args
      ..['actorPlayerId'] = action.playerId
      ..['actorCharacterId'] = action.characterId
      ..['actionId'] = action.actionId;
    return OpenAIToolCall(id: call.id, name: call.name, arguments: args);
  }

  Future<void> _resolveHumanGmTurn(
    _ServerRoom room,
    _Identity actor,
    MultiplayerEnvelope command,
  ) async {
    final player = room.room.players.firstWhere(
      (value) => value.playerId == actor.playerId,
    );
    if (player.role != TRPGPlayerRole.humanGm) {
      throw StateError('只有人类 GM 可以人工结算回合');
    }
    final turn = room.room.currentTurn;
    if (turn == null || command.payload['turnId'] != turn.turnId) {
      throw StateError('回合不存在或已经结束');
    }
    if (turn.phase != MultiplayerTurnPhase.gmResponding) {
      throw StateError('玩家尚未全部确认');
    }
    final narration = _requiredString(command.payload, 'narration');
    final now = DateTime.now();
    room.session = room.session!.copyWith(
      chatHistory: [
        ...room.session!.chatHistory,
        TRPGMessage(
          id: _uuid.v4(),
          messageType: TRPGMessageType.gmMessage,
          content: narration,
          playerId: actor.playerId,
          createdAt: now,
        ),
      ],
      eventLog: [
        ...room.session!.eventLog,
        TRPGEvent(
          id: _uuid.v4(),
          type: TRPGEventType.gmNarration,
          timestamp: now,
          actorId: actor.playerId,
          payload: {'turnId': turn.turnId, 'content': narration},
        ),
      ],
      updatedAt: now,
      lastPlayedAt: now,
    );
    room.room = room.room.copyWith(
      currentTurn: turn.copyWith(
        phase: MultiplayerTurnPhase.completed,
        status: MultiplayerTurnStatus.resolved,
        resolvedAt: now,
      ),
    );
    room.resolvingTurnIds.remove(turn.turnId);
    await _commitSession(room, MultiplayerEventType.turnResolved, {
      'turnId': turn.turnId,
      'content': narration,
    });
    await _startNextTurn(room);
  }

  Future<void> _kick(_ServerRoom room, String playerId) async {
    if (playerId == room.room.ownerPlayerId) throw StateError('不能踢出当前房主');
    room.room = room.room.copyWith(
      players: room.room.players.where((p) => p.playerId != playerId).toList(),
    );
    room.sockets[playerId]?.close(WebSocketStatus.policyViolation, 'kicked');
    await _commitRoom(room, MultiplayerEventType.playerLeft, {
      'playerId': playerId,
      'kicked': true,
    });
  }

  Future<void> _commitRoom(
    _ServerRoom room,
    MultiplayerEventType type,
    Map<String, Object?> patch,
  ) async {
    room.room = room.room.copyWith(
      revision: room.room.revision + 1,
      sequenceNumber: room.room.sequenceNumber + 1,
      updatedAt: DateTime.now(),
    );
    await _persist(room);
    _broadcastRoomPatch(room, type, patch);
  }

  Future<void> _commitSession(
    _ServerRoom room,
    MultiplayerEventType type,
    Map<String, Object?> patch, {
    MultiplayerVisibility visibility = MultiplayerVisibility.public,
    List<String> recipientPlayerIds = const [],
  }) async {
    room.room = room.room.copyWith(
      revision: room.room.revision + 1,
      sequenceNumber: room.room.sequenceNumber + 1,
      updatedAt: DateTime.now(),
    );
    await _persist(room);
    final event = MultiplayerEnvelope(
      type: type,
      roomId: room.room.roomId,
      revision: room.room.revision,
      sequenceNumber: room.room.sequenceNumber,
      payload: patch,
      visibility: visibility,
      recipientPlayerIds: recipientPlayerIds,
    );
    if (visibility == MultiplayerVisibility.public) {
      _broadcast(room, event);
    } else {
      _sendToPlayers(room, recipientPlayerIds, event, includeHumanGm: true);
    }
    // Every connected player receives a personalized state. Private data is
    // stripped on the server; it is never broadcast for client-side filtering.
    for (final entry in room.sockets.entries.toList()) {
      if (entry.value.readyState != WebSocket.open) continue;
      _send(
        entry.value,
        MultiplayerEnvelope(
          type: MultiplayerEventType.statePatch,
          roomId: room.room.roomId,
          revision: room.room.revision,
          sequenceNumber: room.room.sequenceNumber,
          payload: {
            'room': _safeRoomForPlayer(room, entry.key).toJson(),
            'session': _safeSessionForPlayer(room, entry.key).toJson(),
          },
        ),
      );
    }
  }

  void _broadcastRoomPatch(
    _ServerRoom room,
    MultiplayerEventType source,
    Map<String, Object?> patch,
  ) {
    _broadcast(
      room,
      MultiplayerEnvelope(
        type: source,
        roomId: room.room.roomId,
        revision: room.room.revision,
        sequenceNumber: room.room.sequenceNumber,
        payload: patch,
      ),
    );
    for (final entry in room.sockets.entries.toList()) {
      if (entry.value.readyState != WebSocket.open) continue;
      _send(
        entry.value,
        MultiplayerEnvelope(
          type: MultiplayerEventType.statePatch,
          roomId: room.room.roomId,
          revision: room.room.revision,
          sequenceNumber: room.room.sequenceNumber,
          payload: {'room': _safeRoomForPlayer(room, entry.key).toJson()},
        ),
      );
    }
  }

  void _broadcast(_ServerRoom room, MultiplayerEnvelope event) {
    for (final socket in room.sockets.values.toList()) {
      if (socket.readyState == WebSocket.open) _send(socket, event);
    }
  }

  void _sendToPlayers(
    _ServerRoom room,
    Iterable<String> playerIds,
    MultiplayerEnvelope event, {
    bool includeHumanGm = false,
  }) {
    final authorized = playerIds.toSet();
    if (includeHumanGm) {
      authorized.addAll(
        room.room.players
            .where((value) => value.role == TRPGPlayerRole.humanGm)
            .map((value) => value.playerId),
      );
    }
    for (final id in authorized) {
      final socket = room.sockets[id];
      if (socket != null && socket.readyState == WebSocket.open) {
        _send(socket, event);
      }
    }
  }

  void _sendSnapshot(WebSocket socket, _ServerRoom room) {
    _send(
      socket,
      MultiplayerEnvelope(
        type: MultiplayerEventType.snapshot,
        roomId: room.room.roomId,
        revision: room.room.revision,
        sequenceNumber: room.room.sequenceNumber,
        payload: _safeSnapshotForPlayer(
          room,
          _connections[socket]?.playerId,
        ).toJson(),
      ),
    );
  }

  MultiplayerSnapshot _safeSnapshot(_ServerRoom room) {
    final session = room.session == null ? null : _safeSession(room.session!);
    if (session != null) {
      room.lastPublicSessionJson = _deepCopyMap(session.toJson());
    }
    return MultiplayerSnapshot(room: _safeRoom(room.room), session: session);
  }

  MultiplayerSnapshot _safeSnapshotForPlayer(
    _ServerRoom room,
    String? playerId,
  ) => MultiplayerSnapshot(
    room: _safeRoomForPlayer(room, playerId),
    session: room.session == null || playerId == null
        ? null
        : _safeSessionForPlayer(room, playerId),
  );

  TRPGRoom _safeRoom(TRPGRoom room) => TRPGRoom.fromJson({
    ...room.toJson(),
    'aiHostConfig': {...room.aiHostConfig.toJson(), 'providerId': null},
    'currentTurn': room.currentTurn?.forViewer(null).toJson(),
  });

  TRPGRoom _safeRoomForPlayer(_ServerRoom serverRoom, String? playerId) {
    final room = serverRoom.room;
    final isHumanGm =
        playerId != null &&
        room.players.any(
          (value) =>
              value.playerId == playerId &&
              value.role == TRPGPlayerRole.humanGm,
        );
    return TRPGRoom.fromJson({
      ...room.toJson(),
      'aiHostConfig': {...room.aiHostConfig.toJson(), 'providerId': null},
      'currentTurn': room.currentTurn
          ?.forViewer(playerId, isGm: isHumanGm)
          .toJson(),
    });
  }

  TRPGSession _safeSession(TRPGSession session) => TRPGSession.fromJson({
    ...session.toJson(),
    'gmState': const GMState().toJson(),
    'gmStateSnapshot': const GMStateSnapshot().toJson(),
    'actionSnapshots': const [],
    'memoryState': _safeMemoryState(session.memoryState).toJson(),
    'livingNpcState': session.livingNpcState.forViewer(null).toJson(),
    'worldGenerationState': session.worldGenerationState.publicView().toJson(),
    'factionSimulationState': session.factionSimulationState
        .publicView()
        .toJson(),
    'holyGrailState': session.holyGrailState.publicView().toJson(),
    'eventLog': session.eventLog
        .where((event) => _eventVisibleTo(event, null))
        .map((event) => event.toJson())
        .toList(),
    'ruleState': session.ruleState
        .copyWith(
          diceHistory2: session.ruleState.diceHistory2
              .where((value) => value.visibility == DiceVisibility.public)
              .toList(),
          checkHistory: session.ruleState.checkHistory
              .where((value) => value.visibility.name == 'public')
              .toList(),
          growthCandidates: const [],
          growthHistory: const [],
          privateResolutions: session.ruleState.privateResolutions
              .where((value) => value.visibility.name == 'public')
              .toList(),
          repeatedChecks: const [],
        )
        .toJson(),
    'immersionState': session.immersionState
        .copyWith(
          campaignSnapshot: _safeCampaignSnapshot(
            session.immersionState.campaignSnapshot,
          ),
          privateKnowledge: session.immersionState.privateKnowledge
              .where(
                (value) => value.visibility == InformationVisibility.public,
              )
              .toList(),
          privateMessages: const [],
          timeline: session.immersionState.timeline
              .where(
                (value) => value.visibility == InformationVisibility.public,
              )
              .toList(),
        )
        .toJson(),
  });

  TRPGSession _safeSessionForPlayer(_ServerRoom room, String playerId) {
    final session = room.session!;
    final isHumanGm = room.room.players.any(
      (value) =>
          value.playerId == playerId && value.role == TRPGPlayerRole.humanGm,
    );
    if (isHumanGm) return session;
    final immersion = session.immersionState;
    return TRPGSession.fromJson({
      ...session.toJson(),
      'gmState': const GMState().toJson(),
      'gmStateSnapshot': const GMStateSnapshot().toJson(),
      'actionSnapshots': const [],
      'memoryState': _memoryForPlayer(session.memoryState, playerId).toJson(),
      'livingNpcState': session.livingNpcState.forViewer(playerId).toJson(),
      'worldGenerationState': session.worldGenerationState
          .publicView()
          .toJson(),
      'factionSimulationState': session.factionSimulationState
          .forPlayer(playerId)
          .toJson(),
      'holyGrailState': session.holyGrailState.forPlayer(playerId).toJson(),
      'eventLog': session.eventLog
          .where((event) => _eventVisibleTo(event, playerId))
          .map((event) => event.toJson())
          .toList(),
      'ruleState': session.ruleState
          .copyWith(
            diceHistory2: session.ruleState.diceHistory2
                .where((value) => value.visibleTo(playerId))
                .toList(),
            checkHistory: session.ruleState.checkHistory
                .where(
                  (value) =>
                      value.visibility.name == 'public' ||
                      value.playerId == playerId &&
                          value.visibility.name != 'gmHidden',
                )
                .toList(),
            growthCandidates: session.ruleState.growthCandidates
                .where(
                  (value) => session.playerCharacters.any(
                    (character) =>
                        character.id == value.characterId &&
                        character.playerId == playerId,
                  ),
                )
                .toList(),
            growthHistory: session.ruleState.growthHistory
                .where(
                  (value) => session.playerCharacters.any(
                    (character) =>
                        character.id == value.characterId &&
                        character.playerId == playerId,
                  ),
                )
                .toList(),
            privateResolutions: session.ruleState.privateResolutions
                .where((value) => value.visibleTo(playerId))
                .toList(),
            repeatedChecks: session.ruleState.repeatedChecks
                .where(
                  (value) => session.playerCharacters.any(
                    (character) =>
                        character.id == value.characterId &&
                        character.playerId == playerId,
                  ),
                )
                .toList(),
          )
          .toJson(),
      'immersionState': immersion
          .copyWith(
            campaignSnapshot: _safeCampaignSnapshot(immersion.campaignSnapshot),
            privateKnowledge: immersion.privateKnowledge
                .where(
                  (value) =>
                      value.visibility == InformationVisibility.public ||
                      value.ownerPlayerIds.contains(playerId),
                )
                .toList(),
            privateMessages: immersion.privateMessages
                .where(
                  (value) =>
                      value.senderId == playerId ||
                      value.recipientIds.contains(playerId),
                )
                .toList(),
            timeline: immersion.timeline
                .where(
                  (value) =>
                      value.visibility == InformationVisibility.public ||
                      value.ownerPlayerIds.contains(playerId),
                )
                .toList(),
          )
          .toJson(),
    });
  }

  Map<String, Object?> _safeCampaignSnapshot(Map<String, Object?> snapshot) {
    if (snapshot.isEmpty) return const {};
    final generation = snapshot['metadata'] is Map
        ? ((snapshot['metadata'] as Map)['worldGeneration'])
        : null;
    final safeGeneration = generation is Map
        ? WorldGenerationState.fromJson(
            generation.cast<String, Object?>(),
          ).publicView().toJson()
        : null;
    return {
      ...snapshot,
      'secrets': const <String>[],
      'metadata': {'worldGeneration': ?safeGeneration},
      'npcs': (snapshot['npcs'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (raw) => {
              ...raw.cast<String, Object?>(),
              'privateNotes': '',
              'memories': const <Object?>[],
            },
          )
          .toList(),
      'locations': (snapshot['locations'] as List? ?? const [])
          .whereType<Map>()
          .where((raw) => raw['hidden'] != true)
          .map((raw) => {...raw.cast<String, Object?>(), 'gmNotes': ''})
          .toList(),
      'clues': (snapshot['clues'] as List? ?? const [])
          .whereType<Map>()
          .where(
            (raw) =>
                raw['visibility'] == InformationVisibility.public.name &&
                raw['discovered'] == true,
          )
          .map((raw) => raw.cast<String, Object?>())
          .toList(),
    };
  }

  bool _eventVisibleTo(TRPGEvent event, String? playerId) {
    final raw = event.payload['visibilityPlayerIds'];
    if (raw is! List || raw.isEmpty) return true;
    return playerId != null &&
        raw.map((value) => value.toString()).contains(playerId);
  }

  MemoryState _safeMemoryState(MemoryState state) => state.copyWith(
    entries: state.entries
        .where((value) => value.visibility == MemoryVisibility.public)
        .toList(),
    knowledgeRelations: const [],
    promises: state.promises
        .where(
          (value) => state.entries.any(
            (memory) =>
                memory.id == value.memoryId &&
                memory.visibility == MemoryVisibility.public,
          ),
        )
        .toList(),
    storyThreads: state.storyThreads.where((value) => !value.gmOnly).toList(),
    companionSummaries: const {},
  );

  MemoryState _memoryForPlayer(MemoryState state, String playerId) =>
      _safeMemoryState(state).copyWith(
        entries: state.entries
            .where(
              (value) =>
                  value.visibility == MemoryVisibility.public ||
                  value.visibility == MemoryVisibility.playerPrivate &&
                      value.ownerPlayerId == playerId,
            )
            .toList(),
        promises: state.promises
            .where(
              (value) =>
                  value.promiser == playerId || value.promiseTo == playerId,
            )
            .toList(),
      );

  _Identity _authenticate(WebSocket socket, String? suppliedToken) {
    final identity = _connections[socket];
    if (identity == null ||
        suppliedToken == null ||
        suppliedToken != identity.token)
      throw StateError('身份验证失败');
    return identity;
  }

  void _requireOwner(_ServerRoom room, _Identity actor) {
    if (room.room.ownerPlayerId != actor.playerId)
      throw StateError('只有房主可以执行此操作');
  }

  void _requireManagement(
    _ServerRoom room,
    _Identity actor,
    RoomPermission permission,
  ) {
    if (room.room.kind == CampaignRoomKind.temporary) {
      _requireOwner(room, actor);
      return;
    }
    final userId = actor.userId;
    final campaignId = room.room.persistentCampaignRoomId;
    if (userId == null || campaignId == null) {
      throw StateError('永久战役管理操作需要已验证账号');
    }
    final campaign = _social.campaignFor(userId, campaignId);
    const RoomPermissionService().require(campaign, userId, permission);
  }

  void _requireHost(_ServerRoom room, _Identity actor) {
    if (room.room.aiHostConfig.providerPlayerId != actor.playerId)
      throw StateError('只有当前 AI Host 可以执行此操作');
  }

  void _handleDisconnect(WebSocket socket) {
    final identity = _connections.remove(socket);
    if (identity == null) return;
    final room = _rooms[identity.roomId];
    if (room == null || !identical(room.sockets[identity.playerId], socket))
      return;
    room.sockets.remove(identity.playerId);
    _setConnection(room, identity.playerId, TRPGConnectionStatus.reconnecting);
    if (room.room.aiHostConfig.providerPlayerId == identity.playerId)
      _markHostOffline(room);
    _broadcastRoomPatch(room, MultiplayerEventType.playerLeft, {
      'playerId': identity.playerId,
      'temporary': true,
    });
    Timer(config.offlineGrace, () {
      if (!room.sockets.containsKey(identity.playerId)) {
        _setConnection(room, identity.playerId, TRPGConnectionStatus.offline);
        if (room.room.kind == CampaignRoomKind.temporary &&
            room.room.ownerPlayerId == identity.playerId) {
          _transferOwner(room);
        }
        _persist(room);
      }
    });
  }

  void _setConnection(
    _ServerRoom room,
    String playerId,
    TRPGConnectionStatus status,
  ) {
    room.room = room.room.copyWith(
      players: room.room.players
          .map(
            (p) => p.playerId == playerId
                ? p.copyWith(connectionStatus: status)
                : p,
          )
          .toList(),
    );
    if (room.session != null)
      room.session = room.session!.copyWith(players: room.room.players);
  }

  void _markHostOffline(_ServerRoom room) {
    room.room = room.room.copyWith(
      status: room.room.status == MultiplayerRoomStatus.playing
          ? MultiplayerRoomStatus.paused
          : room.room.status,
      gmWaiting: true,
      aiHostConfig: room.room.aiHostConfig.copyWith(
        status: AIHostStatus.offline,
      ),
      revision: room.room.revision + 1,
      sequenceNumber: room.room.sequenceNumber + 1,
      updatedAt: DateTime.now(),
    );
    _broadcastRoomPatch(room, MultiplayerEventType.pauseGame, {
      'reason': 'ai_host_offline',
      'message': 'AI 主持模型提供者已离线，正在等待重连。',
    });
    if (room.room.kind == CampaignRoomKind.persistent) {
      unawaited(_requestPolicyFallback(room));
    }
  }

  Future<void> _requestPolicyFallback(_ServerRoom room) async {
    final campaignId = room.room.persistentCampaignRoomId;
    if (campaignId == null ||
        room.room.aiHostConfig.status != AIHostStatus.offline) {
      return;
    }
    final campaign = _social.inspectCampaign(campaignId);
    if (campaign == null) return;
    final policy = campaign.aiHostPolicy;
    final orderedUsers = <String>[
      if (policy.preferredProviderUserId != null)
        policy.preferredProviderUserId!,
      ...policy.backupProviderUserIds,
      if (policy.allowOwnerFallback) campaign.ownerUserId,
    ];
    final previousPlayerId = room.room.aiHostConfig.providerPlayerId;
    for (final userId in orderedUsers.toSet()) {
      final candidate = _tokens.values.where((identity) {
        if (identity.roomId != room.room.roomId ||
            identity.userId != userId ||
            identity.playerId == previousPlayerId) {
          return false;
        }
        final socket = room.sockets[identity.playerId];
        final capability = room.capabilities[identity.playerId];
        return socket?.readyState == WebSocket.open &&
            capability?.supportsAIHost == true &&
            capability?.toolCallingVerified == true;
      }).firstOrNull;
      if (candidate == null) continue;
      await _requestHost(room, candidate.playerId, {
        'providerType':
            room.capabilities[candidate.playerId]?.providerTypes.firstOrNull ??
            'openai-compatible',
      });
      return;
    }
    _broadcastRoomPatch(room, MultiplayerEventType.statePatch, {
      'gmWaiting': true,
      'message': '没有在线且已验证的备用 Host，战役保持暂停',
    });
  }

  void _transferOwner(_ServerRoom room) {
    final next = room.room.players
        .where((p) => p.connectionStatus == TRPGConnectionStatus.online)
        .firstOrNull;
    if (next == null) {
      room.room = room.room.copyWith(status: MultiplayerRoomStatus.paused);
      return;
    }
    room.room = room.room.copyWith(
      ownerPlayerId: next.playerId,
      players: room.room.players
          .map(
            (p) => p.copyWith(
              role: p.playerId == next.playerId
                  ? TRPGPlayerRole.roomOwner
                  : TRPGPlayerRole.player,
            ),
          )
          .toList(),
    );
    _broadcastRoomPatch(room, MultiplayerEventType.statePatch, {
      'ownerPlayerId': next.playerId,
    });
  }

  void _checkOfflineHosts() {
    final cutoff = DateTime.now().subtract(const Duration(seconds: 35));
    for (final room in _rooms.values) {
      final config = room.room.aiHostConfig;
      if ((config.status == AIHostStatus.ready ||
              config.status == AIHostStatus.busy) &&
          (config.lastHeartbeat == null ||
              config.lastHeartbeat!.isBefore(cutoff))) {
        _markHostOffline(room);
      }
    }
  }

  /// Test/admin read-only snapshot. It never exposes connection tokens.
  MultiplayerSnapshot inspectRoom(
    String roomId, {
    bool includeSecrets = false,
  }) {
    final room = _rooms[roomId];
    if (room == null) throw StateError('Room not found');
    return includeSecrets
        ? MultiplayerSnapshot(room: room.room, session: room.session)
        : _safeSnapshot(room);
  }

  Map<String, Object?>? _campaignSessionSnapshot(String campaignRoomId) =>
      _rooms.values
          .where(
            (value) =>
                value.room.persistentCampaignRoomId == campaignRoomId &&
                value.session != null,
          )
          .firstOrNull
          ?.session
          ?.toJson();

  Future<void> _restoreCampaignSession(
    String campaignRoomId,
    Map<String, Object?> sessionJson,
  ) async {
    final room = _rooms.values
        .where((value) => value.room.persistentCampaignRoomId == campaignRoomId)
        .firstOrNull;
    if (room == null) return;
    final restored = TRPGSession.fromJson(sessionJson);
    room.session = restored;
    room.room = room.room.copyWith(
      sessionId: restored.id,
      status: MultiplayerRoomStatus.paused,
      gmWaiting: true,
      revision: room.room.revision + 1,
      sequenceNumber: room.room.sequenceNumber + 1,
      updatedAt: DateTime.now(),
    );
    await _persist(room);
    for (final entry in room.sockets.entries.toList()) {
      if (entry.value.readyState == WebSocket.open) {
        _sendSnapshot(entry.value, room);
      }
    }
  }

  UserAccount? _optionalAccount(Map<String, Object?> payload) {
    final token = payload['accessToken'];
    if (token is! String || token.trim().isEmpty) return null;
    return _social.authenticate(token.trim()).account;
  }

  Map<String, Object?> _deepCopyMap(Map<String, Object?> source) =>
      (jsonDecode(jsonEncode(source)) as Map).cast<String, Object?>();

  Future<void> _persist(_ServerRoom room) async {
    final previous = room.persistQueue;
    final completer = Completer<void>();
    room.persistQueue = completer.future;
    await previous.catchError((_) {});
    try {
      await _writeRoom(room);
      completer.complete();
    } catch (error, stackTrace) {
      completer.completeError(error, stackTrace);
      rethrow;
    }
  }

  Future<void> _writeRoom(_ServerRoom room) async {
    final dir = Directory(config.persistenceDirectory);
    await dir.create(recursive: true);
    final file = File(
      '${dir.path}${Platform.pathSeparator}${room.room.roomId}.json',
    );
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(
      jsonEncode({
        'room': room.room.toJson(),
        'session': room.session?.toJson(),
        'tokens': _tokens.entries
            .where((e) => e.value.roomId == room.room.roomId)
            .map((e) => {'token': e.key, ...e.value.toJson()})
            .toList(),
        'characters': room.pendingCharacters.map(
          (key, value) => MapEntry(key, value.toJson()),
        ),
        'executedCommandIds': room.executedCommandIds.toList(),
        'campaignSnapshot': room.campaignSnapshot,
        'allowPlayerPrivateChat': room.allowPlayerPrivateChat,
        'capabilities': room.capabilities.map(
          (key, value) => MapEntry(key, value.toJson()),
        ),
      }),
      flush: true,
    );
    await temp.rename(file.path);
  }

  Future<void> _restoreRooms() async {
    final dir = Directory(config.persistenceDirectory);
    if (!await dir.exists()) return;
    await for (final entity in dir.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final raw = (jsonDecode(await entity.readAsString()) as Map)
            .cast<String, Object?>();
        var room = TRPGRoom.fromJson(
          (raw['room'] as Map).cast<String, Object?>(),
        );
        room = room.copyWith(
          status: room.status == MultiplayerRoomStatus.playing
              ? MultiplayerRoomStatus.paused
              : room.status,
          gmWaiting: room.status == MultiplayerRoomStatus.playing,
        );
        final serverRoom = _ServerRoom(
          room: room,
          session: raw['session'] is Map
              ? TRPGSession.fromJson(
                  (raw['session'] as Map).cast<String, Object?>(),
                )
              : null,
          campaignSnapshot: raw['campaignSnapshot'] is Map
              ? (raw['campaignSnapshot'] as Map).cast<String, Object?>()
              : null,
          allowPlayerPrivateChat:
              raw['allowPlayerPrivateChat'] as bool? ?? true,
        );
        for (final entry in ((raw['characters'] as Map?) ?? const {}).entries) {
          serverRoom.pendingCharacters[entry.key
              .toString()] = PlayerCharacter.fromJson(
            (entry.value as Map).cast<String, Object?>(),
          );
        }
        for (final entry
            in ((raw['capabilities'] as Map?) ?? const {}).entries) {
          serverRoom.capabilities[entry.key
              .toString()] = DeviceAIProviderCapability.fromJson(
            (entry.value as Map).cast<String, Object?>(),
          );
        }
        serverRoom.executedCommandIds.addAll(
          (raw['executedCommandIds'] as List? ?? const []).map(
            (e) => e.toString(),
          ),
        );
        _rooms[room.roomId] = serverRoom;
        _roomCodes[room.roomCode] = room.roomId;
        for (final tokenRaw
            in (raw['tokens'] as List? ?? const []).whereType<Map>()) {
          final tokenMap = tokenRaw.cast<String, Object?>();
          final token = tokenMap['token'] as String;
          _tokens[token] = _Identity.fromJson(tokenMap);
        }
      } catch (_) {
        // Corrupt room files stay on disk for manual recovery.
      }
    }
  }

  String _newRoomCode() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    while (true) {
      final code = List.generate(
        6,
        (_) => alphabet[random.nextInt(alphabet.length)],
      ).join();
      if (!_roomCodes.containsKey(code)) return code;
    }
  }

  String _newToken() {
    final random = Random.secure();
    return base64UrlEncode(
      List.generate(32, (_) => random.nextInt(256)),
    ).replaceAll('=', '');
  }

  String _requiredString(Map<String, Object?> source, String key) {
    final value = source[key];
    if (value is! String || value.trim().isEmpty)
      throw FormatException('$key is required');
    return value.trim();
  }

  void _send(WebSocket socket, MultiplayerEnvelope event) {
    if (socket.readyState == WebSocket.open) {
      try {
        socket.add(jsonEncode(event.toJson()));
      } on StateError {
        // The peer closed between readyState and add; disconnect cleanup owns it.
      }
    }
  }

  void _error(
    WebSocket socket,
    String code,
    String message, {
    String? commandId,
  }) => _send(
    socket,
    MultiplayerEnvelope(
      type: MultiplayerEventType.error,
      commandId: commandId,
      payload: {'code': code, 'message': message},
    ),
  );
}

class _ServerRoom {
  _ServerRoom({
    required this.room,
    this.session,
    this.campaignSnapshot,
    this.allowPlayerPrivateChat = true,
  });
  TRPGRoom room;
  TRPGSession? session;
  final sockets = <String, WebSocket>{};
  final pendingCharacters = <String, PlayerCharacter>{};
  final pendingActions = <_QueuedAction>[];
  final executedCommandIds = <String>{};
  final capabilities = <String, DeviceAIProviderCapability>{};
  final resolvingTurnIds = <String>{};
  Timer? settlementTimer;
  _ActiveAction? activeAction;
  String? previousHostId;
  Map<String, Object?>? lastPublicSessionJson;
  final Map<String, Object?>? campaignSnapshot;
  final bool allowPlayerPrivateChat;
  Future<void> persistQueue = Future.value();
}

class _Identity {
  const _Identity({
    required this.roomId,
    required this.playerId,
    required this.token,
    this.userId,
    this.deviceSessionId,
  });
  final String roomId, playerId, token;
  final String? userId, deviceSessionId;
  Map<String, Object?> toJson() => {
    'roomId': roomId,
    'playerId': playerId,
    'userId': userId,
    'deviceSessionId': deviceSessionId,
  };
  factory _Identity.fromJson(Map<String, Object?> json) => _Identity(
    roomId: json['roomId'] as String,
    playerId: json['playerId'] as String,
    token: json['token'] as String,
    userId: json['userId'] as String?,
    deviceSessionId: json['deviceSessionId'] as String?,
  );
}

class _QueuedAction {
  const _QueuedAction({
    required this.actionId,
    required this.playerId,
    required this.characterId,
    required this.content,
    required this.createdAt,
    this.visibility = MultiplayerVisibility.public,
    this.recipientPlayerIds = const [],
    this.turnId,
    this.roundBundle,
    this.isOpening = false,
  });
  final String actionId, playerId, characterId, content;
  final DateTime createdAt;
  final MultiplayerVisibility visibility;
  final List<String> recipientPlayerIds;
  final String? turnId;
  final RoundActionBundle? roundBundle;
  final bool isOpening;
}

class _ActiveAction {
  _ActiveAction({required this.action, required this.messages});
  final _QueuedAction action;
  final List<Map<String, Object?>> messages;
  int round = 0;
  String? requestId;
  Timer? timeout;
}
