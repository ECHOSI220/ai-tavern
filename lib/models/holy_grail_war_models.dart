enum HolyGrailClass {
  saber,
  archer,
  lancer,
  rider,
  caster,
  assassin,
  berserker,
}

enum MasterArchetype {
  ordinaryMage,
  familyHeir,
  churchExecutor,
  homunculus,
  custom,
}

enum ParameterRank { e, d, c, b, a, ex }

enum NoblePhantasmType { antiUnit, antiArmy, antiFortress, special }

enum HolyGrailPhase { phase1, phase2, phase3, phase4, phase5, completed }

enum HolyGrailEnding {
  grailClaimed,
  grailDestroyed,
  grailCorrupted,
  overseer,
  hiddenTruth,
}

enum CommandSpellEffect { forceOrder, strengthen, recall }

enum InvestigationAction { observe, follow, investigate, ambush }

enum HolyAllianceStatus { active, broken, betrayed }

T _enumValue<T extends Enum>(List<T> values, Object? raw, T fallback) =>
    values.where((value) => value.name == raw).firstOrNull ?? fallback;

List<String> _strings(Object? raw) =>
    raw is List ? raw.map((value) => value.toString()).toList() : const [];

Map<String, Object?> _map(Object? raw) => raw is Map
    ? raw.map((key, value) => MapEntry(key.toString(), value))
    : const {};

class ServantParameters {
  const ServantParameters({
    this.strength = ParameterRank.c,
    this.endurance = ParameterRank.c,
    this.agility = ParameterRank.c,
    this.mana = ParameterRank.c,
    this.luck = ParameterRank.c,
    this.noblePhantasm = ParameterRank.c,
  });

  final ParameterRank strength, endurance, agility, mana, luck, noblePhantasm;

  Map<String, Object?> toJson() => {
    'strength': strength.name,
    'endurance': endurance.name,
    'agility': agility.name,
    'mana': mana.name,
    'luck': luck.name,
    'noblePhantasm': noblePhantasm.name,
  };

  factory ServantParameters.fromJson(Map<String, Object?> json) =>
      ServantParameters(
        strength: _enumValue(
          ParameterRank.values,
          json['strength'],
          ParameterRank.c,
        ),
        endurance: _enumValue(
          ParameterRank.values,
          json['endurance'],
          ParameterRank.c,
        ),
        agility: _enumValue(
          ParameterRank.values,
          json['agility'],
          ParameterRank.c,
        ),
        mana: _enumValue(ParameterRank.values, json['mana'], ParameterRank.c),
        luck: _enumValue(ParameterRank.values, json['luck'], ParameterRank.c),
        noblePhantasm: _enumValue(
          ParameterRank.values,
          json['noblePhantasm'],
          ParameterRank.c,
        ),
      );
}

class NoblePhantasm {
  const NoblePhantasm({
    required this.name,
    required this.hiddenName,
    required this.rank,
    required this.type,
    required this.description,
    this.cost = 30,
    this.condition = '魔力充足且从者愿意执行',
    this.effect = '',
  });

  final String name, hiddenName, description, condition, effect;
  final ParameterRank rank;
  final NoblePhantasmType type;
  final int cost;

  Map<String, Object?> toJson() => {
    'name': name,
    'hiddenName': hiddenName,
    'rank': rank.name,
    'type': type.name,
    'description': description,
    'cost': cost,
    'condition': condition,
    'effect': effect,
  };

  factory NoblePhantasm.fromJson(Map<String, Object?> json) => NoblePhantasm(
    name: json['name'] as String? ?? '未明宝具',
    hiddenName: json['hiddenName'] as String? ?? '真名未解放',
    rank: _enumValue(ParameterRank.values, json['rank'], ParameterRank.c),
    type: _enumValue(
      NoblePhantasmType.values,
      json['type'],
      NoblePhantasmType.special,
    ),
    description: json['description'] as String? ?? '',
    cost: (json['cost'] as num?)?.toInt() ?? 30,
    condition: json['condition'] as String? ?? '',
    effect: json['effect'] as String? ?? '',
  );
}

