import 'package:uuid/uuid.dart';

import '../../models/trpg_living_npc_models.dart';
import '../../models/trpg_models.dart';
import '../../models/trpg_party_models.dart';

class NPCPlanner {
  const NPCPlanner();

  NPCAction plan(
    NPCBrain brain,
    TRPGSession session, {
    required int worldMinute,
    NPCScheduleTrigger trigger = NPCScheduleTrigger.time,
  }) {
    final scheduled = _scheduledAction(brain, worldMinute);
    if (scheduled != null) {
      return NPCAction(
        actionId: 'npc-${brain.npcId}-$worldMinute-schedule',
        npcId: brain.npcId,
        actionType: scheduled.actionType,
        location: scheduled.locationId,
        reason: scheduled.description.isEmpty
            ? '执行每日计划'
            : scheduled.description,
        createdAtMinute: worldMinute,
      );
    }
    if (brain.emotionalState.fear >= 75) {
      return NPCAction(
        actionId: 'npc-${brain.npcId}-$worldMinute-fear',
        npcId: brain.npcId,
        actionType: NPCActionType.run,
        location: _safeLocation(brain, session),
        reason: '恐惧过高，优先寻找安全地点',
        createdAtMinute: worldMinute,
      );
    }
    if ((brain.currentNeeds['fatigue'] ?? 0) >= 75) {
      return NPCAction(
        actionId: 'npc-${brain.npcId}-$worldMinute-rest',
        npcId: brain.npcId,
        actionType: NPCActionType.rest,
        location: brain.currentLocation,
        reason: '疲劳过高，需要休息',
        durationMinutes: 60,
        createdAtMinute: worldMinute,
      );
    }
    final goal =
        brain.goals
            .where((value) => value.status == NPCGoalStatus.active)
            .toList()
          ..sort((a, b) => b.priority.compareTo(a.priority));
    final active = goal.firstOrNull;
    final type = switch (active?.type) {
      NPCGoalType.protect || NPCGoalType.help => NPCActionType.help,
      NPCGoalType.find || NPCGoalType.investigate => NPCActionType.search,
      NPCGoalType.escape => NPCActionType.run,
      NPCGoalType.hide => NPCActionType.hide,
      NPCGoalType.revenge => NPCActionType.attack,
      NPCGoalType.survival || null => NPCActionType.work,
    };
    return NPCAction(
      actionId: 'npc-${brain.npcId}-$worldMinute-${type.name}',
      npcId: brain.npcId,
      actionType: type,
      target: active?.targetId,
      location: active?.targetLocationId ?? brain.currentLocation,
      reason:
          active?.description ??
          (trigger == NPCScheduleTrigger.playerImpact
              ? '回应玩家造成的变化'
              : '维持自己的生活与职责'),
      createdAtMinute: worldMinute,
    );
  }

  NPCScheduleEntry? _scheduledAction(NPCBrain brain, int worldMinute) {
    if (brain.schedule.isEmpty) return null;
    final minute = worldMinute % 1440;
    final lastMinute = brain.lastActionAtMinute < 0
        ? -1
        : brain.lastActionAtMinute % 1440;
    return brain.schedule
        .where(
          (entry) =>
              entry.minuteOfDay <= minute && entry.minuteOfDay > lastMinute,
        )
        .lastOrNull;
  }

  String _safeLocation(NPCBrain brain, TRPGSession session) {
    final safe = brain.beliefs.entries
        .where(
          (entry) =>
              entry.key.startsWith('safe_location_') && entry.value == true,
        )
        .map((entry) => entry.key.substring('safe_location_'.length))
        .firstOrNull;
    return safe ?? brain.currentLocation;
  }
}

class NPCActionValidator {
  const NPCActionValidator();

