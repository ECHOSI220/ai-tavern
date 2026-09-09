import 'dart:math';

import 'package:ai_tavern/models/trpg_game_models.dart';
import 'package:ai_tavern/models/trpg_gameplay_models.dart';
import 'package:ai_tavern/models/trpg_models.dart';
import 'package:ai_tavern/services/trpg/ai_gm_tool_registry.dart';
import 'package:ai_tavern/services/ai/openai_compatible_provider.dart';
import 'package:ai_tavern/services/trpg/dice_service.dart';
import 'package:ai_tavern/services/trpg/trpg_rule_engine.dart';
import 'package:ai_tavern/services/trpg/trpg_state_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TRPG phase 2 rule engine', () {
    test('stat modifier and advantage skill check are program generated', () {
      final engine = TRPGRuleEngine(
        diceService: DiceService(random: Random(42)),
      );
      expect(engine.statModifier(10), 0);
      expect(engine.statModifier(14), 2);
      expect(engine.statModifier(8), -1);
      final result = engine.skillCheck(
        character: _session().playerCharacters.single,
        skillId: 'perception',
        difficulty: 12,
        reason: '寻找脚印',
        advantageMode: AdvantageMode.advantage,
      );
      expect(result.rawRolls, hasLength(2));
      expect(result.chosenRoll, result.rawRolls.reduce(max));
      expect(result.modifier, 4); // PER 14 (+2) + proficiency (+2)
      expect(result.difficulty, 12);
    });

    test('invalid difficulty and stat are rejected', () {
      final engine = TRPGRuleEngine();
      expect(
        () => engine.skillCheck(
          character: _session().playerCharacters.single,
          stat: 'LUCK',
          difficulty: 999,
          reason: '无效检定',
        ),
        throwsA(isA<TRPGRuleException>()),
      );
    });

    test('HP clamps and downed is added and removed', () {
      final engine = TRPGRuleEngine();
      var session = engine.modifyHp(
        _session(),
        characterId: 'character',
        amount: -999,
        reason: '测试伤害',
      );
      expect(session.playerCharacters.single.hp, 0);
      expect(session.playerCharacters.single.statusEffects, contains('downed'));
      session = engine.modifyHp(
        session,
        characterId: 'character',
        amount: 999,
        reason: '完全治疗',
      );
      expect(session.playerCharacters.single.hp, 20);
      expect(
        session.playerCharacters.single.statusEffects,
        isNot(contains('downed')),
      );
    });

    test('inventory uses unique id and validates quantity', () {
      final engine = TRPGRuleEngine();
      var session = engine.giveItem(
        _session(),
        characterId: 'character',
        item: const InventoryItem(
          id: 'warehouse_key',
          name: '钥匙',
          category: InventoryCategory.keyItem,
          quantity: 2,
        ),
        reason: '守卫交付',
      );
      session = engine.removeItem(
        session,
        characterId: 'character',
        itemId: 'warehouse_key',
        amount: 1,
        reason: '打开仓库',
      );
      expect(session.playerCharacters.single.inventoryItems.single.quantity, 1);
      expect(
        () => engine.removeItem(
          session,
          characterId: 'character',
          itemId: 'other_key',
          amount: 1,
          reason: '错误钥匙',
        ),
        throwsA(isA<TRPGRuleException>()),
      );
    });

    test('quest scene world flag clue and NPC state are structured', () {
      final state = TRPGStateService();
      var session = state.updateQuest(
        _session(),
        questId: 'missing_investigator',
        operation: 'activate',
        title: '寻找失踪调查员',
      );
      session = state.discoverClue(
        session,
        clueId: 'bootprints',
        name: '泥泞脚印',
        description: '脚印指向仓库',
        characterId: 'character',
      );
      session = state.changeScene(
        session,
        scene: const SceneState(
          sceneId: 'warehouse',
          locationId: 'old_harbor',
          title: '旧港仓库',
          description: '铁门已经打开。',
        ),
        reason: '使用钥匙',
      );
      session = state.updateWorldFlag(
        session,
        flag: 'warehouse_door_open',
        value: true,
        reason: '使用钥匙',
      );
      expect(session.campaignState.quests.single.status, QuestStatus.active);
      expect(session.campaignState.clues.single.discovered, isTrue);
      expect(session.worldState.currentScene.sceneId, 'warehouse');
      expect(session.worldState.worldFlags['warehouse_door_open'], isTrue);
    });

    test('tool call id is idempotent and does not duplicate reward', () async {
      final registry = AIGMToolRegistry();
      const call = OpenAIToolCall(
        id: 'call-reward-1',
        name: 'give_item',
        arguments: {
          'characterId': 'character',
          'itemId': 'warehouse_key',
          'name': '旧仓库钥匙',
          'quantity': 1,
          'category': 'keyItem',
          'reason': '通过检定',
        },
      );
      final first = await registry.execute(
        session: _session(),
        actionId: 'action-1',
        call: call,
      );
      final retry = await registry.execute(
        session: first.session,
        actionId: 'action-1',
        call: call,
      );
      expect(retry.wasCached, isTrue);
      expect(
        retry.session.playerCharacters.single.inventoryItems.single.quantity,
        1,
      );
      expect(retry.session.toolExecutions, hasLength(1));
    });

    test('lightweight combat can damage an NPC and mark defeat', () async {
      final registry = AIGMToolRegistry();
      const call = OpenAIToolCall(
        id: 'damage-guard',
        name: 'apply_damage',
        arguments: {
          'sourceId': 'character',
          'targetId': 'guard',
          'diceSides': 4,
          'diceCount': 1,
          'modifier': 20,
          'damageType': 'physical',
          'reason': 'combat test',
        },
      );
      final outcome = await registry.execute(
        session: _session(),
        actionId: 'combat-action',
        call: call,
      );
      final guard = outcome.session.worldState.npcs.single;
      expect(guard.hp, 0);
      expect(guard.alive, isFalse);
      expect(
        outcome.session.eventLog.any(
          (event) => event.type == TRPGEventType.damageApplied,
        ),
        isTrue,
      );
    });

    test(
      'AI can request a system check but cannot directly edit growth',
      () async {
        final registry = AIGMToolRegistry();
        final toolNames = registry.schemas
            .map((schema) => (schema['function'] as Map)['name'])
            .toSet();
        expect(toolNames, contains('trigger_rule_check'));
        expect(toolNames, isNot(contains('modify_attribute')));
        expect(toolNames, isNot(contains('modify_skill')));

        const call = OpenAIToolCall(
          id: 'ambush-check',
          name: 'trigger_rule_check',
          arguments: {
            'characterId': 'character',
            'situation': 'Assassin突然偷袭，角色能否及时察觉伏击',
            'turnId': 'turn-ambush',
          },
        );
        final outcome = await registry.execute(
          session: _session(),
          actionId: 'system-ambush',
          call: call,
        );
        expect(outcome.record.succeeded, isTrue);
        expect(outcome.result['visibility'], RollVisibility.gmHidden.name);
        expect(
          outcome.result['presentationMode'],
          DicePresentationMode.none.name,
        );
        expect(outcome.session.ruleState.checkHistory, hasLength(1));
      },
    );
  });
}

TRPGSession _session() {
  final now = DateTime.utc(2026, 8, 13);
  return TRPGSession(
    id: 'session',
    title: '测试跑团',
    mode: TRPGMode.solo,
    createdAt: now,
    updatedAt: now,
    lastPlayedAt: now,
    campaignId: 'mist_harbor_test',
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
        name: '晨歌',
        stats: {'STR': 10, 'DEX': 12, 'INT': 15, 'PER': 14, 'CHA': 10},
        skills: {'perception': 2},
      ),
    ],
    worldState: const WorldState(
      npcs: [NPCState(npcId: 'guard', name: '守卫')],
    ),
  );
}
