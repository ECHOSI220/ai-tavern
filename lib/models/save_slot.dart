import 'package:uuid/uuid.dart';

import 'character.dart';
import 'chat_message.dart';
import 'lore_entry.dart';
import 'memory_summary.dart';
import 'play_mode.dart';

const defaultRoleplayRules = '''你正在参与一个持续进行的互动式角色扮演故事。
请依据世界观、剧情前提、玩家信息、角色资料、世界书和历史对话继续故事。
保持角色性格、知识范围、关系和说话方式一致，不要跳出角色讨论自己是 AI。
优先通过动作、表情、环境和语言自然推动剧情。
玩家拥有自己的角色控制权，不要替玩家做重大选择。''';

class SaveSlot {
  const SaveSlot({
    required this.id,
    required this.name,
    this.sourceStoryCardId,
    this.coverImage,
    this.playerName = '',
    this.playerAvatar,
    this.playerDescription = '',
    this.scenario = '',
    this.worldSetting = '',
    this.roleplayRules = defaultRoleplayRules,
    this.openingMessage = '',
    this.characters = const [],
    this.lorebook = const [],
    this.messages = const [],
    this.conversationMemory = '',
    this.playMode = PlayMode.freeform,
    this.choiceCount = 6,
    this.pendingChoices = const [],
    this.storedMessageCount,
    required this.memorySummary,
    required this.createdAt,
    required this.updatedAt,
    required this.lastPlayedAt,
  });

  factory SaveSlot.create({
    required String name,
    String? coverImage,
    String playerName = '',
    String? playerAvatar,
    String playerDescription = '',
    String scenario = '',
    String worldSetting = '',
    String roleplayRules = defaultRoleplayRules,
    String openingMessage = '',
    PlayMode playMode = PlayMode.freeform,
    int choiceCount = 6,
  }) {
    final now = DateTime.now();
    return SaveSlot(
      id: const Uuid().v4(),
      name: name,
      coverImage: coverImage,
      playerName: playerName,
      playerAvatar: playerAvatar,
      playerDescription: playerDescription,
      scenario: scenario,
      worldSetting: worldSetting,
      roleplayRules: roleplayRules,
      openingMessage: openingMessage,
      playMode: playMode,
      choiceCount: choiceCount.clamp(2, 10),
      memorySummary: MemorySummary(updatedAt: now),
      createdAt: now,
      updatedAt: now,
      lastPlayedAt: now,
    );
  }

  final String id;
  final String name;
  final String? sourceStoryCardId;
  final String? coverImage;
  final String playerName;
  final String? playerAvatar;
  final String playerDescription;
  final String scenario;
  final String worldSetting;
  final String roleplayRules;
  final String openingMessage;
  final List<Character> characters;
  final List<LoreEntry> lorebook;
  final List<ChatMessage> messages;
  final String conversationMemory;
  final PlayMode playMode;
  final int choiceCount;
  final List<String> pendingChoices;
  final int? storedMessageCount;
  int get messageCount => storedMessageCount ?? messages.length;
  final MemorySummary memorySummary;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime lastPlayedAt;

