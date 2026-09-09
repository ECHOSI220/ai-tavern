// ignore_for_file: curly_braces_in_flow_control_structures, prefer_initializing_formals

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:uuid/uuid.dart';

import '../../models/multiplayer_models.dart';
import '../../models/trpg_models.dart';
import '../../models/social_models.dart';
import 'public_game_server_api.dart';

abstract interface class MultiplayerTransport {
  Stream<MultiplayerEnvelope> get events;
  bool get isConnected;
  Future<void> connect(String endpoint);
  Future<void> send(MultiplayerEnvelope envelope);
  Future<void> disconnect();
}

class WebSocketTransport implements MultiplayerTransport {
  WebSocketTransport({
    WebSocket Function(Uri uri)? connector,
    this.authorizationToken,
  }) : _connector = connector;

  final WebSocket Function(Uri uri)? _connector;
  String? authorizationToken;
  final _events = StreamController<MultiplayerEnvelope>.broadcast();
  WebSocket? _socket;
  StreamSubscription<Object?>? _subscription;
  Timer? _reconnectTimer;
  int _connectionGeneration = 0;
  int _reconnectAttempts = 0;
  Uri? _reconnectUri;

  @override
  Stream<MultiplayerEnvelope> get events => _events.stream;
  @override
  bool get isConnected => _socket?.readyState == WebSocket.open;

  @override
  Future<void> connect(String endpoint) async {
    await disconnect();
    var uri = Uri.parse(endpoint.trim());
    if (uri.scheme == 'http') uri = uri.replace(scheme: 'ws');
    if (uri.scheme == 'https') uri = uri.replace(scheme: 'wss');
    if (uri.path.isEmpty || uri.path == '/') uri = uri.replace(path: '/ws');
    _reconnectUri = uri;
    _reconnectAttempts = 0;
    await _open(uri, _connectionGeneration);
  }

  Future<void> _open(Uri uri, int generation) async {
    final socket =
        _connector?.call(uri) ??
        await WebSocket.connect(
          uri.toString(),
          headers:
              authorizationToken == null ||
                  uri.scheme != 'wss' ||
                  !uri.path.contains('/v1/rooms/')
              ? null
              : {'Authorization': 'Bearer $authorizationToken'},
        ).timeout(const Duration(seconds: 15));
    if (generation != _connectionGeneration) {
      await socket.close(WebSocketStatus.normalClosure, 'connection_cancelled');
      return;
    }
    _socket = socket;
    socket.pingInterval = const Duration(seconds: 20);
    _subscription = socket.listen(
      (data) {
        if (generation != _connectionGeneration || _socket != socket) return;
        try {
          final decoded = jsonDecode(data.toString());
          _reconnectAttempts = 0;
          _events.add(
            MultiplayerEnvelope.fromJson(
              (decoded as Map).cast<String, Object?>(),
            ),
          );
        } catch (error, stackTrace) {
          _events.addError(error, stackTrace);
        }
      },
      onError: (Object error, StackTrace stack) {
        if (generation != _connectionGeneration || _socket != socket) return;
        _events.addError(StateError('联机连接中断，正在尝试恢复'), stack);
        _scheduleReconnect(uri, generation);
      },
      onDone: () {
        if (generation != _connectionGeneration || _socket != socket) return;
        _socket = null;
        if (socket.closeCode != WebSocketStatus.normalClosure &&
            socket.closeCode != WebSocketStatus.policyViolation) {
          _scheduleReconnect(uri, generation);
        } else {
          _reconnectTimer?.cancel();
          _reconnectTimer = null;
        }
      },
    );
  }

  void _scheduleReconnect(Uri uri, int generation) {
    // Public sockets authenticate and return a fresh snapshot on every upgrade.
    // Legacy/Nearby rooms use their existing explicit reconnect handshake.
    if (generation != _connectionGeneration ||
        _reconnectUri != uri ||
        uri.scheme != 'wss' ||
        !uri.path.contains('/v1/rooms/') ||
        _reconnectTimer != null)
      return;
    if (_reconnectAttempts >= 8) {
      _events.addError(StateError('暂时无法恢复联机，请检查网络并重新登录后重连'));
      return;
    }
    final seconds = [1, 2, 4, 8, 15, 30, 30, 30][_reconnectAttempts++];
    _reconnectTimer = Timer(Duration(seconds: seconds), () async {
      _reconnectTimer = null;
      if (generation != _connectionGeneration) return;
      final old = _socket;
      _socket = null;
      await _subscription?.cancel();
      unawaited(old?.close() ?? Future<void>.value());
      if (generation != _connectionGeneration) return;
      try {
        await _open(uri, generation);
      } catch (_) {
        _scheduleReconnect(uri, generation);
      }
    });
  }

