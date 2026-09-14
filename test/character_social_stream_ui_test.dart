import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_tavern/models/api_profile.dart';
import 'package:ai_tavern/models/character.dart';
import 'package:ai_tavern/models/character_social.dart';
import 'package:ai_tavern/repositories/character_card_repository.dart';
import 'package:ai_tavern/repositories/character_social_repository.dart';
import 'package:ai_tavern/repositories/settings_repository.dart';
import 'package:ai_tavern/services/storage_service.dart';
import 'package:ai_tavern/services/character_social/character_social_service.dart';
import 'package:ai_tavern/screens/character_social/character_social_screen.dart';
import 'character_social_service_test.dart' show TestApi, TestAi;

class GatedSocialAi extends TestAi {
  final replyGate = Completer<void>();
  final memoryGate = Completer<void>();
  bool extracting = false;
  @override
  Stream<String> streamChat({
    required ApiProfile profile,
    required String apiKey,
    required List<Map<String, String>> messages,
  }) async* {
    if (messages.first['content']!.startsWith('仅提取')) {
      extracting = true;
      await memoryGate.future;
      yield '{"memories":[]}';
    } else {
      yield '先显示的回复';
      await replyGate.future;
      yield '，已经说完。';
    }
  }
}

void main() {
  for (final width in [390.0, 1280.0]) {
    testWidgets(
      'stream stays in Card and unlocks before memory finishes $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 850);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final storage = StorageService();
        final repo = CharacterSocialRepository(storage);
        final settings = SettingsRepository(storage);
        final ai = GatedSocialAi();
        final service = CharacterSocialService(
          repository: repo,
          cards: CharacterCardRepository(storage),
          api: TestApi(storage),
          settings: settings,
          ai: ai,
        );
        late SocialRecord conversation;
        await tester.runAsync(() async {
          await storage.initialize(databasePath: ':memory:');
          await service.addCharacter(const Character(id: 'a', name: '角色A'));
          conversation = (await repo.list('conversation')).single;
          await tester.pumpWidget(
            MaterialApp(
              home: SocialChatPage(
                service: service,
                conversation: conversation,
                names: const {'a': Character(id: 'a', name: '角色A')},
                settings: settings,
              ),
            ),
          );
        });
        Future<void> flush() async {
          for (var i = 0; i < 5; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 30)),
            );
            await tester.pump();
          }
        }

        Future<void> until(bool Function() ready) async {
          for (var i = 0; i < 30 && !ready(); i++) {
            await flush();
          }
          expect(
            ready(),
            isTrue,
            reason: 'asynchronous UI did not reach expected state',
          );
        }

        await flush();
        await tester.enterText(find.byType(TextField), '我明天会来');
        await tester.runAsync(() async {
          await tester.tap(find.byTooltip('发送'));
        });
        await flush();
        final streaming = find.text('先显示的回复');
        await until(() => streaming.evaluate().isNotEmpty);
        expect(streaming, findsOneWidget);
        expect(
          find.ancestor(of: streaming, matching: find.byType(Card)),
          findsOneWidget,
        );
        final field = tester.widget<TextField>(find.byType(TextField));
        expect(field.enabled, isNot(false));
        expect(field.controller!.text, isEmpty);
        // Draft typed during streaming must survive the reply's final save.
        await tester.enterText(find.byType(TextField), '下一条草稿');
        await tester.runAsync(() async {
          ai.replyGate.complete();
        });
        await flush();
        await until(
          () =>
              ai.extracting &&
              tester
                      .widget<IconButton>(
                        find.byWidgetPredicate(
                          (w) => w is IconButton && w.tooltip == '发送',
                        ),
                      )
                      .onPressed !=
                  null,
        );
        expect(ai.extracting, isTrue);
        expect(ai.memoryGate.isCompleted, isFalse);
        expect(find.text('先显示的回复，已经说完。'), findsOneWidget);
        expect(find.text('正在输入…'), findsNothing);
        expect(
          tester
              .widget<IconButton>(
                find.byWidgetPredicate(
                  (w) => w is IconButton && w.tooltip == '发送',
                ),
              )
              .onPressed,
          isNotNull,
        );
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          '下一条草稿',
        );
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          ai.memoryGate.complete();
          await service.pendingMemory;
        });
        await tester.pumpWidget(const SizedBox());
        service.dispose();
        await tester.runAsync(() => storage.database.close());
      },
    );
  }
}
