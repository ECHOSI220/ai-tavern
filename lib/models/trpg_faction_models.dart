enum FactionType {
  kingdom,
  guild,
  corporation,
  military,
  religion,
  criminal,
  rebellion,
  aiEntity,
  tribe,
}

enum FactionStatus { active, weakened, collapsed, dissolved }

enum FactionGoalType {
  expand,
  defend,
  research,
  control,
  destroy,
  survive,
  negotiate,
  convert,
  infiltrate,
  revenge,
}

enum FactionGoalStatus { active, completed, failed, abandoned }

enum FactionActionType {
  moveTroops,
  negotiate,
  trade,
  research,
  attack,
  defend,
  spy,
  recruit,
  build,
  destroy,
  createEvent,
}

enum FactionActionStatus { planned, validated, resolved, rejected }

enum TerritoryControl { owned, controlled, contested, unknown, occupied, lost }

enum DiplomaticState { allied, friendly, neutral, tense, hostile, war, truce }

enum FactionSimulationLevel { low, normal, high }

enum FactionKnowledgeVisibility { public, player, faction, gmOnly }

enum InternalConflictStatus { active, resolved, escalated }

enum BattleResult { attackerVictory, defenderVictory, stalemate }

T _enumValue<T extends Enum>(List<T> values, Object? raw, T fallback) {
  for (final value in values) {
    if (value.name == raw) return value;
  }
  return fallback;
}

List<String> _strings(Object? value) => value is List
    ? value.map((item) => item.toString()).toList(growable: false)
    : const [];

Map<String, Object?> _map(Object? value) =>
    value is Map ? value.cast<String, Object?>() : const {};

class FactionResource {
  const FactionResource({
    this.money = 50,
    this.food = 50,
    this.technology = 30,
    this.military = 40,
    this.influence = 40,
    this.knowledge = 30,
  });

  final int money, food, technology, military, influence, knowledge;

  FactionResource copyWith({
    int? money,
    int? food,
    int? technology,
    int? military,
    int? influence,
    int? knowledge,
  }) => FactionResource(
    money: money ?? this.money,
    food: food ?? this.food,
    technology: technology ?? this.technology,
    military: military ?? this.military,
    influence: influence ?? this.influence,
    knowledge: knowledge ?? this.knowledge,
  );

  FactionResource add(FactionResource value) => FactionResource(
    money: (money + value.money).clamp(0, 999999),
    food: (food + value.food).clamp(0, 999999),
    technology: (technology + value.technology).clamp(0, 999999),
    military: (military + value.military).clamp(0, 999999),
    influence: (influence + value.influence).clamp(0, 999999),
    knowledge: (knowledge + value.knowledge).clamp(0, 999999),
  );

  FactionResource subtract(FactionResource value) => FactionResource(
    money: (money - value.money).clamp(0, 999999),
    food: (food - value.food).clamp(0, 999999),
    technology: (technology - value.technology).clamp(0, 999999),
    military: (military - value.military).clamp(0, 999999),
    influence: (influence - value.influence).clamp(0, 999999),
    knowledge: (knowledge - value.knowledge).clamp(0, 999999),
  );

  bool canAfford(FactionResource cost) =>
      money >= cost.money &&
      food >= cost.food &&
      technology >= cost.technology &&
      military >= cost.military &&
      influence >= cost.influence &&
      knowledge >= cost.knowledge;

  int get total => money + food + technology + military + influence + knowledge;

  Map<String, Object?> toJson() => {
    'money': money,
    'food': food,
    'technology': technology,
    'military': military,
    'influence': influence,
    'knowledge': knowledge,
  };

  factory FactionResource.fromJson(Map<String, Object?> json) =>
      FactionResource(
        money: (json['money'] as num?)?.toInt() ?? 50,
        food: (json['food'] as num?)?.toInt() ?? 50,
        technology: (json['technology'] as num?)?.toInt() ?? 30,
        military: (json['military'] as num?)?.toInt() ?? 40,
        influence: (json['influence'] as num?)?.toInt() ?? 40,
        knowledge: (json['knowledge'] as num?)?.toInt() ?? 30,
      );
}

class FactionTerritory {
  const FactionTerritory({
    required this.locationId,
    this.factionId = '',
    this.control = TerritoryControl.controlled,
    this.strength = 50,
    this.controlLevel = 50,
    this.stability = 70,
    this.population = 0,
    this.sinceMinute = 0,
  });
  final String factionId, locationId;
  final TerritoryControl control;
  final int strength, controlLevel, stability, population, sinceMinute;

