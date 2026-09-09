enum InventoryCategory { consumable, weapon, armor, keyItem, questItem, misc }

enum QuestStatus { discovered, active, completed, failed }

enum AdvantageMode { normal, advantage, disadvantage }

enum DifficultyClass {
  veryEasy(5),
  easy(8),
  normal(10),
  moderate(12),
  hard(15),
  veryHard(18),
  extreme(22);

  const DifficultyClass(this.value);
  final int value;
}

T _enumByName<T extends Enum>(List<T> values, Object? raw, T fallback) =>
    values.where((value) => value.name == raw).firstOrNull ?? fallback;

List<String> _stringList(Object? value) => value is List
    ? value.map((item) => item.toString()).toList()
    : const <String>[];

Map<String, Object?> _objectMap(Object? value) =>
    value is Map ? value.cast<String, Object?>() : const <String, Object?>{};

class InventoryItem {
  const InventoryItem({
    required this.id,
    required this.name,
    this.description = '',
    this.quantity = 1,
    this.category = InventoryCategory.misc,
    this.usable = false,
    this.metadata = const {},
  });

  final String id;
  final String name;
  final String description;
  final int quantity;
  final InventoryCategory category;
  final bool usable;
  final Map<String, Object?> metadata;

  InventoryItem copyWith({int? quantity}) => InventoryItem(
    id: id,
    name: name,
    description: description,
    quantity: quantity ?? this.quantity,
    category: category,
    usable: usable,
    metadata: metadata,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'quantity': quantity,
    'category': category.name,
    'usable': usable,
    'metadata': metadata,
  };

  factory InventoryItem.fromJson(Map<String, Object?> json) => InventoryItem(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '未命名物品',
    description: json['description'] as String? ?? '',
    quantity: (json['quantity'] as num?)?.toInt() ?? 1,
    category: _enumByName(
      InventoryCategory.values,
      json['category'],
      InventoryCategory.misc,
    ),
    usable: json['usable'] as bool? ?? false,
    metadata: _objectMap(json['metadata']),
  );
}

class StatusEffect {
  const StatusEffect({
    required this.id,
    required this.name,
    this.description = '',
    this.duration,
    this.source = '',
    this.metadata = const {},
  });

  final String id;
  final String name;
  final String description;
  final int? duration;
  final String source;
  final Map<String, Object?> metadata;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'duration': duration,
    'source': source,
    'metadata': metadata,
  };

  factory StatusEffect.fromJson(Map<String, Object?> json) => StatusEffect(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '未知状态',
    description: json['description'] as String? ?? '',
    duration: (json['duration'] as num?)?.toInt(),
    source: json['source'] as String? ?? '',
    metadata: _objectMap(json['metadata']),
  );
}

class QuestObjective {
  const QuestObjective({
    required this.id,
    required this.description,
    this.current = 0,
    this.target = 1,
  });

  final String id;
  final String description;
  final int current;
  final int target;

  QuestObjective copyWith({int? current}) => QuestObjective(
    id: id,
    description: description,
    current: current ?? this.current,
    target: target,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'description': description,
    'current': current,
    'target': target,
  };

  factory QuestObjective.fromJson(Map<String, Object?> json) => QuestObjective(
    id: json['id'] as String? ?? '',
    description: json['description'] as String? ?? '',
    current: (json['current'] as num?)?.toInt() ?? 0,
    target: (json['target'] as num?)?.toInt() ?? 1,
  );
}

class QuestState {
  const QuestState({
    required this.questId,
    required this.title,
    this.description = '',
    this.objectives = const [],
    this.status = QuestStatus.discovered,
    this.progress = '',
    required this.discoveredAt,
    this.completedAt,
  });

  final String questId;
  final String title;
  final String description;
  final List<QuestObjective> objectives;
  final QuestStatus status;
  final String progress;
  final DateTime discoveredAt;
  final DateTime? completedAt;

  QuestState copyWith({
    List<QuestObjective>? objectives,
    QuestStatus? status,
    String? progress,
    DateTime? completedAt,
  }) => QuestState(
    questId: questId,
    title: title,
    description: description,
    objectives: objectives ?? this.objectives,
    status: status ?? this.status,
    progress: progress ?? this.progress,
    discoveredAt: discoveredAt,
    completedAt: completedAt ?? this.completedAt,
  );

  Map<String, Object?> toJson() => {
    'questId': questId,
    'title': title,
    'description': description,
    'objectives': objectives.map((item) => item.toJson()).toList(),
    'status': status.name,
    'progress': progress,
    'discoveredAt': discoveredAt.toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
  };

