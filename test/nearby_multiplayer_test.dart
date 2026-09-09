import 'dart:typed_data';

import 'package:ai_tavern/models/nearby_models.dart';
import 'package:ai_tavern/services/trpg/android_nearby_transport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Nearby transport endpoint identity', () {
    test('preserves case-sensitive Google Nearby endpoint IDs', () {
      const endpointId = 'AbC9xYzQ';
      final endpoint = AndroidNearbyTransport.endpointFor(endpointId);

      expect(AndroidNearbyTransport.endpointIdFrom(endpoint), endpointId);
    });

    test('preserves Wi-Fi Direct MAC-style endpoint IDs', () {
      const endpointId = 'A2:B3:C4:D5:E6:F7';
      final endpoint = AndroidNearbyTransport.endpointFor(endpointId);

      expect(AndroidNearbyTransport.endpointIdFrom(endpoint), endpointId);
    });

    test('reads legacy authority endpoints without lowercasing', () {
      expect(
        AndroidNearbyTransport.endpointIdFrom('nearby://AbC9xYzQ'),
        'AbC9xYzQ',
      );
    });
  });

  group('Nearby room advertisement', () {
    test('round trips compact Unicode room metadata', () {
      const source = NearbyRoomAdvertisement(
        endpointId: '',
        roomId: 'room-stable-id',
        roomCode: 'AB12CD',
        roomName: '雾港疑云·旧仓库调查团',
        ownerName: '测试房主',
        currentPlayers: 2,
        maxPlayers: 5,
      );

      final encoded = source.encodeEndpointName();
      expect(encoded.codeUnits, isNotEmpty);
      expect(encoded.length, lessThan(120));

      final decoded = NearbyRoomAdvertisement.tryParse('endpoint-1', encoded);
      expect(decoded, isNotNull);
      expect(decoded!.endpointId, 'endpoint-1');
      expect(decoded.roomId, source.roomId);
      expect(decoded.roomCode, source.roomCode);
      expect(decoded.ownerName, source.ownerName);
      expect(decoded.currentPlayers, 2);
      expect(decoded.maxPlayers, 5);
    });

    test('ignores advertisements from unrelated Nearby services', () {
      expect(
        NearbyRoomAdvertisement.tryParse('endpoint-2', 'someone-else'),
        isNull,
      );
    });
  });

  group('Nearby payload framing', () {
    test('round trips a normal envelope', () {
      final source = NearbyEnvelope(
        roomId: 'room-1',
        senderPlayerId: 'player-1',
        type: 'PLAYER_ACTION',
        sequenceNumber: 8,
        revision: 3,
        payload: {
          'multiplayer': {'content': '检查仓库侧门'},
        },
      );
      final packets = NearbyPayloadCodec.encode(source);
      expect(packets, hasLength(1));
      final decoded = NearbyPayloadAssembler().add(packets.single);
      expect(decoded?.messageId, source.messageId);
      expect(decoded?.sequenceNumber, 8);
      expect(decoded?.revision, 3);
    });

    test('splits and reassembles a large snapshot out of order', () {
      final source = NearbyEnvelope(
        roomId: 'room-large',
        senderPlayerId: 'authority',
        type: 'SNAPSHOT',
        sequenceNumber: 42,
        revision: 19,
        payload: {'snapshot': '剧情状态' * 30000},
      );
      final packets = NearbyPayloadCodec.encode(source);
      expect(packets.length, greaterThan(2));

      final assembler = NearbyPayloadAssembler();
      NearbyEnvelope? decoded;
      for (final packet in packets.reversed) {
        decoded = assembler.add(Uint8List.fromList(packet)) ?? decoded;
      }
      expect(decoded, isNotNull);
      expect(decoded!.messageId, source.messageId);
      expect(decoded.payload['snapshot'], source.payload['snapshot']);
      expect(decoded.revision, 19);
    });

    test('rejects protocol versions from an incompatible app', () {
      expect(
        () =>
            NearbyEnvelope.fromJson({'protocolVersion': 99, 'messageId': 'x'}),
        throwsFormatException,
      );
    });
  });
}
