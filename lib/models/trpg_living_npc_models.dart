enum NPCLifeTier { main, important, normal, background }

enum NPCLifeStatus { active, travelling, hidden, companion, left, dead }

enum NPCGoalType {
  survival,
  protect,
  find,
  escape,
  revenge,
  help,
  hide,
  investigate,
}

enum NPCGoalStatus { active, paused, completed, failed, abandoned }

enum NPCActionType {
  move,
  talk,
  search,
  rest,
  work,
  hide,
  help,
  steal,
  attack,
  run,
}

enum NPCMemoryKind { shortTerm, longTerm, trauma, beliefChange }

enum NPCScheduleTrigger { time, playerImpact, worldChange, manual }

T _npcEnum<T extends Enum>(List<T> values, Object? raw, T fallback) =>
    values.where((value) => value.name == raw).firstOrNull ?? fallback;

List<String> _npcStrings(Object? raw) => raw is List
    ? raw.map((value) => value.toString()).toList()
    : const <String>[];

Map<String, Object?> _npcMap(Object? raw) => raw is Map
    ? raw.map((key, value) => MapEntry(key.toString(), value))
    : const <String, Object?>{};

class NPCPersonality {
  const NPCPersonality({
    this.traits = const [],
    this.values = const [],
    this.fears = const [],
    this.likes = const [],
    this.dislikes = const [],
    this.temperament = 'stable',
    this.morality = 'neutral',
    this.speechStyle = '',
  });

  final List<String> traits, values, fears, likes, dislikes;
  final String temperament, morality, speechStyle;

  Map<String, Object?> toJson() => {
    'traits': traits,
    'values': values,
    'fears': fears,
    'likes': likes,
    'dislikes': dislikes,
    'temperament': temperament,
    'morality': morality,
    'speechStyle': speechStyle,
  };

  factory NPCPersonality.fromJson(Map<String, Object?> json) => NPCPersonality(
    traits: _npcStrings(json['traits']),
    values: _npcStrings(json['values']),
    fears: _npcStrings(json['fears']),
    likes: _npcStrings(json['likes']),
    dislikes: _npcStrings(json['dislikes']),
    temperament: json['temperament'] as String? ?? 'stable',
    morality: json['morality'] as String? ?? 'neutral',
    speechStyle: json['speechStyle'] as String? ?? '',
  );
}

class NPCGoal {
  const NPCGoal({
    required this.goalId,
    required this.npcId,
    required this.type,
    required this.description,
    this.priority = 50,
    this.progress = 0,
    this.deadline,
    this.status = NPCGoalStatus.active,
    this.targetId,
    this.targetLocationId,
  });

  final String goalId, npcId, description;
  final NPCGoalType type;
  final int priority, progress;
  final DateTime? deadline;
  final NPCGoalStatus status;
  final String? targetId, targetLocationId;

  NPCGoal copyWith({
    int? priority,
    int? progress,
    NPCGoalStatus? status,
    DateTime? deadline,
  }) => NPCGoal(
    goalId: goalId,
    npcId: npcId,
    type: type,
    description: description,
    priority: (priority ?? this.priority).clamp(0, 100),
    progress: (progress ?? this.progress).clamp(0, 100),
    deadline: deadline ?? this.deadline,
    status: status ?? this.status,
    targetId: targetId,
    targetLocationId: targetLocationId,
  );

  Map<String, Object?> toJson() => {
    'goalId': goalId,
    'npcId': npcId,
    'type': type.name,
    'description': description,
    'priority': priority,
    'progress': progress,
    'deadline': deadline?.toIso8601String(),
    'status': status.name,
    'targetId': targetId,
    'targetLocationId': targetLocationId,
  };

  factory NPCGoal.fromJson(Map<String, Object?> json) => NPCGoal(
    goalId: json['goalId'] as String? ?? '',
    npcId: json['npcId'] as String? ?? '',
    type: _npcEnum(NPCGoalType.values, json['type'], NPCGoalType.survival),
    description: json['description'] as String? ?? '',
    priority: ((json['priority'] as num?)?.toInt() ?? 50).clamp(0, 100),
    progress: ((json['progress'] as num?)?.toInt() ?? 0).clamp(0, 100),
    deadline: DateTime.tryParse(json['deadline'] as String? ?? ''),
    status: _npcEnum(
      NPCGoalStatus.values,
      json['status'],
      NPCGoalStatus.active,
    ),
    targetId: json['targetId'] as String?,
    targetLocationId: json['targetLocationId'] as String?,
  );
}

