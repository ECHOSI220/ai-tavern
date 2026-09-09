import 'package:flutter/material.dart';

import 'app/app.dart';
import 'repositories/api_repository.dart';
import 'repositories/character_card_repository.dart';
import 'repositories/campaign_repository.dart';
import 'repositories/save_repository.dart';
import 'repositories/settings_repository.dart';
import 'repositories/story_card_repository.dart';
import 'repositories/trpg_session_repository.dart';
import 'services/ai_service.dart';
import 'services/secure_storage_service.dart';
import 'services/official_story_card_service.dart';
import 'services/storage_service.dart';
import 'utils/app_logger.dart';

Future<void> _ensureOfficialStoryCard(
  Future<void> Function() operation,
  String cardName,
) async {
  try {
    await operation();
  } catch (error, stackTrace) {
    // Official cards are bundled conveniences, not a prerequisite for opening
    // the app. A damaged/incomplete installation must still reach the UI so the
    // user can repair or reinstall it instead of seeing a white-screen crash.
    debugPrint('Unable to load official story card "$cardName": $error');
    debugPrintStack(stackTrace: stackTrace);
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final storage = StorageService();
  await storage.initialize();
  final secureStorage = SecureStorageService();
  final settingsRepository = SettingsRepository(storage);
  final storyCardRepository = StoryCardRepository(storage);
  final characterCardRepository = CharacterCardRepository(storage);
  const officialStoryCardService = OfficialStoryCardService();
  await _ensureOfficialStoryCard(
    () async => storyCardRepository.ensureOfficial(
      await officialStoryCardService.loadWhiteEcho(),
    ),
    'White Echo',
  );
  await _ensureOfficialStoryCard(
    () async => storyCardRepository.ensureOfficial(
      await officialStoryCardService.loadSaintReincarnation(),
    ),
    'Saint Reincarnation',
  );
  await _ensureOfficialStoryCard(
    () async => storyCardRepository.ensureOfficial(
      await officialStoryCardService.loadRetiredHeroEarlyEight(),
    ),
    'Retired Hero Early Eight',
  );
  final settings = await settingsRepository.load();
  AppLogger.configure(debugEnabled: settings.debugMode);
  runApp(
    AiTavernApp(
      saveRepository: SaveRepository(storage),
      storyCardRepository: storyCardRepository,
      characterCardRepository: characterCardRepository,
      campaignRepository: CampaignRepository(storage),
      apiRepository: ApiRepository(storage, secureStorage),
      settingsRepository: settingsRepository,
      aiService: AiService(),
      trpgSessionRepository: TRPGSessionRepository(storage),
    ),
  );
}
