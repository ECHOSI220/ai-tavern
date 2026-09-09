import 'package:ai_tavern/models/app_settings.dart';
import 'package:ai_tavern/models/chat_message.dart';
import 'package:ai_tavern/models/memory_summary.dart';
import 'package:ai_tavern/models/nsfw_prompt_template.dart';
import 'package:ai_tavern/models/save_slot.dart';
import 'package:ai_tavern/services/context_compression_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 8, 12);

  ChatMessage message(String id, ChatRole role, String content) => ChatMessage(
    id: id,
    saveId: 'save-1',
    role: role,
    content: content,
    createdAt: now,
    updatedAt: now,
  );

  test('只压缩上次摘要后新增的有效消息', () {
    final save = SaveSlot.create(name: '测试').copyWith(
      messages: [
        message('m1', ChatRole.assistant, '开场'),
        message('m2', ChatRole.user, '旧行动'),
        message('m3', ChatRole.assistant, '新剧情'),
        message('m4', ChatRole.user, '新选择'),
      ],
      memorySummary: MemorySummary(
        content: '已有摘要',
        updatedAt: now,
        coveredMessageId: 'm2',
      ),
    );
    const service = ContextCompressionService();

    expect(service.pendingMessages(save).map((item) => item.id), ['m3', 'm4']);
    expect(service.shouldCompress(save, 2), isTrue);
    expect(service.shouldCompress(save, 3), isFalse);

    final request = service.buildRequest(save, service.pendingMessages(save));
    expect(request.last['content'], contains('已有摘要'));
    expect(request.last['content'], contains('新剧情'));
    expect(request.last['content'], isNot(contains('旧行动')));
  });

  test('设置 JSON 往返保留开关和压缩频率', () {
    const settings = AppSettings(
      autoContextCompression: true,
      contextCompressionInterval: 12,
    );
    final restored = AppSettings.fromJson(settings.toJson());

    expect(restored.autoContextCompression, isTrue);
    expect(restored.contextCompressionInterval, 12);
    expect(AppSettings.fromJson(const {}).autoContextCompression, isFalse);
  });

  test('NSFW 总开关、模板选择和自定义提示词可以持久化', () {
    const settings = AppSettings(
      nsfwEnabled: true,
      nsfwPromptTemplates: [
        NsfwPromptTemplate(
          id: 'custom-1',
          name: '自定义',
          content: '只使用成年、自愿的虚构角色。',
          enabled: true,
        ),
      ],
    );

    final restored = AppSettings.fromJson(settings.toJson());

    expect(restored.nsfwEnabled, isTrue);
    expect(restored.nsfwPromptTemplates, hasLength(1));
    expect(restored.nsfwPromptTemplates.single.name, '自定义');
    expect(restored.activeNsfwPrompt, contains('成年、自愿'));
    expect(restored.copyWith(nsfwEnabled: false).activeNsfwPrompt, isEmpty);
  });
}