class NPCEmotionState {
  const NPCEmotionState({
    this.fear = 0,
    this.anger = 0,
    this.joy = 0,
    this.sadness = 0,
    this.stress = 0,
  });

  final int fear, anger, joy, sadness, stress;

  NPCEmotionState copyWith({
    int? fear,
    int? anger,
    int? joy,
    int? sadness,
    int? stress,
  }) => NPCEmotionState(
    fear: (fear ?? this.fear).clamp(0, 100),
    anger: (anger ?? this.anger).clamp(0, 100),
    joy: (joy ?? this.joy).clamp(0, 100),
    sadness: (sadness ?? this.sadness).clamp(0, 100),
    stress: (stress ?? this.stress).clamp(0, 100),
  );

  Map<String, Object?> toJson() => {
    'fear': fear,
    'anger': anger,
    'joy': joy,
    'sadness': sadness,
    'stress': stress,
  };

  factory NPCEmotionState.fromJson(Map<String, Object?> json) =>
      NPCEmotionState(
        fear: ((json['fear'] as num?)?.toInt() ?? 0).clamp(0, 100),
        anger: ((json['anger'] as num?)?.toInt() ?? 0).clamp(0, 100),
        joy: ((json['joy'] as num?)?.toInt() ?? 0).clamp(0, 100),
        sadness: ((json['sadness'] as num?)?.toInt() ?? 0).clamp(0, 100),
        stress: ((json['stress'] as num?)?.toInt() ?? 0).clamp(0, 100),
      );
}

class NPCPlan {
  const NPCPlan({
    required this.summary,
    this.targetLocationId,
    this.targetId,
    this.startedAtMinute = 0,
    this.expectedEndMinute = 0,
  });

  final String summary;
  final String? targetLocationId, targetId;
  final int startedAtMinute, expectedEndMinute;

  Map<String, Object?> toJson() => {
    'summary': summary,
    'targetLocationId': targetLocationId,
    'targetId': targetId,
    'startedAtMinute': startedAtMinute,
    'expectedEndMinute': expectedEndMinute,
  };

  factory NPCPlan.fromJson(Map<String, Object?> json) => NPCPlan(
    summary: json['summary'] as String? ?? '',
    targetLocationId: json['targetLocationId'] as String?,
    targetId: json['targetId'] as String?,
    startedAtMinute: (json['startedAtMinute'] as num?)?.toInt() ?? 0,
    expectedEndMinute: (json['expectedEndMinute'] as num?)?.toInt() ?? 0,
  );
}

class NPCScheduleEntry {
  const NPCScheduleEntry({
    required this.minuteOfDay,
    required this.actionType,
    this.locationId,
    this.description = '',
  });

  final int minuteOfDay;
  final NPCActionType actionType;
  final String? locationId;
  final String description;

  Map<String, Object?> toJson() => {
    'minuteOfDay': minuteOfDay,
    'actionType': actionType.name,
    'locationId': locationId,
    'description': description,
  };

  factory NPCScheduleEntry.fromJson(Map<String, Object?> json) =>
      NPCScheduleEntry(
        minuteOfDay: ((json['minuteOfDay'] as num?)?.toInt() ?? 0).clamp(
          0,
          1439,
        ),
        actionType: _npcEnum(
          NPCActionType.values,
          json['actionType'],
          NPCActionType.work,
        ),
        locationId: json['locationId'] as String?,
        description: json['description'] as String? ?? '',
      );
}

class NPCBrain {
  const NPCBrain({
    required this.npcId,
    this.personality = const NPCPersonality(),
    this.goals = const [],
    this.beliefs = const {},
    this.currentNeeds = const {},
    this.currentLocation = '',
    this.currentPlan,
    this.emotionalState = const NPCEmotionState(),
    this.tier = NPCLifeTier.normal,
    this.status = NPCLifeStatus.active,
    this.schedule = const [],
    this.inventory = const [],
    this.lastActionAtMinute = -1,
    this.nextActionAtMinute = 0,
    this.deathEventId,
    this.killerId,
    this.deathLocationId,
    this.deathMinute,
  });

