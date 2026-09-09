import 'package:ai_tavern/controllers/chat_controller.dart';
import 'package:ai_tavern/models/api_profile.dart';
import 'package:ai_tavern/models/app_settings.dart';
import 'package:ai_tavern/models/chat_attachment.dart';
import 'package:ai_tavern/models/save_slot.dart';
import 'package:ai_tavern/models/play_mode.dart';
import 'package:ai_tavern/models/vision_analysis.dart';
import 'package:ai_tavern/models/vision_settings.dart';
import 'package:ai_tavern/repositories/api_repository.dart';
import 'package:ai_tavern/repositories/save_repository.dart';
import 'package:ai_tavern/repositories/settings_repository.dart';
import 'package:ai_tavern/services/ai_service.dart';
import 'package:ai_tavern/services/secure_storage_service.dart';
import 'package:ai_tavern/services/storage_service.dart';
import 'package:ai_tavern/services/vision/vision_provider.dart';
import 'package:ai_tavern/services/vision/vision_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('退出聊天页后重新进入会恢复消息和跨会话自动记忆', () async {
    sqfliteFfiInit();
    final storage = StorageService();
    await storage.initialize(databasePath: inMemoryDatabasePath);
    addTearDown(storage.close);

    final saveRepository = SaveRepository(storage);
    final apiRepository = ApiRepository(storage, SecureStorageService());
    final settingsRepository = SettingsRepository(storage);
    final save = SaveSlot.create(
      name: '白色回声测试',
      playerName: '指挥官',
      openingMessage: '白雪停在雪地里，询问你还记得什么。',
    );
    await saveRepository.upsert(save);

    final firstController = ChatController(
      saveRepository,
      apiRepository,
      settingsRepository,
      AiService(),
      initialSave: save,
    );
    await firstController.initialize();
    await firstController.sendUserMessage('我只记得方舟，还有左侧模糊的脚步声。');
    expect(firstController.save.conversationMemory, contains('我只记得方舟'));
    firstController.dispose();

    // 首页只持有不含消息正文的摘要对象，模拟退出聊天页后的真实重新进入流程。
    final homeSummary = (await saveRepository.getAll()).single;
    expect(homeSummary.messages, isEmpty);
    expect(homeSummary.messageCount, 3);

    final reopenedController = ChatController(
      saveRepository,
      apiRepository,
      settingsRepository,
      AiService(),
      initialSave: homeSummary,
    );
    await reopenedController.initialize();
    addTearDown(reopenedController.dispose);

    expect(reopenedController.save.messages, hasLength(3));
    expect(
      reopenedController.save.messages.any(
        (message) => message.content.contains('我只记得方舟'),
      ),
      isTrue,
    );
    expect(reopenedController.save.conversationMemory, contains('我只记得方舟'));
  });

  test('选项玩法首次进入生成六项并在退出后保留', () async {
    sqfliteFfiInit();
    final storage = StorageService();
    await storage.initialize(databasePath: inMemoryDatabasePath);
    addTearDown(storage.close);

    final saveRepository = SaveRepository(storage);
    final apiRepository = ApiRepository(storage, SecureStorageService());
    final settingsRepository = SettingsRepository(storage);
    final save = SaveSlot.create(
      name: '选项玩法测试',
      openingMessage: '你在陌生房间中醒来。',
      playMode: PlayMode.choice,
    );
    await saveRepository.upsert(save);

    final firstController = ChatController(
      saveRepository,
      apiRepository,
      settingsRepository,
      AiService(),
      initialSave: save,
    );
    await firstController.initialize();
    expect(firstController.save.pendingChoices, hasLength(6));
    final choices = [...firstController.save.pendingChoices];
    firstController.dispose();

    final homeSummary = (await saveRepository.getAll()).single;
    final reopenedController = ChatController(
      saveRepository,
      apiRepository,
      settingsRepository,
      AiService(),
      initialSave: homeSummary,
    );
    await reopenedController.initialize();
    addTearDown(reopenedController.dispose);

    expect(reopenedController.save.pendingChoices, choices);
    expect(reopenedController.save.playMode, PlayMode.choice);
  });

  test('选项玩法可自由输入并清空未使用的预设选项', () async {
    sqfliteFfiInit();
    final storage = StorageService();
    await storage.initialize(databasePath: inMemoryDatabasePath);
    addTearDown(storage.close);

    final saveRepository = SaveRepository(storage);
    final save = SaveSlot.create(
      name: '自由输入测试',
      openingMessage: '守卫拦在门前。',
      playMode: PlayMode.choice,
    );
    await saveRepository.upsert(save);
    final controller = ChatController(
      saveRepository,
      ApiRepository(storage, SecureStorageService()),
      SettingsRepository(storage),
      AiService(),
      initialSave: save,
    );
    await controller.initialize();
    addTearDown(controller.dispose);
    expect(controller.save.pendingChoices, isNotEmpty);

    await controller.submitFreeChoice('我举起双手示意没有敌意：“让我进去，我有急事。”');

    expect(
      controller.save.messages.any(
        (message) => message.content.contains('让我进去，我有急事'),
      ),
      isTrue,
    );
    expect(controller.save.pendingChoices, isEmpty);
    final restored = await saveRepository.getById(save.id);
    expect(
      restored!.messages.any(
        (message) => message.content.contains('让我进去，我有急事'),
      ),
      isTrue,
    );
  });

  test('图片分析结果会持久化并作为文字上下文发送给主模型', () async {
    sqfliteFfiInit();
    final storage = StorageService();
    await storage.initialize(databasePath: inMemoryDatabasePath);
    addTearDown(storage.close);

    final saveRepository = SaveRepository(storage);
    final apiRepository = ApiRepository(storage, _FakeSecureStorage());
    final settingsRepository = SettingsRepository(storage);
    const profile = ApiProfile(
      id: 'deepseek',
      name: 'DeepSeek V4 Flash',
      baseUrl: 'https://main.example/v1',
      model: 'deepseek-v4-flash',
    );
    await apiRepository.upsert(profile);
    await settingsRepository.save(
      const AppSettings(
        defaultApiProfileId: 'deepseek',
        visionSettings: VisionSettings(
          enabled: true,
          baseUrl: 'https://vision.example/v1',
          model: 'vision-model',
        ),
      ),
    );
    final save = SaveSlot.create(name: '看图存档', openingMessage: '请给我看看。');
    await saveRepository.upsert(save);
    final ai = _RecordingAiService();
    final controller = ChatController(
      saveRepository,
      apiRepository,
      settingsRepository,
      ai,
      initialSave: save,
      visionService: VisionService(
        factory: (_, _) => const _FakeVisionProvider(),
      ),
    );
    await controller.initialize();
    addTearDown(controller.dispose);

    await controller.sendUserMessage(
      '图里是谁？',
      attachments: const [
        ChatAttachment(
          id: 'image-1',
          localPath: r'D:\fake\image.jpg',
          mimeType: 'image/jpeg',
          width: 800,
          height: 600,
          sizeBytes: 1234,
        ),
      ],
    );

    final userMessage = controller.save.messages.firstWhere(
      (message) => message.attachments.isNotEmpty,
    );
    expect(
      userMessage.attachments.single.analysisStatus,
      AttachmentAnalysisStatus.analyzed,
    );
    expect(userMessage.visionContext, contains('白发少女'));
    expect(
      ai.lastMessages.any(
        (message) => message['content']!.contains('[用户发送了一张图片]'),
      ),
      isTrue,
    );

    final reopened = await saveRepository.getById(save.id);
    final persisted = reopened!.messages.firstWhere(
      (message) => message.attachments.isNotEmpty,
    );
    expect(persisted.attachments.single.analysis?.summary, '雪地中的白发少女');
    expect(persisted.visionContext, contains('图里是谁'));
  });
}

