import 'dart:math';

import 'package:ai_tavern/models/trpg_dice_models.dart';
import 'package:ai_tavern/models/trpg_game_models.dart';
import 'package:ai_tavern/models/trpg_gameplay_models.dart';
import 'package:ai_tavern/models/trpg_models.dart';
import 'package:ai_tavern/services/trpg/action_check_analyzer.dart';
import 'package:ai_tavern/services/trpg/growth_resolver.dart';
import 'package:ai_tavern/services/trpg/trpg_check_pipeline.dart';
import 'package:ai_tavern/services/trpg/trait_unlock_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TRPG dice-driven gameplay', () {
    test('ordinary actions bypass dice and risky actions create one check', () {
      final pipeline = TRPGCheckPipeline(random: Random(17));
      final ordinary = pipeline.resolveAction(
        session: _session(),
        action: '我坐下来喝一口水。',
        actionId: 'ordinary',
        playerId: 'player',
      );
      expect(ordinary.decision?.requiresCheck, isFalse);
      expect(ordinary.session.ruleState.checkHistory, isEmpty);

      final risky = pipeline.resolveAction(
        session: _session(),
        action: '我强行破门。',
        actionId: 'risky',
        playerId: 'player',
      );
      expect(risky.result, isNotNull);
      expect(risky.session.ruleState.checkHistory, hasLength(1));
      expect(risky.session.ruleState.diceHistory2, hasLength(1));
      expect(risky.result!.modifierSources, isNotEmpty);
      expect(risky.result!.displayExplanation, contains('最终'));
    });

    test('hidden information creates GM-only check without presentation', () {
      const analyzer = ActionCheckAnalyzer();
      final decision = analyzer.analyze(
        action: '我调查房间里有没有暗门。',
        session: _session(hiddenClue: true),
        character: _session().playerCharacters.single,
      );
      expect(decision.visibility, RollVisibility.gmHidden);
      expect(decision.presentationMode, DicePresentationMode.none);

      final casualWithoutSecret = analyzer.analyze(
        action: '我看看桌子。',
        session: _session(),
        character: _session().playerCharacters.single,
      );
      expect(casualWithoutSecret.requiresCheck, isFalse);
      final casualWithSecret = analyzer.analyze(
        action: '我看看桌子。',
        session: _session(hiddenClue: true),
        character: _session().playerCharacters.single,
      );
      expect(casualWithSecret.requiresCheck, isTrue);
      expect(casualWithSecret.visibility, RollVisibility.gmHidden);
    });

    test('repeat failure is blocked until approach changes', () {
      final base = _session().copyWith(
        ruleState: RuleState(
          repeatedChecks: [
            RepeatedCheckRecord(
              semanticKey: 'hotel:technology',
              characterId: 'character',
              sceneId: 'hotel',
              attempts: 1,
              lastSuccess: false,
              updatedAt: DateTime.utc(2026, 8, 23),
            ),
          ],
        ),
      );
      final pipeline = TRPGCheckPipeline(random: Random(3));
      final blocked = pipeline.resolveAction(
        session: base,
        action: '我再尝试破解门锁。',
        actionId: 'repeat',
        playerId: 'player',
      );
      expect(blocked.result?.successLevel, ActionOutcomeLevel.blocked);
      expect(blocked.session.ruleState.diceHistory2, isEmpty);

      final changed = pipeline.resolveAction(
        session: base,
        action: '我改用拾到的铁丝破解门锁。',
        actionId: 'new-approach',
        playerId: 'player',
      );
      expect(changed.result?.successLevel, isNot(ActionOutcomeLevel.blocked));
    });

    test('D100 uses a percentile roll and preserves structured state', () {
      final session = _session().copyWith(
        ruleState: const RuleState(
          diceSettings: DiceSettings(rulePackage: DiceRulePackageType.coc),
        ),
      );
      final outcome = TRPGCheckPipeline(random: Random(9)).resolveAction(
        session: session,
        action: '我尝试破解终端。',
        actionId: 'd100',
        playerId: 'player',
      );
      expect(outcome.result?.diceFormula, '1D100');
      expect(outcome.result!.difficulty, inInclusiveRange(5, 95));
      expect(outcome.result!.individualRolls.single, inInclusiveRange(1, 100));
      expect(outcome.session.playerCharacters.single.stats['INT'], 14);
    });

    test('dice-pool and custom rule packs keep their configured formulas', () {
      final pool = TRPGCheckPipeline(random: Random(2)).resolveAction(
        session: _session().copyWith(
          ruleState: const RuleState(
            diceSettings: DiceSettings(
              rulePackage: DiceRulePackageType.dicePool,
            ),
          ),
        ),
        action: '我尝试破解终端。',
        actionId: 'pool',
        playerId: 'player',
      );
      expect(pool.result?.diceFormula, '3D6');
      expect(pool.result?.individualRolls, hasLength(3));

      final custom = TRPGCheckPipeline(random: Random(2)).resolveAction(
        session: _session().copyWith(
          ruleState: const RuleState(
            diceSettings: DiceSettings(
              rulePackage: DiceRulePackageType.custom,
              customFormula: '2D10',
            ),
          ),
        ),
        action: '我尝试破解终端。',
        actionId: 'custom',
        playerId: 'player',
      );
      expect(custom.result?.diceFormula, '2D10');
      expect(custom.result?.individualRolls, hasLength(2));
    });

    test('explicit attribute checks do not invent a skill modifier', () {
      final outcome = TRPGCheckPipeline(random: Random(8)).resolveAction(
        session: _session(),
        action: '进行一次纯力量检定来撑住石门。',
        actionId: 'attribute',
        playerId: 'player',
      );
      expect(outcome.result?.checkType, ActionCheckType.attribute);
      expect(outcome.result?.attributeId, 'STR');
      expect(outcome.result?.skillId, isNull);
    });

    test('equipment status environment and relationship all modify checks', () {
      final base = _session();
      final character = base.playerCharacters.single.copyWith(
        skills: {...base.playerCharacters.single.skills, 'insight': 3},
        equipment: const ['truth-lens'],
        inventoryItems: const [
          InventoryItem(
            id: 'truth-lens',
            name: '测谎镜片',
            metadata: {
              'equipped': true,
              'checkModifiers': {'insight': 2},
            },
          ),
        ],
        structuredStatusEffects: const [
          StatusEffect(
            id: 'headache',
            name: '头痛',
            metadata: {
              'checkModifiers': {'insight': -1},
            },
          ),
        ],
      );
      final session = base.copyWith(
        playerCharacters: [character],
        worldState: base.worldState.copyWith(
          npcs: const [NPCState(npcId: 'guard', name: '守卫', relationship: 40)],
        ),
        ruleState: const RuleState(temporaryModifiers: {'insight': 1}),
      );
      final result = TRPGCheckPipeline(random: Random(10))
          .resolveAction(
            session: session,
            action: '我判断守卫有没有撒谎。',
            actionId: 'all-modifiers',
            playerId: 'player',
            targetId: 'guard',
          )
          .result!;
      final categories = result.modifierSources
          .map((value) => value.category)
          .toSet();
      expect(
        categories,
        containsAll(<String>[
          'attribute',
          'skill',
          'equipment',
          'status',
          'environment',
          'relationship',
        ]),
      );
    });

    test('opposed checks roll the target and keep the margin', () {
      final outcome = TRPGCheckPipeline(random: Random(12)).resolveAction(
        session: _session(),
        action: '我试着欺骗守卫，让他相信我有通行许可。',
        actionId: 'opposed',
        playerId: 'player',
        targetId: 'guard',
      );
      expect(outcome.result?.checkType, ActionCheckType.opposed);
      expect(outcome.result?.opposedResult, isNotNull);
      expect(outcome.result!.margin, isA<int>());
    });

    test(
      'group actions preserve actor ownership and apply successful help',
      () {
        final outcome = TRPGCheckPipeline(random: Random(6)).resolveGroup(
          session: _groupSession(),
          actionsByPlayer: const {
            'helper': '我协助队长一起推开石门。',
            'leader': '我强行推开石门。',
          },
          actionIdsByPlayer: const {
            'helper': 'group-help',
            'leader': 'group-lead',
          },
          turnId: 'group-turn',
        );
        expect(outcome.individual, hasLength(2));
        expect(
          outcome.individual.map((value) => value.result?.playerId),
          containsAll(['helper', 'leader']),
        );
        expect(outcome.partyResolution?.visibility, ResolutionVisibility.party);
        final leader = outcome.individual.singleWhere(
          (value) => value.result?.playerId == 'leader',
        );
        expect(
          leader.result!.modifierSources.any(
            (value) => value.category == 'environment' && value.value >= 2,
          ),
          isTrue,
        );
        expect(outcome.session.ruleState.temporaryModifiers, isEmpty);
      },
    );

    test('multiplayer secret actions keep their dice result private', () {
      final outcome = TRPGCheckPipeline(random: Random(13)).resolveGroup(
        session: _groupSession(),
        actionsByPlayer: const {
          'leader': '我偷偷搜索守卫的房间。',
          'helper': '我观察走廊替队长望风。',
        },
        actionIdsByPlayer: const {
          'leader': 'private-search',
          'helper': 'public-lookout',
        },
        visibilityByPlayer: const {
          'leader': RollVisibility.playerPrivate,
          'helper': RollVisibility.public,
        },
        turnId: 'private-group-turn',
      );
      final privateCheck = outcome.individual.singleWhere(
        (item) => item.result?.playerId == 'leader',
      );
      final publicCheck = outcome.individual.singleWhere(
        (item) => item.result?.playerId == 'helper',
      );
      expect(privateCheck.result?.visibility, RollVisibility.playerPrivate);
      expect(publicCheck.result?.visibility, RollVisibility.public);
      expect(outcome.partyResolution, isNull);
    });

    test('trait progress is rule-owned and unlocked traits modify checks', () {
      final moment = ActionCheckResult(
        checkId: 'moment',
        turnId: 'turn',
        actionId: 'action',
        playerId: 'player',
        characterId: 'character',
        checkType: ActionCheckType.skill,
        attributeId: 'PER',
        skillId: 'insight',
        diceFormula: '1D20',
        individualRolls: const [20],
        baseRoll: 20,
        modifierSources: const [],
        difficulty: 12,
        finalResult: 20,
        successLevel: ActionOutcomeLevel.criticalSuccess,
        margin: 8,
        visibility: RollVisibility.playerPrivate,
        presentationMode: DicePresentationMode.compact,
        reason: '危机中的洞察',
        createdAt: DateTime.utc(2026, 8, 23),
      );
      const resolver = TraitUnlockResolver();
      final first = resolver.applyCheck(_session(), moment);
      final second = resolver.applyCheck(
        _session().copyWith(ruleState: RuleState(traits: first)),
        moment,
      );
      expect(second.single.unlocked, isTrue);

      final checked = TRPGCheckPipeline(random: Random(7)).resolveAction(
        session: _session().copyWith(ruleState: RuleState(traits: second)),
        action: '我判断守卫有没有撒谎。',
        actionId: 'trait-check',
        playerId: 'player',
        targetId: 'guard',
      );
      expect(
        checked.result!.modifierSources.any(
          (value) => value.category == 'trait' && value.value == 1,
        ),
        isTrue,
      );
    });

    test('scene-end growth only applies validated pending candidates', () {
      final session = _session().copyWith(
        ruleState: RuleState(
          growthCandidates: [
            GrowthCandidate(
              candidateId: 'growth-1',
              characterId: 'character',
              sourceEventId: 'event-1',
              skillId: 'technology',
              reason: '成功破解危险终端',
              difficulty: 17,
              importance: 9,
              growthType: GrowthType.skill,
              sceneId: 'hotel',
              createdAt: DateTime.utc(2026, 8, 23),
            ),
          ],
        ),
      );
      final resolved = GrowthResolver(
        random: Random(1),
      ).resolvePending(session);
      expect(resolved.entries, hasLength(1));
      expect(resolved.session.playerCharacters.single.skills['technology'], 4);
      expect(
        resolved.session.ruleState.growthCandidates.single.status,
        GrowthCandidateStatus.resolved,
      );
      expect(resolved.session.ruleState.growthHistory, hasLength(1));
    });

    test(
      'new gameplay state survives JSON save and old saves default empty',
      () {
        final checked = TRPGCheckPipeline(random: Random(4)).resolveAction(
          session: _session(),
          action: '我攻击守卫。',
          actionId: 'save-check',
          playerId: 'player',
          targetId: 'guard',
        );
        final restored = TRPGSession.fromJson(checked.session.toJson());
        expect(restored.ruleState.checkHistory, hasLength(1));
        expect(restored.ruleState.repeatedChecks, hasLength(1));
        expect(restored.schemaVersion, trpgSchemaVersion);

        final oldJson = _session().toJson()
          ..['schemaVersion'] = 10
          ..['ruleState'] = <String, Object?>{};
        final old = TRPGSession.fromJson(oldJson);
        expect(old.ruleState.checkHistory, isEmpty);
        expect(old.ruleState.growthHistory, isEmpty);
      },
    );
  });
}

