import 'package:uuid/uuid.dart';

import 'character.dart';
import 'trpg_models.dart';
import 'trpg_presentation_models.dart';
import 'voice_settings.dart';

const campaignSchemaVersion = 4;
const _campaignUuid = Uuid();

enum CampaignNpcRole { npc, companion, majorNpc, enemy }

enum CompanionParticipationPolicy { low, normal, high }

enum CampaignDifficulty { easy, normal, hard, expert }

enum CampaignType { standard, holyGrailWar }

CampaignType _campaignTypeOr(Object? raw) => switch (raw?.toString()) {
  'HOLY_GRAIL_WAR' || 'holyGrailWar' => CampaignType.holyGrailWar,
  _ => CampaignType.standard,
};

T _enumOr<T extends Enum>(List<T> values, Object? raw, T fallback) =>
    values.where((value) => value.name == raw).firstOrNull ?? fallback;

List<String> _stringList(Object? raw) => raw is List
    ? raw.map((value) => value.toString()).toList()
    : const <String>[];

Map<String, Object?> _objectMap(Object? raw) => raw is Map
    ? raw.map((key, value) => MapEntry(key.toString(), value))
    : const <String, Object?>{};

class CampaignTrigger {
  const CampaignTrigger({
    required this.id,
    required this.conditionType,
    required this.key,
    this.operator = 'equals',
    this.value = true,
    this.effects = const [],
  });

  final String id, conditionType, key, operator;
  final Object? value;
  final List<Map<String, Object?>> effects;

  Map<String, Object?> toJson() => {
    'id': id,
    'conditionType': conditionType,
    'key': key,
    'operator': operator,
    'value': value,
    'effects': effects,
  };

  factory CampaignTrigger.fromJson(Map<String, Object?> json) =>
      CampaignTrigger(
        id: json['id'] as String? ?? _campaignUuid.v4(),
        conditionType: json['conditionType'] as String? ?? 'flag',
        key: json['key'] as String? ?? '',
        operator: json['operator'] as String? ?? 'equals',
        value: json['value'],
        effects: (json['effects'] as List? ?? const [])
            .whereType<Map>()
            .map((value) => value.cast<String, Object?>())
            .toList(),
      );
}

class StoryNode {
  const StoryNode({
    required this.id,
    required this.title,
    this.description = '',
    this.prerequisites = const [],
    this.triggers = const [],
    this.effects = const [],
    this.nextNodes = const [],
    this.hidden = false,
    this.gmNotes = '',
  });

  final String id, title, description, gmNotes;
  final List<String> prerequisites, nextNodes;
  final List<CampaignTrigger> triggers;
  final List<Map<String, Object?>> effects;
  final bool hidden;

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'prerequisites': prerequisites,
    'triggers': triggers.map((value) => value.toJson()).toList(),
    'effects': effects,
    'nextNodes': nextNodes,
    'hidden': hidden,
    'gmNotes': gmNotes,
  };

  factory StoryNode.fromJson(Map<String, Object?> json) => StoryNode(
    id: json['id'] as String? ?? _campaignUuid.v4(),
    title: json['title'] as String? ?? '未命名节点',
    description: json['description'] as String? ?? '',
    prerequisites: _stringList(json['prerequisites']),
    triggers: (json['triggers'] as List? ?? const [])
        .whereType<Map>()
        .map((value) => CampaignTrigger.fromJson(value.cast<String, Object?>()))
        .toList(),
    effects: (json['effects'] as List? ?? const [])
        .whereType<Map>()
        .map((value) => value.cast<String, Object?>())
        .toList(),
    nextNodes: _stringList(json['nextNodes']),
    hidden: json['hidden'] as bool? ?? false,
    gmNotes: json['gmNotes'] as String? ?? '',
  );
}

class CampaignChapter {
  const CampaignChapter({
    required this.id,
    required this.title,
    this.description = '',
    this.storyNodes = const [],
  });