  final String npcId, currentLocation;
  final NPCPersonality personality;
  final List<NPCGoal> goals;
  final Map<String, Object?> beliefs;
  final Map<String, int> currentNeeds;
  final NPCPlan? currentPlan;
  final NPCEmotionState emotionalState;
  final NPCLifeTier tier;
  final NPCLifeStatus status;
  final List<NPCScheduleEntry> schedule;
  final List<String> inventory;
  final int lastActionAtMinute, nextActionAtMinute;
  final String? deathEventId, killerId, deathLocationId;
  final int? deathMinute;

  NPCBrain copyWith({
    NPCPersonality? personality,
    List<NPCGoal>? goals,
    Map<String, Object?>? beliefs,
    Map<String, int>? currentNeeds,
    String? currentLocation,
    NPCPlan? currentPlan,
    bool clearPlan = false,
    NPCEmotionState? emotionalState,
    NPCLifeTier? tier,
    NPCLifeStatus? status,
    List<NPCScheduleEntry>? schedule,
    List<String>? inventory,
    int? lastActionAtMinute,
    int? nextActionAtMinute,
    String? deathEventId,
    String? killerId,
    String? deathLocationId,
    int? deathMinute,
  }) => NPCBrain(
    npcId: npcId,
    personality: personality ?? this.personality,
    goals: goals ?? this.goals,
    beliefs: beliefs ?? this.beliefs,
    currentNeeds: currentNeeds ?? this.currentNeeds,
    currentLocation: currentLocation ?? this.currentLocation,
    currentPlan: clearPlan ? null : currentPlan ?? this.currentPlan,
    emotionalState: emotionalState ?? this.emotionalState,
    tier: tier ?? this.tier,
    status: status ?? this.status,
    schedule: schedule ?? this.schedule,
    inventory: inventory ?? this.inventory,
    lastActionAtMinute: lastActionAtMinute ?? this.lastActionAtMinute,
    nextActionAtMinute: nextActionAtMinute ?? this.nextActionAtMinute,
    deathEventId: deathEventId ?? this.deathEventId,
    killerId: killerId ?? this.killerId,
    deathLocationId: deathLocationId ?? this.deathLocationId,
    deathMinute: deathMinute ?? this.deathMinute,
  );

  NPCBrain publicView() => copyWith(
    goals: const [],
    beliefs: const {},
    currentNeeds: const {},
    clearPlan: true,
    schedule: const [],
  );

  Map<String, Object?> toJson() => {
    'npcId': npcId,
    'personality': personality.toJson(),
    'goals': goals.map((value) => value.toJson()).toList(),
    'beliefs': beliefs,
    'currentNeeds': currentNeeds,
    'currentLocation': currentLocation,
    'currentPlan': currentPlan?.toJson(),
    'emotionalState': emotionalState.toJson(),
    'tier': tier.name,
    'status': status.name,
    'schedule': schedule.map((value) => value.toJson()).toList(),
    'inventory': inventory,
    'lastActionAtMinute': lastActionAtMinute,
    'nextActionAtMinute': nextActionAtMinute,
    'deathEventId': deathEventId,
    'killerId': killerId,
    'deathLocationId': deathLocationId,
    'deathMinute': deathMinute,
  };

