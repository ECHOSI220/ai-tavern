import 'dart:convert';

import '../models/trpg_memory_models.dart';
import '../services/storage_service.dart';

class TRPGMemoryRepository {
  TRPGMemoryRepository(this._storage);
  final StorageService _storage;

  Future<void> replaceSessionMemories(
    String sessionId,
    Iterable<MemoryEntry> entries,
  ) async {
    await _storage.database.transaction((transaction) async {
      await transaction.delete(
        'trpg_memories',
        where: 'session_id = ?',
        whereArgs: [sessionId],
      );
      for (final entry in entries) {
        await _insert(transaction, entry);
      }
    });
  }

  Future<void> upsert(MemoryEntry entry) async {
    await _storage.database.transaction((transaction) async {
      await transaction.delete(
        'trpg_memories',
        where: 'id = ?',
        whereArgs: [entry.id],
      );
      await _insert(transaction, entry);
    });
  }

  Future<void> _insert(dynamic db, MemoryEntry entry) async {
    await db.insert('trpg_memories', {
      'id': entry.id,
      'session_id': entry.sessionId,
      'type': entry.type.name,
      'importance': entry.importance,
      'visibility': entry.visibility.name,
      'owner_player_id': entry.ownerPlayerId,
      'npc_id': entry.npcId,
      'location_id': entry.locationId,
      'quest_id': entry.questId,
      'resolved': entry.resolved ? 1 : 0,
      'pinned': entry.pinned ? 1 : 0,
      'updated_at': entry.updatedAt.millisecondsSinceEpoch,
      'payload': jsonEncode(entry.toJson()),
    });
    for (final entity in entry.relatedEntityIds.toSet()) {
      await db.insert('trpg_memory_entities', {
        'memory_id': entry.id,
        'entity_id': entity,
      });
    }
    for (final tag in entry.tags.toSet()) {
      await db.insert('trpg_memory_tags', {
        'memory_id': entry.id,
        'tag': tag.toLowerCase(),
      });
    }
  }

  Future<List<MemoryEntry>> getForSession(String sessionId) async {
    final rows = await _storage.database.query(
      'trpg_memories',
      columns: ['payload'],
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'pinned DESC, importance DESC, updated_at DESC',
    );
    return rows
        .map(
          (row) => MemoryEntry.fromJson(
            (jsonDecode(row['payload']! as String) as Map)
                .cast<String, Object?>(),
          ),
        )
        .toList();
  }

  Future<List<MemoryEntry>> search(
    String sessionId,
    String query, {
    int limit = 50,
  }) async {
    final normalized = query.trim().toLowerCase();
    final all = await getForSession(sessionId);
    if (normalized.isEmpty) return all.take(limit).toList();
    return all
        .where((entry) {
          final text = [
            entry.title,
            entry.content,
            entry.summary,
            ...entry.tags,
            ...entry.relatedEntityIds,
          ].join(' ').toLowerCase();
          return text.contains(normalized);
        })
        .take(limit)
        .toList();
  }

  Future<void> delete(String id) => _storage.database.delete(
    'trpg_memories',
    where: 'id = ?',
    whereArgs: [id],
  );
}
