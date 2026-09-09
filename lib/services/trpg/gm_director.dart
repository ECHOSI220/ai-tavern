import '../../models/trpg_models.dart';
import '../../models/trpg_party_models.dart';

enum NarrativePurpose {
  actionResult,
  discovery,
  combat,
  dialogue,
  clue,
  suspense,
  reaction,
  transition,
}

enum NarrativeTransition { cut, smooth, timeSkip, parallel }

enum NarrativeMode { singleGroup, multiGroup, splitScreen, crossCut }

enum NarrativePacing { calm, building, tense, climax, aftermath }

enum NarrativeVisibility { global, group, player, gmOnly }

class NarrativeSegment {
  const NarrativeSegment({
    required this.segmentId,
    required this.targetGroupId,
    required this.locationId,
    required this.eventIds,
    required this.purpose,
    required this.priority,
    this.visibility = NarrativeVisibility.global,
    this.transition = NarrativeTransition.smooth,
  });
  final String segmentId, targetGroupId, locationId;
  final List<String> eventIds;
  final NarrativePurpose purpose;
  final int priority;
  final NarrativeVisibility visibility;
  final NarrativeTransition transition;

  Map<String, Object?> toJson() => {
    'segmentId': segmentId,
    'targetGroupId': targetGroupId,
    'locationId': locationId,
    'eventIds': eventIds,
    'purpose': purpose.name,
    'priority': priority,
    'visibility': visibility.name,
    'transition': transition.name,
  };
}

class NarrativePlan {
  const NarrativePlan({
    required this.planId,
    required this.turnId,
    required this.segments,
    required this.focusGroup,
    required this.mode,
    required this.pacing,
    required this.tensionLevel,
    required this.estimatedLength,
  });
  final String planId, turnId, focusGroup;
  final List<NarrativeSegment> segments;
  final NarrativeMode mode;
  final NarrativePacing pacing;
  final int tensionLevel, estimatedLength;

  Map<String, Object?> toJson() => {
    'planId': planId,
    'turnId': turnId,
    'segments': segments.map((value) => value.toJson()).toList(),
    'focusGroup': focusGroup,
    'mode': mode.name,
    'pacing': pacing.name,
    'tensionLevel': tensionLevel,
    'estimatedLength': estimatedLength,
  };

  String toPrompt() =>
      '''【GM Director 叙事计划】
模式：${mode.name}；节奏：${pacing.name}；紧张度：$tensionLevel/100；长度：$estimatedLength
镜头顺序：${segments.map((s) => '${s.locationId}(${s.purpose.name})').join(' → ')}
焦点小组：$focusGroup
这是叙事调度建议，不是世界状态修改指令。按角色位置分段叙述，不要把不同小组写成同一个“你们”。''';
}

class EventPriorityCalculator {
  const EventPriorityCalculator();
  int score(TRPGEvent event) {
    var value = switch (event.type) {
      TRPGEventType.combatStarted || TRPGEventType.damageApplied => 90,
      TRPGEventType.combatEnded => 75,
      TRPGEventType.npcDeath => 95,
      TRPGEventType.npcAction || TRPGEventType.npcDiscovery => 58,
      TRPGEventType.npcDecision => 48,
      TRPGEventType.npcRelationChange => 55,
      TRPGEventType.factionWar => 92,
      TRPGEventType.factionTerritory || TRPGEventType.factionSuccession => 82,
      TRPGEventType.factionInternalConflict => 75,
      TRPGEventType.factionAction || TRPGEventType.factionRelationship => 60,
      TRPGEventType.holyGrailNoblePhantasm ||
      TRPGEventType.holyGrailEnding => 100,
      TRPGEventType.holyGrailBetrayal => 94,
      TRPGEventType.holyGrailSummoning || TRPGEventType.holyGrailPhase => 84,
      TRPGEventType.holyGrailCommandSpell => 88,
      TRPGEventType.holyGrailAlliance => 68,
      TRPGEventType.holyGrailInvestigation => 62,
      TRPGEventType.worldSimulation => 35,
      TRPGEventType.clueDiscovered => 70,
      TRPGEventType.questUpdate || TRPGEventType.informationRevealed => 65,
      TRPGEventType.playerAction => 40,
      TRPGEventType.npcRelationship => 50,
      TRPGEventType.sceneChange => 45,
      TRPGEventType.diceRoll || TRPGEventType.skillCheck => 55,
      _ => 20,
    };
    if (event.payload['importance'] case final num importance?) {
      value += importance.toInt().clamp(-20, 30);
    }
    return value.clamp(0, 120);
  }
}

class GMDirector {
  const GMDirector({this.priorityCalculator = const EventPriorityCalculator()});
  final EventPriorityCalculator priorityCalculator;

