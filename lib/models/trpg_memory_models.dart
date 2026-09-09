enum MemoryType {
  event,
  relationship,
  promise,
  secret,
  clue,
  playerChoice,
  npcMemory,
  companionMemory,
  worldEvent,
  locationMemory,
  questMemory,
  combatMemory,
  itemMemory,
  factionMemory,
  gmPlot,
  foreshadowing,
  privateMemory,
  summary,
}

enum MemoryConfidence { confirmed, likely, uncertain }

enum MemoryVisibility {
  public,
  playerPrivate,
  npcPrivate,
  companionPrivate,
  gmOnly,
}

enum KnowledgeRelationType { knows, suspects, doesNotKnow, believes, witnessed }

enum PromiseStatus { active, fulfilled, broken, expired }

enum StoryThreadStatus { open, progressing, resolved, abandoned }

enum CanonPriority {
  aiInference,
  npcBelief,
  confirmedMemory,
  confirmedEvent,
  structuredState,
  campaignCanon,
}

T _enum<T extends Enum>(List<T> values, Object? raw, T fallback) =>
    values.where((value) => value.name == raw).firstOrNull ?? fallback;

List<String> _strings(Object? raw) =>
    raw is List ? raw.map((value) => value.toString()).toList() : const [];

Map<String, Object?> _map(Object? raw) => raw is Map
    ? raw.map((key, value) => MapEntry(key.toString(), value))
    : const {};

class MemoryEntry {
  const MemoryEntry({
    required this.id,
    required this.sessionId,
    required this.type,
    required this.title,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    this.summary = '',
    this.importance = 4,
    this.confidence = MemoryConfidence.confirmed,
    this.sourceEventIds = const [],
    this.relatedEntityIds = const [],
    this.tags = const [],
    this.visibility = MemoryVisibility.public,
    this.ownerPlayerId,
    this.npcId,
    this.locationId,
    this.questId,
    this.resolved = false,
    this.pinned = false,
    this.expiresAt,
    this.canonPriority = CanonPriority.confirmedMemory,
    this.metadata = const {},
  });

  final String id, sessionId, title, content, summary;
  final MemoryType type;
  final int importance;
  final MemoryConfidence confidence;
  final DateTime createdAt, updatedAt;
  final List<String> sourceEventIds, relatedEntityIds, tags;
  final MemoryVisibility visibility;
  final String? ownerPlayerId, npcId, locationId, questId;
  final bool resolved, pinned;
  final DateTime? expiresAt;
  final CanonPriority canonPriority;
  final Map<String, Object?> metadata;

  MemoryEntry copyWith({
    String? title,
    String? content,
    String? summary,
    int? importance,
    MemoryConfidence? confidence,
    DateTime? updatedAt,
    List<String>? sourceEventIds,
    List<String>? relatedEntityIds,
    List<String>? tags,
    MemoryVisibility? visibility,
    bool? resolved,
    bool? pinned,
    CanonPriority? canonPriority,
    Map<String, Object?>? metadata,
  }) => MemoryEntry(
    id: id,
    sessionId: sessionId,
    type: type,
    title: title ?? this.title,
    content: content ?? this.content,
    summary: summary ?? this.summary,
    importance: (importance ?? this.importance).clamp(1, 10),
    confidence: confidence ?? this.confidence,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    sourceEventIds: sourceEventIds ?? this.sourceEventIds,
    relatedEntityIds: relatedEntityIds ?? this.relatedEntityIds,
    tags: tags ?? this.tags,
    visibility: visibility ?? this.visibility,
    ownerPlayerId: ownerPlayerId,
    npcId: npcId,
    locationId: locationId,
    questId: questId,
    resolved: resolved ?? this.resolved,
    pinned: pinned ?? this.pinned,
    expiresAt: expiresAt,
    canonPriority: canonPriority ?? this.canonPriority,
    metadata: metadata ?? this.metadata,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'sessionId': sessionId,
    'type': type.name,
    'title': title,
    'content': content,
    'summary': summary,
    'importance': importance,
    'confidence': confidence.name,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'sourceEventIds': sourceEventIds,
    'relatedEntityIds': relatedEntityIds,
    'tags': tags,
    'visibility': visibility.name,
    'ownerPlayerId': ownerPlayerId,
    'npcId': npcId,
    'locationId': locationId,
    'questId': questId,
    'resolved': resolved,
    'pinned': pinned,
    'expiresAt': expiresAt?.toIso8601String(),
    'canonPriority': canonPriority.name,
    'metadata': metadata,
  };