  factory NPCBrain.fromJson(Map<String, Object?> json) => NPCBrain(
    npcId: json['npcId'] as String? ?? '',
    personality: NPCPersonality.fromJson(_npcMap(json['personality'])),
    goals: (json['goals'] as List? ?? const [])
        .whereType<Map>()
        .map((value) => NPCGoal.fromJson(value.cast<String, Object?>()))
        .toList(),
    beliefs: _npcMap(json['beliefs']),
    currentNeeds: json['currentNeeds'] is Map
        ? (json['currentNeeds'] as Map).map(
            (key, value) => MapEntry(key.toString(), (value as num).toInt()),
          )
        : const {},
    currentLocation: json['currentLocation'] as String? ?? '',
    currentPlan: json['currentPlan'] is Map
        ? NPCPlan.fromJson((json['currentPlan'] as Map).cast<String, Object?>())
        : null,
    emotionalState: NPCEmotionState.fromJson(_npcMap(json['emotionalState'])),
    tier: _npcEnum(NPCLifeTier.values, json['tier'], NPCLifeTier.normal),
    status: _npcEnum(
      NPCLifeStatus.values,
      json['status'],
      NPCLifeStatus.active,
    ),
    schedule: (json['schedule'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (value) => NPCScheduleEntry.fromJson(value.cast<String, Object?>()),
        )
        .toList(),
    inventory: _npcStrings(json['inventory']),
    lastActionAtMinute: (json['lastActionAtMinute'] as num?)?.toInt() ?? -1,
    nextActionAtMinute: (json['nextActionAtMinute'] as num?)?.toInt() ?? 0,
    deathEventId: json['deathEventId'] as String?,
    killerId: json['killerId'] as String?,
    deathLocationId: json['deathLocationId'] as String?,
    deathMinute: (json['deathMinute'] as num?)?.toInt(),
  );
}

class NPCAction {
  const NPCAction({
    required this.actionId,
    required this.npcId,
    required this.actionType,
    required this.reason,
    this.target,
    this.location,
    this.durationMinutes = 30,
    this.createdAtMinute = 0,
    this.validated = false,
    this.blockedReason,
  });

  final String actionId, npcId, reason;
  final NPCActionType actionType;
  final String? target, location, blockedReason;
  final int durationMinutes, createdAtMinute;
  final bool validated;

  NPCAction copyWith({bool? validated, String? blockedReason}) => NPCAction(
    actionId: actionId,
    npcId: npcId,
    actionType: actionType,
    reason: reason,
    target: target,
    location: location,
    durationMinutes: durationMinutes,
    createdAtMinute: createdAtMinute,
    validated: validated ?? this.validated,
    blockedReason: blockedReason ?? this.blockedReason,
  );

  Map<String, Object?> toJson() => {
    'actionId': actionId,
    'npcId': npcId,
    'actionType': actionType.name,
    'target': target,
    'location': location,
    'reason': reason,
    'durationMinutes': durationMinutes,
    'createdAtMinute': createdAtMinute,
    'validated': validated,
    'blockedReason': blockedReason,
  };

  factory NPCAction.fromJson(Map<String, Object?> json) => NPCAction(
    actionId: json['actionId'] as String? ?? '',
    npcId: json['npcId'] as String? ?? '',
    actionType: _npcEnum(
      NPCActionType.values,
      json['actionType'],
      NPCActionType.work,
    ),
    target: json['target'] as String?,
    location: json['location'] as String?,
    reason: json['reason'] as String? ?? '',
    durationMinutes: (json['durationMinutes'] as num?)?.toInt() ?? 30,
    createdAtMinute: (json['createdAtMinute'] as num?)?.toInt() ?? 0,
    validated: json['validated'] as bool? ?? false,
    blockedReason: json['blockedReason'] as String?,
  );
}

class NPCMemoryRecord {
  const NPCMemoryRecord({
    required this.memoryId,
    required this.npcId,
    required this.eventId,
    required this.content,
    required this.timestampMinute,
    this.importance = 10,
    this.emotion = '',
    this.kind = NPCMemoryKind.shortTerm,
    this.currentWeight = 10,
    this.knownBy = const [],
  });

  final String memoryId, npcId, eventId, content, emotion;
  final int importance, timestampMinute, currentWeight;
  final NPCMemoryKind kind;
  final List<String> knownBy;

  bool get permanent =>
      kind == NPCMemoryKind.trauma ||
      kind == NPCMemoryKind.beliefChange ||
      importance >= 100;

  NPCMemoryRecord decay(int elapsedMinutes) {
    if (permanent || elapsedMinutes <= 0) return this;
    final loss = kind == NPCMemoryKind.longTerm
        ? elapsedMinutes ~/ 2880
        : elapsedMinutes ~/ 720;
    return NPCMemoryRecord(
      memoryId: memoryId,
      npcId: npcId,
      eventId: eventId,
      content: content,
      timestampMinute: timestampMinute,
      importance: importance,
      emotion: emotion,
      kind: kind,
      currentWeight: (currentWeight - loss).clamp(0, 200),
      knownBy: knownBy,
    );
  }

