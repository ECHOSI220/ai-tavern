import 'package:uuid/uuid.dart';

import '../../models/trpg_faction_models.dart';
import '../../models/trpg_game_models.dart';
import '../../models/trpg_living_npc_models.dart';
import '../../models/trpg_models.dart';
import 'living_npc_service.dart';

enum FactionTickTrigger { time, playerImpact, quest, majorEvent, manual }

class FactionValidationResult {
  const FactionValidationResult(this.accepted, [this.reason = '']);
  final bool accepted;
  final String reason;
}

class FactionRuleValidator {
  const FactionRuleValidator();

  FactionValidationResult validate(
    FactionActionState action,
    FactionSimulationState state,
  ) {
    final faction = state.factions
        .where((item) => item.id == action.factionId)
        .firstOrNull;
    if (faction == null) return const FactionValidationResult(false, '势力不存在');
    if (faction.status != FactionStatus.active) {
      return const FactionValidationResult(false, '势力已无法行动');
    }
    if (!faction.resources.canAfford(action.cost)) {
      return const FactionValidationResult(false, '资源不足');
    }
    if (action.targetFactionId != null &&
        !state.factions.any((item) => item.id == action.targetFactionId)) {
      return const FactionValidationResult(false, '目标势力不存在');
    }
    if (action.targetFactionId == action.factionId) {
      return const FactionValidationResult(false, '不能以自身为敌对目标');
    }
    if (action.type == FactionActionType.attack &&
        action.targetFactionId == null) {
      return const FactionValidationResult(false, '进攻必须指定目标势力');
    }
    if ({
          FactionActionType.moveTroops,
          FactionActionType.attack,
          FactionActionType.build,
        }.contains(action.type) &&
        (action.targetLocationId == null || action.targetLocationId!.isEmpty)) {
      return const FactionValidationResult(false, '行动必须指定地点');
    }
    return const FactionValidationResult(true);
  }
}

class FactionScheduler {
  const FactionScheduler();

  List<FactionState> dueFactions(
    TRPGSession session, {
    required int targetMinute,
    required FactionTickTrigger trigger,
  }) {
    final state = session.factionSimulationState;
    final candidates = state.factions
        .where(
          (item) =>
              item.status == FactionStatus.active &&
              (item.brain.nextDecisionMinute <= targetMinute ||
                  trigger != FactionTickTrigger.time),
        )
        .toList();
    candidates.sort(
      (a, b) => _priority(session, b).compareTo(_priority(session, a)),
    );
    final limit = switch (state.simulationLevel) {
      FactionSimulationLevel.low => 2,
      FactionSimulationLevel.normal => 5,
      FactionSimulationLevel.high => candidates.length,
    };
    return candidates.take(limit).toList();
  }

  int nextDecisionMinute(FactionSimulationLevel level, int now) =>
      now +
      switch (level) {
        FactionSimulationLevel.low => 1440,
        FactionSimulationLevel.normal => 720,
        FactionSimulationLevel.high => 360,
      };

  int _priority(TRPGSession session, FactionState faction) {
    var value = faction.importance;
    final current = session.campaignState.currentLocationId;
    if (faction.territories.any((item) => item.locationId == current)) {
      value += 40;
    }
    if (session.campaignState.activeQuests.any(
      (quest) => quest.contains(faction.id),
    )) {
      value += 25;
    }
    if (faction.stability < 40) value += 20;
    final atWar = session.factionSimulationState.relationships.any(
      (item) =>
          (item.fromFactionId == faction.id ||
              item.toFactionId == faction.id) &&
          item.state == DiplomaticState.war,
    );
    if (atWar) value += 30;
    return value;
  }
}

class FactionBrainEngine {
  const FactionBrainEngine();

  FactionActionState plan(
    FactionState faction,
    TRPGSession session, {
    required int worldMinute,
    required FactionTickTrigger trigger,
  }) {
    final state = session.factionSimulationState;
    final relations =
        state.relationships
            .where((item) => item.fromFactionId == faction.id)
            .toList()
          ..sort((a, b) => a.score.compareTo(b.score));
    final enemy = relations
        .where(
          (item) =>
              item.state == DiplomaticState.war ||
              item.state == DiplomaticState.hostile ||
              item.score <= -50,
        )
        .firstOrNull;
    final goal =
        (faction.brain.goals
                .where((item) => item.status == FactionGoalStatus.active)
                .toList()
              ..sort((a, b) => b.priority.compareTo(a.priority)))
            .firstOrNull;
    final targetId =
        enemy?.toFactionId ??
        goal?.targetFactionId ??
        state.factions.where((item) => item.id != faction.id).firstOrNull?.id;
    final target = state.factions
        .where((item) => item.id == targetId)
        .firstOrNull;
    final targetLocation =
        goal?.targetLocationId ??
        target?.territories.firstOrNull?.locationId ??
        faction.territories.firstOrNull?.locationId ??
        session.campaignState.currentLocationId;

    var type = _goalAction(goal?.type);
    if (faction.stability < 35 || faction.resources.food < 15) {
      type = faction.resources.food < 15
          ? FactionActionType.trade
          : FactionActionType.defend;
    } else if (enemy != null &&
        faction.resources.military >= 25 &&
        (enemy.state == DiplomaticState.war ||
            faction.brain.aggression >= 45)) {
      type = FactionActionType.attack;
    } else if (trigger == FactionTickTrigger.playerImpact && enemy != null) {
      type = faction.resources.military >= 20
          ? FactionActionType.spy
          : FactionActionType.negotiate;
    }
    return FactionActionState(
      id: 'faction-action-${faction.id}-$worldMinute-${type.name}',
      factionId: faction.id,
      type: type,
      targetFactionId: _needsFaction(type) ? targetId : null,
      targetLocationId: _needsLocation(type) ? targetLocation : null,
      cost: _cost(type),
      reason: goal?.description.isNotEmpty == true
          ? goal!.description
          : '势力根据资源、关系和世界变化自主决策',
      createdAtMinute: worldMinute,
    );
  }

