enum CharacterMovementState { stationary, moving, blocked, unknown }

class CharacterLocationState {
  const CharacterLocationState({
    required this.characterId,
    this.sceneId = '',
    this.locationId = '',
    this.subLocationId,
    this.groupId = '',
    this.enteredAt,
    this.previousSceneId,
    this.previousLocationId,
    this.movementState = CharacterMovementState.stationary,
    this.metadata = const {},
  });

  final String characterId, sceneId, locationId, groupId;
  final String? subLocationId, previousSceneId, previousLocationId;
  final DateTime? enteredAt;
  final CharacterMovementState movementState;
  final Map<String, Object?> metadata;

  CharacterLocationState copyWith({
    String? sceneId,
    String? locationId,
    String? subLocationId,
    String? groupId,
    DateTime? enteredAt,
    String? previousSceneId,
    String? previousLocationId,
    CharacterMovementState? movementState,
    Map<String, Object?>? metadata,
  }) => CharacterLocationState(
    characterId: characterId,
    sceneId: sceneId ?? this.sceneId,
    locationId: locationId ?? this.locationId,
    subLocationId: subLocationId ?? this.subLocationId,
    groupId: groupId ?? this.groupId,
    enteredAt: enteredAt ?? this.enteredAt,
    previousSceneId: previousSceneId ?? this.previousSceneId,
    previousLocationId: previousLocationId ?? this.previousLocationId,
    movementState: movementState ?? this.movementState,
    metadata: metadata ?? this.metadata,
  );

  Map<String, Object?> toJson() => {
    'characterId': characterId,
    'sceneId': sceneId,
    'locationId': locationId,
    'subLocationId': subLocationId,
    'groupId': groupId,
    'enteredAt': enteredAt?.toIso8601String(),
    'previousSceneId': previousSceneId,
    'previousLocationId': previousLocationId,
    'movementState': movementState.name,
    'metadata': metadata,
  };

  factory CharacterLocationState.fromJson(Map<String, Object?> json) =>
      CharacterLocationState(
        characterId: json['characterId'] as String? ?? '',
        sceneId: json['sceneId'] as String? ?? '',
        locationId: json['locationId'] as String? ?? '',
        subLocationId: json['subLocationId'] as String?,
        groupId: json['groupId'] as String? ?? '',
        enteredAt: DateTime.tryParse(json['enteredAt'] as String? ?? ''),
        previousSceneId: json['previousSceneId'] as String?,
        previousLocationId: json['previousLocationId'] as String?,
        movementState: CharacterMovementState.values.firstWhere(
          (value) => value.name == json['movementState'],
          orElse: () => CharacterMovementState.stationary,
        ),
        metadata: json['metadata'] is Map
            ? (json['metadata'] as Map).cast<String, Object?>()
            : const {},
      );
}

enum PartyGroupStatus { active, merged, disbanded }

class PartyGroup {
  const PartyGroup({
    required this.groupId,
    this.sceneId = '',
    this.locationId = '',
    this.characterIds = const [],
    this.createdAt,
    this.updatedAt,
    this.status = PartyGroupStatus.active,
    this.metadata = const {},
  });

  final String groupId, sceneId, locationId;
  final List<String> characterIds;
  final DateTime? createdAt, updatedAt;
  final PartyGroupStatus status;
  final Map<String, Object?> metadata;

  Map<String, Object?> toJson() => {
    'groupId': groupId,
    'sceneId': sceneId,
    'locationId': locationId,
    'characterIds': characterIds,
    'createdAt': createdAt?.toIso8601String(),
    'updatedAt': updatedAt?.toIso8601String(),
    'status': status.name,
    'metadata': metadata,
  };

  factory PartyGroup.fromJson(Map<String, Object?> json) => PartyGroup(
    groupId: json['groupId'] as String? ?? '',
    sceneId: json['sceneId'] as String? ?? '',
    locationId: json['locationId'] as String? ?? '',
    characterIds: (json['characterIds'] as List? ?? const [])
        .map((value) => value.toString())
        .toList(),
    createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
    updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
    status: PartyGroupStatus.values.firstWhere(
      (value) => value.name == json['status'],
      orElse: () => PartyGroupStatus.active,
    ),
    metadata: json['metadata'] is Map
        ? (json['metadata'] as Map).cast<String, Object?>()
        : const {},
  );
}

/// Recomputes groups from authoritative character locations. Secrets and
/// knowledge are intentionally not touched when characters merge.
class PartyGroupManager {
  const PartyGroupManager();

  List<PartyGroup> rebuild(
    Map<String, CharacterLocationState> locations, {
    List<PartyGroup> previous = const [],
    DateTime? now,
  }) {
    final timestamp = now ?? DateTime.now();
    final buckets = <String, List<String>>{};
    for (final location in locations.values) {
      final key = '${location.sceneId}\u0000${location.locationId}';
      (buckets[key] ??= []).add(location.characterId);
    }
    return buckets.entries.map((entry) {
      final ids = [...entry.value]..sort();
      final old = previous.where((group) {
        final oldIds = [...group.characterIds]..sort();
        return oldIds.join('|') == ids.join('|') &&
            group.status == PartyGroupStatus.active;
      }).firstOrNull;
      final split = entry.key.split('\u0000');
      return PartyGroup(
        groupId: old?.groupId ?? 'group-${_stableId(ids.join('|'))}',
        sceneId: split.first,
        locationId: split.length > 1 ? split[1] : '',
        characterIds: ids,
        createdAt: old?.createdAt ?? timestamp,
        updatedAt: timestamp,
      );
    }).toList();
  }

  static String _stableId(String value) {
    var hash = 2166136261;
    for (final unit in value.codeUnits) {
      hash = (hash ^ unit) * 16777619 & 0x7fffffff;
    }
    return hash.toRadixString(36);
  }
}