class _FakeSecureStorage extends SecureStorageService {
  @override
  Future<String> readApiKey(String profileId) async => 'main-key';

  @override
  Future<String> readVisionApiKey() async => 'vision-key';

  @override
  Future<void> writeApiKey(String profileId, String apiKey) async {}
}

class _RecordingAiService extends AiService {
  List<Map<String, String>> lastMessages = const [];

  @override
  Stream<String> streamChat({
    required ApiProfile profile,
    required String apiKey,
    required List<Map<String, String>> messages,
  }) async* {
    lastMessages = messages;
    yield '我看见她站在雪地里。';
  }
}

class _FakeVisionProvider implements VisionProvider {
  const _FakeVisionProvider();

  @override
  Future<List<VisionAnalysis>> analyzeImages(
    List<ChatAttachment> images, {
    required String userQuestion,
  }) async => List.filled(
    images.length,
    const VisionAnalysis(summary: '雪地中的白发少女', people: ['白发少女'], scene: '雪原'),
  );

  @override
  Future<VisionAnalysis> analyzeImage(
    ChatAttachment image, {
    required String userQuestion,
  }) async => (await analyzeImages([image], userQuestion: userQuestion)).single;

  @override
  void dispose() {}

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<String> testConnection() async => 'Vision OK';
}
