import 'dart:convert';
import 'package:uuid/uuid.dart';

typedef SocialData = Map<String, Object?>;

enum MemoryScope { tavernChat, social, trpg, globalCharacter }

enum SocialSimulationQuality { lowCost, balanced, rich }

enum SocialTimeMode { realTime, accelerated, gameTime }

/// Persisted envelope shared by SQLite and the private cloud replica.
/// Revision is local optimistic concurrency; baseVersion is the cloud revision.
class SocialRecord {
  const SocialRecord({
    required this.id,
    required this.kind,
    required this.data,
    required this.createdAt,
    this.worldId = 'default',
    this.characterId = '',
    this.parentId = '',
    this.revision = 1,
    this.baseVersion = 0,
    this.deleted = false,
    this.dirty = true,
    this.conflict,
  });
  factory SocialRecord.create(
    String kind,
    SocialData data, {
    String? id,
    String worldId = 'default',
    String characterId = '',
    String parentId = '',
    DateTime? now,
  }) => SocialRecord(
    id: id ?? const Uuid().v4(),
    kind: kind,
    data: data,
    worldId: worldId,
    characterId: characterId,
    parentId: parentId,
    createdAt: (now ?? DateTime.now()).toUtc().millisecondsSinceEpoch,
  );
  final String id, kind, worldId, characterId, parentId;
  final SocialData data;
  final int createdAt, revision, baseVersion;
  final bool deleted, dirty;
  final SocialData? conflict;
  String text(String key, [String fallback = '']) =>
      data[key] as String? ?? fallback;
  int number(String key, [int fallback = 0]) =>
      (data[key] as num?)?.toInt() ?? fallback;
  bool flag(String key, [bool fallback = false]) =>
      data[key] as bool? ?? fallback;
  List<String> strings(String key) =>
      (data[key] as List? ?? []).whereType<String>().toList();
  SocialRecord change(SocialData patch, {bool? deleted}) => SocialRecord(
    id: id,
    kind: kind,
    data: {...data, ...patch},
    createdAt: createdAt,
    worldId: worldId,
    characterId: characterId,
    parentId: parentId,
    revision: revision + 1,
    baseVersion: baseVersion,
    deleted: deleted ?? this.deleted,
    conflict: conflict,
  );
  SocialData toCloud() => {
    'id': id,
    'kind': kind,
    'world_id': worldId,
    'character_id': characterId,
    'parent_id': parentId,
    'payload': data,
    'created_at_ms': createdAt,
    'deleted': deleted,
    'expected_version': baseVersion,
  };
  SocialData toLocal(String owner) => {
    'owner_id': owner,
    'id': id,
    'kind': kind,
    'world_id': worldId,
    'character_id': characterId,
    'parent_id': parentId,
    'payload': jsonEncode(data),
    'created_at_ms': createdAt,
    'revision': revision,
    'base_version': baseVersion,
    'deleted': deleted ? 1 : 0,
    'dirty': dirty ? 1 : 0,
    'conflict': conflict == null ? null : jsonEncode(conflict),
  };
  factory SocialRecord.fromLocal(Map<String, Object?> row) => SocialRecord(
    id: row['id']! as String,
    kind: row['kind']! as String,
    data: (jsonDecode(row['payload']! as String) as Map)
        .cast<String, Object?>(),
    worldId: row['world_id']! as String,
    characterId: row['character_id']! as String,
    parentId: row['parent_id']! as String,
    createdAt: row['created_at_ms']! as int,
    revision: row['revision']! as int,
    baseVersion: row['base_version']! as int,
    deleted: row['deleted'] == 1,
    dirty: row['dirty'] == 1,
    conflict: row['conflict'] == null
        ? null
        : (jsonDecode(row['conflict']! as String) as Map)
              .cast<String, Object?>(),
  );
}

class CharacterSocialProfile {
  const CharacterSocialProfile({
    this.postFrequency = 1,
    this.initiative = .3,
    this.socialEnergy = .5,
    this.privacy = .7,
    this.replySeconds = 2,
    this.postingStyle = '简短自然，遵守角色语言',
    this.nightOwl = false,
  });
  final double postFrequency, initiative, socialEnergy, privacy;
  final int replySeconds;
  final String postingStyle;
  final bool nightOwl;
  SocialData toJson() => {
    'postFrequency': postFrequency,
    'initiative': initiative,
    'socialEnergy': socialEnergy,
    'privacy': privacy,
    'replySeconds': replySeconds,
    'postingStyle': postingStyle,
    'nightOwl': nightOwl,
    'activeChatFrequency': initiative,
    'likeFrequency': socialEnergy,
    'commentFrequency': initiative,
    'onlinePattern': nightOwl ? 'night' : 'day',
    'privacyPreference': privacy,
    'commentStyle': postingStyle,
    'onlinePersonality': 'follow_character_card',
    'emojiStyle': socialEnergy > .7 ? '适量' : '克制',
    'photoPostingPreference': 'text_first',
    'deletePostChance': 0.02,
    'lateNightActivity': nightOwl,
    'morningActivity': !nightOwl,
    'relationshipSensitivity': 0.5,
    'initiativeLevel': initiative,
  };
  factory CharacterSocialProfile.fromJson(SocialData v) =>
      CharacterSocialProfile(
        postFrequency: (v['postFrequency'] as num? ?? 1).toDouble(),
        initiative: (v['initiative'] as num? ?? .3).toDouble(),
        socialEnergy: (v['socialEnergy'] as num? ?? .5).toDouble(),
        privacy: (v['privacy'] as num? ?? .7).toDouble(),
        replySeconds: (v['replySeconds'] as num? ?? 2).toInt(),
        postingStyle: v['postingStyle'] as String? ?? '简短自然',
        nightOwl: v['nightOwl'] == true,
      );
}

class SocialRelationshipState {
  static const dimensions = [
    'familiarity',
    'trust',
    'closeness',
    'attachment',
    'respect',
    'tension',
    'jealousy',
    'dependence',
    'wariness',
  ];
  static SocialData apply(SocialData before, SocialData delta) => {
    for (final key in dimensions)
      key:
          (((before[key] as num? ?? (key == 'respect' ? 30 : 0))) +
                  (delta[key] as num? ?? 0).clamp(-5, 5))
              .clamp(0, 100)
              .toInt(),
  };
  static String label(SocialData value) {
    if ((value['tension'] as num? ?? 0) > 45) return '关系有些紧张';
    if ((value['trust'] as num? ?? 0) > 60 &&
        (value['closeness'] as num? ?? 0) > 55) {
      return '彼此信赖';
    }
    if ((value['familiarity'] as num? ?? 0) > 30) return '逐渐熟悉';
    return '正在相互了解';
  }
}