  FactionActionType _goalAction(FactionGoalType? type) => switch (type) {
    FactionGoalType.expand => FactionActionType.moveTroops,
    FactionGoalType.defend ||
    FactionGoalType.survive => FactionActionType.defend,
    FactionGoalType.research => FactionActionType.research,
    FactionGoalType.control => FactionActionType.build,
    FactionGoalType.destroy ||
    FactionGoalType.revenge => FactionActionType.attack,
    FactionGoalType.negotiate => FactionActionType.negotiate,
    FactionGoalType.convert => FactionActionType.recruit,
    FactionGoalType.infiltrate => FactionActionType.spy,
    null => FactionActionType.createEvent,
  };

  bool _needsFaction(FactionActionType type) => {
    FactionActionType.attack,
    FactionActionType.negotiate,
    FactionActionType.trade,
    FactionActionType.spy,
    FactionActionType.destroy,
  }.contains(type);

  bool _needsLocation(FactionActionType type) => {
    FactionActionType.attack,
    FactionActionType.moveTroops,
    FactionActionType.build,
  }.contains(type);

  FactionResource _cost(FactionActionType type) => switch (type) {
    FactionActionType.attack => const FactionResource(
      money: 8,
      food: 8,
      technology: 0,
      military: 10,
      influence: 0,
      knowledge: 0,
    ),
    FactionActionType.defend => const FactionResource(
      money: 3,
      food: 3,
      technology: 0,
      military: 2,
      influence: 0,
      knowledge: 0,
    ),
    FactionActionType.research => const FactionResource(
      money: 5,
      food: 0,
      technology: 0,
      military: 0,
      influence: 0,
      knowledge: 4,
    ),
    FactionActionType.spy => const FactionResource(
      money: 4,
      food: 0,
      technology: 0,
      military: 0,
      influence: 3,
      knowledge: 2,
    ),
    FactionActionType.build => const FactionResource(
      money: 10,
      food: 2,
      technology: 2,
      military: 0,
      influence: 0,
      knowledge: 0,
    ),
    _ => const FactionResource(
      money: 1,
      food: 0,
      technology: 0,
      military: 0,
      influence: 0,
      knowledge: 0,
    ),
  };
}

class FactionManager {
  const FactionManager({
    this.scheduler = const FactionScheduler(),
    this.brain = const FactionBrainEngine(),
    this.validator = const FactionRuleValidator(),
  });

  final FactionScheduler scheduler;
  final FactionBrainEngine brain;
  final FactionRuleValidator validator;
  static const _uuid = Uuid();

  TRPGSession ensureInitialized(TRPGSession session) {
    if (session.factionSimulationState.isInitialized) return session;
    final blueprint = session.worldGenerationState.blueprint;
    if (blueprint == null || blueprint.factions.isEmpty) return session;
    final npcs = blueprint.npcs;
    final factions = blueprint.factions.map((definition) {
      final members = npcs
          .where((npc) => npc.factionId == definition.id)
          .map((npc) => npc.id)
          .toList();
      if (definition.leaderNpcId.isNotEmpty &&
          !members.contains(definition.leaderNpcId)) {
        members.insert(0, definition.leaderNpcId);
      }
      return FactionState(
        id: definition.id,
        name: definition.name,
        type: _inferType(definition.tags, definition.name),
        description: definition.goal,
        leaderNpcId: definition.leaderNpcId,
        resources: _seedResources(definition.resources),
        territories: definition.territoryLocationIds
            .map(
              (id) => FactionTerritory(
                factionId: definition.id,
                locationId: id,
                control: TerritoryControl.owned,
              ),
            )
            .toList(),
        memberNpcIds: members,
        memberRoles: {
          for (final member in members)
            member: member == definition.leaderNpcId ? 'leader' : 'member',
        },
        brain: FactionBrain(
          factionId: definition.id,
          goals: [
            FactionGoalState(
              id: 'goal-${definition.id}-primary',
              factionId: definition.id,
              type: _inferGoal(definition.goal),
              description: definition.goal,
              priority: 80,
            ),
          ],
          aggression: _aggression(definition.tags),
          diplomacy: _diplomacy(definition.tags),
        ),
        beliefs: {'primaryGoal': definition.goal},
        personality: definition.tags.contains('激进')
            ? 'aggressive'
            : 'pragmatic',
        strength: _seedResources(definition.resources).military,
        influence: _seedResources(definition.resources).influence,
        technologyLevel: _seedResources(definition.resources).technology,
        importance: definition.tags.contains('major') ? 80 : 50,
        tags: definition.tags,
      );
    }).toList();
    final relationships = <FactionRelationshipState>[];
    for (final relation in blueprint.factionRelationships) {
      relationships.add(
        FactionRelationshipState(
          fromFactionId: relation.fromFactionId,
          toFactionId: relation.toFactionId,
          score: relation.score.clamp(-100, 100),
          trust: relation.score.clamp(0, 100),
          hostility: (-relation.score).clamp(0, 100),
          state: _stateFrom(relation.type, relation.score),
          reason: relation.reason,
          hidden: relation.hidden,
        ),
      );
    }
    for (final source in factions) {
      for (final target in factions.where((item) => item.id != source.id)) {
        if (!relationships.any(
          (item) =>
              item.fromFactionId == source.id && item.toFactionId == target.id,
        )) {
          relationships.add(
            FactionRelationshipState(
              fromFactionId: source.id,
              toFactionId: target.id,
            ),
          );
        }
      }
    }
    final secrets = blueprint.factions
        .where((item) => item.secret.isNotEmpty)
        .map(
          (item) => FactionSecretState(
            id: 'faction-secret-${item.id}',
            factionId: item.id,
            content: item.secret,
          ),
        )
        .toList();
    final initial = FactionSimulationState(
      factions: factions,
      relationships: relationships,
      secrets: secrets,
      worldMinute: session.livingNpcState.worldMinute,
      lastTickMinute: session.livingNpcState.worldMinute,
    );
    return session.copyWith(factionSimulationState: initial);
  }

