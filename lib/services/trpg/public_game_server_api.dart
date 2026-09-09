import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/multiplayer_models.dart';

class PublicRoomBootstrap {
  const PublicRoomBootstrap({
    required this.credentials,
    required this.socketUrl,
  });
  final MultiplayerCredentials credentials;
  final String socketUrl;
}

class PublicGameServerApi {
  PublicGameServerApi({http.Client? client})
    : _client = client ?? http.Client();
  final http.Client _client;

  Future<PublicRoomBootstrap> createRoom({
    required String endpoint,
    required String accessToken,
    required String roomName,
    required String playerName,
    required String campaignId,
    required int maxPlayers,
    required bool allowPlayerPrivateChat,
    Map<String, Object?>? campaignSnapshot,
  }) => _bootstrap(endpoint, '/v1/rooms', accessToken, {
    'roomName': roomName,
    'playerName': playerName,
    'campaignId': campaignId,
    'maxPlayers': maxPlayers,
    'gameMode': 'trpg',
    'rulePackId': 'simple_trpg',
    'privacy': 'private',
    'campaignSnapshot': ?campaignSnapshot,
    'allowPlayerPrivateChat': allowPlayerPrivateChat,
    'settings': const <String, Object?>{},
  });

  Future<PublicRoomBootstrap> joinRoom({
    required String endpoint,
    required String accessToken,
    required String roomCode,
    required String playerName,
  }) => _bootstrap(endpoint, '/v1/rooms/join', accessToken, {
    'roomCode': roomCode.trim().toUpperCase(),
    'playerName': playerName,
  });

  Future<PublicRoomBootstrap> _bootstrap(
    String endpoint,
    String path,
    String token,
    Map<String, Object?> body,
  ) async {
    var base = Uri.parse(endpoint.trim());
    if (base.scheme == 'ws') base = base.replace(scheme: 'http');
    if (base.scheme == 'wss') base = base.replace(scheme: 'https');
    final prefix = base.path.replaceFirst(RegExp(r'/+$'), '');
    final uri = base.replace(path: '$prefix$path', query: null, fragment: null);
    final response = await _client
        .post(
          uri,
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 20));
    final decoded = response.body.isEmpty
        ? <String, Object?>{}
        : (jsonDecode(response.body) as Map).cast<String, Object?>();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = decoded['error'];
      final message = error is Map ? error['message']?.toString() : null;
      throw StateError(message ?? '公网房间服务器请求失败 (${response.statusCode})');
    }
    final socketUrl = decoded['socketUrl']?.toString() ?? '';
    if (socketUrl.isEmpty) throw StateError('服务器没有返回 WebSocket 地址');
    final socket = Uri.parse(socketUrl);
    if (socket.scheme != 'wss' ||
        socket.host != uri.host ||
        (socket.hasPort ? socket.port : 443) !=
            (uri.hasPort ? uri.port : 443) ||
        !socket.path.contains('/v1/rooms/')) {
      throw StateError('服务器返回的连接地址不安全');
    }
    return PublicRoomBootstrap(
      socketUrl: socketUrl,
      credentials: MultiplayerCredentials(
        endpoint: socketUrl,
        roomId: decoded['roomId']!.toString(),
        playerId: decoded['playerId']!.toString(),
        playerSessionId: decoded['playerSessionId']!.toString(),
        sessionToken: decoded['reconnectToken']!.toString(),
        lastRevision: (decoded['revision'] as num?)?.toInt() ?? 0,
      ),
    );
  }

  void close() => _client.close();
}