  @override
  Future<void> send(MultiplayerEnvelope envelope) async {
    final socket = _socket;
    if (socket == null || socket.readyState != WebSocket.open)
      throw StateError('WebSocket 未连接');
    socket.add(jsonEncode(envelope.toJson()));
  }

  @override
  Future<void> disconnect() async {
    _connectionGeneration++;
    _reconnectUri = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _subscription?.cancel();
    _subscription = null;
    final socket = _socket;
    _socket = null;
    await socket?.close(WebSocketStatus.normalClosure, 'client_disconnect');
  }
}

class MultiplayerClient {
  MultiplayerClient({MultiplayerTransport? transport})
    : transport = transport ?? WebSocketTransport();

  final MultiplayerTransport transport;
  final _state = StreamController<MultiplayerSnapshot>.broadcast();
  final _events = StreamController<MultiplayerEnvelope>.broadcast();
  final _uuid = const Uuid();
  StreamSubscription<MultiplayerEnvelope>? _subscription;
  MultiplayerCredentials? credentials;
  MultiplayerSnapshot? snapshot;
  String _endpoint = '';
  final PublicGameServerApi _publicApi = PublicGameServerApi();

  Stream<MultiplayerSnapshot> get states => _state.stream;
  Stream<MultiplayerEnvelope> get events => _events.stream;
  bool get isConnected => transport.isConnected;

  Future<void> connect(String endpoint) async {
    _endpoint = endpoint;
    await _subscription?.cancel();
    _subscription = transport.events.listen(
      _handleEvent,
      onError: _events.addError,
    );
    await transport.connect(endpoint);
  }

  Future<void> createRoom({
    required String endpoint,
    required String roomName,
    required String playerName,
    String campaignId = 'mist_harbor_test',
    int maxPlayers = 4,
    AIHostMode gmMode = AIHostMode.selectedPlayer,
    Map<String, Object?>? campaignSnapshot,
    bool allowPlayerPrivateChat = true,
    AuthTokens? account,
    CampaignRoomKind kind = CampaignRoomKind.temporary,
    String? persistentCampaignRoomId,
  }) async {
    if (_isPublicEndpoint(endpoint)) {
      final token = account?.accessToken;
      if (token == null || token.isEmpty) throw StateError('公网联机需要先登录账号');
      final bootstrap = await _publicApi.createRoom(
        endpoint: endpoint,
        accessToken: token,
        roomName: roomName,
        playerName: playerName,
        campaignId: campaignId,
        maxPlayers: maxPlayers,
        allowPlayerPrivateChat: allowPlayerPrivateChat,
        campaignSnapshot: campaignSnapshot,
      );
      credentials = bootstrap.credentials;
      if (transport is WebSocketTransport)
        (transport as WebSocketTransport).authorizationToken = token;
      await connect(bootstrap.socketUrl);
      return;
    }
    if (!isConnected) await connect(endpoint);
    await _send(MultiplayerEventType.createRoom, {
      'roomName': roomName,
      'playerName': playerName,
      'campaignId': campaignId,
      'maxPlayers': maxPlayers,
      'gmMode': gmMode.name,
      'campaignSnapshot': campaignSnapshot,
      'allowPlayerPrivateChat': allowPlayerPrivateChat,
      'accessToken': account?.accessToken,
      'kind': kind.name,
      'persistentCampaignRoomId': persistentCampaignRoomId,
    }, authenticated: false);
  }

  Future<void> joinRoom({
    required String endpoint,
    required String roomCode,
    required String playerName,
    AuthTokens? account,
    String? persistentCampaignRoomId,
  }) async {
    if (_isPublicEndpoint(endpoint)) {
      final token = account?.accessToken;
      if (token == null || token.isEmpty) throw StateError('公网联机需要先登录账号');
      final bootstrap = await _publicApi.joinRoom(
        endpoint: endpoint,
        accessToken: token,
        roomCode: roomCode,
        playerName: playerName,
      );
      credentials = bootstrap.credentials;
      if (transport is WebSocketTransport)
        (transport as WebSocketTransport).authorizationToken = token;
      await connect(bootstrap.socketUrl);
      return;
    }
    if (!isConnected) await connect(endpoint);
    await _send(MultiplayerEventType.joinRoom, {
      'roomCode': roomCode.trim().toUpperCase(),
      'playerName': playerName,
      'accessToken': account?.accessToken,
      'persistentCampaignRoomId': persistentCampaignRoomId,
    }, authenticated: false);
  }

  Future<void> reconnect(MultiplayerCredentials saved) async {
    credentials = saved;
    if (!isConnected) await connect(saved.endpoint);
    if (saved.playerSessionId != null && saved.endpoint.contains('/v1/rooms/'))
      return;
    await transport.send(
      MultiplayerEnvelope(
        type: MultiplayerEventType.reconnect,
        roomId: saved.roomId,
        token: saved.sessionToken,
        payload: {
          'sessionToken': saved.sessionToken,
          'lastRevision': saved.lastRevision,
        },
      ),
    );
  }

