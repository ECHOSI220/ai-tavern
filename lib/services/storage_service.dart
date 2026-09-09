import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as mobile;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../utils/app_logger.dart';

class StorageService {
  Database? _database;

  Database get database {
    final value = _database;
    if (value == null) throw StateError('数据库尚未初始化');
    return value;
  }

  Future<void> initialize({String? databasePath}) async {
    final String path;
    if (databasePath == null) {
      final directory = await getApplicationSupportDirectory();
      path = '${directory.path}${Platform.pathSeparator}ai_tavern.db';
    } else {
      path = databasePath;
    }

    // Windows 使用 FFI，Android 使用 sqflite 原生实现；Repository 层无需感知平台差异。
    final DatabaseFactory factory;
    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      factory = databaseFactoryFfi;
    } else {
      factory = mobile.databaseFactory;
    }

    AppLogger.info('database.open.start', fields: {'version': 8});
    try {
      _database = await factory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 8,
          onConfigure: (db) async {
            await db.execute('PRAGMA foreign_keys = ON');
          },
          onCreate: (db, version) async {
            await db.execute('''
            CREATE TABLE save_slots (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              player_name TEXT NOT NULL,
              message_count INTEGER NOT NULL DEFAULT 0,
              updated_at INTEGER NOT NULL,
              last_played_at INTEGER NOT NULL,
              payload TEXT NOT NULL
            )
          ''');
            await db.execute(
              'CREATE INDEX idx_save_slots_last_played '
              'ON save_slots(last_played_at DESC)',
            );
            await _createVersion2Tables(db);
            await _createVersion3Tables(db);
            await _createVersion4Tables(db);
            await _createVersion5Tables(db);
            await _createVersion6Tables(db);
            await _createVersion7Tables(db);
            await _createVersion8Tables(db);
          },
          onUpgrade: (db, oldVersion, newVersion) async {
            if (oldVersion < 2) await _createVersion2Tables(db);
            if (oldVersion < 3) await _createVersion3Tables(db);
            if (oldVersion < 4) await _createVersion4Tables(db);
            if (oldVersion < 5) await _createVersion5Tables(db);
            if (oldVersion < 6) await _createVersion6Tables(db);
            if (oldVersion < 7) await _createVersion7Tables(db);
            if (oldVersion < 8) await _createVersion8Tables(db);
          },
        ),
      );
      AppLogger.info('database.open.complete', fields: {'version': 8});
    } catch (error, stackTrace) {
      AppLogger.error('database.open.failed', error, stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<void> _createVersion2Tables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS api_profiles (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        updated_at INTEGER NOT NULL,
        payload TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_settings (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        payload TEXT NOT NULL
      )
    ''');
  }

  Future<void> _createVersion3Tables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS messages (
        id TEXT PRIMARY KEY,
        save_id TEXT NOT NULL,
        role TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        payload TEXT NOT NULL,
        FOREIGN KEY(save_id) REFERENCES save_slots(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_messages_save_created '
      'ON messages(save_id, created_at)',
    );
  }

  Future<void> _createVersion4Tables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS story_cards (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        is_official INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL,
        payload TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_story_cards_official_updated '
      'ON story_cards(is_official DESC, updated_at DESC)',
    );
  }

  Future<void> _createVersion5Tables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS character_cards (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        updated_at INTEGER NOT NULL,
        payload TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_character_cards_updated '
      'ON character_cards(updated_at DESC)',
    );
  }

  Future<void> _createVersion6Tables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS trpg_sessions (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        mode TEXT NOT NULL,
        status TEXT NOT NULL,
        campaign_id TEXT NOT NULL,
        updated_at INTEGER NOT NULL,
        last_played_at INTEGER NOT NULL,
        schema_version INTEGER NOT NULL DEFAULT 1,
        payload TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_trpg_sessions_mode_played '
      'ON trpg_sessions(mode, last_played_at DESC)',
    );
  }

  Future<void> _createVersion7Tables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS campaigns (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        source TEXT NOT NULL,
        updated_at INTEGER NOT NULL,
        schema_version INTEGER NOT NULL DEFAULT 2,
        payload TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_campaigns_updated '
      'ON campaigns(updated_at DESC)',
    );
  }

  Future<void> _createVersion8Tables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS trpg_memories (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        type TEXT NOT NULL,
        importance INTEGER NOT NULL,
        visibility TEXT NOT NULL,
        owner_player_id TEXT,
        npc_id TEXT,
        location_id TEXT,
        quest_id TEXT,
        resolved INTEGER NOT NULL DEFAULT 0,
        pinned INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL,
        payload TEXT NOT NULL,
        FOREIGN KEY(session_id) REFERENCES trpg_sessions(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_trpg_memory_session_importance '
      'ON trpg_memories(session_id, pinned DESC, importance DESC, updated_at DESC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_trpg_memory_npc '
      'ON trpg_memories(session_id, npc_id, updated_at DESC)',
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS trpg_memory_entities (
        memory_id TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        PRIMARY KEY(memory_id, entity_id),
        FOREIGN KEY(memory_id) REFERENCES trpg_memories(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_trpg_memory_entity '
      'ON trpg_memory_entities(entity_id, memory_id)',
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS trpg_memory_tags (
        memory_id TEXT NOT NULL,
        tag TEXT NOT NULL,
        PRIMARY KEY(memory_id, tag),
        FOREIGN KEY(memory_id) REFERENCES trpg_memories(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_trpg_memory_tag '
      'ON trpg_memory_tags(tag, memory_id)',
    );
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}
