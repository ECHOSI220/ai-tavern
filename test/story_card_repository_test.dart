import 'dart:io';

import 'package:ai_tavern/models/chat_message.dart';
import 'package:ai_tavern/models/save_slot.dart';
import 'package:ai_tavern/models/story_card.dart';
import 'package:ai_tavern/repositories/story_card_repository.dart';
import 'package:ai_tavern/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('旧版 v3 数据库升级后自动创建剧情卡片和角色卡表', () async {
    sqfliteFfiInit();
    final directory = await Directory.systemTemp.createTemp('ai-tavern-v3-');
    final path = '${directory.path}${Platform.pathSeparator}legacy.db';
    addTearDown(() => directory.delete(recursive: true));
    final legacy = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 3,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE save_slots (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              player_name TEXT NOT NULL,
              message_count INTEGER NOT NULL DEFAULT 0,
              updated_at INTEGER NOT NULL,
              last_played_at INTEGER NOT NULL,
              payload TEXT NOT NULL
            )
          ''');
        },
      ),
    );
    await legacy.close();

    final storage = StorageService();
    await storage.initialize(databasePath: path);
    await StoryCardRepository(
      storage,
    ).upsert(StoryCard.fromSave(SaveSlot.create(name: '升级测试')));

    expect(await StoryCardRepository(storage).getAll(), hasLength(1));
    final characterTables = await storage.database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='character_cards'",
    );
    expect(characterTables, hasLength(1));
    await storage.close();
  });

  test('卡片库保存自制卡片并保护官方卡片', () async {
    sqfliteFfiInit();
    final storage = StorageService();
    await storage.initialize(databasePath: inMemoryDatabasePath);
    addTearDown(storage.close);
    final repository = StoryCardRepository(storage);
    final now = DateTime.utc(2026, 8, 12);
    final official = StoryCard(
      id: officialWhiteEchoCardId,
      name: '官方剧情',
      isOfficial: true,
      template: SaveSlot.create(name: '官方剧情'),
      createdAt: now,
      updatedAt: now,
    );
    final custom = StoryCard.fromSave(SaveSlot.create(name: '我的剧情'));

    await repository.ensureOfficial(official);
    await repository.upsert(custom);
    final cards = await repository.getAll();

    expect(cards, hasLength(2));
    expect(cards.first.isOfficial, isTrue);
    await expectLater(
      repository.delete(official.id),
      throwsA(isA<StateError>()),
    );
    await repository.delete(custom.id);
    expect(await repository.getAll(), hasLength(1));
  });

  test('从剧情卡片创建新存档时重建身份并清空聊天进度', () {
    final now = DateTime.utc(2026, 8, 12);
    final source =
        SaveSlot.create(
          name: '循环剧场',
          coverImage: r'C:\images\theater.jpg',
        ).copyWith(
          conversationMemory: '旧进度',
          messages: [
            ChatMessage(
              id: 'old-message',
              saveId: 'old-save',
              role: ChatRole.user,
              content: '旧行动',
              createdAt: now,
              updatedAt: now,
            ),
          ],
        );
    final card = StoryCard.fromSave(source);
    final first = card.createSave();
    final second = card.createSave();

    expect(first.id, isNot(source.id));
    expect(first.id, isNot(second.id));
    expect(first.sourceStoryCardId, card.id);
    expect(first.messages, isEmpty);
    expect(first.conversationMemory, isEmpty);
    expect(first.coverImage, endsWith('theater.jpg'));
  });
}
