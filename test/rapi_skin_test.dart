import 'dart:io';
import 'dart:ui' as ui;

import 'package:ai_tavern/app/skins/character_theme.dart';
import 'package:ai_tavern/app/skins/theme_background.dart';
import 'package:ai_tavern/app/skins/theme_builder.dart';
import 'package:ai_tavern/app/skins/theme_catalog.dart';
import 'package:ai_tavern/app/skins/theme_craft.dart';
import 'package:ai_tavern/app/skins/theme_manager.dart';
import 'package:ai_tavern/models/chat_message.dart';
import 'package:ai_tavern/screens/app_settings/skin_gallery_page.dart';
import 'package:ai_tavern/widgets/message_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import 'theme_skin_system_test.dart' show MemoryThemeStore, harness;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Rapi theme ships distinct portrait and landscape compositions',
    () async {
      final rapi = ThemeCatalog.byId('rapi_tactical_command');
      expect(rapi.category, 'character_theme');
      expect(rapi.material, SkinMaterial.tactical);
      expect(rapi.immersiveArtwork, isTrue);
      expect(rapi.animatedBackground, isTrue);
      expect(rapi.backgroundImage, isNot(rapi.portraitBackgroundImage));
      expect(rapi.palette!.accent, const Color(0xffef3340));

      for (final entry in {
        rapi.backgroundImage!: const Size(1672, 941),
        rapi.portraitBackgroundImage!: const Size(941, 1672),
      }.entries) {
        final data = await rootBundle.load(entry.key);
        final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
        final frame = await codec.getNextFrame();
        expect(frame.image.width, entry.value.width, reason: entry.key);
        expect(frame.image.height, entry.value.height, reason: entry.key);
        frame.image.dispose();
        codec.dispose();
      }
    },
  );

  test('Rapi theme enables its dedicated tactical character UI', () {
    final theme = SkinThemeBuilder.build(
      ThemeCatalog.byId('rapi_tactical_command'),
      Brightness.dark,
    );
    expect(theme.extension<CharacterThemeExtension>(), isNotNull);
    expect(theme.extension<SkinCraft>()!.material, SkinMaterial.tactical);
    expect(theme.colorScheme.primary, const Color(0xffef3340));
    expect(theme.cardTheme.shape, isA<CraftFrameBorder>());
  });

  test('Rapi tactical HUD repaints while scanning', () {
    const first = RapiTacticalPainter(
      signal: Color(0xffef3340),
      neutral: Color(0xffd9e0e5),
    );
    const next = RapiTacticalPainter(
      signal: Color(0xffef3340),
      neutral: Color(0xffd9e0e5),
      phase: .5,
    );
    expect(next.shouldRepaint(first), isTrue);
  });

  testWidgets('Rapi skin preview fits a 360px phone and renders artwork', (
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
    await manager.applyTheme('rapi_tactical_command');
    final boundary = GlobalKey();

    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: harness(
          manager,
          Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: SkinPreviewContent(
                definition: ThemeCatalog.byId('rapi_tactical_command'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => precacheImage(
        const AssetImage(
          'assets/themes/rapi_tactical_command/bg_rapi_mobile.png',
        ),
        tester.element(find.byType(SkinPreviewContent)),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(
      find.byKey(const ValueKey('skin-integrated-wallpaper')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('immersive-skin-heading')),
      findsOneWidget,
    );
    expect(find.text('地面夺还 · 战术待命'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.runAsync(() async {
      final image =
          await (boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory('build/rapi_skin_review').create(recursive: true);
      await File(
        'build/rapi_skin_review/rapi-mobile-preview.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });

    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -780),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      final image =
          await (boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        'build/rapi_skin_review/rapi-mobile-controls.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  });

  testWidgets('Rapi AI reply keeps bright text on its dark tactical panel', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final manager = ThemeManager(MemoryThemeStore());
    addTearDown(manager.dispose);
    await manager.applyTheme('rapi_tactical_command');
    final boundary = GlobalKey();
    final message = ChatMessage(
      id: 'rapi-ai',
      saveId: 'preview',
      role: ChatRole.assistant,
      content: '走廊里的人已经散去。\n\n**脚步声正在接近。**',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: harness(
          manager,
          Scaffold(
            appBar: AppBar(title: const Text('拉毗战术记录')),
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                MessageBubble(
                  message: message,
                  isStreaming: false,
                  onAction: (_) {},
                  onRetry: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    final headerContext = tester.element(find.text('AI 剧情'));
    expect(Theme.of(headerContext).brightness, Brightness.dark);
    final markdown = tester.widget<MarkdownBody>(find.byType(MarkdownBody));
    expect(
      markdown.styleSheet?.p?.color,
      ThemeCatalog.byId(
        'rapi_tactical_command',
      ).tokens(Brightness.dark).aiForeground,
    );
    expect(tester.takeException(), isNull);

    await tester.runAsync(() async {
      final image =
          await (boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory('build/rapi_skin_review').create(recursive: true);
      await File(
        'build/rapi_skin_review/rapi-ai-readability.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  });

  testWidgets('character route transition fully hides the previous page', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final manager = ThemeManager(MemoryThemeStore());
    addTearDown(manager.dispose);
    await manager.applyTheme('rapi_tactical_command');
    final boundary = GlobalKey();
    late BuildContext routeContext;

    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: harness(
          manager,
          Scaffold(
            body: Builder(
              builder: (context) {
                routeContext = context;
                return const ColoredBox(
                  key: ValueKey('old-page-marker'),
                  color: Color(0xffff00ff),
                  child: SizedBox.expand(),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    Navigator.of(routeContext).push<void>(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('新页面')),
          body: const Center(child: Text('切换完成')),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(
      find.byKey(const ValueKey('character-route-background')),
      findsWidgets,
    );
    expect(find.text('切换完成'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.runAsync(() async {
      final image =
          await (boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage();
      final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final offset = (400 * image.width + 8) * 4;
      final bytes = rgba!.buffer.asUint8List();
      expect(
        Color.fromARGB(
          255,
          bytes[offset],
          bytes[offset + 1],
          bytes[offset + 2],
        ),
        isNot(const Color(0xffff00ff)),
      );
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        'build/rapi_skin_review/rapi-route-transition.png',
      ).writeAsBytes(png!.buffer.asUint8List());
      image.dispose();
    });
  });
}
