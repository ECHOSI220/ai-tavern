import 'package:uuid/uuid.dart';

import 'memory_summary.dart';
import 'save_slot.dart';

const officialWhiteEchoCardId = 'official-white-echo-v1';
const officialSaintReincarnationCardId =
    'official-saint-reincarnation-accident-v1';
const officialRetiredHeroEarlyEightCardId =
    'official-retired-hero-early-eight-v1';

class StoryCard {
  const StoryCard({
    required this.id,
    required this.name,
    this.description = '',
    this.author = '',
    this.isOfficial = false,
    required this.template,
    required this.createdAt,
    required this.updatedAt,
  });

  factory StoryCard.fromSave(
    SaveSlot save, {
    String? name,
    String description = '',
    String author = '',
  }) {
    final now = DateTime.now();
    return StoryCard(
      id: const Uuid().v4(),
      name: name?.trim().isNotEmpty == true ? name!.trim() : save.name,
      description: description,
      author: author,
      template: save.copyWith(
        clearSourceStoryCardId: true,
        messages: const [],
        conversationMemory: '',
        pendingChoices: const [],
        memorySummary: MemorySummary(updatedAt: now),
        createdAt: now,
        updatedAt: now,
        lastPlayedAt: now,
      ),
      createdAt: now,
      updatedAt: now,
    );
  }

  final String id;
  final String name;
  final String description;
  final String author;
  final bool isOfficial;
  final SaveSlot template;
  final DateTime createdAt;
  final DateTime updatedAt;

  StoryCard copyWith({
    String? id,
    String? name,
    String? description,
    String? author,
    bool? isOfficial,
    SaveSlot? template,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => StoryCard(
    id: id ?? this.id,
    name: name ?? this.name,
    description: description ?? this.description,
    author: author ?? this.author,
    isOfficial: isOfficial ?? this.isOfficial,
    template: template ?? this.template,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  SaveSlot createSave() {
    const uuid = Uuid();
    final now = DateTime.now();
    final saveId = uuid.v4();
    return template.copyWith(
      id: saveId,
      name: name,
      sourceStoryCardId: id,
      characters: template.characters
          .map((character) => character.copyWith(id: uuid.v4()))
          .toList(),
      lorebook: template.lorebook
          .map((entry) => entry.copyWith(id: uuid.v4()))
          .toList(),
      messages: const [],
      conversationMemory: '',
      pendingChoices: template.pendingChoices,
      memorySummary: template.memorySummary.copyWith(
        updatedAt: now,
        clearCoveredMessageId: true,
      ),
      createdAt: now,
      updatedAt: now,
      lastPlayedAt: now,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'author': author,
    'isOfficial': isOfficial,
    'template': template.toJson(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory StoryCard.fromJson(Map<String, Object?> json) => StoryCard(
    id: json['id']! as String,
    name: json['name']! as String,
    description: json['description'] as String? ?? '',
    author: json['author'] as String? ?? '',
    isOfficial: json['isOfficial'] as bool? ?? false,
    template: SaveSlot.fromJson(
      (json['template']! as Map).cast<String, Object?>(),
    ),
    createdAt: DateTime.parse(json['createdAt']! as String),
    updatedAt: DateTime.parse(json['updatedAt']! as String),
  );
}
