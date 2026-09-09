import '../../models/trpg_models.dart';

class TRPGMemoryService {
  const TRPGMemoryService({
    this.recentMessageLimit = 30,
    this.contextCharacterBudget = 12000,
  });
  final int recentMessageLimit;
  final int contextCharacterBudget;

  List<TRPGMessage> selectRecentMessages(TRPGSession session) => session
      .chatHistory
      .where((message) => message.visibleToAi)
      .toList()
      .reversed
      .take(recentMessageLimit)
      .toList()
      .reversed
      .toList();

  List<TRPGEvent> selectImportantEvents(TRPGSession session) => session.eventLog
      .where(
        (event) =>
            event.visibleToAi &&
            event.type != TRPGEventType.system &&
            event.type != TRPGEventType.gmNarration,
      )
      .toList()
      .reversed
      .take(30)
      .toList()
      .reversed
      .toList();

  String buildDeterministicSummary(TRPGSession session) {
    final messages = session.chatHistory
        .where((message) => message.visibleToAi)
        .toList();
    if (messages.length <= recentMessageLimit) return session.sessionSummary;
    final older = messages.take(messages.length - recentMessageLimit).toList();
    final lines = older
        .map(
          (message) =>
              '${message.messageType.name}: ${_compact(message.content, 180)}',
        )
        .toList();
    return [
      if (session.sessionSummary.trim().isNotEmpty)
        session.sessionSummary.trim(),
      ...lines,
    ].join('\n').trim();
  }

  TRPGSession compact(TRPGSession session) =>
      session.copyWith(sessionSummary: buildDeterministicSummary(session));

  /// Highest-value structured sections are trimmed last. This is a character
  /// budget because providers tokenize differently; it prevents unbounded
  /// prompts without treating summaries as authoritative state.
  Map<String, String> buildBudgetedSections({
    required String system,
    required String scene,
    required String player,
    required String quests,
    required String clues,
    required String relevantSecrets,
    required String recentMessages,
    required String summary,
  }) {
    final sections = <String, String>{
      'system': system,
      'scene': scene,
      'player': player,
      'quests': quests,
      'clues': clues,
      'secrets': relevantSecrets,
      'recent': recentMessages,
      'summary': summary,
    };
    var used = 0;
    final result = <String, String>{};
    for (final key in const [
      'system',
      'scene',
      'player',
      'quests',
      'clues',
      'secrets',
      'recent',
      'summary',
    ]) {
      final value = sections[key] ?? '';
      final remaining = contextCharacterBudget - used;
      if (remaining <= 0) {
        result[key] = '';
        continue;
      }
      result[key] = value.length <= remaining
          ? value
          : '${value.substring(0, remaining.clamp(0, value.length))}…';
      used += result[key]!.length;
    }
    return result;
  }

  String _compact(String value, int maxLength) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    return normalized.length <= maxLength
        ? normalized
        : '${normalized.substring(0, maxLength)}…';
  }
}