  Map<String, Object?> toJson() => {
    'memoryId': memoryId,
    'npcId': npcId,
    'eventId': eventId,
    'content': content,
    'importance': importance,
    'emotion': emotion,
    'timestampMinute': timestampMinute,
    'kind': kind.name,
    'currentWeight': currentWeight,
    'knownBy': knownBy,
  };

  factory NPCMemoryRecord.fromJson(Map<String, Object?> json) =>
      NPCMemoryRecord(
        memoryId: json['memoryId'] as String? ?? '',
        npcId: json['npcId'] as String? ?? '',
        eventId: json['eventId'] as String? ?? '',
        content: json['content'] as String? ?? '',
        importance: (json['importance'] as num?)?.toInt() ?? 10,
        emotion: json['emotion'] as String? ?? '',
        timestampMinute: (json['timestampMinute'] as num?)?.toInt() ?? 0,
        kind: _npcEnum(
          NPCMemoryKind.values,
          json['kind'],
          NPCMemoryKind.shortTerm,
        ),
        currentWeight: (json['currentWeight'] as num?)?.toInt() ?? 10,
        knownBy: _npcStrings(json['knownBy']),
      );
}

class NPCRelationship {
  const NPCRelationship({
    required this.sourceNpc,
    required this.targetCharacter,
    this.trust = 0,
    this.fear = 0,
    this.respect = 0,
    this.hate = 0,
    this.affection = 0,
    this.suspicion = 0,
    this.lastUpdateMinute = 0,
    this.reasons = const [],
  });

  final String sourceNpc, targetCharacter;
  final int trust, fear, respect, hate, affection, suspicion;
  final int lastUpdateMinute;
  final List<String> reasons;

  String get key => '$sourceNpc->$targetCharacter';

  NPCRelationship apply({
    int trust = 0,
    int fear = 0,
    int respect = 0,
    int hate = 0,
    int affection = 0,
    int suspicion = 0,
    required int atMinute,
    required String reason,
  }) => NPCRelationship(
    sourceNpc: sourceNpc,
    targetCharacter: targetCharacter,
    trust: (this.trust + trust).clamp(-100, 100),
    fear: (this.fear + fear).clamp(0, 100),
    respect: (this.respect + respect).clamp(-100, 100),
    hate: (this.hate + hate).clamp(0, 100),
    affection: (this.affection + affection).clamp(-100, 100),
    suspicion: (this.suspicion + suspicion).clamp(0, 100),
    lastUpdateMinute: atMinute,
    reasons: [...reasons, reason].reversed.take(12).toList().reversed.toList(),
  );

  Map<String, Object?> toJson() => {
    'sourceNpc': sourceNpc,
    'targetCharacter': targetCharacter,
    'trust': trust,
    'fear': fear,
    'respect': respect,
    'hate': hate,
    'affection': affection,
    'suspicion': suspicion,
    'lastUpdateMinute': lastUpdateMinute,
    'reasons': reasons,
  };

  factory NPCRelationship.fromJson(Map<String, Object?> json) =>
      NPCRelationship(
        sourceNpc: json['sourceNpc'] as String? ?? '',
        targetCharacter: json['targetCharacter'] as String? ?? '',
        trust: (json['trust'] as num?)?.toInt() ?? 0,
        fear: (json['fear'] as num?)?.toInt() ?? 0,
        respect: (json['respect'] as num?)?.toInt() ?? 0,
        hate: (json['hate'] as num?)?.toInt() ?? 0,
        affection: (json['affection'] as num?)?.toInt() ?? 0,
        suspicion: (json['suspicion'] as num?)?.toInt() ?? 0,
        lastUpdateMinute: (json['lastUpdateMinute'] as num?)?.toInt() ?? 0,
        reasons: _npcStrings(json['reasons']),
      );
}

class NPCSecret {
  const NPCSecret({
    required this.secretId,
    required this.ownerNpc,
    required this.content,
    this.importance = 50,
    this.knownBy = const [],
  });

  final String secretId, ownerNpc, content;
  final int importance;
  final List<String> knownBy;

  NPCSecret copyWith({List<String>? knownBy}) => NPCSecret(
    secretId: secretId,
    ownerNpc: ownerNpc,
    content: content,
    importance: importance,
    knownBy: knownBy ?? this.knownBy,
  );

