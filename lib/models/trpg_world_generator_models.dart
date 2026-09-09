enum WorldGenerationLevel { quick, normal, detailed }

enum GeneratedLocationType { region, city, village, dungeon, wilderness, site }

enum GeneratedNpcRank { main, important, normal }

enum WorldSecretScope { world, faction, npc, location, quest }

List<String> _strings(Object? value) => value is List
    ? value.map((item) => item.toString()).toList()
    : const <String>[];

Map<String, Object?> _map(Object? value) => value is Map
    ? value.map((key, item) => MapEntry(key.toString(), item))
    : const <String, Object?>{};

T _enumValue<T extends Enum>(List<T> values, Object? raw, T fallback) =>
    values.where((item) => item.name == raw).firstOrNull ?? fallback;

class WorldSeed {
  const WorldSeed({
    required this.theme,
    required this.genre,
    required this.tone,
    required this.era,
    required this.technologyLevel,
    required this.magicLevel,
    required this.difficulty,
    required this.playerCount,
    required this.campaignLength,
    this.level = WorldGenerationLevel.normal,
    this.specialRules = const [],
    this.keywords = const [],
    this.referenceWorks = const [],
    this.favoriteCharacters = const [],
    this.forbiddenElements = const [],
    this.worldRules = const [],
  });

  final String theme;
  final String genre;
  final String tone;
  final String era;
  final String technologyLevel;
  final String magicLevel;
  final String difficulty;
  final int playerCount;
  final String campaignLength;
  final WorldGenerationLevel level;
  final List<String> specialRules;
  final List<String> keywords;
  final List<String> referenceWorks;
  final List<String> favoriteCharacters;
  final List<String> forbiddenElements;
  final List<String> worldRules;

  bool get isEmpty => theme.trim().isEmpty && genre.trim().isEmpty;

  Map<String, Object?> toJson() => {
    'theme': theme,
    'genre': genre,
    'tone': tone,
    'era': era,
    'technologyLevel': technologyLevel,
    'magicLevel': magicLevel,
    'difficulty': difficulty,
    'playerCount': playerCount,
    'campaignLength': campaignLength,
    'level': level.name,
    'specialRules': specialRules,
    'keywords': keywords,
    'referenceWorks': referenceWorks,
    'favoriteCharacters': favoriteCharacters,
    'forbiddenElements': forbiddenElements,
    'worldRules': worldRules,
  };

  factory WorldSeed.fromJson(Map<String, Object?> json) => WorldSeed(
    theme: json['theme'] as String? ?? '',
    genre: json['genre'] as String? ?? '',
    tone: json['tone'] as String? ?? '',
    era: json['era'] as String? ?? '',
    technologyLevel: json['technologyLevel'] as String? ?? '',
    magicLevel: json['magicLevel'] as String? ?? '',
    difficulty: json['difficulty'] as String? ?? '普通',
    playerCount: (json['playerCount'] as num?)?.toInt() ?? 1,
    campaignLength: json['campaignLength'] as String? ?? '',
    level: _enumValue(
      WorldGenerationLevel.values,
      json['level'],
      WorldGenerationLevel.normal,
    ),
    specialRules: _strings(json['specialRules']),
    keywords: _strings(json['keywords']),
    referenceWorks: _strings(json['referenceWorks']),
    favoriteCharacters: _strings(json['favoriteCharacters']),
    forbiddenElements: _strings(json['forbiddenElements']),
    worldRules: _strings(json['worldRules']),
  );
}

class WorldHistoryEvent {
  const WorldHistoryEvent({
    required this.eventId,
    required this.time,
    required this.description,
    this.importance = 5,
    this.affectedRegions = const [],
  });

  final String eventId;
  final String time;
  final String description;
  final int importance;
  final List<String> affectedRegions;

  Map<String, Object?> toJson() => {
    'eventId': eventId,
    'time': time,
    'description': description,
    'importance': importance,
    'affectedRegions': affectedRegions,
  };

