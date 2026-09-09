import '../../models/trpg_models.dart';
import '../trpg_memory/memory_context_builder.dart';
import '../trpg_memory/memory_privacy_filter.dart';
import '../trpg_memory/memory_ranker.dart';
import '../trpg_memory/memory_retriever.dart';

class TRPGRecapService {
  const TRPGRecapService({
    this.retriever = const MemoryRetriever(),
    this.contextBuilder = const MemoryContextBuilder(),
  });
  final MemoryRetriever retriever;
  final MemoryContextBuilder contextBuilder;

  String buildStructuredRecap(TRPGSession session, {String? playerId}) {
    final visibleTimeline = session.immersionState.timeline.where(
      (entry) =>
          entry.visibility == InformationVisibility.public ||
          (playerId != null && entry.ownerPlayerIds.contains(playerId)),
    );
    final activeQuests = session.campaignState.quests
        .where((quest) => quest.status.name == 'active')
        .map((quest) => quest.title)
        .join('、');
    final clues = session.campaignState.clues
        .where((clue) => clue.discovered)
        .map((clue) => clue.name)
        .join('、');
    final events = visibleTimeline.isNotEmpty
        ? visibleTimeline
              .toList()
              .reversed
              .take(8)
              .toList()
              .reversed
              .map(
                (entry) =>
                    '• ${entry.title}${entry.detail.isEmpty ? '' : '：${entry.detail}'}',
              )
              .join('\n')
        : session.eventLog.reversed
              .take(8)
              .toList()
              .reversed
              .map((event) => '• ${event.type.name}')
              .join('\n');
    final memories = retriever.retrieve(
      memories: session.memoryState.entries,
      access: MemoryAccessContext(
        requestingPlayerId: playerId,
        channel: playerId == null
            ? MemoryRequestChannel.public
            : MemoryRequestChannel.playerPrivate,
      ),
      context: MemoryRetrievalContext(
        query: '当前目标 最近发生 重要人物 未解决事件',
        locationId: session.worldState.currentScene.locationId,
        entityIds: [?playerId, ...session.worldState.currentScene.npcIds],
        limit: 8,
      ),
    );
    final memoryText = contextBuilder.build(memories, tokenBudget: 900);
    return '''上次发生了什么？

当前地点：${session.worldState.location.isEmpty ? '未知' : session.worldState.location}
当前场景：${session.worldState.currentScene.title}
进行中任务：${activeQuests.isEmpty ? '暂无' : activeQuests}
公开线索：${clues.isEmpty ? '暂无' : clues}

近期重要事件：
${events.isEmpty ? '• 冒险刚刚开始' : events}

${memoryText.isEmpty ? '' : memoryText}

${session.sessionSummary.isEmpty ? '' : 'AI 摘要：${session.sessionSummary}'}''';
  }
}
