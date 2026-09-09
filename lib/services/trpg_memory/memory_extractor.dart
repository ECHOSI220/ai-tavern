import 'package:uuid/uuid.dart';

import '../../models/trpg_memory_models.dart';
import '../../models/trpg_models.dart';

class MemoryExtractor {
  const MemoryExtractor({this.minimumImportance = 4});
  static const _uuid = Uuid();
  final int minimumImportance;

  List<MemoryEntry> extract(TRPGSession session, Iterable<TRPGEvent> events) {
    final entries = <MemoryEntry>[];
    for (final event in events) {
      final candidate = _fromEvent(session, event);
      if (candidate != null && candidate.importance >= minimumImportance) {
        entries.add(candidate);
      }
    }
    return entries;
  }

  MemoryEntry? _fromEvent(TRPGSession session, TRPGEvent event) {
    final payload = event.payload;
    final now = event.timestamp;
    final data = switch (event.type) {
      TRPGEventType.questUpdate => (MemoryType.questMemory, 7, '任务发生变化'),
      TRPGEventType.clueDiscovered => (MemoryType.clue, 7, '发现重要线索'),
      TRPGEventType.sceneChange => (MemoryType.locationMemory, 4, '抵达新场景'),
      TRPGEventType.itemGain => (MemoryType.itemMemory, 5, '获得物品'),
      TRPGEventType.combatStarted => (MemoryType.combatMemory, 5, '战斗开始'),
      TRPGEventType.combatEnded => (MemoryType.combatMemory, 6, '战斗结束'),
      TRPGEventType.damageApplied => (MemoryType.combatMemory, 4, '战斗造成伤害'),
      TRPGEventType.npcRelationship => (MemoryType.relationship, 7, '人物关系变化'),
      TRPGEventType.secretAction => (MemoryType.privateMemory, 6, '秘密行动'),
      TRPGEventType.privateMessage => (MemoryType.privateMemory, 4, '私人交流'),
      _ => null,
    };
    if (data == null) return null;
    final npcId =
        payload['npcId']?.toString() ?? payload['targetId']?.toString();
    final locationId =
        payload['locationId']?.toString() ??
        (event.type == TRPGEventType.sceneChange
            ? session.worldState.currentScene.locationId
            : null);
    final questId = payload['questId']?.toString();
    final visibility =
        event.type == TRPGEventType.secretAction ||
            event.type == TRPGEventType.privateMessage
        ? MemoryVisibility.playerPrivate
        : MemoryVisibility.public;
    final content = _describe(event);
    return MemoryEntry(
      id: _uuid.v4(),
      sessionId: session.id,
      type: data.$1,
      title: data.$3,
      content: content,
      summary: content,
      importance: data.$2,
      confidence: MemoryConfidence.confirmed,
      createdAt: now,
      updatedAt: now,
      sourceEventIds: [event.id],
      relatedEntityIds: [?event.actorId, ?npcId, ?locationId, ?questId],
      tags: [event.type.name],
      visibility: visibility,
      ownerPlayerId: visibility == MemoryVisibility.playerPrivate
          ? event.actorId
          : null,
      npcId: npcId,
      locationId: locationId,
      questId: questId,
      canonPriority: CanonPriority.confirmedEvent,
      metadata: payload,
    );
  }

  String _describe(TRPGEvent event) {
    final payload = event.payload;
    final reason = payload['reason']?.toString();
    final name =
        payload['name'] ??
        payload['title'] ??
        payload['itemId'] ??
        payload['questId'];
    return [
      if (name != null) name.toString(),
      if (reason != null && reason.isNotEmpty) reason,
      if (name == null && (reason == null || reason.isEmpty))
        payload.toString(),
    ].join('：');
  }
}
