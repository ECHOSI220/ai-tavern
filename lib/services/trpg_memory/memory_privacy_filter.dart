import '../../models/trpg_memory_models.dart';

enum MemoryRequestChannel { public, playerPrivate, npc, companion, gm }

class MemoryAccessContext {
  const MemoryAccessContext({
    this.requestingPlayerId,
    this.npcId,
    this.companionId,
    this.channel = MemoryRequestChannel.public,
    this.isGm = false,
  });
  final String? requestingPlayerId, npcId, companionId;
  final MemoryRequestChannel channel;
  final bool isGm;
}

class MemoryPrivacyFilter {
  const MemoryPrivacyFilter();

  List<MemoryEntry> filter(
    Iterable<MemoryEntry> memories,
    MemoryAccessContext access,
  ) => memories.where((memory) => canAccess(memory, access)).toList();

  bool canAccess(MemoryEntry memory, MemoryAccessContext access) {
    if (access.isGm || access.channel == MemoryRequestChannel.gm) return true;
    return switch (memory.visibility) {
      MemoryVisibility.public => true,
      MemoryVisibility.playerPrivate =>
        access.channel == MemoryRequestChannel.playerPrivate &&
            memory.ownerPlayerId == access.requestingPlayerId,
      MemoryVisibility.npcPrivate =>
        access.channel == MemoryRequestChannel.npc &&
            memory.npcId == access.npcId,
      MemoryVisibility.companionPrivate =>
        access.channel == MemoryRequestChannel.companion &&
            memory.npcId == access.companionId,
      MemoryVisibility.gmOnly => false,
    };
  }
}
