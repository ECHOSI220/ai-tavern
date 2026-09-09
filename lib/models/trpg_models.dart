import 'package:uuid/uuid.dart';

import 'trpg_game_models.dart';
import 'trpg_presentation_models.dart';
import 'trpg_memory_models.dart';
import 'trpg_party_models.dart';
import 'trpg_living_npc_models.dart';
import 'trpg_world_generator_models.dart';
import 'trpg_faction_models.dart';
import 'holy_grail_war_models.dart';
import 'trpg_dice_models.dart';
import 'trpg_gameplay_models.dart';

const trpgSchemaVersion = 11;
const _uuid = Uuid();

enum TRPGMode { solo, multiplayer }

enum TRPGSessionStatus { preparing, active, paused, completed, archived }

enum TRPGPlayerRole { player, roomOwner, humanGm }

enum TRPGConnectionStatus { offline, connecting, reconnecting, online, left }

enum InformationVisibility { public, playerPrivate, partyPartial, gmOnly }

enum CampaignSourceType { local, imported, aiGenerated, template }

enum AIHostMode { localUser, selectedPlayer, server, humanGm }

enum AIHostStatus {
  none,
  pending,
  accepted,
  ready,
  busy,
  offline,
  declined,
  error,
}

enum TRPGEventType {
  playerAction,
  gmNarration,
  diceRoll,
  skillCheck,
  itemGain,
  itemLoss,
  hpChange,
  sceneChange,
  questUpdate,
  statusChange,
  clueDiscovered,
  npcRelationship,
  combatStarted,
  attackCheck,
  damageApplied,
  combatEnded,
  toolError,
  secretAction,
  privateMessage,
  privateRoll,
  informationRevealed,
  npcAction,
  npcDecision,
  npcRelationChange,
  npcDiscovery,
  npcDeath,
  factionAction,
  factionRelationship,
  factionWar,
  factionTerritory,
  factionInternalConflict,
  factionSuccession,
  holyGrailSummoning,
  holyGrailInvestigation,
  holyGrailCommandSpell,
  holyGrailNoblePhantasm,
  holyGrailAlliance,
  holyGrailBetrayal,
  holyGrailPhase,
  holyGrailEnding,
  worldSimulation,
  system,
}

enum TRPGMessageType {
  playerMessage,
  gmMessage,
  npcMessage,
  npcPlayerMessage,
  systemMessage,
  diceMessage,
}

T _enumValue<T extends Enum>(List<T> values, Object? raw, T fallback) =>
    values.where((item) => item.name == raw).firstOrNull ?? fallback;

Map<String, Object?> _map(Object? value) =>
    value is Map ? value.cast<String, Object?>() : <String, Object?>{};
List<String> _strings(Object? value) =>
    value is List ? value.map((item) => item.toString()).toList() : const [];
Map<String, num> _numbers(Object? value) => value is Map
    ? value.map((key, value) => MapEntry(key.toString(), value as num))
    : const {};
Map<String, CharacterLocationState> _locationMap(Object? value) => value is Map
    ? value.map(
        (key, item) => MapEntry(
          key.toString(),
          CharacterLocationState.fromJson(
            item is Map ? item.cast<String, Object?>() : const {},
          ),
        ),
      )
    : const {};
Map<String, CharacterLocationState> _legacyCharacterLocations(
  Map<String, Object?> json,
) {
  final world = _map(json['worldState']);
  final scene = _map(world['currentScene']);
  final sceneId = scene['sceneId'] as String? ?? '';
  final locationId =
      scene['locationId'] as String? ??
      world['location'] as String? ??
      json['currentScene'] as String? ??
      '';
  final characters = json['playerCharacters'] as List? ?? const [];
  return {
    for (final raw in characters.whereType<Map>())
      if ((raw['id'] ?? '').toString().isNotEmpty)
        raw['id'].toString(): CharacterLocationState(
          characterId: raw['id'].toString(),
          sceneId: sceneId,
          locationId:
              (raw['metadata'] as Map?)?['locationId'] as String? ?? locationId,
        ),
  };
}

class TRPGPlayer {
  const TRPGPlayer({
    required this.playerId,
    required this.displayName,
    this.avatar,
    this.role = TRPGPlayerRole.player,
    this.characterId,
    this.connectionStatus = TRPGConnectionStatus.online,
    required this.joinedAt,
    this.isReady = false,
    this.isAiControlled = false,
  });
  final String playerId;
  final String displayName;
  final String? avatar;
  final TRPGPlayerRole role;
  final String? characterId;
  final TRPGConnectionStatus connectionStatus;
  final DateTime joinedAt;
  final bool isReady;
  final bool isAiControlled;

  TRPGPlayer copyWith({
    String? displayName,
    String? characterId,
    TRPGPlayerRole? role,
    TRPGConnectionStatus? connectionStatus,
    bool? isReady,
    bool? isAiControlled,
  }) => TRPGPlayer(
    playerId: playerId,
    displayName: displayName ?? this.displayName,
    avatar: avatar,
    role: role ?? this.role,
    characterId: characterId ?? this.characterId,
    connectionStatus: connectionStatus ?? this.connectionStatus,
    joinedAt: joinedAt,
    isReady: isReady ?? this.isReady,
    isAiControlled: isAiControlled ?? this.isAiControlled,
  );
  Map<String, Object?> toJson() => {
    'playerId': playerId,
    'displayName': displayName,
    'avatar': avatar,
    'role': role.name,
    'characterId': characterId,
    'connectionStatus': connectionStatus.name,
    'joinedAt': joinedAt.toIso8601String(),
    'isReady': isReady,
    'isAiControlled': isAiControlled,
  };
  factory TRPGPlayer.fromJson(Map<String, Object?> json) => TRPGPlayer(
    playerId: json['playerId']! as String,
    displayName: json['displayName'] as String? ?? '玩家',
    avatar: json['avatar'] as String?,
    role: _enumValue(
      TRPGPlayerRole.values,
      json['role'],
      TRPGPlayerRole.player,
    ),
    characterId: json['characterId'] as String?,
    connectionStatus: _enumValue(
      TRPGConnectionStatus.values,
      json['connectionStatus'],
      TRPGConnectionStatus.offline,
    ),
    joinedAt:
        DateTime.tryParse(json['joinedAt'] as String? ?? '') ?? DateTime.now(),
    isReady: json['isReady'] as bool? ?? false,
    isAiControlled: json['isAiControlled'] as bool? ?? false,
  );
}

class PlayerCharacter {
  const PlayerCharacter({
    required this.id,
    required this.playerId,
    required this.name,
    this.avatar,
    this.description = '',
    this.background = '',
    this.personality = '',
    this.stats = const {'STR': 10, 'DEX': 10, 'INT': 10, 'PER': 10, 'CHA': 10},
    this.skills = const {},
    this.hp = 20,
    this.maxHp = 20,
    this.resource = const {},
    this.inventory = const [],
    this.inventoryItems = const [],
    this.equipment = const [],
    this.statusEffects = const [],
    this.structuredStatusEffects = const [],
    this.notes = '',
    this.metadata = const {},
  });
  final String id;
  final String playerId;
  final String name;
  final String? avatar;
  final String description;
  final String background;
  final String personality;
  final Map<String, num> stats;
  final Map<String, num> skills;
  final int hp;
  final int maxHp;
  final Map<String, Object?> resource;
  final List<String> inventory;
  final List<InventoryItem> inventoryItems;
  final List<String> equipment;
  final List<String> statusEffects;
  final List<StatusEffect> structuredStatusEffects;
  final String notes;
  final Map<String, Object?> metadata;
  String? get locationId => metadata['locationId'] as String?;
  bool get isAiControlled => metadata['isAiControlled'] == true;