  final String id, title, description;
  final List<StoryNode> storyNodes;
  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'storyNodes': storyNodes.map((value) => value.toJson()).toList(),
  };
  factory CampaignChapter.fromJson(Map<String, Object?> json) =>
      CampaignChapter(
        id: json['id'] as String? ?? _campaignUuid.v4(),
        title: json['title'] as String? ?? '未命名章节',
        description: json['description'] as String? ?? '',
        storyNodes: (json['storyNodes'] as List? ?? const [])
            .whereType<Map>()
            .map((value) => StoryNode.fromJson(value.cast<String, Object?>()))
            .toList(),
      );
}

class CampaignAct {
  const CampaignAct({
    required this.id,
    required this.title,
    this.description = '',
    this.chapters = const [],
  });
  final String id, title, description;
  final List<CampaignChapter> chapters;
  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'chapters': chapters.map((value) => value.toJson()).toList(),
  };
  factory CampaignAct.fromJson(Map<String, Object?> json) => CampaignAct(
    id: json['id'] as String? ?? _campaignUuid.v4(),
    title: json['title'] as String? ?? '未命名幕',
    description: json['description'] as String? ?? '',
    chapters: (json['chapters'] as List? ?? const [])
        .whereType<Map>()
        .map((value) => CampaignChapter.fromJson(value.cast<String, Object?>()))
        .toList(),
  );
}

class NPCMemory {
  const NPCMemory({
    required this.id,
    required this.summary,
    required this.createdAt,
    this.importance = 1,
    this.playerId,
  });
  final String id, summary;
  final String? playerId;
  final DateTime createdAt;
  final int importance;
  Map<String, Object?> toJson() => {
    'id': id,
    'summary': summary,
    'playerId': playerId,
    'createdAt': createdAt.toIso8601String(),
    'importance': importance,
  };
  factory NPCMemory.fromJson(Map<String, Object?> json) => NPCMemory(
    id: json['id'] as String? ?? _campaignUuid.v4(),
    summary: json['summary'] as String? ?? '',
    playerId: json['playerId'] as String?,
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    importance: (json['importance'] as num?)?.toInt() ?? 1,
  );
}

class TRPGNPCProfile {
  const TRPGNPCProfile({
    required this.npcId,
    required this.name,
    this.sourceCharacterId,
    this.avatar,
    this.portrait,
    this.portraitVariants = const {},
    this.voice = const CharacterVoiceConfig(),
    this.description = '',
    this.personality = '',
    this.exampleDialogue = '',
    this.role = CampaignNpcRole.npc,
    this.faction = '',
    this.locationId,
    this.relationship = 0,
    this.disposition = 'neutral',
    this.alive = true,
    this.knownToPlayers = false,
    this.privateNotes = '',
    this.stats = const {},
    this.combatProfile = const {},
    this.inventory = const [],
    this.memories = const [],
    this.participationPolicy = CompanionParticipationPolicy.normal,
    this.metadata = const {},
  });

  final String npcId, name, description, personality, exampleDialogue;
  final String? sourceCharacterId, avatar, portrait, locationId;
  final Map<String, String> portraitVariants;
  final CharacterVoiceConfig voice;
  final CampaignNpcRole role;
  final String faction, disposition, privateNotes;
  final int relationship;
  final bool alive, knownToPlayers;
  final Map<String, num> stats;
  final Map<String, Object?> combatProfile, metadata;
  final List<String> inventory;
  final List<NPCMemory> memories;
  final CompanionParticipationPolicy participationPolicy;

  factory TRPGNPCProfile.fromCharacter(
    Character character, {
    CampaignNpcRole role = CampaignNpcRole.npc,
  }) => TRPGNPCProfile(
    npcId: _campaignUuid.v4(),
    sourceCharacterId: character.id,
    name: character.name,
    avatar: character.avatar,
    portrait: character.avatar,
    description: [
      character.description,
      character.appearance,
      character.background,
    ].where((value) => value.trim().isNotEmpty).join('\n'),
    personality: [
      character.personality,
      character.speakingStyle,
      character.goals,
    ].where((value) => value.trim().isNotEmpty).join('\n'),
    exampleDialogue: character.exampleDialogue,
    role: role,
    privateNotes: character.secrets,
    knownToPlayers: true,
  );