  NarrativePlan plan(TRPGSession session, {String? turnId}) {
    final groups = session.partyGroups
        .where((g) => g.characterIds.isNotEmpty)
        .toList();
    final effectiveGroups = groups.isEmpty
        ? [
            PartyGroup(
              groupId: 'primary',
              sceneId: session.worldState.currentScene.sceneId,
              locationId: session.worldState.currentScene.locationId,
              characterIds: session.playerCharacters.map((c) => c.id).toList(),
            ),
          ]
        : groups;
    final recent = session.eventLog.reversed.take(24).toList();
    final ranked = [...recent]
      ..sort(
        (a, b) =>
            priorityCalculator.score(b).compareTo(priorityCalculator.score(a)),
      );
    final segments = effectiveGroups.asMap().entries.map((entry) {
      final group = entry.value;
      final groupEvents = ranked
          .where((event) => _eventBelongs(event, group))
          .take(4)
          .toList();
      final score = groupEvents.isEmpty
          ? 10
          : priorityCalculator.score(groupEvents.first);
      return NarrativeSegment(
        segmentId: 'segment-${entry.key}',
        targetGroupId: group.groupId,
        locationId: group.locationId,
        eventIds: groupEvents.map((e) => e.id).toList(),
        purpose: _purpose(groupEvents.firstOrNull),
        priority: score,
        transition: entry.key == 0
            ? NarrativeTransition.smooth
            : NarrativeTransition.parallel,
      );
    }).toList()..sort((a, b) => b.priority.compareTo(a.priority));
    final highest = segments.firstOrNull?.priority ?? 10;
    final mode = effectiveGroups.length == 1
        ? NarrativeMode.singleGroup
        : highest >= 85
        ? NarrativeMode.crossCut
        : NarrativeMode.multiGroup;
    final pacing = highest >= 90
        ? NarrativePacing.climax
        : highest >= 65
        ? NarrativePacing.tense
        : highest >= 45
        ? NarrativePacing.building
        : NarrativePacing.calm;
    return NarrativePlan(
      planId: 'plan-${session.id}-${turnId ?? session.eventLog.length}',
      turnId: turnId ?? 'current',
      segments: segments,
      focusGroup: segments.firstOrNull?.targetGroupId ?? 'primary',
      mode: mode,
      pacing: pacing,
      tensionLevel: highest.clamp(0, 100),
      estimatedLength: mode == NarrativeMode.crossCut
          ? 900
          : mode == NarrativeMode.multiGroup
          ? 700
          : 500,
    );
  }

  bool _eventBelongs(TRPGEvent event, PartyGroup group) {
    final groupId = event.payload['groupId']?.toString();
    if (groupId != null && groupId.isNotEmpty) return groupId == group.groupId;
    final characterId = event.payload['characterId']?.toString();
    return characterId == null || group.characterIds.contains(characterId);
  }

  NarrativePurpose _purpose(TRPGEvent? event) => switch (event?.type) {
    TRPGEventType.clueDiscovered => NarrativePurpose.clue,
    TRPGEventType.combatStarted ||
    TRPGEventType.damageApplied => NarrativePurpose.combat,
    TRPGEventType.npcRelationship => NarrativePurpose.dialogue,
    TRPGEventType.npcRelationChange => NarrativePurpose.reaction,
    TRPGEventType.npcAction => NarrativePurpose.actionResult,
    TRPGEventType.npcDecision => NarrativePurpose.reaction,
    TRPGEventType.npcDiscovery => NarrativePurpose.discovery,
    TRPGEventType.npcDeath => NarrativePurpose.suspense,
    TRPGEventType.factionWar => NarrativePurpose.combat,
    TRPGEventType.factionTerritory ||
    TRPGEventType.factionSuccession ||
    TRPGEventType.factionInternalConflict => NarrativePurpose.suspense,
    TRPGEventType.factionAction ||
    TRPGEventType.factionRelationship => NarrativePurpose.reaction,
    TRPGEventType.holyGrailNoblePhantasm => NarrativePurpose.combat,
    TRPGEventType.holyGrailBetrayal => NarrativePurpose.suspense,
    TRPGEventType.holyGrailSummoning => NarrativePurpose.discovery,
    TRPGEventType.holyGrailInvestigation => NarrativePurpose.clue,
    TRPGEventType.holyGrailCommandSpell => NarrativePurpose.actionResult,
    TRPGEventType.holyGrailAlliance => NarrativePurpose.dialogue,
    TRPGEventType.holyGrailPhase ||
    TRPGEventType.holyGrailEnding => NarrativePurpose.transition,
    TRPGEventType.informationRevealed => NarrativePurpose.discovery,
    TRPGEventType.sceneChange => NarrativePurpose.transition,
    _ => NarrativePurpose.actionResult,
  };
}