  PlayerCharacter copyWith({
    Map<String, num>? stats,
    Map<String, num>? skills,
    int? hp,
    int? maxHp,
    List<String>? inventory,
    List<InventoryItem>? inventoryItems,
    List<String>? statusEffects,
    List<StatusEffect>? structuredStatusEffects,
    Map<String, Object?>? resource,
    List<String>? equipment,
    Map<String, Object?>? metadata,
  }) => PlayerCharacter(
    id: id,
    playerId: playerId,
    name: name,
    avatar: avatar,
    description: description,
    background: background,
    personality: personality,
    stats: stats ?? this.stats,
    skills: skills ?? this.skills,
    hp: hp ?? this.hp,
    maxHp: maxHp ?? this.maxHp,
    resource: resource ?? this.resource,
    inventory: inventory ?? this.inventory,
    inventoryItems: inventoryItems ?? this.inventoryItems,
    equipment: equipment ?? this.equipment,
    statusEffects: statusEffects ?? this.statusEffects,
    structuredStatusEffects:
        structuredStatusEffects ?? this.structuredStatusEffects,
    notes: notes,
    metadata: metadata ?? this.metadata,
  );
  Map<String, Object?> toJson() => {
    'id': id,
    'playerId': playerId,
    'name': name,
    'avatar': avatar,
    'description': description,
    'background': background,
    'personality': personality,
    'stats': stats,
    'skills': skills,
    'hp': hp,
    'maxHp': maxHp,
    'resource': resource,
    'inventory': inventory,
    'inventoryItems': inventoryItems.map((item) => item.toJson()).toList(),
    'equipment': equipment,
    'statusEffects': statusEffects,
    'structuredStatusEffects': structuredStatusEffects
        .map((item) => item.toJson())
        .toList(),
    'notes': notes,
    'metadata': metadata,
  };
  factory PlayerCharacter.fromJson(Map<String, Object?> json) =>
      PlayerCharacter(
        id: json['id']! as String,
        playerId: json['playerId']! as String,
        name: json['name'] as String? ?? '未命名角色',
        avatar: json['avatar'] as String?,
        description: json['description'] as String? ?? '',
        background: json['background'] as String? ?? '',
        personality: json['personality'] as String? ?? '',
        stats: _numbers(json['stats']),
        skills: _numbers(json['skills']),
        hp: (json['hp'] as num?)?.toInt() ?? 20,
        maxHp: (json['maxHp'] as num?)?.toInt() ?? 20,
        resource: _map(json['resource']),
        inventory: _strings(json['inventory']),
        inventoryItems: (json['inventoryItems'] as List? ?? const [])
            .whereType<Map>()
            .map((item) => InventoryItem.fromJson(item.cast<String, Object?>()))
            .toList(),
        equipment: _strings(json['equipment']),
        statusEffects: _strings(json['statusEffects']),
        structuredStatusEffects:
            (json['structuredStatusEffects'] as List? ?? const [])
                .whereType<Map>()
                .map(
                  (item) => StatusEffect.fromJson(item.cast<String, Object?>()),
                )
                .toList(),
        notes: json['notes'] as String? ?? '',
        metadata: _map(json['metadata']),
      );
}