  Future<void> setReady(bool ready) =>
      command(MultiplayerEventType.playerReady, {'ready': ready});
  Future<void> selectCharacter(PlayerCharacter character) => command(
    MultiplayerEventType.selectCharacter,
    {'character': character.toJson()},
  );
  Future<void> requestHost(
    String playerId, {
    String? modelId,
    int maxRequests = 0,
    int maxTokens = 0,
  }) => command(MultiplayerEventType.hostRequested, {
    'providerPlayerId': playerId,
    'providerType': 'openai-compatible',
    'modelId': modelId,
    'maxRequests': maxRequests,
    'maxTokens': maxTokens,
  });
  Future<void> acceptHost({
    required String modelId,
    String providerType = 'openai-compatible',
  }) => command(MultiplayerEventType.hostAccepted, {
    'modelId': modelId,
    'providerType': providerType,
  });
  Future<void> declineHost() => command(MultiplayerEventType.hostDeclined);
  Future<void> startGame() => command(MultiplayerEventType.gameStarted);
  Future<void> submitAction(String content, {String? actionId}) => command(
    MultiplayerEventType.playerAction,
    {'content': content, 'actionId': actionId ?? _uuid.v4()},
  );
  Future<void> confirmTurnAction({
    required String turnId,
    required String content,
    String? actionId,
    bool secret = false,
  }) => command(MultiplayerEventType.turnActionConfirm, {
    'turnId': turnId,
    'content': content.trim(),
    'isPass': content.trim().isEmpty,
    'actionId': actionId ?? _uuid.v4(),
    'secret': secret,
  });
  Future<void> unconfirmTurnAction(String turnId) =>
      command(MultiplayerEventType.turnActionUnconfirm, {'turnId': turnId});
  Future<void> skipTurnPlayer(String turnId, String playerId) => command(
    MultiplayerEventType.turnSkipPlayer,
    {'turnId': turnId, 'playerId': playerId},
  );
  Future<void> resolveHumanGmTurn(String turnId, String narration) => command(
    MultiplayerEventType.turnResolved,
    {'turnId': turnId, 'narration': narration},
  );
  Future<void> submitSecretAction(String content, {String? actionId}) =>
      command(MultiplayerEventType.secretAction, {
        'content': content,
        'actionId': actionId ?? _uuid.v4(),
      });
  Future<void> submitChat(String content) =>
      command(MultiplayerEventType.playerChat, {'content': content});
  Future<void> sendPrivateMessage(
    String content, {
    List<String> recipientPlayerIds = const [],
    bool toGm = false,
  }) => command(MultiplayerEventType.privateMessage, {
    'content': content,
    'recipientPlayerIds': recipientPlayerIds,
    'toGm': toGm,
  });
  Future<void> privateRoll({
    int sides = 20,
    String? formula,
    String reason = '',
  }) {
    final payload = <String, Object?>{'sides': sides, 'reason': reason};
    if (formula != null) payload['formula'] = formula;
    return command(MultiplayerEventType.privateRoll, payload);
  }

  Future<void> revealInformation(String knowledgeId) => command(
    MultiplayerEventType.revealInformation,
    {'knowledgeId': knowledgeId},
  );
  Future<void> retryAction() => command(MultiplayerEventType.retryAction);
  Future<void> sendPresentationEvent(Map<String, Object?> event) =>
      command(MultiplayerEventType.presentationEvent, {'event': event});
  Future<void> heartbeat() => command(MultiplayerEventType.hostHeartbeat);
  Future<void> sendDeviceCapability({
    required bool supportsAIHost,
    required List<String> providerTypes,
    required bool toolCallingVerified,
    bool autoAcceptForCampaign = false,
  }) => command(MultiplayerEventType.deviceCapability, {
    'supportsAIHost': supportsAIHost,
    'providerTypes': providerTypes,
    'toolCallingVerified': toolCallingVerified,
    'autoAcceptForCampaign': autoAcceptForCampaign,
  });
  Future<void> requestSnapshot() =>
      command(MultiplayerEventType.requestSnapshot);

  Future<void> sendAIResponse({
    required String requestId,
    required Map<String, Object?> response,
    int inputTokens = 0,
    int outputTokens = 0,
  }) => command(MultiplayerEventType.aiResponse, {
    'requestId': requestId,
    'response': response,
    'inputTokens': inputTokens,
    'outputTokens': outputTokens,
  });

  Future<void> command(
    MultiplayerEventType type, [
    Map<String, Object?> payload = const {},
  ]) => _send(type, payload, authenticated: true);

