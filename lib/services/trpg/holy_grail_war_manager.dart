import 'dart:convert';
import 'dart:math';

import 'package:uuid/uuid.dart';

import '../../models/campaign_models.dart';
import '../../models/holy_grail_war_models.dart';
import '../../models/trpg_game_models.dart';
import '../../models/trpg_models.dart';
import 'campaign_template_service.dart';
import 'living_npc_service.dart';

class HolyGrailActionResult {
  const HolyGrailActionResult(
    this.session,
    this.summary, {
    this.succeeded = true,
  });
  final TRPGSession session;
  final String summary;
  final bool succeeded;
}

class HolyGrailWarManager {
  const HolyGrailWarManager({this.livingNpcService = const LivingNPCService()});

  static const _uuid = Uuid();
  final LivingNPCService livingNpcService;

  bool isHolyGrailCampaign(TRPGSession session) =>
      session.holyGrailState.initialized ||
      session.metadata['campaignType'] == 'HOLY_GRAIL_WAR' ||
      session.immersionState.campaignSnapshot['campaignType'] ==
          'HOLY_GRAIL_WAR' ||
      session.immersionState.campaignSnapshot['campaignType'] ==
          CampaignType.holyGrailWar.name;

  TRPGSession initialize(TRPGSession session, {CampaignDocument? campaign}) {
    if (session.holyGrailState.initialized) return session;
    final fromCampaign = campaign?.campaignType == CampaignType.holyGrailWar;
    if (!fromCampaign && !isHolyGrailCampaign(session)) return session;
    final participants = session.players
        .where((value) => value.role != TRPGPlayerRole.humanGm)
        .take(7)
        .toList();
    final masters = List<MasterCharacter>.generate(7, (index) {
      final slot = index + 1;
      final player = index < participants.length ? participants[index] : null;
      final character = session.playerCharacters
          .where((value) => value.playerId == player?.playerId)
          .firstOrNull;
      final owned = player != null;
      return MasterCharacter(
        masterId: 'master_$slot',
        characterId: owned
            ? (character?.id ?? 'character_$slot')
            : 'ai_master_$slot',
        ownerPlayerId: owned ? player.playerId : null,
        name: owned ? (character?.name ?? player.displayName) : '第$slot阵营御主',
        archetype: owned
            ? MasterArchetype.ordinaryMage
            : _aiArchetypes[index % _aiArchetypes.length],
        magicAbility: owned ? 45 : 45 + index * 6,
        origin: owned ? '未定' : _aiOrigins[index % _aiOrigins.length],
        family: owned ? '新兴术式家系' : _aiFamilies[index % _aiFamilies.length],
        wish: owned ? '在战争中寻找自己的答案' : _aiWishes[index % _aiWishes.length],
        personality: owned
            ? '谨慎但不愿旁观'
            : _aiPersonalities[index % _aiPersonalities.length],
        resources: {'mana': 70 + index * 4, 'funds': 40 + index * 5},
      );
    });
    final information = <String, HolyGrailInformation>{
      for (final item in session.players)
        item.playerId: HolyGrailInformation(ownerPlayerId: item.playerId),
    };
    final now = DateTime.now();
    final state = HolyGrailWarState(
      initialized: true,
      masters: masters,
      informationByPlayer: information,
      history: [
        HolyGrailHistoryEntry(
          id: _uuid.v4(),
          type: 'war_initialized',
          summary: '第七次圣杯战争的灵脉开始活化，七个御主席位已经形成。',
          createdAt: now,
        ),
      ],
    );
    return session.copyWith(
      holyGrailState: state,
      metadata: {
        ...session.metadata,
        'campaignType': 'HOLY_GRAIL_WAR',
        'holyGrailVersion': 1,
      },
      worldState: session.worldState.copyWith(
        time: '召唤之夜',
        location: session.worldState.location.isEmpty
            ? '冬木市'
            : session.worldState.location,
        factionRelations: {
          ...session.worldState.factionRelations,
          'mage_association': 0,
          'holy_church': 0,
          'three_families': 0,
        },
        worldFlags: {
          ...session.worldState.worldFlags,
          'holy_grail_war_active': true,
        },
      ),
      eventLog: [
        ...session.eventLog,
        TRPGEvent(
          id: _uuid.v4(),
          type: TRPGEventType.holyGrailPhase,
          timestamp: now,
          payload: {'phase': HolyGrailPhase.phase1.name},
        ),
      ],
      updatedAt: now,
    );
  }

  /// Completes the authoritative opening setup for every occupied Holy Grail
  /// seat. Ability rolls and Servant bindings are stored once and never
  /// regenerated on later loads. Player-owned dossiers are delivered through
  /// player-private state; the public timeline receives no stat or True Name.
  TRPGSession prepareOpening(TRPGSession session) {
    var current = initialize(session);
    if (!current.holyGrailState.initialized ||
        current.metadata['holyGrailOpeningPrepared'] == true) {
      return current;
    }

    final generatedMasters = current.holyGrailState.masters
        .map((master) => _generateMasterDossier(current, master))
        .toList();
    current = current.copyWith(
      holyGrailState: current.holyGrailState.copyWith(
        masters: generatedMasters,
      ),
    );

    // Seven classes are assigned once. Player seats and AI/NPC seats follow
    // exactly the same rule so hidden NPC values remain stable in the save.
    for (final master in current.holyGrailState.masters) {
      if (master.servantId != null) continue;
      final catalyst = master.resources['catalyst']?.toString() ?? '';
      final result = summonServant(
        current,
        masterId: master.masterId,
        catalyst: catalyst,
      );
      if (result.succeeded) current = result.session;
    }

    final now = DateTime.now();
    final privateKnowledge = [...current.immersionState.privateKnowledge];
    final privateMessages = [...current.immersionState.privateMessages];
    final timeline = [...current.immersionState.timeline];
    for (final master in current.holyGrailState.masters) {
      final playerId = master.ownerPlayerId;
      if (playerId == null) continue;
      final servant = current.holyGrailState.servants
          .where((value) => value.masterId == master.masterId)
          .firstOrNull;
      final dossier = _privateOpeningDossier(master, servant);
      privateKnowledge.add(
        PrivateKnowledge(
          id: 'holy_grail_dossier_$playerId',
          title: '圣杯战争私密档案',
          content: dossier,
          visibility: InformationVisibility.playerPrivate,
          createdAt: now,
          ownerPlayerIds: [playerId],
          linkedEntityId: master.masterId,
        ),
      );
      privateMessages.add(
        TRPGPrivateMessage(
          id: _uuid.v4(),
          senderId: 'gm',
          recipientIds: [playerId],
          content: dossier,
          createdAt: now,
        ),
      );
      timeline.add(
        SessionTimelineEntry(
          id: _uuid.v4(),
          title: '你的召唤之夜',
          detail: dossier,
          createdAt: now,
          visibility: InformationVisibility.playerPrivate,
          ownerPlayerIds: [playerId],
        ),
      );
    }

    const publicOpening =
        '召唤之夜降临冬木。七处互不相通的灵脉同时亮起，七名御主分别收到了只属于自己的令咒、能力检定与英灵契约。公开频道不会显示任何阵营的私密属性；情报必须在行动中调查、交换或主动公开。';
    final chat = current.chatHistory
        .where(
          (message) =>
              !message.content.contains('你必须先决定自己为何而战') &&
              message.content != publicOpening,
        )
        .toList();
    chat.add(
      TRPGMessage(
        id: _uuid.v4(),
        messageType: TRPGMessageType.gmMessage,
        content: publicOpening,
        createdAt: now,
      ),
    );
    return current.copyWith(
      currentScene: publicOpening,
      chatHistory: chat,
      immersionState: current.immersionState.copyWith(
        privateKnowledge: privateKnowledge,
        privateMessages: privateMessages,
        timeline: timeline,
      ),
      metadata: {
        ...current.metadata,
        'holyGrailOpeningPrepared': true,
        'holyGrailOpeningVersion': 2,
      },
      worldState: current.worldState.copyWith(
        time: '召唤之夜',
        weather: '阴云与灵脉震荡',
        location: '冬木市',
        currentScene: const SceneState(
          sceneId: 'hgw_summoning_night',
          locationId: 'fuyuki_city',
          title: '冬木市 · 召唤之夜',
          description: publicOpening,
          atmosphere: '隐秘、紧张、魔力涌动',
        ),
      ),
      updatedAt: now,
    );
  }

