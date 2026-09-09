import 'dart:convert';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

const nearbyProtocolVersion = 1;

enum NearbyConnectionStatus {
  idle,
  permissionRequired,
  advertising,
  discovering,
  connecting,
  awaitingVerification,
  connected,
  reconnecting,
  disconnected,
  error,
  unsupported,
}

class NearbySupportState {
  const NearbySupportState({
    required this.platformSupported,
    required this.playServicesAvailable,
    this.playServicesCode = 0,
    this.sdkInt = 0,
    this.backend = 'googleNearby',
  });

  final bool platformSupported, playServicesAvailable;
  final int playServicesCode, sdkInt;
  final String backend;
  bool get available => platformSupported && playServicesAvailable;

  factory NearbySupportState.fromJson(Map<Object?, Object?> json) =>
      NearbySupportState(
        platformSupported: json['platformSupported'] == true,
        playServicesAvailable: json['playServicesAvailable'] == true,
        playServicesCode: (json['playServicesCode'] as num?)?.toInt() ?? 0,
        sdkInt: (json['sdkInt'] as num?)?.toInt() ?? 0,
        backend: json['backend']?.toString() ?? 'googleNearby',
      );
}

class NearbyPermissionState {
  const NearbyPermissionState({
    required this.granted,
    this.missing = const [],
    this.showRationale = false,
    this.mayNeedSettings = false,
  });
  final bool granted, showRationale, mayNeedSettings;
  final List<String> missing;

  factory NearbyPermissionState.fromJson(Map<Object?, Object?> json) =>
      NearbyPermissionState(
        granted: json['granted'] == true,
        missing: (json['missing'] as List? ?? const [])
            .map((value) => value.toString())
            .toList(),
        showRationale: json['showRationale'] == true,
        mayNeedSettings: json['mayNeedSettings'] == true,
      );
}

class NearbyPlatformEvent {
  const NearbyPlatformEvent({required this.type, this.data = const {}});
  final String type;
  final Map<String, Object?> data;

  factory NearbyPlatformEvent.fromJson(Map<Object?, Object?> json) =>
      NearbyPlatformEvent(
        type: json['type']?.toString() ?? 'unknown',
        data: json['data'] is Map
            ? (json['data'] as Map).map(
                (key, value) => MapEntry(key.toString(), value),
              )
            : const {},
      );
}

class NearbyVerificationRequest {
  const NearbyVerificationRequest({
    required this.endpointId,
    required this.endpointName,
    required this.authenticationDigits,
    required this.incoming,
  });
  final String endpointId, endpointName, authenticationDigits;
  final bool incoming;

  factory NearbyVerificationRequest.fromEvent(NearbyPlatformEvent event) =>
      NearbyVerificationRequest(
        endpointId: event.data['endpointId']?.toString() ?? '',
        endpointName: event.data['endpointName']?.toString() ?? '附近设备',
        authenticationDigits:
            event.data['authenticationDigits']?.toString() ?? '----',
        incoming: event.data['incoming'] == true,
      );
}

class NearbyRoomAdvertisement {
  const NearbyRoomAdvertisement({
    required this.endpointId,
    required this.roomId,
    required this.roomCode,
    required this.roomName,
    required this.ownerName,
    required this.currentPlayers,
    required this.maxPlayers,
    this.passwordRequired = false,
  });
  final String endpointId, roomId, roomCode, roomName, ownerName;
  final int currentPlayers, maxPlayers;
  final bool passwordRequired;

  NearbyRoomAdvertisement copyWith({String? endpointId}) =>
      NearbyRoomAdvertisement(
        endpointId: endpointId ?? this.endpointId,
        roomId: roomId,
        roomCode: roomCode,
        roomName: roomName,
        ownerName: ownerName,
        currentPlayers: currentPlayers,
        maxPlayers: maxPlayers,
        passwordRequired: passwordRequired,
      );

  String encodeEndpointName() {
    var safeOwner = ownerName;
    var safeRoomName = roomName;
    String build() => [
      'AIT1',
      Uri.encodeComponent(roomId),
      Uri.encodeComponent(roomCode),
      currentPlayers.toString(),
      maxPlayers.toString(),
      passwordRequired ? '1' : '0',
      Uri.encodeComponent(safeOwner),
      Uri.encodeComponent(safeRoomName),
    ].join('|');

    var value = build();
    while (utf8.encode(value).length > 115 && safeRoomName.isNotEmpty) {
      safeRoomName = safeRoomName.substring(0, safeRoomName.length - 1);
      value = build();
    }
    while (utf8.encode(value).length > 115 && safeOwner.isNotEmpty) {
      safeOwner = safeOwner.substring(0, safeOwner.length - 1);
      value = build();
    }
    return value;
  }