class Campaign {
  const Campaign({
    required this.id,
    required this.title,
    this.description = '',
    this.cover,
    this.systemPrompt = '',
    this.opening = '',
    this.locations = const [],
    this.npcs = const [],
    this.factions = const [],
    this.quests = const [],
    this.secrets = const [],
    this.items = const [],
    this.encounters = const [],
    this.possibleEndings = const [],
    this.sourceType = CampaignSourceType.local,
    this.metadata = const {},
  });
  final String id;
  final String title;
  final String description;
  final String? cover;
  final String systemPrompt;
  final String opening;
  final List<Map<String, Object?>> locations;
  final List<Map<String, Object?>> npcs;
  final List<Map<String, Object?>> factions;
  final List<Map<String, Object?>> quests;
  final List<String> secrets;
  final List<Map<String, Object?>> items;
  final List<Map<String, Object?>> encounters;
  final List<String> possibleEndings;
  final CampaignSourceType sourceType;
  final Map<String, Object?> metadata;
  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'cover': cover,
    'systemPrompt': systemPrompt,
    'opening': opening,
    'locations': locations,
    'npcs': npcs,
    'factions': factions,
    'quests': quests,
    'secrets': secrets,
    'items': items,
    'encounters': encounters,
    'possibleEndings': possibleEndings,
    'sourceType': sourceType.name,
    'metadata': metadata,
  };
  factory Campaign.fromJson(Map<String, Object?> json) => Campaign(
    id: json['id']! as String,
    title: json['title'] as String? ?? '未命名剧本',
    description: json['description'] as String? ?? '',
    cover: json['cover'] as String?,
    systemPrompt: json['systemPrompt'] as String? ?? '',
    opening: json['opening'] as String? ?? '',
    locations: (json['locations'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => e.cast<String, Object?>())
        .toList(),
    npcs: (json['npcs'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => e.cast<String, Object?>())
        .toList(),
    factions: (json['factions'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => e.cast<String, Object?>())
        .toList(),
    quests: (json['quests'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => e.cast<String, Object?>())
        .toList(),
    secrets: _strings(json['secrets']),
    items: (json['items'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => e.cast<String, Object?>())
        .toList(),
    encounters: (json['encounters'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => e.cast<String, Object?>())
        .toList(),
    possibleEndings: _strings(json['possibleEndings']),
    sourceType: _enumValue(
      CampaignSourceType.values,
      json['sourceType'],
      CampaignSourceType.local,
    ),
    metadata: _map(json['metadata']),
  );
}

class CampaignState {
  const CampaignState({
    this.currentAct = 1,
    this.currentChapter = 1,
    this.currentLocationId = '',
    this.completedQuests = const [],
    this.activeQuests = const [],
    this.failedQuests = const [],
    this.discoveredLocations = const [],
    this.triggeredEvents = const [],
    this.flags = const {},
    this.variables = const {},
    this.quests = const [],
    this.clues = const [],
  });
  final int currentAct, currentChapter;
  final String currentLocationId;
  final List<String> completedQuests,
      activeQuests,
      failedQuests,
      discoveredLocations,
      triggeredEvents;
  final Map<String, bool> flags;
  final Map<String, Object?> variables;
  final List<QuestState> quests;
  final List<ClueState> clues;

  CampaignState copyWith({
    int? currentAct,
    int? currentChapter,
    String? currentLocationId,
    List<String>? completedQuests,
    List<String>? activeQuests,
    List<String>? failedQuests,
    List<String>? discoveredLocations,
    List<String>? triggeredEvents,
    Map<String, bool>? flags,
    Map<String, Object?>? variables,
    List<QuestState>? quests,
    List<ClueState>? clues,
  }) => CampaignState(
    currentAct: currentAct ?? this.currentAct,
    currentChapter: currentChapter ?? this.currentChapter,
    currentLocationId: currentLocationId ?? this.currentLocationId,
    completedQuests: completedQuests ?? this.completedQuests,
    activeQuests: activeQuests ?? this.activeQuests,
    failedQuests: failedQuests ?? this.failedQuests,
    discoveredLocations: discoveredLocations ?? this.discoveredLocations,
    triggeredEvents: triggeredEvents ?? this.triggeredEvents,
    flags: flags ?? this.flags,
    variables: variables ?? this.variables,
    quests: quests ?? this.quests,
    clues: clues ?? this.clues,
  );
  Map<String, Object?> toJson() => {
    'currentAct': currentAct,
    'currentChapter': currentChapter,
    'currentLocationId': currentLocationId,
    'completedQuests': completedQuests,
    'activeQuests': activeQuests,
    'failedQuests': failedQuests,
    'discoveredLocations': discoveredLocations,
    'triggeredEvents': triggeredEvents,
    'flags': flags,
    'variables': variables,
    'quests': quests.map((item) => item.toJson()).toList(),
    'clues': clues.map((item) => item.toJson()).toList(),
  };
  factory CampaignState.fromJson(Map<String, Object?> j) => CampaignState(
    currentAct: (j['currentAct'] as num?)?.toInt() ?? 1,
    currentChapter: (j['currentChapter'] as num?)?.toInt() ?? 1,
    currentLocationId: j['currentLocationId'] as String? ?? '',
    completedQuests: _strings(j['completedQuests']),
    activeQuests: _strings(j['activeQuests']),
    failedQuests: _strings(j['failedQuests']),
    discoveredLocations: _strings(j['discoveredLocations']),
    triggeredEvents: _strings(j['triggeredEvents']),
    flags: j['flags'] is Map
        ? (j['flags'] as Map).map((k, v) => MapEntry(k.toString(), v as bool))
        : const {},
    variables: _map(j['variables']),
    quests: (j['quests'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => QuestState.fromJson(item.cast<String, Object?>()))
        .toList(),
    clues: (j['clues'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => ClueState.fromJson(item.cast<String, Object?>()))
        .toList(),
  );
}

class WorldState {
  const WorldState({
    this.time = '',
    this.weather = '',
    this.location = '',
    this.knownNpcs = const [],
    this.factionRelations = const {},
    this.worldFlags = const {},
    this.customVariables = const {},
    this.currentScene = const SceneState(),
    this.npcs = const [],
  });
  final String time, weather, location;
  final List<String> knownNpcs;
  final Map<String, num> factionRelations;
  final Map<String, bool> worldFlags;
  final Map<String, Object?> customVariables;
  final SceneState currentScene;
  final List<NPCState> npcs;

  WorldState copyWith({
    String? time,
    String? weather,
    String? location,
    List<String>? knownNpcs,
    Map<String, num>? factionRelations,
    Map<String, bool>? worldFlags,
    Map<String, Object?>? customVariables,
    SceneState? currentScene,
    List<NPCState>? npcs,
  }) => WorldState(
    time: time ?? this.time,
    weather: weather ?? this.weather,
    location: location ?? this.location,
    knownNpcs: knownNpcs ?? this.knownNpcs,
    factionRelations: factionRelations ?? this.factionRelations,
    worldFlags: worldFlags ?? this.worldFlags,
    customVariables: customVariables ?? this.customVariables,
    currentScene: currentScene ?? this.currentScene,
    npcs: npcs ?? this.npcs,
  );
  Map<String, Object?> toJson() => {
    'time': time,
    'weather': weather,
    'location': location,
    'knownNpcs': knownNpcs,
    'factionRelations': factionRelations,
    'worldFlags': worldFlags,
    'customVariables': customVariables,
    'currentScene': currentScene.toJson(),
    'npcs': npcs.map((item) => item.toJson()).toList(),
  };
  factory WorldState.fromJson(Map<String, Object?> j) => WorldState(
    time: j['time'] as String? ?? '',
    weather: j['weather'] as String? ?? '',
    location: j['location'] as String? ?? '',
    knownNpcs: _strings(j['knownNpcs']),
    factionRelations: _numbers(j['factionRelations']),
    worldFlags: j['worldFlags'] is Map
        ? (j['worldFlags'] as Map).map(
            (k, v) => MapEntry(k.toString(), v as bool),
          )
        : const {},
    customVariables: _map(j['customVariables']),
    currentScene: SceneState.fromJson(_map(j['currentScene'])),
    npcs: (j['npcs'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => NPCState.fromJson(item.cast<String, Object?>()))
        .toList(),
  );
}

class GMState {
  const GMState({
    this.privateNotes = '',
    this.hiddenNpcInfo = const {},
    this.secretLocations = const [],
    this.undiscoveredClues = const [],
    this.futureEvents = const [],
    this.plotHooks = const [],
    this.gmMemory = '',
    this.campaignSummary = '',
    this.recentSummary = '',
  });
  final String privateNotes, gmMemory, campaignSummary, recentSummary;
  final Map<String, Object?> hiddenNpcInfo;
  final List<String> secretLocations,
      undiscoveredClues,
      futureEvents,
      plotHooks;
  Map<String, Object?> toJson() => {
    'privateNotes': privateNotes,
    'hiddenNpcInfo': hiddenNpcInfo,
    'secretLocations': secretLocations,
    'undiscoveredClues': undiscoveredClues,
    'futureEvents': futureEvents,
    'plotHooks': plotHooks,
    'gmMemory': gmMemory,
    'campaignSummary': campaignSummary,
    'recentSummary': recentSummary,
  };
  factory GMState.fromJson(Map<String, Object?> j) => GMState(
    privateNotes: j['privateNotes'] as String? ?? '',
    hiddenNpcInfo: _map(j['hiddenNpcInfo']),
    secretLocations: _strings(j['secretLocations']),
    undiscoveredClues: _strings(j['undiscoveredClues']),
    futureEvents: _strings(j['futureEvents']),
    plotHooks: _strings(j['plotHooks']),
    gmMemory: j['gmMemory'] as String? ?? '',
    campaignSummary: j['campaignSummary'] as String? ?? '',
    recentSummary: j['recentSummary'] as String? ?? '',
  );
}

class DiceRoll {
  const DiceRoll({
    required this.diceType,
    required this.count,
    required this.rolls,
    this.modifier = 0,
    required this.total,
    required this.playerId,
    required this.timestamp,
    this.characterId,
    this.turnId,
    this.actionId,
  });
  final String diceType, playerId;
  final String? characterId, turnId, actionId;
  final int count, modifier, total;
  final List<int> rolls;
  final DateTime timestamp;
  Map<String, Object?> toJson() => {
    'diceType': diceType,
    'count': count,
    'rolls': rolls,
    'modifier': modifier,
    'total': total,
    'playerId': playerId,
    'timestamp': timestamp.toIso8601String(),
    'characterId': characterId,
    'turnId': turnId,
    'actionId': actionId,
  };
  factory DiceRoll.fromJson(Map<String, Object?> j) => DiceRoll(
    diceType: j['diceType'] as String? ?? 'D20',
    count: (j['count'] as num?)?.toInt() ?? 1,
    rolls: (j['rolls'] as List? ?? const [])
        .map((e) => (e as num).toInt())
        .toList(),
    modifier: (j['modifier'] as num?)?.toInt() ?? 0,
    total: (j['total'] as num?)?.toInt() ?? 0,
    playerId: j['playerId'] as String? ?? '',
    characterId: j['characterId'] as String?,
    turnId: j['turnId'] as String?,
    actionId: j['actionId'] as String?,
    timestamp:
        DateTime.tryParse(j['timestamp'] as String? ?? '') ?? DateTime.now(),
  );
}

class RuleState {
  const RuleState({
    this.initiative = const [],
    this.activeTurn = '',
    this.combatActive = false,
    this.round = 0,
    this.diceHistory = const [],
    this.diceHistory2 = const [],
    this.diceSettings = const DiceSettings(),
    this.customRules = const {},
    this.temporaryModifiers = const {},
    this.checkHistory = const [],
    this.growthCandidates = const [],
    this.growthHistory = const [],
    this.privateResolutions = const [],
    this.traits = const [],
    this.repeatedChecks = const [],
  });
  final List<String> initiative;
  final String activeTurn;
  final bool combatActive;
  final int round;
  final List<DiceRoll> diceHistory;
  final List<DiceRollResult> diceHistory2;
  final DiceSettings diceSettings;
  final Map<String, Object?> customRules, temporaryModifiers;
  final List<ActionCheckResult> checkHistory;
  final List<GrowthCandidate> growthCandidates;
  final List<CharacterGrowthEntry> growthHistory;
  final List<PlayerResolution> privateResolutions;
  final List<CharacterTrait> traits;
  final List<RepeatedCheckRecord> repeatedChecks;
  RuleState copyWith({
    List<String>? initiative,
    String? activeTurn,
    bool? combatActive,
    int? round,
    List<DiceRoll>? diceHistory,
    List<DiceRollResult>? diceHistory2,
    DiceSettings? diceSettings,
    Map<String, Object?>? customRules,
    Map<String, Object?>? temporaryModifiers,
    List<ActionCheckResult>? checkHistory,
    List<GrowthCandidate>? growthCandidates,
    List<CharacterGrowthEntry>? growthHistory,
    List<PlayerResolution>? privateResolutions,
    List<CharacterTrait>? traits,
    List<RepeatedCheckRecord>? repeatedChecks,
  }) => RuleState(
    initiative: initiative ?? this.initiative,
    activeTurn: activeTurn ?? this.activeTurn,
    combatActive: combatActive ?? this.combatActive,
    round: round ?? this.round,
    diceHistory: diceHistory ?? this.diceHistory,
    diceHistory2: diceHistory2 ?? this.diceHistory2,
    diceSettings: diceSettings ?? this.diceSettings,
    customRules: customRules ?? this.customRules,
    temporaryModifiers: temporaryModifiers ?? this.temporaryModifiers,
    checkHistory: checkHistory ?? this.checkHistory,
    growthCandidates: growthCandidates ?? this.growthCandidates,
    growthHistory: growthHistory ?? this.growthHistory,
    privateResolutions: privateResolutions ?? this.privateResolutions,
    traits: traits ?? this.traits,
    repeatedChecks: repeatedChecks ?? this.repeatedChecks,
  );
  Map<String, Object?> toJson() => {
    'initiative': initiative,
    'activeTurn': activeTurn,
    'combatActive': combatActive,
    'round': round,
    'diceHistory': diceHistory.map((e) => e.toJson()).toList(),
    'diceHistory2': diceHistory2.map((e) => e.toJson()).toList(),
    'diceSettings': diceSettings.toJson(),
    'customRules': customRules,
    'temporaryModifiers': temporaryModifiers,
    'checkHistory': checkHistory.map((value) => value.toJson()).toList(),
    'growthCandidates': growthCandidates
        .map((value) => value.toJson())
        .toList(),
    'growthHistory': growthHistory.map((value) => value.toJson()).toList(),
    'privateResolutions': privateResolutions
        .map((value) => value.toJson())
        .toList(),
    'traits': traits.map((value) => value.toJson()).toList(),
    'repeatedChecks': repeatedChecks.map((value) => value.toJson()).toList(),
  };
  factory RuleState.fromJson(Map<String, Object?> j) => RuleState(
    initiative: _strings(j['initiative']),
    activeTurn: j['activeTurn'] as String? ?? '',
    combatActive: j['combatActive'] as bool? ?? false,
    round: (j['round'] as num?)?.toInt() ?? 0,
    diceHistory: (j['diceHistory'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => DiceRoll.fromJson(e.cast<String, Object?>()))
        .toList(),
    diceHistory2: (j['diceHistory2'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => DiceRollResult.fromJson(e.cast<String, Object?>()))
        .toList(),
    diceSettings: j['diceSettings'] is Map
        ? DiceSettings.fromJson(
            (j['diceSettings'] as Map).cast<String, Object?>(),
          )
        : const DiceSettings(),
    customRules: _map(j['customRules']),
    temporaryModifiers: _map(j['temporaryModifiers']),
    checkHistory: (j['checkHistory'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (value) => ActionCheckResult.fromJson(value.cast<String, Object?>()),
        )
        .toList(),
    growthCandidates: (j['growthCandidates'] as List? ?? const [])
        .whereType<Map>()
        .map((value) => GrowthCandidate.fromJson(value.cast<String, Object?>()))
        .toList(),
    growthHistory: (j['growthHistory'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (value) =>
              CharacterGrowthEntry.fromJson(value.cast<String, Object?>()),
        )
        .toList(),
    privateResolutions: (j['privateResolutions'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (value) => PlayerResolution.fromJson(value.cast<String, Object?>()),
        )
        .toList(),
    traits: (j['traits'] as List? ?? const [])
        .whereType<Map>()
        .map((value) => CharacterTrait.fromJson(value.cast<String, Object?>()))
        .toList(),
    repeatedChecks: (j['repeatedChecks'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (value) =>
              RepeatedCheckRecord.fromJson(value.cast<String, Object?>()),
        )
        .toList(),
  );
}

class TRPGMessage {
  const TRPGMessage({
    required this.id,
    required this.messageType,
    required this.content,
    this.playerId,
    this.npcId,
    this.visibleToAi = true,
    this.presentation = const MessagePresentationMetadata(),
    required this.createdAt,
  });
  final String id, content;
  final TRPGMessageType messageType;
  final String? playerId, npcId;
  final bool visibleToAi;
  final MessagePresentationMetadata presentation;
  final DateTime createdAt;
  Map<String, Object?> toJson() => {
    'id': id,
    'messageType': messageType.name,
    'content': content,
    'playerId': playerId,
    'npcId': npcId,
    'visibleToAi': visibleToAi,
    'presentation': presentation.toJson(),
    'createdAt': createdAt.toIso8601String(),
  };
  factory TRPGMessage.fromJson(Map<String, Object?> j) => TRPGMessage(
    id: j['id']! as String,
    messageType: _enumValue(
      TRPGMessageType.values,
      j['messageType'],
      TRPGMessageType.systemMessage,
    ),
    content: j['content'] as String? ?? '',
    playerId: j['playerId'] as String?,
    npcId: j['npcId'] as String?,
    visibleToAi: j['visibleToAi'] as bool? ?? true,
    presentation: j['presentation'] is Map
        ? MessagePresentationMetadata.fromJson(
            (j['presentation'] as Map).cast<String, Object?>(),
          )
        : MessagePresentationMetadata(
            speakerType: switch (_enumValue(
              TRPGMessageType.values,
              j['messageType'],
              TRPGMessageType.systemMessage,
            )) {
              TRPGMessageType.gmMessage => PresentationSpeakerType.narrator,
              TRPGMessageType.npcMessage => PresentationSpeakerType.npc,
              TRPGMessageType.npcPlayerMessage =>
                PresentationSpeakerType.player,
              TRPGMessageType.playerMessage => PresentationSpeakerType.player,
              _ => PresentationSpeakerType.system,
            },
            speakerId: j['npcId'] as String?,
          ),
    createdAt:
        DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
  );
}

class TRPGEvent {
  const TRPGEvent({
    required this.id,
    required this.type,
    required this.timestamp,
    this.actorId,
    this.payload = const {},
    this.visibleToAi = true,
  });
  final String id;
  final TRPGEventType type;
  final DateTime timestamp;
  final String? actorId;
  final Map<String, Object?> payload;
  final bool visibleToAi;
  Map<String, Object?> toJson() => {
    'id': id,
    'type': type.name,
    'timestamp': timestamp.toIso8601String(),
    'actorId': actorId,
    'payload': payload,
    'visibleToAi': visibleToAi,
  };
  factory TRPGEvent.fromJson(Map<String, Object?> j) => TRPGEvent(
    id: j['id']! as String,
    type: _enumValue(TRPGEventType.values, j['type'], TRPGEventType.system),
    timestamp:
        DateTime.tryParse(j['timestamp'] as String? ?? '') ?? DateTime.now(),
    actorId: j['actorId'] as String?,
    payload: _map(j['payload']),
    visibleToAi: j['visibleToAi'] as bool? ?? true,
  );
}

class AIHostConfig {
  const AIHostConfig({
    this.mode = AIHostMode.localUser,
    this.providerPlayerId,
    this.providerId,
    this.modelId,
    this.status = AIHostStatus.accepted,
    this.providerType = 'openai-compatible',
    this.acceptedAt,
    this.lastHeartbeat,
    this.maxRequests = 0,
    this.maxTokens = 0,
    this.requestCount = 0,
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.errorCount = 0,
  });
  final AIHostMode mode;
  final String? providerPlayerId, providerId, modelId;
  final AIHostStatus status;
  final String providerType;
  final DateTime? acceptedAt, lastHeartbeat;
  final int maxRequests,
      maxTokens,
      requestCount,
      inputTokens,
      outputTokens,
      errorCount;
  AIHostConfig copyWith({
    AIHostMode? mode,
    String? providerPlayerId,
    String? providerId,
    String? modelId,
    AIHostStatus? status,
    String? providerType,
    DateTime? acceptedAt,
    DateTime? lastHeartbeat,
    int? maxRequests,
    int? maxTokens,
    int? requestCount,
    int? inputTokens,
    int? outputTokens,
    int? errorCount,
  }) => AIHostConfig(
    mode: mode ?? this.mode,
    providerPlayerId: providerPlayerId ?? this.providerPlayerId,
    providerId: providerId ?? this.providerId,
    modelId: modelId ?? this.modelId,
    status: status ?? this.status,
    providerType: providerType ?? this.providerType,
    acceptedAt: acceptedAt ?? this.acceptedAt,
    lastHeartbeat: lastHeartbeat ?? this.lastHeartbeat,
    maxRequests: maxRequests ?? this.maxRequests,
    maxTokens: maxTokens ?? this.maxTokens,
    requestCount: requestCount ?? this.requestCount,
    inputTokens: inputTokens ?? this.inputTokens,
    outputTokens: outputTokens ?? this.outputTokens,
    errorCount: errorCount ?? this.errorCount,
  );
  Map<String, Object?> toJson() => {
    'mode': mode.name,
    'providerPlayerId': providerPlayerId,
    'providerId': providerId,
    'modelId': modelId,
    'status': status.name,
    'providerType': providerType,
    'acceptedAt': acceptedAt?.toIso8601String(),
    'lastHeartbeat': lastHeartbeat?.toIso8601String(),
    'maxRequests': maxRequests,
    'maxTokens': maxTokens,
    'requestCount': requestCount,
    'inputTokens': inputTokens,
    'outputTokens': outputTokens,
    'errorCount': errorCount,
  };
  factory AIHostConfig.fromJson(Map<String, Object?> j) => AIHostConfig(
    mode: _enumValue(AIHostMode.values, j['mode'], AIHostMode.localUser),
    providerPlayerId: j['providerPlayerId'] as String?,
    providerId: j['providerId'] as String?,
    modelId: j['modelId'] as String?,
    status: _enumValue(AIHostStatus.values, j['status'], AIHostStatus.offline),
    providerType: j['providerType'] as String? ?? 'openai-compatible',
    acceptedAt: DateTime.tryParse(j['acceptedAt'] as String? ?? ''),
    lastHeartbeat: DateTime.tryParse(j['lastHeartbeat'] as String? ?? ''),
    maxRequests: (j['maxRequests'] as num?)?.toInt() ?? 0,
    maxTokens: (j['maxTokens'] as num?)?.toInt() ?? 0,
    requestCount: (j['requestCount'] as num?)?.toInt() ?? 0,
    inputTokens: (j['inputTokens'] as num?)?.toInt() ?? 0,
    outputTokens: (j['outputTokens'] as num?)?.toInt() ?? 0,
    errorCount: (j['errorCount'] as num?)?.toInt() ?? 0,
  );
}

class GMStateSnapshot {
  const GMStateSnapshot({
    this.campaignSummary = '',
    this.currentScene = '',
    this.worldStateSummary = '',
    this.playersSummary = '',
    this.npcSummary = '',
    this.activeQuestSummary = '',
    this.hiddenGmNotes = '',
    this.recentEvents = const [],
    this.recentMessages = const [],
    this.longTermMemory = const [],
    this.npcMemorySummaries = const {},
    this.worldMemorySummary = '',
  });
  final String campaignSummary,
      currentScene,
      worldStateSummary,
      playersSummary,
      npcSummary,
      activeQuestSummary,
      hiddenGmNotes;
  final List<String> recentEvents, recentMessages, longTermMemory;
  final Map<String, String> npcMemorySummaries;
  final String worldMemorySummary;
  Map<String, Object?> toJson() => {
    'campaignSummary': campaignSummary,
    'currentScene': currentScene,
    'worldStateSummary': worldStateSummary,
    'playersSummary': playersSummary,
    'npcSummary': npcSummary,
    'activeQuestSummary': activeQuestSummary,
    'hiddenGmNotes': hiddenGmNotes,
    'recentEvents': recentEvents,
    'recentMessages': recentMessages,
    'longTermMemory': longTermMemory,
    'npcMemorySummaries': npcMemorySummaries,
    'worldMemorySummary': worldMemorySummary,
  };
  factory GMStateSnapshot.fromJson(Map<String, Object?> j) => GMStateSnapshot(
    campaignSummary: j['campaignSummary'] as String? ?? '',
    currentScene: j['currentScene'] as String? ?? '',
    worldStateSummary: j['worldStateSummary'] as String? ?? '',
    playersSummary: j['playersSummary'] as String? ?? '',
    npcSummary: j['npcSummary'] as String? ?? '',
    activeQuestSummary: j['activeQuestSummary'] as String? ?? '',
    hiddenGmNotes: j['hiddenGmNotes'] as String? ?? '',
    recentEvents: _strings(j['recentEvents']),
    recentMessages: _strings(j['recentMessages']),
    longTermMemory: _strings(j['longTermMemory']),
    npcMemorySummaries: (j['npcMemorySummaries'] as Map? ?? const {}).map(
      (key, value) => MapEntry(key.toString(), value.toString()),
    ),
    worldMemorySummary: j['worldMemorySummary'] as String? ?? '',
  );
}

class PrivateKnowledge {
  const PrivateKnowledge({
    required this.id,
    required this.title,
    required this.content,
    required this.visibility,
    required this.createdAt,
    this.ownerPlayerIds = const [],
    this.linkedEntityId,
    this.revealed = false,
  });
  final String id, title, content;
  final InformationVisibility visibility;
  final DateTime createdAt;
  final List<String> ownerPlayerIds;
  final String? linkedEntityId;
  final bool revealed;

  PrivateKnowledge copyWith({
    InformationVisibility? visibility,
    List<String>? ownerPlayerIds,
    bool? revealed,
  }) => PrivateKnowledge(
    id: id,
    title: title,
    content: content,
    visibility: visibility ?? this.visibility,
    createdAt: createdAt,
    ownerPlayerIds: ownerPlayerIds ?? this.ownerPlayerIds,
    linkedEntityId: linkedEntityId,
    revealed: revealed ?? this.revealed,
  );
  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'content': content,
    'visibility': visibility.name,
    'createdAt': createdAt.toIso8601String(),
    'ownerPlayerIds': ownerPlayerIds,
    'linkedEntityId': linkedEntityId,
    'revealed': revealed,
  };
  factory PrivateKnowledge.fromJson(Map<String, Object?> json) =>
      PrivateKnowledge(
        id: json['id'] as String? ?? _uuid.v4(),
        title: json['title'] as String? ?? '秘密信息',
        content: json['content'] as String? ?? '',
        visibility: _enumValue(
          InformationVisibility.values,
          json['visibility'],
          InformationVisibility.playerPrivate,
        ),
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
        ownerPlayerIds: _strings(json['ownerPlayerIds']),
        linkedEntityId: json['linkedEntityId'] as String?,
        revealed: json['revealed'] as bool? ?? false,
      );
}

class TRPGPrivateMessage {
  const TRPGPrivateMessage({
    required this.id,
    required this.senderId,
    required this.recipientIds,
    required this.content,
    required this.createdAt,
    this.toGm = false,
  });
  final String id, senderId, content;
  final List<String> recipientIds;
  final DateTime createdAt;
  final bool toGm;
  Map<String, Object?> toJson() => {
    'id': id,
    'senderId': senderId,
    'recipientIds': recipientIds,
    'content': content,
    'createdAt': createdAt.toIso8601String(),
    'toGm': toGm,
  };
  factory TRPGPrivateMessage.fromJson(Map<String, Object?> json) =>
      TRPGPrivateMessage(
        id: json['id'] as String? ?? _uuid.v4(),
        senderId: json['senderId'] as String? ?? '',
        recipientIds: _strings(json['recipientIds']),
        content: json['content'] as String? ?? '',
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
        toGm: json['toGm'] as bool? ?? false,
      );
}

class NPCInstanceState {
  const NPCInstanceState({
    required this.npcId,
    this.sourceCharacterId,
    this.hp = 20,
    this.maxHp = 20,
    this.relationship = 0,
    this.locationId,
    this.alive = true,
    this.knownToPlayers = false,
    this.inventory = const [],
    this.memories = const [],
    this.metadata = const {},
  });
  final String npcId;
  final String? sourceCharacterId, locationId;
  final int hp, maxHp, relationship;
  final bool alive, knownToPlayers;
  final List<String> inventory;
  final List<Map<String, Object?>> memories;
  final Map<String, Object?> metadata;
  NPCInstanceState copyWith({
    int? hp,
    int? relationship,
    String? locationId,
    bool? alive,
    bool? knownToPlayers,
    List<String>? inventory,
    List<Map<String, Object?>>? memories,
  }) => NPCInstanceState(
    npcId: npcId,
    sourceCharacterId: sourceCharacterId,
    hp: hp ?? this.hp,
    maxHp: maxHp,
    relationship: (relationship ?? this.relationship).clamp(-100, 100),
    locationId: locationId ?? this.locationId,
    alive: alive ?? this.alive,
    knownToPlayers: knownToPlayers ?? this.knownToPlayers,
    inventory: inventory ?? this.inventory,
    memories: memories ?? this.memories,
    metadata: metadata,
  );
  Map<String, Object?> toJson() => {
    'npcId': npcId,
    'sourceCharacterId': sourceCharacterId,
    'hp': hp,
    'maxHp': maxHp,
    'relationship': relationship,
    'locationId': locationId,
    'alive': alive,
    'knownToPlayers': knownToPlayers,
    'inventory': inventory,
    'memories': memories,
    'metadata': metadata,
  };
  factory NPCInstanceState.fromJson(Map<String, Object?> json) =>
      NPCInstanceState(
        npcId: json['npcId'] as String? ?? '',
        sourceCharacterId: json['sourceCharacterId'] as String?,
        hp: (json['hp'] as num?)?.toInt() ?? 20,
        maxHp: (json['maxHp'] as num?)?.toInt() ?? 20,
        relationship: (json['relationship'] as num?)?.toInt() ?? 0,
        locationId: json['locationId'] as String?,
        alive: json['alive'] as bool? ?? true,
        knownToPlayers: json['knownToPlayers'] as bool? ?? false,
        inventory: _strings(json['inventory']),
        memories: (json['memories'] as List? ?? const [])
            .whereType<Map>()
            .map((value) => value.cast<String, Object?>())
            .toList(),
        metadata: _map(json['metadata']),
      );
}

class SessionTimelineEntry {
  const SessionTimelineEntry({
    required this.id,
    required this.title,
    required this.createdAt,
    this.detail = '',
    this.visibility = InformationVisibility.public,
    this.ownerPlayerIds = const [],
  });
  final String id, title, detail;
  final DateTime createdAt;
  final InformationVisibility visibility;
  final List<String> ownerPlayerIds;
  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'detail': detail,
    'createdAt': createdAt.toIso8601String(),
    'visibility': visibility.name,
    'ownerPlayerIds': ownerPlayerIds,
  };
  factory SessionTimelineEntry.fromJson(Map<String, Object?> json) =>
      SessionTimelineEntry(
        id: json['id'] as String? ?? _uuid.v4(),
        title: json['title'] as String? ?? '',
        detail: json['detail'] as String? ?? '',
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
        visibility: _enumValue(
          InformationVisibility.values,
          json['visibility'],
          InformationVisibility.public,
        ),
        ownerPlayerIds: _strings(json['ownerPlayerIds']),
      );
}

class TRPGImmersionState {
  const TRPGImmersionState({
    this.npcInstances = const [],
    this.privateKnowledge = const [],
    this.privateMessages = const [],
    this.timeline = const [],
    this.discoveredNpcIds = const [],
    this.revealedMarkerIds = const [],
    this.campaignSnapshot = const {},
    this.allowPlayerPrivateChat = true,
  });
  final List<NPCInstanceState> npcInstances;
  final List<PrivateKnowledge> privateKnowledge;
  final List<TRPGPrivateMessage> privateMessages;
  final List<SessionTimelineEntry> timeline;
  final List<String> discoveredNpcIds, revealedMarkerIds;
  final Map<String, Object?> campaignSnapshot;
  final bool allowPlayerPrivateChat;
  TRPGImmersionState copyWith({
    List<NPCInstanceState>? npcInstances,
    List<PrivateKnowledge>? privateKnowledge,
    List<TRPGPrivateMessage>? privateMessages,
    List<SessionTimelineEntry>? timeline,
    List<String>? discoveredNpcIds,
    List<String>? revealedMarkerIds,
    Map<String, Object?>? campaignSnapshot,
    bool? allowPlayerPrivateChat,
  }) => TRPGImmersionState(
    npcInstances: npcInstances ?? this.npcInstances,
    privateKnowledge: privateKnowledge ?? this.privateKnowledge,
    privateMessages: privateMessages ?? this.privateMessages,
    timeline: timeline ?? this.timeline,
    discoveredNpcIds: discoveredNpcIds ?? this.discoveredNpcIds,
    revealedMarkerIds: revealedMarkerIds ?? this.revealedMarkerIds,
    campaignSnapshot: campaignSnapshot ?? this.campaignSnapshot,
    allowPlayerPrivateChat:
        allowPlayerPrivateChat ?? this.allowPlayerPrivateChat,
  );
  Map<String, Object?> toJson() => {
    'npcInstances': npcInstances.map((value) => value.toJson()).toList(),
    'privateKnowledge': privateKnowledge
        .map((value) => value.toJson())
        .toList(),
    'privateMessages': privateMessages.map((value) => value.toJson()).toList(),
    'timeline': timeline.map((value) => value.toJson()).toList(),
    'discoveredNpcIds': discoveredNpcIds,
    'revealedMarkerIds': revealedMarkerIds,
    'campaignSnapshot': campaignSnapshot,
    'allowPlayerPrivateChat': allowPlayerPrivateChat,
  };
  factory TRPGImmersionState.fromJson(Map<String, Object?> json) =>
      TRPGImmersionState(
        npcInstances: (json['npcInstances'] as List? ?? const [])
            .whereType<Map>()
            .map(
              (value) =>
                  NPCInstanceState.fromJson(value.cast<String, Object?>()),
            )
            .toList(),
        privateKnowledge: (json['privateKnowledge'] as List? ?? const [])
            .whereType<Map>()
            .map(
              (value) =>
                  PrivateKnowledge.fromJson(value.cast<String, Object?>()),
            )
            .toList(),
        privateMessages: (json['privateMessages'] as List? ?? const [])
            .whereType<Map>()
            .map(
              (value) =>
                  TRPGPrivateMessage.fromJson(value.cast<String, Object?>()),
            )
            .toList(),
        timeline: (json['timeline'] as List? ?? const [])
            .whereType<Map>()
            .map(
              (value) =>
                  SessionTimelineEntry.fromJson(value.cast<String, Object?>()),
            )
            .toList(),
        discoveredNpcIds: _strings(json['discoveredNpcIds']),
        revealedMarkerIds: _strings(json['revealedMarkerIds']),
        campaignSnapshot: _map(json['campaignSnapshot']),
        allowPlayerPrivateChat: json['allowPlayerPrivateChat'] as bool? ?? true,
      );
}

class TRPGSession {
  const TRPGSession({
    required this.id,
    required this.title,
    required this.mode,
    required this.createdAt,
    required this.updatedAt,
    required this.lastPlayedAt,
    this.status = TRPGSessionStatus.preparing,
    required this.campaignId,
    this.ruleSystemId = 'simple_trpg',
    this.gmProviderConfigRef,
    this.roomOwnerPlayerId,
    this.players = const [],
    this.playerCharacters = const [],
    this.characterLocations = const {},
    this.partyGroups = const [],
    this.npcLocations = const {},
    this.locationFlags = const {},
    this.currentScene = '',
    this.campaignState = const CampaignState(),
    this.worldState = const WorldState(),
    this.gmState = const GMState(),
    this.ruleState = const RuleState(),
    this.chatHistory = const [],
    this.eventLog = const [],
    this.aiHostConfig = const AIHostConfig(),
    this.gmStateSnapshot = const GMStateSnapshot(),
    this.metadata = const {},
    this.toolExecutions = const [],
    this.actionSnapshots = const [],
    this.sessionSummary = '',
    this.immersionState = const TRPGImmersionState(),
    this.presentationState = const CurrentPresentationState(),
    this.memoryState = const MemoryState(),
    this.livingNpcState = const LivingNPCState(),
    this.worldGenerationState = const WorldGenerationState(),
    this.factionSimulationState = const FactionSimulationState(),
    this.holyGrailState = const HolyGrailWarState(),
    this.schemaVersion = trpgSchemaVersion,
  });
  final int schemaVersion;
  final String id, title, campaignId, ruleSystemId, currentScene;
  final TRPGMode mode;
  final DateTime createdAt, updatedAt, lastPlayedAt;
  final TRPGSessionStatus status;
  final String? gmProviderConfigRef, roomOwnerPlayerId;
  final List<TRPGPlayer> players;
  final List<PlayerCharacter> playerCharacters;
  final Map<String, CharacterLocationState> characterLocations;
  final List<PartyGroup> partyGroups;
  final Map<String, CharacterLocationState> npcLocations;
  final Map<String, Map<String, Object?>> locationFlags;
  final CampaignState campaignState;
  final WorldState worldState;
  final GMState gmState;
  final RuleState ruleState;
  final List<TRPGMessage> chatHistory;
  final List<TRPGEvent> eventLog;
  final AIHostConfig aiHostConfig;
  final GMStateSnapshot gmStateSnapshot;
  final Map<String, Object?> metadata;
  final List<ToolExecutionRecord> toolExecutions;
  final List<TRPGActionSnapshot> actionSnapshots;
  final String sessionSummary;
  final TRPGImmersionState immersionState;
  final CurrentPresentationState presentationState;
  final MemoryState memoryState;
  final LivingNPCState livingNpcState;
  final WorldGenerationState worldGenerationState;
  final FactionSimulationState factionSimulationState;
  final HolyGrailWarState holyGrailState;
  TRPGSession copyWith({
    TRPGSessionStatus? status,
    String? currentScene,
    List<TRPGPlayer>? players,
    List<PlayerCharacter>? playerCharacters,
    Map<String, CharacterLocationState>? characterLocations,
    List<PartyGroup>? partyGroups,
    Map<String, CharacterLocationState>? npcLocations,
    Map<String, Map<String, Object?>>? locationFlags,
    CampaignState? campaignState,
    WorldState? worldState,
    GMState? gmState,
    RuleState? ruleState,
    List<TRPGMessage>? chatHistory,
    List<TRPGEvent>? eventLog,
    AIHostConfig? aiHostConfig,
    GMStateSnapshot? gmStateSnapshot,
    DateTime? updatedAt,
    DateTime? lastPlayedAt,
    List<ToolExecutionRecord>? toolExecutions,
    List<TRPGActionSnapshot>? actionSnapshots,
    String? sessionSummary,
    TRPGImmersionState? immersionState,
    CurrentPresentationState? presentationState,
    MemoryState? memoryState,
    LivingNPCState? livingNpcState,
    WorldGenerationState? worldGenerationState,
    FactionSimulationState? factionSimulationState,
    HolyGrailWarState? holyGrailState,
    Map<String, Object?>? metadata,
  }) => TRPGSession(
    id: id,
    title: title,
    mode: mode,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
    status: status ?? this.status,
    campaignId: campaignId,
    ruleSystemId: ruleSystemId,
    gmProviderConfigRef: gmProviderConfigRef,
    roomOwnerPlayerId: roomOwnerPlayerId,
    players: players ?? this.players,
    playerCharacters: playerCharacters ?? this.playerCharacters,
    characterLocations: characterLocations ?? this.characterLocations,
    partyGroups: partyGroups ?? this.partyGroups,
    npcLocations: npcLocations ?? this.npcLocations,
    locationFlags: locationFlags ?? this.locationFlags,
    currentScene: currentScene ?? this.currentScene,
    campaignState: campaignState ?? this.campaignState,
    worldState: worldState ?? this.worldState,
    gmState: gmState ?? this.gmState,
    ruleState: ruleState ?? this.ruleState,
    chatHistory: chatHistory ?? this.chatHistory,
    eventLog: eventLog ?? this.eventLog,
    aiHostConfig: aiHostConfig ?? this.aiHostConfig,
    gmStateSnapshot: gmStateSnapshot ?? this.gmStateSnapshot,
    metadata: metadata ?? this.metadata,
    toolExecutions: toolExecutions ?? this.toolExecutions,
    actionSnapshots: actionSnapshots ?? this.actionSnapshots,
    sessionSummary: sessionSummary ?? this.sessionSummary,
    immersionState: immersionState ?? this.immersionState,
    presentationState: presentationState ?? this.presentationState,
    memoryState: memoryState ?? this.memoryState,
    livingNpcState: livingNpcState ?? this.livingNpcState,
    worldGenerationState: worldGenerationState ?? this.worldGenerationState,
    factionSimulationState:
        factionSimulationState ?? this.factionSimulationState,
    holyGrailState: holyGrailState ?? this.holyGrailState,
    schemaVersion: schemaVersion,
  );
  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'id': id,
    'title': title,
    'mode': mode.name,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'lastPlayedAt': lastPlayedAt.toIso8601String(),
    'status': status.name,
    'campaignId': campaignId,
    'ruleSystemId': ruleSystemId,
    'gmProviderConfigRef': gmProviderConfigRef,
    'roomOwnerPlayerId': roomOwnerPlayerId,
    'players': players.map((e) => e.toJson()).toList(),
    'playerCharacters': playerCharacters.map((e) => e.toJson()).toList(),
    'characterLocations': characterLocations.map(
      (key, value) => MapEntry(key, value.toJson()),
    ),
    'partyGroups': partyGroups.map((value) => value.toJson()).toList(),
    'npcLocations': npcLocations.map(
      (key, value) => MapEntry(key, value.toJson()),
    ),
    'locationFlags': locationFlags,
    'currentScene': currentScene,
    'campaignState': campaignState.toJson(),
    'worldState': worldState.toJson(),
    'gmState': gmState.toJson(),
    'ruleState': ruleState.toJson(),
    'chatHistory': chatHistory.map((e) => e.toJson()).toList(),
    'eventLog': eventLog.map((e) => e.toJson()).toList(),
    'aiHostConfig': aiHostConfig.toJson(),
    'gmStateSnapshot': gmStateSnapshot.toJson(),
    'metadata': metadata,
    'toolExecutions': toolExecutions.map((item) => item.toJson()).toList(),
    'actionSnapshots': actionSnapshots.map((item) => item.toJson()).toList(),
    'sessionSummary': sessionSummary,
    'immersionState': immersionState.toJson(),
    'presentationState': presentationState.toJson(),
    'memoryState': memoryState.toJson(),
    'livingNpcState': livingNpcState.toJson(),
    'worldGenerationState': worldGenerationState.toJson(),
    'factionSimulationState': factionSimulationState.toJson(),
    'holyGrailState': holyGrailState.toJson(),
  };
  factory TRPGSession.fromJson(Map<String, Object?> j) => TRPGSession(
    schemaVersion: (j['schemaVersion'] as num?)?.toInt() ?? 1,
    id: j['id']! as String,
    title: j['title'] as String? ?? '未命名跑团',
    mode: _enumValue(TRPGMode.values, j['mode'], TRPGMode.solo),
    createdAt: DateTime.parse(j['createdAt']! as String),
    updatedAt: DateTime.parse(j['updatedAt']! as String),
    lastPlayedAt:
        DateTime.tryParse(j['lastPlayedAt'] as String? ?? '') ??
        DateTime.parse(j['updatedAt']! as String),
    status: _enumValue(
      TRPGSessionStatus.values,
      j['status'],
      TRPGSessionStatus.preparing,
    ),
    campaignId: j['campaignId'] as String? ?? 'blank',
    ruleSystemId: j['ruleSystemId'] as String? ?? 'simple_trpg',
    gmProviderConfigRef: j['gmProviderConfigRef'] as String?,
    roomOwnerPlayerId: j['roomOwnerPlayerId'] as String?,
    players: (j['players'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => TRPGPlayer.fromJson(e.cast<String, Object?>()))
        .toList(),
    playerCharacters: (j['playerCharacters'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => PlayerCharacter.fromJson(e.cast<String, Object?>()))
        .toList(),
    characterLocations: j['characterLocations'] is Map
        ? _locationMap(j['characterLocations'])
        : _legacyCharacterLocations(j),
    partyGroups: (j['partyGroups'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => PartyGroup.fromJson(item.cast<String, Object?>()))
        .toList(),
    npcLocations: _locationMap(j['npcLocations']),
    locationFlags: j['locationFlags'] is Map
        ? (j['locationFlags'] as Map).map(
            (key, value) => MapEntry(
              key.toString(),
              value is Map
                  ? value.cast<String, Object?>()
                  : <String, Object?>{},
            ),
          )
        : const {},
    currentScene: j['currentScene'] as String? ?? '',
    campaignState: CampaignState.fromJson(_map(j['campaignState'])),
    worldState: WorldState.fromJson(_map(j['worldState'])),
    gmState: GMState.fromJson(_map(j['gmState'])),
    ruleState: RuleState.fromJson(_map(j['ruleState'])),
    chatHistory: (j['chatHistory'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => TRPGMessage.fromJson(e.cast<String, Object?>()))
        .toList(),
    eventLog: (j['eventLog'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => TRPGEvent.fromJson(e.cast<String, Object?>()))
        .toList(),
    aiHostConfig: AIHostConfig.fromJson(_map(j['aiHostConfig'])),
    gmStateSnapshot: GMStateSnapshot.fromJson(_map(j['gmStateSnapshot'])),
    metadata: _map(j['metadata']),
    toolExecutions: (j['toolExecutions'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (item) => ToolExecutionRecord.fromJson(item.cast<String, Object?>()),
        )
        .toList(),
    actionSnapshots: (j['actionSnapshots'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (item) => TRPGActionSnapshot.fromJson(item.cast<String, Object?>()),
        )
        .toList(),
    sessionSummary: j['sessionSummary'] as String? ?? '',
    immersionState: TRPGImmersionState.fromJson(_map(j['immersionState'])),
    presentationState: CurrentPresentationState.fromJson(
      _map(j['presentationState']),
    ),
    memoryState: MemoryState.fromJson(_map(j['memoryState'])),
    livingNpcState: LivingNPCState.fromJson(_map(j['livingNpcState'])),
    worldGenerationState: WorldGenerationState.fromJson(
      _map(j['worldGenerationState']),
    ),
    factionSimulationState: FactionSimulationState.fromJson(
      _map(j['factionSimulationState']),
    ),
    holyGrailState: HolyGrailWarState.fromJson(_map(j['holyGrailState'])),
  );
}

class TRPGSave {
  const TRPGSave({
    required this.session,
    required this.savedAt,
    this.schemaVersion = trpgSchemaVersion,
  });
  final int schemaVersion;
  final TRPGSession session;
  final DateTime savedAt;
  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'savedAt': savedAt.toIso8601String(),
    'session': session.toJson(),
  };
  factory TRPGSave.fromJson(Map<String, Object?> j) => TRPGSave(
    schemaVersion: (j['schemaVersion'] as num?)?.toInt() ?? 1,
    savedAt: DateTime.tryParse(j['savedAt'] as String? ?? '') ?? DateTime.now(),
    session: TRPGSession.fromJson(_map(j['session'])),
  );
}

TRPGSession createLocalMultiplayerSession({
  required String title,
  required String ownerName,
  String? providerId,
  String? modelId,
}) {
  final now = DateTime.now();
  final playerId = _uuid.v4();
  return TRPGSession(
    id: _uuid.v4(),
    title: title,
    mode: TRPGMode.multiplayer,
    createdAt: now,
    updatedAt: now,
    lastPlayedAt: now,
    campaignId: 'test_campaign',
    roomOwnerPlayerId: playerId,
    players: [
      TRPGPlayer(
        playerId: playerId,
        displayName: ownerName,
        role: TRPGPlayerRole.roomOwner,
        joinedAt: now,
        isReady: true,
      ),
    ],
    currentScene: '等待冒险者集结',
    aiHostConfig: AIHostConfig(
      mode: AIHostMode.localUser,
      providerPlayerId: playerId,
      providerId: providerId,
      modelId: modelId,
      status: AIHostStatus.accepted,
    ),
    metadata: {
      'roomCode': _uuid.v4().substring(0, 6).toUpperCase(),
      'maxPlayers': 4,
    },
  );
}
