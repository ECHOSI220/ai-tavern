import '../../models/trpg_memory_models.dart';

class MemoryConsolidator {
  const MemoryConsolidator();

  List<MemoryEntry> consolidate(Iterable<MemoryEntry> source) {
    final result = <MemoryEntry>[];
    for (final memory in source) {
      final duplicateIndex = result.indexWhere(
        (existing) =>
            existing.type == memory.type &&
            existing.npcId == memory.npcId &&
            existing.locationId == memory.locationId &&
            existing.questId == memory.questId &&
            _similar(existing, memory),
      );
      if (duplicateIndex < 0 || memory.pinned) {
        result.add(memory);
        continue;
      }
      final previous = result[duplicateIndex];
      result[duplicateIndex] = previous.copyWith(
        content: memory.content.length > previous.content.length
            ? memory.content
            : previous.content,
        importance: memory.importance > previous.importance
            ? memory.importance
            : previous.importance,
        updatedAt: memory.updatedAt.isAfter(previous.updatedAt)
            ? memory.updatedAt
            : previous.updatedAt,
        sourceEventIds: {
          ...previous.sourceEventIds,
          ...memory.sourceEventIds,
        }.toList(),
        relatedEntityIds: {
          ...previous.relatedEntityIds,
          ...memory.relatedEntityIds,
        }.toList(),
        tags: {...previous.tags, ...memory.tags}.toList(),
      );
    }
    return result;
  }

  bool _similar(MemoryEntry a, MemoryEntry b) {
    final left = _terms('${a.title} ${a.content}');
    final right = _terms('${b.title} ${b.content}');
    if (left.isEmpty || right.isEmpty) return false;
    final overlap = left.intersection(right).length;
    return overlap /
            (left.length < right.length ? left.length : right.length) >=
        .72;
  }

  Set<String> _terms(String value) => value
      .toLowerCase()
      .split(RegExp(r'[^\p{L}\p{N}_]+', unicode: true))
      .where((word) => word.length > 1)
      .toSet();
}
