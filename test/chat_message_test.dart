import 'package:ai_tavern/models/chat_attachment.dart';
import 'package:ai_tavern/models/chat_message.dart';
import 'package:ai_tavern/models/vision_analysis.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('聊天消息 JSON 往返保留分支和中断状态', () {
    final now = DateTime.utc(2026, 8, 10, 12, 30);
    final message = ChatMessage(
      id: 'message-1',
      saveId: 'save-1',
      role: ChatRole.assistant,
      content: '“今晚恐怕走不了了……”',
      createdAt: now,
      updatedAt: now,
      branchId: 'branch-a',
      parentMessageId: 'message-0',
      generationIndex: 2,
      isInterrupted: true,
    );

    final restored = ChatMessage.fromJson(message.toJson());

    expect(restored.id, message.id);
    expect(restored.role, ChatRole.assistant);
    expect(restored.content, message.content);
    expect(restored.branchId, 'branch-a');
    expect(restored.parentMessageId, 'message-0');
    expect(restored.generationIndex, 2);
    expect(restored.isInterrupted, isTrue);
  });

  test('旧消息没有附件字段时仍可读取', () {
    final restored = ChatMessage.fromJson({
      'id': 'old-message',
      'saveId': 'save-1',
      'role': 'user',
      'content': '旧版本消息',
      'createdAt': '2026-08-10T12:30:00.000Z',
      'updatedAt': '2026-08-10T12:30:00.000Z',
    });

    expect(restored.attachments, isEmpty);
    expect(restored.visionContext, isNull);
    expect(restored.modelContent, '旧版本消息');
  });

  test('图片附件和隐藏视觉上下文可随消息持久化', () {
    final now = DateTime.utc(2026, 8, 13);
    final message = ChatMessage(
      id: 'image-message',
      saveId: 'save-1',
      role: ChatRole.user,
      content: '她是谁？',
      createdAt: now,
      updatedAt: now,
      attachments: const [
        ChatAttachment(
          id: 'image-1',
          localPath: r'D:\images\one.jpg',
          mimeType: 'image/jpeg',
          width: 1200,
          height: 800,
          sizeBytes: 12345,
          analysisStatus: AttachmentAnalysisStatus.analyzed,
          analysis: VisionAnalysis(summary: '雪地中的白发少女', detectedText: 'ARK'),
        ),
      ],
      visionContext: '[用户发送了一张图片]\n概要：雪地中的白发少女',
    );

    final restored = ChatMessage.fromJson(message.toJson());

    expect(restored.attachments, hasLength(1));
    expect(restored.attachments.single.analysis?.summary, '雪地中的白发少女');
    expect(restored.visionContext, contains('白发少女'));
    expect(restored.modelContent, isNot(contains('她是谁？')));
    expect(restored.modelContent, contains('[用户发送了一张图片]'));
  });
}