  FactionTerritory copyWith({
    TerritoryControl? control,
    int? strength,
    int? controlLevel,
    int? stability,
    int? population,
    int? sinceMinute,
  }) => FactionTerritory(
    factionId: factionId,
    locationId: locationId,
    control: control ?? this.control,
    strength: strength ?? this.strength,
    controlLevel: controlLevel ?? this.controlLevel,
    stability: stability ?? this.stability,
    population: population ?? this.population,
    sinceMinute: sinceMinute ?? this.sinceMinute,
  );

  Map<String, Object?> toJson() => {
    'factionId': factionId,
    'locationId': locationId,
    'control': control.name,
    'strength': strength,
    'controlLevel': controlLevel,
    'stability': stability,
    'population': population,
    'sinceMinute': sinceMinute,
  };

  factory FactionTerritory.fromJson(Map<String, Object?> json) =>
      FactionTerritory(
        factionId: json['factionId'] as String? ?? '',
        locationId: json['locationId'] as String? ?? '',
        control: _enumValue(
          TerritoryControl.values,
          json['control'],
          TerritoryControl.controlled,
        ),
        strength: (json['strength'] as num?)?.toInt() ?? 50,
        controlLevel: (json['controlLevel'] as num?)?.toInt() ?? 50,
        stability: (json['stability'] as num?)?.toInt() ?? 70,
        population: (json['population'] as num?)?.toInt() ?? 0,
        sinceMinute: (json['sinceMinute'] as num?)?.toInt() ?? 0,
      );
}

class FactionRelationshipState {
  const FactionRelationshipState({
    required this.fromFactionId,
    required this.toFactionId,
    this.score = 0,
    this.trust = 0,
    this.hostility = 0,
    this.trade = 0,
    this.fear = 0,
    this.state = DiplomaticState.neutral,
    this.reason = '',
    this.hidden = false,
    this.lastChangedMinute = 0,
  });
  final String fromFactionId, toFactionId, reason;
  final int score, trust, hostility, trade, fear, lastChangedMinute;
  final DiplomaticState state;
  final bool hidden;

  String get key => '$fromFactionId->$toFactionId';

  FactionRelationshipState copyWith({
    int? score,
    int? trust,
    int? hostility,
    int? trade,
    int? fear,
    DiplomaticState? state,
    String? reason,
    bool? hidden,
    int? lastChangedMinute,
  }) => FactionRelationshipState(
    fromFactionId: fromFactionId,
    toFactionId: toFactionId,
    score: score ?? this.score,
    trust: trust ?? this.trust,
    hostility: hostility ?? this.hostility,
    trade: trade ?? this.trade,
    fear: fear ?? this.fear,
    state: state ?? this.state,
    reason: reason ?? this.reason,
    hidden: hidden ?? this.hidden,
    lastChangedMinute: lastChangedMinute ?? this.lastChangedMinute,
  );

  Map<String, Object?> toJson() => {
    'fromFactionId': fromFactionId,
    'toFactionId': toFactionId,
    'score': score,
    'trust': trust,
    'hostility': hostility,
    'trade': trade,
    'fear': fear,
    'state': state.name,
    'reason': reason,
    'hidden': hidden,
    'lastChangedMinute': lastChangedMinute,
  };

  factory FactionRelationshipState.fromJson(Map<String, Object?> json) =>
      FactionRelationshipState(
        fromFactionId: json['fromFactionId'] as String? ?? '',
        toFactionId: json['toFactionId'] as String? ?? '',
        score: (json['score'] as num?)?.toInt() ?? 0,
        trust: (json['trust'] as num?)?.toInt() ?? 0,
        hostility: (json['hostility'] as num?)?.toInt() ?? 0,
        trade: (json['trade'] as num?)?.toInt() ?? 0,
        fear: (json['fear'] as num?)?.toInt() ?? 0,
        state: _enumValue(
          DiplomaticState.values,
          json['state'],
          DiplomaticState.neutral,
        ),
        reason: json['reason'] as String? ?? '',
        hidden: json['hidden'] as bool? ?? false,
        lastChangedMinute: (json['lastChangedMinute'] as num?)?.toInt() ?? 0,
      );
}

class FactionGoalState {
  const FactionGoalState({
    required this.id,
    required this.type,
    required this.description,
    this.factionId = '',
    this.priority = 50,
    this.targetFactionId,
    this.targetLocationId,
    this.status = FactionGoalStatus.active,
    this.progress = 0,
    this.deadlineMinute,
  });
  final String id, factionId, description;
  final FactionGoalType type;
  final int priority, progress;
  final String? targetFactionId, targetLocationId;
  final FactionGoalStatus status;
  final int? deadlineMinute;