  factory MemoryEntry.fromJson(Map<String, Object?> json) => MemoryEntry(
    id: json['id'] as String? ?? '',
    sessionId: json['sessionId'] as String? ?? '',
    type: _enum(MemoryType.values, json['type'], MemoryType.event),
    title: json['title'] as String? ?? '',
    content: json['content'] as String? ?? '',
    summary: json['summary'] as String? ?? '',
    importance: ((json['importance'] as num?)?.toInt() ?? 4).clamp(1, 10),
    confidence: _enum(
      MemoryConfidence.values,
      json['confidence'],
      MemoryConfidence.confirmed,
    ),
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    updatedAt:
        DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
    sourceEventIds: _strings(json['sourceEventIds']),
    relatedEntityIds: _strings(json['relatedEntityIds']),
    tags: _strings(json['tags']),
    visibility: _enum(
      MemoryVisibility.values,
      json['visibility'],
      MemoryVisibility.public,
    ),
    ownerPlayerId: json['ownerPlayerId'] as String?,
    npcId: json['npcId'] as String?,
    locationId: json['locationId'] as String?,
    questId: json['questId'] as String?,
    resolved: json['resolved'] as bool? ?? false,
    pinned: json['pinned'] as bool? ?? false,
    expiresAt: DateTime.tryParse(json['expiresAt'] as String? ?? ''),
    canonPriority: _enum(
      CanonPriority.values,
      json['canonPriority'],
      CanonPriority.confirmedMemory,
    ),
    metadata: _map(json['metadata']),
  );
}

class KnowledgeRelation {
  const KnowledgeRelation({
    required this.id,
    required this.subjectId,
    required this.type,
    required this.objectId,
    required this.createdAt,
    this.confidence = MemoryConfidence.confirmed,
    this.sourceMemoryId,
    this.active = true,
  });
  final String id, subjectId, objectId;
  final KnowledgeRelationType type;
  final MemoryConfidence confidence;
  final DateTime createdAt;
  final String? sourceMemoryId;
  final bool active;
  Map<String, Object?> toJson() => {
    'id': id,
    'subjectId': subjectId,
    'type': type.name,
    'objectId': objectId,
    'confidence': confidence.name,
    'createdAt': createdAt.toIso8601String(),
    'sourceMemoryId': sourceMemoryId,
    'active': active,
  };
  factory KnowledgeRelation.fromJson(Map<String, Object?> json) =>
      KnowledgeRelation(
        id: json['id'] as String? ?? '',
        subjectId: json['subjectId'] as String? ?? '',
        type: _enum(
          KnowledgeRelationType.values,
          json['type'],
          KnowledgeRelationType.knows,
        ),
        objectId: json['objectId'] as String? ?? '',
        confidence: _enum(
          MemoryConfidence.values,
          json['confidence'],
          MemoryConfidence.confirmed,
        ),
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
        sourceMemoryId: json['sourceMemoryId'] as String?,
        active: json['active'] as bool? ?? true,
      );
}

