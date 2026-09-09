import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:ai_tavern/app/skins/character_theme.dart';
import 'package:ai_tavern/app/skins/skin_icon.dart';
import 'package:ai_tavern/app/skins/theme_asset_pipeline.dart';
import 'package:ai_tavern/app/skins/theme_background.dart';
import 'package:ai_tavern/app/skins/theme_builder.dart';
import 'package:ai_tavern/app/skins/theme_catalog.dart';
import 'package:ai_tavern/app/skins/theme_craft.dart';
import 'package:ai_tavern/app/skins/theme_manager.dart';
import 'package:ai_tavern/app/skins/theme_validator.dart';
import 'package:ai_tavern/models/app_mode.dart';
import 'package:ai_tavern/screens/app_settings/skin_gallery_page.dart';
import 'package:ai_tavern/screens/platform_home/platform_home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'theme_skin_system_test.dart' show MemoryThemeStore, harness;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final skins = {
    'miku_digital_stage': (
      material: SkinMaterial.digitalStage,
      wide: const Size(1672, 941),
      portrait: const Size(941, 1672),
      accent: const Color(0xff39e6d3),
    ),
    'teto_clockwork_voice': (
      material: SkinMaterial.clockworkVoice,
      wide: const Size(1672, 941),
      portrait: const Size(941, 1672),
      accent: const Color(0xffed4355),
    ),
  };

  test('Miku and Teto ship complete independent character themes', () async {
    for (final item in skins.entries) {
      final definition = ThemeCatalog.byId(item.key);
      expect(definition.category, 'character_theme', reason: item.key);
      expect(definition.material, item.value.material, reason: item.key);
      expect(definition.immersiveArtwork, isTrue, reason: item.key);
      expect(definition.animatedBackground, isTrue, reason: item.key);
      expect(
        definition.backgroundImage,
        isNot(definition.portraitBackgroundImage),
        reason: item.key,
      );
      expect(definition.palette!.accent, item.value.accent, reason: item.key);
      if (item.key == 'teto_clockwork_voice') {
        expect(definition.portraitArtworkScale, 1.32);
      }
      expect(ThemeValidator.validate(definition), isEmpty, reason: item.key);

      final raw =
          jsonDecode(await rootBundle.loadString(definition.assetManifest!))
              as Map<String, dynamic>;
      expect(ThemeAssetValidator.validate(raw), isEmpty, reason: item.key);
      final manifest = await ThemeAssetPipeline.load(definition.assetManifest!);
      expect(manifest, isNotNull, reason: item.key);
      expect(await ThemeAssetPipeline.missingAssets(manifest!), isEmpty);

      for (final asset in {
        definition.backgroundImage!: item.value.wide,
        definition.portraitBackgroundImage!: item.value.portrait,
      }.entries) {
        final data = await rootBundle.load(asset.key);
        final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
        final frame = await codec.getNextFrame();
        expect(frame.image.width, asset.value.width, reason: asset.key);
        expect(frame.image.height, asset.value.height, reason: asset.key);
        frame.image.dispose();
        codec.dispose();
      }
    }
  });

  test('both vocal skins activate distinct native UI and readable chat', () {
    for (final item in skins.entries) {
      final definition = ThemeCatalog.byId(item.key);
      final theme = SkinThemeBuilder.build(definition, Brightness.dark);
      expect(theme.extension<CharacterThemeExtension>(), isNotNull);
      expect(theme.extension<SkinCraft>()!.material, item.value.material);
      expect(theme.cardTheme.shape, isA<CraftFrameBorder>());
      expect(
        ThemeValidator.contrast(
          definition.tokens(Brightness.dark).aiForeground,
          definition.tokens(Brightness.dark).aiBubble,
        ),
        greaterThan(7),
        reason: item.key,
      );
    }
  });

  test('audio motion distinguishes waveform and VU meter frames', () {
    const miku = VocalSkinMotionPainter(
      material: SkinMaterial.digitalStage,
      primary: Color(0xff39e6d3),
      secondary: Color(0xff8adcf6),
    );
    const teto = VocalSkinMotionPainter(
      material: SkinMaterial.clockworkVoice,
      primary: Color(0xffed4355),
      secondary: Color(0xffffd78a),
      phase: .4,
    );
    expect(
      teto.shouldRepaint(
        const VocalSkinMotionPainter(
          material: SkinMaterial.clockworkVoice,
          primary: Color(0xffed4355),
          secondary: Color(0xffffd78a),
        ),
      ),
      isTrue,
    );
    expect(teto.shouldRepaint(miku), isTrue);
  });

  testWidgets('vocal skins keep semantic icons clear and full size', (
    tester,
  ) async {
    final manager = ThemeManager(MemoryThemeStore());
    addTearDown(manager.dispose);
    for (final id in skins.keys) {
      await manager.applyTheme(id);
      await tester.pumpWidget(
        harness(
          manager,
          const Scaffold(
            body: Center(
              child: SkinIcon(
                Icons.chat_outlined,
                size: 48,
                semanticLabel: '聊天',
              ),
            ),
          ),
        ),
      );
      final icon = tester.widget<Icon>(find.byIcon(Icons.chat_outlined));
      expect(icon.size, 48, reason: id);
      expect(find.bySemanticsLabel('聊天'), findsOneWidget, reason: id);
      expect(tester.takeException(), isNull, reason: id);
    }
  });

  testWidgets('vocal mode cards use one clean circular icon badge', (
    tester,
  ) async {
    final manager = ThemeManager(MemoryThemeStore());
    addTearDown(manager.dispose);
    for (final id in skins.keys) {
      await manager.applyTheme(id);
      await tester.pumpWidget(
        harness(
          manager,
          Scaffold(
            body: Center(
              child: SizedBox(
                width: 340,
                child: PlatformModeCard(
                  mode: AppMode.soloTrpg,
                  icon: Icons.explore_outlined,
                  description: '由 AI 担任主持人的个人冒险',
                  recentTitle: '测试冒险',
                  recentDetail: '第 1 幕 · 城市',
                  onTap: () {},
                ),
              ),
            ),
          ),
        ),
      );
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is DecoratedBox &&
              widget.decoration is ShapeDecoration &&
              (widget.decoration as ShapeDecoration).shape is CircleBorder,
        ),
        findsOneWidget,
        reason: id,
      );
      expect(tester.takeException(), isNull, reason: id);
    }
  });

  testWidgets('Miku and Teto mobile previews render without overflow', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final font = File('C:/Windows/Fonts/msyh.ttc');
      if (await font.exists()) {
        final data = ByteData.sublistView(await font.readAsBytes());
        for (final family in ['Ahem', 'Roboto', 'Microsoft YaHei']) {
          await (FontLoader(family)..addFont(Future.value(data))).load();
        }
      }
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final manager = ThemeManager(MemoryThemeStore());
    addTearDown(manager.dispose);
    final boundary = GlobalKey();

    for (final id in skins.keys) {
      await manager.applyTheme(id);
      final definition = ThemeCatalog.byId(id);
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: harness(
            manager,
            ThemeBackground(
              definition: definition,
              settings: manager.settings,
              child: Scaffold(
                body: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: SkinPreviewContent(definition: definition),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => precacheImage(
          AssetImage(definition.portraitBackgroundImage!),
          tester.element(find.byType(SkinPreviewContent)),
        ),
      );
      await tester.pump(const Duration(milliseconds: 800));
      expect(
        find.byKey(const ValueKey('skin-integrated-wallpaper')),
        findsWidgets,
        reason: id,
      );
      expect(find.text(definition.metadata['coverTitle']!), findsOneWidget);
      expect(tester.takeException(), isNull, reason: id);

      await tester.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory('build/vocal_skins_review').create(recursive: true);
        await File(
          'build/vocal_skins_review/${id == 'miku_digital_stage' ? 'miku' : 'teto'}-mobile-preview.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
  });
}
