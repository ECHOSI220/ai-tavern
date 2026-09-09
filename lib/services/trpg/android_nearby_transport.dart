import 'dart:async';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../../models/multiplayer_models.dart';
import '../../models/nearby_models.dart';
import 'multiplayer_transport.dart';
import 'nearby_connections_manager.dart';

class AndroidNearbyTransport implements MultiplayerTransport {
  AndroidNearbyTransport({
    ProximityConnectionsManager? manager,
    String? senderSessionId,
  }) : _manager = manager ?? NearbyConnectionsManager.instance,
       _senderSessionId = senderSessionId ?? const Uuid().v4() {
    _subscription = _manager.events.listen(_onPlatformEvent);
  }

  final ProximityConnectionsManager _manager;
  final String _senderSessionId;
  final _events = StreamController<MultiplayerEnvelope>.broadcast();
  final _seenMessageIds = <String>{};
  final _assembler = NearbyPayloadAssembler();
  StreamSubscription<NearbyPlatformEvent>? _subscription;
  String? _endpointId;

  /// Keeps Nearby endpoint IDs byte-for-byte intact. Treating the ID as a URI
  /// host lowercases Google endpoint IDs and interprets Wi-Fi Direct MAC
  /// colons as a port separator.
  static String endpointFor(String endpointId) =>
      'nearby:${Uri.encodeComponent(endpointId)}';

  static String endpointIdFrom(String endpoint) {
    const scheme = 'nearby:';
    if (!endpoint.startsWith(scheme)) {
      throw const FormatException('无效的附近联机地址');
    }
    var encoded = endpoint.substring(scheme.length);
    // Read legacy nearby://endpoint values without Uri.host normalization.
    if (encoded.startsWith('//')) encoded = encoded.substring(2);
    if (encoded.isEmpty) throw const FormatException('无效的附近联机地址');
    final endpointId = Uri.decodeComponent(encoded);
    if (endpointId.isEmpty) throw const FormatException('无效的附近联机地址');
    return endpointId;
  }

  @override
  Stream<MultiplayerEnvelope> get events => _events.stream;
  @override
  bool get isConnected =>
      _endpointId != null && _manager.isEndpointConnected(_endpointId!);

  @override
  Future<void> connect(String endpoint) async {
    final endpointId = endpointIdFrom(endpoint);
    _endpointId = endpointId;
    if (!_manager.isEndpointConnected(endpointId)) {
      throw StateError('附近设备尚未完成双端认证');
    }
  }

  @override
  Future<void> send(MultiplayerEnvelope envelope) async {
    final endpointId = _endpointId;
    if (endpointId == null || !_manager.isEndpointConnected(endpointId)) {
      throw StateError('附近连接已断开');
    }
    final nearby = NearbyEnvelope(
      roomId: envelope.roomId ?? '',
      senderPlayerId: _senderSessionId,
      type: envelope.type.name.toUpperCase(),
      sequenceNumber: envelope.sequenceNumber,
      revision: envelope.revision,
      payload: {'multiplayer': envelope.toJson()},
    );
    for (final packet in NearbyPayloadCodec.encode(nearby)) {
      await _manager.sendBytes(endpointId, packet);
    }
  }

  void _onPlatformEvent(NearbyPlatformEvent event) {
    if (event.type != 'bytesReceived' ||
        event.data['endpointId']?.toString() != _endpointId) {
      return;
    }
    try {
      final raw = event.data['bytes'];
      final bytes = raw is Uint8List
          ? raw
          : Uint8List.fromList((raw as List).cast<int>());
      final nearby = _assembler.add(bytes);
      if (nearby == null) return;
      if (!_seenMessageIds.add(nearby.messageId)) return;
      if (_seenMessageIds.length > 2048) _seenMessageIds.clear();
      final inner = nearby.payload['multiplayer'];
      if (inner is! Map) throw const FormatException('附近消息缺少游戏内容');
      _events.add(MultiplayerEnvelope.fromJson(inner.cast<String, Object?>()));
    } catch (error, stackTrace) {
      _events.addError(error, stackTrace);
    }
  }

  @override
  Future<void> disconnect() async {
    final endpointId = _endpointId;
    _endpointId = null;
    if (endpointId != null) await _manager.disconnectEndpoint(endpointId);
  }

  Future<void> dispose() async {
    await disconnect();
    await _subscription?.cancel();
    await _events.close();
  }
}
