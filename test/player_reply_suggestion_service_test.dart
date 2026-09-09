import 'package:ai_tavern/controllers/chat_controller.dart';
import 'package:ai_tavern/models/api_profile.dart';
import 'package:ai_tavern/models/chat_message.dart';
import 'package:ai_tavern/models/player_reply_tone.dart';
import 'package:ai_tavern/models/save_slot.dart';
import 'package:ai_tavern/repositories/api_repository.dart';
import 'package:ai_tavern/repositories/save_repository.dart';
import 'package:ai_tavern/repositories/settings_repository.dart';
import 'package:ai_tavern/services/ai_service.dart';
import 'package:ai_tavern/services/player_reply_suggestion_service.dart';
import 'package:ai_tavern/services/secure_storage_service.dart';
import 'package:ai_tavern/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _profile = ApiProfile(
  id: 'reply-profile',
  name: '回复建议 API',
  baseUrl: 'https://example.invalid/v1',
  model: 'test-model',
);

class _FakeAiService extends AiService {
  final requests = <List<Map<String, String>>>[];
  ApiProfile? usedProfile;

  @override
  Stream<String> streamChat({
    required ApiProfile profile,
    required String apiKey,
    required List<Map<String, String>> messages,
  }) async* {
    usedProfile = profile;
    requests.add(messages);
    yield '建议：“我压低声音，直视着他：把你知道的事全部告诉我，';
    yield '现在。”';
  }
}

class _FakeApiRepository extends ApiRepository {
  _FakeApiRepository(StorageService storage)
    : super(storage, SecureStorageService());

  @override
  Future<List<ApiProfile>> getAll() async => const [_profile];

  @override
  Future<String> readApiKey(String profileId) async => 'test-key';
}

void main() {
  test('提供至少十五种可选思考语气', () {
    expect(PlayerReplyTone.values.length, greaterThanOrEqualTo(15));
    expect(
      PlayerReplyTone.values.map((tone) => tone.label),
      containsAll(['生气', '开心', '果断']),
    );
  });

  test('结合剧情与历史生成玩家文本，并清理标题和外层引号', () async {
    final ai = _FakeAiService();
    final save = SaveSlot.create(
      name: '雾港',
      playerName: '调查员',
      worldSetting: '漂浮城市依靠龙晶运转。',
      scenario: '调查失踪案件。',
    );
    final now = DateTime.utc(2026, 8, 12);
    final history = [
      ChatMessage(
        id: 'm1',
        saveId: save.id,
        role: ChatRole.assistant,
        content: '男人避开你的目光，说他什么也不知道。',
        createdAt: now,
        updatedAt: now,
      ),
    ];

    final result = await PlayerReplySuggestionService(ai).generate(
      profile: _profile,
      apiKey: 'test-key',
      save: save,
      history: history,
      tone: PlayerReplyTone.angry,
      customTone: '愤怒但不要失去理智',
      draft: '让他说实话',
    );

    expect(result, '我压低声音，直视着他：把你知道的事全部告诉我，现在。');
    expect(ai.usedProfile!.stream, isFalse);
    expect(ai.usedProfile!.maxTokens, 500);
    expect(ai.requests.single.first['content'], contains('不是续写剧情'));
    expect(ai.requests.single.last['content'], contains('愤怒但不要失去理智'));
    expect(ai.requests.single.last['content'], contains('让他说实话'));
  });

  test('控制器生成建议不会写入或发送聊天消息', () async {
    sqfliteFfiInit();
    final storage = StorageService();
    await storage.initialize(databasePath: inMemoryDatabasePath);
    addTearDown(storage.close);
    final saveRepository = SaveRepository(storage);
    final save = SaveSlot.create(name: '不自动发送测试', openingMessage: '守卫挡住了你的去路。');
    await saveRepository.upsert(save);
    final controller = ChatController(
      saveRepository,
      _FakeApiRepository(storage),
      SettingsRepository(storage),
      _FakeAiService(),
      initialSave: save,
    );
    await controller.initialize();
    addTearDown(controller.dispose);
    final before = controller.save.messages.length;

    final result = await controller.generatePlayerReply(
      tone: PlayerReplyTone.decisive,
    );

    expect(result, contains('全部告诉我'));
    expect(controller.save.messages, hasLength(before));
    final persisted = await saveRepository.getById(save.id);
    expect(persisted!.messages, hasLength(before));
  });
}
