import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart' show ConflictAlgorithm;

import '../models/story_card.dart';
import '../services/storage_service.dart';

class StoryCardRepository {
  const StoryCardRepository(this._storage);

  final StorageService _storage;

  Future<List<StoryCard>> getAll() async {
    final rows = await _storage.database.query(
      'story_cards',
      columns: ['payload'],
      orderBy: 'is_official DESC, updated_at DESC',
    );
    return rows
        .map(
          (row) => StoryCard.fromJson(
            (jsonDecode(row['payload']! as String) as Map)
                .cast<String, Object?>(),
          ),
        )
        .toList();
  }

  Future<StoryCard?> getById(String id) async {
    final rows = await _storage.database.query(
      'story_cards',
      columns: ['payload'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return StoryCard.fromJson(
      (jsonDecode(rows.single['payload']! as String) as Map)
          .cast<String, Object?>(),
    );
  }

  Future<void> upsert(StoryCard card) async {
    await _storage.database.insert('story_cards', {
      'id': card.id,
      'name': card.name,
      'is_official': card.isOfficial ? 1 : 0,
      'updated_at': card.updatedAt.millisecondsSinceEpoch,
      'payload': jsonEncode(card.toJson()),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> ensureOfficial(StoryCard card) async {
    if (!card.isOfficial) {
      throw ArgumentError('默认卡片必须标记为官方卡片');
    }
    await upsert(card);
  }

  Future<void> delete(String id) async {
    final card = await getById(id);
    if (card?.isOfficial == true) {
      throw StateError('官方剧情卡片不能删除');
    }
    await _storage.database.delete(
      'story_cards',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
