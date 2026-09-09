import '../../models/trpg_memory_models.dart';
import '../../models/trpg_models.dart';

class MemoryConflict {
  const MemoryConflict({
    required this.newMemory,
    required this.reason,
    this.existing,
  });
  final MemoryEntry newMemory;
  final MemoryEntry? existing;
  final String reason;
}

class MemoryConsistencyChecker {
  const MemoryConsistencyChecker();

  List<MemoryConflict> check(
    TRPGSession session,
    MemoryEntry candidate,
    Iterable<MemoryEntry> existing,
  ) {
    final conflicts = <MemoryConflict>[];
    if (candidate.npcId != null) {
      final npc = session.worldState.npcs
          .where((value) => value.npcId == candidate.npcId)
          .firstOrNull;
      if (npc != null && !npc.alive && _claimsAlive(candidate.content)) {
        conflicts.add(
          MemoryConflict(
            newMemory: candidate,
            reason: '与 Structured State 冲突：NPC ${npc.name} 已死亡',
          ),
        );
      }
    }
    for (final fact in existing) {
      if (fact.canonPriority.index <= candidate.canonPriority.index) {
        continue;
      }
      if (fact.relatedEntityIds
          .toSet()
          .intersection(candidate.relatedEntityIds.toSet())
          .isEmpty) {
        continue;
      }
      if (_opposes(fact.content, candidate.content)) {
        conflicts.add(
          MemoryConflict(
            newMemory: candidate,
            existing: fact,
            reason: '与更高优先级事实冲突',
          ),
        );
      }
    }
    return conflicts;
  }

  bool _claimsAlive(String text) => RegExp(r'走进|说话|正在|活着|出现').hasMatch(text);
  bool _opposes(String a, String b) {
    final deathA = RegExp(r'死亡|已死|被杀').hasMatch(a);
    final aliveB = _claimsAlive(b);
    final deathB = RegExp(r'死亡|已死|被杀').hasMatch(b);
    final aliveA = _claimsAlive(a);
    return deathA && aliveB || deathB && aliveA;
  }
}
