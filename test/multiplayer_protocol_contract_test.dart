import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ai_tavern/models/multiplayer_models.dart';
import 'package:ai_tavern/models/trpg_models.dart';

void main() {
  test('Flutter reads the snapshot produced by the real workerd room', () {
    final wire =
        (jsonDecode(
                  File(
                    'shared/protocol/fixtures/public-room-snapshot.json',
                  ).readAsStringSync(),
                )
                as Map)
            .cast<String, Object?>();
    final snapshot = MultiplayerSnapshot.fromJson(wire);
    expect(snapshot.room.players.length, 3);
    expect(snapshot.room.players.every((player) => player.isReady), isTrue);
    expect(
      snapshot.room.players
          .where((player) => player.role == TRPGPlayerRole.roomOwner)
          .length,
      1,
    );
    expect(snapshot.room.aiHostConfig.status, AIHostStatus.ready);
    expect(snapshot.room.currentTurn!.roundNumber, 2);
    expect(snapshot.session!.playerCharacters.length, 1);
    expect(snapshot.session!.playerCharacters.single.hp, 20);
    expect(
      snapshot.session!.chatHistory.any(
        (message) => message.content.contains('门后响起脚步声'),
      ),
      isTrue,
    );
    expect(
      jsonEncode(snapshot.toJson()),
      isNot(contains('PRIVATE_MESSAGE_CANARY')),
    );
    expect(jsonEncode(snapshot.toJson()), isNot(contains('GM_ONLY_CANARY')));
  });
  test('Dart multiplayer events match the shared protocol schema', () {
    final schema =
        (jsonDecode(
                  File(
                    'shared/protocol/protocol.schema.json',
                  ).readAsStringSync(),
                )
                as Map)
            .cast<String, Object?>();
    final properties = (schema['properties'] as Map).cast<String, Object?>();
    final type = (properties['type'] as Map).cast<String, Object?>();
    final serverEvents = (type['enum'] as List)
        .map((value) => value.toString())
        .toSet();
    final clientEvents = MultiplayerEventType.values
        .map((value) => value.name)
        .toSet();
    expect(serverEvents, clientEvents);
    expect(multiplayerProtocolVersion, 3);
  });
}