class MasterServantRelationship {
  const MasterServantRelationship({
    required this.masterId,
    required this.servantId,
    this.trust = 0,
    this.respect = 0,
    this.obedience = 0,
    this.affection = 0,
    this.conflict = 0,
    this.fear = 0,
  });

  final String masterId, servantId;
  final int trust, respect, obedience, affection, conflict, fear;
  static int clamp(int value) => value.clamp(-100, 100);

  MasterServantRelationship copyWith({
    int? trust,
    int? respect,
    int? obedience,
    int? affection,
    int? conflict,
    int? fear,
  }) => MasterServantRelationship(
    masterId: masterId,
    servantId: servantId,
    trust: clamp(trust ?? this.trust),
    respect: clamp(respect ?? this.respect),
    obedience: clamp(obedience ?? this.obedience),
    affection: clamp(affection ?? this.affection),
    conflict: clamp(conflict ?? this.conflict),
    fear: clamp(fear ?? this.fear),
  );

  bool get mayRefuse => trust < -25 || obedience < -35 || conflict > 65;
  bool get mayBetray => trust < -65 && conflict > 70;

  Map<String, Object?> toJson() => {
    'masterId': masterId,
    'servantId': servantId,
    'trust': trust,
    'respect': respect,
    'obedience': obedience,
    'affection': affection,
    'conflict': conflict,
    'fear': fear,
  };

  factory MasterServantRelationship.fromJson(Map<String, Object?> json) =>
      MasterServantRelationship(
        masterId: json['masterId'] as String? ?? '',
        servantId: json['servantId'] as String? ?? '',
        trust: (json['trust'] as num?)?.toInt() ?? 0,
        respect: (json['respect'] as num?)?.toInt() ?? 0,
        obedience: (json['obedience'] as num?)?.toInt() ?? 0,
        affection: (json['affection'] as num?)?.toInt() ?? 0,
        conflict: (json['conflict'] as num?)?.toInt() ?? 0,
        fear: (json['fear'] as num?)?.toInt() ?? 0,
      );
}

class MasterCharacter {
  const MasterCharacter({
    required this.masterId,
    required this.characterId,
    required this.name,
    required this.archetype,
    this.ownerPlayerId,
    this.magicAbility = 50,
    this.origin = '未明',
    this.family = '无名家系',
    this.wish = '',
    this.personality = '',
    this.resources = const {},
    this.commandSpells = 3,
    this.servantId,
    this.knowledge = const [],
    this.alive = true,
    this.locationId = 'fuyuki_city',
  });

  final String masterId, characterId, name, origin, family, wish, personality;
  final String? ownerPlayerId, servantId;
  final MasterArchetype archetype;
  final int magicAbility, commandSpells;
  final Map<String, Object?> resources;
  final List<String> knowledge;
  final bool alive;
  final String locationId;

  MasterCharacter copyWith({
    String? ownerPlayerId,
    String? servantId,
    int? commandSpells,
    List<String>? knowledge,
    bool? alive,
    String? locationId,
  }) => MasterCharacter(
    masterId: masterId,
    characterId: characterId,
    name: name,
    archetype: archetype,
    ownerPlayerId: ownerPlayerId ?? this.ownerPlayerId,
    magicAbility: magicAbility,
    origin: origin,
    family: family,
    wish: wish,
    personality: personality,
    resources: resources,
    commandSpells: commandSpells ?? this.commandSpells,
    servantId: servantId ?? this.servantId,
    knowledge: knowledge ?? this.knowledge,
    alive: alive ?? this.alive,
    locationId: locationId ?? this.locationId,
  );

  Map<String, Object?> toJson() => {
    'masterId': masterId,
    'characterId': characterId,
    'name': name,
    'archetype': archetype.name,
    'ownerPlayerId': ownerPlayerId,
    'magicAbility': magicAbility,
    'origin': origin,
    'family': family,
    'wish': wish,
    'personality': personality,
    'resources': resources,
    'commandSpells': commandSpells,
    'servantId': servantId,
    'knowledge': knowledge,
    'alive': alive,
    'locationId': locationId,
  };

