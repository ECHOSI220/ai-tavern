import 'dart:io';

import 'package:ai_tavern/models/trpg_game_models.dart';
import 'package:ai_tavern/models/trpg_memory_models.dart';
import 'package:ai_tavern/models/trpg_models.dart';
import 'package:ai_tavern/services/ai/openai_compatible_provider.dart';
import 'package:ai_tavern/repositories/trpg_memory_repository.dart';
import 'package:ai_tavern/repositories/trpg_session_repository.dart';
import 'package:ai_tavern/services/storage_service.dart';
import 'package:ai_tavern/services/trpg/ai_gm_tool_registry.dart';
import 'package:ai_tavern/services/trpg_memory/memory_consistency_checker.dart';
import 'package:ai_tavern/services/trpg_memory/memory_consolidator.dart';
import 'package:ai_tavern/services/trpg_memory/memory_context_builder.dart';
import 'package:ai_tavern/services/trpg_memory/memory_privacy_filter.dart';
import 'package:ai_tavern/services/trpg_memory/memory_ranker.dart';
import 'package:ai_tavern/services/trpg_memory/memory_retriever.dart';
import 'package:ai_tavern/services/trpg_memory/trpg_long_term_memory_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TRPG Phase 6 Memory Core', () {
    test('old save receives deterministic structured seed', () {
      final session = _session().copyWith(
        campaignState: CampaignState(
          quests: [
            QuestState(
              questId: 'q1',
              title: '寻找妹妹',
              status: QuestStatus.active,
              discoveredAt: DateTime.now(),
            ),
          ],
          clues: [
            ClueState(
              clueId: 'key',
              name: '仓库钥匙',
              description: '能打开侧门',
              discovered: true,
            ),
          ],
        ),
      );
      final seeded = const TRPGLongTermMemoryService().process(
        session,
        force: true,
      );
      expect(seeded.memoryState.entries, isNotEmpty);
      expect(
        seeded.memoryState.entries.every(
          (value) => value.canonPriority == CanonPriority.structuredState,
        ),
        isTrue,
      );
    });

    test('private player memory cannot leak to another player or npc', () {
      final secret = _memory(
        'secret',
        visibility: MemoryVisibility.playerPrivate,
        ownerPlayerId: 'alice',
      );
      const filter = MemoryPrivacyFilter();
      expect(
        filter.filter(
          [secret],
          const MemoryAccessContext(
            requestingPlayerId: 'alice',
            channel: MemoryRequestChannel.playerPrivate,
          ),
        ),
        hasLength(1),
      );
      expect(
        filter.filter(
          [secret],
          const MemoryAccessContext(
            requestingPlayerId: 'bob',
            channel: MemoryRequestChannel.public,
          ),
        ),
        isEmpty,
      );
      expect(
        filter.filter(
          [secret],
          const MemoryAccessContext(
            npcId: 'guard',
            channel: MemoryRequestChannel.npc,
          ),
        ),
        isEmpty,
      );
    });

    test('npc only receives its own private belief', () {
      final guard = _memory(
        'guard suspects Alice',
        visibility: MemoryVisibility.npcPrivate,
        npcId: 'guard',
        priority: CanonPriority.npcBelief,
      );
      final boss = _memory(
        'boss is cultist',
        visibility: MemoryVisibility.npcPrivate,
        npcId: 'boss',
      );
      final visible = const MemoryPrivacyFilter().filter(
        [guard, boss],
        const MemoryAccessContext(
          npcId: 'guard',
          channel: MemoryRequestChannel.npc,
        ),
      );
      expect(visible.single.content, contains('guard'));
    });

    test(
      '100+ actions preserve early important memory without prompt overflow',
      () {
        final memories = <MemoryEntry>[
          _memory('第一章玩家承诺帮卡尔找到妹妹', importance: 10, pinned: true),
          for (var i = 0; i < 120; i++)
            _memory(
              '普通行动 $i 坐下又站起',
              importance: 1,
              updatedAt: DateTime.now().add(Duration(minutes: i)),
            ),
        ];
        final ranked = const MemoryRetriever().retrieve(
          memories: memories,
          access: const MemoryAccessContext(),
          context: const MemoryRetrievalContext(
            query: '卡尔 妹妹 承诺',
            entityIds: ['karl'],
            limit: 12,
          ),
        );
        final context = const MemoryContextBuilder().build(
          ranked,
          tokenBudget: 180,
        );
        expect(context, contains('找到妹妹'));
        expect(
          const TokenEstimator().estimate(context),
          lessThanOrEqualTo(180),
        );
        expect(ranked, hasLength(12));
      },
    );

    test('duplicate memories consolidate and retain source event ids', () {
      final now = DateTime.now();
      final first = _memory('玩家帮助卡尔逃离追兵', sourceIds: ['e1']);
      final second = _memory('玩家帮助卡尔逃离追兵', sourceIds: ['e2'], updatedAt: now);
      final result = const MemoryConsolidator().consolidate([first, second]);
      expect(result, hasLength(1));
      expect(result.single.sourceEventIds, containsAll(['e1', 'e2']));
    });

    test('structured dead NPC blocks lower-priority alive claim', () {
      final session = _session().copyWith(
        worldState: const WorldState(
          npcs: [NPCState(npcId: 'father', name: '父亲', alive: false)],
        ),
      );
      final claim = _memory(
        '父亲今天走进房间与大家说话',
        npcId: 'father',
        confidence: MemoryConfidence.uncertain,
        priority: CanonPriority.aiInference,
      );
      final conflicts = const MemoryConsistencyChecker().check(
        session,
        claim,
        const [],
      );
      expect(conflicts.single.reason, contains('已死亡'));
    });

    test('promise resolution survives json round trip', () {
      final promise = PromiseMemory(
        id: 'p1',
        promiser: 'alice',
        promiseTo: 'karl',
        content: '帮你找到妹妹',
        status: PromiseStatus.fulfilled,
        createdAt: DateTime(2026),
        resolvedAt: DateTime(2026, 2),
      );
      final restored = PromiseMemory.fromJson(promise.toJson());
      expect(restored.status, PromiseStatus.fulfilled);
      expect(restored.resolvedAt, isNotNull);
    });

    test('memory state survives session and host snapshot serialization', () {
      final session = _session().copyWith(
        memoryState: MemoryState(
          entries: [_memory('救过莉拉', npcId: 'lyra')],
          companionSummaries: const {'lyra': '非常信任玩家'},
        ),
        gmStateSnapshot: const GMStateSnapshot(
          longTermMemory: ['重大事件'],
          npcMemorySummaries: {'lyra': '信任'},
          worldMemorySummary: '港口仓库已烧毁',
        ),
      );
      final restored = TRPGSession.fromJson(session.toJson());
      expect(restored.memoryState.entries.single.content, '救过莉拉');
      expect(restored.gmStateSnapshot.longTermMemory, ['重大事件']);
      expect(restored.gmStateSnapshot.worldMemorySummary, contains('烧毁'));
    });

    test('relationship tool records the reason, not only the number', () async {
      final base = _session().copyWith(
        players: [
          TRPGPlayer(
            playerId: 'alice',
            displayName: 'Alice',
            joinedAt: DateTime(2026),
          ),
        ],
        immersionState: const TRPGImmersionState(
          npcInstances: [NPCInstanceState(npcId: 'karl')],
        ),
        worldState: const WorldState(
          npcs: [NPCState(npcId: 'karl', name: '卡尔')],
        ),
      );
      final outcome = await AIGMToolRegistry().execute(
        session: base,
        actionId: 'save-karl',
        call: const OpenAIToolCall(
          id: 'relationship-call',
          name: 'modify_npc_relationship',
          arguments: {
            'npcId': 'karl',
            'amount': 20,
            'reason': '玩家在港口战斗中救了卡尔的妹妹',
          },
        ),
      );
      expect(outcome.session.memoryState.relationshipHistory, hasLength(1));
      expect(
        outcome.session.memoryState.relationshipHistory.single.reason,
        contains('卡尔'),
      );
      expect(
        outcome.session.memoryState.entries.single.type,
        MemoryType.relationship,
      );
    });

    test(
      'promise tools retain fulfilled promise as resolved history',
      () async {
        final registry = AIGMToolRegistry();
        final recorded = await registry.execute(
          session: _session(),
          actionId: 'promise-action',
          call: const OpenAIToolCall(
            id: 'promise-call',
            name: 'record_promise',
            arguments: {
              'promiser': 'alice',
              'promiseTo': 'karl',
              'content': '找到失踪的妹妹',
            },
          ),
        );
        final promiseId = recorded.result['promiseId']! as String;
        final resolved = await registry.execute(
          session: recorded.session,
          actionId: 'promise-resolved',
          call: OpenAIToolCall(
            id: 'resolve-call',
            name: 'resolve_promise',
            arguments: {'promiseId': promiseId, 'status': 'fulfilled'},
          ),
        );
        expect(
          resolved.session.memoryState.promises.single.status,
          PromiseStatus.fulfilled,
        );
        expect(resolved.session.memoryState.entries.single.resolved, isTrue);
        expect(resolved.session.memoryState.entries.single.pinned, isTrue);
      },
    );

    test('SQLite store persists indexed long-term memories', () async {
      final directory = await Directory.systemTemp.createTemp(
        'ai_tavern_memory_',
      );
      final storage = StorageService();
      await storage.initialize(
        databasePath: '${directory.path}${Platform.pathSeparator}memory.db',
      );
      try {
        final repository = TRPGMemoryRepository(storage);
        final entry = _memory(
          '仓库钥匙能打开旧仓库侧门',
        ).copyWith(tags: ['钥匙', '仓库'], relatedEntityIds: ['warehouse', 'key']);
        await TRPGSessionRepository(storage).upsert(
          _session().copyWith(memoryState: MemoryState(entries: [entry])),
        );
        expect(await repository.search('session', '仓库'), hasLength(1));
        final entityRows = await storage.database.query(
          'trpg_memory_entities',
          where: 'memory_id = ?',
          whereArgs: [entry.id],
        );
        expect(entityRows, hasLength(2));
      } finally {
        await storage.close();
        await directory.delete(recursive: true);
      }
    });
  });
}