  TRPGNPCProfile copyWith({
    int? relationship,
    String? locationId,
    bool? knownToPlayers,
    List<NPCMemory>? memories,
    List<String>? inventory,
  }) => TRPGNPCProfile(
    npcId: npcId,
    sourceCharacterId: sourceCharacterId,
    name: name,
    avatar: avatar,
    portrait: portrait,
    portraitVariants: portraitVariants,
    voice: voice,
    description: description,
    personality: personality,
    exampleDialogue: exampleDialogue,
    role: role,
    faction: faction,
    locationId: locationId ?? this.locationId,
    relationship: (relationship ?? this.relationship).clamp(-100, 100),
    disposition: disposition,
    alive: alive,
    knownToPlayers: knownToPlayers ?? this.knownToPlayers,
    privateNotes: privateNotes,
    stats: stats,
    combatProfile: combatProfile,
    inventory: inventory ?? this.inventory,
    memories: memories ?? this.memories,
    participationPolicy: participationPolicy,
    metadata: metadata,
  );

  Map<String, Object?> toJson() => {
    'npcId': npcId,
    'sourceCharacterId': sourceCharacterId,
    'name': name,
    'avatar': avatar,
    'portrait': portrait,
    'portraitVariants': portraitVariants,
    'voice': voice.toJson(),
    'description': description,
    'personality': personality,
    'exampleDialogue': exampleDialogue,
    'role': role.name,
    'faction': faction,
    'locationId': locationId,
    'relationship': relationship,
    'disposition': disposition,
    'alive': alive,
    'knownToPlayers': knownToPlayers,
    'privateNotes': privateNotes,
    'stats': stats,
    'combatProfile': combatProfile,
    'inventory': inventory,
    'memories': memories.map((value) => value.toJson()).toList(),
    'participationPolicy': participationPolicy.name,
    'metadata': metadata,
  };

  factory TRPGNPCProfile.fromJson(Map<String, Object?> json) => TRPGNPCProfile(
    npcId:
        json['npcId'] as String? ?? json['id'] as String? ?? _campaignUuid.v4(),
    sourceCharacterId: json['sourceCharacterId'] as String?,
    name: json['name'] as String? ?? '未命名 NPC',
    avatar: json['avatar'] as String?,
    portrait: json['portrait'] as String? ?? json['avatar'] as String?,
    portraitVariants: json['portraitVariants'] is Map
        ? (json['portraitVariants'] as Map).map(
            (key, value) => MapEntry(key.toString(), value.toString()),
          )
        : const {},
    voice: json['voice'] is Map
        ? CharacterVoiceConfig.fromJson(
            (json['voice'] as Map).cast<String, Object?>(),
          )
        : const CharacterVoiceConfig(),
    description: json['description'] as String? ?? '',
    personality: json['personality'] as String? ?? '',
    exampleDialogue: json['exampleDialogue'] as String? ?? '',
    role: _enumOr(CampaignNpcRole.values, json['role'], CampaignNpcRole.npc),
    faction: json['faction'] as String? ?? '',
    locationId: json['locationId'] as String?,
    relationship: (json['relationship'] as num?)?.toInt() ?? 0,
    disposition: json['disposition'] as String? ?? 'neutral',
    alive: json['alive'] as bool? ?? true,
    knownToPlayers: json['knownToPlayers'] as bool? ?? false,
    privateNotes: json['privateNotes'] as String? ?? '',
    stats: json['stats'] is Map
        ? (json['stats'] as Map).map(
            (key, value) => MapEntry(key.toString(), value as num),
          )
        : const {},
    combatProfile: _objectMap(json['combatProfile']),
    inventory: _stringList(json['inventory']),
    memories: (json['memories'] as List? ?? const [])
        .whereType<Map>()
        .map((value) => NPCMemory.fromJson(value.cast<String, Object?>()))
        .toList(),
    participationPolicy: _enumOr(
      CompanionParticipationPolicy.values,
      json['participationPolicy'],
      CompanionParticipationPolicy.normal,
    ),
    metadata: _objectMap(json['metadata']),
  );
}

