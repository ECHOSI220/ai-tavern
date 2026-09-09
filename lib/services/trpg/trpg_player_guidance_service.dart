import '../../models/trpg_game_models.dart';
import '../../models/trpg_gameplay_models.dart';
import '../../models/trpg_models.dart';
import 'action_check_analyzer.dart';

class TrpgPlayerGuidance {
  const TrpgPlayerGuidance({
    required this.situation,
    required this.objective,
    required this.suggestedActions,
  });

  final String situation;
  final String objective;
  final List<String> suggestedActions;
}

class TrpgDiceGuidance {
  const TrpgDiceGuidance({required this.title, required this.detail});

  final String title;
  final String detail;
}

/// Converts authoritative campaign state into player-facing, spoiler-safe
/// guidance. It deliberately does not call an AI model, so the help stays
/// available while offline and never consumes the user's API quota.
class TrpgPlayerGuidanceService {
  const TrpgPlayerGuidanceService({
    this.actionAnalyzer = const ActionCheckAnalyzer(),
  });

  final ActionCheckAnalyzer actionAnalyzer;

  TrpgPlayerGuidance build({required TRPGSession session, String? playerId}) {
    final activeQuest = session.campaignState.quests
        .where((quest) => quest.status == QuestStatus.active)
        .firstOrNull;
    final discoveredQuest = session.campaignState.quests
        .where((quest) => quest.status == QuestStatus.discovered)
        .firstOrNull;
    final quest = activeQuest ?? discoveredQuest;
    final objective = quest?.objectives
        .where((item) => item.current < item.target)
        .firstOrNull;
    final latestNarrative = session.chatHistory.reversed
        .where(
          (message) =>
              message.messageType == TRPGMessageType.gmMessage ||
              message.messageType == TRPGMessageType.npcMessage,
        )
        .map((message) => message.content.trim())
        .where((content) => content.isNotEmpty)
        .firstOrNull;
    final scene = session.worldState.currentScene;
    final situationSource =
        latestNarrative ??
        (scene.description.trim().isNotEmpty
            ? scene.description
            : scene.title.trim().isNotEmpty
            ? '你正在${scene.title}。'
            : session.worldState.location.trim().isNotEmpty
            ? '你正在${session.worldState.location}，故事正等待你的第一个行动。'
            : '开场正在展开，你可以先观察环境、询问人物或查看任务。');
    final objectiveText = quest == null
        ? '暂无明确任务：先了解现场，找到可交谈人物或可调查线索。'
        : '${quest.title}：${objective?.description.trim().isNotEmpty == true
              ? objective!.description
              : quest.progress.trim().isNotEmpty
              ? quest.progress
              : quest.description}';

    final suggestions = <String>[];
    if (session.ruleState.combatActive) {
      suggestions.add('我先确认当前威胁和队友位置，做好防御并寻找反击机会。');
    }
    if (objective != null && objective.description.trim().isNotEmpty) {
      suggestions.add(
        '我先围绕“${_short(objective.description, 26)}”采取最直接的行动，并留意风险。',
      );
    } else if (quest != null) {
      suggestions.add('我查看“${_short(quest.title, 22)}”的已知信息，找出下一个可执行的目标。');
    }

    final visibleNpc = _visibleNpcs(session).firstOrNull;
    if (visibleNpc != null) {
      suggestions.add('我去找${visibleNpc.name}，询问这里正在发生什么，以及我现在该做什么。');
    }

    final knownClue = session.campaignState.clues
        .where((clue) => clue.discovered)
        .firstOrNull;
    if (knownClue != null) {
      suggestions.add('我重新检查“${_short(knownClue.name, 22)}”，看它能否指向新的人物、地点或行动。');
    }
    suggestions.add('我仔细观察当前场景，寻找异常、危险、线索和可互动的对象。');
    suggestions.add('我先回顾任务和已知线索，确认还有哪一步没有完成。');

    final unique = <String>[];
    for (final suggestion in suggestions) {
      if (!unique.contains(suggestion)) unique.add(suggestion);
      if (unique.length == 3) break;
    }
    return TrpgPlayerGuidance(
      situation: _compact(situationSource),
      objective: _compact(objectiveText, maxLength: 150),
      suggestedActions: unique,
    );
  }

  TrpgDiceGuidance dicePreview({
    required TRPGSession session,
    required String action,
    String? playerId,
    bool actionEnabled = true,
  }) {
    if (!actionEnabled) {
      return const TrpgDiceGuidance(
        title: '当前不会触发正式检定',
        detail: '闲聊与普通私信不推进回合；切回“行动”后，直接描述你要做的事。',
      );
    }
    final trimmed = action.trim();
    if (trimmed.isEmpty) {
      return const TrpgDiceGuidance(
        title: '不用自己决定何时投骰',
        detail: '直接描述行动。攻击、调查、潜行、说服等有风险的行动，系统会自动选骰、加修正并把成败写进剧情。',
      );
    }
    final character =
        session.playerCharacters
            .where((value) => value.playerId == playerId)
            .firstOrNull ??
        session.playerCharacters.firstOrNull;
    if (character == null) {
      return const TrpgDiceGuidance(
        title: '尚未选择角色',
        detail: '选择角色后，系统才能按属性和技能计算检定修正。',
      );
    }
    final decision = actionAnalyzer.analyze(
      action: trimmed,
      session: session,
      character: character,
    );
    if (!decision.requiresCheck) {
      return const TrpgDiceGuidance(
        title: '这个行动通常无需投骰',
        detail: '普通移动、对话和无风险操作会直接进入叙事；如果现场出现新危险，系统仍会按规则处理。',
      );
    }
    if (decision.visibility == RollVisibility.gmHidden) {
      return const TrpgDiceGuidance(
        title: '这类行动可能由 GM 自动暗骰',
        detail: '暗骰不显示点数和难度，避免提前泄露是否有陷阱或隐藏线索；结果仍会真实影响剧情。',
      );
    }
    return TrpgDiceGuidance(
      title: '将自动进行${decision.reason}',
      detail:
          '${decision.suggestedDiceFormula} 加属性/技能修正，对比难度 ${decision.difficulty ?? 12}。成功、部分成功或失败会直接决定这个行动的后果。',
    );
  }

  Iterable<NPCState> _visibleNpcs(TRPGSession session) {
    final scene = session.worldState.currentScene;
    final knownIds = session.worldState.knownNpcs.toSet();
    return session.worldState.npcs.where((npc) {
      if (!npc.alive || (!npc.knownToPlayer && !knownIds.contains(npc.npcId))) {
        return false;
      }
      if (scene.npcIds.contains(npc.npcId)) return true;
      return scene.locationId.isNotEmpty && npc.locationId == scene.locationId;
    });
  }

  static String _compact(String value, {int maxLength = 180}) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= maxLength) return normalized;
    return '…${normalized.substring(normalized.length - maxLength)}';
  }

  static String _short(String value, int maxLength) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    return normalized.length <= maxLength
        ? normalized
        : '${normalized.substring(0, maxLength)}…';
  }
}
