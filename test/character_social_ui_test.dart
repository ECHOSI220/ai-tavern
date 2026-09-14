import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_tavern/app/skins/theme_manager.dart';
import 'package:ai_tavern/models/character.dart';
import 'package:ai_tavern/models/character_social.dart';
import 'package:ai_tavern/repositories/character_card_repository.dart';
import 'package:ai_tavern/repositories/character_social_repository.dart';
import 'package:ai_tavern/repositories/settings_repository.dart';
import 'package:ai_tavern/repositories/save_repository.dart';
import 'package:ai_tavern/repositories/story_card_repository.dart';
import 'package:ai_tavern/services/storage_service.dart';
import 'package:ai_tavern/services/character_social/character_social_service.dart';
import 'package:ai_tavern/screens/character_social/character_social_screen.dart';
import 'character_social_service_test.dart' show TestApi, TestAi;
import 'theme_skin_system_test.dart' show MemoryThemeStore, harness;

class UiApi extends TestApi {
  UiApi(super.storage);
  @override
  Future<String> readAccountTokens() async => '';
}

void main() {
  for (final size in [const Size(390, 844), const Size(1280, 850)]) {
    testWidgets('real social screens navigate without overflow at ${size.width}', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final storage = StorageService();
      final cards = CharacterCardRepository(storage);
      final settings = SettingsRepository(storage);
      final api = UiApi(storage);
      await tester.runAsync(() async {
        await storage.initialize(databasePath: ':memory:');
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
        final repo = CharacterSocialRepository(storage);
        final service = CharacterSocialService(
          repository: repo,
          cards: cards,
          api: api,
          settings: settings,
          ai: TestAi(),
        );
        await service.addCharacter(
          const Character(id: 'quiet', name: '白雪', personality: '沉默寡言'),
        );
        await service.addCharacter(
          const Character(id: 'active', name: '露娜', personality: '活泼外向'),
        );
        await repo.save(
          SocialRecord.create('post', {
            'content': '训练结束。今晚想早点休息。',
            'visibility': 'PUBLIC_SOCIAL',
          }, characterId: 'quiet'),
        );
      });
      final manager = ThemeManager(MemoryThemeStore());
      await manager.applyTheme('knight_oath_mooncourt');
      final boundary = GlobalKey();
      await tester.runAsync(() async {
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: harness(
              manager,
              CharacterSocialScreen(
                cards: cards,
                api: api,
                settings: settings,
                saves: SaveRepository(storage),
                stories: StoryCardRepository(storage),
                onExit: () {},
              ),
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      // Character themes have continuous decorative animations, so settling every frame is not possible.
      Future<void> settle() async {
        for (var i = 0; i < 8; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 80)),
          );
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      await settle();
      expect(find.text('角色社交 · 消息'), findsOneWidget);
      expect(
        find.text('白雪'),
        findsOneWidget,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((v) => v.data)
            .join(' | '),
      );
      await tester.tap(find.text('联系人').last);
      await settle();
      expect(find.text('角色社交 · 联系人'), findsOneWidget);
      await tester.tap(find.text('朋友圈').last);
      await settle();
      expect(find.text('训练结束。今晚想早点休息。'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await render.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final directory = Directory('build/social_ui');
        await directory.create(recursive: true);
        await File(
          '${directory.path}/social-${size.width.toInt()}.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      await tester.tap(find.text('我的').last);
      await settle();
      expect(find.text('每日自动 AI 调用上限'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => storage.database.close());
      manager.dispose();
    });
  }
}