  TRPGSession tick(
    TRPGSession rawSession, {
    FactionTickTrigger trigger = FactionTickTrigger.time,
    String reason = '世界势力周期更新',
  }) {
    var session = ensureInitialized(rawSession);
    if (!session.factionSimulationState.isInitialized) return session;
    final target = session.livingNpcState.worldMinute;
    var state = session.factionSimulationState.copyWith(worldMinute: target);
    session = session.copyWith(factionSimulationState: state);
    final due = scheduler.dueFactions(
      session,
      targetMinute: target,
      trigger: trigger,
    );
    for (final faction in due) {
      final planned = brain.plan(
        faction,
        session,
        worldMinute: target,
        trigger: trigger,
      );
      session = executeAction(session, planned);
    }
    session = _resolveLeadership(session);
    session = _resolveInternalConflicts(session);
    session = _promoteMembers(session);
    state = session.factionSimulationState.copyWith(
      worldMinute: target,
      lastTickMinute: target,
    );
    final now = DateTime.now();
    return session.copyWith(
      factionSimulationState: state,
      eventLog: [
        ...session.eventLog,
        TRPGEvent(
          id: _uuid.v4(),
          type: TRPGEventType.worldSimulation,
          timestamp: now,
          payload: {
            'source': 'faction_scheduler',
            'trigger': trigger.name,
            'worldMinute': target,
            'factionCount': due.length,
            'reason': reason,
          },
        ),
      ],
      updatedAt: now,
      lastPlayedAt: now,
    );
  }