  factory MasterCharacter.fromJson(Map<String, Object?> json) =>
      MasterCharacter(
        masterId: json['masterId'] as String? ?? '',
        characterId: json['characterId'] as String? ?? '',
        name: json['name'] as String? ?? '无名御主',
        archetype: _enumValue(
          MasterArchetype.values,
          json['archetype'],
          MasterArchetype.custom,
        ),
        ownerPlayerId: json['ownerPlayerId'] as String?,
        magicAbility: (json['magicAbility'] as num?)?.toInt() ?? 50,
        origin: json['origin'] as String? ?? '未明',
        family: json['family'] as String? ?? '无名家系',
        wish: json['wish'] as String? ?? '',
        personality: json['personality'] as String? ?? '',
        resources: _map(json['resources']),
        commandSpells: (json['commandSpells'] as num?)?.toInt() ?? 3,
        servantId: json['servantId'] as String?,
        knowledge: _strings(json['knowledge']),
        alive: json['alive'] as bool? ?? true,
        locationId: json['locationId'] as String? ?? 'fuyuki_city',
      );
}

class ServantCharacter {
  const ServantCharacter({
    required this.servantId,
    required this.classType,
    required this.trueName,
    required this.legend,
    required this.appearance,
    required this.personality,
    required this.parameters,
    required this.skills,
    required this.noblePhantasm,
    required this.masterId,
    this.relationship = 0,
    this.alive = true,
    this.trueNameRevealedTo = const [],
    this.observedAbilityTags = const [],
  });

  final String servantId, trueName, legend, appearance, personality, masterId;
  final HolyGrailClass classType;
  final ServantParameters parameters;
  final List<String> skills, trueNameRevealedTo, observedAbilityTags;
  final NoblePhantasm noblePhantasm;
  final int relationship;
  final bool alive;

  ServantCharacter copyWith({
    bool? alive,
    int? relationship,
    List<String>? trueNameRevealedTo,
    List<String>? observedAbilityTags,
  }) => ServantCharacter(
    servantId: servantId,
    classType: classType,
    trueName: trueName,
    legend: legend,
    appearance: appearance,
    personality: personality,
    parameters: parameters,
    skills: skills,
    noblePhantasm: noblePhantasm,
    masterId: masterId,
    relationship: relationship ?? this.relationship,
    alive: alive ?? this.alive,
    trueNameRevealedTo: trueNameRevealedTo ?? this.trueNameRevealedTo,
    observedAbilityTags: observedAbilityTags ?? this.observedAbilityTags,
  );

  Map<String, Object?> toJson({bool revealSecrets = true}) => {
    'servantId': servantId,
    'classType': classType.name,
    'trueName': revealSecrets ? trueName : null,
    'legend': revealSecrets ? legend : null,
    'appearance': appearance,
    'personality': revealSecrets ? personality : '尚未了解',
    'parameters': revealSecrets ? parameters.toJson() : const {},
    'skills': revealSecrets ? skills : observedAbilityTags,
    'noblePhantasm': revealSecrets
        ? noblePhantasm.toJson()
        : {'name': '未明宝具', 'rank': '?', 'type': 'unknown'},
    'masterId': revealSecrets ? masterId : null,
    'relationship': revealSecrets ? relationship : null,
    'alive': alive,
    'trueNameRevealedTo': revealSecrets ? trueNameRevealedTo : const [],
    'observedAbilityTags': observedAbilityTags,
  };

  factory ServantCharacter.fromJson(Map<String, Object?> json) =>
      ServantCharacter(
        servantId: json['servantId'] as String? ?? '',
        classType: _enumValue(
          HolyGrailClass.values,
          json['classType'],
          HolyGrailClass.saber,
        ),
        trueName: json['trueName'] as String? ?? 'UNKNOWN',
        legend: json['legend'] as String? ?? '',
        appearance: json['appearance'] as String? ?? '',
        personality: json['personality'] as String? ?? '',
        parameters: ServantParameters.fromJson(_map(json['parameters'])),
        skills: _strings(json['skills']),
        noblePhantasm: NoblePhantasm.fromJson(_map(json['noblePhantasm'])),
        masterId: json['masterId'] as String? ?? '',
        relationship: (json['relationship'] as num?)?.toInt() ?? 0,
        alive: json['alive'] as bool? ?? true,
        trueNameRevealedTo: _strings(json['trueNameRevealedTo']),
        observedAbilityTags: _strings(json['observedAbilityTags']),
      );
}