  NPCAction validate(NPCAction action, NPCBrain brain, TRPGSession session) {
    if (brain.status == NPCLifeStatus.dead) {
      return action.copyWith(blockedReason: 'NPC 已死亡');
    }
    if (brain.status == NPCLifeStatus.left) {
      return action.copyWith(blockedReason: 'NPC 已离开当前世界区域');
    }
    final targetLocation = action.location;
    if (targetLocation != null && targetLocation.isNotEmpty) {
      final locations =
          (session.immersionState.campaignSnapshot['locations'] as List? ??
                  const [])
              .whereType<Map>();
      if (locations.isNotEmpty &&
          !locations.any((value) => value['id'] == targetLocation)) {
        return action.copyWith(blockedReason: '目标地点不存在');
      }
      final isMovement = {
        NPCActionType.move,
        NPCActionType.run,
        NPCActionType.hide,
      }.contains(action.actionType);
      if (isMovement && targetLocation != brain.currentLocation) {
        final knowsRoute =
            brain.beliefs['knows_location_$targetLocation'] == true ||
            brain.beliefs['knows_route_${brain.currentLocation}_$targetLocation'] ==
                true;
        if (!knowsRoute) {
          return action.copyWith(blockedReason: 'NPC 不知道前往目标地点的路线');
        }
        final flags = session.locationFlags[targetLocation] ?? const {};
        if (flags['locked'] == true &&
            !brain.inventory.contains('key:$targetLocation') &&
            !brain.inventory.contains(flags['requiredKeyId'])) {
          return action.copyWith(blockedReason: '目标地点被锁且 NPC 没有钥匙');
        }
      }
    }
    if (brain.emotionalState.fear >= 90 &&
        !{
          NPCActionType.run,
          NPCActionType.hide,
          NPCActionType.rest,
        }.contains(action.actionType)) {
      return action.copyWith(blockedReason: '恐惧使 NPC 无法执行该行动');
    }
    return action.copyWith(validated: true);
  }
}

class NPCRelationshipGraph {
  const NPCRelationshipGraph();

  NPCRelationship? relation(
    LivingNPCState state,
    String sourceNpc,
    String targetCharacter,
  ) => state.relationships
      .where(
        (value) =>
            value.sourceNpc == sourceNpc &&
            value.targetCharacter == targetCharacter,
      )
      .firstOrNull;

  List<NPCRelationship> outgoing(LivingNPCState state, String sourceNpc) =>
      state.relationships
          .where((value) => value.sourceNpc == sourceNpc)
          .toList();
}

class NPCMemoryDecay {
  const NPCMemoryDecay();

  List<NPCMemoryRecord> apply(
    Iterable<NPCMemoryRecord> memories,
    int elapsedMinutes,
  ) {
    final decayed = memories
        .map((value) => value.decay(elapsedMinutes))
        .where((value) => value.permanent || value.currentWeight > 0)
        .toList();
    final byNpc = <String, List<NPCMemoryRecord>>{};
    for (final memory in decayed) {
      (byNpc[memory.npcId] ??= []).add(memory);
    }
    return [
      for (final entries in byNpc.values)
        ...(entries..sort((a, b) {
              final permanent = (b.permanent ? 1 : 0) - (a.permanent ? 1 : 0);
              if (permanent != 0) return permanent;
              return b.currentWeight.compareTo(a.currentWeight);
            }))
            .take(100),
    ];
  }
}

class NPCScheduler {
  const NPCScheduler({
    this.planner = const NPCPlanner(),
    this.validator = const NPCActionValidator(),
  });

  final NPCPlanner planner;
  final NPCActionValidator validator;

  List<NPCAction> dueActions(
    TRPGSession session, {
    required int targetMinute,
    NPCScheduleTrigger trigger = NPCScheduleTrigger.time,
  }) {
    final actions = <NPCAction>[];
    for (final brain in session.livingNpcState.brains.values) {
      if (brain.status == NPCLifeStatus.dead ||
          brain.status == NPCLifeStatus.left) {
        continue;
      }
      final interval = switch (brain.tier) {
        NPCLifeTier.main => 60,
        NPCLifeTier.important => 120,
        NPCLifeTier.normal => 360,
        NPCLifeTier.background => 720,
      };
      final due =
          trigger != NPCScheduleTrigger.time ||
          targetMinute >= brain.nextActionAtMinute ||
          targetMinute - brain.lastActionAtMinute >= interval;
      if (!due) continue;
      final planned = planner.plan(
        brain,
        session,
        worldMinute: targetMinute,
        trigger: trigger,
      );
      actions.add(validator.validate(planned, brain, session));
    }
    return actions;
  }
}

class LivingNPCService {
  const LivingNPCService({
    this.scheduler = const NPCScheduler(),
    this.decay = const NPCMemoryDecay(),
  });