  TRPGSession executeAction(TRPGSession rawSession, FactionActionState action) {
    var session = ensureInitialized(rawSession);
    final validation = validator.validate(
      action,
      session.factionSimulationState,
    );
    if (!validation.accepted) {
      final rejected = action.copyWith(
        status: FactionActionStatus.rejected,
        reason: validation.reason,
        resolvedAtMinute: session.factionSimulationState.worldMinute,
      );
      return session.copyWith(
        factionSimulationState: session.factionSimulationState.copyWith(
          actions: [...session.factionSimulationState.actions, rejected],
        ),
      );
    }
    final state = session.factionSimulationState;
    final index = state.factions.indexWhere(
      (item) => item.id == action.factionId,
    );
    final current = state.factions[index];
    final spent = current.copyWith(
      resources: current.resources.subtract(action.cost),
      lastUpdatedMinute: state.worldMinute,
      brain: current.brain.copyWith(
        lastDecisionMinute: state.worldMinute,
        nextDecisionMinute: scheduler.nextDecisionMinute(
          state.simulationLevel,
          state.worldMinute,
        ),
        currentActions: [
          ...current.brain.currentActions,
          action.id,
        ].reversed.take(12).toList().reversed.toList(),
      ),
    );
    final factions = [...state.factions]..[index] = spent;
    session = session.copyWith(
      factionSimulationState: state.copyWith(factions: factions),
    );
    final result = <String, Object?>{};
    switch (action.type) {
      case FactionActionType.attack:
        session = _resolveAttack(session, action, result);
      case FactionActionType.trade:
        session = _resolveTrade(session, action, result);
      case FactionActionType.negotiate:
        session = modifyRelationship(
          session,
          fromFactionId: action.factionId,
          toFactionId: action.targetFactionId!,
          delta: 10,
          reason: action.reason,
        );
        result['relationshipDelta'] = 10;
      case FactionActionType.research:
        session = _modifyResources(
          session,
          action.factionId,
          const FactionResource(
            money: 0,
            food: 0,
            technology: 8,
            military: 0,
            influence: 0,
            knowledge: 6,
          ),
        );
        result['technology'] = 8;
      case FactionActionType.defend:
        session = _strengthenTerritory(session, action.factionId, 10);
        result['defense'] = 10;
      case FactionActionType.spy:
        final knowledge = FactionKnowledge(
          id: _uuid.v4(),
          factionId: action.factionId,
          subjectId: action.targetFactionId!,
          content: '${action.factionId}获得了关于${action.targetFactionId}的内部情报',
          visibility: FactionKnowledgeVisibility.gmOnly,
          worldMinute: session.factionSimulationState.worldMinute,
        );
        session = session.copyWith(
          factionSimulationState: session.factionSimulationState.copyWith(
            knowledge: [...session.factionSimulationState.knowledge, knowledge],
          ),
        );
        result['knowledgeId'] = knowledge.id;
      case FactionActionType.moveTroops:
        session = _claimTerritory(
          session,
          action.factionId,
          action.targetLocationId!,
          TerritoryControl.contested,
        );
        result['locationId'] = action.targetLocationId;
      case FactionActionType.recruit:
        session = _modifyResources(
          session,
          action.factionId,
          const FactionResource(
            money: 0,
            food: 0,
            technology: 0,
            military: 3,
            influence: 4,
            knowledge: 0,
          ),
        );
        result['recruits'] = 3;
      case FactionActionType.build:
        session = _strengthenTerritory(session, action.factionId, 15);
        result['structure'] = action.targetLocationId;
      case FactionActionType.destroy:
        if (action.targetFactionId != null) {
          session = _modifyResources(
            session,
            action.targetFactionId!,
            const FactionResource(
              money: -8,
              food: -3,
              technology: 0,
              military: -4,
              influence: -5,
              knowledge: 0,
            ),
          );
        }
        result['sabotage'] = true;
      case FactionActionType.createEvent:
        result['event'] = action.reason;
    }
    final minute = session.factionSimulationState.worldMinute;
    final resolved = action.copyWith(
      status: FactionActionStatus.resolved,
      resolvedAtMinute: minute,
      result: result,
    );
    final history = FactionHistoryEntry(
      id: _uuid.v4(),
      factionId: action.factionId,
      summary: _actionSummary(action, result),
      worldMinute: minute,
      event: action.type.name,
      participants: [
        action.factionId,
        if (action.targetFactionId != null) action.targetFactionId!,
      ],
      result: result.toString(),
      actionId: action.id,
      relatedEntityIds: [
        if (action.targetFactionId != null) action.targetFactionId!,
        if (action.targetLocationId != null) action.targetLocationId!,
      ],
      importance: action.type == FactionActionType.attack ? 9 : 5,
    );
    final now = DateTime.now();
    return session.copyWith(
      factionSimulationState: session.factionSimulationState.copyWith(
        actions: [
          ...session.factionSimulationState.actions,
          resolved,
        ].reversed.take(300).toList().reversed.toList(),
        history: [
          ...session.factionSimulationState.history,
          history,
        ].reversed.take(500).toList().reversed.toList(),
      ),
      eventLog: [
        ...session.eventLog,
        TRPGEvent(
          id: _uuid.v4(),
          type: action.type == FactionActionType.attack
              ? TRPGEventType.factionWar
              : TRPGEventType.factionAction,
          timestamp: now,
          actorId: action.factionId,
          payload: resolved.toJson(),
        ),
      ],
    );
  }

  TRPGSession applyPlayerSupport(
    TRPGSession rawSession, {
    required String factionId,
    required String playerId,
    required String reason,
    int resourceBoost = 8,
  }) {
    var session = ensureInitialized(rawSession);
    session = _modifyResources(
      session,
      factionId,
      FactionResource(
        money: resourceBoost,
        food: resourceBoost ~/ 2,
        technology: 0,
        military: resourceBoost ~/ 2,
        influence: resourceBoost,
        knowledge: 0,
      ),
    );
    final minute = session.factionSimulationState.worldMinute;
    final history = FactionHistoryEntry(
      id: _uuid.v4(),
      factionId: factionId,
      summary: '玩家 $playerId 支持该势力：$reason',
      worldMinute: minute,
      relatedEntityIds: [playerId],
      importance: 7,
    );
    session = session.copyWith(
      factionSimulationState: session.factionSimulationState.copyWith(
        history: [...session.factionSimulationState.history, history],
      ),
    );
    return tick(
      session,
      trigger: FactionTickTrigger.playerImpact,
      reason: reason,
    );
  }

  TRPGSession modifyRelationship(
    TRPGSession rawSession, {
    required String fromFactionId,
    required String toFactionId,
    required int delta,
    required String reason,
    bool reciprocal = true,
  }) {
    var session = ensureInitialized(rawSession);
    var relationships = [...session.factionSimulationState.relationships];
    relationships = _modifyOneRelation(
      relationships,
      fromFactionId,
      toFactionId,
      delta,
      reason,
      session.factionSimulationState.worldMinute,
    );
    if (reciprocal) {
      relationships = _modifyOneRelation(
        relationships,
        toFactionId,
        fromFactionId,
        delta,
        reason,
        session.factionSimulationState.worldMinute,
      );
    }
    final factionStates = session.factionSimulationState.factions.map((
      faction,
    ) {
      final relationMap = {...faction.brain.relationshipMap};
      if (faction.id == fromFactionId) {
        relationMap[toFactionId] = relationships
            .firstWhere(
              (item) =>
                  item.fromFactionId == fromFactionId &&
                  item.toFactionId == toFactionId,
            )
            .score;
      } else if (reciprocal && faction.id == toFactionId) {
        relationMap[fromFactionId] = relationships
            .firstWhere(
              (item) =>
                  item.fromFactionId == toFactionId &&
                  item.toFactionId == fromFactionId,
            )
            .score;
      } else {
        return faction;
      }
      return faction.copyWith(
        brain: faction.brain.copyWith(relationshipMap: relationMap),
      );
    }).toList();
    return session.copyWith(
      factionSimulationState: session.factionSimulationState.copyWith(
        factions: factionStates,
        relationships: relationships,
      ),
      worldState: session.worldState.copyWith(
        factionRelations: {
          ...session.worldState.factionRelations,
          '$fromFactionId->$toFactionId': relationships
              .where(
                (item) =>
                    item.fromFactionId == fromFactionId &&
                    item.toFactionId == toFactionId,
              )
              .first
              .score,
        },
      ),
    );
  }

