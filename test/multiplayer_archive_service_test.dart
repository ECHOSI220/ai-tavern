import 'package:flutter_test/flutter_test.dart';
import 'package:ai_tavern/models/trpg_models.dart';
import 'package:ai_tavern/services/trpg/multiplayer_archive_service.dart';
import 'package:ai_tavern/services/trpg/cloud_save_service.dart';

void main() {
  test('personal archive roundtrip and solo branch keep actor, HP and round', () {
    final now = DateTime.utc(2026);
    final archive = TRPGSession(id: 'archive', title: 'Adventure', mode: TRPGMode.multiplayer, campaignId: 'campaign', createdAt: now, updatedAt: now, lastPlayedAt: now,
      metadata: const {'localMultiplayerArchive': true, 'localPlayerId': 'b'},
      players: [TRPGPlayer(playerId: 'a', displayName: 'A', characterId: 'ca', joinedAt: now), TRPGPlayer(playerId: 'b', displayName: 'B', characterId: 'cb', joinedAt: now)],
      playerCharacters: const [PlayerCharacter(id: 'ca', playerId: 'a', name: 'A'), PlayerCharacter(id: 'cb', playerId: 'b', name: 'B', hp: 7)],
      ruleState: const RuleState(round: 3),
      chatHistory: [TRPGMessage(id: 'm', messageType: TRPGMessageType.gmMessage, content: 'Saved story', createdAt: now)],
    );
    final restored = CloudSaveService.decode(CloudSaveService.encode(archive));
    expect(restored.toJson(), archive.toJson());
    final solo = MultiplayerArchiveService.toSolo(restored);
    expect(solo.id, isNot(archive.id));
    expect(solo.mode, TRPGMode.solo);
    expect(solo.players.first.playerId, 'b');
    expect(solo.players.first.isAiControlled, false);
    expect(solo.players.last.isAiControlled, true);
    expect(solo.playerCharacters.first.hp, 7);
    expect(solo.ruleState.round, 3);
    expect(solo.chatHistory.single.content, 'Saved story');
    expect(archive.players.first.isAiControlled, false);
  });
}
