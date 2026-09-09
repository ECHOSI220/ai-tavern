import 'package:ai_tavern/models/trpg_models.dart';
import 'package:ai_tavern/models/trpg_party_models.dart';
import 'package:ai_tavern/services/trpg/gm_director.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('director creates multi-group cross-cut plan for combat', () {
    final now = DateTime.now();
    final session = TRPGSession(
      id: 's',
      title: 'test',
      mode: TRPGMode.multiplayer,
      createdAt: now,
      updatedAt: now,
      lastPlayedAt: now,
      campaignId: 'c',
      playerCharacters: const [],
      partyGroups: const [
        PartyGroup(
          groupId: 'basement',
          locationId: 'basement',
          characterIds: ['a'],
        ),
        PartyGroup(groupId: 'hall', locationId: 'hall', characterIds: ['b']),
      ],
      eventLog: [
        TRPGEvent(
          id: 'combat',
          type: TRPGEventType.combatStarted,
          timestamp: now,
          payload: const {'groupId': 'basement'},
        ),
      ],
    );
    final plan = const GMDirector().plan(session, turnId: 't1');
    expect(plan.mode, NarrativeMode.crossCut);
    expect(plan.pacing, NarrativePacing.climax);
    expect(plan.focusGroup, 'basement');
    expect(plan.toPrompt(), contains('不同小组'));
  });
}
