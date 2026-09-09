// ignore_for_file: use_null_aware_elements

import 'package:uuid/uuid.dart';

import '../../models/trpg_game_models.dart';
import '../../models/trpg_models.dart';
import 'trpg_rule_engine.dart';

class TRPGStateService {
  static const _uuid = Uuid();

  TRPGSession updateQuest(
    TRPGSession session, {
    required String questId,
    required String operation,
    String? title,
    String? description,
    String? progress,
    String? objectiveId,
    int? objectiveProgress,
    String? actionId,
  }) {
    const operations = {'discover', 'activate', 'progress', 'complete', 'fail'};
    if (!operations.contains(operation)) {
      throw TRPGRuleException('无效任务操作：$operation');
    }
    final now = DateTime.now();
    final quests = [...session.campaignState.quests];
    var index = quests.indexWhere((quest) => quest.questId == questId);
    if (index < 0) {
      if (operation != 'discover' && operation != 'activate') {
        throw TRPGRuleException('任务不存在：$questId');
      }
      quests.add(
        QuestState(
          questId: questId,
          title: title?.trim().isNotEmpty == true ? title!.trim() : questId,
          description: description ?? '',
          status: operation == 'activate'
              ? QuestStatus.active
              : QuestStatus.discovered,
          discoveredAt: now,
        ),
      );
      index = quests.length - 1;
    } else {
      final old = quests[index];
      var objectives = old.objectives;
      if (objectiveId != null && objectiveProgress != null) {
        objectives = old.objectives
            .map(
              (objective) => objective.id == objectiveId
                  ? objective.copyWith(
                      current: objectiveProgress.clamp(0, objective.target),
                    )
                  : objective,
            )
            .toList();
      }
      final status = switch (operation) {
        'activate' || 'progress' => QuestStatus.active,
        'complete' => QuestStatus.completed,
        'fail' => QuestStatus.failed,
        _ => old.status,
      };
      quests[index] = old.copyWith(
        status: status,
        progress: progress ?? old.progress,
        objectives: objectives,
        completedAt: status == QuestStatus.completed ? now : null,
      );
    }
    final active = quests
        .where((quest) => quest.status == QuestStatus.active)
        .map((quest) => quest.questId)
        .toList();
    final completed = quests
        .where((quest) => quest.status == QuestStatus.completed)
        .map((quest) => quest.questId)
        .toList();
    final failed = quests
        .where((quest) => quest.status == QuestStatus.failed)
        .map((quest) => quest.questId)
        .toList();
    return session.copyWith(
      campaignState: session.campaignState.copyWith(
        quests: quests,
        activeQuests: active,
        completedQuests: completed,
        failedQuests: failed,
      ),
      eventLog: [
        ...session.eventLog,
        TRPGEvent(
          id: _uuid.v4(),
          type: TRPGEventType.questUpdate,
          timestamp: now,
          payload: {
            'questId': questId,
            'operation': operation,
            if (progress != null) 'progress': progress,
            if (actionId != null) 'actionId': actionId,
          },
        ),
      ],
      updatedAt: now,
    );
  }

  TRPGSession changeScene(
    TRPGSession session, {
    required SceneState scene,
    required String reason,
    String? time,
    String? weather,
    String? actionId,
  }) {
    if (scene.sceneId.trim().isEmpty || scene.locationId.trim().isEmpty) {
      throw const TRPGRuleException('场景和地点 id 不能为空');
    }
    final now = DateTime.now();
    final discovered = {
      ...session.campaignState.discoveredLocations,
      scene.locationId,
    }.toList();
    return session.copyWith(
      currentScene: scene.description,
      campaignState: session.campaignState.copyWith(
        currentLocationId: scene.locationId,
        discoveredLocations: discovered,
      ),
      worldState: session.worldState.copyWith(
        currentScene: scene,
        location: scene.title,
        time: time,
        weather: weather,
      ),
      eventLog: [
        ...session.eventLog,
        TRPGEvent(
          id: _uuid.v4(),
          type: TRPGEventType.sceneChange,
          timestamp: now,
          payload: {
            'scene': scene.toJson(),
            'reason': reason,
            if (actionId != null) 'actionId': actionId,
          },
        ),
      ],
      updatedAt: now,
    );
  }

  TRPGSession updateWorldFlag(
    TRPGSession session, {
    required String flag,
    required bool value,
    required String reason,
    String? actionId,
  }) {
    if (!RegExp(r'^[a-zA-Z0-9_\-]{1,80}$').hasMatch(flag)) {
      throw const TRPGRuleException('世界标记名称无效');
    }
    final now = DateTime.now();
    return session.copyWith(
      worldState: session.worldState.copyWith(
        worldFlags: {...session.worldState.worldFlags, flag: value},
      ),
      eventLog: [
        ...session.eventLog,
        TRPGEvent(
          id: _uuid.v4(),
          type: TRPGEventType.system,
          timestamp: now,
          visibleToAi: true,
          payload: {
            'worldFlag': flag,
            'value': value,
            'reason': reason,
            if (actionId != null) 'actionId': actionId,
          },
        ),
      ],
      updatedAt: now,
    );
  }

  TRPGSession discoverClue(
    TRPGSession session, {
    required String clueId,
    required String name,
    required String description,
    required String characterId,
    String? actionId,
  }) {
    final now = DateTime.now();
    final clues = [...session.campaignState.clues];
    final index = clues.indexWhere((clue) => clue.clueId == clueId);
    final clue = ClueState(
      clueId: clueId,
      name: name,
      description: description,
      discovered: true,
      discoveredBy: characterId,
      timestamp: now,
    );
    if (index < 0) {
      clues.add(clue);
    } else if (!clues[index].discovered) {
      clues[index] = clues[index].copyWith(
        discovered: true,
        discoveredBy: characterId,
        timestamp: now,
      );
    }
    return session.copyWith(
      campaignState: session.campaignState.copyWith(clues: clues),
      eventLog: [
        ...session.eventLog,
        TRPGEvent(
          id: _uuid.v4(),
          type: TRPGEventType.clueDiscovered,
          timestamp: now,
          actorId: characterId,
          payload: {
            'clue': clue.toJson(),
            if (actionId != null) 'actionId': actionId,
          },
        ),
      ],
      updatedAt: now,
    );
  }

  TRPGSession modifyNpcRelationship(
    TRPGSession session, {
    required String npcId,
    required int amount,
    required String reason,
    String? actionId,
  }) {
    final npcs = [...session.worldState.npcs];
    final index = npcs.indexWhere((npc) => npc.npcId == npcId);
    if (index < 0) throw TRPGRuleException('NPC 不存在：$npcId');
    final before = npcs[index].relationship;
    npcs[index] = npcs[index].copyWith(
      relationship: (before + amount).clamp(-100, 100),
    );
    final now = DateTime.now();
    return session.copyWith(
      worldState: session.worldState.copyWith(npcs: npcs),
      eventLog: [
        ...session.eventLog,
        TRPGEvent(
          id: _uuid.v4(),
          type: TRPGEventType.npcRelationship,
          timestamp: now,
          actorId: npcId,
          payload: {
            'before': before,
            'after': npcs[index].relationship,
            'reason': reason,
            if (actionId != null) 'actionId': actionId,
          },
        ),
      ],
      updatedAt: now,
    );
  }
}