  TRPGSession declareWar(
    TRPGSession session, {
    required String attackerFactionId,
    required String defenderFactionId,
    String reason = '利益冲突升级为战争',
  }) => modifyRelationship(
    session,
    fromFactionId: attackerFactionId,
    toFactionId: defenderFactionId,
    delta: -200,
    reason: reason,
  );

  TRPGSession revealKnowledge(
    TRPGSession rawSession, {
    required String playerId,
    String? secretId,
    String? knowledgeId,
  }) {
    var session = ensureInitialized(rawSession);
    final secrets = session.factionSimulationState.secrets.map((item) {
      if (item.id != secretId) return item;
      return item.copyWith(
        revealedToPlayerIds: {...item.revealedToPlayerIds, playerId}.toList(),
      );
    }).toList();
    final knowledge = session.factionSimulationState.knowledge.map((item) {
      if (item.id != knowledgeId) return item;
      return FactionKnowledge(
        id: item.id,
        factionId: item.factionId,
        subjectId: item.subjectId,
        content: item.content,
        visibility: FactionKnowledgeVisibility.player,
        ownerPlayerId: playerId,
        confidence: item.confidence,
        worldMinute: item.worldMinute,
      );
    }).toList();
    return session.copyWith(
      factionSimulationState: session.factionSimulationState.copyWith(
        secrets: secrets,
        knowledge: knowledge,
      ),
    );
  }

  String buildRelevantContext(
    TRPGSession rawSession, {
    String? playerId,
    String? locationId,
    bool isGm = true,
  }) {
    final session = ensureInitialized(rawSession);
    final source = isGm
        ? session.factionSimulationState
        : playerId == null
        ? session.factionSimulationState.publicView()
        : session.factionSimulationState.forPlayer(playerId);
    if (source.factions.isEmpty) return '';
    final current = locationId ?? session.campaignState.currentLocationId;
    final relevant = source.factions
        .where((faction) {
          final local = faction.territories.any(
            (item) => item.locationId == current,
          );
          final recent = source.history.reversed
              .take(12)
              .any((item) => item.factionId == faction.id);
          return local || recent || faction.importance >= 70;
        })
        .take(5);
    final lines = <String>['【相关势力状态（程序权威）】'];
    for (final faction in relevant) {
      lines.add(
        '- ${faction.name}：稳定度${faction.stability}，军事${faction.resources.military}，影响力${faction.resources.influence}，目标：${faction.brain.goals.firstOrNull?.description ?? '维持生存'}。',
      );
    }
    final war = source.relationships.where(
      (item) => item.state == DiplomaticState.war,
    );
    for (final relation in war.take(3)) {
      lines.add('- 战争：${relation.fromFactionId} 与 ${relation.toFactionId}。');
    }
    for (final item in source.history.reversed.take(5)) {
      lines.add('- 最近事件：${item.summary}');
    }
    for (final item in source.secrets.take(3)) {
      lines.add('- 已获知秘密：${item.content}');
    }
    lines.add('叙事不得绕过资源验证、伪造战争结果或泄露不可见势力秘密。');
    return lines.join('\n');
  }

