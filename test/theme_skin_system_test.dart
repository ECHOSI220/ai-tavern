import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:ai_tavern/app/skins/background_image_store.dart';
import 'package:ai_tavern/app/skins/theme_background.dart';
import 'package:ai_tavern/app/skins/theme_builder.dart';
import 'package:ai_tavern/app/skins/theme_catalog.dart';
import 'package:ai_tavern/app/skins/theme_definition.dart';
import 'package:ai_tavern/app/skins/theme_manager.dart';
import 'package:ai_tavern/app/skins/theme_preferences.dart';
import 'package:ai_tavern/app/skins/theme_validator.dart';
import 'package:ai_tavern/app/skins/theme_craft.dart';
import 'package:ai_tavern/app/skins/skin_artwork.dart';
import 'package:ai_tavern/models/app_mode.dart';
import 'package:ai_tavern/screens/platform_home/platform_home_screen.dart';
import 'package:ai_tavern/app/skins/theme_tokens.dart';
import 'package:ai_tavern/models/app_settings.dart';
import 'package:ai_tavern/repositories/settings_repository.dart';
import 'package:ai_tavern/screens/app_settings/skin_gallery_page.dart';
import 'package:ai_tavern/screens/trpg_shared/trpg_play_ui.dart';
import 'package:ai_tavern/services/storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class MemoryThemeStore implements ThemePreferenceStore {
  ThemePreference value = const ThemePreference();
  int writes = 0;
  bool fail = false;
  Completer<ThemePreference>? loading;
  @override
  Future<ThemePreference> loadThemePreference() async =>
      loading == null ? value : loading!.future;
  @override
  Future<void> saveThemePreference(ThemePreference preference) async {
    if (fail) throw const FileSystemException('test unavailable');
    writes++;
    value = ThemePreference.fromJson(preference.toJson());
  }
}

Widget harness(ThemeManager manager, Widget home, {double textScale = 1}) =>
    ThemeScope(
      manager: manager,
      child: ListenableBuilder(
        listenable: manager,
        builder: (context, _) => MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: SkinThemeBuilder.build(
            manager.getCurrentTheme(),
            Brightness.light,
            settings: manager.settings,
            transparentScaffold: true,
          ),
          themeAnimationDuration: Duration.zero,
          builder: (context, child) {
            final definition = manager.getCurrentTheme();
            final page = definition.category == 'character_theme'
                ? ColoredBox(
                    color: definition
                        .tokens(MediaQuery.platformBrightnessOf(context))
                        .backgroundPrimary,
                    child: child!,
                  )
                : ThemeBackground(child: child!);
            return MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: page,
            );
          },
          home: home,
        ),
      ),
    );

