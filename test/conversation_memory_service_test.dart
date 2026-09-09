import 'package:ai_tavern/models/chat_message.dart';
import 'package:ai_tavern/services/conversation_memory_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('自动记忆保留最近有效玩家与 AI 对话', () {
    final now = DateTime.utc(2026, 8, 11);
    final messages = [
      ChatMessage(
        id: 'm1',
        saveId: 's1',
        role: ChatRole.user,
        content: '我把安全绳系在腰间。',
        createdAt: now,
        updatedAt: now,
      ),
      ChatMessage(
        id: 'm2',
        saveId: 's1',
        role: ChatRole.assistant,
        content: '白雪检查绳结后走向前方。',
        createdAt: now,
        updatedAt: now,
      ),
      ChatMessage(
        id: 'm3',
        saveId: 's1',
        role: ChatRole.assistant,
        content: '',
        createdAt: now,
        updatedAt: now,
        errorMessage: '网络错误',
      ),
    ];

    final memory = const ConversationMemoryService().build(
      messages,
      playerName: '指挥官',
    );

    expect(memory, contains('指挥官：我把安全绳系在腰间。'));
    expect(memory, contains('AI剧情：白雪检查绳结后走向前方。'));
    expect(memory, isNot(contains('网络错误')));
  });

  test('自动记忆限制消息数量并优先保留最新内容', () {
    final now = DateTime.utc(2026, 8, 11);
    final messages = List.generate(
      5,
      (index) => ChatMessage(
        id: 'm$index',
        saveId: 's1',
        role: ChatRole.user,
        content: '消息$index',
        createdAt: now,
        updatedAt: now,
      ),
    );

    final memory = const ConversationMemoryService(
      maxMessages: 2,
    ).build(messages, playerName: '玩家');

    expect(memory, contains('消息3'));
    expect(memory, contains('消息4'));
    expect(memory, isNot(contains('消息2')));
  });
}
