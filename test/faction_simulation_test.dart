import 'package:flutter_test/flutter_test.dart';

import 'package:ai_tavern/models/trpg_faction_models.dart';
import 'package:ai_tavern/models/trpg_models.dart';
import 'package:ai_tavern/models/trpg_world_generator_models.dart';
import 'package:ai_tavern/services/trpg/faction_simulation_service.dart';
import 'package:ai_tavern/services/trpg/living_npc_service.dart';
import 'package:ai_tavern/services/trpg/world_generator.dart';

void main() {
  late TRPGSession base;
  const factions = FactionManager();

  setUpAll(() async {
    final generated = await WorldGenerator().generate(
      seed: const WorldSeed(
        theme: '武侠江湖与三方势力战争',
        genre: '政治冒险',
        tone: '严肃',
        era: '架空时代',
        technologyLevel: '中等',
        magicLevel: '低魔法',
        difficulty: '普通',
        playerCount: 3,
        campaignLength: '长期',
        level: WorldGenerationLevel.normal,
        keywords: ['势力', '战争', '领地'],
      ),
    );
    var session = const WorldGenerationRuntime().initializeSession(
      _session(),
      generated.campaign,
    );
    session = const LivingNPCService().ensureInitialized(session);
    base = factions.ensureInitialized(session);
  });

  test('测试1：三个势力被初始化并拥有资源、目标和领地', () {
    expect(base.factionSimulationState.factions.length, 3);
    expect(
      base.factionSimulationState.factions.every(
        (item) =>
            item.resources.total > 0 &&
            item.brain.goals.isNotEmpty &&
            item.territories.isNotEmpty,
      ),
      isTrue,
    );
  });

  test('测试2：势力关系保持有向数值且可修改', () {
    final a = base.factionSimulationState.factions[0].id;
    final b = base.factionSimulationState.factions[1].id;
    final next = factions.modifyRelationship(
      base,
      fromFactionId: a,
      toFactionId: b,
      delta: -25,
      reason: '边境冲突',
    );
    expect(_relation(next, a, b).score, lessThan(_relation(base, a, b).score));
    expect(
      next.worldState.factionRelations['$a->$b'],
      _relation(next, a, b).score,
    );
  });

  test('测试3：玩家帮助势力 A 会留下历史并增加资源', () {
    final a = base.factionSimulationState.factions.first;
    final next = factions.applyPlayerSupport(
      base,
      factionId: a.id,
      playerId: 'player-a',
      reason: '送来补给',
      resourceBoost: 12,
    );
    final updated = _faction(next, a.id);
    expect(updated.resources.money, greaterThan(a.resources.money));
    expect(
      next.factionSimulationState.history.any(
        (item) => item.summary.contains('player-a'),
      ),
      isTrue,
    );
  });

  test('测试4：敌对势力会在玩家影响后自主响应', () {
    final a = base.factionSimulationState.factions[0];
    final b = base.factionSimulationState.factions[1];
    var session = factions.modifyRelationship(
      base,
      fromFactionId: b.id,
      toFactionId: a.id,
      delta: -100,
      reason: '长期敌对',
    );
    session = factions.applyPlayerSupport(
      session,
      factionId: a.id,
      playerId: 'player-a',
      reason: '公开结盟',
    );
    expect(
      session.factionSimulationState.actions.any(
        (item) => item.factionId == b.id,
      ),
      isTrue,
    );
  });

  test('测试5：战争由规则结算并生成 BattleEvent 和任务', () {
    final prepared = _strongAttacker(base);
    final attacker = prepared.factionSimulationState.factions[0];
    final defender = prepared.factionSimulationState.factions[1];
    final location = defender.territories.first.locationId;
    final next = factions.executeAction(
      prepared,
      FactionActionState(
        id: 'attack-test',
        factionId: attacker.id,
        targetFactionId: defender.id,
        targetLocationId: location,
        type: FactionActionType.attack,
        reason: '测试战争',
      ),
    );
    expect(next.factionSimulationState.battles, isNotEmpty);
    expect(
      next.campaignState.quests.any(
        (item) => item.questId.startsWith('faction-conflict-'),
      ),
      isTrue,
    );
    expect(
      _relation(next, attacker.id, defender.id).state,
      DiplomaticState.war,
    );
  });

  test('测试6：攻击方胜利后领地转移且生成领地事件', () {
    final prepared = _strongAttacker(base);
    final attacker = prepared.factionSimulationState.factions[0];
    final defender = prepared.factionSimulationState.factions[1];
    final location = defender.territories.first.locationId;
    final next = factions.executeAction(
      prepared,
      FactionActionState(
        id: 'territory-test',
        factionId: attacker.id,
        targetFactionId: defender.id,
        targetLocationId: location,
        type: FactionActionType.attack,
        reason: '争夺领地',
      ),
    );
    expect(
      _faction(
        next,
        attacker.id,
      ).territories.any((item) => item.locationId == location),
      isTrue,
    );
    expect(
      _faction(
        next,
        defender.id,
      ).territories.any((item) => item.locationId == location),
      isFalse,
    );
    expect(
      next.eventLog.any(
        (event) => event.type == TRPGEventType.factionTerritory,
      ),
      isTrue,
    );
  });

  test('测试7：世界 NPC 正确绑定势力成员与职位', () {
    for (final faction in base.factionSimulationState.factions) {
      expect(faction.memberNpcIds, isNotEmpty);
      expect(faction.memberRoles.keys, containsAll(faction.memberNpcIds));
      expect(
        base.livingNpcState.brains.keys,
        containsAll(faction.memberNpcIds),
      );
    }
  });

  test('测试8：领袖死亡后由存活成员继承且原势力卡不丢失', () {
    var session = base;
    final original = session.factionSimulationState.factions.first;
    final members = original.memberNpcIds;
    expect(members.length, greaterThan(1));
    session = const LivingNPCService().killNpc(
      session,
      npcId: original.leaderNpcId,
      reason: '继承测试',
    );
    session = factions.tick(session, trigger: FactionTickTrigger.majorEvent);
    final updated = _faction(session, original.id);
    expect(updated.leaderNpcId, isNot(original.leaderNpcId));
    expect(updated.memberNpcIds, containsAll(members));
    expect(
      session.eventLog.any(
        (event) => event.type == TRPGEventType.factionSuccession,
      ),
      isTrue,
    );
  });

  test('测试9：完整势力状态可以保存和恢复', () {
    final restored = TRPGSession.fromJson(base.toJson());
    expect(restored.schemaVersion, trpgSchemaVersion);
    expect(restored.factionSimulationState.factions.length, 3);
    expect(
      restored.factionSimulationState.relationships.length,
      base.factionSimulationState.relationships.length,
    );
    expect(
      restored.factionSimulationState.secrets.length,
      base.factionSimulationState.secrets.length,
    );
  });

  test('测试10：多人公开视图和玩家视图不会泄露势力秘密', () {
    final secret = base.factionSimulationState.secrets.first;
    var session = factions.revealKnowledge(
      base,
      playerId: 'player-a',
      secretId: secret.id,
    );
    expect(session.factionSimulationState.publicView().secrets, isEmpty);
    expect(
      session.factionSimulationState.forPlayer('player-b').secrets,
      isEmpty,
    );
    expect(
      session.factionSimulationState
          .forPlayer('player-a')
          .secrets
          .map((item) => item.id),
      contains(secret.id),
    );
  });

  test('测试11：统一世界时间同时推进 NPC 与势力 Tick', () {
    final next = const WorldSimulationService().advanceTime(
      base,
      minutes: 1440,
      reason: '推进一天',
    );
    expect(next.livingNpcState.worldMinute, 1440);
    expect(next.factionSimulationState.worldMinute, 1440);
    expect(next.factionSimulationState.actions, isNotEmpty);
    expect(
      next.eventLog.any((event) => event.type == TRPGEventType.worldSimulation),
      isTrue,
    );
  });

  test('测试12：玩家不介入时势力仍会在一天后自主行动', () {
    final next = const WorldSimulationService().advanceTime(
      base,
      minutes: 1440,
      reason: '无人干预的世界日',
    );
    expect(
      next.factionSimulationState.actions.where(
        (item) => item.status == FactionActionStatus.resolved,
      ),
      isNotEmpty,
    );
    expect(next.factionSimulationState.history, isNotEmpty);
  });

  test('额外验证：资源不足的非法行动被拒绝且不会修改世界', () {
    final faction = base.factionSimulationState.factions.first;
    final before = faction.resources.toJson();
    final next = factions.executeAction(
      base,
      FactionActionState(
        id: 'invalid-cost',
        factionId: faction.id,
        type: FactionActionType.build,
        targetLocationId: faction.territories.first.locationId,
        reason: '非法超额建造',
        cost: const FactionResource(
          money: 99999,
          food: 0,
          technology: 0,
          military: 0,
          influence: 0,
          knowledge: 0,
        ),
      ),
    );
    expect(_faction(next, faction.id).resources.toJson(), before);
    expect(
      next.factionSimulationState.actions.last.status,
      FactionActionStatus.rejected,
    );
  });
}

TRPGSession _strongAttacker(TRPGSession session) {
  final state = session.factionSimulationState;
  final factions = [...state.factions];
  factions[0] = factions[0].copyWith(
    resources: factions[0].resources.copyWith(military: 500, technology: 200),
    stability: 100,
  );
  factions[1] = factions[1].copyWith(
    resources: factions[1].resources.copyWith(military: 1, technology: 1),
    stability: 10,
  );
  return session.copyWith(
    factionSimulationState: state.copyWith(factions: factions),
  );
}

FactionState _faction(TRPGSession session, String id) =>
    session.factionSimulationState.factions.firstWhere((item) => item.id == id);

FactionRelationshipState _relation(
  TRPGSession session,
  String from,
  String to,
) => session.factionSimulationState.relationships.firstWhere(
  (item) => item.fromFactionId == from && item.toFactionId == to,
);

TRPGSession _session() {
  final now = DateTime(2026, 8, 21);
  return TRPGSession(
    id: 'faction-test-session',
    title: '势力模拟测试',
    mode: TRPGMode.multiplayer,
    createdAt: now,
    updatedAt: now,
    lastPlayedAt: now,
    campaignId: 'generated-faction-world',
  );
}