  static NearbyRoomAdvertisement? tryParse(
    String endpointId,
    String endpointName,
  ) {
    final parts = endpointName.split('|');
    if (parts.length < 8 || parts.first != 'AIT1') return null;
    try {
      return NearbyRoomAdvertisement(
        endpointId: endpointId,
        roomId: Uri.decodeComponent(parts[1]),
        roomCode: Uri.decodeComponent(parts[2]),
        currentPlayers: int.parse(parts[3]),
        maxPlayers: int.parse(parts[4]),
        passwordRequired: parts[5] == '1',
        ownerName: Uri.decodeComponent(parts[6]),
        roomName: Uri.decodeComponent(parts.sublist(7).join('|')),
      );
    } catch (_) {
      return null;
    }
  }
}

/// Transport-level envelope. The existing multiplayer message is nested in
/// [payload], so game/business code remains transport agnostic.
class NearbyEnvelope {
  NearbyEnvelope({
    required this.roomId,
    required this.senderPlayerId,
    required this.type,
    required this.payload,
    this.sequenceNumber = 0,
    this.revision = 0,
    String? messageId,
    DateTime? timestamp,
  }) : messageId = messageId ?? const Uuid().v4(),
       timestamp = timestamp ?? DateTime.now().toUtc();

  final String messageId, roomId, senderPlayerId, type;
  final DateTime timestamp;
  final int sequenceNumber, revision;
  final Map<String, Object?> payload;

  Map<String, Object?> toJson() => {
    'protocolVersion': nearbyProtocolVersion,
    'messageId': messageId,
    'roomId': roomId,
    'senderPlayerId': senderPlayerId,
    'type': type,
    'timestamp': timestamp.toIso8601String(),
    'sequenceNumber': sequenceNumber,
    'revision': revision,
    'payload': payload,
  };

  factory NearbyEnvelope.fromJson(Map<String, Object?> json) {
    final version = (json['protocolVersion'] as num?)?.toInt() ?? 0;
    if (version != nearbyProtocolVersion) {
      throw FormatException('不支持的附近联机协议版本：$version');
    }
    return NearbyEnvelope(
      messageId: json['messageId'] as String?,
      roomId: json['roomId']?.toString() ?? '',
      senderPlayerId: json['senderPlayerId']?.toString() ?? '',
      type: json['type']?.toString() ?? 'ERROR',
      timestamp: DateTime.tryParse(json['timestamp']?.toString() ?? ''),
      sequenceNumber: (json['sequenceNumber'] as num?)?.toInt() ?? 0,
      revision: (json['revision'] as num?)?.toInt() ?? 0,
      payload: json['payload'] is Map
          ? (json['payload'] as Map).cast<String, Object?>()
          : const {},
    );
  }
}

/// Nearby BYTES payloads are intentionally kept below the platform limit.
/// Large snapshots are split and reassembled before JSON decoding.
class NearbyPayloadCodec {
  static const _chunkBytes = 18 * 1024;

  static List<Uint8List> encode(NearbyEnvelope envelope) {
    final raw = utf8.encode(jsonEncode(envelope.toJson()));
    if (raw.length <= 28 * 1024) return [Uint8List.fromList(raw)];
    final count = (raw.length / _chunkBytes).ceil();
    return [
      for (var index = 0; index < count; index++)
        Uint8List.fromList(
          utf8.encode(
            jsonEncode({
              '_nearbyFrame': 1,
              'messageId': envelope.messageId,
              'index': index,
              'count': count,
              'data': base64Encode(
                raw.sublist(
                  index * _chunkBytes,
                  ((index + 1) * _chunkBytes).clamp(0, raw.length),
                ),
              ),
            }),
          ),
        ),
    ];
  }
}

class NearbyPayloadAssembler {
  final _chunks = <String, Map<int, Uint8List>>{};
  final _counts = <String, int>{};

  NearbyEnvelope? add(Uint8List packet) {
    final decoded = (jsonDecode(utf8.decode(packet)) as Map)
        .cast<String, Object?>();
    if (decoded['_nearbyFrame'] != 1) {
      return NearbyEnvelope.fromJson(decoded);
    }
    final messageId = decoded['messageId']?.toString() ?? '';
    final index = (decoded['index'] as num?)?.toInt() ?? -1;
    final count = (decoded['count'] as num?)?.toInt() ?? 0;
    if (messageId.isEmpty || index < 0 || count < 1 || index >= count) {
      throw const FormatException('无效的附近联机分片');
    }
    final parts = _chunks.putIfAbsent(messageId, () => {});
    parts[index] = base64Decode(decoded['data']?.toString() ?? '');
    _counts[messageId] = count;
    if (parts.length != count) return null;
    final builder = BytesBuilder(copy: false);
    for (var i = 0; i < count; i++) {
      final chunk = parts[i];
      if (chunk == null) return null;
      builder.add(chunk);
    }
    _chunks.remove(messageId);
    _counts.remove(messageId);
    final whole = (jsonDecode(utf8.decode(builder.takeBytes())) as Map)
        .cast<String, Object?>();
    return NearbyEnvelope.fromJson(whole);
  }
}