TRPGSession _groupSession() {
  final base = _session();
  return base.copyWith(
    players: [
      TRPGPlayer(
        playerId: 'leader',
        displayName: '队长',
        characterId: 'leader-character',
        joinedAt: base.createdAt,
      ),
      TRPGPlayer(
        playerId: 'helper',
        displayName: '协助者',
        characterId: 'helper-character',
        joinedAt: base.createdAt,
      ),
    ],
    playerCharacters: const [
      PlayerCharacter(
        id: 'leader-character',
        playerId: 'leader',
        name: '队长',
        stats: {'STR': 18, 'DEX': 10, 'INT': 10, 'PER': 10, 'CHA': 10},
        skills: {'athletics': 5},
      ),
      PlayerCharacter(
        id: 'helper-character',
        playerId: 'helper',
        name: '协助者',
        stats: {'STR': 30, 'DEX': 10, 'INT': 10, 'PER': 10, 'CHA': 10},
        skills: {'athletics': 10},
      ),
    ],
  );
}

TRPGSession _session({bool hiddenClue = false}) {
  final now = DateTime.utc(2026, 8, 23);
  return TRPGSession(
    id: 'dice-session',
    title: '骰子驱动测试',
    mode: TRPGMode.solo,
    createdAt: now,
    updatedAt: now,
    lastPlayedAt: now,
    campaignId: 'test-campaign',
    ruleSystemId: 'simple_trpg',
    players: [
      TRPGPlayer(
        playerId: 'player',
        displayName: '玩家',
        characterId: 'character',
        joinedAt: now,
      ),
    ],
    playerCharacters: const [
      PlayerCharacter(
        id: 'character',
        playerId: 'player',
        name: '测试角色',
        stats: {'STR': 12, 'DEX': 11, 'INT': 14, 'PER': 13, 'CHA': 10},
        skills: {'athletics': 2, 'technology': 2, 'combat': 2},
      ),
    ],
    worldState: const WorldState(
      location: 'hotel',
      currentScene: SceneState(
        sceneId: 'hotel',
        locationId: 'hotel',
        title: '陌生旅店',
      ),
      npcs: [NPCState(npcId: 'guard', name: '守卫')],
    ),
    gmState: GMState(
      undiscoveredClues: hiddenClue ? const ['secret-door'] : const [],
    ),
  );
}
