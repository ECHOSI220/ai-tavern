import 'package:ai_tavern/controllers/chat_controller.dart';
import 'package:ai_tavern/models/api_profile.dart';
import 'package:ai_tavern/models/app_settings.dart';
import 'package:ai_tavern/models/save_slot.dart';
import 'package:ai_tavern/repositories/api_repository.dart';
import 'package:ai_tavern/repositories/save_repository.dart';
import 'package:ai_tavern/repositories/settings_repository.dart';
import 'package:ai_tavern/services/ai_service.dart';
import 'package:ai_tavern/services/secure_storage_service.dart';
import 'package:ai_tavern/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakeApiRepository extends ApiRepository {
  _FakeApiRepository(StorageService storage)
    : super(storage, SecureStorageService());

  static const profile = ApiProfile(
    id: 'profile-1',
    name: '测试 API',
    baseUrl: 'https://example.invalid/v1',
    model: 'test-model',
  );

  @override
  Future<List<ApiProfile>> getAll() async => const [profile];

  @override
  Future<String> readApiKey(String profileId) async => 'test-key';
}

class _FakeAiService extends AiService {
  final requests = <List<Map<String, String>>>[];

  @override
  Stream<String> streamChat({
    required ApiProfile profile,
    required String apiKey,
    required List<Map<String, String>> messages,
  }) async* {
    requests.add(messages);
    if (requests.length.isOdd) {
      yield requests.length == 1 ? '第一段 AI 剧情' : '第二段 AI 剧情';
    } else {
      yield requests.length == 2 ? '- 关键事件：玩家进入森林' : '- 关键事件：玩家进入森林并找到密道';
    }
  }
}

void main() {
  test('每两条消息自动压缩，持久化并加入后续 API Prompt', () async {
    sqfliteFfiInit();
    final storage = StorageService();
    await storage.initialize(databasePath: inMemoryDatabasePath);
    addTearDown(storage.close);

    final saveRepository = SaveRepository(storage);
    final settingsRepository = SettingsRepository(storage);
    await settingsRepository.save(
      const AppSettings(
        autoContextCompression: true,
        contextCompressionInterval: 2,
      ),
    );
    final save = SaveSlot.create(
      name: '自动压缩测试',
      playerName: '旅人',
      openingMessage: '你在森林边缘醒来。',
    );
    await saveRepository.upsert(save);
    final ai = _FakeAiService();
    final controller = ChatController(
      saveRepository,
      _FakeApiRepository(storage),
      settingsRepository,
      ai,
      initialSave: save,
    );
    await controller.initialize();
    addTearDown(controller.dispose);

    await controller.sendUserMessage('走进森林');
    expect(ai.requests, hasLength(2));
    expect(controller.save.memorySummary.content, contains('进入森林'));
    expect(
      controller.save.memorySummary.coveredMessageId,
      controller.save.messages.last.id,
    );

    final persisted = await saveRepository.getById(save.id);
    expect(persisted!.memorySummary.content, contains('进入森林'));
    expect(persisted.messages, hasLength(3));

    await controller.sendUserMessage('寻找隐藏通道');
    expect(ai.requests, hasLength(4));
    final nextStorySystemPrompt = ai.requests[2].first['content']!;
    expect(nextStorySystemPrompt, contains('关键事件：玩家进入森林'));
    expect(nextStorySystemPrompt, isNot(contains('第一段 AI 剧情')));
    expect(controller.save.memorySummary.content, contains('密道'));
    expect(controller.save.messages, hasLength(5));
  });
}
