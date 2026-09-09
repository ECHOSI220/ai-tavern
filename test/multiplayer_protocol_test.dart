import 'package:ai_tavern/models/multiplayer_models.dart';
import 'package:ai_tavern/models/trpg_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('multiplayer envelope round trip keeps protocol and ordering', () {
    const source = MultiplayerEnvelope(
      type: MultiplayerEventType.playerAction,
      commandId: 'command-1',
      roomId: 'room-1',
      token: 'secret-token',
      sequenceNumber: 7,
      revision: 12,
      payload: {'actionId': 'action-1', 'content': '检查门锁'},
      visibility: MultiplayerVisibility.selectedPlayers,
      recipientPlayerIds: ['player-a'],
    );
    final decoded = MultiplayerEnvelope.fromJson(source.toJson());
    expect(decoded.type, MultiplayerEventType.playerAction);
    expect(decoded.sequenceNumber, 7);
    expect(decoded.revision, 12);
    expect(decoded.payload['actionId'], 'action-1');
    expect(decoded.visibility, MultiplayerVisibility.selectedPlayers);
    expect(decoded.recipientPlayerIds, ['player-a']);
  });

  test('room snapshot never contains an API key field', () {
    final now = DateTime.utc(2026, 8, 14);
    final room = TRPGRoom(
      roomId: 'room',
      roomCode: '7K4P9F',
      roomName: '测试团',
      ownerPlayerId: 'owner',
      campaignId: 'mist_harbor_test',
      createdAt: now,
      updatedAt: now,
      players: [TRPGPlayer(playerId: 'owner', displayName: 'A', joinedAt: now)],
      aiHostConfig: const AIHostConfig(
        mode: AIHostMode.selectedPlayer,
        providerPlayerId: 'owner',
        modelId: 'tool-model',
        status: AIHostStatus.ready,
      ),
    );
    final encoded = room.toJson().toString().toLowerCase();
    expect(encoded, isNot(contains('apikey')));
    expect(encoded, isNot(contains('authorization')));
  });
}