class HolyGrailInformation {
  const HolyGrailInformation({
    required this.ownerPlayerId,
    this.knownServantIds = const [],
    this.observedAbilities = const {},
    this.suspectedIdentity = const {},
    this.knownMasterIds = const [],
  });

  final String ownerPlayerId;
  final List<String> knownServantIds, knownMasterIds;
  final Map<String, List<String>> observedAbilities;
  final Map<String, String> suspectedIdentity;

  HolyGrailInformation copyWith({
    List<String>? knownServantIds,
    Map<String, List<String>>? observedAbilities,
    Map<String, String>? suspectedIdentity,
    List<String>? knownMasterIds,
  }) => HolyGrailInformation(
    ownerPlayerId: ownerPlayerId,
    knownServantIds: knownServantIds ?? this.knownServantIds,
    observedAbilities: observedAbilities ?? this.observedAbilities,
    suspectedIdentity: suspectedIdentity ?? this.suspectedIdentity,
    knownMasterIds: knownMasterIds ?? this.knownMasterIds,
  );

  Map<String, Object?> toJson() => {
    'ownerPlayerId': ownerPlayerId,
    'knownServantIds': knownServantIds,
    'observedAbilities': observedAbilities,
    'suspectedIdentity': suspectedIdentity,
    'knownMasterIds': knownMasterIds,
  };

  factory HolyGrailInformation.fromJson(Map<String, Object?> json) =>
      HolyGrailInformation(
        ownerPlayerId: json['ownerPlayerId'] as String? ?? '',
        knownServantIds: _strings(json['knownServantIds']),
        observedAbilities: json['observedAbilities'] is Map
            ? (json['observedAbilities'] as Map).map(
                (key, value) => MapEntry(key.toString(), _strings(value)),
              )
            : const {},
        suspectedIdentity: json['suspectedIdentity'] is Map
            ? (json['suspectedIdentity'] as Map).map(
                (key, value) => MapEntry(key.toString(), value.toString()),
              )
            : const {},
        knownMasterIds: _strings(json['knownMasterIds']),
      );
}

class HolyAlliance {
  const HolyAlliance({
    required this.allianceId,
    required this.masterIds,
    required this.purpose,
    this.status = HolyAllianceStatus.active,
    this.terms = const [],
  });

  final String allianceId, purpose;
  final List<String> masterIds, terms;
  final HolyAllianceStatus status;

  HolyAlliance copyWith({HolyAllianceStatus? status}) => HolyAlliance(
    allianceId: allianceId,
    masterIds: masterIds,
    purpose: purpose,
    status: status ?? this.status,
    terms: terms,
  );

  Map<String, Object?> toJson() => {
    'allianceId': allianceId,
    'masterIds': masterIds,
    'purpose': purpose,
    'status': status.name,
    'terms': terms,
  };

  factory HolyAlliance.fromJson(Map<String, Object?> json) => HolyAlliance(
    allianceId: json['allianceId'] as String? ?? '',
    masterIds: _strings(json['masterIds']),
    purpose: json['purpose'] as String? ?? '',
    status: _enumValue(
      HolyAllianceStatus.values,
      json['status'],
      HolyAllianceStatus.active,
    ),
    terms: _strings(json['terms']),
  );
}

class HolyGrailHistoryEntry {
  const HolyGrailHistoryEntry({
    required this.id,
    required this.type,
    required this.summary,
    required this.createdAt,
    this.visibilityPlayerIds = const [],
    this.metadata = const {},
  });

