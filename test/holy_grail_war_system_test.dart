import 'dart:math';

import 'package:ai_tavern/models/campaign_models.dart';
import 'package:ai_tavern/models/holy_grail_war_models.dart';
import 'package:ai_tavern/models/trpg_gameplay_models.dart';
import 'package:ai_tavern/models/trpg_models.dart';
import 'package:ai_tavern/services/trpg/campaign_template_service.dart';
import 'package:ai_tavern/services/trpg/holy_grail_war_manager.dart';
import 'package:ai_tavern/services/trpg/trpg_check_pipeline.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const manager = HolyGrailWarManager();
  const templates = CampaignTemplateService();
  late TRPGSession initialized;

  setUp(() {
    initialized = manager.initialize(
      _session(),
      campaign: templates.holyGrailWar(),
    );
  });

  test('1 创建圣杯战争并生成七个御主席位', () {
    expect(initialized.holyGrailState.initialized, isTrue);
    expect(initialized.holyGrailState.masters, hasLength(7));
    expect(initialized.metadata['campaignType'], 'HOLY_GRAIL_WAR');
  });

  test('2 玩家可以选择御主预设并保留愿望', () {
    final result = manager.selectMaster(
      initialized,
      playerId: 'player-a',
      archetype: MasterArchetype.homunculus,
      wish: '获得真正自由',
    );
    final master = result.session.holyGrailState.masters
        .where((value) => value.ownerPlayerId == 'player-a')
        .single;
    expect(master.archetype, MasterArchetype.homunculus);
    expect(master.magicAbility, 95);
    expect(master.wish, '获得真正自由');
  });

  test('3 召唤根据上下文匹配且职阶不重复', () {
    var session = initialized;
    for (final master in session.holyGrailState.masters) {
      session = manager
          .summonServant(
            session,
            masterId: master.masterId,
            catalyst: '媒介-${master.masterId}',
          )
          .session;
    }
    expect(session.holyGrailState.servants, hasLength(7));
    expect(
      session.holyGrailState.servants.map((value) => value.classType).toSet(),
      hasLength(7),
    );
  });

  test('4 敌方从者真名在玩家视角中隐藏', () {
    var session = initialized;
    session = manager
        .summonServant(session, masterId: 'master_1', catalyst: '王冠残片')
        .session;
    session = manager
        .summonServant(session, masterId: 'master_2', catalyst: '古老箭头')
        .session;
    final enemy = session.holyGrailState.servants
        .where((value) => value.masterId == 'master_2')
        .single;
    final visible = session.holyGrailState
        .forPlayer('player-a')
        .servants
        .where((value) => value.servantId == enemy.servantId)
        .single;
    expect(visible.trueName, 'UNKNOWN');
    expect(visible.classType, enemy.classType);
  });

  test('5 多人御主拥有隔离的信息仓库', () {
    final selected = manager.selectMaster(
      initialized,
      playerId: 'player-b',
      archetype: MasterArchetype.familyHeir,
    );
    expect(
      selected.session.holyGrailState.informationByPlayer.keys,
      containsAll(['player-a', 'player-b']),
    );
    expect(
      selected.session.holyGrailState.masters.where(
        (value) => value.ownerPlayerId != null,
      ),
      hasLength(2),
    );
  });

  test('6 情报调查逐步记录能力并最终确认真名', () {
    var session = manager
        .summonServant(initialized, masterId: 'master_2', catalyst: '长枪碎片')
        .session;
    final target = session.holyGrailState.servants.single;
    session = manager
        .investigate(
          session,
          playerId: 'player-a',
          targetServantId: target.servantId,
          action: InvestigationAction.investigate,
        )
        .session;
    final info = session.holyGrailState.informationByPlayer['player-a']!;
    expect(
      info.observedAbilities[target.servantId]!.length,
      greaterThanOrEqualTo(3),
    );
    expect(info.suspectedIdentity[target.servantId], target.trueName);
  });

  test('7 宝具真名解放增强威力并向目击者暴露', () {
    var session = manager
        .summonServant(initialized, masterId: 'master_1', catalyst: '古剑')
        .session;
    final servant = session.holyGrailState.servants.single;
    final result = manager.releaseNoblePhantasm(
      session,
      servantId: servant.servantId,
      trueNameRelease: true,
      witnessPlayerIds: const ['player-b'],
    );
    final event = result.session.eventLog.last;
    expect(event.payload['powerMultiplier'], 1.75);
    expect(
      result.session.holyGrailState.servants.single.trueNameRevealedTo,
      contains('player-b'),
    );
  });

  test('8 两个存活御主可以建立联盟', () {
    final result = manager.formAlliance(
      initialized,
      masterIds: const ['master_1', 'master_2'],
      purpose: '共同对付强敌',
    );
    expect(result.succeeded, isTrue);
    expect(
      result.session.holyGrailState.alliances.single.status,
      HolyAllianceStatus.active,
    );
  });

  test('9 联盟可以被主动背叛且产生独立事件', () {
    var session = manager
        .formAlliance(
          initialized,
          masterIds: const ['master_1', 'master_2'],
          purpose: '停战一夜',
        )
        .session;
    final alliance = session.holyGrailState.alliances.single;
    session = manager
        .breakAlliance(
          session,
          allianceId: alliance.allianceId,
          actorMasterId: 'master_2',
          betrayal: true,
        )
        .session;
    expect(
      session.holyGrailState.alliances.single.status,
      HolyAllianceStatus.betrayed,
    );
    expect(session.eventLog.last.type, TRPGEventType.holyGrailBetrayal);
  });

  test('10 令咒消耗次数并改变主从关系', () {
    var session = manager
        .summonServant(initialized, masterId: 'master_1', catalyst: '剑鞘')
        .session;
    session = manager
        .useCommandSpell(
          session,
          masterId: 'master_1',
          effect: CommandSpellEffect.forceOrder,
          order: '立刻撤退',
        )
        .session;
    expect(session.holyGrailState.masters.first.commandSpells, 2);
    expect(session.holyGrailState.relationships.first.obedience, 100);
    expect(session.holyGrailState.relationships.first.trust, lessThan(10));
  });

  test('11 最后存活阵营触发最终结局', () {
    var session = initialized;
    for (final master in session.holyGrailState.masters.take(2)) {
      session = manager
          .summonServant(session, masterId: master.masterId)
          .session;
    }
    for (final id in [
      'master_2',
      'master_3',
      'master_4',
      'master_5',
      'master_6',
      'master_7',
    ]) {
      session = manager
          .eliminateTeam(session, masterId: id, masterKilled: true)
          .session;
    }
    expect(session.holyGrailState.phase, HolyGrailPhase.completed);
    expect(session.holyGrailState.winnerMasterId, 'master_1');
    expect(session.status, TRPGSessionStatus.completed);
  });

  test('12 holyGrailState 可以完整 Save Load', () {
    final session = manager
        .summonServant(initialized, masterId: 'master_1', catalyst: '圣遗物')
        .session;
    final restored = TRPGSession.fromJson(session.toJson());
    expect(restored.schemaVersion, trpgSchemaVersion);
    expect(
      restored.holyGrailState.servants.single.trueName,
      session.holyGrailState.servants.single.trueName,
    );
    expect(restored.holyGrailState.masters.first.commandSpells, 3);
  });

  test('13 从者召唤后接入 Living NPC Brain', () {
    final session = manager
        .summonServant(initialized, masterId: 'master_1', catalyst: '传说残片')
        .session;
    final servantId = session.holyGrailState.servants.single.servantId;
    expect(session.livingNpcState.brains.containsKey(servantId), isTrue);
    expect(session.livingNpcState.brains[servantId]!.goals, isNotEmpty);
  });

  test('14 模板包含动态章节、任务、势力、结局和 GM 规则', () {
    final campaign = templates.holyGrailWar();
    expect(campaign.campaignType, CampaignType.holyGrailWar);
    expect(campaign.toJson()['campaignType'], 'HOLY_GRAIL_WAR');
    expect(campaign.acts, hasLength(5));
    expect(campaign.quests.length, greaterThanOrEqualTo(5));
    expect(campaign.factions, hasLength(3));
    expect(campaign.endings, hasLength(5));
    expect(campaign.systemPrompt, contains('隐藏'));
  });

  test('15 开局为所有阵营生成固定能力和七骑英灵', () {
    final ready = manager.prepareOpening(initialized);
    expect(ready.holyGrailState.servants, hasLength(7));
    expect(
      ready.holyGrailState.servants.map((value) => value.classType).toSet(),
      hasLength(7),
    );
    for (final master in ready.holyGrailState.masters) {
      final attributes = master.resources['attributes'] as Map;
      final rolls = master.resources['attributeRolls'] as Map;
      expect(attributes, hasLength(6));
      expect(
        rolls.values.every((value) => (value as List).length == 3),
        isTrue,
      );
      expect(master.resources['incitingIncident'], isNotEmpty);
      expect(master.servantId, isNotNull);
    }
    final second = manager.prepareOpening(ready);
    expect(second.toJson(), ready.toJson());
  });

  test('16 每名玩家只收到自己的御主与英灵私密开局', () {
    final ready = manager.prepareOpening(initialized);
    final messages = ready.immersionState.privateMessages;
    expect(messages, hasLength(2));
    expect(
      messages.singleWhere((m) => m.recipientIds.contains('player-a')).content,
      contains('仅你可见 · 御主开局'),
    );
    expect(
      messages.singleWhere((m) => m.recipientIds.contains('player-b')).content,
      contains('仅你可见 · 契约英灵'),
    );
    expect(
      ready.chatHistory.any(
        (message) => ready.holyGrailState.servants.any(
          (servant) => message.content.contains(servant.trueName),
        ),
      ),
      isFalse,
    );
  });

  test('17 公共视图隐藏所有御主能力，玩家视图只开放自己的能力', () {
    final ready = manager.prepareOpening(initialized);
    final public = ready.holyGrailState.publicView();
    expect(public.masters.every((master) => master.magicAbility == 0), isTrue);
    expect(public.masters.every((master) => master.resources.isEmpty), isTrue);

    final playerView = ready.holyGrailState.forPlayer('player-a');
    final own = playerView.masters.singleWhere(
      (master) => master.ownerPlayerId == 'player-a',
    );
    expect(own.resources['attributes'], isNotNull);
    expect(
      playerView.masters
          .where((master) => master.masterId != own.masterId)
          .every((master) => master.resources.isEmpty),
      isTrue,
    );
  });

  test('18 私密开局完整保存并恢复', () {
    final ready = manager.prepareOpening(initialized);
    final restored = TRPGSession.fromJson(ready.toJson());
    expect(restored.metadata['holyGrailOpeningPrepared'], isTrue);
    expect(restored.immersionState.privateMessages, hasLength(2));
    expect(
      restored.holyGrailState.masters.first.resources['attributeRolls'],
      ready.holyGrailState.masters.first.resources['attributeRolls'],
    );
  });

  test('19 官方模板绑定 Fate 共享世界书与来源', () {
    final campaign = templates.holyGrailWar();
    final entries = campaign.metadata['fateWorldBook'] as List;
    final sources = campaign.metadata['officialLoreSources'] as List;
    expect(
      campaign.metadata['fateUniverseMode'],
      'parallel_branch_original_holy_grail_war',
    );
    expect(entries.length, greaterThanOrEqualTo(12));
    expect(entries.toString(), contains('平行世界'));
    expect(entries.toString(), contains('魔术协会'));
    expect(entries.toString(), contains('英灵座'));
    expect(sources.length, greaterThanOrEqualTo(8));
    expect(sources.toString(), contains('fatesf-anime.com/world'));
  });

  test('20 重抽只更新本人私密御主档案并保留英灵契约', () {
    final ready = manager.prepareOpening(initialized);
    final ownBefore = ready.holyGrailState.masters.singleWhere(
      (master) => master.ownerPlayerId == 'player-a',
    );
    final otherBefore = ready.holyGrailState.masters.singleWhere(
      (master) => master.ownerPlayerId == 'player-b',
    );
    final result = manager.rerollMasterDossier(
      ready,
      playerId: 'player-a',
      nonce: 20260821,
    );
    final ownAfter = result.session.holyGrailState.masters.singleWhere(
      (master) => master.ownerPlayerId == 'player-a',
    );
    final otherAfter = result.session.holyGrailState.masters.singleWhere(
      (master) => master.ownerPlayerId == 'player-b',
    );
    expect(result.succeeded, isTrue);
    expect(ownAfter.resources['dossierRerollCount'], 1);
    expect(ownAfter.servantId, ownBefore.servantId);
    expect(
      ownAfter.resources['attributeRolls'],
      isNot(ownBefore.resources['attributeRolls']),
    );
    expect(otherAfter.toJson(), otherBefore.toJson());
    expect(result.session.holyGrailState.servants, hasLength(7));
    expect(
      result.session.immersionState.privateMessages.where(
        (message) => message.recipientIds.contains('player-a'),
      ),
      hasLength(1),
    );
    expect(
      result.session.chatHistory.any(
        (message) => message.content.contains(ownAfter.origin),
      ),
      isFalse,
    );
  });

  test('21 从者参数真正进入宝具权威检定并使用重要动画', () {
    final ready = manager.prepareOpening(initialized);
    final outcome = TRPGCheckPipeline(random: Random(19)).resolveAction(
      session: ready,
      action: '我命令自己的从者释放宝具攻击敌方阵营。',
      actionId: 'holy-np-check',
      playerId: 'player-a',
      characterId: 'character-a',
      targetId: 'master_2',
    );
    expect(outcome.result, isNotNull);
    expect(outcome.result!.presentationMode, DicePresentationMode.dramatic);
    expect(
      outcome.result!.modifierSources.any(
        (value) => value.category == 'holyGrailRank',
      ),
      isTrue,
    );
  });
}

