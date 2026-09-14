import '../../models/character.dart';
import '../../models/character_social.dart';
import '../../models/trpg_memory_models.dart';
import '../../models/trpg_models.dart';
import '../trpg_memory/memory_privacy_filter.dart';

/// No campaign canon, GM notes, private channel or arbitrary metadata is copied.
class SocialImportService {
  static List<Character> knownNpcs(TRPGSession session) => [
    for (final npc in session.worldState.npcs.where((n) => n.knownToPlayer))
      Character(
        id: 'trpg:${session.id}:${npc.npcId}',
        name: npc.name,
        description: '在「${session.title}」中相识的角色。',
      ),
  ];
  static bool shareable(
    MemoryEntry memory,
    String actorId,
    List<KnowledgeRelation> knowledge,
  ) {
    if (memory.confidence != MemoryConfidence.confirmed ||
        !const MemoryPrivacyFilter().canAccess(
          memory,
          const MemoryAccessContext(),
        ) ||
        const [
          MemoryType.secret,
          MemoryType.gmPlot,
          MemoryType.foreshadowing,
          MemoryType.privateMemory,
        ].contains(memory.type)) {
      return false;
    }
    return knowledge.any(
      (k) =>
          k.active &&
          k.subjectId == actorId &&
          (k.sourceMemoryId == memory.id || k.objectId == memory.id) &&
          k.confidence == MemoryConfidence.confirmed &&
          [
            KnowledgeRelationType.knows,
            KnowledgeRelationType.witnessed,
          ].contains(k.type),
    );
  }

  static SocialRecord sharedMemory(SocialRecord contact, MemoryEntry memory) =>
      SocialRecord.create(
        'memory',
        {
          'content': memory.content,
          'scope': MemoryScope.globalCharacter.name,
          'sourceScope': MemoryScope.trpg.name,
          'sourceMemoryId': memory.id,
          'sourceSessionId': memory.sessionId,
          'importance': memory.importance,
          'knownBy': ['user', contact.characterId],
          'decayPolicy': 'never',
          'userApproved': true,
        },
        id: 'shared:${contact.id}:${memory.id}',
        worldId: contact.worldId,
        characterId: contact.characterId,
      );
}