class PromiseMemory {
  const PromiseMemory({
    required this.id,
    required this.promiser,
    required this.promiseTo,
    required this.content,
    required this.createdAt,
    this.status = PromiseStatus.active,
    this.deadline,
    this.resolvedAt,
    this.memoryId,
  });
  final String id, promiser, promiseTo, content;
  final PromiseStatus status;
  final DateTime createdAt;
  final DateTime? deadline, resolvedAt;
  final String? memoryId;
  PromiseMemory copyWith({PromiseStatus? status, DateTime? resolvedAt}) =>
      PromiseMemory(
        id: id,
        promiser: promiser,
        promiseTo: promiseTo,
        content: content,
        createdAt: createdAt,
        status: status ?? this.status,
        deadline: deadline,
        resolvedAt: resolvedAt ?? this.resolvedAt,
        memoryId: memoryId,
      );
  Map<String, Object?> toJson() => {
    'id': id,
    'promiser': promiser,
    'promiseTo': promiseTo,
    'content': content,
    'status': status.name,
    'createdAt': createdAt.toIso8601String(),
    'deadline': deadline?.toIso8601String(),
    'resolvedAt': resolvedAt?.toIso8601String(),
    'memoryId': memoryId,
  };
  factory PromiseMemory.fromJson(Map<String, Object?> json) => PromiseMemory(
    id: json['id'] as String? ?? '',
    promiser: json['promiser'] as String? ?? '',
    promiseTo: json['promiseTo'] as String? ?? '',
    content: json['content'] as String? ?? '',
    status: _enum(PromiseStatus.values, json['status'], PromiseStatus.active),
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    deadline: DateTime.tryParse(json['deadline'] as String? ?? ''),
    resolvedAt: DateTime.tryParse(json['resolvedAt'] as String? ?? ''),
    memoryId: json['memoryId'] as String?,
  );
}

class RelationshipHistory {
  const RelationshipHistory({
    required this.id,
    required this.npcId,
    required this.playerId,
    required this.change,
    required this.reason,
    required this.createdAt,
    this.sourceEventId,
  });
  final String id, npcId, playerId, reason;
  final int change;
  final DateTime createdAt;
  final String? sourceEventId;
  Map<String, Object?> toJson() => {
    'id': id,
    'npcId': npcId,
    'playerId': playerId,
    'change': change,
    'reason': reason,
    'createdAt': createdAt.toIso8601String(),
    'sourceEventId': sourceEventId,
  };
  factory RelationshipHistory.fromJson(Map<String, Object?> json) =>
      RelationshipHistory(
        id: json['id'] as String? ?? '',
        npcId: json['npcId'] as String? ?? '',
        playerId: json['playerId'] as String? ?? '',
        change: (json['change'] as num?)?.toInt() ?? 0,
        reason: json['reason'] as String? ?? '',
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
        sourceEventId: json['sourceEventId'] as String?,
      );
}

class StoryThread {
  const StoryThread({
    required this.id,
    required this.title,
    required this.description,
    required this.createdAt,
    this.status = StoryThreadStatus.open,
    this.relatedEntityIds = const [],
    this.updatedAt,
    this.gmOnly = false,
  });
  final String id, title, description;
  final StoryThreadStatus status;
  final List<String> relatedEntityIds;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final bool gmOnly;
  StoryThread copyWith({
    String? title,
    String? description,
    StoryThreadStatus? status,
    List<String>? relatedEntityIds,
    DateTime? updatedAt,
    bool? gmOnly,
  }) => StoryThread(
    id: id,
    title: title ?? this.title,
    description: description ?? this.description,
    status: status ?? this.status,
    relatedEntityIds: relatedEntityIds ?? this.relatedEntityIds,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    gmOnly: gmOnly ?? this.gmOnly,
  );
  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'status': status.name,
    'relatedEntityIds': relatedEntityIds,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt?.toIso8601String(),
    'gmOnly': gmOnly,
  };
  factory StoryThread.fromJson(Map<String, Object?> json) => StoryThread(
    id: json['id'] as String? ?? '',
    title: json['title'] as String? ?? '',
    description: json['description'] as String? ?? '',
    status: _enum(
      StoryThreadStatus.values,
      json['status'],
      StoryThreadStatus.open,
    ),
    relatedEntityIds: _strings(json['relatedEntityIds']),
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
    gmOnly: json['gmOnly'] as bool? ?? false,
  );
}

class MemoryState {
  const MemoryState({
    this.entries = const [],
    this.knowledgeRelations = const [],
    this.promises = const [],
    this.relationshipHistory = const [],
    this.storyThreads = const [],
    this.sessionSummary = '',
    this.chapterSummaries = const {},
    this.sceneSummaries = const {},
    this.companionSummaries = const {},
    this.lastExtractionEventIndex = 0,
    this.actionCountSinceExtraction = 0,
  });
  final List<MemoryEntry> entries;
  final List<KnowledgeRelation> knowledgeRelations;
  final List<PromiseMemory> promises;
  final List<RelationshipHistory> relationshipHistory;
  final List<StoryThread> storyThreads;
  final String sessionSummary;
  final Map<String, String> chapterSummaries,
      sceneSummaries,
      companionSummaries;
  final int lastExtractionEventIndex, actionCountSinceExtraction;