  FactionGoalState copyWith({FactionGoalStatus? status, int? progress}) =>
      FactionGoalState(
        id: id,
        factionId: factionId,
        type: type,
        description: description,
        priority: priority,
        targetFactionId: targetFactionId,
        targetLocationId: targetLocationId,
        status: status ?? this.status,
        progress: progress ?? this.progress,
        deadlineMinute: deadlineMinute,
      );

  Map<String, Object?> toJson() => {
    'id': id,
    'factionId': factionId,
    'type': type.name,
    'description': description,
    'priority': priority,
    'targetFactionId': targetFactionId,
    'targetLocationId': targetLocationId,
    'status': status.name,
    'progress': progress,
    'deadlineMinute': deadlineMinute,
  };

  factory FactionGoalState.fromJson(Map<String, Object?> json) =>
      FactionGoalState(
        id: json['id'] as String? ?? '',
        factionId: json['factionId'] as String? ?? '',
        type: _enumValue(
          FactionGoalType.values,
          json['type'],
          FactionGoalType.survive,
        ),
        description: json['description'] as String? ?? '',
        priority: (json['priority'] as num?)?.toInt() ?? 50,
        targetFactionId: json['targetFactionId'] as String?,
        targetLocationId: json['targetLocationId'] as String?,
        status: _enumValue(
          FactionGoalStatus.values,
          json['status'],
          FactionGoalStatus.active,
        ),
        progress: (json['progress'] as num?)?.toInt() ?? 0,
        deadlineMinute: (json['deadlineMinute'] as num?)?.toInt(),
      );
}

class FactionPlan {
  const FactionPlan({
    required this.id,
    required this.goalId,
    required this.description,
    this.actionIds = const [],
    this.createdAtMinute = 0,
  });
  final String id, goalId, description;
  final List<String> actionIds;
  final int createdAtMinute;

  Map<String, Object?> toJson() => {
    'id': id,
    'goalId': goalId,
    'description': description,
    'actionIds': actionIds,
    'createdAtMinute': createdAtMinute,
  };

  factory FactionPlan.fromJson(Map<String, Object?> json) => FactionPlan(
    id: json['id'] as String? ?? '',
    goalId: json['goalId'] as String? ?? '',
    description: json['description'] as String? ?? '',
    actionIds: _strings(json['actionIds']),
    createdAtMinute: (json['createdAtMinute'] as num?)?.toInt() ?? 0,
  );
}

class FactionActionState {
  const FactionActionState({
    required this.id,
    required this.factionId,
    required this.type,
    this.targetFactionId,
    this.targetLocationId,
    this.target,
    this.cost = const FactionResource(
      money: 0,
      food: 0,
      technology: 0,
      military: 0,
      influence: 0,
      knowledge: 0,
    ),
    this.status = FactionActionStatus.planned,
    this.reason = '',
    this.createdAtMinute = 0,
    this.durationMinutes = 0,
    this.resolvedAtMinute,
    this.result = const {},
  });
  final String id, factionId, reason;
  final FactionActionType type;
  final String? targetFactionId, targetLocationId, target;
  final FactionResource cost;
  final FactionActionStatus status;
  final int createdAtMinute, durationMinutes;
  final int? resolvedAtMinute;
  final Map<String, Object?> result;

  FactionActionState copyWith({
    FactionActionStatus? status,
    int? resolvedAtMinute,
    Map<String, Object?>? result,
    String? reason,
  }) => FactionActionState(
    id: id,
    factionId: factionId,
    type: type,
    targetFactionId: targetFactionId,
    targetLocationId: targetLocationId,
    target: target,
    cost: cost,
    status: status ?? this.status,
    reason: reason ?? this.reason,
    createdAtMinute: createdAtMinute,
    durationMinutes: durationMinutes,
    resolvedAtMinute: resolvedAtMinute ?? this.resolvedAtMinute,
    result: result ?? this.result,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'factionId': factionId,
    'type': type.name,
    'targetFactionId': targetFactionId,
    'targetLocationId': targetLocationId,
    'target': target,
    'cost': cost.toJson(),
    'status': status.name,
    'reason': reason,
    'createdAtMinute': createdAtMinute,
    'durationMinutes': durationMinutes,
    'resolvedAtMinute': resolvedAtMinute,
    'result': result,
  };

