import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart' show ConflictAlgorithm;

import '../models/app_settings.dart';
import '../app/skins/theme_manager.dart';
import '../app/skins/theme_preferences.dart';
import '../services/storage_service.dart';
import '../utils/app_logger.dart';

class SettingsRepository implements ThemePreferenceStore {
  SettingsRepository(this._storage);

  final StorageService _storage;

  // An isolated visual preference table avoids stale AppSettings overwriting
  // appearance preferences. No campaign, API or conversation data is touched.
  @override
  Future<ThemePreference> loadThemePreference() async {
    await _ensureThemeTable();
    final rows = await _storage.database.query(
      'skin_preferences',
      columns: ['payload'],
      where: 'id = 1',
      limit: 1,
    );
    if (rows.isEmpty) return const ThemePreference();
    return ThemePreference.fromJson(
      Map<String, Object?>.from(
        jsonDecode(rows.single['payload']! as String) as Map,
      ),
    );
  }

  @override
  Future<void> saveThemePreference(ThemePreference preference) async {
    await _ensureThemeTable();
    await _storage.database.insert('skin_preferences', {
      'id': 1,
      'payload': jsonEncode(preference.toJson()),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> _ensureThemeTable() => _storage.database.execute(
    'CREATE TABLE IF NOT EXISTS skin_preferences (id INTEGER PRIMARY KEY CHECK (id = 1), payload TEXT NOT NULL)',
  );

  Future<AppSettings> load() async {
    final rows = await _storage.database.query(
      'app_settings',
      columns: ['payload'],
      where: 'id = 1',
      limit: 1,
    );
    if (rows.isEmpty) return const AppSettings();
    return AppSettings.fromJson(
      (jsonDecode(rows.single['payload']! as String) as Map)
          .cast<String, Object?>(),
    );
  }

  Future<void> save(AppSettings settings) async {
    await _storage.database.insert('app_settings', {
      'id': 1,
      'payload': jsonEncode(settings.toJson()),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    AppLogger.configure(debugEnabled: settings.debugMode);
  }
}