  SaveSlot copyWith({
    String? id,
    String? name,
    String? sourceStoryCardId,
    bool clearSourceStoryCardId = false,
    String? coverImage,
    bool clearCoverImage = false,
    String? playerName,
    String? playerAvatar,
    bool clearPlayerAvatar = false,
    String? playerDescription,
    String? scenario,
    String? worldSetting,
    String? roleplayRules,
    String? openingMessage,
    List<Character>? characters,
    List<LoreEntry>? lorebook,
    List<ChatMessage>? messages,
    String? conversationMemory,
    PlayMode? playMode,
    int? choiceCount,
    List<String>? pendingChoices,
    int? storedMessageCount,
    MemorySummary? memorySummary,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastPlayedAt,
  }) => SaveSlot(
    id: id ?? this.id,
    name: name ?? this.name,
    sourceStoryCardId: clearSourceStoryCardId
        ? null
        : sourceStoryCardId ?? this.sourceStoryCardId,
    coverImage: clearCoverImage ? null : coverImage ?? this.coverImage,
    playerName: playerName ?? this.playerName,
    playerAvatar: clearPlayerAvatar ? null : playerAvatar ?? this.playerAvatar,
    playerDescription: playerDescription ?? this.playerDescription,
    scenario: scenario ?? this.scenario,
    worldSetting: worldSetting ?? this.worldSetting,
    roleplayRules: roleplayRules ?? this.roleplayRules,
    openingMessage: openingMessage ?? this.openingMessage,
    characters: characters ?? this.characters,
    lorebook: lorebook ?? this.lorebook,
    messages: messages ?? this.messages,
    conversationMemory: conversationMemory ?? this.conversationMemory,
    playMode: playMode ?? this.playMode,
    choiceCount: (choiceCount ?? this.choiceCount).clamp(2, 10),
    pendingChoices: pendingChoices ?? this.pendingChoices,
    storedMessageCount: storedMessageCount ?? this.storedMessageCount,
    memorySummary: memorySummary ?? this.memorySummary,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'sourceStoryCardId': sourceStoryCardId,
    'coverImage': coverImage,
    'playerName': playerName,
    'playerAvatar': playerAvatar,
    'playerDescription': playerDescription,
    'scenario': scenario,
    'worldSetting': worldSetting,
    'roleplayRules': roleplayRules,
    'openingMessage': openingMessage,
    'characters': characters.map((item) => item.toJson()).toList(),
    'lorebook': lorebook.map((item) => item.toJson()).toList(),
    'messages': messages.map((item) => item.toJson()).toList(),
    'conversationMemory': conversationMemory,
    'playMode': playMode.name,
    'choiceCount': choiceCount,
    'pendingChoices': pendingChoices,
    'memorySummary': memorySummary.toJson(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'lastPlayedAt': lastPlayedAt.toIso8601String(),
  };

  factory SaveSlot.fromJson(Map<String, Object?> json) => SaveSlot(
    id: json['id']! as String,
    name: json['name']! as String,
    sourceStoryCardId: json['sourceStoryCardId'] as String?,
    coverImage: json['coverImage'] as String?,
    playerName: json['playerName'] as String? ?? '',
    playerAvatar: json['playerAvatar'] as String?,
    playerDescription: json['playerDescription'] as String? ?? '',
    scenario: json['scenario'] as String? ?? '',
    worldSetting: json['worldSetting'] as String? ?? '',
    roleplayRules: json['roleplayRules'] as String? ?? defaultRoleplayRules,
    openingMessage: json['openingMessage'] as String? ?? '',
    characters: (json['characters'] as List<Object?>? ?? const [])
        .map(
          (item) => Character.fromJson((item! as Map).cast<String, Object?>()),
        )
        .toList(),
    lorebook: (json['lorebook'] as List<Object?>? ?? const [])
        .map(
          (item) => LoreEntry.fromJson((item! as Map).cast<String, Object?>()),
        )
        .toList(),
    messages: (json['messages'] as List<Object?>? ?? const [])
        .map(
          (item) =>
              ChatMessage.fromJson((item! as Map).cast<String, Object?>()),
        )
        .toList(),
    conversationMemory: json['conversationMemory'] as String? ?? '',
    playMode: PlayMode.fromJson(json['playMode']),
    choiceCount: (json['choiceCount'] as int? ?? 6).clamp(2, 10),
    pendingChoices: (json['pendingChoices'] as List<Object?>? ?? const [])
        .whereType<String>()
        .toList(),
    memorySummary: json['memorySummary'] == null
        ? MemorySummary(updatedAt: DateTime.now())
        : MemorySummary.fromJson(
            (json['memorySummary']! as Map).cast<String, Object?>(),
          ),
    createdAt: DateTime.parse(json['createdAt']! as String),
    updatedAt: DateTime.parse(json['updatedAt']! as String),
    lastPlayedAt: DateTime.parse(json['lastPlayedAt']! as String),
  );
}