  factory FactionActionState.fromJson(Map<String, Object?> json) =>
      FactionActionState(
        id: json['id'] as String? ?? '',
        factionId: json['factionId'] as String? ?? '',
        type: _enumValue(
          FactionActionType.values,
          json['type'],
          FactionActionType.createEvent,
        ),
        targetFactionId: json['targetFactionId'] as String?,
        targetLocationId: json['targetLocationId'] as String?,
        target: json['target'] as String?,
        cost: FactionResource.fromJson(_map(json['cost'])),
        status: _enumValue(
          FactionActionStatus.values,
          json['status'],
          FactionActionStatus.planned,
        ),
        reason: json['reason'] as String? ?? '',
        createdAtMinute: (json['createdAtMinute'] as num?)?.toInt() ?? 0,
        durationMinutes: (json['durationMinutes'] as num?)?.toInt() ?? 0,
        resolvedAtMinute: (json['resolvedAtMinute'] as num?)?.toInt(),
        result: _map(json['result']),
      );
}

class FactionBrain {
  const FactionBrain({
    this.factionId = '',
    this.goals = const [],
    this.plans = const [],
    this.strategy = 'balanced',
    this.beliefs = const {},
    this.fear = 20,
    this.needs = const {},
    this.relationshipMap = const {},
    this.currentActions = const [],
    this.aggression = 40,
    this.caution = 50,
    this.diplomacy = 50,
    this.lastDecisionMinute = 0,
    this.nextDecisionMinute = 0,
  });
  final String factionId, strategy;
  final List<FactionGoalState> goals;
  final List<FactionPlan> plans;
  final Map<String, Object?> beliefs;
  final Map<String, int> needs, relationshipMap;
  final List<String> currentActions;
  final int fear, aggression, caution, diplomacy, lastDecisionMinute;
  final int nextDecisionMinute;

  FactionBrain copyWith({
    List<FactionGoalState>? goals,
    List<FactionPlan>? plans,
    String? strategy,
    Map<String, Object?>? beliefs,
    int? fear,
    Map<String, int>? needs,
    Map<String, int>? relationshipMap,
    List<String>? currentActions,
    int? lastDecisionMinute,
    int? nextDecisionMinute,
  }) => FactionBrain(
    factionId: factionId,
    goals: goals ?? this.goals,
    plans: plans ?? this.plans,
    strategy: strategy ?? this.strategy,
    beliefs: beliefs ?? this.beliefs,
    fear: fear ?? this.fear,
    needs: needs ?? this.needs,
    relationshipMap: relationshipMap ?? this.relationshipMap,
    currentActions: currentActions ?? this.currentActions,
    aggression: aggression,
    caution: caution,
    diplomacy: diplomacy,
    lastDecisionMinute: lastDecisionMinute ?? this.lastDecisionMinute,
    nextDecisionMinute: nextDecisionMinute ?? this.nextDecisionMinute,
  );

  Map<String, Object?> toJson() => {
    'factionId': factionId,
    'goals': goals.map((item) => item.toJson()).toList(),
    'plans': plans.map((item) => item.toJson()).toList(),
    'strategy': strategy,
    'beliefs': beliefs,
    'fear': fear,
    'needs': needs,
    'relationshipMap': relationshipMap,
    'currentActions': currentActions,
    'aggression': aggression,
    'caution': caution,
    'diplomacy': diplomacy,
    'lastDecisionMinute': lastDecisionMinute,
    'nextDecisionMinute': nextDecisionMinute,
  };