  static const _uuid = Uuid();
  final NPCScheduler scheduler;
  final NPCMemoryDecay decay;

  TRPGSession ensureInitialized(TRPGSession session) {
    final brains = <String, NPCBrain>{...session.livingNpcState.brains};
    final secrets = [...session.livingNpcState.secrets];
    final npcLocations = <String, CharacterLocationState>{
      ...session.npcLocations,
    };
    final profiles =
        (session.immersionState.campaignSnapshot['npcs'] as List? ?? const [])
            .whereType<Map>()
            .map((value) => value.cast<String, Object?>())
            .toList();
    final instanceById = {
      for (final value in session.immersionState.npcInstances)
        value.npcId: value,
    };
    final worldById = {
      for (final value in session.worldState.npcs) value.npcId: value,
    };
    final ids = <String>{
      ...profiles.map(
        (value) => (value['npcId'] ?? value['id'] ?? '').toString(),
      ),
      ...instanceById.keys,
      ...worldById.keys,
    }..remove('');
    for (final npcId in ids) {
      final existingBrain = brains[npcId];
      if (existingBrain != null) {
        npcLocations.putIfAbsent(
          npcId,
          () => CharacterLocationState(
            characterId: npcId,
            sceneId: session.worldState.currentScene.sceneId,
            locationId: existingBrain.currentLocation,
          ),
        );
        continue;
      }
      final profile = profiles
          .where((value) => value['npcId'] == npcId || value['id'] == npcId)
          .firstOrNull;
      final instance = instanceById[npcId];
      final world = worldById[npcId];
      final location =
          instance?.locationId ??
          profile?['locationId']?.toString() ??
          world?.locationId ??
          session.worldState.currentScene.locationId;
      final role = profile?['role']?.toString() ?? 'npc';
      final tier = switch (role) {
        'majorNpc' => NPCLifeTier.main,
        'companion' || 'enemy' => NPCLifeTier.important,
        _ => NPCLifeTier.normal,
      };
      final personalityText = profile?['personality']?.toString() ?? '';
      final metadata = profile?['metadata'] is Map
          ? (profile!['metadata'] as Map).cast<String, Object?>()
          : const <String, Object?>{};
      final knownLocations = <String>{
        location,
        ..._strings(metadata['knownLocationIds']),
      }..remove('');
      final schedule = (metadata['schedule'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (value) => NPCScheduleEntry.fromJson(value.cast<String, Object?>()),
          )
          .toList();
      final goalText = metadata['goal']?.toString().trim();
      final goalType = switch (role) {
        'companion' => NPCGoalType.protect,
        'enemy' => NPCGoalType.revenge,
        _ => NPCGoalType.investigate,
      };
      brains[npcId] = NPCBrain(
        npcId: npcId,
        personality: NPCPersonality(
          traits: personalityText
              .split(RegExp(r'[,，、;；\n]'))
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty)
              .take(8)
              .toList(),
          values: _strings(metadata['values']),
          fears: _strings(metadata['fears']),
          likes: _strings(metadata['likes']),
          dislikes: _strings(metadata['dislikes']),
          temperament: metadata['temperament']?.toString() ?? 'stable',
          morality: metadata['morality']?.toString() ?? 'neutral',
          speechStyle: metadata['speechStyle']?.toString() ?? '',
        ),
        goals: [
          NPCGoal(
            goalId: 'goal-$npcId-primary',
            npcId: npcId,
            type: goalType,
            description: goalText == null || goalText.isEmpty
                ? _defaultGoalDescription(role)
                : goalText,
            priority: tier == NPCLifeTier.main ? 80 : 60,
            targetLocationId: metadata['goalLocationId']?.toString(),
            targetId: metadata['goalTargetId']?.toString(),
          ),
        ],
        beliefs: {
          for (final value in knownLocations) 'knows_location_$value': true,
          for (final value in _strings(metadata['safeLocationIds']))
            'safe_location_$value': true,
        },
        currentNeeds: const {'hunger': 20, 'fatigue': 20, 'safety': 50},
        currentLocation: location,
        emotionalState: const NPCEmotionState(),
        tier: tier,
        status: (instance?.alive ?? world?.alive ?? true)
            ? (role == 'companion'
                  ? NPCLifeStatus.companion
                  : NPCLifeStatus.active)
            : NPCLifeStatus.dead,
        schedule: schedule,
        inventory: instance?.inventory ?? const [],
        nextActionAtMinute: session.livingNpcState.worldMinute,
      );
      npcLocations[npcId] = CharacterLocationState(
        characterId: npcId,
        sceneId: session.worldState.currentScene.sceneId,
        locationId: location,
      );
      final privateNotes = profile?['privateNotes']?.toString().trim() ?? '';
      if (privateNotes.isNotEmpty &&
          !secrets.any((value) => value.ownerNpc == npcId)) {
        secrets.add(
          NPCSecret(
            secretId: 'secret-$npcId-canon',
            ownerNpc: npcId,
            content: privateNotes,
            importance: 80,
            knownBy: [npcId],
          ),
        );
      }
    }
    return session.copyWith(
      npcLocations: npcLocations,
      livingNpcState: session.livingNpcState.copyWith(
        brains: brains,
        secrets: secrets,
      ),
    );
  }