class MapMarker {
  const MapMarker({
    required this.id,
    required this.x,
    required this.y,
    required this.type,
    required this.label,
    this.visibility = InformationVisibility.public,
    this.linkedEntityId,
    this.discovered = true,
  });
  final String id, type, label;
  final double x, y;
  final InformationVisibility visibility;
  final String? linkedEntityId;
  final bool discovered;
  Map<String, Object?> toJson() => {
    'id': id,
    'x': x,
    'y': y,
    'type': type,
    'label': label,
    'visibility': visibility.name,
    'linkedEntityId': linkedEntityId,
    'discovered': discovered,
  };
  factory MapMarker.fromJson(Map<String, Object?> json) => MapMarker(
    id: json['id'] as String? ?? _campaignUuid.v4(),
    x: (json['x'] as num?)?.toDouble() ?? .5,
    y: (json['y'] as num?)?.toDouble() ?? .5,
    type: json['type'] as String? ?? 'custom',
    label: json['label'] as String? ?? '',
    visibility: _enumOr(
      InformationVisibility.values,
      json['visibility'],
      InformationVisibility.public,
    ),
    linkedEntityId: json['linkedEntityId'] as String?,
    discovered: json['discovered'] as bool? ?? true,
  );
}

class CampaignLocation {
  const CampaignLocation({
    required this.id,
    required this.name,
    this.description = '',
    this.mapImage,
    this.sceneImage,
    this.backgroundId,
    this.visualTheme = CampaignVisualTheme.modern,
    this.timeOfDay = '',
    this.weather = '',
    this.ambientId,
    this.bgmId,
    this.discovered = false,
    this.hidden = false,
    this.markers = const [],
    this.gmNotes = '',
  });
  final String id, name, description, gmNotes;
  final String? mapImage, sceneImage, backgroundId, ambientId, bgmId;
  final CampaignVisualTheme visualTheme;
  final String timeOfDay, weather;
  final bool discovered, hidden;
  final List<MapMarker> markers;
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'mapImage': mapImage,
    'sceneImage': sceneImage,
    'backgroundId': backgroundId,
    'visualTheme': visualTheme.name,
    'timeOfDay': timeOfDay,
    'weather': weather,
    'ambientId': ambientId,
    'bgmId': bgmId,
    'discovered': discovered,
    'hidden': hidden,
    'markers': markers.map((value) => value.toJson()).toList(),
    'gmNotes': gmNotes,
  };
  factory CampaignLocation.fromJson(Map<String, Object?> json) =>
      CampaignLocation(
        id: json['id'] as String? ?? _campaignUuid.v4(),
        name: json['name'] as String? ?? '未命名地点',
        description: json['description'] as String? ?? '',
        mapImage: json['mapImage'] as String?,
        sceneImage: json['sceneImage'] as String?,
        backgroundId: json['backgroundId'] as String?,
        visualTheme: _enumOr(
          CampaignVisualTheme.values,
          json['visualTheme'],
          CampaignVisualTheme.modern,
        ),
        timeOfDay: json['timeOfDay'] as String? ?? '',
        weather: json['weather'] as String? ?? '',
        ambientId: json['ambientId'] as String?,
        bgmId: json['bgmId'] as String?,
        discovered: json['discovered'] as bool? ?? false,
        hidden: json['hidden'] as bool? ?? false,
        markers: (json['markers'] as List? ?? const [])
            .whereType<Map>()
            .map((value) => MapMarker.fromJson(value.cast<String, Object?>()))
            .toList(),
        gmNotes: json['gmNotes'] as String? ?? '',
      );
}