  MasterCharacter _generateMasterDossier(
    TRPGSession session,
    MasterCharacter master,
  ) {
    final rerollCount =
        (master.resources['dossierRerollCount'] as num?)?.toInt() ?? 0;
    final rerollNonce = master.resources['dossierRerollNonce'] ?? 0;
    final seed = _stableSeed(
      '${session.id}|${master.masterId}|${master.name}|$rerollCount|$rerollNonce',
    );
    final random = Random(seed);
    List<int> roll() => List<int>.generate(3, (_) => random.nextInt(6) + 1);
    final rolls = <String, List<int>>{
      'strength': roll(),
      'agility': roll(),
      'endurance': roll(),
      'magecraft': roll(),
      'perception': roll(),
      'willpower': roll(),
    };
    final attributes = rolls.map(
      (key, value) => MapEntry(key, value.fold<int>(0, (a, b) => a + b)),
    );
    final incident = _incitingIncidents[seed % _incitingIncidents.length];
    final playerOwned = master.ownerPlayerId != null;
    final origin = master.origin == '未定' || master.origin == '未明'
        ? _aiOrigins[(seed ~/ 3) % _aiOrigins.length]
        : master.origin;
    final family = master.family == '新兴术式家系' || master.family == '无名家系'
        ? _aiFamilies[(seed ~/ 5) % _aiFamilies.length]
        : master.family;
    final wish = master.wish == '在战争中寻找自己的答案' || master.wish.isEmpty
        ? _aiWishes[(seed ~/ 7) % _aiWishes.length]
        : master.wish;
    final personality =
        master.personality == '谨慎但不愿旁观' || master.personality.isEmpty
        ? _aiPersonalities[(seed ~/ 11) % _aiPersonalities.length]
        : master.personality;
    return MasterCharacter(
      masterId: master.masterId,
      characterId: master.characterId,
      name: master.name,
      archetype: playerOwned && master.archetype == MasterArchetype.ordinaryMage
          ? _aiArchetypes[(seed ~/ 13) % _aiArchetypes.length]
          : master.archetype,
      ownerPlayerId: master.ownerPlayerId,
      magicAbility: (attributes['magecraft']! * 5).clamp(25, 95),
      origin: origin,
      family: family,
      wish: wish,
      personality: personality,
      resources: {
        ...master.resources,
        'attributes': attributes,
        'attributeRolls': rolls,
        'incitingIncident': incident,
        'dossierGenerated': true,
        'dossierRerollCount': rerollCount,
        'dossierRerollNonce': rerollNonce,
      },
      commandSpells: master.commandSpells,
      servantId: master.servantId,
      knowledge: master.knowledge,
      alive: master.alive,
      locationId: _summoningLocations[seed % _summoningLocations.length],
    );
  }

  String _privateOpeningDossier(
    MasterCharacter master,
    ServantCharacter? servant,
  ) {
    final attributes = master.resources['attributes'] is Map
        ? (master.resources['attributes'] as Map).map(
            (key, value) => MapEntry(key.toString(), value),
          )
        : const <String, Object?>{};
    final rolls = master.resources['attributeRolls'] is Map
        ? (master.resources['attributeRolls'] as Map).map(
            (key, value) => MapEntry(key.toString(), value),
          )
        : const <String, Object?>{};
    String stat(String key, String label) {
      final dice = (rolls[key] as List? ?? const []).join('+');
      return '$label ${attributes[key] ?? '?'}（3D6：$dice）';
    }

    final servantBlock = servant == null
        ? '英灵召唤尚未完成。'
        : '''
【仅你可见 · 契约英灵】
职阶：${holyGrailClassLabel(servant.classType)}
真名：${servant.trueName}
传说：${servant.legend}
性格：${servant.personality}
参数：筋力 ${parameterRankLabel(servant.parameters.strength)} / 耐久 ${parameterRankLabel(servant.parameters.endurance)} / 敏捷 ${parameterRankLabel(servant.parameters.agility)} / 魔力 ${parameterRankLabel(servant.parameters.mana)} / 幸运 ${parameterRankLabel(servant.parameters.luck)} / 宝具 ${parameterRankLabel(servant.parameters.noblePhantasm)}
技能：${servant.skills.join('、')}
宝具：${servant.noblePhantasm.hiddenName}（${parameterRankLabel(servant.noblePhantasm.rank)}）
''';
    return '''
【仅你可见 · 御主开局】
${master.resources['incitingIncident'] ?? '你被冬木灵脉选中，令咒在手背成形。'}
身份：${masterArchetypeLabel(master.archetype)}
家系：${master.family}　起源：${master.origin}
愿望：${master.wish}
${stat('strength', '体魄')} / ${stat('agility', '敏捷')}
${stat('endurance', '耐力')} / ${stat('magecraft', '魔术')}
${stat('perception', '感知')} / ${stat('willpower', '意志')}
魔术资质：${master.magicAbility}　令咒：${master.commandSpells}/3
$servantBlock
这些资料不会进入公共频道；你可以在游戏中选择主动公开其中一部分。
'''
        .trim();
  }