  factory FactionBrain.fromJson(Map<String, Object?> json) => FactionBrain(
    factionId: json['factionId'] as String? ?? '',
    goals: (json['goals'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => FactionGoalState.fromJson(item.cast<String, Object?>()))
        .toList(),
    plans: (json['plans'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => FactionPlan.fromJson(item.cast<String, Object?>()))
        .toList(),
    strategy: json['strategy'] as String? ?? 'balanced',
    beliefs: _map(json['beliefs']),
    fear: (json['fear'] as num?)?.toInt() ?? 20,
    needs: json['needs'] is Map
        ? (json['needs'] as Map).map(
            (key, value) => MapEntry(key.toString(), (value as num).toInt()),
          )
        : const {},
    relationshipMap: json['relationshipMap'] is Map
        ? (json['relationshipMap'] as Map).map(
            (key, value) => MapEntry(key.toString(), (value as num).toInt()),
          )
        : const {},
    currentActions: _strings(json['currentActions']),
    aggression: (json['aggression'] as num?)?.toInt() ?? 40,
    caution: (json['caution'] as num?)?.toInt() ?? 50,
    diplomacy: (json['diplomacy'] as num?)?.toInt() ?? 50,
    lastDecisionMinute: (json['lastDecisionMinute'] as num?)?.toInt() ?? 0,
    nextDecisionMinute: (json['nextDecisionMinute'] as num?)?.toInt() ?? 0,
  );
}

class FactionState {
  const FactionState({
    required this.id,
    required this.name,
    this.type = FactionType.guild,
    this.description = '',
    this.leaderNpcId = '',
    this.resources = const FactionResource(),
    this.territories = const [],
    this.memberNpcIds = const [],
    this.memberRoles = const {},
    this.brain = const FactionBrain(),
    this.beliefs = const {},
    this.personality = 'pragmatic',
    this.strength = 40,
    this.influence = 40,
    this.technologyLevel = 30,
    this.morality = 0,
    this.stability = 70,
    this.importance = 50,
    this.status = FactionStatus.active,
    this.tags = const [],
    this.lastUpdatedMinute = 0,
  });
  final String id, name, description, leaderNpcId, personality;
  final FactionType type;
  final FactionResource resources;
  final List<FactionTerritory> territories;
  final List<String> memberNpcIds, tags;
  final Map<String, String> memberRoles;
  final FactionBrain brain;
  final Map<String, Object?> beliefs;
  final int strength,
      influence,
      technologyLevel,
      morality,
      stability,
      importance,
      lastUpdatedMinute;
  final FactionStatus status;

  FactionState copyWith({
    String? leaderNpcId,
    FactionResource? resources,
    List<FactionTerritory>? territories,
    List<String>? memberNpcIds,
    Map<String, String>? memberRoles,
    FactionBrain? brain,
    Map<String, Object?>? beliefs,
    String? personality,
    int? strength,
    int? influence,
    int? technologyLevel,
    int? morality,
    int? stability,
    int? importance,
    FactionStatus? status,
    int? lastUpdatedMinute,
  }) => FactionState(
    id: id,
    name: name,
    type: type,
    description: description,
    leaderNpcId: leaderNpcId ?? this.leaderNpcId,
    resources: resources ?? this.resources,
    territories: territories ?? this.territories,
    memberNpcIds: memberNpcIds ?? this.memberNpcIds,
    memberRoles: memberRoles ?? this.memberRoles,
    brain: brain ?? this.brain,
    beliefs: beliefs ?? this.beliefs,
    personality: personality ?? this.personality,
    strength: strength ?? this.strength,
    influence: influence ?? this.influence,
    technologyLevel: technologyLevel ?? this.technologyLevel,
    morality: morality ?? this.morality,
    stability: stability ?? this.stability,
    importance: importance ?? this.importance,
    status: status ?? this.status,
    tags: tags,
    lastUpdatedMinute: lastUpdatedMinute ?? this.lastUpdatedMinute,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'type': type.name,
    'description': description,
    'leaderNpcId': leaderNpcId,
    'resources': resources.toJson(),
    'territories': territories.map((item) => item.toJson()).toList(),
    'memberNpcIds': memberNpcIds,
    'memberRoles': memberRoles,
    'brain': brain.toJson(),
    'beliefs': beliefs,
    'personality': personality,
    'strength': strength,
    'influence': influence,
    'technologyLevel': technologyLevel,
    'morality': morality,
    'stability': stability,
    'importance': importance,
    'status': status.name,
    'tags': tags,
    'lastUpdatedMinute': lastUpdatedMinute,
  };

  factory FactionState.fromJson(Map<String, Object?> json) => FactionState(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '未命名势力',
    type: _enumValue(FactionType.values, json['type'], FactionType.guild),
    description: json['description'] as String? ?? '',
    leaderNpcId: json['leaderNpcId'] as String? ?? '',
    resources: FactionResource.fromJson(_map(json['resources'])),
    territories: (json['territories'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => FactionTerritory.fromJson(item.cast<String, Object?>()))
        .toList(),
    memberNpcIds: _strings(json['memberNpcIds']),
    memberRoles: json['memberRoles'] is Map
        ? (json['memberRoles'] as Map).map(
            (key, value) => MapEntry(key.toString(), value.toString()),
          )
        : const {},
    brain: FactionBrain.fromJson(_map(json['brain'])),
    beliefs: _map(json['beliefs']),
    personality: json['personality'] as String? ?? 'pragmatic',
    strength:
        (json['strength'] as num?)?.toInt() ??
        (json['resources'] is Map
            ? ((_map(json['resources'])['military'] as num?)?.toInt() ?? 40)
            : 40),
    influence:
        (json['influence'] as num?)?.toInt() ??
        (json['resources'] is Map
            ? ((_map(json['resources'])['influence'] as num?)?.toInt() ?? 40)
            : 40),
    technologyLevel:
        (json['technologyLevel'] as num?)?.toInt() ??
        (json['resources'] is Map
            ? ((_map(json['resources'])['technology'] as num?)?.toInt() ?? 30)
            : 30),
    morality: (json['morality'] as num?)?.toInt() ?? 0,
    stability: (json['stability'] as num?)?.toInt() ?? 70,
    importance: (json['importance'] as num?)?.toInt() ?? 50,
    status: _enumValue(
      FactionStatus.values,
      json['status'],
      FactionStatus.active,
    ),
    tags: _strings(json['tags']),
    lastUpdatedMinute: (json['lastUpdatedMinute'] as num?)?.toInt() ?? 0,
  );
}

class BattleEvent {
  const BattleEvent({
    required this.id,
    required this.attackerFactionId,
    required this.defenderFactionId,
    required this.locationId,
    required this.result,
    this.powerDifference = 0,
    this.attackerLoss = 0,
    this.defenderLoss = 0,
    this.casualties = const {},
    this.worldMinute = 0,
  });
  final String id, attackerFactionId, defenderFactionId, locationId;
  final BattleResult result;
  final int powerDifference, attackerLoss, defenderLoss, worldMinute;
  final Map<String, int> casualties;

  Map<String, Object?> toJson() => {
    'id': id,
    'attackerFactionId': attackerFactionId,
    'defenderFactionId': defenderFactionId,
    'locationId': locationId,
    'result': result.name,
    'powerDifference': powerDifference,
    'attackerLoss': attackerLoss,
    'defenderLoss': defenderLoss,
    'casualties': casualties,
    'worldMinute': worldMinute,
  };

  factory BattleEvent.fromJson(Map<String, Object?> json) => BattleEvent(
    id: json['id'] as String? ?? '',
    attackerFactionId: json['attackerFactionId'] as String? ?? '',
    defenderFactionId: json['defenderFactionId'] as String? ?? '',
    locationId: json['locationId'] as String? ?? '',
    result: _enumValue(
      BattleResult.values,
      json['result'],
      BattleResult.stalemate,
    ),
    powerDifference: (json['powerDifference'] as num?)?.toInt() ?? 0,
    attackerLoss: (json['attackerLoss'] as num?)?.toInt() ?? 0,
    defenderLoss: (json['defenderLoss'] as num?)?.toInt() ?? 0,
    casualties: json['casualties'] is Map
        ? (json['casualties'] as Map).map(
            (key, value) => MapEntry(key.toString(), (value as num).toInt()),
          )
        : const {},
    worldMinute: (json['worldMinute'] as num?)?.toInt() ?? 0,
  );
}

class InternalConflict {
  const InternalConflict({
    required this.id,
    required this.factionId,
    required this.title,
    this.description = '',
    this.status = InternalConflictStatus.active,
    this.severity = 50,
    this.startedAtMinute = 0,
    this.resolvedAtMinute,
  });
  final String id, factionId, title, description;
  final InternalConflictStatus status;
  final int severity, startedAtMinute;
  final int? resolvedAtMinute;

  Map<String, Object?> toJson() => {
    'id': id,
    'factionId': factionId,
    'title': title,
    'description': description,
    'status': status.name,
    'severity': severity,
    'startedAtMinute': startedAtMinute,
    'resolvedAtMinute': resolvedAtMinute,
  };

  factory InternalConflict.fromJson(Map<String, Object?> json) =>
      InternalConflict(
        id: json['id'] as String? ?? '',
        factionId: json['factionId'] as String? ?? '',
        title: json['title'] as String? ?? '',
        description: json['description'] as String? ?? '',
        status: _enumValue(
          InternalConflictStatus.values,
          json['status'],
          InternalConflictStatus.active,
        ),
        severity: (json['severity'] as num?)?.toInt() ?? 50,
        startedAtMinute: (json['startedAtMinute'] as num?)?.toInt() ?? 0,
        resolvedAtMinute: (json['resolvedAtMinute'] as num?)?.toInt(),
      );
}

class FactionHistoryEntry {
  const FactionHistoryEntry({
    required this.id,
    required this.factionId,
    required this.summary,
    required this.worldMinute,
    this.event = '',
    this.participants = const [],
    this.result = '',
    this.actionId,
    this.relatedEntityIds = const [],
    this.importance = 5,
  });
  final String id, factionId, summary, event, result;
  final String? actionId;
  final List<String> relatedEntityIds;
  final List<String> participants;
  final int worldMinute, importance;

  Map<String, Object?> toJson() => {
    'id': id,
    'factionId': factionId,
    'summary': summary,
    'worldMinute': worldMinute,
    'event': event,
    'participants': participants,
    'result': result,
    'actionId': actionId,
    'relatedEntityIds': relatedEntityIds,
    'importance': importance,
  };

  factory FactionHistoryEntry.fromJson(Map<String, Object?> json) =>
      FactionHistoryEntry(
        id: json['id'] as String? ?? '',
        factionId: json['factionId'] as String? ?? '',
        summary: json['summary'] as String? ?? '',
        worldMinute: (json['worldMinute'] as num?)?.toInt() ?? 0,
        event: json['event'] as String? ?? '',
        participants: _strings(json['participants']),
        result: json['result'] as String? ?? '',
        actionId: json['actionId'] as String?,
        relatedEntityIds: _strings(json['relatedEntityIds']),
        importance: (json['importance'] as num?)?.toInt() ?? 5,
      );
}

class FactionSecretState {
  const FactionSecretState({
    required this.id,
    required this.factionId,
    required this.content,
    this.revealedToPlayerIds = const [],
    this.revealed = false,
  });
  final String id, factionId, content;
  final List<String> revealedToPlayerIds;
  final bool revealed;

  FactionSecretState copyWith({
    List<String>? revealedToPlayerIds,
    bool? revealed,
  }) => FactionSecretState(
    id: id,
    factionId: factionId,
    content: content,
    revealedToPlayerIds: revealedToPlayerIds ?? this.revealedToPlayerIds,
    revealed: revealed ?? this.revealed,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'factionId': factionId,
    'content': content,
    'revealedToPlayerIds': revealedToPlayerIds,
    'revealed': revealed,
  };

  factory FactionSecretState.fromJson(Map<String, Object?> json) =>
      FactionSecretState(
        id: json['id'] as String? ?? '',
        factionId: json['factionId'] as String? ?? '',
        content: json['content'] as String? ?? '',
        revealedToPlayerIds: _strings(json['revealedToPlayerIds']),
        revealed: json['revealed'] as bool? ?? false,
      );
}

class FactionKnowledge {
  const FactionKnowledge({
    required this.id,
    required this.factionId,
    required this.subjectId,
    required this.content,
    this.visibility = FactionKnowledgeVisibility.faction,
    this.ownerPlayerId,
    this.confidence = 1,
    this.worldMinute = 0,
  });
  final String id, factionId, subjectId, content;
  final FactionKnowledgeVisibility visibility;
  final String? ownerPlayerId;
  final double confidence;
  final int worldMinute;

  bool visibleTo(String? playerId, {bool gm = false}) =>
      gm ||
      visibility == FactionKnowledgeVisibility.public ||
      (visibility == FactionKnowledgeVisibility.player &&
          ownerPlayerId == playerId);

  Map<String, Object?> toJson() => {
    'id': id,
    'factionId': factionId,
    'subjectId': subjectId,
    'content': content,
    'visibility': visibility.name,
    'ownerPlayerId': ownerPlayerId,
    'confidence': confidence,
    'worldMinute': worldMinute,
  };

  factory FactionKnowledge.fromJson(Map<String, Object?> json) =>
      FactionKnowledge(
        id: json['id'] as String? ?? '',
        factionId: json['factionId'] as String? ?? '',
        subjectId: json['subjectId'] as String? ?? '',
        content: json['content'] as String? ?? '',
        visibility: _enumValue(
          FactionKnowledgeVisibility.values,
          json['visibility'],
          FactionKnowledgeVisibility.faction,
        ),
        ownerPlayerId: json['ownerPlayerId'] as String?,
        confidence: (json['confidence'] as num?)?.toDouble() ?? 1,
        worldMinute: (json['worldMinute'] as num?)?.toInt() ?? 0,
      );
}

class FactionSimulationState {
  const FactionSimulationState({
    this.factions = const [],
    this.relationships = const [],
    this.actions = const [],
    this.battles = const [],
    this.internalConflicts = const [],
    this.history = const [],
    this.secrets = const [],
    this.knowledge = const [],
    this.worldMinute = 0,
    this.lastTickMinute = 0,
    this.simulationLevel = FactionSimulationLevel.normal,
  });
  final List<FactionState> factions;
  final List<FactionRelationshipState> relationships;
  final List<FactionActionState> actions;
  final List<BattleEvent> battles;
  final List<InternalConflict> internalConflicts;
  final List<FactionHistoryEntry> history;
  final List<FactionSecretState> secrets;
  final List<FactionKnowledge> knowledge;
  final int worldMinute, lastTickMinute;
  final FactionSimulationLevel simulationLevel;

  bool get isInitialized => factions.isNotEmpty;

  FactionSimulationState copyWith({
    List<FactionState>? factions,
    List<FactionRelationshipState>? relationships,
    List<FactionActionState>? actions,
    List<BattleEvent>? battles,
    List<InternalConflict>? internalConflicts,
    List<FactionHistoryEntry>? history,
    List<FactionSecretState>? secrets,
    List<FactionKnowledge>? knowledge,
    int? worldMinute,
    int? lastTickMinute,
    FactionSimulationLevel? simulationLevel,
  }) => FactionSimulationState(
    factions: factions ?? this.factions,
    relationships: relationships ?? this.relationships,
    actions: actions ?? this.actions,
    battles: battles ?? this.battles,
    internalConflicts: internalConflicts ?? this.internalConflicts,
    history: history ?? this.history,
    secrets: secrets ?? this.secrets,
    knowledge: knowledge ?? this.knowledge,
    worldMinute: worldMinute ?? this.worldMinute,
    lastTickMinute: lastTickMinute ?? this.lastTickMinute,
    simulationLevel: simulationLevel ?? this.simulationLevel,
  );

  FactionSimulationState publicView() => copyWith(
    relationships: relationships.where((item) => !item.hidden).toList(),
    secrets: secrets.where((item) => item.revealed).toList(),
    knowledge: knowledge
        .where((item) => item.visibility == FactionKnowledgeVisibility.public)
        .toList(),
  );

  FactionSimulationState forPlayer(String playerId) => publicView().copyWith(
    secrets: secrets
        .where(
          (item) =>
              item.revealed || item.revealedToPlayerIds.contains(playerId),
        )
        .toList(),
    knowledge: knowledge.where((item) => item.visibleTo(playerId)).toList(),
  );

  Map<String, Object?> toJson() => {
    'factions': factions.map((item) => item.toJson()).toList(),
    'relationships': relationships.map((item) => item.toJson()).toList(),
    'actions': actions.map((item) => item.toJson()).toList(),
    'battles': battles.map((item) => item.toJson()).toList(),
    'internalConflicts': internalConflicts
        .map((item) => item.toJson())
        .toList(),
    'history': history.map((item) => item.toJson()).toList(),
    'secrets': secrets.map((item) => item.toJson()).toList(),
    'knowledge': knowledge.map((item) => item.toJson()).toList(),
    'worldMinute': worldMinute,
    'lastTickMinute': lastTickMinute,
    'simulationLevel': simulationLevel.name,
  };

  factory FactionSimulationState.fromJson(
    Map<String, Object?> json,
  ) => FactionSimulationState(
    factions: (json['factions'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => FactionState.fromJson(item.cast<String, Object?>()))
        .toList(),
    relationships: (json['relationships'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (item) =>
              FactionRelationshipState.fromJson(item.cast<String, Object?>()),
        )
        .toList(),
    actions: (json['actions'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (item) => FactionActionState.fromJson(item.cast<String, Object?>()),
        )
        .toList(),
    battles: (json['battles'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => BattleEvent.fromJson(item.cast<String, Object?>()))
        .toList(),
    internalConflicts: (json['internalConflicts'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => InternalConflict.fromJson(item.cast<String, Object?>()))
        .toList(),
    history: (json['history'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (item) => FactionHistoryEntry.fromJson(item.cast<String, Object?>()),
        )
        .toList(),
    secrets: (json['secrets'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (item) => FactionSecretState.fromJson(item.cast<String, Object?>()),
        )
        .toList(),
    knowledge: (json['knowledge'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => FactionKnowledge.fromJson(item.cast<String, Object?>()))
        .toList(),
    worldMinute: (json['worldMinute'] as num?)?.toInt() ?? 0,
    lastTickMinute: (json['lastTickMinute'] as num?)?.toInt() ?? 0,
    simulationLevel: _enumValue(
      FactionSimulationLevel.values,
      json['simulationLevel'],
      FactionSimulationLevel.normal,
    ),
  );
}