class ClueRelation {
  const ClueRelation({required this.entityType, required this.entityId});
  final String entityType, entityId;
  Map<String, Object?> toJson() => {
    'entityType': entityType,
    'entityId': entityId,
  };
  factory ClueRelation.fromJson(Map<String, Object?> json) => ClueRelation(
    entityType: json['entityType'] as String? ?? 'custom',
    entityId: json['entityId'] as String? ?? '',
  );
}

class CampaignClue {
  const CampaignClue({
    required this.id,
    required this.name,
    this.description = '',
    this.source = '',
    this.visibility = InformationVisibility.public,
    this.ownerPlayerIds = const [],
    this.discovered = false,
    this.relations = const [],
    this.gmNotes = '',
  });
  final String id, name, description, source, gmNotes;
  final InformationVisibility visibility;
  final List<String> ownerPlayerIds;
  final bool discovered;
  final List<ClueRelation> relations;
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'source': source,
    'visibility': visibility.name,
    'ownerPlayerIds': ownerPlayerIds,
    'discovered': discovered,
    'relations': relations.map((value) => value.toJson()).toList(),
    'gmNotes': gmNotes,
  };
  factory CampaignClue.fromJson(Map<String, Object?> json) => CampaignClue(
    id: json['id'] as String? ?? _campaignUuid.v4(),
    name: json['name'] as String? ?? '未命名线索',
    description: json['description'] as String? ?? '',
    source: json['source'] as String? ?? '',
    visibility: _enumOr(
      InformationVisibility.values,
      json['visibility'],
      InformationVisibility.public,
    ),
    ownerPlayerIds: _stringList(json['ownerPlayerIds']),
    discovered: json['discovered'] as bool? ?? false,
    relations: (json['relations'] as List? ?? const [])
        .whereType<Map>()
        .map((value) => ClueRelation.fromJson(value.cast<String, Object?>()))
        .toList(),
    gmNotes: json['gmNotes'] as String? ?? '',
  );
}

class CampaignDocument {
  const CampaignDocument({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.schemaVersion = campaignSchemaVersion,
    this.campaignType = CampaignType.standard,
    this.description = '',
    this.cover,
    this.tags = const [],
    this.recommendedPlayers = '1~4',
    this.estimatedLength = '2~4小时',
    this.ruleSystem = '通用规则',
    this.theme = '',
    this.tone = '',
    this.difficulty = CampaignDifficulty.normal,
    this.author = '',
    this.source = CampaignSourceType.local,
    this.opening = '',
    this.systemPrompt = '',
    this.acts = const [],
    this.locations = const [],
    this.npcs = const [],
    this.quests = const [],
    this.clues = const [],
    this.items = const [],
    this.factions = const [],
    this.encounters = const [],
    this.secrets = const [],
    this.endings = const [],
    this.aiGmSettings = const {},
    this.audioAssets = const [],
    this.presentationSettings = const CampaignPresentationSettings(),
    this.metadata = const {},
  });

  final int schemaVersion;
  final CampaignType campaignType;
  final String id, title, description, recommendedPlayers, estimatedLength;
  final String ruleSystem, theme, tone, author, opening, systemPrompt;
  final String? cover;
  final List<String> tags, secrets, endings;
  final CampaignDifficulty difficulty;
  final CampaignSourceType source;
  final DateTime createdAt, updatedAt;
  final List<CampaignAct> acts;
  final List<CampaignLocation> locations;
  final List<TRPGNPCProfile> npcs;
  final List<CampaignClue> clues;
  final List<Map<String, Object?>> quests, items, factions, encounters;
  final Map<String, Object?> aiGmSettings, metadata;
  final List<AudioAsset> audioAssets;
  final CampaignPresentationSettings presentationSettings;

  factory CampaignDocument.blank({String title = '未命名剧本'}) {
    final now = DateTime.now();
    return CampaignDocument(
      id: _campaignUuid.v4(),
      title: title,
      createdAt: now,
      updatedAt: now,
    );
  }