  TRPGSession _resolveAttack(
    TRPGSession session,
    FactionActionState action,
    Map<String, Object?> result,
  ) {
    session = declareWar(
      session,
      attackerFactionId: action.factionId,
      defenderFactionId: action.targetFactionId!,
      reason: action.reason,
    );
    var state = session.factionSimulationState;
    final attacker = state.factions.firstWhere(
      (item) => item.id == action.factionId,
    );
    final defender = state.factions.firstWhere(
      (item) => item.id == action.targetFactionId,
    );
    final attackPower =
        attacker.resources.military +
        attacker.resources.technology ~/ 3 +
        attacker.stability ~/ 5;
    final defensePower =
        defender.resources.military +
        defender.resources.technology ~/ 4 +
        defender.stability ~/ 4 +
        (defender.territories
                .where((item) => item.locationId == action.targetLocationId)
                .firstOrNull
                ?.strength ??
            0);
    final battleResult = attackPower > defensePower + 5
        ? BattleResult.attackerVictory
        : defensePower > attackPower + 5
        ? BattleResult.defenderVictory
        : BattleResult.stalemate;
    final attackerLoss = battleResult == BattleResult.attackerVictory ? 5 : 10;
    final defenderLoss = battleResult == BattleResult.defenderVictory ? 5 : 10;
    session = _modifyResources(
      session,
      attacker.id,
      FactionResource(
        money: 0,
        food: 0,
        technology: 0,
        military: -attackerLoss,
        influence: 0,
        knowledge: 0,
      ),
    );
    session = _modifyResources(
      session,
      defender.id,
      FactionResource(
        money: 0,
        food: -3,
        technology: 0,
        military: -defenderLoss,
        influence: battleResult == BattleResult.attackerVictory ? -8 : 0,
        knowledge: 0,
      ),
    );
    if (battleResult == BattleResult.attackerVictory) {
      session = _transferTerritory(
        session,
        fromFactionId: defender.id,
        toFactionId: attacker.id,
        locationId: action.targetLocationId!,
      );
    } else if (battleResult == BattleResult.stalemate) {
      session = _claimTerritory(
        session,
        defender.id,
        action.targetLocationId!,
        TerritoryControl.contested,
      );
    }
    state = session.factionSimulationState;
    final battle = BattleEvent(
      id: _uuid.v4(),
      attackerFactionId: attacker.id,
      defenderFactionId: defender.id,
      locationId: action.targetLocationId!,
      result: battleResult,
      powerDifference: attackPower - defensePower,
      attackerLoss: attackerLoss,
      defenderLoss: defenderLoss,
      casualties: {attacker.id: attackerLoss, defender.id: defenderLoss},
      worldMinute: state.worldMinute,
    );
    final questId = 'faction-conflict-${battle.id}';
    final quest = QuestState(
      questId: questId,
      title: '介入${attacker.name}与${defender.name}的冲突',
      description: '两大势力在${action.targetLocationId}爆发冲突，玩家可以选择介入、调查或保持中立。',
      status: QuestStatus.discovered,
      objectives: [
        QuestObjective(id: '$questId-objective', description: '了解冲突并决定立场'),
      ],
      discoveredAt: DateTime.now(),
    );
    result
      ..['battleId'] = battle.id
      ..['battleResult'] = battleResult.name
      ..['questId'] = questId;
    return session.copyWith(
      factionSimulationState: state.copyWith(
        battles: [...state.battles, battle],
      ),
      campaignState: session.campaignState.copyWith(
        quests:
            session.campaignState.quests.any((item) => item.questId == questId)
            ? session.campaignState.quests
            : [...session.campaignState.quests, quest],
      ),
    );
  }

  TRPGSession _resolveTrade(
    TRPGSession session,
    FactionActionState action,
    Map<String, Object?> result,
  ) {
    session = _modifyResources(
      session,
      action.factionId,
      const FactionResource(
        money: 8,
        food: 10,
        technology: 0,
        military: 0,
        influence: 2,
        knowledge: 0,
      ),
    );
    if (action.targetFactionId != null) {
      session = _modifyResources(
        session,
        action.targetFactionId!,
        const FactionResource(
          money: 5,
          food: 3,
          technology: 0,
          military: 0,
          influence: 1,
          knowledge: 0,
        ),
      );
      session = modifyRelationship(
        session,
        fromFactionId: action.factionId,
        toFactionId: action.targetFactionId!,
        delta: 6,
        reason: '贸易往来',
      );
    }
    result['tradeCompleted'] = true;
    return session;
  }

  TRPGSession _resolveLeadership(TRPGSession session) {
    var state = session.factionSimulationState;
    final factions = [...state.factions];
    final history = [...state.history];
    var changed = false;
    for (var index = 0; index < factions.length; index++) {
      final faction = factions[index];
      final leaderBrain = session.livingNpcState.brains[faction.leaderNpcId];
      if (faction.leaderNpcId.isEmpty ||
          leaderBrain?.status != NPCLifeStatus.dead) {
        continue;
      }
      final successor = faction.memberNpcIds.firstWhere(
        (id) =>
            id != faction.leaderNpcId &&
            session.livingNpcState.brains[id]?.status != NPCLifeStatus.dead,
        orElse: () => '',
      );
      if (successor.isEmpty) {
        factions[index] = faction.copyWith(
          status: FactionStatus.collapsed,
          stability: 0,
          lastUpdatedMinute: state.worldMinute,
        );
      } else {
        final roles = {...faction.memberRoles};
        roles[faction.leaderNpcId] = 'former_leader';
        roles[successor] = 'leader';
        factions[index] = faction.copyWith(
          leaderNpcId: successor,
          memberRoles: roles,
          stability: (faction.stability - 20).clamp(0, 100),
          lastUpdatedMinute: state.worldMinute,
        );
      }
      history.add(
        FactionHistoryEntry(
          id: _uuid.v4(),
          factionId: faction.id,
          summary: successor.isEmpty
              ? '${faction.name}因领袖死亡且无人继承而崩溃'
              : '${faction.name}领袖死亡，$successor 接任',
          worldMinute: state.worldMinute,
          relatedEntityIds: [
            faction.leaderNpcId,
            if (successor.isNotEmpty) successor,
          ],
          importance: 10,
        ),
      );
      changed = true;
    }
    if (!changed) return session;
    return session.copyWith(
      factionSimulationState: state.copyWith(
        factions: factions,
        history: history,
      ),
      eventLog: [
        ...session.eventLog,
        TRPGEvent(
          id: _uuid.v4(),
          type: TRPGEventType.factionSuccession,
          timestamp: DateTime.now(),
          payload: const {'source': 'faction_leadership'},
        ),
      ],
    );
  }