  TRPGSession advanceTime(
    TRPGSession rawSession, {
    required int minutes,
    NPCScheduleTrigger trigger = NPCScheduleTrigger.time,
    String reason = '世界时间推进',
  }) {
    if (minutes < 0 || minutes > 43200) {
      throw ArgumentError.value(minutes, 'minutes', '必须在 0~43200 之间');
    }
    var session = ensureInitialized(rawSession);
    final before = session.livingNpcState.worldMinute;
    final target = before + minutes;
    session = session.copyWith(
      livingNpcState: session.livingNpcState.copyWith(
        worldMinute: target,
        lastTickMinute: target,
        memories: decay.apply(session.livingNpcState.memories, minutes),
      ),
      worldState: session.worldState.copyWith(time: _formatMinute(target)),
    );
    final actions = scheduler.dueActions(
      session,
      targetMinute: target,
      trigger: trigger,
    );
    for (final action in actions) {
      session = _applyScheduledAction(session, action);
    }
    final now = DateTime.now();
    return session.copyWith(
      eventLog: [
        ...session.eventLog,
        TRPGEvent(
          id: _uuid.v4(),
          type: TRPGEventType.npcDecision,
          timestamp: now,
          payload: {
            'source': 'npc_scheduler',
            'trigger': trigger.name,
            'fromMinute': before,
            'toMinute': target,
            'reason': reason,
            'actionCount': actions.length,
          },
        ),
      ],
      updatedAt: now,
      lastPlayedAt: now,
    );
  }

  TRPGSession applyRelationshipEvent(
    TRPGSession rawSession, {
    required String npcId,
    required String targetCharacter,
    required String reason,
    int trust = 0,
    int fear = 0,
    int respect = 0,
    int hate = 0,
    int affection = 0,
    int suspicion = 0,
    int memoryImportance = 40,
  }) {
    var session = ensureInitialized(rawSession);
    if (!session.livingNpcState.brains.containsKey(npcId)) {
      throw StateError('NPC 不存在：$npcId');
    }
    final minute = session.livingNpcState.worldMinute;
    final relations = [...session.livingNpcState.relationships];
    final index = relations.indexWhere(
      (value) =>
          value.sourceNpc == npcId && value.targetCharacter == targetCharacter,
    );
    final base = index < 0
        ? NPCRelationship(sourceNpc: npcId, targetCharacter: targetCharacter)
        : relations[index];
    final updated = base.apply(
      trust: trust,
      fear: fear,
      respect: respect,
      hate: hate,
      affection: affection,
      suspicion: suspicion,
      atMinute: minute,
      reason: reason,
    );
    if (index < 0) {
      relations.add(updated);
    } else {
      relations[index] = updated;
    }
    final eventId = _uuid.v4();
    session = session.copyWith(
      livingNpcState: session.livingNpcState.copyWith(
        relationships: relations,
        memories: [
          ...session.livingNpcState.memories,
          NPCMemoryRecord(
            memoryId: _uuid.v4(),
            npcId: npcId,
            eventId: eventId,
            content: reason,
            importance: memoryImportance.clamp(1, 200),
            emotion: fear > 0
                ? 'fear'
                : hate > 0 || suspicion > 0
                ? 'anger'
                : trust > 0 || affection > 0
                ? 'joy'
                : '',
            timestampMinute: minute,
            kind: memoryImportance >= 100
                ? NPCMemoryKind.longTerm
                : NPCMemoryKind.shortTerm,
            currentWeight: memoryImportance.clamp(1, 200),
            knownBy: [npcId],
          ),
        ],
      ),
      eventLog: [
        ...session.eventLog,
        TRPGEvent(
          id: eventId,
          type: TRPGEventType.npcRelationChange,
          timestamp: DateTime.now(),
          actorId: npcId,
          payload: {
            'npcId': npcId,
            'targetCharacter': targetCharacter,
            'trust': updated.trust,
            'fear': updated.fear,
            'respect': updated.respect,
            'hate': updated.hate,
            'affection': updated.affection,
            'suspicion': updated.suspicion,
            'reason': reason,
          },
        ),
      ],
    );
    return session;
  }