  factory CampaignDocument.fromLegacy(Campaign campaign) {
    final now = DateTime.now();
    return CampaignDocument(
      id: campaign.id,
      title: campaign.title,
      description: campaign.description,
      cover: campaign.cover,
      opening: campaign.opening,
      systemPrompt: campaign.systemPrompt,
      locations: campaign.locations.map(CampaignLocation.fromJson).toList(),
      npcs: campaign.npcs.map(TRPGNPCProfile.fromJson).toList(),
      quests: campaign.quests,
      items: campaign.items,
      factions: campaign.factions,
      encounters: campaign.encounters,
      secrets: campaign.secrets,
      endings: campaign.possibleEndings,
      source: campaign.sourceType,
      createdAt: now,
      updatedAt: now,
      metadata: campaign.metadata,
    );
  }

  CampaignDocument copyWith({
    CampaignType? campaignType,
    String? id,
    String? title,
    String? description,
    String? cover,
    String? recommendedPlayers,
    String? estimatedLength,
    String? ruleSystem,
    String? theme,
    String? tone,
    String? author,
    String? opening,
    String? systemPrompt,
    List<String>? tags,
    CampaignDifficulty? difficulty,
    CampaignSourceType? source,
    DateTime? updatedAt,
    List<CampaignAct>? acts,
    List<CampaignLocation>? locations,
    List<TRPGNPCProfile>? npcs,
    List<Map<String, Object?>>? quests,
    List<CampaignClue>? clues,
    List<Map<String, Object?>>? items,
    List<Map<String, Object?>>? factions,
    List<Map<String, Object?>>? encounters,
    List<String>? secrets,
    List<String>? endings,
    Map<String, Object?>? aiGmSettings,
    List<AudioAsset>? audioAssets,
    CampaignPresentationSettings? presentationSettings,
  }) => CampaignDocument(
    campaignType: campaignType ?? this.campaignType,
    id: id ?? this.id,
    title: title ?? this.title,
    description: description ?? this.description,
    cover: cover ?? this.cover,
    tags: tags ?? this.tags,
    recommendedPlayers: recommendedPlayers ?? this.recommendedPlayers,
    estimatedLength: estimatedLength ?? this.estimatedLength,
    ruleSystem: ruleSystem ?? this.ruleSystem,
    theme: theme ?? this.theme,
    tone: tone ?? this.tone,
    difficulty: difficulty ?? this.difficulty,
    author: author ?? this.author,
    source: source ?? this.source,
    opening: opening ?? this.opening,
    systemPrompt: systemPrompt ?? this.systemPrompt,
    acts: acts ?? this.acts,
    locations: locations ?? this.locations,
    npcs: npcs ?? this.npcs,
    quests: quests ?? this.quests,
    clues: clues ?? this.clues,
    items: items ?? this.items,
    factions: factions ?? this.factions,
    encounters: encounters ?? this.encounters,
    secrets: secrets ?? this.secrets,
    endings: endings ?? this.endings,
    aiGmSettings: aiGmSettings ?? this.aiGmSettings,
    audioAssets: audioAssets ?? this.audioAssets,
    presentationSettings: presentationSettings ?? this.presentationSettings,
    metadata: metadata,
    createdAt: createdAt,
    updatedAt: updatedAt ?? DateTime.now(),
  );

