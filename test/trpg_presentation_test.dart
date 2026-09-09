import 'package:ai_tavern/models/campaign_models.dart';
import 'package:ai_tavern/models/trpg_models.dart';
import 'package:ai_tavern/models/trpg_presentation_models.dart';
import 'package:ai_tavern/services/trpg/ai_gm_tool_registry.dart';
import 'package:ai_tavern/services/trpg/campaign_codec_service.dart';
import 'package:ai_tavern/services/trpg/campaign_template_service.dart';
import 'package:ai_tavern/services/trpg/trpg_presentation_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TRPG Phase 5 presentation', () {
    test('presentation state migrates from old saves', () {
      final now = DateTime.now().toIso8601String();
      final session = TRPGSession.fromJson({
        'schemaVersion': 2,
        'id': 'old',
        'title': '旧存档',
        'mode': 'solo',
        'createdAt': now,
        'updatedAt': now,
        'campaignId': 'old_campaign',
      });
      expect(session.presentationState, isA<CurrentPresentationState>());
      expect(session.presentationState.visibleCharacters, isEmpty);
    });

    test('presentation reducer never mutates rule state', () {
      final before = _session();
      final event = PresentationEvent(
        eventId: 'show',
        type: PresentationEventType.characterShow,
        sequenceNumber: 1,
        createdAt: DateTime.now(),
        payload: const {
          'npcId': 'npc_1',
          'position': 'right',
          'expression': 'angry',
        },
      );
      final state = TRPGPresentationService.reduce(
        before.presentationState,
        event,
      );
      expect(state.visibleCharacters.single.npcId, 'npc_1');
      expect(before.playerCharacters.single.hp, 20);
      expect(before.ruleState.diceHistory, isEmpty);
    });

    test('queue honors server sequence and ignores replay', () async {
      final service = TRPGPresentationService();
      addTearDown(service.dispose);
      final first = service.create(
        PresentationEventType.bgmPlay,
        payload: const {'assetId': 'mystery'},
        durationMs: 0,
      );
      await service.enqueue(first);
      await service.enqueue(first);
      expect(service.state.sequenceNumber, first.sequenceNumber);
      expect(service.state.bgmId, 'mystery');
    });

    test('combat end restores scene bgm', () {
      const state = CurrentPresentationState(sceneBgmId: 'mystery');
      final started = TRPGPresentationService.reduce(
        state,
        PresentationEvent(
          eventId: 'start',
          type: PresentationEventType.combatStart,
          sequenceNumber: 1,
          createdAt: DateTime.now(),
        ),
      );
      final ended = TRPGPresentationService.reduce(
        started,
        PresentationEvent(
          eventId: 'end',
          type: PresentationEventType.combatEnd,
          sequenceNumber: 2,
          createdAt: DateTime.now(),
        ),
      );
      expect(started.bgmId, 'battle');
      expect(ended.bgmId, 'mystery');
      expect(ended.combatActive, isFalse);
    });

    test('presentation tools are enum and whitelist constrained', () {
      final registry = AIGMToolRegistry();
      final names = registry.schemas
          .map((value) => (value['function'] as Map)['name'])
          .toSet();
      expect(
        names,
        containsAll([
          'set_expression',
          'show_character',
          'hide_character',
          'set_bgm',
          'set_ambient',
          'play_sfx',
          'set_scene_visual',
        ]),
      );
    });

    test('Mist Harbor contains Phase 5 presentation resources', () {
      final campaign = const CampaignTemplateService().mistHarbor();
      expect(
        campaign.locations.every((value) => value.backgroundId != null),
        isTrue,
      );
      expect(campaign.npcs.length, 4);
      expect(
        campaign.audioAssets.where((value) => value.type == AudioAssetType.bgm),
        hasLength(3),
      );
      expect(
        campaign.audioAssets.where(
          (value) => value.type == AudioAssetType.ambient,
        ),
        hasLength(3),
      );
    });

    test('campaign validation rejects absolute asset paths', () {
      final campaign = CampaignDocument.blank().copyWith(
        audioAssets: const [
          AudioAsset(
            id: 'bad',
            type: AudioAssetType.bgm,
            path: r'C:\music\bad.mp3',
          ),
        ],
      );
      final result = const CampaignCodecService().validateCampaign(campaign);
      expect(
        result.errors.any((value) => value.code == 'absolute_asset_path'),
        isTrue,
      );
    });
  });
}

TRPGSession _session() {
  final now = DateTime.now();
  return TRPGSession(
    id: 'session',
    title: 'test',
    mode: TRPGMode.solo,
    createdAt: now,
    updatedAt: now,
    lastPlayedAt: now,
    campaignId: 'campaign',
    players: [TRPGPlayer(playerId: 'player', displayName: 'P', joinedAt: now)],
    playerCharacters: const [
      PlayerCharacter(id: 'pc', playerId: 'player', name: 'Hero'),
    ],
  );
}