  factory QuestState.fromJson(Map<String, Object?> json) => QuestState(
    questId: json['questId'] as String? ?? '',
    title: json['title'] as String? ?? '未命名任务',
    description: json['description'] as String? ?? '',
    objectives: (json['objectives'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => QuestObjective.fromJson(item.cast<String, Object?>()))
        .toList(),
    status: _enumByName(
      QuestStatus.values,
      json['status'],
      QuestStatus.discovered,
    ),
    progress: json['progress'] as String? ?? '',
    discoveredAt:
        DateTime.tryParse(json['discoveredAt'] as String? ?? '') ??
        DateTime.now(),
    completedAt: DateTime.tryParse(json['completedAt'] as String? ?? ''),
  );
}

class SceneState {
  const SceneState({
    this.sceneId = '',
    this.locationId = '',
    this.title = '',
    this.description = '',
    this.atmosphere = '',
    this.npcIds = const [],
    this.tags = const [],
    this.backgroundImage,
    this.backgroundId,
    this.visualTheme = 'modern',
    this.timeOfDay = '',
    this.weather = '',
    this.ambientId,
    this.bgmId,
  });

  final String sceneId;
  final String locationId;
  final String title;
  final String description;
  final String atmosphere;
  final List<String> npcIds;
  final List<String> tags;
  final String? backgroundImage, backgroundId, ambientId, bgmId;
  final String visualTheme, timeOfDay, weather;

  Map<String, Object?> toJson() => {
    'sceneId': sceneId,
    'locationId': locationId,
    'title': title,
    'description': description,
    'atmosphere': atmosphere,
    'npcIds': npcIds,
    'tags': tags,
    'backgroundImage': backgroundImage,
    'backgroundId': backgroundId,
    'visualTheme': visualTheme,
    'timeOfDay': timeOfDay,
    'weather': weather,
    'ambientId': ambientId,
    'bgmId': bgmId,
  };

  factory SceneState.fromJson(Map<String, Object?> json) => SceneState(
    sceneId: json['sceneId'] as String? ?? '',
    locationId: json['locationId'] as String? ?? '',
    title: json['title'] as String? ?? '',
    description: json['description'] as String? ?? '',
    atmosphere: json['atmosphere'] as String? ?? '',
    npcIds: _stringList(json['npcIds']),
    tags: _stringList(json['tags']),
    backgroundImage: json['backgroundImage'] as String?,
    backgroundId: json['backgroundId'] as String?,
    visualTheme: json['visualTheme'] as String? ?? 'modern',
    timeOfDay: json['timeOfDay'] as String? ?? '',
    weather: json['weather'] as String? ?? '',
    ambientId: json['ambientId'] as String?,
    bgmId: json['bgmId'] as String?,
  );
}

class ClueState {
  const ClueState({
    required this.clueId,
    required this.name,
    this.description = '',
    this.discovered = false,
    this.discoveredBy,
    this.timestamp,
  });

  final String clueId;
  final String name;
  final String description;
  final bool discovered;
  final String? discoveredBy;
  final DateTime? timestamp;

  ClueState copyWith({
    bool? discovered,
    String? discoveredBy,
    DateTime? timestamp,
  }) => ClueState(
    clueId: clueId,
    name: name,
    description: description,
    discovered: discovered ?? this.discovered,
    discoveredBy: discoveredBy ?? this.discoveredBy,
    timestamp: timestamp ?? this.timestamp,
  );

  Map<String, Object?> toJson() => {
    'clueId': clueId,
    'name': name,
    'description': description,
    'discovered': discovered,
    'discoveredBy': discoveredBy,
    'timestamp': timestamp?.toIso8601String(),
  };

  factory ClueState.fromJson(Map<String, Object?> json) => ClueState(
    clueId: json['clueId'] as String? ?? '',
    name: json['name'] as String? ?? '未知线索',
    description: json['description'] as String? ?? '',
    discovered: json['discovered'] as bool? ?? false,
    discoveredBy: json['discoveredBy'] as String?,
    timestamp: DateTime.tryParse(json['timestamp'] as String? ?? ''),
  );
}

class NPCState {
  const NPCState({
    required this.npcId,
    required this.name,
    this.alive = true,
    this.disposition = 'neutral',
    this.locationId = '',
    this.relationship = 0,
    this.knownToPlayer = false,
    this.notes = '',
    this.hp = 10,
    this.maxHp = 10,
  });

  final String npcId;
  final String name;
  final bool alive;
  final String disposition;
  final String locationId;
  final int relationship;
  final bool knownToPlayer;
  final String notes;
  final int hp;
  final int maxHp;