  TRPGSession _resolveInternalConflicts(TRPGSession session) {
    final state = session.factionSimulationState;
    final conflicts = [...state.internalConflicts];
    final quests = [...session.campaignState.quests];
    var changed = false;
    for (final faction in state.factions) {
      if (faction.stability >= 35 ||
          conflicts.any(
            (item) =>
                item.factionId == faction.id &&
                item.status == InternalConflictStatus.active,
          )) {
        continue;
      }
      final conflict = InternalConflict(
        id: _uuid.v4(),
        factionId: faction.id,
        title: '${faction.name}内部权力危机',
        description: '稳定度过低，成员开始争夺资源与领导权。',
        severity: (100 - faction.stability).clamp(1, 100),
        startedAtMinute: state.worldMinute,
      );
      conflicts.add(conflict);
      quests.add(
        QuestState(
          questId: 'faction-internal-${conflict.id}',
          title: '调查${faction.name}的内部危机',
          description: conflict.description,
          discoveredAt: DateTime.now(),
        ),
      );
      changed = true;
    }
    if (!changed) return session;
    return session.copyWith(
      factionSimulationState: state.copyWith(internalConflicts: conflicts),
      campaignState: session.campaignState.copyWith(quests: quests),
      eventLog: [
        ...session.eventLog,
        TRPGEvent(
          id: _uuid.v4(),
          type: TRPGEventType.factionInternalConflict,
          timestamp: DateTime.now(),
          payload: {
            'newConflictCount':
                conflicts.length - state.internalConflicts.length,
          },
        ),
      ],
    );
  }

  TRPGSession _promoteMembers(TRPGSession session) {
    if (session.factionSimulationState.worldMinute == 0) return session;
    final factions = session.factionSimulationState.factions.map((faction) {
      final candidate = faction.memberNpcIds
          .where((id) => faction.memberRoles[id] == 'member')
          .firstOrNull;
      if (candidate == null || faction.stability < 50) return faction;
      final roles = {...faction.memberRoles, candidate: 'officer'};
      return faction.copyWith(memberRoles: roles);
    }).toList();
    return session.copyWith(
      factionSimulationState: session.factionSimulationState.copyWith(
        factions: factions,
      ),
    );
  }

  TRPGSession _modifyResources(
    TRPGSession session,
    String factionId,
    FactionResource delta,
  ) {
    final state = session.factionSimulationState;
    final factions = state.factions.map((item) {
      if (item.id != factionId) return item;
      return item.copyWith(
        resources: item.resources.add(delta),
        strength: item.resources.add(delta).military,
        influence: item.resources.add(delta).influence,
        technologyLevel: item.resources.add(delta).technology,
        lastUpdatedMinute: state.worldMinute,
      );
    }).toList();
    return session.copyWith(
      factionSimulationState: state.copyWith(factions: factions),
    );
  }

  TRPGSession _strengthenTerritory(
    TRPGSession session,
    String factionId,
    int delta,
  ) {
    final state = session.factionSimulationState;
    final factions = state.factions.map((faction) {
      if (faction.id != factionId) return faction;
      return faction.copyWith(
        territories: faction.territories
            .map(
              (item) => item.copyWith(
                strength: (item.strength + delta).clamp(0, 100),
              ),
            )
            .toList(),
      );
    }).toList();
    return session.copyWith(
      factionSimulationState: state.copyWith(factions: factions),
    );
  }

  TRPGSession _claimTerritory(
    TRPGSession session,
    String factionId,
    String locationId,
    TerritoryControl control,
  ) {
    final state = session.factionSimulationState;
    final factions = state.factions.map((faction) {
      if (faction.id != factionId) return faction;
      final territories = [...faction.territories];
      final index = territories.indexWhere(
        (item) => item.locationId == locationId,
      );
      final territory = FactionTerritory(
        factionId: factionId,
        locationId: locationId,
        control: control,
        strength: control == TerritoryControl.contested ? 30 : 50,
        sinceMinute: state.worldMinute,
      );
      if (index < 0) {
        territories.add(territory);
      } else {
        territories[index] = territory;
      }
      return faction.copyWith(territories: territories);
    }).toList();
    return session.copyWith(
      factionSimulationState: state.copyWith(factions: factions),
    );
  }

  TRPGSession _transferTerritory(
    TRPGSession session, {
    required String fromFactionId,
    required String toFactionId,
    required String locationId,
  }) {
    final state = session.factionSimulationState;
    final factions = state.factions.map((faction) {
      if (faction.id == fromFactionId) {
        return faction.copyWith(
          territories: faction.territories
              .where((item) => item.locationId != locationId)
              .toList(),
          stability: (faction.stability - 10).clamp(0, 100),
        );
      }
      if (faction.id == toFactionId) {
        final territories =
            faction.territories
                .where((item) => item.locationId != locationId)
                .toList()
              ..add(
                FactionTerritory(
                  factionId: toFactionId,
                  locationId: locationId,
                  control: TerritoryControl.occupied,
                  strength: 30,
                  sinceMinute: state.worldMinute,
                ),
              );
        return faction.copyWith(
          territories: territories,
          stability: (faction.stability + 5).clamp(0, 100),
        );
      }
      return faction;
    }).toList();
    return session.copyWith(
      factionSimulationState: state.copyWith(factions: factions),
      eventLog: [
        ...session.eventLog,
        TRPGEvent(
          id: _uuid.v4(),
          type: TRPGEventType.factionTerritory,
          timestamp: DateTime.now(),
          payload: {
            'locationId': locationId,
            'fromFactionId': fromFactionId,
            'toFactionId': toFactionId,
          },
        ),
      ],
    );
  }