  factory WorldHistoryEvent.fromJson(Map<String, Object?> json) =>
      WorldHistoryEvent(
        eventId: json['eventId'] as String? ?? '',
        time: json['time'] as String? ?? '',
        description: json['description'] as String? ?? '',
        importance: (json['importance'] as num?)?.toInt() ?? 5,
        affectedRegions: _strings(json['affectedRegions']),
      );
}

class LocationDefinition {
  const LocationDefinition({
    required this.id,
    required this.name,
    required this.description,
    this.type = GeneratedLocationType.site,
    this.parentLocation,
    this.connectedLocations = const [],
    this.background = '',
    this.population = 0,
    this.dangerLevel = 0,
    this.resources = const [],
    this.tags = const [],
    this.hidden = false,
  });

  final String id;
  final String name;
  final String description;
  final GeneratedLocationType type;
  final String? parentLocation;
  final List<String> connectedLocations;
  final String background;
  final int population;
  final int dangerLevel;
  final List<String> resources;
  final List<String> tags;
  final bool hidden;

  LocationDefinition copyWith({
    String? parentLocation,
    List<String>? connectedLocations,
  }) => LocationDefinition(
    id: id,
    name: name,
    description: description,
    type: type,
    parentLocation: parentLocation ?? this.parentLocation,
    connectedLocations: connectedLocations ?? this.connectedLocations,
    background: background,
    population: population,
    dangerLevel: dangerLevel,
    resources: resources,
    tags: tags,
    hidden: hidden,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'type': type.name,
    'parentLocation': parentLocation,
    'connectedLocations': connectedLocations,
    'background': background,
    'population': population,
    'dangerLevel': dangerLevel,
    'resources': resources,
    'tags': tags,
    'hidden': hidden,
  };

  factory LocationDefinition.fromJson(Map<String, Object?> json) =>
      LocationDefinition(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '未命名地点',
        description: json['description'] as String? ?? '',
        type: _enumValue(
          GeneratedLocationType.values,
          json['type'],
          GeneratedLocationType.site,
        ),
        parentLocation: json['parentLocation'] as String?,
        connectedLocations: _strings(json['connectedLocations']),
        background: json['background'] as String? ?? '',
        population: (json['population'] as num?)?.toInt() ?? 0,
        dangerLevel: (json['dangerLevel'] as num?)?.toInt() ?? 0,
        resources: _strings(json['resources']),
        tags: _strings(json['tags']),
        hidden: json['hidden'] as bool? ?? false,
      );
}

class FactionDefinition {
  const FactionDefinition({
    required this.id,
    required this.name,
    required this.goal,
    required this.leaderNpcId,
    required this.territoryLocationIds,
    this.resources = const [],
    this.secret = '',
    this.tags = const [],
  });

  final String id;
  final String name;
  final String goal;
  final String leaderNpcId;
  final List<String> territoryLocationIds;
  final List<String> resources;
  final String secret;
  final List<String> tags;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'goal': goal,
    'leaderNpcId': leaderNpcId,
    'territoryLocationIds': territoryLocationIds,
    'resources': resources,
    'secret': secret,
    'tags': tags,
  };

  factory FactionDefinition.fromJson(Map<String, Object?> json) =>
      FactionDefinition(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '未命名势力',
        goal: json['goal'] as String? ?? '',
        leaderNpcId: json['leaderNpcId'] as String? ?? '',
        territoryLocationIds: _strings(json['territoryLocationIds']),
        resources: _strings(json['resources']),
        secret: json['secret'] as String? ?? '',
        tags: _strings(json['tags']),
      );
}

class FactionRelationshipDefinition {
  const FactionRelationshipDefinition({
    required this.fromFactionId,
    required this.toFactionId,
    required this.type,
    this.score = 0,
    this.reason = '',
    this.hidden = false,
  });

  final String fromFactionId;
  final String toFactionId;
  final String type;
  final int score;
  final String reason;
  final bool hidden;

