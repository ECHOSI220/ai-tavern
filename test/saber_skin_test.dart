import 'dart:io';
import 'dart:ui' as ui;
import 'package:ai_tavern/app/skins/skin_artwork.dart';
import 'package:ai_tavern/app/skins/skin_icon.dart';
import 'package:ai_tavern/app/skins/theme_background.dart';
import 'package:ai_tavern/app/skins/theme_catalog.dart';
import 'package:ai_tavern/app/skins/theme_manager.dart';
import 'package:ai_tavern/app/skins/theme_preferences.dart';
import 'package:ai_tavern/models/app_mode.dart';
import 'package:ai_tavern/screens/platform_home/platform_home_screen.dart';
import 'package:ai_tavern/screens/trpg_shared/trpg_play_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'theme_skin_system_test.dart' show MemoryThemeStore, harness;

const _samples = <(IconData, String)>[
  (Icons.explore_outlined, '单人冒险'),
  (Icons.lock_outline, '私密档案'),
  (Icons.auto_awesome, '主持叙事'),
  (Icons.menu_book_outlined, '世界书'),
  (Icons.person_outline, '角色'),
  (Icons.groups_outlined, '多人跑团'),
  (Icons.casino_outlined, '投骰'),
  (Icons.backpack_outlined, '背包'),
  (Icons.assignment_outlined, '任务'),
  (Icons.search, '线索'),
  (Icons.public, '世界'),
  (Icons.settings, '设置'),
  (Icons.send, '发送'),
  (Icons.forum_outlined, '对话'),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final knight = ThemeCatalog.byId('knight_oath_mooncourt');

  test(
    'integrated skin has distinct opaque landscape and portrait artwork',
    () async {
      for (final path in [
        knight.backgroundImage!,
        knight.portraitBackgroundImage!,
      ]) {
        final bytes = await rootBundle.load(path);
        final codec = await ui.instantiateImageCodec(
          bytes.buffer.asUint8List(),
        );
        final frame = await codec.getNextFrame();
        final image = frame.image;
        expect(image.width, greaterThan(900));
        expect(image.width > image.height, path == knight.backgroundImage);
        final rgba = (await image.toByteData())!.buffer.asUint8List();
        expect(rgba[3], 255);
        expect(rgba[(image.width - 1) * 4 + 3], 255);
        expect(
          rgba[((image.height ~/ 2) * image.width + image.width ~/ 2) * 4 + 3],
          greaterThan(240),
        );
        image.dispose();
        codec.dispose();
      }
    },
  );

  testWidgets(
    'heading is transparent copy over full-page art not a separate portrait card',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final manager = ThemeManager(MemoryThemeStore());
      addTearDown(manager.dispose);
      await manager.applyTheme(knight.id);
      for (final width in [320.0, 360.0, 700.0, 1200.0]) {
        tester.view.physicalSize = Size(width, 1200);
        await tester.pumpWidget(
          harness(
            manager,
            const Scaffold(
              body: SingleChildScrollView(child: SkinWelcomeHeader()),
            ),
            textScale: 1.8,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'width=$width');
        final art = tester.getRect(
          find.byKey(const ValueKey('skin-integrated-wallpaper')),
        );
        final title = tester.getRect(find.text('我的幻境酒馆'));
        expect(art.width, width);
        expect(art.height, 1200);
        expect(title.right, lessThanOrEqualTo(width * .53));
        expect(
          find.byKey(const ValueKey('skin-character-portrait')),
          findsNothing,
        );
        expect(
          find.descendant(
            of: find.byType(SkinWelcomeHeader),
            matching: find.byType(Image),
          ),
          findsNothing,
        );
        expect(find.text('Saber · 阿尔托莉雅'), findsNothing);
      }
    },
  );

  testWidgets(
    'heraldry is skin scoped and preserves unknown icon fallback and semantics',
    (tester) async {
      final manager = ThemeManager(MemoryThemeStore());
      addTearDown(manager.dispose);
      final semantics = tester.ensureSemantics();
      await manager.applyTheme(knight.id);
      await tester.pumpWidget(
        harness(
          manager,
          Scaffold(
            body: Wrap(
              children: [
                for (final sample in _samples)
                  SkinIcon(sample.$1, semanticLabel: sample.$2),
                const SkinIcon(Icons.close),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is OathIconPainter,
        ),
        findsNWidgets(14),
      );
      expect(find.byIcon(Icons.close), findsOneWidget);
      expect(find.bySemanticsLabel('私密档案'), findsOneWidget);
      expect(_samples.map((s) => SkinIcon.glyphFor(s.$1)).toSet().length, 14);
      await manager.applyTheme('classic_tavern');
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is OathIconPainter,
        ),
        findsNothing,
      );
      for (final sample in _samples) {
        expect(find.byIcon(sample.$1), findsOneWidget);
      }
      semantics.dispose();
    },
  );

  testWidgets('actual TRPG actions and composer keep callbacks and text', (
    tester,
  ) async {
    final manager = ThemeManager(MemoryThemeStore());
    final input = TextEditingController(text: '我查看纹章');
    addTearDown(manager.dispose);
    addTearDown(input.dispose);
    await manager.applyTheme(knight.id);
    var privateTaps = 0, rolls = 0;
    String? sent;
    await tester.pumpWidget(
      harness(
        manager,
        Scaffold(
          body: Column(
            children: [
              TrpgQuickActions(
                actions: [
                  TrpgActionSpec(
                    icon: Icons.lock_outline,
                    label: '私密档案',
                    onPressed: () => privateTaps++,
                  ),
                  TrpgActionSpec(
                    icon: Icons.casino_outlined,
                    label: '投骰',
                    onPressed: () => rolls++,
                  ),
                ],
              ),
              TrpgComposer(
                controller: input,
                hintText: '行动',
                onSend: () => sent = input.text,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('私密档案'));
    await tester.tap(find.text('投骰'));
    await tester.tap(find.byKey(const ValueKey('trpg_send_action')));
    expect(privateTaps, 1);
    expect(rolls, 1);
    expect(sent, '我查看纹章');
    expect(input.text, '我查看纹章');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'integrated chat wallpaper yields to custom wallpaper with no extra cutout',
    (tester) async {
      final manager = ThemeManager(MemoryThemeStore());
      addTearDown(manager.dispose);
      await manager.applyTheme(knight.id);
      for (final custom in [false, true]) {
        await tester.pumpWidget(
          harness(
            manager,
            Scaffold(
              body: ThemeBackground(
                key: const ValueKey('chat-skin-test'),
                chat: true,
                settings: ThemeSettings(
                  chatBackground: custom ? 'Z:/missing/saber-test.png' : null,
                ),
                child: const SizedBox.expand(
                  child: Center(child: Text('剧情保持原样')),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('chat-skin-test')),
            matching: find.byKey(const ValueKey('skin-integrated-wallpaper')),
          ),
          custom ? findsNothing : findsOneWidget,
        );
        expect(find.text('剧情保持原样'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('skin-chat-character-watermark')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'chat artwork stays page-aligned while history grows and scrolls',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final manager = ThemeManager(MemoryThemeStore());
      final scroll = ScrollController();
      addTearDown(manager.dispose);
      addTearDown(scroll.dispose);
      await manager.applyTheme(knight.id);
      for (final size in [const Size(430, 900), const Size(1200, 700)]) {
        tester.view.physicalSize = size;
        for (final count in [0, 1, 50]) {
          await tester.pumpWidget(
            harness(
              manager,
              Scaffold(
                appBar: AppBar(title: const Text('王之庭院')),
                body: Column(
                  children: [
                    const SizedBox(height: 120, child: Text('当前场景')),
                    Expanded(
                      child: TrpgTimelineViewport(
                        controller: scroll,
                        children: [
                          for (var i = 0; i < count; i++)
                            SizedBox(height: 150, child: Text('第 $i 段剧情')),
                        ],
                      ),
                    ),
                    const SizedBox(height: 90, child: Text('输入行动')),
                  ],
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          void checkCanvas() {
            final art = find.byKey(const ValueKey('skin-integrated-wallpaper'));
            expect(art, findsNWidgets(2));
            // Two paint surfaces, but exactly one continuous page composition:
            // the clipped chat slice cannot restart the face below the banner.
            expect(tester.getRect(art.at(0)), Offset.zero & size);
            expect(tester.getRect(art.at(1)), Offset.zero & size);
            final base = tester.widget<ColoredBox>(
              find.byKey(const ValueKey('trpg_timeline_dark_backdrop')),
            );
            expect(base.color.a, 1);
            expect(tester.takeException(), isNull);
          }

          checkCanvas();
          if (count == 50) {
            scroll.jumpTo(scroll.position.maxScrollExtent);
            await tester.pumpAndSettle();
            checkCanvas();
            scroll.jumpTo(0);
            await tester.pumpAndSettle();
            checkCanvas();
          }
        }
      }
    },
  );

  testWidgets('render mobile home and heraldry from production widgets', (
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
      final icons = File(
        'D:/AI_Tavern_Tools/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      );
      if (await icons.exists()) {
        await (FontLoader('MaterialIcons')..addFont(
              Future.value(ByteData.sublistView(await icons.readAsBytes())),
            ))
            .load();
      }
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 1100);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final manager = ThemeManager(MemoryThemeStore());
    addTearDown(manager.dispose);
    await manager.applyTheme(knight.id);
    final boundary = GlobalKey();
    for (final icons in [false, true]) {
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: harness(
            manager,
            Scaffold(
              body: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: icons
                        ? [
                            const SizedBox(height: 24),
                            Builder(
                              builder: (context) => Text(
                                '誓约纹章',
                                style: Theme.of(
                                  context,
                                ).textTheme.headlineMedium,
                              ),
                            ),
                            const Text('14 种语义化矢量图标 · 不是贴图'),
                            const SizedBox(height: 24),
                            Wrap(
                              spacing: 12,
                              runSpacing: 18,
                              children: [
                                for (final sample in _samples)
                                  SizedBox(
                                    width: 115,
                                    child: Card(
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 16,
                                        ),
                                        child: Column(
                                          children: [
                                            Builder(
                                              builder: (context) => SkinIcon(
                                                sample.$1,
                                                size: 32,
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.primary,
                                              ),
                                            ),
                                            const SizedBox(height: 12),
                                            Text(sample.$2),
                                            const SizedBox(height: 8),
                                            Builder(
                                              builder: (context) => SkinIcon(
                                                sample.$1,
                                                size: 16,
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.primary,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ]
                        : [
                            const SkinWelcomeHeader(),
                            const SizedBox(height: 20),
                            for (final mode in AppMode.values)
                              PlatformModeCard(
                                mode: mode,
                                icon: switch (mode) {
                                  AppMode.tavern => Icons.forum_outlined,
                                  AppMode.soloTrpg => Icons.explore_outlined,
                                  AppMode.multiplayerTrpg =>
                                    Icons.groups_outlined,
                                },
                                description: '选择角色，开启属于你的故事',
                                recentTitle: '雾港来信',
                                recentDetail: '第一幕 · 旧港钟楼',
                                onTap: () {},
                              ),
                          ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        for (final element in find.byType(Image).evaluate()) {
          await precacheImage((element.widget as Image).image, element);
        }
      });
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory('build/saber_review').create(recursive: true);
        await File(
          'build/saber_review/${icons ? 'icons' : 'home_mobile'}.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
  });
}
