import 'package:ai_tavern/models/save_slot.dart';
import 'package:ai_tavern/models/chat_message.dart';
import 'package:ai_tavern/repositories/save_repository.dart';
import 'package:ai_tavern/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('两个存档在 SQLite 中独立保存与删除', () async {
    sqfliteFfiInit();
    final storage = StorageService();
    await storage.initialize(databasePath: inMemoryDatabasePath);
    addTearDown(storage.close);
    final repository = SaveRepository(storage);
    final first = SaveSlot.create(name: '王国边境', scenario: '剑与魔法');
    final second = SaveSlot.create(name: '赛博都市', scenario: '雨夜追逐');

    await repository.upsert(first);
    await repository.upsert(second);
    expect((await repository.getAll()).map((save) => save.name), {
      '王国边境',
      '赛博都市',
    });

    await repository.delete(first.id);
    expect(await repository.getById(first.id), isNull);
    expect((await repository.getAll()).single.name, '赛博都市');
  });

  test('复制存档会重建消息 ID 与所属存档 ID', () async {
    sqfliteFfiInit();
    final storage = StorageService();
    await storage.initialize(databasePath: inMemoryDatabasePath);
    addTearDown(storage.close);
    final repository = SaveRepository(storage);
    final now = DateTime.utc(2026, 8, 10);
    final source = SaveSlot.create(name: '原存档').copyWith(
      messages: [
        ChatMessage(
          id: 'message-1',
          saveId: 'legacy-save-id',
          role: ChatRole.user,
          content: '我推开酒馆大门。',
          createdAt: now,
          updatedAt: now,
        ),
      ],
    );

    final copy = await repository.duplicate(source);

    expect(copy.id, isNot(source.id));
    expect(copy.messages.single.id, isNot(source.messages.single.id));
    expect(copy.messages.single.saveId, copy.id);
  });

  test('旧窗口保存较早快照时不会覆盖新窗口已经写入的对话', () async {
    sqfliteFfiInit();
    final storage = StorageService();
    await storage.initialize(databasePath: inMemoryDatabasePath);
    addTearDown(storage.close);
    final repository = SaveRepository(storage);
    final now = DateTime.now();
    final source = SaveSlot.create(name: '并发存档').copyWith(
      messages: [
        ChatMessage(
          id: 'opening',
          saveId: 'concurrent-save',
          role: ChatRole.assistant,
          content: '开场',
          createdAt: now,
          updatedAt: now,
        ),
      ],
      id: 'concurrent-save',
    );
    await repository.upsert(source);
    final staleWindow = await repository.getById(source.id);

    final newerWindow = source.copyWith(
      messages: [
        ...source.messages,
        ChatMessage(
          id: 'player-action',
          saveId: source.id,
          role: ChatRole.user,
          content: '继续前进',
          createdAt: now.add(const Duration(seconds: 1)),
          updatedAt: now.add(const Duration(seconds: 1)),
        ),
      ],
    );
    await repository.upsert(newerWindow);
    await repository.upsert(staleWindow!.copyWith(name: '旧窗口改名'));

    final restored = await repository.getById(source.id);
    expect(restored!.messages.map((message) => message.id), [
      'opening',
      'player-action',
    ]);
  });

  test('首页更新最后游玩时间后仍保留全部消息', () async {
    sqfliteFfiInit();
    final storage = StorageService();
    await storage.initialize(databasePath: inMemoryDatabasePath);
    addTearDown(storage.close);
    final repository = SaveRepository(storage);
    final now = DateTime.now();
    final save = SaveSlot.create(name: '首页重进测试').copyWith(
      messages: [
        ChatMessage(
          id: 'opening-home',
          saveId: 'home-save',
          role: ChatRole.assistant,
          content: '开场',
          createdAt: now,
          updatedAt: now,
        ),
        ChatMessage(
          id: 'user-home',
          saveId: 'home-save',
          role: ChatRole.user,
          content: '玩家行动',
          createdAt: now.add(const Duration(seconds: 1)),
          updatedAt: now.add(const Duration(seconds: 1)),
        ),
        ChatMessage(
          id: 'assistant-home',
          saveId: 'home-save',
          role: ChatRole.assistant,
          content: '剧情继续',
          createdAt: now.add(const Duration(seconds: 2)),
          updatedAt: now.add(const Duration(seconds: 2)),
        ),
      ],
      id: 'home-save',
    );
    await repository.upsert(save);

    final homeSummary = (await repository.getAll()).single;
    expect(homeSummary.messages, isEmpty);
    expect(homeSummary.messageCount, 3);
    await repository.upsert(homeSummary.copyWith(lastPlayedAt: DateTime.now()));

    final reopened = await repository.getById(save.id);
    expect(reopened!.messages, hasLength(3));
  });
}