  Campaign toLegacy() => Campaign(
    id: id,
    title: title,
    description: description,
    cover: cover,
    systemPrompt: systemPrompt,
    opening: opening,
    locations: locations.map((value) => value.toJson()).toList(),
    npcs: npcs.map((value) => value.toJson()).toList(),
    factions: factions,
    quests: quests,
    secrets: secrets,
    items: items,
    encounters: encounters,
    possibleEndings: endings,
    sourceType: source,
    metadata: metadata,
  );

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'campaignType': campaignType == CampaignType.holyGrailWar
        ? 'HOLY_GRAIL_WAR'
        : 'STANDARD',
    'id': id,
    'title': title,
    'description': description,
    'cover': cover,
    'tags': tags,
    'recommendedPlayers': recommendedPlayers,
    'estimatedLength': estimatedLength,
    'ruleSystem': ruleSystem,
    'theme': theme,
    'tone': tone,
    'difficulty': difficulty.name,
    'author': author,
    'source': source.name,
    'opening': opening,
    'systemPrompt': systemPrompt,
    'acts': acts.map((value) => value.toJson()).toList(),
    'locations': locations.map((value) => value.toJson()).toList(),
    'npcs': npcs.map((value) => value.toJson()).toList(),
    'quests': quests,
    'clues': clues.map((value) => value.toJson()).toList(),
    'items': items,
    'factions': factions,
    'encounters': encounters,
    'secrets': secrets,
    'endings': endings,
    'aiGmSettings': aiGmSettings,
    'audioAssets': audioAssets.map((value) => value.toJson()).toList(),
    'presentationSettings': presentationSettings.toJson(),
    'metadata': metadata,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory CampaignDocument.fromJson(
    Map<String, Object?> json,
  ) => CampaignDocument(
    schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? 1,
    campaignType: _campaignTypeOr(json['campaignType'] ?? json['type']),
    id: json['id'] as String? ?? _campaignUuid.v4(),
    title: json['title'] as String? ?? '未命名剧本',
    description: json['description'] as String? ?? '',
    cover: json['cover'] as String?,
    tags: _stringList(json['tags']),
    recommendedPlayers: json['recommendedPlayers'] as String? ?? '1~4',
    estimatedLength: json['estimatedLength'] as String? ?? '2~4小时',
    ruleSystem: json['ruleSystem'] as String? ?? '通用规则',
    theme: json['theme'] as String? ?? '',
    tone: json['tone'] as String? ?? '',
    difficulty: _enumOr(
      CampaignDifficulty.values,
      json['difficulty'],
      CampaignDifficulty.normal,
    ),
    author: json['author'] as String? ?? '',
    source: _enumOr(
      CampaignSourceType.values,
      json['source'] ?? json['sourceType'],
      CampaignSourceType.local,
    ),
    opening: json['opening'] as String? ?? '',
    systemPrompt: json['systemPrompt'] as String? ?? '',
    acts: (json['acts'] as List? ?? const [])
        .whereType<Map>()
        .map((value) => CampaignAct.fromJson(value.cast<String, Object?>()))
        .toList(),
    locations: (json['locations'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (value) => CampaignLocation.fromJson(value.cast<String, Object?>()),
        )
        .toList(),
    npcs: (json['npcs'] as List? ?? const [])
        .whereType<Map>()
        .map((value) => TRPGNPCProfile.fromJson(value.cast<String, Object?>()))
        .toList(),
    quests: (json['quests'] as List? ?? const [])
        .whereType<Map>()
        .map((value) => value.cast<String, Object?>())
        .toList(),
    clues: (json['clues'] as List? ?? const [])
        .whereType<Map>()
        .map((value) => CampaignClue.fromJson(value.cast<String, Object?>()))
        .toList(),
    items: (json['items'] as List? ?? const [])
        .whereType<Map>()
        .map((value) => value.cast<String, Object?>())
        .toList(),
    factions: (json['factions'] as List? ?? const [])
        .whereType<Map>()
        .map((value) => value.cast<String, Object?>())
        .toList(),
    encounters: (json['encounters'] as List? ?? const [])
        .whereType<Map>()
        .map((value) => value.cast<String, Object?>())
        .toList(),
    secrets: _stringList(json['secrets']),
    endings: _stringList(json['endings'] ?? json['possibleEndings']),
    aiGmSettings: _objectMap(json['aiGmSettings']),
    audioAssets: (json['audioAssets'] as List? ?? const [])
        .whereType<Map>()
        .map((value) => AudioAsset.fromJson(value.cast<String, Object?>()))
        .toList(),
    presentationSettings: json['presentationSettings'] is Map
        ? CampaignPresentationSettings.fromJson(
            (json['presentationSettings'] as Map).cast<String, Object?>(),
          )
        : const CampaignPresentationSettings(),
    metadata: _objectMap(json['metadata']),
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    updatedAt:
        DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
  );
}
