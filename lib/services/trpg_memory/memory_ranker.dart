import '../../models/trpg_memory_models.dart';

class MemoryRetrievalContext {
  const MemoryRetrievalContext({
    required this.query,
    this.entityIds = const [],
    this.tags = const [],
    this.locationId,
    this.questId,
    this.npcId,
    this.limit = 12,
  });
  final String query;
  final List<String> entityIds, tags;
  final String? locationId, questId, npcId;
  final int limit;
}

class RankedMemory {
  const RankedMemory(this.memory, this.score);
  final MemoryEntry memory;
  final double score;
}

class MemoryRanker {
  const MemoryRanker();

  List<RankedMemory> rank(
    Iterable<MemoryEntry> memories,
    MemoryRetrievalContext context,
  ) {
    final queryTerms = _terms(context.query);
    final now = DateTime.now();
    final ranked = memories.map((memory) {
      final memoryTerms = _terms(
        [
          memory.title,
          memory.content,
          memory.summary,
          ...memory.tags,
        ].join(' '),
      );
      final overlap = queryTerms.intersection(memoryTerms).length;
      final entityOverlap = memory.relatedEntityIds
          .toSet()
          .intersection(context.entityIds.toSet())
          .length;
      final tagOverlap = memory.tags
          .map((value) => value.toLowerCase())
          .toSet()
          .intersection(
            context.tags.map((value) => value.toLowerCase()).toSet(),
          )
          .length;
      final ageDays = now.difference(memory.updatedAt).inHours / 24;
      final recency = 1 / (1 + ageDays / 30);
      final unresolved = memory.resolved ? 0 : 1.4;
      final scene =
          memory.locationId != null && memory.locationId == context.locationId
          ? 3
          : 0;
      final quest = memory.questId != null && memory.questId == context.questId
          ? 3
          : 0;
      final npc = memory.npcId != null && memory.npcId == context.npcId ? 4 : 0;
      final pinned = memory.pinned ? 8 : 0;
      final protected =
          const {
            MemoryType.promise,
            MemoryType.secret,
            MemoryType.foreshadowing,
            MemoryType.gmPlot,
            MemoryType.questMemory,
          }.contains(memory.type)
          ? 2
          : 0;
      final confidence = switch (memory.confidence) {
        MemoryConfidence.confirmed => 2,
        MemoryConfidence.likely => .6,
        MemoryConfidence.uncertain => 0,
      };
      return RankedMemory(
        memory,
        memory.importance * 1.4 +
            overlap * 2.2 +
            entityOverlap * 4 +
            tagOverlap * 2 +
            recency * 2 +
            unresolved +
            scene +
            quest +
            npc +
            pinned +
            protected +
            confidence,
      );
    }).toList()..sort((a, b) => b.score.compareTo(a.score));
    return ranked.take(context.limit).toList();
  }

  Set<String> _terms(String text) => text
      .toLowerCase()
      .split(RegExp(r'[^\p{L}\p{N}_]+', unicode: true))
      .where((value) => value.length > 1)
      .toSet();
}