  TRPGSession addMemory(
    TRPGSession rawSession, {
    required String npcId,
    required String content,
    String? eventId,
    int importance = 10,
    String emotion = '',
    NPCMemoryKind kind = NPCMemoryKind.shortTerm,
    List<String>? knownBy,
  }) {
    final session = ensureInitialized(rawSession);
    if (!session.livingNpcState.brains.containsKey(npcId)) {
      throw StateError('NPC 不存在：$npcId');
    }
    final weight = importance.clamp(1, 200);
    return session.copyWith(
      livingNpcState: session.livingNpcState.copyWith(
        memories: [
          ...session.livingNpcState.memories,
          NPCMemoryRecord(
            memoryId: _uuid.v4(),
            npcId: npcId,
            eventId: eventId ?? _uuid.v4(),
            content: content,
            importance: weight,
            emotion: emotion,
            timestampMinute: session.livingNpcState.worldMinute,
            kind: kind,
            currentWeight: weight,
            knownBy: knownBy ?? [npcId],
          ),
        ],
      ),
    );
  }

  TRPGSession addSecret(
    TRPGSession rawSession, {
    required String npcId,
    required String content,
    int importance = 50,
    List<String> knownBy = const [],
  }) {
    final session = ensureInitialized(rawSession);
    return session.copyWith(
      livingNpcState: session.livingNpcState.copyWith(
        secrets: [
          ...session.livingNpcState.secrets,
          NPCSecret(
            secretId: _uuid.v4(),
            ownerNpc: npcId,
            content: content,
            importance: importance.clamp(1, 200),
            knownBy: {npcId, ...knownBy}.toList(),
          ),
        ],
      ),
    );
  }

  TRPGSession revealSecret(
    TRPGSession rawSession, {
    required String secretId,
    required String receiverId,
  }) {
    final session = ensureInitialized(rawSession);
    if (!session.livingNpcState.secrets.any(
      (value) => value.secretId == secretId,
    )) {
      throw StateError('NPC 秘密不存在：$secretId');
    }
    return session.copyWith(
      livingNpcState: session.livingNpcState.copyWith(
        secrets: session.livingNpcState.secrets
            .map(
              (value) => value.secretId == secretId
                  ? value.copyWith(
                      knownBy: {...value.knownBy, receiverId}.toList(),
                    )
                  : value,
            )
            .toList(),
      ),
    );
  }

  TRPGSession setGoal(TRPGSession rawSession, NPCGoal goal) {
    final session = ensureInitialized(rawSession);
    final brain = session.livingNpcState.brains[goal.npcId];
    if (brain == null) throw StateError('NPC 不存在：${goal.npcId}');
    final goals = [...brain.goals];
    final index = goals.indexWhere((value) => value.goalId == goal.goalId);
    if (index < 0) {
      goals.add(goal);
    } else {
      goals[index] = goal;
    }
    return session.copyWith(
      livingNpcState: session.livingNpcState.copyWith(
        brains: {
          ...session.livingNpcState.brains,
          goal.npcId: brain.copyWith(goals: goals),
        },
      ),
    );
  }

  TRPGSession synchronizeNpcLocation(
    TRPGSession rawSession, {
    required String npcId,
    required String locationId,
  }) {
    final session = ensureInitialized(rawSession);
    final brain = session.livingNpcState.brains[npcId];
    if (brain == null) throw StateError('NPC 不存在：$npcId');
    return session.copyWith(
      livingNpcState: session.livingNpcState.copyWith(
        brains: {
          ...session.livingNpcState.brains,
          npcId: brain.copyWith(currentLocation: locationId),
        },
      ),
      npcLocations: {
        ...session.npcLocations,
        npcId: CharacterLocationState(
          characterId: npcId,
          sceneId: session.worldState.currentScene.sceneId,
          locationId: locationId,
          enteredAt: DateTime.now(),
          previousLocationId: brain.currentLocation,
        ),
      },
    );
  }