  Map<String, Object?> toJson() => {
    'secretId': secretId,
    'ownerNpc': ownerNpc,
    'content': content,
    'importance': importance,
    'knownBy': knownBy,
  };

  factory NPCSecret.fromJson(Map<String, Object?> json) => NPCSecret(
    secretId: json['secretId'] as String? ?? '',
    ownerNpc: json['ownerNpc'] as String? ?? '',
    content: json['content'] as String? ?? '',
    importance: (json['importance'] as num?)?.toInt() ?? 50,
    knownBy: _npcStrings(json['knownBy']),
  );
}

class LivingNPCState {
  const LivingNPCState({
    this.worldMinute = 0,
    this.brains = const {},
    this.memories = const [],
    this.relationships = const [],
    this.secrets = const [],
    this.recentActions = const [],
    this.lastTickMinute = 0,
  });

  final int worldMinute, lastTickMinute;
  final Map<String, NPCBrain> brains;
  final List<NPCMemoryRecord> memories;
  final List<NPCRelationship> relationships;
  final List<NPCSecret> secrets;
  final List<NPCAction> recentActions;

  LivingNPCState copyWith({
    int? worldMinute,
    Map<String, NPCBrain>? brains,
    List<NPCMemoryRecord>? memories,
    List<NPCRelationship>? relationships,
    List<NPCSecret>? secrets,
    List<NPCAction>? recentActions,
    int? lastTickMinute,
  }) => LivingNPCState(
    worldMinute: worldMinute ?? this.worldMinute,
    brains: brains ?? this.brains,
    memories: memories ?? this.memories,
    relationships: relationships ?? this.relationships,
    secrets: secrets ?? this.secrets,
    recentActions: recentActions ?? this.recentActions,
    lastTickMinute: lastTickMinute ?? this.lastTickMinute,
  );

  LivingNPCState forViewer(String? viewerId, {bool isGm = false}) {
    if (isGm) return this;
    return copyWith(
      brains: brains.map((key, value) => MapEntry(key, value.publicView())),
      memories: memories
          .where(
            (value) =>
                value.knownBy.isEmpty ||
                (viewerId != null && value.knownBy.contains(viewerId)),
          )
          .toList(),
      relationships: relationships
          .where(
            (value) => viewerId != null && value.targetCharacter == viewerId,
          )
          .toList(),
      secrets: secrets
          .where(
            (value) => viewerId != null && value.knownBy.contains(viewerId),
          )
          .toList(),
    );
  }

  Map<String, Object?> toJson() => {
    'worldMinute': worldMinute,
    'brains': brains.map((key, value) => MapEntry(key, value.toJson())),
    'memories': memories.map((value) => value.toJson()).toList(),
    'relationships': relationships.map((value) => value.toJson()).toList(),
    'secrets': secrets.map((value) => value.toJson()).toList(),
    'recentActions': recentActions.map((value) => value.toJson()).toList(),
    'lastTickMinute': lastTickMinute,
  };

  factory LivingNPCState.fromJson(Map<String, Object?> json) => LivingNPCState(
    worldMinute: (json['worldMinute'] as num?)?.toInt() ?? 0,
    brains: json['brains'] is Map
        ? (json['brains'] as Map).map(
            (key, value) => MapEntry(
              key.toString(),
              NPCBrain.fromJson(
                value is Map ? value.cast<String, Object?>() : const {},
              ),
            ),
          )
        : const {},
    memories: (json['memories'] as List? ?? const [])
        .whereType<Map>()
        .map((value) => NPCMemoryRecord.fromJson(value.cast<String, Object?>()))
        .toList(),
    relationships: (json['relationships'] as List? ?? const [])
        .whereType<Map>()
        .map((value) => NPCRelationship.fromJson(value.cast<String, Object?>()))
        .toList(),
    secrets: (json['secrets'] as List? ?? const [])
        .whereType<Map>()
        .map((value) => NPCSecret.fromJson(value.cast<String, Object?>()))
        .toList(),
    recentActions: (json['recentActions'] as List? ?? const [])
        .whereType<Map>()
        .map((value) => NPCAction.fromJson(value.cast<String, Object?>()))
        .toList(),
    lastTickMinute: (json['lastTickMinute'] as num?)?.toInt() ?? 0,
  );
}