  Map<String, Object?> toJson() => {
    'fromFactionId': fromFactionId,
    'toFactionId': toFactionId,
    'type': type,
    'score': score,
    'reason': reason,
    'hidden': hidden,
  };

  factory FactionRelationshipDefinition.fromJson(Map<String, Object?> json) =>
      FactionRelationshipDefinition(
        fromFactionId: json['fromFactionId'] as String? ?? '',
        toFactionId: json['toFactionId'] as String? ?? '',
        type: json['type'] as String? ?? 'neutral',
        score: (json['score'] as num?)?.toInt() ?? 0,
        reason: json['reason'] as String? ?? '',
        hidden: json['hidden'] as bool? ?? false,
      );
}

class GeneratedNpcDefinition {
  const GeneratedNpcDefinition({
    required this.id,
    required this.name,
    required this.age,
    required this.role,
    required this.personality,
    required this.goal,
    required this.locationId,
    this.rank = GeneratedNpcRank.normal,
    this.secret = '',
    this.factionId,
    this.relationships = const {},
    this.tags = const [],
  });

  final String id;
  final String name;
  final int age;
  final String role;
  final String personality;
  final String goal;
  final String secret;
  final String locationId;
  final String? factionId;
  final GeneratedNpcRank rank;
  final Map<String, int> relationships;
  final List<String> tags;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'age': age,
    'role': role,
    'personality': personality,
    'goal': goal,
    'secret': secret,
    'locationId': locationId,
    'factionId': factionId,
    'rank': rank.name,
    'relationships': relationships,
    'tags': tags,
  };

  factory GeneratedNpcDefinition.fromJson(Map<String, Object?> json) =>
      GeneratedNpcDefinition(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '未命名人物',
        age: (json['age'] as num?)?.toInt() ?? 30,
        role: json['role'] as String? ?? '居民',
        personality: json['personality'] as String? ?? '',
        goal: json['goal'] as String? ?? '',
        secret: json['secret'] as String? ?? '',
        locationId: json['locationId'] as String? ?? '',
        factionId: json['factionId'] as String?,
        rank: _enumValue(
          GeneratedNpcRank.values,
          json['rank'],
          GeneratedNpcRank.normal,
        ),
        relationships: json['relationships'] is Map
            ? (json['relationships'] as Map).map(
                (key, value) =>
                    MapEntry(key.toString(), (value as num?)?.toInt() ?? 0),
              )
            : const {},
        tags: _strings(json['tags']),
      );
}

class GeneratedQuestDefinition {
  const GeneratedQuestDefinition({
    required this.id,
    required this.title,
    required this.description,
    required this.giverNpcId,
    required this.locationId,
    this.objectives = const [],
    this.rewards = const [],
    this.failure = '',
    this.branches = const [],
    this.prerequisiteQuestIds = const [],
  });

  final String id;
  final String title;
  final String description;
  final String giverNpcId;
  final String locationId;
  final List<String> objectives;
  final List<String> rewards;
  final String failure;
  final List<Map<String, Object?>> branches;
  final List<String> prerequisiteQuestIds;

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'giverNpcId': giverNpcId,
    'locationId': locationId,
    'objectives': objectives,
    'rewards': rewards,
    'failure': failure,
    'branches': branches,
    'prerequisiteQuestIds': prerequisiteQuestIds,
  };

  factory GeneratedQuestDefinition.fromJson(Map<String, Object?> json) =>
      GeneratedQuestDefinition(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '未命名任务',
        description: json['description'] as String? ?? '',
        giverNpcId: json['giverNpcId'] as String? ?? '',
        locationId: json['locationId'] as String? ?? '',
        objectives: _strings(json['objectives']),
        rewards: _strings(json['rewards']),
        failure: json['failure'] as String? ?? '',
        branches: (json['branches'] as List? ?? const [])
            .whereType<Map>()
            .map((item) => item.cast<String, Object?>())
            .toList(),
        prerequisiteQuestIds: _strings(json['prerequisiteQuestIds']),
      );
}