  TRPGSession killNpc(
    TRPGSession rawSession, {
    required String npcId,
    String? killerId,
    String? locationId,
    String reason = 'NPC 死亡',
  }) {
    var session = ensureInitialized(rawSession);
    final brain = session.livingNpcState.brains[npcId];
    if (brain == null) throw StateError('NPC 不存在：$npcId');
    final eventId = _uuid.v4();
    final minute = session.livingNpcState.worldMinute;
    final deathLocation = locationId ?? brain.currentLocation;
    final brains = <String, NPCBrain>{...session.livingNpcState.brains};
    brains[npcId] = brain.copyWith(
      status: NPCLifeStatus.dead,
      clearPlan: true,
      deathEventId: eventId,
      killerId: killerId,
      deathLocationId: deathLocation,
      deathMinute: minute,
    );
    final memories = [...session.livingNpcState.memories];
    for (final witness in brains.values.where(
      (value) =>
          value.npcId != npcId &&
          value.status != NPCLifeStatus.dead &&
          value.currentLocation == deathLocation,
    )) {
      memories.add(
        NPCMemoryRecord(
          memoryId: _uuid.v4(),
          npcId: witness.npcId,
          eventId: eventId,
          content: '$npcId 在 $deathLocation 死亡：$reason',
          importance: 200,
          emotion: 'trauma',
          timestampMinute: minute,
          kind: NPCMemoryKind.trauma,
          currentWeight: 200,
          knownBy: [witness.npcId],
        ),
      );
      brains[witness.npcId] = witness.copyWith(
        emotionalState: witness.emotionalState.copyWith(
          sadness: witness.emotionalState.sadness + 35,
          stress: witness.emotionalState.stress + 25,
        ),
      );
    }
    session = session.copyWith(
      livingNpcState: session.livingNpcState.copyWith(
        brains: brains,
        memories: memories,
      ),
      worldState: session.worldState.copyWith(
        npcs: session.worldState.npcs
            .map(
              (value) => value.npcId == npcId
                  ? value.copyWith(alive: false, hp: 0)
                  : value,
            )
            .toList(),
      ),
      immersionState: session.immersionState.copyWith(
        npcInstances: session.immersionState.npcInstances
            .map(
              (value) => value.npcId == npcId
                  ? value.copyWith(alive: false, hp: 0)
                  : value,
            )
            .toList(),
      ),
      eventLog: [
        ...session.eventLog,
        TRPGEvent(
          id: eventId,
          type: TRPGEventType.npcDeath,
          timestamp: DateTime.now(),
          actorId: npcId,
          payload: {
            'npcId': npcId,
            'killerId': killerId,
            'locationId': deathLocation,
            'worldMinute': minute,
            'reason': reason,
          },
        ),
      ],
    );
    return session;
  }

  String buildRelevantContext(
    TRPGSession rawSession, {
    required Set<String> locationIds,
    String? requestingPlayerId,
    bool isGm = false,
    int limit = 6,
  }) {
    final session = ensureInitialized(rawSession);
    final state = session.livingNpcState;
    final relevant = state.brains.values
        .where(
          (brain) =>
              locationIds.contains(brain.currentLocation) ||
              brain.status == NPCLifeStatus.companion,
        )
        .take(limit)
        .toList();
    if (relevant.isEmpty) return '';
    final lines = <String>['【附近 Living NPC 状态】'];
    for (final brain in relevant) {
      final goals = brain.goals
          .where((value) => value.status == NPCGoalStatus.active)
          .take(2)
          .map((value) => '${value.description}(${value.priority})')
          .join('；');
      final relation = state.relationships
          .where(
            (value) =>
                value.sourceNpc == brain.npcId &&
                (requestingPlayerId == null ||
                    value.targetCharacter == requestingPlayerId),
          )
          .firstOrNull;
      final memories =
          state.memories
              .where(
                (value) =>
                    value.npcId == brain.npcId &&
                    (isGm || value.knownBy.contains(brain.npcId)),
              )
              .toList()
            ..sort((a, b) => b.currentWeight.compareTo(a.currentWeight));
      lines.add(
        '- ${brain.npcId} @ ${brain.currentLocation}；人格：${brain.personality.traits.join('、')}；'
        '目标：${goals.isEmpty ? '维持当前职责' : goals}；'
        '情绪 fear=${brain.emotionalState.fear}, anger=${brain.emotionalState.anger}, '
        'stress=${brain.emotionalState.stress}'
        '${relation == null ? '' : '；对当前角色 trust=${relation.trust}, suspicion=${relation.suspicion}, fear=${relation.fear}'}'
        '${memories.isEmpty ? '' : '；相关记忆：${memories.take(3).map((value) => value.content).join(' / ')}'}',
      );
    }
    lines.add('NPC有自己的目标与记忆，不会等待玩家触发；只能使用自己经历或被告知的知识，行为必须符合人格、关系、目标与当前情绪。');
    return lines.join('\n');
  }

