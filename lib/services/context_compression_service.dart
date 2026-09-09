import '../models/chat_message.dart';
import '../models/save_slot.dart';

class ContextCompressionService {
  const ContextCompressionService();

  List<ChatMessage> validMessages(List<ChatMessage> messages) => messages
      .where(
        (message) =>
            message.role != ChatRole.system &&
            message.errorMessage == null &&
            message.hasModelContent,
      )
      .toList();

  List<ChatMessage> pendingMessages(SaveSlot save) {
    final valid = validMessages(save.messages);
    final coveredId = save.memorySummary.coveredMessageId;
    if (coveredId == null) return valid;
    final coveredIndex = valid.indexWhere((message) => message.id == coveredId);
    return coveredIndex < 0 ? valid : valid.sublist(coveredIndex + 1);
  }

  bool shouldCompress(SaveSlot save, int interval) =>
      pendingMessages(save).length >= interval.clamp(2, 30);

  List<Map<String, String>> buildRequest(
    SaveSlot save,
    List<ChatMessage> pending,
  ) {
    final player = save.playerName.trim().isEmpty
        ? '玩家'
        : save.playerName.trim();
    final transcript = pending
        .map(
          (message) =>
              '${message.role == ChatRole.user ? player : 'AI剧情'}：${message.modelContent.trim()}',
        )
        .join('\n\n');
    final previous = save.memorySummary.content.trim();
    return [
      const {
        'role': 'system',
        'content':
            '你是角色扮演游戏的上下文记忆压缩器。把旧记忆与新对话合并成简洁、可继续累积的中文记忆。'
            '必须保留：已发生事件与因果、角色关系变化、关键物品与伤势、承诺与决定、未解线索、已知世界信息、当前场景和下一步目标。'
            '删除重复描写、修辞和无关细节；不得续写剧情或捏造事实。使用分组要点，不要输出分析过程。',
      },
      {
        'role': 'user',
        'content':
            '[已有压缩记忆]\n${previous.isEmpty ? '（无）' : previous}\n\n'
            '[待合并的新对话]\n$transcript',
      },
    ];
  }
}
