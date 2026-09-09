import 'package:flutter/material.dart';

import '../repositories/api_repository.dart';
import '../repositories/character_card_repository.dart';
import '../repositories/campaign_repository.dart';
import '../repositories/save_repository.dart';
import '../repositories/settings_repository.dart';
import '../repositories/story_card_repository.dart';
import '../repositories/trpg_session_repository.dart';
import '../screens/platform_home/platform_home_screen.dart';
import '../services/ai_service.dart';
import 'skins/theme_background.dart';
import 'skins/theme_builder.dart';
import 'skins/theme_manager.dart';

class AiTavernApp extends StatefulWidget {
  const AiTavernApp({
    required this.saveRepository,
    required this.storyCardRepository,
    required this.characterCardRepository,
    required this.campaignRepository,
    required this.apiRepository,
    required this.settingsRepository,
    required this.aiService,
    required this.trpgSessionRepository,
    super.key,
  });

  final SaveRepository saveRepository;
  final StoryCardRepository storyCardRepository;
  final CharacterCardRepository characterCardRepository;
  final CampaignRepository campaignRepository;
  final ApiRepository apiRepository;
  final SettingsRepository settingsRepository;
  final AiService aiService;
  final TRPGSessionRepository trpgSessionRepository;

  @override
  State<AiTavernApp> createState() => _AiTavernAppState();
}

class _AiTavernAppState extends State<AiTavernApp> {
  late final ThemeManager _themeManager;
  late final Widget _home;
  @override
  void initState() {
    super.initState();
    _themeManager = ThemeManager(widget.settingsRepository)
      ..loadThemePreference();
    _home = PlatformHomeScreen(
      saveRepository: widget.saveRepository,
      storyCardRepository: widget.storyCardRepository,
      characterCardRepository: widget.characterCardRepository,
      campaignRepository: widget.campaignRepository,
      apiRepository: widget.apiRepository,
      settingsRepository: widget.settingsRepository,
      aiService: widget.aiService,
      trpgSessionRepository: widget.trpgSessionRepository,
    );
  }

  @override
  void dispose() {
    _themeManager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ThemeScope(
      manager: _themeManager,
      child: ListenableBuilder(
        listenable: _themeManager,
        builder: (context, _) => MaterialApp(
          title: '幻境酒馆',
          debugShowCheckedModeBanner: false,
          theme: SkinThemeBuilder.build(
            _themeManager.getCurrentTheme(),
            Brightness.light,
            settings: _themeManager.settings,
            transparentScaffold: true,
          ),
          darkTheme: SkinThemeBuilder.build(
            _themeManager.getCurrentTheme(),
            Brightness.dark,
            settings: _themeManager.settings,
            transparentScaffold: true,
          ),
          themeMode: ThemeMode.system,
          themeAnimationDuration: Duration.zero,
          builder: (context, child) {
            final page = child ?? const SizedBox.shrink();
            final definition = _themeManager.getCurrentTheme();
            if (definition.category == 'character_theme') {
              // Character routes paint their own wallpaper in the transition
              // builder. Keep only an opaque fallback here so two animated
              // full-screen backgrounds are never running at once.
              return ColoredBox(
                color: definition
                    .tokens(MediaQuery.platformBrightnessOf(context))
                    .backgroundPrimary,
                child: page,
              );
            }
            return ThemeBackground(child: page);
          },
          home: _home,
        ),
      ),
    );
  }
}
