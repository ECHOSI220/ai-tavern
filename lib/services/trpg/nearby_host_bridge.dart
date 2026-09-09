import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../models/multiplayer_models.dart';
import '../../models/nearby_models.dart';
import 'multiplayer_server.dart';
import 'nearby_connections_manager.dart';

class NearbyHostBridge {
  NearbyHostBridge({ProximityConnectionsManager? manager})
    : _manager = manager ?? NearbyConnectionsManager.instance;

  final ProximityConnectionsManager _manager;
  final _verificationRequests =
      StreamController<NearbyVerificationRequest>.broadcast();
  final _connectionNotices = StreamController<String>.broadcast();
  final _proxies = <String, WebSocket>{};
  final _pendingPackets = <String, List<Uint8List>>{};
  final _assemblers = <String, NearbyPayloadAssembler>{};
  final _seenByEndpoint = <String, Set<String>>{};
  StreamSubscription<NearbyPlatformEvent>? _subscription;
  MultiplayerAuthoritativeServer? _server;
  NearbyRoomAdvertisement? _advertisement;
  bool _closed = false;

  Stream<NearbyVerificationRequest> get verificationRequests =>
      _verificationRequests.stream;
  Stream<String> get connectionNotices => _connectionNotices.stream;
  String get localEndpoint {
    final server = _server;
    if (server == null) throw StateError('附近联机权威服务尚未启动');
    return 'ws://127.0.0.1:${server.port}/ws';
  }

  Future<void> startAuthority() async {
    if (_server != null) return;
    final root = await Directory.systemTemp.createTemp('ai_tavern_nearby_');
    final server = MultiplayerAuthoritativeServer(
      config: MultiplayerServerConfig(
        address: '127.0.0.1',
        port: 0,
        persistenceDirectory: root.path,
      ),
    );
    await server.start();
    _server = server;
    _subscription = _manager.events.listen(_onPlatformEvent);
  }

  Future<void> advertise(NearbyRoomAdvertisement advertisement) async {
    _advertisement = advertisement;
    await _manager.startAdvertising(
      endpointName: advertisement.encodeEndpointName(),
      roomName: advertisement.roomName,
    );
  }

  Future<void> updateAdvertisement(
    NearbyRoomAdvertisement advertisement,
  ) async {
    if (_closed) return;
    final previous = _advertisement;
    _advertisement = advertisement;
    if (previous?.encodeEndpointName() == advertisement.encodeEndpointName()) {
      return;
    }
    // Wi-Fi Direct advertising is bound to the authoritative P2P group.
    // Restarting it just to refresh the player count would tear down every
    // connected socket, so keep the room alive until the host closes it.
    if (_manager is WifiDirectConnectionsManager) return;
    await _manager.stopAdvertising();
    await _manager.startAdvertising(
      endpointName: advertisement.encodeEndpointName(),
      roomName: advertisement.roomName,
    );
  }

  Future<void> accept(String endpointId) =>
      _manager.acceptConnection(endpointId);
  Future<void> reject(String endpointId) =>
      _manager.rejectConnection(endpointId);

  void _onPlatformEvent(NearbyPlatformEvent event) {
    final endpointId = event.data['endpointId']?.toString() ?? '';
    if (event.type == 'verificationRequired' &&
        event.data['incoming'] == true) {
      _verificationRequests.add(NearbyVerificationRequest.fromEvent(event));
      return;
    }
    if (event.type == 'connected' && endpointId.isNotEmpty) {
      unawaited(_openProxy(endpointId));
      return;
    }
    if (event.type == 'bytesReceived' && endpointId.isNotEmpty) {
      final raw = event.data['bytes'];
      final packet = raw is Uint8List
          ? raw
          : Uint8List.fromList((raw as List).cast<int>());
      final socket = _proxies[endpointId];
      if (socket == null) {
        _pendingPackets.putIfAbsent(endpointId, () => []).add(packet);
      } else {
        _forwardToAuthority(endpointId, socket, packet);
      }
      return;
    }
    if (event.type == 'disconnected' && endpointId.isNotEmpty) {
      unawaited(_closeProxy(endpointId));
      _connectionNotices.add('附近玩家已断开，可重新搜索并用原存档凭证恢复。');
    }
  }

  Future<void> _openProxy(String endpointId) async {
    if (_closed || _proxies.containsKey(endpointId)) return;
    try {
      final socket = await WebSocket.connect(localEndpoint);
      _proxies[endpointId] = socket;
      socket.listen(
        (raw) => _forwardToNearby(endpointId, raw.toString()),
        onError: (_) => _closeProxy(endpointId),
        onDone: () => _closeProxy(endpointId),
      );
      final pending = _pendingPackets.remove(endpointId) ?? const [];
      for (final packet in pending) {
        _forwardToAuthority(endpointId, socket, packet);
      }
      _connectionNotices.add('附近玩家已安全连接。');
    } catch (error) {
      _connectionNotices.add('无法建立房主权威通道：$error');
      await _manager.disconnectEndpoint(endpointId);
    }
  }

  void _forwardToAuthority(
    String endpointId,
    WebSocket socket,
    Uint8List packet,
  ) {
    try {
      final assembler = _assemblers.putIfAbsent(
        endpointId,
        NearbyPayloadAssembler.new,
      );
      final nearby = assembler.add(packet);
      if (nearby == null) return;
      final seen = _seenByEndpoint.putIfAbsent(endpointId, () => {});
      if (!seen.add(nearby.messageId)) return;
      if (seen.length > 2048) seen.clear();
      final multiplayer = nearby.payload['multiplayer'];
      if (multiplayer is! Map) return;
      socket.add(jsonEncode(multiplayer));
    } catch (error) {
      _connectionNotices.add('忽略了一条损坏的附近消息：$error');
    }
  }

  Future<void> _forwardToNearby(String endpointId, String raw) async {
    try {
      final inner = (jsonDecode(raw) as Map).cast<String, Object?>();
      final multiplayer = MultiplayerEnvelope.fromJson(inner);
      final nearby = NearbyEnvelope(
        roomId: multiplayer.roomId ?? _advertisement?.roomCode ?? '',
        senderPlayerId: 'nearby-authority',
        type: multiplayer.type.name.toUpperCase(),
        sequenceNumber: multiplayer.sequenceNumber,
        revision: multiplayer.revision,
        payload: {'multiplayer': inner},
      );
      for (final packet in NearbyPayloadCodec.encode(nearby)) {
        await _manager.sendBytes(endpointId, packet);
      }
    } catch (error) {
      _connectionNotices.add('发送附近状态失败：$error');
    }
  }

  Future<void> _closeProxy(String endpointId) async {
    final socket = _proxies.remove(endpointId);
    _pendingPackets.remove(endpointId);
    _assemblers.remove(endpointId);
    _seenByEndpoint.remove(endpointId);
    await socket?.close(WebSocketStatus.normalClosure, 'nearby_disconnected');
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _subscription?.cancel();
    await _manager.disconnectAll();
    for (final endpointId in _proxies.keys.toList()) {
      await _closeProxy(endpointId);
    }
    await _server?.stop();
    _server = null;
    await _verificationRequests.close();
    await _connectionNotices.close();
  }
}