  String buildNpcContext(
    TRPGSession rawSession, {
    required String npcId,
    String? interactingCharacterId,
  }) {
    final session = ensureInitialized(rawSession);
    final state = session.livingNpcState;
    final brain = state.brains[npcId];
    if (brain == null) return '';
    final relation = state.relationships
        .where(
          (value) =>
              value.sourceNpc == npcId &&
              (interactingCharacterId == null ||
                  value.targetCharacter == interactingCharacterId),
        )
        .firstOrNull;
    final memories =
        state.memories
            .where(
              (value) =>
                  value.npcId == npcId &&
                  (value.knownBy.isEmpty || value.knownBy.contains(npcId)),
            )
            .toList()
          ..sort((a, b) => b.currentWeight.compareTo(a.currentWeight));
    return [
      '【NPC 私有判断上下文：$npcId】',
      '人格：${brain.personality.traits.join('、')}；价值：${brain.personality.values.join('、')}；恐惧：${brain.personality.fears.join('、')}；说话风格：${brain.personality.speechStyle}',
      '目标：${brain.goals.where((value) => value.status == NPCGoalStatus.active).map((value) => value.description).join('；')}',
      '情绪：fear=${brain.emotionalState.fear}, anger=${brain.emotionalState.anger}, joy=${brain.emotionalState.joy}, sadness=${brain.emotionalState.sadness}, stress=${brain.emotionalState.stress}',
      if (relation != null)
        '关系：trust=${relation.trust}, fear=${relation.fear}, respect=${relation.respect}, hate=${relation.hate}, affection=${relation.affection}, suspicion=${relation.suspicion}',
      if (memories.isNotEmpty)
        '自己知道的记忆：${memories.take(8).map((value) => value.content).join(' / ')}',
      '禁止使用其他 NPC 的私人记忆、秘密或未来信息。NPC 的怀疑不等于世界事实。',
    ].join('\n');
  }

