import '../../models/trpg_memory_models.dart';
import '../../models/trpg_models.dart';

class MemorySummarizer {
  const MemorySummarizer();

  String session(TRPGSession session, Iterable<MemoryEntry> memories) {
    final important = memories.toList()
      ..sort((a, b) => b.importance.compareTo(a.importance));
    final quests = session.campaignState.quests
        .where((value) => value.status.name == 'active')
        .map((value) => value.title)
        .join('、');
    return [
      '当前位置：${session.worldState.location}',
      if (quests.isNotEmpty) '当前目标：$quests',
      ...important
          .take(8)
          .map(
            (value) =>
                '• ${value.summary.isEmpty ? value.content : value.summary}',
          ),
    ].join('\n');
  }

  String scene(String sceneTitle, Iterable<MemoryEntry> memories) => [
    '场景：$sceneTitle',
    ...memories
        .where((value) => value.locationId != null)
        .take(8)
        .map((value) => '• ${value.content}'),
  ].join('\n');

  String chapter(String chapter, Iterable<MemoryEntry> memories) => [
    '章节：$chapter',
    ...memories
        .where((value) => value.importance >= 6)
        .take(12)
        .map((value) => '• ${value.content}'),
  ].join('\n');

  String companion(String companionId, Iterable<MemoryEntry> memories) {
    final relevant = memories.where((value) => value.npcId == companionId);
    return relevant.isEmpty
        ? '尚未形成重要共同经历。'
        : relevant.take(8).map((value) => '• ${value.content}').join('\n');
  }
}
