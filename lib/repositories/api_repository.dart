import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart' show ConflictAlgorithm;

import '../models/api_profile.dart';
import '../services/secure_storage_service.dart';
import '../services/storage_service.dart';

class ApiRepository {
  ApiRepository(this._storage, this._secureStorage);

  final StorageService _storage;
  final SecureStorageService _secureStorage;

  Future<List<ApiProfile>> getAll() async {
    final rows = await _storage.database.query(
      'api_profiles',
      columns: ['payload'],
      orderBy: 'name COLLATE NOCASE',
    );
    return rows
        .map(
          (row) => ApiProfile.fromJson(
            (jsonDecode(row['payload']! as String) as Map)
                .cast<String, Object?>(),
          ),
        )
        .toList();
  }

  Future<ApiProfile?> getById(String id) async {
    final rows = await _storage.database.query(
      'api_profiles',
      columns: ['payload'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return ApiProfile.fromJson(
      (jsonDecode(rows.single['payload']! as String) as Map)
          .cast<String, Object?>(),
    );
  }

  Future<void> upsert(ApiProfile profile, {String? apiKey}) async {
    await _storage.database.insert('api_profiles', {
      'id': profile.id,
      'name': profile.name,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
      'payload': jsonEncode(profile.toJson()),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    if (apiKey != null) {
      await _secureStorage.writeApiKey(profile.id, apiKey);
    }
  }

  Future<String> readApiKey(String profileId) {
    return _secureStorage.readApiKey(profileId);
  }

  Future<String> readVisionApiKey() => _secureStorage.readVisionApiKey();

  Future<void> writeVisionApiKey(String apiKey) =>
      _secureStorage.writeVisionApiKey(apiKey);

  Future<String> readMultiplayerCredentials() =>
      _secureStorage.readMultiplayerCredentials();

  Future<void> writeMultiplayerCredentials(String value) =>
      _secureStorage.writeMultiplayerCredentials(value);

  Future<String> readAccountTokens() => _secureStorage.readAccountTokens();

  Future<void> writeAccountTokens(String value) =>
      _secureStorage.writeAccountTokens(value);

  Future<String> readMultiplayerTurnDraft(String roomId, String playerId) =>
      _secureStorage.readTurnDraft(roomId, playerId);

  Future<void> writeMultiplayerTurnDraft(
    String roomId,
    String playerId,
    String value,
  ) => _secureStorage.writeTurnDraft(roomId, playerId, value);

  Future<void> delete(String id) async {
    await _storage.database.delete(
      'api_profiles',
      where: 'id = ?',
      whereArgs: [id],
    );
    await _secureStorage.deleteApiKey(id);
  }
}
