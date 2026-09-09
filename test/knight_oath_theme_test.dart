import 'dart:convert';
import 'dart:io';
import 'package:ai_tavern/app/skins/character_theme.dart';
import 'package:ai_tavern/app/skins/theme_asset_pipeline.dart';
import 'package:ai_tavern/app/skins/theme_background.dart';
import 'package:ai_tavern/app/skins/theme_builder.dart';
import 'package:ai_tavern/app/skins/theme_catalog.dart';
import 'package:ai_tavern/app/skins/theme_definition.dart';
import 'package:ai_tavern/app/skins/theme_manager.dart';
import 'package:ai_tavern/app/skins/theme_preferences.dart';
import 'package:ai_tavern/app/skins/theme_tokens.dart';
import 'package:ai_tavern/app/skins/theme_validator.dart';
import 'package:ai_tavern/models/chat_message.dart';
import 'package:ai_tavern/models/trpg_dice_models.dart';
import 'package:ai_tavern/screens/trpg_shared/dice_panel.dart';
import 'package:ai_tavern/widgets/message_bubble.dart';
import 'package:ai_tavern/screens/trpg_shared/trpg_play_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'theme_skin_system_test.dart' show MemoryThemeStore, harness;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final knight = ThemeCatalog.byId('knight_oath_mooncourt');
  test('complete bundled manifest and runtime art', () async {
    final json =
        jsonDecode(await rootBundle.loadString(knight.assetManifest!))
            as Map<String, dynamic>;
    expect(ThemeAssetValidator.validate(json), isEmpty);
    final manifest = await ThemeAssetPipeline.load(knight.assetManifest!);
    expect(manifest, isNotNull);
    expect(manifest!.assets.length, 17);
    expect(await ThemeAssetPipeline.missingAssets(manifest), isEmpty);
    expect(manifest.image('bg_main'), knight.backgroundImage);
    expect(manifest.image('bg_chat'), knight.chatBackgroundImage);
    expect(knight.immersiveArtwork, isTrue);
    expect(knight.portraitBackgroundImage, isNot(knight.backgroundImage));
    expect(manifest.image('bg_portrait'), knight.portraitBackgroundImage);
    json['assets']['bg_main']['path'] = '../not-local.png';
    expect(ThemeAssetValidator.validate(json), isNotEmpty);
    expect(
      await ThemeAssetPipeline.load('assets/missing-manifest.json'),
      isNull,
    );
  });

  test('parchment text stays legible at minimum and full opacity', () {
    expect(ThemeValidator.validate(knight), isEmpty);
    for (final opacity in [.35, .7, 1.0]) {
      final theme = SkinThemeBuilder.build(
        knight,
        Brightness.dark,
        settings: ThemeSettings(uiOpacity: opacity),
      );
      final tokens = theme.extension<ThemeTokens>()!;
      final composited = Color.alphaBlend(
        tokens.aiBubble,
        tokens.backgroundPrimary,
      );
      expect(
        ThemeValidator.contrast(tokens.aiForeground, composited),
        greaterThan(7),
      );
      expect(tokens.privateBubble, isNot(tokens.gmBubble));
      expect(tokens.backgroundPrimary.a, 1);
      expect(theme.extension<CharacterThemeExtension>(), isNotNull);
    }
  });

  test('knight preferences persist independently of other themes', () async {
    final store = MemoryThemeStore(),
        manager = ThemeManager(MemoryThemeStore());
    final saved = ThemeManager(store);
    addTearDown(manager.dispose);
    addTearDown(saved.dispose);
    await saved.applyTheme(knight.id);
    await saved.updateSettings(
      const ThemeSettings(uiOpacity: .8, reduceMotion: true),
    );
    final restarted = ThemeManager(store);
    addTearDown(restarted.dispose);
    await restarted.loadThemePreference();
    expect(restarted.getCurrentTheme().id, knight.id);
    expect(restarted.settings.uiOpacity, .8);
    expect(restarted.settings.reduceMotion, isTrue);
    await saved.applyTheme('default_clean');
    expect(saved.settings.uiOpacity, 1);
    await saved.applyTheme(knight.id);
    expect(saved.settings.uiOpacity, .8);
  });

  testWidgets(
    'actual tavern and TRPG text unchanged, parchment has dark text',
    (tester) async {
      final manager = ThemeManager(MemoryThemeStore());
      addTearDown(manager.dispose);
      final message = ChatMessage(
        id: 'm1',
        saveId: 's1',
        role: ChatRole.assistant,
        content: '回廊里传来脚步声。\n\n**我会履行誓约。**',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      final before = message.toJson();
      await manager.applyTheme(knight.id);
      await tester.pumpWidget(
        harness(
          manager,
          Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  MessageBubble(
                    message: message,
                    isStreaming: true,
                    onAction: (_) {},
                    onRetry: () {},
                  ),
                  const TrpgMessageBubble(
                    label: '同伴',
                    content: '内容没有变',
                    tone: TrpgMessageTone.npc,
                  ),
                  const TrpgMessageBubble(
                    label: '私密 · 仅你可见',
                    content: '秘密仍然保密',
                    tone: TrpgMessageTone.private,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(message.toJson(), before);
      expect(
        tester.widget<Text>(find.text('内容没有变')).style!.color,
        knight.tokens(Brightness.dark).aiForeground,
      );
      expect(find.text('秘密仍然保密'), findsOneWidget);
      final aiHeader = tester.element(find.text('AI 剧情'));
      expect(Theme.of(aiHeader).colorScheme.brightness, Brightness.light);
    },
  );

  testWidgets(
    'portrait/landscape keys differ and failed image keeps full opaque viewport',
    (tester) async {
      final manager = ThemeManager(MemoryThemeStore());
      addTearDown(manager.dispose);
      await manager.applyTheme(knight.id);
      await manager.updateSettings(
        const ThemeSettings(chatBackground: 'Z:/missing/background.png'),
      );
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        harness(
          manager,
          const Scaffold(
            body: TrpgTimelineViewport(
              children: [
                TrpgMessageBubble(
                  label: 'GM',
                  content: '背景缺失仍能阅读',
                  tone: TrpgMessageTone.gm,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.runAsync(() => File('Z:/missing/background.png').exists());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('背景缺失仍能阅读'), findsOneWidget);
      final context = tester.element(find.text('背景缺失仍能阅读'));
      expect(
        skinBackgroundImage(context, knight, const ThemeSettings()),
        isNot(
          skinBackgroundImage(
            context,
            knight,
            const ThemeSettings(),
            chat: true,
            viewport: const Size(1200, 700),
          ),
        ),
      );
      expect(find.byType(ErrorWidget), findsNothing);
    },
  );

  testWidgets('loading motion stops for off low reduceMotion and OS settings', (
    tester,
  ) async {
    final manager = ThemeManager(MemoryThemeStore());
    addTearDown(manager.dispose);
    await manager.applyTheme(knight.id);
    Widget page() => harness(
      manager,
      const Scaffold(body: Center(child: ThemedLoadingIndicator())),
    );
    double phase() => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((w) => w.painter)
        .whereType<OathCirclePainter>()
        .single
        .phase;
    for (final setting in [
      const ThemeSettings(effectsLevel: ThemeEffectsLevel.off),
      const ThemeSettings(effectsLevel: ThemeEffectsLevel.low),
      const ThemeSettings(
        effectsLevel: ThemeEffectsLevel.high,
        reduceMotion: true,
      ),
    ]) {
      await manager.updateSettings(setting);
      await tester.pumpWidget(page());
      await tester.pump(const Duration(seconds: 1));
      final first = phase();
      await tester.pump(const Duration(seconds: 2));
      expect(phase(), first);
      expect(tester.binding.transientCallbackCount, 0);
    }
    await manager.updateSettings(
      const ThemeSettings(effectsLevel: ThemeEffectsLevel.high),
    );
    await tester.pumpWidget(page());
    await tester.pump(const Duration(seconds: 1));
    final first = phase();
    await tester.pump(const Duration(seconds: 2));
    expect(phase(), isNot(first));
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(phase(), 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'dice decoration preserves supplied number in success and failure states',
    (tester) async {
      for (final failure in [false, true]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: SkinThemeBuilder.build(knight, Brightness.dark),
            home: Scaffold(
              body: Center(
                child: ThemedDiceCard(
                  failure: failure,
                  critical: !failure,
                  child: const Text('18'),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(find.text('18'), findsOneWidget);
        expect(find.byType(ErrorWidget), findsNothing);
      }
    },
  );
  testWidgets(
    'real dice dialog fits narrow large text and uses the original result',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final result = DiceRollResult(
        rollId: 'fixed',
        playerId: 'player',
        diceFormula: '1D20+2',
        diceType: 'D20',
        individualResults: const [20],
        baseResult: 20,
        modifier: 2,
        finalResult: 22,
        successLevel: DiceSuccessLevel.criticalSuccess,
        explanation: '你在月光下辨认出了纹章。基础结果20，加值2，最终22。原有结果不能被主题改变。',
        timestamp: DateTime(2026),
      );
      final before = result.toJson();
      final manager = ThemeManager(MemoryThemeStore());
      addTearDown(manager.dispose);
      await manager.applyTheme(knight.id);
      await tester.pumpWidget(
        harness(
          manager,
          Scaffold(
            body: DiceResultDialog(
              result: result,
              settings: const DiceSettings(
                soundEnabled: false,
                hapticsEnabled: false,
              ),
            ),
          ),
          textScale: 1.5,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('22'), findsOneWidget);
      expect(find.text('完成'), findsOneWidget);
      expect(result.toJson(), before);
      final close = tester.widget<TextButton>(
        find.ancestor(of: find.text('完成'), matching: find.byType(TextButton)),
      );
      expect(close.onPressed, isNotNull);
      expect(tester.binding.transientCallbackCount, 0);
    },
  );
}