MemoryEntry _memory(
  String content, {
  int importance = 6,
  bool pinned = false,
  MemoryVisibility visibility = MemoryVisibility.public,
  String? ownerPlayerId,
  String? npcId,
  MemoryConfidence confidence = MemoryConfidence.confirmed,
  CanonPriority priority = CanonPriority.confirmedMemory,
  List<String> sourceIds = const ['event'],
  DateTime? updatedAt,
}) {
  final now = updatedAt ?? DateTime.now();
  return MemoryEntry(
    id: '${content.hashCode}_${now.microsecondsSinceEpoch}',
    sessionId: 'session',
    type: MemoryType.event,
    title: content,
    content: content,
    importance: importance,
    pinned: pinned,
    visibility: visibility,
    ownerPlayerId: ownerPlayerId,
    npcId: npcId,
    confidence: confidence,
    canonPriority: priority,
    sourceEventIds: sourceIds,
    relatedEntityIds: [?npcId, 'karl'],
    createdAt: now,
    updatedAt: now,
  );
}

TRPGSession _session() {
  final now = DateTime.now();
  return TRPGSession(
    id: 'session',
    title: '长期团',
    mode: TRPGMode.solo,
    createdAt: now,
    updatedAt: now,
    lastPlayedAt: now,
    campaignId: 'campaign',
  );
}
