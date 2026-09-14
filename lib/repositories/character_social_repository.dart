import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/character_social.dart';
import '../services/storage_service.dart';

/// Account-bound local replica. Guest data never silently moves to an account.
class CharacterSocialRepository {
  CharacterSocialRepository(this.storage, {this.owner = 'local'});
  final StorageService storage;
  final String owner;
  Future<void>? _ready;
  Future<void> initialize() => _ready ??= _initialize();
  Future<void> _initialize() async {
    final db = storage.database;
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS character_social_records (
      owner_id TEXT NOT NULL, id TEXT NOT NULL, kind TEXT NOT NULL,
      world_id TEXT NOT NULL, character_id TEXT NOT NULL, parent_id TEXT NOT NULL,
      payload TEXT NOT NULL, created_at_ms INTEGER NOT NULL,
      revision INTEGER NOT NULL, base_version INTEGER NOT NULL DEFAULT 0,
      deleted INTEGER NOT NULL DEFAULT 0, dirty INTEGER NOT NULL DEFAULT 1,
      conflict TEXT, batch_id TEXT NOT NULL DEFAULT '', PRIMARY KEY(owner_id,id))''',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS social_kind_time ON character_social_records(owner_id,kind,created_at_ms DESC,id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS social_parent_time ON character_social_records(owner_id,parent_id,kind,created_at_ms DESC,id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS social_character ON character_social_records(owner_id,character_id,kind)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS social_world ON character_social_records(owner_id,world_id,kind)',
    );
  }

  Future<SocialRecord?> get(String id) async {
    await initialize();
    final rows = await storage.database.query(
      'character_social_records',
      where: 'owner_id = ? AND id = ?',
      whereArgs: [owner, id],
      limit: 1,
    );
    return rows.isEmpty ? null : SocialRecord.fromLocal(rows.single);
  }

  Future<List<SocialRecord>> list(
    String kind, {
    String? parentId,
    String? characterId,
    String? worldId,
    int limit = 50,
    int offset = 0,
    bool includeDeleted = false,
  }) async {
    await initialize();
    final where = [
      'owner_id = ?',
      'kind = ?',
      if (!includeDeleted) 'deleted = 0',
    ];
    final args = <Object?>[owner, kind];
    for (final pair in [
      ('parent_id', parentId),
      ('character_id', characterId),
      ('world_id', worldId),
    ]) {
      if (pair.$2 != null) {
        where.add('${pair.$1} = ?');
        args.add(pair.$2);
      }
    }
    return (await storage.database.query(
      'character_social_records',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'created_at_ms DESC,id DESC',
      limit: limit.clamp(1, 500),
      offset: offset,
    )).map(SocialRecord.fromLocal).toList();
  }

  Future<void> save(SocialRecord record) => saveAll([record]);

  Future<int> unreadCount(String conversationId) async {
    final read = await get('read:$conversationId');
    final rows = await storage.database.rawQuery(
      '''SELECT count(*) AS n FROM character_social_records
      WHERE owner_id=? AND kind='message' AND parent_id=? AND character_id<>'user'
      AND deleted=0 AND created_at_ms>?''',
      [owner, conversationId, read?.number('readAt') ?? 0],
    );
    return (rows.single['n'] as num).toInt();
  }

  Future<int> likesFor(String characterId) async {
    await initialize();
    final rows = await storage.database.rawQuery(
      '''SELECT count(*) AS n FROM character_social_records l
      JOIN character_social_records p ON p.owner_id=l.owner_id AND p.id=l.parent_id
      WHERE l.owner_id=? AND l.kind='like' AND l.character_id='user' AND l.deleted=0
      AND p.kind='post' AND p.character_id=? AND p.deleted=0''',
      [owner, characterId],
    );
    return (rows.single['n'] as num).toInt();
  }

  /// Atomic life event / post / relation / cursor commit; stale edits fail.
  Future<void> saveAll(List<SocialRecord> records) async {
    await initialize();
    await storage.database.transaction((tx) async {
      final batchId = const Uuid().v4();
      for (final record in records) {
        final old = await tx.query(
          'character_social_records',
          columns: ['revision'],
          where: 'owner_id = ? AND id = ?',
          whereArgs: [owner, record.id],
        );
        if (old.isNotEmpty && old.single['revision'] != record.revision - 1) {
          throw StateError('数据已更新，请刷新后重试');
        }
        await tx.insert('character_social_records', {
          ...record.toLocal(owner),
          'batch_id': batchId,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<List<SocialRecord>> pending() async {
    await initialize();
    final batches = await storage.database.rawQuery(
      '''SELECT batch_id FROM character_social_records
      WHERE owner_id = ? AND dirty = 1 AND conflict IS NULL
      AND batch_id NOT IN (SELECT batch_id FROM character_social_records WHERE owner_id = ? AND conflict IS NOT NULL)
      ORDER BY created_at_ms LIMIT 1''',
      [owner, owner],
    );
    if (batches.isEmpty) return [];
    return (await storage.database.query(
      'character_social_records',
      where: 'owner_id = ? AND dirty = 1 AND conflict IS NULL AND batch_id = ?',
      whereArgs: [owner, batches.single['batch_id']],
      limit: 100,
    )).map(SocialRecord.fromLocal).toList();
  }

  Future<List<SocialRecord>> conflicts() async {
    await initialize();
    return (await storage.database.query(
      'character_social_records',
      where: 'owner_id = ? AND conflict IS NOT NULL',
      whereArgs: [owner],
      limit: 100,
    )).map(SocialRecord.fromLocal).toList();
  }

  Future<void> acceptRemote(SocialData remote, {SocialRecord? sent}) async {
    await initialize();
    await storage.database.transaction((tx) async {
      final id = remote['id']! as String;
      final rows = await tx.query(
        'character_social_records',
        where: 'owner_id = ? AND id = ?',
        whereArgs: [owner, id],
      );
      final local = rows.isEmpty ? null : SocialRecord.fromLocal(rows.single);
      final version = remote['version']! as int;
      if (local != null && version <= local.baseVersion) return;
      if (sent != null && local != null) {
        await tx.update(
          'character_social_records',
          {
            'base_version': version,
            'dirty': local.revision == sent.revision ? 0 : 1,
          },
          where: 'owner_id = ? AND id = ?',
          whereArgs: [owner, id],
        );
        return;
      }
      if (local != null && local.dirty) {
        await tx.update(
          'character_social_records',
          {'conflict': jsonEncode(remote)},
          where: 'owner_id = ? AND id = ?',
          whereArgs: [owner, id],
        );
        return;
      }
      final value = SocialRecord(
        id: id,
        kind: remote['kind']! as String,
        data: (remote['payload']! as Map).cast<String, Object?>(),
        worldId: remote['world_id']! as String,
        characterId: remote['character_id']! as String,
        parentId: remote['parent_id']! as String,
        createdAt: remote['created_at_ms']! as int,
        revision: (local?.revision ?? 0) + 1,
        baseVersion: version,
        dirty: false,
        deleted: remote['deleted'] == true,
      );
      await tx.insert(
        'character_social_records',
        value.toLocal(owner),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  Future<void> resolveConflict(
    SocialRecord record, {
    required bool keepLocal,
  }) async {
    final remote = record.conflict;
    if (remote == null) return;
    await storage.database.update(
      'character_social_records',
      {
        'base_version': keepLocal ? remote['version'] : 0,
        'dirty': keepLocal ? 1 : 0,
        'conflict': null,
      },
      where: 'owner_id = ? AND id = ? AND revision = ?',
      whereArgs: [owner, record.id, record.revision],
    );
    if (!keepLocal) await acceptRemote(remote);
  }
}