class EnemyEcologyDefinition {
  const EnemyEcologyDefinition({
    required this.id,
    required this.name,
    required this.regionLocationIds,
    required this.behavior,
    required this.population,
    required this.weaknesses,
    required this.origin,
    this.dangerLevel = 50,
  });

  final String id;
  final String name;
  final List<String> regionLocationIds;
  final String behavior;
  final String population;
  final List<String> weaknesses;
  final String origin;
  final int dangerLevel;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'regionLocationIds': regionLocationIds,
    'behavior': behavior,
    'population': population,
    'weaknesses': weaknesses,
    'origin': origin,
    'dangerLevel': dangerLevel,
  };

  factory EnemyEcologyDefinition.fromJson(Map<String, Object?> json) =>
      EnemyEcologyDefinition(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '未知敌人',
        regionLocationIds: _strings(json['regionLocationIds']),
        behavior: json['behavior'] as String? ?? '',
        population: json['population'] as String? ?? '',
        weaknesses: _strings(json['weaknesses']),
        origin: json['origin'] as String? ?? '',
        dangerLevel: (json['dangerLevel'] as num?)?.toInt() ?? 50,
      );
}

class WorldSecretDefinition {
  const WorldSecretDefinition({
    required this.id,
    required this.title,
    required this.content,
    this.scope = WorldSecretScope.world,
    this.ownerEntityId,
    this.knownByEntityIds = const [],
    this.revealed = false,
  });

  final String id;
  final String title;
  final String content;
  final WorldSecretScope scope;
  final String? ownerEntityId;
  final List<String> knownByEntityIds;
  final bool revealed;

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'content': content,
    'scope': scope.name,
    'ownerEntityId': ownerEntityId,
    'knownByEntityIds': knownByEntityIds,
    'revealed': revealed,
  };

  factory WorldSecretDefinition.fromJson(Map<String, Object?> json) =>
      WorldSecretDefinition(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '未命名秘密',
        content: json['content'] as String? ?? '',
        scope: _enumValue(
          WorldSecretScope.values,
          json['scope'],
          WorldSecretScope.world,
        ),
        ownerEntityId: json['ownerEntityId'] as String?,
        knownByEntityIds: _strings(json['knownByEntityIds']),
        revealed: json['revealed'] as bool? ?? false,
      );
}

class StartingScenarioDefinition {
  const StartingScenarioDefinition({
    required this.locationId,
    required this.npcIds,
    required this.conflict,
    required this.playerGoal,
    required this.opening,
  });

  final String locationId;
  final List<String> npcIds;
  final String conflict;
  final String playerGoal;
  final String opening;

  Map<String, Object?> toJson() => {
    'locationId': locationId,
    'npcIds': npcIds,
    'conflict': conflict,
    'playerGoal': playerGoal,
    'opening': opening,
  };

  factory StartingScenarioDefinition.fromJson(Map<String, Object?> json) =>
      StartingScenarioDefinition(
        locationId: json['locationId'] as String? ?? '',
        npcIds: _strings(json['npcIds']),
        conflict: json['conflict'] as String? ?? '',
        playerGoal: json['playerGoal'] as String? ?? '',
        opening: json['opening'] as String? ?? '',
      );
}

class WorldBlueprint {
  const WorldBlueprint({
    required this.worldName,
    required this.summary,
    required this.history,
    required this.eras,
    required this.locations,
    required this.factions,
    required this.factionRelationships,
    required this.npcs,
    required this.quests,
    required this.items,
    required this.enemies,
    required this.secrets,
    required this.startingScenario,
    this.worldRules = const [],
    this.generationNotes = const {},
  });

  final String worldName;
  final String summary;
  final List<WorldHistoryEvent> history;
  final List<String> eras;
  final List<LocationDefinition> locations;
  final List<FactionDefinition> factions;
  final List<FactionRelationshipDefinition> factionRelationships;
  final List<GeneratedNpcDefinition> npcs;
  final List<GeneratedQuestDefinition> quests;
  final List<Map<String, Object?>> items;
  final List<EnemyEcologyDefinition> enemies;
  final List<WorldSecretDefinition> secrets;
  final StartingScenarioDefinition startingScenario;
  final List<String> worldRules;
  final Map<String, Object?> generationNotes;