  Future<void> _send(
    MultiplayerEventType type,
    Map<String, Object?> payload, {
    required bool authenticated,
  }) {
    final auth = credentials;
    if (authenticated && auth == null) throw StateError('尚未加入房间');
    return transport.send(
      MultiplayerEnvelope(
        type: type,
        commandId: _uuid.v4(),
        roomId: auth?.roomId,
        token: auth?.sessionToken,
        revision: snapshot?.room.revision ?? 0,
        payload: payload,
      ),
    );
  }

  void _handleEvent(MultiplayerEnvelope event) {
    _events.add(event);
    if (event.type == MultiplayerEventType.roomCreated ||
        event.type == MultiplayerEventType.snapshot) {
      final rawSnapshot = event.payload['snapshot'] is Map
          ? (event.payload['snapshot'] as Map).cast<String, Object?>()
          : event.payload;
      if (rawSnapshot['room'] is Map) {
        snapshot = MultiplayerSnapshot.fromJson(rawSnapshot);
        final token = event.payload['sessionToken'] as String? ?? event.token;
        final playerId = event.payload['playerId'] as String?;
        if (token != null && playerId != null) {
          credentials = MultiplayerCredentials(
            endpoint: credentials?.endpoint.isNotEmpty == true
                ? credentials!.endpoint
                : _endpoint,
            roomId: snapshot!.room.roomId,
            playerId: playerId,
            sessionToken: token,
            playerSessionId:
                event.payload['playerSessionId'] as String? ??
                credentials?.playerSessionId,
            lastRevision: snapshot!.room.revision,
          );
        } else if (credentials != null) {
          credentials = MultiplayerCredentials(
            endpoint: credentials!.endpoint,
            roomId: credentials!.roomId,
            playerId: credentials!.playerId,
            sessionToken: credentials!.sessionToken,
            playerSessionId: credentials!.playerSessionId,
            lastRevision: snapshot!.room.revision,
          );
        }
        _state.add(snapshot!);
      }
      return;
    }
    if (event.type == MultiplayerEventType.statePatch) {
      final current = snapshot;
      if (current == null) return;
      if (event.revision < current.room.revision) return;
      if (event.revision > current.room.revision + 1) {
        requestSnapshot();
        return;
      }
      final room = event.payload['room'] is Map
          ? TRPGRoom.fromJson(
              (event.payload['room'] as Map).cast<String, Object?>(),
            )
          : current.room;
      var session = current.session;
      if (event.payload['session'] is Map) {
        session = TRPGSession.fromJson(
          (event.payload['session'] as Map).cast<String, Object?>(),
        );
      } else if (event.payload['sessionPatch'] is Map) {
        final base = session?.toJson() ?? <String, Object?>{};
        final merged = _applyMergePatch(
          base,
          (event.payload['sessionPatch'] as Map).cast<String, Object?>(),
        );
        if (merged.isNotEmpty) session = TRPGSession.fromJson(merged);
      }
      snapshot = MultiplayerSnapshot(room: room, session: session);
      _state.add(snapshot!);
    }
  }

  Map<String, Object?> _applyMergePatch(
    Map<String, Object?> target,
    Map<String, Object?> patch,
  ) {
    final result = (jsonDecode(jsonEncode(target)) as Map)
        .cast<String, Object?>();
    for (final entry in patch.entries) {
      if (entry.value == null) {
        result.remove(entry.key);
      } else if (entry.value is Map && result[entry.key] is Map) {
        result[entry.key] = _applyMergePatch(
          (result[entry.key] as Map).cast<String, Object?>(),
          (entry.value as Map).cast<String, Object?>(),
        );
      } else {
        result[entry.key] = entry.value;
      }
    }
    return result;
  }

  Future<void> close() async {
    await _subscription?.cancel();
    await transport.disconnect();
    await _state.close();
    await _events.close();
    _publicApi.close();
  }

  bool _isPublicEndpoint(String endpoint) {
    final uri = Uri.tryParse(endpoint.trim());
    if (uri == null || uri.scheme == 'nearby') return false;
    return (uri.scheme == 'https' || uri.scheme == 'wss') &&
        !uri.path.endsWith('/ws');
  }
}

/// Backward-compatible Phase 1 interface retained for old tests/integrations.
abstract interface class TRPGNetworkAdapter {
  Stream<TRPGSession> watchSession(String sessionId);
  Future<void> connect(String sessionId);
  Future<void> publish(TRPGSession session);
  Future<void> disconnect();
}

class LocalMockTransport implements TRPGNetworkAdapter {
  TRPGSession? _session;
  @override
  Future<void> connect(String sessionId) async {}
  @override
  Future<void> disconnect() async {}
  @override
  Future<void> publish(TRPGSession session) async => _session = session;
  @override
  Stream<TRPGSession> watchSession(String sessionId) async* {
    if (_session case final session?) yield session;
  }
}
