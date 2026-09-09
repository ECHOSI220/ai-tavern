import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  SecureStorageService({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  String _apiKeyName(String profileId) => 'api_profile_key_$profileId';
  static const _visionApiKeyName = 'vision_provider_api_key';
  static const _multiplayerCredentialsName = 'trpg_multiplayer_credentials';
  static const _accountTokensName = 'trpg_account_tokens';
  String _turnDraftName(String roomId, String playerId) =>
      'trpg_turn_draft_${roomId}_$playerId';

  Future<String> readApiKey(String profileId) async {
    return await _storage.read(key: _apiKeyName(profileId)) ?? '';
  }

  Future<void> writeApiKey(String profileId, String apiKey) async {
    final key = _apiKeyName(profileId);
    if (apiKey.trim().isEmpty) {
      await _storage.delete(key: key);
    } else {
      await _storage.write(key: key, value: apiKey.trim());
    }
  }

  Future<void> deleteApiKey(String profileId) {
    return _storage.delete(key: _apiKeyName(profileId));
  }

  Future<String> readVisionApiKey() async {
    return await _storage.read(key: _visionApiKeyName) ?? '';
  }

  Future<void> writeVisionApiKey(String apiKey) async {
    if (apiKey.trim().isEmpty) {
      await _storage.delete(key: _visionApiKeyName);
    } else {
      await _storage.write(key: _visionApiKeyName, value: apiKey.trim());
    }
  }

  Future<String> readMultiplayerCredentials() async {
    return await _storage.read(key: _multiplayerCredentialsName) ?? '';
  }

  Future<void> writeMultiplayerCredentials(String value) async {
    if (value.trim().isEmpty) {
      await _storage.delete(key: _multiplayerCredentialsName);
    } else {
      await _storage.write(
        key: _multiplayerCredentialsName,
        value: value.trim(),
      );
    }
  }

  Future<String> readAccountTokens() async =>
      await _storage.read(key: _accountTokensName) ?? '';

  Future<void> writeAccountTokens(String value) async {
    if (value.trim().isEmpty) {
      await _storage.delete(key: _accountTokensName);
    } else {
      await _storage.write(key: _accountTokensName, value: value.trim());
    }
  }

  Future<String> readTurnDraft(String roomId, String playerId) async =>
      await _storage.read(key: _turnDraftName(roomId, playerId)) ?? '';

  Future<void> writeTurnDraft(
    String roomId,
    String playerId,
    String value,
  ) async {
    final key = _turnDraftName(roomId, playerId);
    if (value.isEmpty) {
      await _storage.delete(key: key);
    } else {
      await _storage.write(key: key, value: value);
    }
  }
}
