import '../models/app_settings.dart';
import '../models/vision_settings.dart';
import '../services/secure_storage_service.dart';
import 'settings_repository.dart';

class VisionSettingsRepository {
  VisionSettingsRepository(this._settings, this._secureStorage);

  final SettingsRepository _settings;
  final SecureStorageService _secureStorage;

  Future<VisionSettings> load() async {
    return (await _settings.load()).visionSettings;
  }

  Future<void> save(VisionSettings vision, {String? apiKey}) async {
    final current = await _settings.load();
    await _settings.save(current.copyWith(visionSettings: vision));
    if (apiKey != null) await _secureStorage.writeVisionApiKey(apiKey);
  }

  Future<String> readApiKey() => _secureStorage.readVisionApiKey();

  Future<AppSettings> loadAppSettings() => _settings.load();
}