  WorldBlueprint copyWith({
    List<WorldHistoryEvent>? history,
    List<LocationDefinition>? locations,
    List<FactionDefinition>? factions,
    List<FactionRelationshipDefinition>? factionRelationships,
    List<GeneratedNpcDefinition>? npcs,
    List<GeneratedQuestDefinition>? quests,
    List<Map<String, Object?>>? items,
    List<EnemyEcologyDefinition>? enemies,
    List<WorldSecretDefinition>? secrets,
    StartingScenarioDefinition? startingScenario,
    Map<String, Object?>? generationNotes,
  }) => WorldBlueprint(
    worldName: worldName,
    summary: summary,
    history: history ?? this.history,
    eras: eras,
    locations: locations ?? this.locations,
    factions: factions ?? this.factions,
    factionRelationships: factionRelationships ?? this.factionRelationships,
    npcs: npcs ?? this.npcs,
    quests: quests ?? this.quests,
    items: items ?? this.items,
    enemies: enemies ?? this.enemies,
    secrets: secrets ?? this.secrets,
    startingScenario: startingScenario ?? this.startingScenario,
    worldRules: worldRules,
    generationNotes: generationNotes ?? this.generationNotes,
  );

  WorldBlueprint publicView() => WorldBlueprint(
    worldName: worldName,
    summary: summary,
    history: history,
    eras: eras,
    locations: locations.where((item) => !item.hidden).toList(),
    factions: factions
        .map(
          (item) => FactionDefinition(
            id: item.id,
            name: item.name,
            goal: item.goal,
            leaderNpcId: item.leaderNpcId,
            territoryLocationIds: item.territoryLocationIds,
            resources: item.resources,
            tags: item.tags,
          ),
        )
        .toList(),
    factionRelationships: factionRelationships
        .where((item) => !item.hidden)
        .toList(),
    npcs: npcs
        .map(
          (item) => GeneratedNpcDefinition(
            id: item.id,
            name: item.name,
            age: item.age,
            role: item.role,
            personality: item.personality,
            goal: item.goal,
            locationId: item.locationId,
            factionId: item.factionId,
            rank: item.rank,
            relationships: item.relationships,
            tags: item.tags,
          ),
        )
        .toList(),
    quests: quests,
    items: items,
    enemies: enemies,
    secrets: secrets.where((item) => item.revealed).toList(),
    startingScenario: startingScenario,
    worldRules: worldRules,
    generationNotes: const {},
  );

  Map<String, Object?> toJson() => {
    'worldName': worldName,
    'summary': summary,
    'history': history.map((item) => item.toJson()).toList(),
    'eras': eras,
    'locations': locations.map((item) => item.toJson()).toList(),
    'factions': factions.map((item) => item.toJson()).toList(),
    'factionRelationships': factionRelationships
        .map((item) => item.toJson())
        .toList(),
    'npcs': npcs.map((item) => item.toJson()).toList(),
    'quests': quests.map((item) => item.toJson()).toList(),
    'items': items,
    'enemies': enemies.map((item) => item.toJson()).toList(),
    'secrets': secrets.map((item) => item.toJson()).toList(),
    'startingScenario': startingScenario.toJson(),
    'worldRules': worldRules,
    'generationNotes': generationNotes,
  };