  static int _stableSeed(String value) {
    var hash = 0x811c9dc5;
    for (final code in value.codeUnits) {
      hash ^= code;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }

  /// Re-rolls only one player's private Master dossier before the war leaves
  /// the summoning phase. The bound Servant, every other team, public chat and
  /// public history remain untouched.
  HolyGrailActionResult rerollMasterDossier(
    TRPGSession session, {
    required String playerId,
    int? nonce,
  }) {
    final state = session.holyGrailState;
    if (!state.initialized || state.phase != HolyGrailPhase.phase1) {
      return HolyGrailActionResult(session, '只能在召唤之夜重抽御主档案', succeeded: false);
    }
    final index = state.masters.indexWhere(
      (master) => master.ownerPlayerId == playerId,
    );
    if (index < 0) {
      return HolyGrailActionResult(session, '找不到当前玩家的御主席位', succeeded: false);
    }
    final previous = state.masters[index];
    final count =
        ((previous.resources['dossierRerollCount'] as num?)?.toInt() ?? 0) + 1;
    final base = MasterCharacter(
      masterId: previous.masterId,
      characterId: previous.characterId,
      name: previous.name,
      archetype: MasterArchetype.ordinaryMage,
      ownerPlayerId: previous.ownerPlayerId,
      magicAbility: 45,
      origin: '未定',
      family: '新兴术式家系',
      wish: '在战争中寻找自己的答案',
      personality: '谨慎但不愿旁观',
      resources: {
        ...previous.resources,
        'dossierRerollCount': count,
        'dossierRerollNonce': nonce ?? DateTime.now().microsecondsSinceEpoch,
      },
      commandSpells: previous.commandSpells,
      servantId: previous.servantId,
      knowledge: previous.knowledge,
      alive: previous.alive,
      locationId: previous.locationId,
    );
    final generated = _generateMasterDossier(session, base);
    final masters = [...state.masters]..[index] = generated;
    final servant = state.servants
        .where((item) => item.masterId == generated.masterId)
        .firstOrNull;
    final dossier = _privateOpeningDossier(generated, servant);
    final now = DateTime.now();
    final privateKnowledge =
        session.immersionState.privateKnowledge
            .where((item) => item.id != 'holy_grail_dossier_$playerId')
            .toList()
          ..add(
            PrivateKnowledge(
              id: 'holy_grail_dossier_$playerId',
              title: '圣杯战争私密档案',
              content: dossier,
              visibility: InformationVisibility.playerPrivate,
              createdAt: now,
              ownerPlayerIds: [playerId],
              linkedEntityId: generated.masterId,
            ),
          );
    final privateMessages =
        session.immersionState.privateMessages
            .where(
              (message) =>
                  !message.recipientIds.contains(playerId) ||
                  !message.content.startsWith('【仅你可见 · 御主开局】'),
            )
            .toList()
          ..add(
            TRPGPrivateMessage(
              id: _uuid.v4(),
              senderId: 'gm',
              recipientIds: [playerId],
              content: dossier,
              createdAt: now,
            ),
          );
    final timeline =
        session.immersionState.timeline
            .where(
              (item) =>
                  item.title != '你的召唤之夜' ||
                  !item.ownerPlayerIds.contains(playerId),
            )
            .toList()
          ..add(
            SessionTimelineEntry(
              id: _uuid.v4(),
              title: '你的召唤之夜',
              detail: dossier,
              createdAt: now,
              visibility: InformationVisibility.playerPrivate,
              ownerPlayerIds: [playerId],
            ),
          );
    return HolyGrailActionResult(
      session.copyWith(
        holyGrailState: state.copyWith(masters: masters),
        immersionState: session.immersionState.copyWith(
          privateKnowledge: privateKnowledge,
          privateMessages: privateMessages,
          timeline: timeline,
        ),
        metadata: {
          ...session.metadata,
          'holyGrailDossierRerolls': {
            ...(session.metadata['holyGrailDossierRerolls'] as Map? ??
                const {}),
            playerId: count,
          },
        },
        updatedAt: now,
      ),
      '已随机重抽你的卷入事件、魔术背景、起源与能力值',
    );
  }

  HolyGrailActionResult selectMaster(
    TRPGSession session, {
    required String playerId,
    required MasterArchetype archetype,
    String? wish,
    String? personality,
    String? origin,
    String? family,
  }) {
    final state = session.holyGrailState;
    if (!state.initialized) {
      return HolyGrailActionResult(session, '圣杯战争尚未初始化', succeeded: false);
    }
    final character = session.playerCharacters
        .where((value) => value.playerId == playerId)
        .firstOrNull;
    final player = session.players
        .where((value) => value.playerId == playerId)
        .firstOrNull;
    if (player == null) {
      return HolyGrailActionResult(session, '玩家不存在', succeeded: false);
    }
    final existingIndex = state.masters.indexWhere(
      (value) => value.ownerPlayerId == playerId,
    );
    final slotIndex = existingIndex >= 0
        ? existingIndex
        : state.masters.indexWhere((value) => value.ownerPlayerId == null);
    if (slotIndex < 0) {
      return HolyGrailActionResult(session, '七个御主席位均已被占用', succeeded: false);
    }
    final base = _preset(archetype);
    final old = state.masters[slotIndex];
    final selected = MasterCharacter(
      masterId: old.masterId,
      characterId: character?.id ?? old.characterId,
      ownerPlayerId: playerId,
      name: character?.name ?? player.displayName,
      archetype: archetype,
      magicAbility: base.$1,
      origin: origin?.trim().isNotEmpty == true ? origin!.trim() : base.$2,
      family: family?.trim().isNotEmpty == true ? family!.trim() : base.$3,
      wish: wish?.trim().isNotEmpty == true ? wish!.trim() : base.$4,
      personality: personality?.trim().isNotEmpty == true
          ? personality!.trim()
          : base.$5,
      resources: base.$6,
      commandSpells: old.commandSpells,
      servantId: old.servantId,
    );
    final masters = [...state.masters]..[slotIndex] = selected;
    final next = session.copyWith(
      holyGrailState: state.copyWith(
        masters: masters,
        informationByPlayer: {
          ...state.informationByPlayer,
          playerId:
              state.informationByPlayer[playerId] ??
              HolyGrailInformation(ownerPlayerId: playerId),
        },
      ),
      updatedAt: DateTime.now(),
    );
    return HolyGrailActionResult(
      next,
      '${selected.name}已选择“${masterArchetypeLabel(archetype)}”身份',
    );
  }

  HolyGrailActionResult summonServant(
    TRPGSession session, {
    required String masterId,
    String catalyst = '',
  }) {
    final state = session.holyGrailState;
    final masterIndex = state.masters.indexWhere(
      (value) => value.masterId == masterId,
    );
    if (masterIndex < 0) {
      return HolyGrailActionResult(session, '御主不存在', succeeded: false);
    }
    final master = state.masters[masterIndex];
    if (master.servantId != null) {
      return HolyGrailActionResult(session, '该御主已经完成召唤', succeeded: false);
    }
    final used = state.servants.map((value) => value.classType).toSet();
    final candidates = _servantPool
        .where((value) => !used.contains(value.classType))
        .toList();
    if (candidates.isEmpty) {
      return HolyGrailActionResult(session, '七个职阶已经全部降临', succeeded: false);
    }
    final key =
        '${master.wish}|${master.personality}|${master.origin}|$catalyst';
    final normalized = key.codeUnits.fold<int>(0, (sum, value) => sum + value);
    final match = candidates[normalized % candidates.length];
    final servant = ServantCharacter(
      servantId:
          'servant_${match.classType.name}_${_uuid.v4().substring(0, 8)}',
      classType: match.classType,
      trueName: match.trueName,
      legend: match.legend,
      appearance: match.appearance,
      personality: match.personality,
      parameters: match.parameters,
      skills: match.skills,
      noblePhantasm: match.noblePhantasm,
      masterId: master.masterId,
      relationship: 10,
      trueNameRevealedTo: [
        if (master.ownerPlayerId != null) master.ownerPlayerId!,
      ],
    );
    final updatedMaster = master.copyWith(servantId: servant.servantId);
    final masters = [...state.masters]..[masterIndex] = updatedMaster;
    final relationship = MasterServantRelationship(
      masterId: master.masterId,
      servantId: servant.servantId,
      trust: 10,
      respect: master.magicAbility >= 70 ? 20 : 5,
      obedience: 15,
    );
    final now = DateTime.now();
    final history = HolyGrailHistoryEntry(
      id: _uuid.v4(),
      type: 'summoning',
      summary:
          '${master.name}召唤出${holyGrailClassLabel(servant.classType)}职阶从者。',
      createdAt: now,
      visibilityPlayerIds: [
        if (master.ownerPlayerId != null) master.ownerPlayerId!,
      ],
      metadata: {'masterId': master.masterId, 'servantId': servant.servantId},
    );
    final worldNpc = NPCState(
      npcId: servant.servantId,
      name: holyGrailClassLabel(servant.classType),
      locationId: master.locationId,
      relationship: servant.relationship,
      knownToPlayer: master.ownerPlayerId != null,
      notes: '独立从者人格：${servant.personality}；目标与愿望相关，但不会盲从御主。',
      hp: 40,
      maxHp: 40,
    );
    var next = session.copyWith(
      holyGrailState: state.copyWith(
        masters: masters,
        servants: [...state.servants, servant],
        relationships: [...state.relationships, relationship],
        history: [...state.history, history],
      ),
      worldState: session.worldState.copyWith(
        npcs: [...session.worldState.npcs, worldNpc],
        knownNpcs: [
          ...session.worldState.knownNpcs,
          if (master.ownerPlayerId != null) servant.servantId,
        ],
      ),
      eventLog: [
        ...session.eventLog,
        TRPGEvent(
          id: _uuid.v4(),
          type: TRPGEventType.holyGrailSummoning,
          timestamp: now,
          payload: {
            'masterId': master.masterId,
            'servantId': servant.servantId,
            'classType': servant.classType.name,
            'visibilityPlayerIds': [
              if (master.ownerPlayerId != null) master.ownerPlayerId!,
            ],
          },
        ),
      ],
      updatedAt: now,
    );
    next = livingNpcService.ensureInitialized(next);
    return HolyGrailActionResult(
      next,
      '召唤完成：${holyGrailClassLabel(servant.classType)}回应了${master.name}',
    );
  }

  HolyGrailActionResult investigate(
    TRPGSession session, {
    required String playerId,
    required String targetServantId,
    required InvestigationAction action,
  }) {
    final state = session.holyGrailState;
    final servant = state.servants
        .where((value) => value.servantId == targetServantId)
        .firstOrNull;
    if (servant == null) {
      return HolyGrailActionResult(session, '调查目标不存在', succeeded: false);
    }
    final info =
        state.informationByPlayer[playerId] ??
        HolyGrailInformation(ownerPlayerId: playerId);
    final observed = [...?info.observedAbilities[targetServantId]];
    final amount = switch (action) {
      InvestigationAction.observe => 1,
      InvestigationAction.follow => 2,
      InvestigationAction.investigate => 3,
      InvestigationAction.ambush => 2,
    };
    for (final skill in servant.skills.take(amount)) {
      if (!observed.contains(skill)) observed.add(skill);
    }
    final revealed = observed.length >= 3;
    final suspected = {...info.suspectedIdentity};
    if (observed.length >= 2) {
      suspected[targetServantId] = revealed
          ? servant.trueName
          : '与${servant.legend.split('。').first}有关';
    }
    final known = {...info.knownServantIds, targetServantId}.toList();
    final nextInfo = info.copyWith(
      knownServantIds: known,
      observedAbilities: {...info.observedAbilities, targetServantId: observed},
      suspectedIdentity: suspected,
    );
    final servants = state.servants.map((value) {
      if (value.servantId != targetServantId || !revealed) return value;
      return value.copyWith(
        trueNameRevealedTo: {...value.trueNameRevealedTo, playerId}.toList(),
      );
    }).toList();
    final now = DateTime.now();
    final next = session.copyWith(
      holyGrailState: state.copyWith(
        servants: servants,
        informationByPlayer: {...state.informationByPlayer, playerId: nextInfo},
        history: [
          ...state.history,
          HolyGrailHistoryEntry(
            id: _uuid.v4(),
            type: 'investigation',
            summary: revealed
                ? '调查锁定了${holyGrailClassLabel(servant.classType)}的真名。'
                : '调查获得了新的能力特征。',
            createdAt: now,
            visibilityPlayerIds: [playerId],
          ),
        ],
      ),
      eventLog: [
        ...session.eventLog,
        TRPGEvent(
          id: _uuid.v4(),
          type: TRPGEventType.holyGrailInvestigation,
          timestamp: now,
          payload: {
            'playerId': playerId,
            'targetServantId': targetServantId,
            'revealed': revealed,
          },
        ),
      ],
      updatedAt: now,
    );
    return HolyGrailActionResult(
      next,
      revealed ? '调查成功：真名已确认' : '调查成功：记录了${observed.length}项能力特征',
    );
  }

  HolyGrailActionResult useCommandSpell(
    TRPGSession session, {
    required String masterId,
    required CommandSpellEffect effect,
    required String order,
  }) {
    final state = session.holyGrailState;
    final masterIndex = state.masters.indexWhere(
      (value) => value.masterId == masterId,
    );
    if (masterIndex < 0) {
      return HolyGrailActionResult(session, '御主不存在', succeeded: false);
    }
    final master = state.masters[masterIndex];
    if (master.commandSpells <= 0 || master.servantId == null) {
      return HolyGrailActionResult(session, '没有可用令咒或尚未召唤从者', succeeded: false);
    }
    final cost = effect == CommandSpellEffect.strengthen ? 1 : 1;
    final masters = [...state.masters]
      ..[masterIndex] = master.copyWith(
        commandSpells: master.commandSpells - cost,
      );
    final relationships = state.relationships.map((value) {
      if (value.masterId != masterId) return value;
      return switch (effect) {
        CommandSpellEffect.forceOrder => value.copyWith(
          obedience: 100,
          conflict: value.conflict + 20,
          trust: value.trust - 12,
        ),
        CommandSpellEffect.strengthen => value.copyWith(
          trust: value.trust + 5,
          respect: value.respect + 8,
        ),
        CommandSpellEffect.recall => value.copyWith(fear: value.fear - 8),
      };
    }).toList();
    final now = DateTime.now();
    var next = session.copyWith(
      holyGrailState: state.copyWith(
        masters: masters,
        relationships: relationships,
        history: [
          ...state.history,
          HolyGrailHistoryEntry(
            id: _uuid.v4(),
            type: 'command_spell',
            summary: '${master.name}消耗一划令咒：$order',
            createdAt: now,
            visibilityPlayerIds: [
              if (master.ownerPlayerId != null) master.ownerPlayerId!,
            ],
          ),
        ],
      ),
      eventLog: [
        ...session.eventLog,
        TRPGEvent(
          id: _uuid.v4(),
          type: TRPGEventType.holyGrailCommandSpell,
          timestamp: now,
          payload: {
            'masterId': masterId,
            'effect': effect.name,
            'order': order,
          },
        ),
      ],
      updatedAt: now,
    );
    if (effect == CommandSpellEffect.recall) {
      final locations = {...next.npcLocations};
      final location = next.characterLocations[master.characterId];
      if (location != null) locations[master.servantId!] = location;
      next = next.copyWith(npcLocations: locations);
    }
    return HolyGrailActionResult(
      next,
      '令咒生效，剩余${master.commandSpells - cost}划',
    );
  }

  HolyGrailActionResult releaseNoblePhantasm(
    TRPGSession session, {
    required String servantId,
    required bool trueNameRelease,
    List<String> witnessPlayerIds = const [],
  }) {
    final state = session.holyGrailState;
    final servantIndex = state.servants.indexWhere(
      (value) => value.servantId == servantId,
    );
    if (servantIndex < 0) {
      return HolyGrailActionResult(session, '从者不存在', succeeded: false);
    }
    final servant = state.servants[servantIndex];
    final relation = state.relationships
        .where((value) => value.servantId == servantId)
        .firstOrNull;
    if (!trueNameRelease && relation?.mayRefuse == true) {
      return HolyGrailActionResult(session, '从者因关系恶化拒绝解放宝具', succeeded: false);
    }
    final revealedTo = trueNameRelease
        ? {...servant.trueNameRevealedTo, ...witnessPlayerIds}.toList()
        : servant.trueNameRevealedTo;
    final servants = [...state.servants]
      ..[servantIndex] = servant.copyWith(trueNameRevealedTo: revealedTo);
    final now = DateTime.now();
    final next = session.copyWith(
      holyGrailState: state.copyWith(
        servants: servants,
        history: [
          ...state.history,
          HolyGrailHistoryEntry(
            id: _uuid.v4(),
            type: 'noble_phantasm',
            summary: trueNameRelease
                ? '${holyGrailClassLabel(servant.classType)}解放真名：${servant.noblePhantasm.hiddenName}'
                : '${holyGrailClassLabel(servant.classType)}隐匿真名使用宝具能力',
            createdAt: now,
          ),
        ],
      ),
      eventLog: [
        ...session.eventLog,
        TRPGEvent(
          id: _uuid.v4(),
          type: TRPGEventType.holyGrailNoblePhantasm,
          timestamp: now,
          payload: {
            'servantId': servantId,
            'trueNameRelease': trueNameRelease,
            'powerMultiplier': trueNameRelease ? 1.75 : 1.0,
            'witnessPlayerIds': witnessPlayerIds,
          },
        ),
      ],
      updatedAt: now,
    );
    return HolyGrailActionResult(
      next,
      trueNameRelease ? '宝具真名已经解放，身份同时暴露' : '宝具以隐匿真名方式发动',
    );
  }

  HolyGrailActionResult formAlliance(
    TRPGSession session, {
    required List<String> masterIds,
    required String purpose,
    List<String> terms = const [],
  }) {
    if (masterIds.toSet().length < 2 ||
        masterIds.any(
          (id) => !session.holyGrailState.masters.any(
            (value) => value.masterId == id && value.alive,
          ),
        )) {
      return HolyGrailActionResult(
        session,
        '联盟至少需要两个仍在参战的御主',
        succeeded: false,
      );
    }
    final alliance = HolyAlliance(
      allianceId: _uuid.v4(),
      masterIds: masterIds.toSet().toList(),
      purpose: purpose,
      terms: terms,
    );
    final now = DateTime.now();
    return HolyGrailActionResult(
      session.copyWith(
        holyGrailState: session.holyGrailState.copyWith(
          alliances: [...session.holyGrailState.alliances, alliance],
          history: [
            ...session.holyGrailState.history,
            HolyGrailHistoryEntry(
              id: _uuid.v4(),
              type: 'alliance',
              summary: '一项以“$purpose”为目标的临时盟约成立。',
              createdAt: now,
            ),
          ],
        ),
        eventLog: [
          ...session.eventLog,
          TRPGEvent(
            id: _uuid.v4(),
            type: TRPGEventType.holyGrailAlliance,
            timestamp: now,
            payload: alliance.toJson(),
          ),
        ],
        updatedAt: now,
      ),
      '临时联盟已经成立',
    );
  }

  HolyGrailActionResult breakAlliance(
    TRPGSession session, {
    required String allianceId,
    required String actorMasterId,
    bool betrayal = false,
  }) {
    final index = session.holyGrailState.alliances.indexWhere(
      (value) => value.allianceId == allianceId,
    );
    if (index < 0) {
      return HolyGrailActionResult(session, '联盟不存在', succeeded: false);
    }
    final alliance = session.holyGrailState.alliances[index];
    if (!alliance.masterIds.contains(actorMasterId)) {
      return HolyGrailActionResult(session, '该御主不是联盟成员', succeeded: false);
    }
    final alliances = [...session.holyGrailState.alliances]
      ..[index] = alliance.copyWith(
        status: betrayal
            ? HolyAllianceStatus.betrayed
            : HolyAllianceStatus.broken,
      );
    final now = DateTime.now();
    final type = betrayal
        ? TRPGEventType.holyGrailBetrayal
        : TRPGEventType.holyGrailAlliance;
    return HolyGrailActionResult(
      session.copyWith(
        holyGrailState: session.holyGrailState.copyWith(alliances: alliances),
        eventLog: [
          ...session.eventLog,
          TRPGEvent(
            id: _uuid.v4(),
            type: type,
            timestamp: now,
            payload: {'allianceId': allianceId, 'actorMasterId': actorMasterId},
          ),
        ],
        updatedAt: now,
      ),
      betrayal ? '联盟遭到背叛' : '联盟已经解除',
    );
  }

  HolyGrailActionResult eliminateTeam(
    TRPGSession session, {
    required String masterId,
    required bool masterKilled,
  }) {
    final state = session.holyGrailState;
    final index = state.masters.indexWhere(
      (value) => value.masterId == masterId,
    );
    if (index < 0) {
      return HolyGrailActionResult(session, '目标御主不存在', succeeded: false);
    }
    final master = state.masters[index];
    final masters = [...state.masters]
      ..[index] = master.copyWith(alive: !masterKilled);
    final servants = state.servants.map((value) {
      if (value.masterId != masterId) return value;
      return value.copyWith(alive: false);
    }).toList();
    var next = session.copyWith(
      holyGrailState: state.copyWith(masters: masters, servants: servants),
    );
    next = evaluatePhaseAndVictory(next);
    return HolyGrailActionResult(next, '${master.name}阵营已经退场');
  }

  TRPGSession evaluatePhaseAndVictory(TRPGSession session) {
    final state = session.holyGrailState;
    final aliveTeams = state.masters.where((master) {
      final servant = state.servants
          .where((value) => value.masterId == master.masterId)
          .firstOrNull;
      return master.alive && (servant?.alive ?? true);
    }).toList();
    final eventCount = state.history.length;
    var phase = state.phase;
    if (aliveTeams.length <= 1 && state.servants.length >= 2) {
      phase = HolyGrailPhase.completed;
    } else if (aliveTeams.length <= 2) {
      phase = HolyGrailPhase.phase5;
    } else if (aliveTeams.length <= 4 || eventCount >= 20) {
      phase = HolyGrailPhase.phase4;
    } else if (state.alliances.isNotEmpty || eventCount >= 12) {
      phase = HolyGrailPhase.phase3;
    } else if (state.servants.length >= 7 || eventCount >= 7) {
      phase = HolyGrailPhase.phase2;
    }
    final winner = phase == HolyGrailPhase.completed
        ? aliveTeams.firstOrNull?.masterId
        : null;
    final ending = winner == null
        ? null
        : (state.anomalyLevel >= 70
              ? HolyGrailEnding.grailCorrupted
              : HolyGrailEnding.grailClaimed);
    if (phase == state.phase && winner == state.winnerMasterId) return session;
    final now = DateTime.now();
    return session.copyWith(
      status: phase == HolyGrailPhase.completed
          ? TRPGSessionStatus.completed
          : session.status,
      holyGrailState: state.copyWith(
        phase: phase,
        winnerMasterId: winner,
        ending: ending,
        history: [
          ...state.history,
          HolyGrailHistoryEntry(
            id: _uuid.v4(),
            type: phase == HolyGrailPhase.completed ? 'ending' : 'phase',
            summary: phase == HolyGrailPhase.completed
                ? '圣杯战争结束。'
                : '战争推进至${holyGrailPhaseLabel(phase)}。',
            createdAt: now,
          ),
        ],
      ),
      eventLog: [
        ...session.eventLog,
        TRPGEvent(
          id: _uuid.v4(),
          type: phase == HolyGrailPhase.completed
              ? TRPGEventType.holyGrailEnding
              : TRPGEventType.holyGrailPhase,
          timestamp: now,
          payload: {
            'phase': phase.name,
            'winnerMasterId': winner,
            'ending': ending?.name,
          },
        ),
      ],
      updatedAt: now,
    );
  }

  String buildGmContext(
    TRPGSession session, {
    String? playerId,
    bool fullGm = false,
  }) {
    final state = fullGm
        ? session.holyGrailState
        : playerId == null
        ? session.holyGrailState.publicView()
        : session.holyGrailState.forPlayer(playerId);
    final fateWorldBook = _buildFateWorldBookContext(session);
    return '''
【圣杯战争主持规则】
当前阶段：${holyGrailPhaseLabel(state.phase)}。每名御主都有独立愿望，每名从者均由 NPC Brain 驱动并可拒绝或背叛。
严禁提前泄露其他阵营的位置、计划、御主身份、从者真名、传说和宝具真名。公开回复只能使用当前视角已经获得的情报。
战斗应综合参数、已掌握情报、策略、关系、令咒与环境，不可只按旁白偏好决定。御主可以被追踪、保护或暗杀。
$fateWorldBook
结构化状态：${jsonEncode(state.toJson())}
''';
  }

  String _buildFateWorldBookContext(TRPGSession session) {
    final rawMetadata = session.immersionState.campaignSnapshot['metadata'];
    final bundledMetadata = const CampaignTemplateService()
        .holyGrailWar()
        .metadata;
    final rawEntries = rawMetadata is Map
        ? rawMetadata['fateWorldBook'] ?? bundledMetadata['fateWorldBook']
        : bundledMetadata['fateWorldBook'];
    if (rawEntries is! List || rawEntries.isEmpty) return '';
    final lines = <String>['【已绑定 Fate 共享世界书】'];
    for (final raw in rawEntries.whereType<Map>()) {
      final title = raw['title']?.toString().trim() ?? '';
      final content = raw['content']?.toString().trim() ?? '';
      if (content.isEmpty) continue;
      lines.add(title.isEmpty ? '- $content' : '- $title：$content');
    }
    return lines.join('\n');
  }

  static String masterArchetypeLabel(MasterArchetype value) => switch (value) {
    MasterArchetype.ordinaryMage => '普通魔术师',
    MasterArchetype.familyHeir => '魔术家族继承人',
    MasterArchetype.churchExecutor => '圣堂教会执行者',
    MasterArchetype.homunculus => '人工生命体',
    MasterArchetype.custom => '自定义御主',
  };

  static String holyGrailClassLabel(HolyGrailClass value) => switch (value) {
    HolyGrailClass.saber => 'Saber',
    HolyGrailClass.archer => 'Archer',
    HolyGrailClass.lancer => 'Lancer',
    HolyGrailClass.rider => 'Rider',
    HolyGrailClass.caster => 'Caster',
    HolyGrailClass.assassin => 'Assassin',
    HolyGrailClass.berserker => 'Berserker',
  };

  static String holyGrailPhaseLabel(HolyGrailPhase value) => switch (value) {
    HolyGrailPhase.phase1 => '召唤之夜',
    HolyGrailPhase.phase2 => '初次交战',
    HolyGrailPhase.phase3 => '联盟与猎杀',
    HolyGrailPhase.phase4 => '真相调查',
    HolyGrailPhase.phase5 => '最终决战',
    HolyGrailPhase.completed => '战争终局',
  };

  static String parameterRankLabel(ParameterRank value) => switch (value) {
    ParameterRank.e => 'E',
    ParameterRank.d => 'D',
    ParameterRank.c => 'C',
    ParameterRank.b => 'B',
    ParameterRank.a => 'A',
    ParameterRank.ex => 'EX',
  };

  static const _aiArchetypes = [
    MasterArchetype.familyHeir,
    MasterArchetype.churchExecutor,
    MasterArchetype.homunculus,
    MasterArchetype.ordinaryMage,
  ];
  static const _aiOrigins = ['切断', '承继', '空洞', '共鸣', '静止', '流转', '守护'];
  static const _aiFamilies = [
    '远坂旁系',
    '间桐旧门',
    '艾因兹贝伦工房',
    '圣堂教会',
    '流浪术师',
    '时钟塔派遣队',
    '本地灵脉守护者',
  ];
  static const _aiWishes = [
    '挽回无法挽回的人',
    '证明家系的价值',
    '终止仪式',
    '获得真正自由',
    '抵达根源',
    '守护冬木市',
    '揭露圣杯的真相',
  ];
  static const _aiPersonalities = [
    '冷静克制',
    '骄傲好胜',
    '虔诚果断',
    '天真敏锐',
    '现实多疑',
    '温和坚定',
    '自由不羁',
  ];
  static const _incitingIncidents = [
    '你在回家途中目击一场不可能存在的战斗。为避开贯穿街道的魔力余波，你本能抬手，三道令咒随灼痛浮现；圣杯把你从普通生活中强行拖入战争。',
    '一封没有寄件人的遗书把你带到废弃工房。你触碰残留召唤阵时继承了陌生魔术回路，也继承了上一位候选者未能完成的契约。',
    '你为救下一名被灵体袭击的路人而暴露潜藏回路。冬木灵脉回应了这个选择，令咒成形，教会随后通知你：退出已经不再安全。',
    '家族封存多年的礼装在午夜自行启动。你原本只想查明亲人的失踪，却发现名字已经被写入圣杯仪式的御主名单。',
    '一场重复数周的梦把你引向冬木。梦中英雄在火海里问你是否愿意承担代价；当你回答后醒来，召唤阵与令咒已同时出现。',
    '你在调查城市连续昏迷事件时发现魔力采集术式。破坏术式救人让你被幕后阵营锁定，也让圣杯判定你具备参战资格。',
    '本应属于他人的令咒在袭击中转移到你身上。你既不知道死去候选者的敌人是谁，也不知道即将回应召唤的英雄会如何评价这份继承。',
  ];
  static const _summoningLocations = [
    'miyama_town',
    'shinto_district',
    'fuyuki_church',
    'ryuudou_temple',
    'fuyuki_city',
  ];

  static (int, String, String, String, String, Map<String, Object?>) _preset(
    MasterArchetype archetype,
  ) => switch (archetype) {
    MasterArchetype.ordinaryMage => (
      45,
      '适应',
      '新兴魔术家系',
      '活着看见战争终结',
      '谨慎、善于变通',
      const {'mana': 65, 'funds': 45, 'difficulty': 'easy'},
    ),
    MasterArchetype.familyHeir => (
      72,
      '承继',
      '古老魔术家族',
      '让家系抵达根源',
      '自信、重视责任',
      const {'mana': 90, 'funds': 90, 'workshop': true, 'difficulty': 'normal'},
    ),
    MasterArchetype.churchExecutor => (
      62,
      '断罪',
      '圣堂教会',
      '阻止圣杯落入恶人之手',
      '果断、善于调查',
      const {
        'mana': 65,
        'funds': 60,
        'investigationBonus': 20,
        'difficulty': 'hard',
      },
    ),
    MasterArchetype.homunculus => (
      95,
      '献祭',
      '人工生命工房',
      '摆脱被制造的命运',
      '寡言、渴望自由',
      const {
        'mana': 120,
        'funds': 30,
        'secretIdentity': true,
        'difficulty': 'extreme',
      },
    ),
    MasterArchetype.custom => (
      55,
      '未定',
      '自定义家系',
      '尚未决定',
      '由玩家决定',
      const {'mana': 75, 'funds': 55, 'difficulty': 'custom'},
    ),
  };

  static final _servantPool = <ServantCharacter>[
    ServantCharacter(
      servantId: 'pool_saber',
      classType: HolyGrailClass.saber,
      trueName: '阿尔托莉亚·潘德拉贡',
      legend: '不列颠传说中的骑士王。',
      appearance: '银甲与深蓝披风的年轻剑士，持有被风遮蔽的剑。',
      personality: '克制、守诺、将责任置于个人愿望之前。',
      parameters: const ServantParameters(
        strength: ParameterRank.b,
        endurance: ParameterRank.b,
        agility: ParameterRank.b,
        mana: ParameterRank.a,
        luck: ParameterRank.a,
        noblePhantasm: ParameterRank.a,
      ),
      skills: const ['直感', '魔力放出', '对魔力'],
      noblePhantasm: const NoblePhantasm(
        name: '被风隐藏的王剑',
        hiddenName: '誓约胜利之剑',
        rank: ParameterRank.a,
        type: NoblePhantasmType.antiFortress,
        description: '将庞大魔力转化为光之斩击。',
        cost: 55,
        effect: '大范围高强度攻击，同时暴露真名。',
      ),
      masterId: '',
    ),
    ServantCharacter(
      servantId: 'pool_archer',
      classType: HolyGrailClass.archer,
      trueName: '阿拉什',
      legend: '以一箭划定国境的古代英雄。',
      appearance: '持长弓、身披轻甲的沉稳弓兵。',
      personality: '爽朗、可靠，愿以自身终结无谓的战争。',
      parameters: const ServantParameters(
        strength: ParameterRank.b,
        endurance: ParameterRank.c,
        agility: ParameterRank.b,
        mana: ParameterRank.c,
        luck: ParameterRank.b,
        noblePhantasm: ParameterRank.a,
      ),
      skills: const ['千里眼', '强健', '弓术'],
      noblePhantasm: const NoblePhantasm(
        name: '终境之矢',
        hiddenName: '流星一条',
        rank: ParameterRank.a,
        type: NoblePhantasmType.antiArmy,
        description: '以自身为代价射出终结战场的一箭。',
        cost: 100,
        condition: '从者自愿且承认必须牺牲',
        effect: '毁灭性范围攻击；使用者极可能退场。',
      ),
      masterId: '',
    ),
    ServantCharacter(
      servantId: 'pool_lancer',
      classType: HolyGrailClass.lancer,
      trueName: '库·丘林',
      legend: '凯尔特神话中的光之子。',
      appearance: '蓝色战装、持猩红长枪的敏捷战士。',
      personality: '豪爽好战，厌恶卑劣命令但尊重勇气。',
      parameters: const ServantParameters(
        strength: ParameterRank.b,
        endurance: ParameterRank.c,
        agility: ParameterRank.a,
        mana: ParameterRank.c,
        luck: ParameterRank.e,
        noblePhantasm: ParameterRank.b,
      ),
      skills: const ['战斗续行', '卢恩魔术', '避矢加护'],
      noblePhantasm: const NoblePhantasm(
        name: '逆转因果之枪',
        hiddenName: '刺穿死棘之枪',
        rank: ParameterRank.b,
        type: NoblePhantasmType.antiUnit,
        description: '先决定命中心脏，再倒置因果刺出的一击。',
        cost: 35,
        effect: '高概率致命的对人攻击。',
      ),
      masterId: '',
    ),
    ServantCharacter(
      servantId: 'pool_rider',
      classType: HolyGrailClass.rider,
      trueName: '亚历山大',
      legend: '远征至世界尽头的征服者。',
      appearance: '赤发壮硕、披红色斗篷的王者。',
      personality: '豪迈、包容，渴望与值得尊重者共同见证世界。',
      parameters: const ServantParameters(
        strength: ParameterRank.b,
        endurance: ParameterRank.a,
        agility: ParameterRank.d,
        mana: ParameterRank.c,
        luck: ParameterRank.a,
        noblePhantasm: ParameterRank.ex,
      ),
      skills: const ['领袖气质', '骑乘', '军略'],
      noblePhantasm: const NoblePhantasm(
        name: '王者远征',
        hiddenName: '王之军势',
        rank: ParameterRank.ex,
        type: NoblePhantasmType.antiArmy,
        description: '将共同远征的英灵军势展开为固有结界。',
        cost: 70,
        effect: '展开独立战场并召来军势。',
      ),
      masterId: '',
    ),
    ServantCharacter(
      servantId: 'pool_caster',
      classType: HolyGrailClass.caster,
      trueName: '美狄亚',
      legend: '科尔基斯的王女与古代魔术师。',
      appearance: '紫色长袍遮面的神秘术者。',
      personality: '聪慧而戒备，对背叛极度敏感，也珍惜真正的善意。',
      parameters: const ServantParameters(
        strength: ParameterRank.e,
        endurance: ParameterRank.d,
        agility: ParameterRank.c,
        mana: ParameterRank.a,
        luck: ParameterRank.b,
        noblePhantasm: ParameterRank.c,
      ),
      skills: const ['高速神言', '阵地建造', '道具作成'],
      noblePhantasm: const NoblePhantasm(
        name: '契约断绝之刃',
        hiddenName: '万符必应破戒',
        rank: ParameterRank.c,
        type: NoblePhantasmType.special,
        description: '解除以魔力建立的一切契约与术式。',
        cost: 25,
        effect: '解除契约、结界或控制效果。',
      ),
      masterId: '',
    ),
    ServantCharacter(
      servantId: 'pool_assassin',
      classType: HolyGrailClass.assassin,
      trueName: '山中老人·百貌',
      legend: '暗杀教团传说中拥有众多人格的首领。',
      appearance: '戴白色骷髅面具、藏于暗影中的刺客。',
      personality: '谨慎服从，但不同人格拥有不同偏好和判断。',
      parameters: const ServantParameters(
        strength: ParameterRank.c,
        endurance: ParameterRank.d,
        agility: ParameterRank.a,
        mana: ParameterRank.c,
        luck: ParameterRank.e,
        noblePhantasm: ParameterRank.b,
      ),
      skills: const ['气息遮断', '人格分割', '渗透'],
      noblePhantasm: const NoblePhantasm(
        name: '多重潜影',
        hiddenName: '妄想幻象',
        rank: ParameterRank.b,
        type: NoblePhantasmType.special,
        description: '将多重人格分别具现为独立个体。',
        cost: 40,
        effect: '大幅强化侦察、渗透与多点行动。',
      ),
      masterId: '',
    ),
    ServantCharacter(
      servantId: 'pool_berserker',
      classType: HolyGrailClass.berserker,
      trueName: '贝奥武夫',
      legend: '击败魔物格伦德尔的北方英雄。',
      appearance: '赤裸上身、带着伤痕与巨刃的战士。',
      personality: '直率勇猛，狂化仍保留战士的骄傲与判断。',
      parameters: const ServantParameters(
        strength: ParameterRank.a,
        endurance: ParameterRank.a,
        agility: ParameterRank.b,
        mana: ParameterRank.d,
        luck: ParameterRank.c,
        noblePhantasm: ParameterRank.a,
      ),
      skills: const ['狂化', '战斗续行', '怪力'],
      noblePhantasm: const NoblePhantasm(
        name: '赤手破魔',
        hiddenName: '源流斗争',
        rank: ParameterRank.a,
        type: NoblePhantasmType.antiUnit,
        description: '舍弃武器，以英雄原初的肉搏决出胜负。',
        cost: 45,
        effect: '对单一强敌造成极高近战压制。',
      ),
      masterId: '',
    ),
  ];
}