  final String id, type, summary;
  final DateTime createdAt;
  final List<String> visibilityPlayerIds;
  final Map<String, Object?> metadata;

  Map<String, Object?> toJson() => {
    'id': id,
    'type': type,
    'summary': summary,
    'createdAt': createdAt.toIso8601String(),
    'visibilityPlayerIds': visibilityPlayerIds,
    'metadata': metadata,
  };

  factory HolyGrailHistoryEntry.fromJson(Map<String, Object?> json) =>
      HolyGrailHistoryEntry(
        id: json['id'] as String? ?? '',
        type: json['type'] as String? ?? 'system',
        summary: json['summary'] as String? ?? '',
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
        visibilityPlayerIds: _strings(json['visibilityPlayerIds']),
        metadata: _map(json['metadata']),
      );
}

class HolyGrailWarState {
  const HolyGrailWarState({
    this.initialized = false,
    this.phase = HolyGrailPhase.phase1,
    this.masters = const [],
    this.servants = const [],
    this.relationships = const [],
    this.informationByPlayer = const {},
    this.alliances = const [],
    this.history = const [],
    this.ending,
    this.winnerMasterId,
    this.anomalyLevel = 0,
  });

  final bool initialized;
  final HolyGrailPhase phase;
  final List<MasterCharacter> masters;
  final List<ServantCharacter> servants;
  final List<MasterServantRelationship> relationships;
  final Map<String, HolyGrailInformation> informationByPlayer;
  final List<HolyAlliance> alliances;
  final List<HolyGrailHistoryEntry> history;
  final HolyGrailEnding? ending;
  final String? winnerMasterId;
  final int anomalyLevel;

  HolyGrailWarState copyWith({
    bool? initialized,
    HolyGrailPhase? phase,
    List<MasterCharacter>? masters,
    List<ServantCharacter>? servants,
    List<MasterServantRelationship>? relationships,
    Map<String, HolyGrailInformation>? informationByPlayer,
    List<HolyAlliance>? alliances,
    List<HolyGrailHistoryEntry>? history,
    HolyGrailEnding? ending,
    String? winnerMasterId,
    int? anomalyLevel,
  }) => HolyGrailWarState(
    initialized: initialized ?? this.initialized,
    phase: phase ?? this.phase,
    masters: masters ?? this.masters,
    servants: servants ?? this.servants,
    relationships: relationships ?? this.relationships,
    informationByPlayer: informationByPlayer ?? this.informationByPlayer,
    alliances: alliances ?? this.alliances,
    history: history ?? this.history,
    ending: ending ?? this.ending,
    winnerMasterId: winnerMasterId ?? this.winnerMasterId,
    anomalyLevel: anomalyLevel ?? this.anomalyLevel,
  );

  HolyGrailWarState publicView() => HolyGrailWarState(
    initialized: initialized,
    phase: phase,
    // Ownership does not make a dossier public. Every Master is redacted in
    // the shared snapshot; each player receives their own full view through
    // [forPlayer].
    masters: masters.map((master) => _redactedMaster(master)).toList(),
    servants: servants
        .map(
          (servant) =>
              ServantCharacter.fromJson(servant.toJson(revealSecrets: false)),
        )
        .toList(),
    alliances: alliances
        .where((value) => value.status == HolyAllianceStatus.active)
        .toList(),
    history: history
        .where((value) => value.visibilityPlayerIds.isEmpty)
        .toList(),
    anomalyLevel: anomalyLevel,
  );