  factory WorldBlueprint.fromJson(Map<String, Object?> json) => WorldBlueprint(
    worldName: json['worldName'] as String? ?? '未命名世界',
    summary: json['summary'] as String? ?? '',
    history: (json['history'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => WorldHistoryEvent.fromJson(item.cast<String, Object?>()))
        .toList(),
    eras: _strings(json['eras']),
    locations: (json['locations'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (item) => LocationDefinition.fromJson(item.cast<String, Object?>()),
        )
        .toList(),
    factions: (json['factions'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => FactionDefinition.fromJson(item.cast<String, Object?>()))
        .toList(),
    factionRelationships: (json['factionRelationships'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (item) => FactionRelationshipDefinition.fromJson(
            item.cast<String, Object?>(),
          ),
        )
        .toList(),
    npcs: (json['npcs'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (item) =>
              GeneratedNpcDefinition.fromJson(item.cast<String, Object?>()),
        )
        .toList(),
    quests: (json['quests'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (item) =>
              GeneratedQuestDefinition.fromJson(item.cast<String, Object?>()),
        )
        .toList(),
    items: (json['items'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => item.cast<String, Object?>())
        .toList(),
    enemies: (json['enemies'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (item) =>
              EnemyEcologyDefinition.fromJson(item.cast<String, Object?>()),
        )
        .toList(),
    secrets: (json['secrets'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (item) =>
              WorldSecretDefinition.fromJson(item.cast<String, Object?>()),
        )
        .toList(),
    startingScenario: StartingScenarioDefinition.fromJson(
      _map(json['startingScenario']),
    ),
    worldRules: _strings(json['worldRules']),
    generationNotes: _map(json['generationNotes']),
  );
}

class WorldGenerationState {
  const WorldGenerationState({
    this.seed,
    this.blueprint,
    this.generatedData = const {},
    this.generationVersion = 0,
    this.generationId = '',
    this.parentGenerationId,
    this.generatedLocationIds = const [],
    this.lockedAfterPlay = false,
  });

  final WorldSeed? seed;
  final WorldBlueprint? blueprint;
  final Map<String, Object?> generatedData;
  final int generationVersion;
  final String generationId;
  final String? parentGenerationId;
  final List<String> generatedLocationIds;
  final bool lockedAfterPlay;

  bool get isGenerated => seed != null && blueprint != null;

  WorldGenerationState copyWith({
    WorldSeed? seed,
    WorldBlueprint? blueprint,
    Map<String, Object?>? generatedData,
    int? generationVersion,
    String? generationId,
    String? parentGenerationId,
    List<String>? generatedLocationIds,
    bool? lockedAfterPlay,
  }) => WorldGenerationState(
    seed: seed ?? this.seed,
    blueprint: blueprint ?? this.blueprint,
    generatedData: generatedData ?? this.generatedData,
    generationVersion: generationVersion ?? this.generationVersion,
    generationId: generationId ?? this.generationId,
    parentGenerationId: parentGenerationId ?? this.parentGenerationId,
    generatedLocationIds: generatedLocationIds ?? this.generatedLocationIds,
    lockedAfterPlay: lockedAfterPlay ?? this.lockedAfterPlay,
  );

  WorldGenerationState publicView() =>
      copyWith(blueprint: blueprint?.publicView(), generatedData: const {});

  Map<String, Object?> toJson() => {
    'worldSeed': seed?.toJson(),
    'worldBlueprint': blueprint?.toJson(),
    'generatedData': generatedData,
    'generationVersion': generationVersion,
    'generationId': generationId,
    'parentGenerationId': parentGenerationId,
    'generatedLocationIds': generatedLocationIds,
    'lockedAfterPlay': lockedAfterPlay,
  };

  factory WorldGenerationState.fromJson(Map<String, Object?> json) =>
      WorldGenerationState(
        seed: json['worldSeed'] is Map
            ? WorldSeed.fromJson(_map(json['worldSeed']))
            : null,
        blueprint: json['worldBlueprint'] is Map
            ? WorldBlueprint.fromJson(_map(json['worldBlueprint']))
            : null,
        generatedData: _map(json['generatedData']),
        generationVersion: (json['generationVersion'] as num?)?.toInt() ?? 0,
        generationId: json['generationId'] as String? ?? '',
        parentGenerationId: json['parentGenerationId'] as String?,
        generatedLocationIds: _strings(json['generatedLocationIds']),
        lockedAfterPlay: json['lockedAfterPlay'] as bool? ?? false,
      );
}
