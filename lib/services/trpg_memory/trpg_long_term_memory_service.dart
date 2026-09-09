import 'package:uuid/uuid.dart';

import '../../models/trpg_memory_models.dart';
import '../../models/trpg_models.dart';
import 'memory_consolidator.dart';
import 'memory_consistency_checker.dart';
import 'memory_extractor.dart';
import 'memory_summarizer.dart';

class TRPGLongTermMemoryService {
  const TRPGLongTermMemoryService({
    this.extractor = const MemoryExtractor(),
    this.consolidator = const MemoryConsolidator(),
    this.consistency = const MemoryConsistencyChecker(),
    this.summarizer = const MemorySummarizer(),
  });
  static const _uuid = Uuid();
  final MemoryExtractor extractor;
  final MemoryConsolidator consolidator;
  final MemoryConsistencyChecker consistency;
  final MemorySummarizer summarizer;

  TRPGSession process(TRPGSession session, {bool force = false}) {
    var state = session.memoryState;
    if (state.entries.isEmpty &&
        (session.eventLog.isNotEmpty ||
            session.campaignState.quests.isNotEmpty ||
            session.campaignState.clues.isNotEmpty ||
            session.worldState.npcs.isNotEmpty)) {
      state = seedFromStructuredState(session);
    }
    final start = state.lastExtractionEventIndex.clamp(
      0,
      session.eventLog.length,
    );
    final newEvents = session.eventLog.skip(start).toList();
    final important = newEvents.any(_immediate);
    final actionCount =
        state.actionCountSinceExtraction +
        newEvents
            .where((value) => value.type == TRPGEventType.playerAction)
            .length;
    if (!force && !important && actionCount < 4) {
      return session.copyWith(
        memoryState: state.copyWith(actionCountSinceExtraction: actionCount),
      );
    }
    final candidates = extractor.extract(session, newEvents);
    final accepted = <MemoryEntry>[];
    final conflicts = <MemoryConflict>[];
    for (final candidate in candidates) {
      final found = consistency.check(session, candidate, [
        ...state.entries,
        ...accepted,
      ]);
      if (found.isEmpty) {
        accepted.add(candidate);
      } else {
        conflicts.addAll(found);
      }
    }
    final entries = consolidator.consolidate([...state.entries, ...accepted]);
    final summary = summarizer.session(session, entries);
    final sceneKey = session.worldState.currentScene.sceneId.isEmpty
        ? session.worldState.location
        : session.worldState.currentScene.sceneId;
    final chapterKey = 'act-${session.campaignState.currentAct}';
    final companionIds =
        (session.immersionState.campaignSnapshot['npcs'] as List? ?? const [])
            .whereType<Map>()
            .where((value) => value['role'] == 'companion')
            .map((value) => (value['npcId'] ?? value['id'] ?? '').toString())
            .where((value) => value.isNotEmpty);
    state = state.copyWith(
      entries: entries,
      sessionSummary: summary,
      sceneSummaries: {
        ...state.sceneSummaries,
        if (sceneKey.isNotEmpty)
          sceneKey: summarizer.scene(
            session.worldState.currentScene.title.isEmpty
                ? session.worldState.location
                : session.worldState.currentScene.title,
            entries.where(
              (value) =>
                  value.locationId == null ||
                  value.locationId ==
                      session.worldState.currentScene.locationId,
            ),
          ),
      },
      chapterSummaries: {
        ...state.chapterSummaries,
        chapterKey: summarizer.chapter(chapterKey, entries),
      },
      companionSummaries: {
        ...state.companionSummaries,
        for (final companionId in companionIds)
          companionId: summarizer.companion(companionId, entries),
      },
      lastExtractionEventIndex: session.eventLog.length,
      actionCountSinceExtraction: 0,
    );
    return session.copyWith(
      memoryState: state,
      sessionSummary: summary,
      metadata: {
        ...session.metadata,
        if (conflicts.isNotEmpty)
          'memoryConflicts': conflicts.map((value) => value.reason).toList(),
      },
    );
  }

  MemoryState seedFromStructuredState(TRPGSession session) {
    final now = DateTime.now();
    final entries = <MemoryEntry>[];
    MemoryEntry entry(
      MemoryType type,
      String title,
      String content,
      int importance, {
      String? npcId,
      String? questId,
    }) => MemoryEntry(
      id: _uuid.v4(),
      sessionId: session.id,
      type: type,
      title: title,
      content: content,
      summary: content,
      importance: importance,
      confidence: MemoryConfidence.confirmed,
      createdAt: now,
      updatedAt: now,
      npcId: npcId,
      questId: questId,
      relatedEntityIds: [?npcId, ?questId],
      tags: ['migration_seed'],
      canonPriority: CanonPriority.structuredState,
    );
    for (final quest in session.campaignState.quests.where(
      (value) => value.status.name != 'undiscovered',
    )) {
      entries.add(
        entry(
          MemoryType.questMemory,
          quest.title,
          '任务状态：${quest.status.name}；${quest.progress}',
          7,
          questId: quest.questId,
        ),
      );
    }
    for (final clue in session.campaignState.clues.where(
      (value) => value.discovered,
    )) {
      entries.add(entry(MemoryType.clue, clue.name, clue.description, 6));
    }
    for (final npc in session.worldState.npcs.where(
      (value) => value.relationship != 0 || !value.alive,
    )) {
      entries.add(
        entry(
          MemoryType.relationship,
          npc.name,
          '关系=${npc.relationship}；存活=${npc.alive}',
          !npc.alive ? 10 : 6,
          npcId: npc.npcId,
        ),
      );
    }
    for (final event in session.eventLog.where(_immediate)) {
      entries.addAll(extractor.extract(session, [event]));
    }
    final consolidated = consolidator.consolidate(entries);
    return MemoryState(
      entries: consolidated,
      sessionSummary: summarizer.session(session, consolidated),
      lastExtractionEventIndex: session.eventLog.length,
    );
  }

  bool _immediate(TRPGEvent event) => const {
    TRPGEventType.questUpdate,
    TRPGEventType.clueDiscovered,
    TRPGEventType.npcRelationship,
    TRPGEventType.combatEnded,
    TRPGEventType.itemGain,
    TRPGEventType.secretAction,
  }.contains(event.type);
}