void main() {
  testWidgets('illustrated headers resolve own assets and fit large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final paths = <String>{};
    for (final d in ThemeCatalog.featured) {
      expect(d.backgroundImage, isNotNull);
      paths.add(d.backgroundImage!);
      await tester.pumpWidget(
        MaterialApp(
          theme: SkinThemeBuilder.build(d, Brightness.light),
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(360, 900),
              textScaler: TextScaler.linear(1.6),
            ),
            child: const Scaffold(
              body: SingleChildScrollView(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: SkinWelcomeHeader(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final art = tester.widget<Image>(find.byType(Image));
      expect(
        (art.image as ResizeImage).imageProvider,
        AssetImage(d.backgroundImage!),
      );
      await tester.runAsync(() async {
        final bytes = await rootBundle.load(d.backgroundImage!);
        final codec = await ui.instantiateImageCodec(
          bytes.buffer.asUint8List(),
        );
        final frame = await codec.getNextFrame();
        expect(frame.image.width, 1536);
        expect(frame.image.height, 1024);
        frame.image.dispose();
        codec.dispose();
      });
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: d.id);
      final title = tester.getRect(find.text('我的幻境酒馆'));
      final header = tester.getRect(find.byType(SkinIllustratedHeader));
      expect(header.contains(title.bottomRight), isTrue);
    }
    expect(paths.length, 3);
  });
  test(
    'featured skins have distinct material frames and directed surface palettes',
    () {
      expect(ThemeCatalog.featured.map((d) => d.material).toSet(), {
        SkinMaterial.brass,
        SkinMaterial.neon,
        SkinMaterial.paper,
      });
      const rect = Rect.fromLTWH(0, 0, 160, 100);
      for (final d in ThemeCatalog.featured) {
        final theme = SkinThemeBuilder.build(d, Brightness.light);
        final craft = theme.extension<SkinCraft>()!;
        expect(craft.refined, isTrue);
        expect(theme.cardTheme.shape, isA<CraftFrameBorder>());
        expect(theme.colorScheme.surface, d.palette!.surface);
        expect(
          theme.extension<ThemeTokens>()!.surfacePrimary,
          d.palette!.surface,
        );
        final path = craft.frame().getOuterPath(rect);
        expect(path.contains(rect.center), isTrue);
        if (craft.material == SkinMaterial.neon) {
          expect(path.contains(const Offset(158, 2)), isFalse);
        }
      }
    },
  );
  test(
    '16 built-in themes: contrast, semantic distinction, tokens and OLED',
    () {
      expect(ThemeCatalog.themes.length, 16);
      expect(ThemeCatalog.themes.map((e) => e.id).toSet().length, 16);
      for (final d in ThemeCatalog.themes) {
        expect(ThemeValidator.validate(d), isEmpty, reason: d.id);
        for (final brightness in Brightness.values) {
          final t = d.tokens(brightness);
          expect(t.colors.length, greaterThanOrEqualTo(23));
          expect(t.privateBubble, isNot(t.gmBubble));
          expect(t.success, isNot(t.danger));
          expect(t.backgroundPrimary.a, 1);
        }
      }
      expect(
        ThemeCatalog.byId(
          'oled_black',
        ).tokens(Brightness.light).backgroundPrimary,
        Colors.black,
      );
      expect(ThemeCatalog.recommend('圣杯战争'), contains('gothic_night'));
    },
  );

  test('validator rejects invalid theme data/resources', () {
    const invalid = ThemeDefinition(
      id: '',
      name: '',
      description: '',
      mode: SkinMode.dark,
      seed: Colors.blue,
      background: Colors.black,
      backgroundImage: '../bad.png',
      radius: -1,
      backgroundOpacity: 2,
      backgroundBlur: 30,
    );
    expect(
      ThemeValidator.validate(invalid),
      hasLength(greaterThanOrEqualTo(4)),
    );
  });

  test(
    'preview is isolated; per-theme preferences persist; failed save recovers',
    () async {
      final store = MemoryThemeStore();
      final manager = ThemeManager(store);
      addTearDown(manager.dispose);
      expect(manager.previewTheme('cyber_neon').id, 'cyber_neon');
      expect(manager.getCurrentTheme().id, 'default_clean');
      expect(store.writes, 0);
      await manager.applyTheme('cyber_neon');
      await manager.updateSettings(
        const ThemeSettings(
          brightness: .7,
          customBackground: 'app.png',
          chatBackground: 'chat.png',
        ),
      );
      await manager.applyTheme('gothic_night');
      expect(manager.settings.customBackground, isNull);
      await manager.applyTheme('cyber_neon');
      expect(manager.settings.chatBackground, 'chat.png');
      final restarted = ThemeManager(store);
      addTearDown(restarted.dispose);
      await restarted.loadThemePreference();
      expect(restarted.preference.toJson(), manager.preference.toJson());
      store.fail = true;
      await expectLater(
        manager.applyTheme('classic_tavern'),
        throwsA(isA<FileSystemException>()),
      );
      store.fail = false;
      await manager.applyTheme('ink_oriental');
      expect(store.value.themeId, 'ink_oriental');
      await manager.resetTheme();
      expect(manager.settings.toJson(), const ThemeSettings().toJson());
    },
  );

  test(
    'corrupt/unknown settings fallback; clamp; stale load cannot undo apply',
    () async {
      final normalized = ThemeSettings.fromJson({
        'brightness': double.nan,
        'blur': 99,
        'opacity': -9,
        'overlay': 9,
        'effectsLevel': 'bad',
        'customBackground': 123,
      });
      expect(normalized.brightness, 1);
      expect(normalized.blur, 20);
      expect(normalized.opacity, 0);
      expect(normalized.overlay, 1);
      expect(normalized.effectsLevel, ThemeEffectsLevel.low);
      expect(normalized.customBackground, isNull);
      final store = MemoryThemeStore()
        ..value = const ThemePreference(themeId: 'missing');
      final manager = ThemeManager(store);
      addTearDown(manager.dispose);
      await manager.loadThemePreference();
      expect(manager.getCurrentTheme().id, 'default_clean');
      expect(manager.warning, isNotNull);
      store.loading = Completer<ThemePreference>();
      final pending = manager.loadThemePreference();
      await manager.applyTheme('gothic_night');
      store.loading!.complete(const ThemePreference());
      await pending;
      expect(manager.getCurrentTheme().id, 'gothic_night');
    },
  );

  test(
    'SQLite skin writes leave every existing business table unchanged',
    () async {
      sqfliteFfiInit();
      final storage = StorageService();
      await storage.initialize(databasePath: inMemoryDatabasePath);
      addTearDown(storage.close);
      final repository = SettingsRepository(storage);
      await repository.save(const AppSettings());
      // Nonempty sentinels: theme code must preserve bytes, not reinterpret them.
      const payload = '{"content":"原聊天与角色文字","lorebook":["世界书"],"hp":18}';
      await storage.database.insert('save_slots', {
        'id': 'saved',
        'name': '原存档',
        'player_name': '玩家',
        'updated_at': 1,
        'last_played_at': 1,
        'payload': payload,
      });
      await storage.database.insert('messages', {
        'id': 'message',
        'save_id': 'saved',
        'role': 'assistant',
        'created_at': 1,
        'payload': payload,
      });
      for (final table in ['api_profiles', 'character_cards', 'story_cards']) {
        await storage.database.insert(table, {
          'id': 'existing',
          'name': '已有内容',
          'updated_at': 1,
          'payload': payload,
        });
      }
      await storage.database.insert('trpg_sessions', {
        'id': 'trpg',
        'title': '原跑团',
        'mode': 'solo',
        'status': 'active',
        'campaign_id': 'campaign',
        'updated_at': 1,
        'last_played_at': 1,
        'payload': payload,
      });
      await repository.loadThemePreference();
      final names = await storage.database.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name != 'skin_preferences'",
      );
      Future<Map<String, Object>> snapshot() async => {
        for (final row in names)
          row['name']! as String: await storage.database.query(
            row['name']! as String,
          ),
      };
      final before = await snapshot();
      final manager = ThemeManager(repository);
      addTearDown(manager.dispose);
      for (final d in ThemeCatalog.themes) {
        await manager.applyTheme(d.id);
      }
      await manager.updateSettings(
        const ThemeSettings(chatBackground: 'local-only.png'),
      );
      expect(await snapshot(), before);
      await repository.save(await repository.load());
      expect((await repository.loadThemePreference()).themeId, 'future_white');
      await storage.database.update('skin_preferences', {'payload': '{broken'});
      await manager.loadThemePreference();
      expect(manager.getCurrentTheme().id, 'default_clean');
      expect(await snapshot(), before);
    },
  );

  testWidgets(
    'switching themes keeps route, input, scroll, and active stream alive',
    (tester) async {
      final manager = ThemeManager(MemoryThemeStore());
      final stream = StreamController<String>();
      addTearDown(manager.dispose);
      addTearDown(stream.close);
      final probe = GlobalKey<_SessionProbeState>();
      await tester.pumpWidget(
        harness(manager, _SessionProbe(key: probe, stream: stream.stream)),
      );
      final original = probe.currentState!;
      original.input.text = '未发送的行动';
      original.scroll.jumpTo(240);
      await tester.tap(find.byTooltip('会话内换肤'));
      await tester.pumpAndSettle();
      expect(find.byType(SkinGalleryPage), findsOneWidget);
      for (final id in [
        'knight_oath_mooncourt',
        'cyber_neon',
        'gothic_night',
        'classic_tavern',
        'ink_oriental',
      ]) {
        await manager.applyTheme(id);
        await tester.pump();
        expect(probe.currentState, same(original));
        expect(original.input.text, '未发送的行动');
        expect(original.scroll.offset, 240);
        expect(original.disposed, isFalse);
      }
      stream.add('正在生成的回复仍然到达');
      await tester.pump();
      expect(original.messages, ['正在生成的回复仍然到达']);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(probe.currentState, same(original));
      expect(original.input.text, '未发送的行动');
      expect(original.scroll.offset, 240);
    },
  );

  testWidgets('gallery and all previews fit 360px with large Chinese text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final manager = ThemeManager(MemoryThemeStore());
    addTearDown(manager.dispose);
    await tester.pumpWidget(
      harness(manager, const SkinGalleryPage(), textScale: 1.5),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('背景与效果'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).last, const Offset(0, -1800));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    for (final d in ThemeCatalog.themes) {
      await tester.pumpWidget(
        harness(
          manager,
          ThemePreview(key: ValueKey(d.id), definition: d),
          textScale: 1.5,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: d.id);
    }
  });

  testWidgets('preview back does not save; apply changes theme immediately', (
    tester,
  ) async {
    final store = MemoryThemeStore(),
        manager = ThemeManager(MemoryThemeStore());
    final persisted = ThemeManager(store);
    addTearDown(manager.dispose);
    addTearDown(persisted.dispose);
    await tester.pumpWidget(harness(persisted, const SkinGalleryPage()));
    await tester.ensureVisible(find.text('预览').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('预览').first);
    await tester.pumpAndSettle();
    expect(find.text('应用皮肤'), findsOneWidget);
    await tester.tap(find.text('返回'));
    await tester.pumpAndSettle();
    expect(store.writes, 0);
    await tester.ensureVisible(find.text('使用').first);
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await preloadSkin(
        tester.element(find.byType(SkinGalleryPage)),
        ThemeCatalog.byId('knight_oath_mooncourt'),
        const ThemeSettings(),
      );
    });
    await tester.tap(find.text('使用').first);
    // Image decoding completes on the engine IO thread, not the fake clock.
    // pumpAndSettle alone can finish before that thread returns a frame.
    for (var i = 0; i < 50 && store.writes == 0; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(persisted.getCurrentTheme().id, 'knight_oath_mooncourt');
    expect(store.writes, 1);
  });

  testWidgets('OFF/LOW/reduce motion stop backgrounds; high animates', (
    tester,
  ) async {
    final manager = ThemeManager(MemoryThemeStore());
    addTearDown(manager.dispose);
    await manager.applyTheme('sakura_dream');
    await tester.pumpWidget(
      harness(manager, const Scaffold(body: Text('内容不动'))),
    );
    double phase() =>
        (tester
                    .widgetList<CustomPaint>(find.byType(CustomPaint))
                    .firstWhere((p) => p.painter is SkinBackdropPainter)
                    .painter!
                as SkinBackdropPainter)
            .phase;
    for (final level in [ThemeEffectsLevel.off, ThemeEffectsLevel.low]) {
      await manager.updateSettings(ThemeSettings(effectsLevel: level));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(phase(), 0);
    }
    await manager.updateSettings(
      const ThemeSettings(effectsLevel: ThemeEffectsLevel.high),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(phase(), greaterThan(0));
    await manager.updateSettings(
      const ThemeSettings(
        effectsLevel: ThemeEffectsLevel.high,
        reduceMotion: true,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(phase(), 0);
    await tester.pumpWidget(const SizedBox());
  });

  test(
    'background resize limits long edge before display; malformed rejects',
    () async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
      final picture = recorder.endRecording();
      final source = await picture.toImage(4096, 2048);
      final bytes = (await source.toByteData(
        format: ui.ImageByteFormat.png,
      ))!.buffer.asUint8List();
      source.dispose();
      picture.dispose();
      final result = await BackgroundImageStore.normalize(bytes);
      final codec = await ui.instantiateImageCodec(result);
      final frame = await codec.getNextFrame();
      expect(frame.image.width, 1920);
      expect(frame.image.height, 960);
      frame.image.dispose();
      codec.dispose();
      await expectLater(
        BackgroundImageStore.normalize(Uint8List(0)),
        throwsFormatException,
      );
      await expectLater(
        BackgroundImageStore.normalize(Uint8List.fromList([1, 2, 3])),
        throwsA(anything),
      );
    },
  );

  testWidgets('render actual preview page artifacts for visual review', (
    tester,
  ) async {
    // Optional local fonts for review artifacts; never ship platform font files.
    await tester.runAsync(() async {
      final chinese = File('C:/Windows/Fonts/msyh.ttc');
      if (await chinese.exists()) {
        final data = ByteData.sublistView(await chinese.readAsBytes());
        for (final family in ['Roboto', 'Microsoft YaHei', 'Ahem']) {
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
    tester.view.physicalSize = const Size(430, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final manager = ThemeManager(MemoryThemeStore());
    addTearDown(manager.dispose);
    final boundary = GlobalKey();
    for (final id in ThemeCatalog.themes.map((d) => d.id)) {
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: harness(
            manager,
            ThemePreview(key: ValueKey(id), definition: ThemeCatalog.byId(id)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory('build/theme_review').create(recursive: true);
        await File(
          'build/theme_review/$id.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    // Render the real shared play widgets, not only the skin-gallery demo.
    for (final d in ThemeCatalog.showcase) {
      await manager.applyTheme(d.id);
      final input = TextEditingController();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: harness(
            manager,
            Scaffold(
              appBar: AppBar(
                title: const Text('雾港来信'),
                actions: [
                  IconButton(
                    onPressed: () {},
                    tooltip: '存档',
                    icon: const Icon(Icons.save_outlined),
                  ),
                ],
              ),
              body: Column(
                children: [
                  const TrpgSceneSummary(
                    title: '旧港 · 钟楼街',
                    subtitle: '第一幕 · 入夜后的来信',
                    facts: [
                      TrpgFact(Icons.favorite_outline, 'HP 18/20'),
                      TrpgFact(Icons.assignment_outlined, '寻找送信人'),
                    ],
                  ),
                  Expanded(
                    child: TrpgTimelineViewport(
                      children: [
                        TrpgMessageBubble(
                          label: 'GM 主持',
                          time: DateTime(2026, 8, 31, 21, 8),
                          content:
                              '钟声穿过雾气，在空荡的街道上回响。\n\n你推开酒馆的木门。壁炉旁，一封没有署名的信被压在铜制烛台下，封口的蜡印还留着余温。\n\n“有人等了你很久。”店主放下擦拭中的杯子，望向窗外。街角的灯，恰好在这时熄灭。',
                          tone: TrpgMessageTone.gm,
                        ),
                        const TrpgMessageBubble(
                          label: '玩家',
                          content: '我拿起信，仔细查看封口的纹章。',
                          tone: TrpgMessageTone.player,
                        ),
                        const TrpgMessageBubble(
                          label: '私密信息 · 仅你可见',
                          content: '这个纹章，你曾在父亲的旧笔记里见过。',
                          tone: TrpgMessageTone.private,
                        ),
                      ],
                    ),
                  ),
                  TrpgComposer(
                    controller: input,
                    hintText: '描述你的行动…',
                    onSend: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'live ${d.id}');
      await tester.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          'build/theme_review/play_${d.id}.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      await tester.pumpWidget(const SizedBox());
      input.dispose();
    }
    // Actual home header and mode cards, composed at desktop width for review.
    tester.view.physicalSize = const Size(1200, 1000);
    for (final d in ThemeCatalog.showcase) {
      await manager.applyTheme(d.id);
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: harness(
            manager,
            Scaffold(
              body: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SkinWelcomeHeader(),
                      const SizedBox(height: 28),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final mode in AppMode.values)
                            Expanded(
                              child: PlatformModeCard(
                                mode: mode,
                                icon: switch (mode) {
                                  AppMode.tavern => Icons.forum_outlined,
                                  AppMode.characterSocial =>
                                    Icons.contacts_outlined,
                                  AppMode.soloTrpg => Icons.explore_outlined,
                                  AppMode.multiplayerTrpg =>
                                    Icons.groups_outlined,
                                },
                                description: '选择角色，开启属于你的故事',
                                recentTitle: '雾港来信',
                                recentDetail: '第一幕 · 旧港钟楼',
                                onTap: () {},
                              ),
                            ),
                        ],
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
      expect(tester.takeException(), isNull, reason: 'home artwork ${d.id}');
      await tester.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          'build/theme_review/home_${d.id}.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    // Full three-column gallery screenshot, useful to review visual hierarchy.
    tester.view.physicalSize = const Size(1200, 1050);
    await manager.applyTheme('classic_tavern');
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: harness(manager, const SkinGalleryPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      final image =
          await (boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        'build/theme_review/refined_gallery.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  });

  testWidgets(
    'ordinary TRPG retains an opaque full-height timeline in every skin',
    (tester) async {
      final manager = ThemeManager(MemoryThemeStore());
      addTearDown(manager.dispose);
      for (final d in ThemeCatalog.themes) {
        await manager.applyTheme(d.id);
        await tester.pumpWidget(
          harness(
            manager,
            const Scaffold(
              body: Column(
                children: [
                  Text('普通剧本'),
                  Expanded(
                    child: TrpgTimelineViewport(
                      children: [
                        TrpgMessageBubble(
                          label: '玩家',
                          content: '查看房间',
                          tone: TrpgMessageTone.player,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: d.id);
        final backdrop = tester.widget<ColoredBox>(
          find.byKey(const ValueKey('trpg_timeline_dark_backdrop')),
        );
        expect(backdrop.color, d.tokens(Brightness.light).backgroundPrimary);
        expect(backdrop.color.a, 1);
        final viewport = tester.getSize(
          find.byKey(const ValueKey('trpg_timeline_dark_backdrop')),
        );
        final content = tester.getSize(
          find.byKey(const ValueKey('trpg_timeline_content_backdrop')),
        );
        expect(content.height, greaterThanOrEqualTo(viewport.height));
        expect(find.text('查看房间'), findsOneWidget);
      }
    },
  );

  testWidgets('missing custom wallpaper falls back without covering content', (
    tester,
  ) async {
    final manager = ThemeManager(MemoryThemeStore());
    addTearDown(manager.dispose);
    await manager.applyTheme('cyber_neon');
    await manager.updateSettings(
      const ThemeSettings(customBackground: 'missing-skin-image.png'),
    );
    await tester.pumpWidget(
      harness(manager, const Scaffold(body: Text('内容仍可阅读'))),
    );
    // FileImage performs real file IO outside the widget test fake clock.
    await tester.runAsync(() => File('missing-skin-image.png').exists());
    await tester.pumpAndSettle();
    expect(find.text('内容仍可阅读'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(
      find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is SkinBackdropPainter,
      ),
      findsOneWidget,
    );
  });
}

class _SessionProbe extends StatefulWidget {
  const _SessionProbe({super.key, required this.stream});
  final Stream<String> stream;
  @override
  State<_SessionProbe> createState() => _SessionProbeState();
}

class _SessionProbeState extends State<_SessionProbe> {
  final input = TextEditingController();
  final scroll = ScrollController();
  final messages = <String>[];
  late final StreamSubscription<String> subscription;
  bool disposed = false;
  @override
  void initState() {
    super.initState();
    subscription = widget.stream.listen(messages.add);
  }

  @override
  void dispose() {
    disposed = true;
    subscription.cancel();
    scroll.dispose();
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      actions: [
        IconButton(
          tooltip: '会话内换肤',
          icon: const Icon(Icons.palette_outlined),
          onPressed: () => openSkinGallery(context),
        ),
      ],
    ),
    body: Column(
      children: [
        Expanded(
          child: ListView(
            controller: scroll,
            children: [for (var i = 0; i < 100; i++) Text('聊天记录 $i')],
          ),
        ),
        TextField(controller: input),
      ],
    ),
  );
}