  List<FactionRelationshipState> _modifyOneRelation(
    List<FactionRelationshipState> input,
    String from,
    String to,
    int delta,
    String reason,
    int minute,
  ) {
    final values = [...input];
    final index = values.indexWhere(
      (item) => item.fromFactionId == from && item.toFactionId == to,
    );
    final base = index < 0
        ? FactionRelationshipState(fromFactionId: from, toFactionId: to)
        : values[index];
    final score = (base.score + delta).clamp(-100, 100);
    final updated = base.copyWith(
      score: score,
      trust: (base.trust + delta).clamp(0, 100),
      hostility: (base.hostility - delta).clamp(0, 100),
      state: _stateFrom('', score),
      reason: reason,
      lastChangedMinute: minute,
    );
    if (index < 0) {
      values.add(updated);
    } else {
      values[index] = updated;
    }
    return values;
  }

  String _actionSummary(
    FactionActionState action,
    Map<String, Object?> result,
  ) =>
      '${action.factionId}执行${action.type.name}：${action.reason}'
      '${result['battleResult'] == null ? '' : '，结果${result['battleResult']}'}';

  static FactionType _inferType(List<String> tags, String name) {
    final text = '${tags.join(' ')} $name'.toLowerCase();
    if (text.contains('王') || text.contains('国')) return FactionType.kingdom;
    if (text.contains('军')) return FactionType.military;
    if (text.contains('教')) return FactionType.religion;
    if (text.contains('公司') || text.contains('corpor')) {
      return FactionType.corporation;
    }
    if (text.contains('帮') || text.contains('犯罪')) return FactionType.criminal;
    if (text.contains('反抗') || text.contains('叛')) return FactionType.rebellion;
    if (text.contains('部落')) return FactionType.tribe;
    if (text.contains('ai')) return FactionType.aiEntity;
    return FactionType.guild;
  }

  static FactionGoalType _inferGoal(String goal) {
    if (goal.contains('扩') || goal.contains('占领')) {
      return FactionGoalType.expand;
    }
    if (goal.contains('研究')) return FactionGoalType.research;
    if (goal.contains('毁') || goal.contains('消灭')) {
      return FactionGoalType.destroy;
    }
    if (goal.contains('谈') || goal.contains('和平')) {
      return FactionGoalType.negotiate;
    }
    if (goal.contains('渗透')) return FactionGoalType.infiltrate;
    if (goal.contains('复仇')) return FactionGoalType.revenge;
    if (goal.contains('守') || goal.contains('保护')) {
      return FactionGoalType.defend;
    }
    return FactionGoalType.survive;
  }

  static FactionResource _seedResources(List<String> resources) {
    var value = const FactionResource();
    for (final resource in resources) {
      final lower = resource.toLowerCase();
      if (lower.contains('钱') || lower.contains('金') || lower.contains('商')) {
        value = value.copyWith(money: value.money + 20);
      } else if (lower.contains('粮') || lower.contains('食')) {
        value = value.copyWith(food: value.food + 20);
      } else if (lower.contains('军') || lower.contains('武')) {
        value = value.copyWith(military: value.military + 20);
      } else if (lower.contains('技') || lower.contains('科研')) {
        value = value.copyWith(technology: value.technology + 20);
      } else if (lower.contains('情报') || lower.contains('知识')) {
        value = value.copyWith(knowledge: value.knowledge + 20);
      } else {
        value = value.copyWith(influence: value.influence + 10);
      }
    }
    return value;
  }

  static int _aggression(List<String> tags) =>
      tags.any((item) => item.contains('激进') || item.contains('军')) ? 75 : 40;
  static int _diplomacy(List<String> tags) =>
      tags.any((item) => item.contains('商') || item.contains('外交')) ? 75 : 50;

  static DiplomaticState _stateFrom(String type, int score) {
    final lower = type.toLowerCase();
    if (lower.contains('war') || lower.contains('战争')) {
      return DiplomaticState.war;
    }
    if (lower.contains('ally') || lower.contains('盟')) {
      return DiplomaticState.allied;
    }
    if (lower.contains('truce') || lower.contains('停战')) {
      return DiplomaticState.truce;
    }
    if (score <= -60) return DiplomaticState.war;
    if (score <= -30) return DiplomaticState.hostile;
    if (score < 0) return DiplomaticState.tense;
    if (score >= 60) return DiplomaticState.allied;
    if (score >= 25) return DiplomaticState.friendly;
    return DiplomaticState.neutral;
  }
}

class WorldSimulationService {
  const WorldSimulationService({
    this.livingNpcService = const LivingNPCService(),
    this.factionManager = const FactionManager(),
  });
  final LivingNPCService livingNpcService;
  final FactionManager factionManager;

  TRPGSession advanceTime(
    TRPGSession session, {
    required int minutes,
    String reason = '世界时间推进',
    FactionTickTrigger factionTrigger = FactionTickTrigger.time,
  }) {
    var next = livingNpcService.advanceTime(
      session,
      minutes: minutes,
      reason: reason,
    );
    next = factionManager.tick(next, trigger: factionTrigger, reason: reason);
    return next;
  }
}