  TRPGSession _applyScheduledAction(TRPGSession session, NPCAction action) {
    final brain = session.livingNpcState.brains[action.npcId];
    if (brain == null) return session;
    final brains = <String, NPCBrain>{...session.livingNpcState.brains};
    final now = DateTime.now();
    final interval = switch (brain.tier) {
      NPCLifeTier.main => 60,
      NPCLifeTier.important => 120,
      NPCLifeTier.normal => 360,
      NPCLifeTier.background => 720,
    };
    if (!action.validated) {
      brains[action.npcId] = brain.copyWith(
        clearPlan: true,
        lastActionAtMinute: action.createdAtMinute,
        nextActionAtMinute: action.createdAtMinute + interval,
        emotionalState: brain.emotionalState.copyWith(
          stress: brain.emotionalState.stress + 5,
        ),
      );
      return session.copyWith(
        livingNpcState: session.livingNpcState.copyWith(brains: brains),
        eventLog: [
          ...session.eventLog,
          TRPGEvent(
            id: action.actionId,
            type: TRPGEventType.npcDecision,
            timestamp: now,
            actorId: action.npcId,
            payload: {...action.toJson(), 'executed': false},
          ),
        ],
      );
    }
    final movement = {
      NPCActionType.move,
      NPCActionType.run,
      NPCActionType.hide,
    }.contains(action.actionType);
    final destination = movement && (action.location?.isNotEmpty ?? false)
        ? action.location!
        : brain.currentLocation;
    final activeGoals = brain.goals.map((goal) {
      if (goal.status != NPCGoalStatus.active) return goal;
      final progress = (goal.progress + 10).clamp(0, 100);
      return goal.copyWith(
        progress: progress,
        status: progress >= 100 ? NPCGoalStatus.completed : goal.status,
      );
    }).toList();
    brains[action.npcId] = brain.copyWith(
      currentLocation: destination,
      currentPlan: NPCPlan(
        summary: action.reason,
        targetLocationId: action.location,
        targetId: action.target,
        startedAtMinute: action.createdAtMinute,
        expectedEndMinute: action.createdAtMinute + action.durationMinutes,
      ),
      goals: activeGoals,
      lastActionAtMinute: action.createdAtMinute,
      nextActionAtMinute: action.createdAtMinute + interval,
      status: action.actionType == NPCActionType.hide
          ? NPCLifeStatus.hidden
          : action.actionType == NPCActionType.run
          ? NPCLifeStatus.travelling
          : brain.status == NPCLifeStatus.companion
          ? NPCLifeStatus.companion
          : NPCLifeStatus.active,
      currentNeeds: {
        ...brain.currentNeeds,
        'fatigue': action.actionType == NPCActionType.rest
            ? ((brain.currentNeeds['fatigue'] ?? 0) - 50).clamp(0, 100)
            : ((brain.currentNeeds['fatigue'] ?? 0) + 5).clamp(0, 100),
      },
    );
    var next = session.copyWith(
      livingNpcState: session.livingNpcState.copyWith(
        brains: brains,
        recentActions: [
          ...session.livingNpcState.recentActions,
          action,
        ].reversed.take(50).toList().reversed.toList(),
      ),
      eventLog: [
        ...session.eventLog,
        TRPGEvent(
          id: action.actionId,
          type: action.actionType == NPCActionType.search
              ? TRPGEventType.npcDiscovery
              : TRPGEventType.npcAction,
          timestamp: now,
          actorId: action.npcId,
          payload: {...action.toJson(), 'executed': true},
        ),
      ],
    );
    if (movement) {
      next = next.copyWith(
        worldState: next.worldState.copyWith(
          npcs: next.worldState.npcs
              .map(
                (value) => value.npcId == action.npcId
                    ? value.copyWith(locationId: destination)
                    : value,
              )
              .toList(),
        ),
        immersionState: next.immersionState.copyWith(
          npcInstances: next.immersionState.npcInstances
              .map(
                (value) => value.npcId == action.npcId
                    ? value.copyWith(locationId: destination)
                    : value,
              )
              .toList(),
        ),
        npcLocations: {
          ...next.npcLocations,
          action.npcId: CharacterLocationState(
            characterId: action.npcId,
            sceneId: next.worldState.currentScene.sceneId,
            locationId: destination,
            enteredAt: now,
            previousLocationId: brain.currentLocation,
          ),
        },
      );
    }
    if (action.actionType == NPCActionType.search) {
      next = addMemory(
        next,
        npcId: action.npcId,
        eventId: action.actionId,
        content: '${action.npcId}主动调查：${action.reason}',
        importance: 35,
        kind: NPCMemoryKind.longTerm,
        knownBy: [action.npcId],
      );
    }
    return next;
  }

  static String _defaultGoalDescription(String role) => switch (role) {
    'companion' => '保护同行者并完成共同目标',
    'enemy' => '寻找机会阻止玩家推进',
    'majorNpc' => '调查正在改变世界的重要事件',
    _ => '完成自己的职责并关注异常变化',
  };

  static List<String> _strings(Object? value) => value is List
      ? value.map((item) => item.toString()).toList()
      : value is String && value.trim().isNotEmpty
      ? value
            .split(RegExp(r'[,，、;；\n]'))
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList()
      : const [];

  static String _formatMinute(int value) {
    final day = value ~/ 1440 + 1;
    final minute = value % 1440;
    final hour = minute ~/ 60;
    final remain = minute % 60;
    return '第$day天 ${hour.toString().padLeft(2, '0')}:${remain.toString().padLeft(2, '0')}';
  }
}
