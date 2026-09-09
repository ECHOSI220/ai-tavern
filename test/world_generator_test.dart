import 'package:flutter_test/flutter_test.dart';

import 'package:ai_tavern/models/trpg_models.dart';
import 'package:ai_tavern/models/trpg_world_generator_models.dart';
import 'package:ai_tavern/services/trpg/living_npc_service.dart';
import 'package:ai_tavern/services/trpg/world_generator.dart';

void main() {
  const generator = _GeneratorHarness();

  test('测试1：生成西幻世界并包含地点、NPC、任务和连通图', () async {
    final result = await generator.generate('西幻魔法王国', '奇幻');
    expect(result.validation.isValid, isTrue);
    expect(result.blueprint.locations.length, greaterThanOrEqualTo(4));
    expect(result.blueprint.npcs.length, greaterThanOrEqualTo(5));
    expect(result.blueprint.quests.length, greaterThanOrEqualTo(3));
    expect(
      result.blueprint.locations.every(
        (item) =>
            result.blueprint.locations.length == 1 ||
            item.connectedLocations.isNotEmpty,
      ),
      isTrue,
    );
  });

  test('测试2：生成末世世界并包含敌人生态与隐藏真相', () async {
    final result = await generator.generate('末世废土地下城市', '生存');
    expect(result.blueprint.worldName, contains('余烬'));
    expect(result.blueprint.enemies, isNotEmpty);
    expect(result.blueprint.enemies.first.behavior, isNotEmpty);
    expect(result.blueprint.enemies.first.weaknesses, isNotEmpty);
    expect(result.blueprint.secrets, isNotEmpty);
  });

  test('测试3：生成武侠世界并建立三方势力关系', () async {
    final result = await generator.generate('武侠江湖', '悬疑冒险');
    expect(result.blueprint.worldName, contains('山河'));
    expect(result.blueprint.factions.length, 3);
    expect(
      result.blueprint.factionRelationships.length,
      greaterThanOrEqualTo(3),
    );
    expect(
      result.blueprint.factions.every(
        (item) => item.territoryLocationIds.isNotEmpty,
      ),
      isTrue,
    );
  });

  test('测试4：生成后 WorldSeed、Blueprint 和版本数据进入存档', () async {
    final result = await generator.generate('末世废土', '调查');
    final session = const WorldGenerationRuntime().initializeSession(
      _session(TRPGMode.solo),
      result.campaign,
    );
    final json = session.toJson();
    expect(json['schemaVersion'], trpgSchemaVersion);
    expect(session.worldGenerationState.seed?.theme, '末世废土');
    expect(session.worldGenerationState.blueprint?.worldName, isNotEmpty);
    expect(session.worldGenerationState.generationVersion, 1);
    expect(session.worldGenerationState.lockedAfterPlay, isTrue);
  });

  test('测试5：重新加载后完整恢复世界蓝图、位置和关系', () async {
    final result = await generator.generate('西幻世界', '冒险');
    final original = const WorldGenerationRuntime().initializeSession(
      _session(TRPGMode.solo),
      result.campaign,
    );
    final loaded = TRPGSession.fromJson(original.toJson());
    expect(
      loaded.worldGenerationState.blueprint?.locations.length,
      original.worldGenerationState.blueprint?.locations.length,
    );
    expect(loaded.campaignState.currentLocationId, isNotEmpty);
    expect(loaded.worldState.factionRelations, isNotEmpty);
  });

  test('测试6：玩家进入随机地点时只进行一次 Lazy NPC 生成', () async {
    final result = await generator.generate('末世废土', '沙盒');
    final runtime = const WorldGenerationRuntime();
    final session = runtime.initializeSession(
      _session(TRPGMode.solo),
      result.campaign,
    );
    final target = result.blueprint.locations.last.id;
    final before = session.worldState.npcs.length;
    final expanded = runtime.enterLocation(session, target);
    expect(expanded.worldState.npcs.length, before + 2);
    expect(expanded.livingNpcState.brains.keys, contains('lazy_${target}_2_0'));
    final repeated = runtime.enterLocation(expanded, target);
    expect(repeated.worldState.npcs.length, expanded.worldState.npcs.length);
  });

  test('测试7：生成 NPC 会进入 Living NPC 并能在时间推进后行动', () async {
    final result = await generator.generate('西幻世界', '冒险');
    var session = const WorldGenerationRuntime().initializeSession(
      _session(TRPGMode.solo),
      result.campaign,
    );
    expect(session.livingNpcState.brains, isNotEmpty);
    session = const LivingNPCService().advanceTime(
      session,
      minutes: 1440,
      reason: '世界生成器长期运行测试',
    );
    expect(session.livingNpcState.recentActions, isNotEmpty);
  });

  test('测试8：开局任务被写入 QuestSystem 并可立即触发', () async {
    final result = await generator.generate('武侠江湖', '悬疑');
    final session = const WorldGenerationRuntime().initializeSession(
      _session(TRPGMode.solo),
      result.campaign,
    );
    final firstQuest = result.blueprint.quests.first;
    expect(session.campaignState.activeQuests, contains(firstQuest.id));
    expect(
      session.campaignState.quests
          .firstWhere((item) => item.questId == firstQuest.id)
          .objectives,
      isNotEmpty,
    );
    expect(firstQuest.branches.length, greaterThanOrEqualTo(3));
  });

  test('测试9：FactionGraph 分数进入 WorldState 并保持方向', () async {
    final result = await generator.generate('末世废土', '政治生存');
    final session = const WorldGenerationRuntime().initializeSession(
      _session(TRPGMode.solo),
      result.campaign,
    );
    final relation = result.blueprint.factionRelationships.first;
    expect(
      session
          .worldState
          .factionRelations['${relation.fromFactionId}:${relation.toFactionId}'],
      relation.score,
    );
  });

  test('测试10：多人模式进入生成世界且公开视图不泄露秘密', () async {
    final result = await generator.generate('武侠江湖', '多人冒险');
    final session = const WorldGenerationRuntime().initializeSession(
      _session(TRPGMode.multiplayer),
      result.campaign,
    );
    expect(session.mode, TRPGMode.multiplayer);
    expect(session.worldState.currentScene.locationId, isNotEmpty);
    expect(session.npcLocations, isNotEmpty);
    final publicState = session.worldGenerationState.publicView();
    expect(publicState.blueprint?.secrets, isEmpty);
    expect(
      publicState.blueprint?.npcs.every((item) => item.secret.isEmpty),
      isTrue,
    );
  });

  test('已开始游玩的世界重新生成时必须 Fork 而不是覆盖', () async {
    final result = await generator.generate('西幻世界', '冒险');
    final forked = const WorldGenerationRuntime().fork(
      result.state.copyWith(lockedAfterPlay: true),
      result.blueprint,
    );
    expect(forked.parentGenerationId, result.state.generationId);
    expect(forked.generationId, isNot(result.state.generationId));
    expect(forked.generationVersion, result.state.generationVersion + 1);
  });
}

class _GeneratorHarness {
  const _GeneratorHarness();

  Future<WorldGenerationResult> generate(String theme, String genre) =>
      WorldGenerator().generate(
        seed: WorldSeed(
          theme: theme,
          genre: genre,
          tone: '严肃 + 少量幽默',
          era: '自定义时代',
          technologyLevel: theme.contains('末世') ? '高科技遗迹' : '中等',
          magicLevel: theme.contains('西幻') ? '高魔法' : '低魔法',
          difficulty: '普通',
          playerCount: 4,
          campaignLength: '3小时',
          level: WorldGenerationLevel.normal,
          keywords: const ['自由探索', '多结局'],
        ),
      );
}

TRPGSession _session(TRPGMode mode) {
  final now = DateTime(2026, 8, 21);
  return TRPGSession(
    id: 'world-test-session',
    title: '世界生成测试',
    mode: mode,
    createdAt: now,
    updatedAt: now,
    lastPlayedAt: now,
    campaignId: 'generated-world',
  );
}