  HolyGrailWarState forPlayer(String playerId) {
    final info = informationByPlayer[playerId];
    final ownedMasters = masters
        .where((value) => value.ownerPlayerId == playerId)
        .toList();
    final ownedServants = ownedMasters
        .map((value) => value.servantId)
        .whereType<String>()
        .toSet();
    final knownServants = {...?info?.knownServantIds, ...ownedServants};
    final visibleMasters = masters.map((master) {
      if (master.ownerPlayerId == playerId) return master;
      final identityKnown =
          info?.knownMasterIds.contains(master.masterId) ?? false;
      return _redactedMaster(master, revealIdentity: identityKnown);
    }).toList();
    final visibleServants = servants.map((servant) {
      final reveal =
          knownServants.contains(servant.servantId) &&
          (ownedServants.contains(servant.servantId) ||
              servant.trueNameRevealedTo.contains(playerId));
      final json = servant.toJson(revealSecrets: reveal);
      if (!reveal) {
        json['skills'] = info?.observedAbilities[servant.servantId] ?? const [];
      }
      return ServantCharacter.fromJson(json);
    }).toList();
    return copyWith(
      masters: visibleMasters,
      servants: visibleServants,
      relationships: relationships
          .where(
            (value) =>
                ownedMasters.any((master) => master.masterId == value.masterId),
          )
          .toList(),
      informationByPlayer: info == null ? const {} : {playerId: info},
      history: history
          .where(
            (value) =>
                value.visibilityPlayerIds.isEmpty ||
                value.visibilityPlayerIds.contains(playerId),
          )
          .toList(),
    );
  }

  MasterCharacter _redactedMaster(
    MasterCharacter master, {
    bool revealIdentity = false,
  }) => MasterCharacter(
    masterId: master.masterId,
    characterId: '',
    name: revealIdentity ? master.name : '身份不明的御主',
    archetype: revealIdentity ? master.archetype : MasterArchetype.custom,
    ownerPlayerId: null,
    magicAbility: 0,
    origin: '未知',
    family: revealIdentity ? master.family : '未知',
    wish: '',
    personality: '',
    resources: const {},
    commandSpells: 0,
    servantId: null,
    knowledge: const [],
    alive: master.alive,
    locationId: 'unknown',
  );

  Map<String, Object?> toJson() => {
    'initialized': initialized,
    'phase': phase.name,
    'masters': masters.map((value) => value.toJson()).toList(),
    'servants': servants.map((value) => value.toJson()).toList(),
    'relationships': relationships.map((value) => value.toJson()).toList(),
    'informationByPlayer': informationByPlayer.map(
      (key, value) => MapEntry(key, value.toJson()),
    ),
    'alliances': alliances.map((value) => value.toJson()).toList(),
    'history': history.map((value) => value.toJson()).toList(),
    'ending': ending?.name,
    'winnerMasterId': winnerMasterId,
    'anomalyLevel': anomalyLevel,
  };

  factory HolyGrailWarState.fromJson(
    Map<String, Object?> json,
  ) => HolyGrailWarState(
    initialized: json['initialized'] as bool? ?? false,
    phase: _enumValue(
      HolyGrailPhase.values,
      json['phase'],
      HolyGrailPhase.phase1,
    ),
    masters: (json['masters'] as List? ?? const [])
        .whereType<Map>()
        .map((value) => MasterCharacter.fromJson(value.cast<String, Object?>()))
        .toList(),
    servants: (json['servants'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (value) => ServantCharacter.fromJson(value.cast<String, Object?>()),
        )
        .toList(),
    relationships: (json['relationships'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (value) =>
              MasterServantRelationship.fromJson(value.cast<String, Object?>()),
        )
        .toList(),
    informationByPlayer: json['informationByPlayer'] is Map
        ? (json['informationByPlayer'] as Map).map(
            (key, value) => MapEntry(
              key.toString(),
              HolyGrailInformation.fromJson(_map(value)),
            ),
          )
        : const {},
    alliances: (json['alliances'] as List? ?? const [])
        .whereType<Map>()
        .map((value) => HolyAlliance.fromJson(value.cast<String, Object?>()))
        .toList(),
    history: (json['history'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (value) =>
              HolyGrailHistoryEntry.fromJson(value.cast<String, Object?>()),
        )
        .toList(),
    ending: json['ending'] == null
        ? null
        : _enumValue(
            HolyGrailEnding.values,
            json['ending'],
            HolyGrailEnding.hiddenTruth,
          ),
    winnerMasterId: json['winnerMasterId'] as String?,
    anomalyLevel: (json['anomalyLevel'] as num?)?.toInt() ?? 0,
  );
}
