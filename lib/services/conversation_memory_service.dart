import '../models/chat_message.dart';

/// 生成可直接持久化的最近对话摘录，保证重新进入存档后仍有连续上下文。
///
/// 这不是替代 AI 长期摘要，而是无需额外 API 调用的安全兜底。较早的重要剧情
/// 仍应写入 MemorySummary；这里保存最近有效轮次并限制长度，避免 Prompt 无限增长。
class ConversationMemoryService {
  const ConversationMemoryService({
    this.maxMessages = 24,
    this.maxCharacters = 8000,
    this.maxCharactersPerMessage = 1200,
  });

  final int maxMessages;
  final int maxCharacters;
  final int maxCharactersPerMessage;

  String build(List<ChatMessage> messages, {required String playerName}) {
    final valid = messages
        .where(
          (message) =>
              message.role != ChatRole.system &&
              message.errorMessage == null &&
              message.hasModelContent,
        )
        .toList();
    if (valid.isEmpty) return '';

    final selected = <String>[];
    var characters = 0;
    for (final message in valid.reversed) {
      if (selected.length >= maxMessages) break;
      final speaker = message.role == ChatRole.user
          ? (playerName.trim().isEmpty ? '玩家' : playerName.trim())
          : 'AI剧情';
      var content = message.content.trim();
      if (content.isEmpty && message.hasImages) content = '[用户发送了图片]';
      if (content.length > maxCharactersPerMessage) {
        content = '${content.substring(0, maxCharactersPerMessage)}…';
      }
      final entry = '$speaker：$content';
      if (characters + entry.length > maxCharacters && selected.isNotEmpty) {
        break;
      }
      selected.insert(0, entry);
      characters += entry.length;
    }
    return selected.join('\n\n');
  }
}
