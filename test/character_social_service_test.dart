import 'package:flutter_test/flutter_test.dart';
import 'package:ai_tavern/models/api_profile.dart';
import 'package:ai_tavern/models/character.dart';
import 'package:ai_tavern/models/character_social.dart';
import 'package:ai_tavern/models/trpg_memory_models.dart';
import 'package:ai_tavern/repositories/api_repository.dart';
import 'package:ai_tavern/repositories/character_card_repository.dart';
import 'package:ai_tavern/repositories/character_social_repository.dart';
import 'package:ai_tavern/repositories/settings_repository.dart';
import 'package:ai_tavern/services/ai_service.dart';
import 'package:ai_tavern/services/storage_service.dart';
import 'package:ai_tavern/services/secure_storage_service.dart';
import 'package:ai_tavern/services/character_social/character_social_service.dart';
import 'package:ai_tavern/services/character_social/social_import_service.dart';

class TestApi extends ApiRepository {
  TestApi(StorageService storage) : super(storage, SecureStorageService());
  @override
  Future<List<ApiProfile>> getAll() async => [
    const ApiProfile(
      id: 'test',
      name: 'test',
      baseUrl: 'https://example.invalid',
      model: 'test',
    ),
  ];
  @override
  Future<String> readApiKey(String profileId) async => 'not-a-real-key';
}

class TestAi extends AiService {
  int calls = 0;
  bool fail = false;
  final prompts = <String>[];
  @override
  Stream<String> streamChat({
    required ApiProfile profile,
    required String apiKey,
    required List<Map<String, String>> messages,
  }) async* {
    calls++;
    prompts.add(messages.map((m) => m['content']).join('\n'));
    if (fail) throw StateError('Test network failure');
    final system = messages.first['content']!;
    if (system.startsWith('仅提取')) {
      yield '{"memories":[{"content":"用户答应明天来","evidence":"我明天会来","importance":8,"type":"PROMISE"}],"event":"support"}';
    } else if (system.contains('仅返回角色ID')) {
      yield '[]';
    } else if (system.contains('like布尔值')) {
      yield '{"like":true,"comment":"早点休息。"}';
    } else if (system.contains('日常动态')) {
      yield '今天的训练结束了。';
    } else {
      yield '我记住了，';
      yield '明天见。';
    }
  }
}

class OverlapDetectingAi extends TestAi {
  bool active = false;
  @override
  Stream<String> streamChat({
    required ApiProfile profile,
    required String apiKey,
    required List<Map<String, String>> messages,
  }) async* {
    if (active) throw StateError('overlapping streams');
    active = true;
    try {
      await Future<void>.delayed(const Duration(milliseconds: 15));
      yield* super.streamChat(
        profile: profile,
        apiKey: apiKey,
        messages: messages,
      );
    } finally {
      active = false;
    }
  }
}