TRPGSession _session() {
  final now = DateTime(2026, 8, 21);
  return TRPGSession(
    id: 'holy-test',
    title: '第七次圣杯战争',
    mode: TRPGMode.multiplayer,
    createdAt: now,
    updatedAt: now,
    lastPlayedAt: now,
    status: TRPGSessionStatus.active,
    campaignId: 'holy_grail_war_fuyuki_echo',
    players: [
      TRPGPlayer(
        playerId: 'player-a',
        displayName: '玩家A',
        characterId: 'character-a',
        joinedAt: now,
      ),
      TRPGPlayer(
        playerId: 'player-b',
        displayName: '玩家B',
        characterId: 'character-b',
        joinedAt: now,
      ),
    ],
    playerCharacters: const [
      PlayerCharacter(
        id: 'character-a',
        playerId: 'player-a',
        name: '御主A',
        stats: {'STR': 10, 'DEX': 10, 'INT': 12, 'PER': 10, 'CHA': 10},
        hp: 20,
        maxHp: 20,
      ),
      PlayerCharacter(
        id: 'character-b',
        playerId: 'player-b',
        name: '御主B',
        stats: {'STR': 10, 'DEX': 10, 'INT': 12, 'PER': 10, 'CHA': 10},
        hp: 20,
        maxHp: 20,
      ),
    ],
    metadata: const {'campaignType': 'HOLY_GRAIL_WAR'},
  );
}