  MemoryState copyWith({
    List<MemoryEntry>? entries,
    List<KnowledgeRelation>? knowledgeRelations,
    List<PromiseMemory>? promises,
    List<RelationshipHistory>? relationshipHistory,
    List<StoryThread>? storyThreads,
    String? sessionSummary,
    Map<String, String>? chapterSummaries,
    Map<String, String>? sceneSummaries,
    Map<String, String>? companionSummaries,
    int? lastExtractionEventIndex,
    int? actionCountSinceExtraction,
  }) => MemoryState(
    entries: entries ?? this.entries,
    knowledgeRelations: knowledgeRelations ?? this.knowledgeRelations,
    promises: promises ?? this.promises,
    relationshipHistory: relationshipHistory ?? this.relationshipHistory,
    storyThreads: storyThreads ?? this.storyThreads,
    sessionSummary: sessionSummary ?? this.sessionSummary,
    chapterSummaries: chapterSummaries ?? this.chapterSummaries,
    sceneSummaries: sceneSummaries ?? this.sceneSummaries,
    companionSummaries: companionSummaries ?? this.companionSummaries,
    lastExtractionEventIndex:
        lastExtractionEventIndex ?? this.lastExtractionEventIndex,
    actionCountSinceExtraction:
        actionCountSinceExtraction ?? this.actionCountSinceExtraction,
  );
  Map<String, Object?> toJson() => {
    'entries': entries.map((value) => value.toJson()).toList(),
    'knowledgeRelations': knowledgeRelations
        .map((value) => value.toJson())
        .toList(),
    'promises': promises.map((value) => value.toJson()).toList(),
    'relationshipHistory': relationshipHistory
        .map((value) => value.toJson())
        .toList(),
    'storyThreads': storyThreads.map((value) => value.toJson()).toList(),
    'sessionSummary': sessionSummary,
    'chapterSummaries': chapterSummaries,
    'sceneSummaries': sceneSummaries,
    'companionSummaries': companionSummaries,
    'lastExtractionEventIndex': lastExtractionEventIndex,
    'actionCountSinceExtraction': actionCountSinceExtraction,
  };
  factory MemoryState.fromJson(Map<String, Object?> json) => MemoryState(
    entries: (json['entries'] as List? ?? const [])
        .whereType<Map>()
        .map((value) => MemoryEntry.fromJson(value.cast<String, Object?>()))
        .toList(),
    knowledgeRelations: (json['knowledgeRelations'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (value) => KnowledgeRelation.fromJson(value.cast<String, Object?>()),
        )
        .toList(),
    promises: (json['promises'] as List? ?? const [])
        .whereType<Map>()
        .map((value) => PromiseMemory.fromJson(value.cast<String, Object?>()))
        .toList(),
    relationshipHistory: (json['relationshipHistory'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (value) =>
              RelationshipHistory.fromJson(value.cast<String, Object?>()),
        )
        .toList(),
    storyThreads: (json['storyThreads'] as List? ?? const [])
        .whereType<Map>()
        .map((value) => StoryThread.fromJson(value.cast<String, Object?>()))
        .toList(),
    sessionSummary: json['sessionSummary'] as String? ?? '',
    chapterSummaries: (json['chapterSummaries'] as Map? ?? const {}).map(
      (key, value) => MapEntry(key.toString(), value.toString()),
    ),
    sceneSummaries: (json['sceneSummaries'] as Map? ?? const {}).map(
      (key, value) => MapEntry(key.toString(), value.toString()),
    ),
    companionSummaries: (json['companionSummaries'] as Map? ?? const {}).map(
      (key, value) => MapEntry(key.toString(), value.toString()),
    ),
    lastExtractionEventIndex:
        (json['lastExtractionEventIndex'] as num?)?.toInt() ?? 0,
    actionCountSinceExtraction:
        (json['actionCountSinceExtraction'] as num?)?.toInt() ?? 0,
  );
}