void main() {
  late StorageService storage;
  late CharacterSocialRepository repo;
  late CharacterCardRepository cards;
  late CharacterSocialService service;
  late TestAi ai;
  setUp(() async {
    storage = StorageService();
    await storage.initialize(databasePath: ':memory:');
    repo = CharacterSocialRepository(storage);
    cards = CharacterCardRepository(storage);
    ai = TestAi();
    service = CharacterSocialService(
      repository: repo,
      cards: cards,
      api: TestApi(storage),
      settings: SettingsRepository(storage),
      ai: ai,
    );
    await service.initialize();
  });
  tearDown(() async {
    service.dispose();
    await storage.database.close();
  });
  test(
    'social provider queues concurrent requests and stops after disposal',
    () async {
      final provider = OverlapDetectingAi();
      final queued = CharacterSocialService(
        repository: repo,
        cards: cards,
        api: TestApi(storage),
        settings: SettingsRepository(storage),
        ai: provider,
      );
      final replies = await Future.wait(
        List.generate(
          3,
          (_) => queued.generate([
            {'role': 'system', 'content': 'reply'},
            {'role': 'user', 'content': 'hello'},
          ]),
        ),
      );
      expect(replies, hasLength(3));
      expect(provider.calls, 3);
      queued.dispose();
      await expectLater(
        queued.generate([
          {'role': 'system', 'content': 'reply'},
        ]),
        throwsStateError,
      );
      expect(provider.calls, 3);
    },
  );
  test(
    'import, streaming reply, extracted memory, relationship and retry idempotency',
    () async {
      final c = await service.addCharacter(
        const Character(id: 'a', name: 'A', personality: '活泼'),
      );
      final again = await service.addCharacter(
        const Character(id: 'a', name: 'A', personality: '活泼'),
      );
      expect(again.id, c.id);
      final conversation = (await repo.list('conversation')).single;
      final chunks = <String>[];
      await service.send(
        conversation,
        '我明天会来',
        onChunk: (_, v) => chunks.add(v),
      );
      expect(chunks.length, 2);
      expect(await repo.list('message'), hasLength(2));
      expect(await repo.list('memory'), hasLength(1));
      expect(((await repo.get(c.id))!.data['relationship'] as Map)['trust'], 2);
      final calls = ai.calls;
      await service.send(conversation, '我明天会来', retryId: 'retry');
      expect(ai.calls, calls);
      expect(await repo.list('message'), hasLength(2));
    },
  );
  test(
    'API failure preserves user message and retry does not duplicate',
    () async {
      await service.addCharacter(const Character(id: 'a', name: 'A'));
      final conversation = (await repo.list('conversation')).single;
      ai.fail = true;
      await expectLater(service.send(conversation, '我明天会来'), throwsStateError);
      expect(await repo.list('message'), hasLength(1));
      ai.fail = false;
      await service.send(conversation, '我明天会来', retryId: 'retry');
      expect(await repo.list('message'), hasLength(2));
    },
  );
  test(
    '20 characters after three days obey budget, cooldown and small event count',
    () async {
      await service.configure({'quality': 'balanced', 'dailyBudget': 4});
      for (var i = 0; i < 20; i++) {
        final c = await service.addCharacter(
          Character(id: '$i', name: 'C$i', personality: '活泼外向'),
        );
        await repo.save(
          c.change({
            'lastSimulated': DateTime.now()
                .subtract(const Duration(days: 3))
                .millisecondsSinceEpoch,
          }),
        );
      }
      await service.catchUp();
      expect(ai.calls, 4);
      expect(await repo.list('post'), hasLength(4));
      expect(await repo.list('event'), hasLength(20));
      await service.catchUp();
      expect(ai.calls, 4);
      expect(await repo.list('event'), hasLength(20));
    },
  );
  test('low cost mode never invokes AI in offline catch-up', () async {
    final c = await service.addCharacter(const Character(id: 'a', name: 'A'));
    await repo.save(c.change({'lastSimulated': 0}));
    await service.catchUp();
    expect(ai.calls, 0);
    expect(await repo.list('event'), hasLength(1));
  });
  test(
    'rich simulation stops at budget without losing deterministic events',
    () async {
      await service.configure({'quality': 'rich', 'dailyBudget': 1});
      for (final id in ['a', 'b']) {
        final contact = await service.addCharacter(Character(id: id, name: id));
        await repo.save(contact.change({'lastSimulated': 0}));
      }
      await service.catchUp();
      expect(ai.calls, 1);
      final events = await repo.list('event');
      expect(events, hasLength(2));
      expect(
        events.where((e) => e.text('source') == 'rich_simulation'),
        hasLength(1),
      );
      expect(await repo.list('post'), isEmpty);
    },
  );
  test('only acquainted characters react to a character moment', () async {
    final a = await service.addCharacter(
      const Character(id: 'a', name: 'A', personality: '活泼'),
    );
    final b = await service.addCharacter(
      const Character(id: 'b', name: 'B', personality: '活泼'),
    );
    await service.addCharacter(
      const Character(id: 'c', name: 'C', personality: '活泼'),
    );
    await service.createGroup('相识', [a, b]);
    final post = SocialRecord.create('post', {
      'content': '训练结束',
      'visibility': 'PUBLIC_SOCIAL',
    }, characterId: 'a');
    await repo.save(post);
    await service.react(post);
    expect(ai.calls, 1);
    expect((await repo.list('comment')).single.characterId, 'b');
  });
  test(
    'clearing messages preserves memories unless explicitly selected',
    () async {
      await service.addCharacter(const Character(id: 'a', name: 'A'));
      final conversation = (await repo.list('conversation')).single;
      await service.send(conversation, '我明天会来');
      await service.clearConversation(conversation, clearMemories: false);
      expect(await repo.list('message'), isEmpty);
      expect(await repo.list('memory'), hasLength(1));
      await service.clearConversation(conversation, clearMemories: true);
      expect(await repo.list('memory'), isEmpty);
    },
  );
  test('user post, character like/comment and world boundaries', () async {
    await service.addCharacter(
      const Character(id: 'a', name: 'A', personality: '活泼外向'),
    );
    await service.addCharacter(
      const Character(id: 'b', name: 'B', personality: '活泼外向'),
      worldId: 'other',
    );
    await service.publish('今天很累', 'default');
    expect(await repo.list('like'), hasLength(1));
    expect((await repo.list('comment')).single.characterId, 'a');
    final post = (await repo.list('post')).single;
    await service.like(post);
    await service.like(post);
    expect(
      (await repo.list('like')).where((v) => v.characterId == 'user'),
      isEmpty,
    );
  });
  test(
    'group director may choose silence; strangers meet only after explicit group creation',
    () async {
      final a = await service.addCharacter(const Character(id: 'a', name: 'A'));
      final b = await service.addCharacter(const Character(id: 'b', name: 'B'));
      expect(await repo.list('edge'), isEmpty);
      final group = await service.createGroup('Group', [a, b]);
      expect(await repo.list('edge'), hasLength(1));
      await service.send(group, '大家好');
      expect((await repo.list('message', parentId: group.id)), hasLength(1));
    },
  );
  test(
    'card edits preserve memories; referenced deletion requires snapshot choice',
    () async {
      await service.addCharacter(const Character(id: 'a', name: 'A'));
      final c = (await repo.list('conversation')).single;
      await service.send(c, '我明天会来');
      await cards.upsert(
        const Character(id: 'a', name: 'New', personality: '沉默'),
      );
      expect((await service.character('a'))!.name, 'New');
      expect(await repo.list('memory'), hasLength(1));
      await expectLater(cards.delete('a'), throwsStateError);
      await cards.delete('a', preserveSocialSnapshot: true);
      expect((await service.character('a'))!.name, 'New');
    },
  );
  test('GM hidden and unknown experiences cannot be shared', () {
    final m = MemoryEntry(
      id: 'm',
      sessionId: 's',
      type: MemoryType.event,
      title: 'Event',
      content: 'Public',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    final known = [
      KnowledgeRelation(
        id: 'k',
        subjectId: 'a',
        type: KnowledgeRelationType.witnessed,
        objectId: 'm',
        createdAt: DateTime.now(),
      ),
    ];
    expect(SocialImportService.shareable(m, 'a', known), isTrue);
    expect(SocialImportService.shareable(m, 'b', known), isFalse);
    expect(
      SocialImportService.shareable(
        m.copyWith(visibility: MemoryVisibility.gmOnly),
        'a',
        known,
      ),
      isFalse,
    );
  });
}