  NPCState copyWith({
    bool? alive,
    String? locationId,
    int? relationship,
    bool? knownToPlayer,
    int? hp,
  }) => NPCState(
    npcId: npcId,
    name: name,
    alive: alive ?? this.alive,
    disposition: disposition,
    locationId: locationId ?? this.locationId,
    relationship: relationship ?? this.relationship,
    knownToPlayer: knownToPlayer ?? this.knownToPlayer,
    notes: notes,
    hp: hp ?? this.hp,
    maxHp: maxHp,
  );

  Map<String, Object?> toJson() => {
    'npcId': npcId,
    'name': name,
    'alive': alive,
    'disposition': disposition,
    'locationId': locationId,
    'relationship': relationship,
    'knownToPlayer': knownToPlayer,
    'notes': notes,
    'hp': hp,
    'maxHp': maxHp,
  };

  factory NPCState.fromJson(Map<String, Object?> json) => NPCState(
    npcId: json['npcId'] as String? ?? '',
    name: json['name'] as String? ?? '未知 NPC',
    alive: json['alive'] as bool? ?? true,
    disposition: json['disposition'] as String? ?? 'neutral',
    locationId: json['locationId'] as String? ?? '',
    relationship: (json['relationship'] as num?)?.toInt() ?? 0,
    knownToPlayer: json['knownToPlayer'] as bool? ?? false,
    notes: json['notes'] as String? ?? '',
    hp: (json['hp'] as num?)?.toInt() ?? 10,
    maxHp: (json['maxHp'] as num?)?.toInt() ?? 10,
  );
}

class SkillCheckResult {
  const SkillCheckResult({
    required this.stat,
    this.skillId,
    required this.rawRolls,
    required this.chosenRoll,
    required this.modifier,
    required this.total,
    required this.difficulty,
    required this.success,
    required this.criticalSuccess,
    required this.criticalFailure,
    required this.reason,
  });

  final String stat;
  final String? skillId;
  final List<int> rawRolls;
  final int chosenRoll;
  final int modifier;
  final int total;
  final int difficulty;
  final bool success;
  final bool criticalSuccess;
  final bool criticalFailure;
  final String reason;

  Map<String, Object?> toJson() => {
    'stat': stat,
    'skillId': skillId,
    'rawRolls': rawRolls,
    'chosenRoll': chosenRoll,
    'modifier': modifier,
    'total': total,
    'difficulty': difficulty,
    'success': success,
    'criticalSuccess': criticalSuccess,
    'criticalFailure': criticalFailure,
    'reason': reason,
  };
}

class ToolExecutionRecord {
  const ToolExecutionRecord({
    required this.toolCallId,
    required this.actionId,
    required this.toolName,
    required this.arguments,
    required this.result,
    required this.succeeded,
    required this.executedAt,
  });

  final String toolCallId;
  final String actionId;
  final String toolName;
  final Map<String, Object?> arguments;
  final Map<String, Object?> result;
  final bool succeeded;
  final DateTime executedAt;

  Map<String, Object?> toJson() => {
    'toolCallId': toolCallId,
    'actionId': actionId,
    'toolName': toolName,
    'arguments': arguments,
    'result': result,
    'succeeded': succeeded,
    'executedAt': executedAt.toIso8601String(),
  };

  factory ToolExecutionRecord.fromJson(Map<String, Object?> json) =>
      ToolExecutionRecord(
        toolCallId: json['toolCallId'] as String? ?? '',
        actionId: json['actionId'] as String? ?? '',
        toolName: json['toolName'] as String? ?? '',
        arguments: _objectMap(json['arguments']),
        result: _objectMap(json['result']),
        succeeded: json['succeeded'] as bool? ?? false,
        executedAt:
            DateTime.tryParse(json['executedAt'] as String? ?? '') ??
            DateTime.now(),
      );
}

class TRPGActionSnapshot {
  const TRPGActionSnapshot({
    required this.actionId,
    required this.createdAt,
    required this.sessionJson,
  });

  final String actionId;
  final DateTime createdAt;
  final Map<String, Object?> sessionJson;

  Map<String, Object?> toJson() => {
    'actionId': actionId,
    'createdAt': createdAt.toIso8601String(),
    'sessionJson': sessionJson,
  };

  factory TRPGActionSnapshot.fromJson(Map<String, Object?> json) =>
      TRPGActionSnapshot(
        actionId: json['actionId'] as String? ?? '',
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
        sessionJson: _objectMap(json['sessionJson']),
      );
}

class SkillDefinition {
  const SkillDefinition({
    required this.id,
    required this.name,
    required this.stat,
  });
  final String id;
  final String name;
  final String stat;
}
