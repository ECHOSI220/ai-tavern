import 'dart:convert';

import '../models/trpg_models.dart';
import '../services/storage_service.dart';
import '../services/trpg_memory/trpg_long_term_memory_service.dart';
import '../utils/app_logger.dart';

class TRPGSessionRepository {
  TRPGSessionRepository(this._storage);

  final StorageService _storage;

  Future<List<TRPGSession>> getAll({TRPGMode? mode}) async {
    final rows = await _storage.database.query(
      'trpg_sessions',
      columns: ['payload'],
      where: mode == null ? null : 'mode = ?',
      whereArgs: mode == null ? null : [mode.name],
      orderBy: 'last_played_at DESC',
    );
    final sessions = <TRPGSession>[];
    for (final row in rows) {
      try {
        sessions.add(_decode(row['payload']! as String));
      } catch (error, stackTrace) {
        AppLogger.error('trpg.save.corrupted', error, stackTrace: stackTrace);
      }
    }
    return sessions;
  }

  Future<TRPGSession?> getById(String id) async {
    final rows = await _storage.database.query(
      'trpg_sessions',
      columns: ['payload'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    try {
      return _decode(rows.single['payload']! as String);
    } catch (error, stackTrace) {
      // Keep the damaged row for possible recovery. The UI treats null as an
      // unavailable save instead of crashing or overwriting the raw payload.
      AppLogger.error('trpg.save.corrupted', error, stackTrace: stackTrace);
      return null;
    }
  }

  Future<void> upsert(TRPGSession session, {bool onlyIfAbsent = false}) async {
    final payload = jsonEncode(
      TRPGSave(session: session, savedAt: DateTime.now()).toJson(),
    );
    final row = <String, Object?>{
      'id': session.id,
      'title': session.title,
      'mode': session.mode.name,
      'status': session.status.name,
      'campaign_id': session.campaignId,
      'updated_at': session.updatedAt.millisecondsSinceEpoch,
      'last_played_at': session.lastPlayedAt.millisecondsSinceEpoch,
      'schema_version': session.schemaVersion,
      'payload': payload,
    };
    await _storage.database.transaction((transaction) async {
      if (onlyIfAbsent) {
        final existing = await transaction.query(
          'trpg_sessions',
          columns: ['id'],
          where: 'id = ?',
          whereArgs: [session.id],
          limit: 1,
        );
        if (existing.isNotEmpty) throw StateError('本机已有这份存档，已停止恢复，未覆盖任何进度');
      }
      final updated = await transaction.update(
        'trpg_sessions',
        row,
        where: 'id = ?',
        whereArgs: [session.id],
      );
      if (updated == 0) await transaction.insert('trpg_sessions', row);
      await transaction.delete(
        'trpg_memories',
        where: 'session_id = ?',
        whereArgs: [session.id],
      );
      for (final entry in session.memoryState.entries) {
        await transaction.insert('trpg_memories', {
          'id': entry.id,
          'session_id': session.id,
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
        for (final entityId in entry.relatedEntityIds.toSet()) {
          await transaction.insert('trpg_memory_entities', {
            'memory_id': entry.id,
            'entity_id': entityId,
          });
        }
        for (final tag in entry.tags.toSet()) {
          await transaction.insert('trpg_memory_tags', {
            'memory_id': entry.id,
            'tag': tag.toLowerCase(),
          });
        }
      }
    });
    AppLogger.info('trpg.save.complete', fields: {'mode': session.mode.name});
  }

  Future<void> delete(String id) => _storage.database.delete(
    'trpg_sessions',
    where: 'id = ?',
    whereArgs: [id],
  );

  TRPGSession _decode(String payload) {
    final json = (jsonDecode(payload) as Map).cast<String, Object?>();
    final session = json['session'] is Map
        ? TRPGSave.fromJson(json).session
        : TRPGSession.fromJson(json);
    if (session.schemaVersion >= trpgSchemaVersion) return session;
    final migrated = TRPGSession.fromJson({
      ...session.toJson(),
      'schemaVersion': trpgSchemaVersion,
    });
    // Phase 1-5 saves had no memoryState. Seed only from authoritative
    // structured state and recorded events; never invent missing history.
    final memory = const TRPGLongTermMemoryService().seedFromStructuredState(
      migrated,
    );
    return migrated.copyWith(
      memoryState: memory,
      sessionSummary: memory.sessionSummary,
    );
  }
}
