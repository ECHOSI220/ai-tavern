import 'dart:convert';
import 'dart:math';

import 'package:uuid/uuid.dart';

import '../../models/api_profile.dart';
import '../../models/trpg_dice_models.dart';
import '../../models/trpg_game_models.dart';
import '../../models/trpg_models.dart';
import '../ai_service.dart';
import 'ai_gm_output_guard.dart';
import 'ai_gm_prompt_builder.dart';
import 'ai_gm_tool_registry.dart';
import 'trpg_memory_service.dart';
import 'trpg_check_pipeline.dart';
import '../trpg_memory/trpg_long_term_memory_service.dart';

abstract interface class GMProvider {
  Future<TRPGSession> initializeSession({
    required TRPGSession session,
    required ApiProfile profile,
    required String apiKey,
    ToolSaveCallback? onToolMutation,
  });

  Future<TRPGSession> handlePlayerAction({
    required TRPGSession session,
    required String action,
    required ApiProfile profile,
    required String apiKey,
    String? actionId,
    ToolSaveCallback? onToolMutation,
  });

  Future<TRPGSession> continueNarration({
    required TRPGSession session,
    required ApiProfile profile,
    required String apiKey,
    ToolSaveCallback? onToolMutation,
  });

  Future<GMStateSnapshot> summarizeSession(TRPGSession session);
  Future<void> restoreSession(TRPGSession session);
  void dispose();
}

/// Lightweight solo channels that mirror multiplayer communication without
/// pretending that extra human clients exist.
enum SoloAIInteractionType { tableChat, secretAction, privateMessage }

class AIGMService implements GMProvider {
  AIGMService(
    this._aiService, {
    AIGMToolRegistry? toolRegistry,
    AIGMPromptBuilder promptBuilder = const AIGMPromptBuilder(),
    TRPGMemoryService memoryService = const TRPGMemoryService(),
    this._longTermMemory = const TRPGLongTermMemoryService(),
    TRPGCheckPipeline? checkPipeline,
    Future<ToolChatResponse> Function({
      required ApiProfile profile,
      required String apiKey,
      required List<Map<String, Object?>> messages,
      required List<Map<String, Object?>> tools,
    })?
    toolCompletion,
    this.maxToolRounds = 8,
    int memoryTokenBudget = 3000,
  }) : _tools = toolRegistry ?? AIGMToolRegistry(),
       _prompts = promptBuilder,
       _memory = memoryService,
       _checks = checkPipeline ?? TRPGCheckPipeline(),
       _memoryTokenBudget = memoryTokenBudget.clamp(500, 12000),
       _toolCompletion = toolCompletion ?? _aiService.completeWithTools;

  final AiService _aiService;
  final AIGMToolRegistry _tools;
  final AIGMPromptBuilder _prompts;
  final TRPGMemoryService _memory;
  final TRPGLongTermMemoryService _longTermMemory;
  final TRPGCheckPipeline _checks;
  final Future<ToolChatResponse> Function({
    required ApiProfile profile,
    required String apiKey,
    required List<Map<String, Object?>> messages,
    required List<Map<String, Object?>> tools,
  })
  _toolCompletion;
  final int maxToolRounds;
  int _memoryTokenBudget;
  int get memoryTokenBudget => _memoryTokenBudget;
  set memoryTokenBudget(int value) =>
      _memoryTokenBudget = value.clamp(500, 12000);
  static const _uuid = Uuid();
  static const double soloPrivateEventChance = .30;
  final Random _random = Random();

  @override
  Future<TRPGSession> initializeSession({
    required TRPGSession session,
    required ApiProfile profile,
    required String apiKey,
    ToolSaveCallback? onToolMutation,
  }) => _runToolLoop(
    session: session,
    action: '请根据当前剧本和角色生成沉浸式开场。简单无风险的开场不要检定。',
    actionId: 'opening-${session.id}',
    profile: profile,
    apiKey: apiKey,
    onToolMutation: onToolMutation,
  );

  @override
  Future<TRPGSession> handlePlayerAction({
    required TRPGSession session,
    required String action,
    required ApiProfile profile,
    required String apiKey,
    String? actionId,
    ToolSaveCallback? onToolMutation,
  }) async {
    final resolvedActionId = actionId ?? _uuid.v4();
    final now = DateTime.now();
    final actionMessage = TRPGMessage(
      id: resolvedActionId,
      messageType: TRPGMessageType.playerMessage,
      content: action,
      playerId: session.players.firstOrNull?.playerId,
      createdAt: now,
    );
    final actionEvent = TRPGEvent(
      id: _uuid.v4(),
      type: TRPGEventType.playerAction,
      timestamp: now,
      actorId: session.players.firstOrNull?.playerId,
      payload: {'action': action, 'actionId': resolvedActionId},
    );
    final snapshotJson = session.toJson()
      ..['actionSnapshots'] = const []
      ..['toolExecutions'] = const [];
    final snapshot = TRPGActionSnapshot(
      actionId: resolvedActionId,
      createdAt: now,
      sessionJson: snapshotJson,
    );
    final alreadyRecorded = session.chatHistory.any(
      (message) => message.id == resolvedActionId,
    );
    final prepared = alreadyRecorded
        ? session
        : session.copyWith(
            chatHistory: [...session.chatHistory, actionMessage],
            eventLog: [...session.eventLog, actionEvent],
            actionSnapshots: [
              ...session.actionSnapshots.reversed.take(9).toList().reversed,
              snapshot,
            ],
            updatedAt: now,
            lastPlayedAt: now,
          );
    return _runToolLoop(
      session: prepared,
      action: action,
      actionId: resolvedActionId,
      profile: profile,
      apiKey: apiKey,
      onToolMutation: onToolMutation,
    );
  }

  /// Used when the UI persisted the player action before the API request.
  Future<TRPGSession> respondToRecordedAction({
    required TRPGSession session,
    required String action,
    required ApiProfile profile,
    required String apiKey,
    String? actionId,
    ToolSaveCallback? onToolMutation,
  }) => _runToolLoop(
    session: session,
    action: action,
    actionId: actionId ?? session.chatHistory.last.id,
    profile: profile,
    apiKey: apiKey,
    onToolMutation: onToolMutation,
  );

  /// Handles solo table chat and private channels. These channels deliberately
  /// run without rule tools: casual chat cannot consume a turn, and private
  /// text cannot accidentally leak a hidden dice/tool result into the public
  /// timeline. A later public action can still react to information the player
  /// chooses to reveal.
  Future<TRPGSession> handleSoloInteraction({
    required TRPGSession session,
    required String content,
    required SoloAIInteractionType type,
    required ApiProfile profile,
    required String apiKey,
    String? targetPlayerId,
    String? targetName,
    String? interactionId,
  }) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return session;
    final now = DateTime.now();
    final id = interactionId ?? _uuid.v4();
    final humanPlayer = session.players
        .where((player) => !player.isAiControlled)
        .firstOrNull;
    final humanPlayerId =
        humanPlayer?.playerId ?? session.players.firstOrNull?.playerId;
    if (humanPlayerId == null) throw StateError('单人跑团缺少玩家身份');

    final isPublicChat = type == SoloAIInteractionType.tableChat;
    final isSecretAction = type == SoloAIInteractionType.secretAction;
    final recipientIds = targetPlayerId == null
        ? <String>[humanPlayerId]
        : <String>[humanPlayerId, targetPlayerId];
    var prepared = isPublicChat
        ? session.copyWith(
            chatHistory: [
              ...session.chatHistory,
              TRPGMessage(
                id: id,
                messageType: TRPGMessageType.playerMessage,
                content: trimmed,
                playerId: humanPlayerId,
                createdAt: now,
              ),
            ],
            updatedAt: now,
            lastPlayedAt: now,
          )
        : session.copyWith(
            immersionState: session.immersionState.copyWith(
              privateMessages: [
                ...session.immersionState.privateMessages,
                TRPGPrivateMessage(
                  id: id,
                  senderId: humanPlayerId,
                  recipientIds: recipientIds,
                  content: trimmed,
                  createdAt: now,
                  toGm: targetPlayerId == null,
                ),
              ],
              timeline: isSecretAction
                  ? [
                      ...session.immersionState.timeline,
                      SessionTimelineEntry(
                        id: id,
                        title: '秘密行动',
                        detail: trimmed,
                        createdAt: now,
                        visibility: InformationVisibility.playerPrivate,
                        ownerPlayerIds: [humanPlayerId],
                      ),
                    ]
                  : session.immersionState.timeline,
            ),
            eventLog: [
              ...session.eventLog,
              TRPGEvent(
                id: _uuid.v4(),
                type: isSecretAction
                    ? TRPGEventType.secretAction
                    : TRPGEventType.privateMessage,
                timestamp: now,
                actorId: humanPlayerId,
                payload: {
                  'interactionId': id,
                  'visibility': DiceVisibility.playerPrivate.name,
                  'visibilityPlayerIds': [humanPlayerId],
                },
                visibleToAi: false,
              ),
            ],
            updatedAt: now,
            lastPlayedAt: now,
          );

    final promptAction = switch (type) {
      SoloAIInteractionType.tableChat => '【桌边闲聊】$trimmed',
      SoloAIInteractionType.secretAction => '【仅 GM 可见的秘密行动】$trimmed',
      SoloAIInteractionType.privateMessage =>
        '【发给${targetName ?? 'GM'}的私信】$trimmed',
    };
    final messages = _prompts.build(
      session: prepared,
      action: promptAction,
      actingPlayerId: humanPlayerId,
      privateInteraction: !isPublicChat,
      memoryTokenBudget: _memoryTokenBudget,
    );
    final channelRule = switch (type) {
      SoloAIInteractionType.tableChat =>
        '''
【本轮是桌边闲聊】
不要调用工具，不推进时间、场景、任务、战斗或回合，也不要宣布任何数值变化。
GM 可以简短回应；AI 玩家应按各自人格自然聊天。继续严格使用 [GM] 与 [AI玩家：角色名] 分段。''',
      SoloAIInteractionType.secretAction =>
        '''
【本轮是秘密行动】
内容与回复仅当前玩家和 GM 可见。不要在回复中假装把秘密公布到公共频道，不要调用工具或写入公开世界结果。
可以由 GM 描述当前玩家私下能感知到的即时反馈；如 AI 队友确实参与，必须用 [AI玩家：角色名] 独立分段。''',
      SoloAIInteractionType.privateMessage =>
        '''
【本轮是私密频道】
你正在扮演“${targetName ?? 'GM'}”回复当前玩家。内容只在双方与 GM 的私密记录中出现。
不要推进公共回合，不要调用工具，不要替其他角色发言。${targetPlayerId == null ? '使用 [GM] 分段。' : '只使用 [AI玩家：${targetName ?? '队友'}] 分段。'}''',
    };
    messages[0] = {
      ...messages[0],
      'content': '${messages[0]['content']}\n\n$channelRule',
    };
    if (!isPublicChat) {
      final privateHistory = prepared.immersionState.privateMessages
          .where((message) {
            final involvesHuman =
                message.senderId == humanPlayerId ||
                message.recipientIds.contains(humanPlayerId);
            if (!involvesHuman) return false;
            if (targetPlayerId == null) {
              return message.toGm || message.senderId == 'gm';
            }
            return message.senderId == targetPlayerId ||
                message.recipientIds.contains(targetPlayerId);
          })
          .toList()
          .reversed
          .take(12)
          .toList()
          .reversed;
      messages.add({
        'role': 'user',
        'content':
            '当前私密频道最近记录：\n${privateHistory.map((message) => '${message.senderId}: ${message.content}').join('\n')}\n\n现在直接回复最新内容。',
      });
    }

    final response = await _toolCompletion(
      profile: profile.copyWith(stream: false),
      apiKey: apiKey,
      messages: messages,
      tools: const [],
    );
    final reply = await _ensureDisplayableChineseNarration(
      response: response,
      messages: messages,
      action: promptAction,
      profile: profile,
      apiKey: apiKey,
    );
    if (isPublicChat) return _appendTableChat(prepared, reply);
    return _appendPrivateReply(
      prepared,
      reply,
      humanPlayerId: humanPlayerId,
      targetPlayerId: targetPlayerId,
      targetName: targetName,
    );
  }

  /// Occasionally lets an AI companion or a known world NPC initiate a
  /// private conversation after a real solo action. The probability gate runs
  /// before the API call, so most turns add no latency or token usage.
  Future<TRPGSession> maybeTriggerSoloPrivateMessage({
    required TRPGSession session,
    required ApiProfile profile,
    required String apiKey,
    required String sourceActionId,
    double? triggerRoll,
    int? senderIndex,
    int? eventKindIndex,
  }) async {
    if (session.eventLog.any(
      (event) =>
          event.type == TRPGEventType.privateMessage &&
          event.payload['randomIncoming'] == true &&
          event.payload['sourceActionId'] == sourceActionId,
    )) {
      return session;
    }
    final roll = triggerRoll ?? _random.nextDouble();
    if (roll >= soloPrivateEventChance) return session;

    final human = session.players
        .where((player) => !player.isAiControlled)
        .firstOrNull;
    if (human == null) return session;
    final candidates = <({String id, String name, String context})>[];
    for (final player in session.players.where(
      (player) => player.isAiControlled,
    )) {
      final character = session.playerCharacters
          .where((item) => item.playerId == player.playerId)
          .firstOrNull;
      candidates.add((
        id: player.playerId,
        name: character?.name ?? player.displayName,
        context:
            'AI 同行者；性格：${character?.personality ?? '按当前剧情表现'}；背景：${character?.background ?? '未知'}',
      ));
    }
    for (final npc in session.worldState.npcs.where(
      (npc) =>
          npc.alive &&
          (npc.knownToPlayer ||
              session.worldState.knownNpcs.contains(npc.npcId) ||
              session.worldState.knownNpcs.contains(npc.name)),
    )) {
      if (candidates.any((candidate) => candidate.id == npc.npcId)) continue;
      candidates.add((
        id: npc.npcId,
        name: npc.name,
        context:
            '世界 NPC；态度：${npc.disposition}；关系值：${npc.relationship}；备注：${npc.notes}',
      ));
    }
    if (candidates.isEmpty) return session;

    final picked =
        candidates[(senderIndex ?? _random.nextInt(candidates.length)) %
            candidates.length];
    const eventKinds = <String>[
      '自然聊天：分享感受、关心玩家、抱怨或闲谈，不强行推进任务。',
      '情报提醒：私下告诉玩家一条与当前地点或事件有关、但不过度剧透的线索。',
      '私人委托：提出一个可拒绝的小任务、请求或交易，说明动机和大致目标。',
      '紧急求助：因为正在发生的事件向玩家求助或发出警告，但不要凭空制造世界毁灭级危机。',
    ];
    final selectedKindIndex =
        (eventKindIndex ?? _random.nextInt(eventKinds.length)) %
        eventKinds.length;
    final kind = eventKinds[selectedKindIndex];
    final messages = _prompts.build(
      session: session,
      action: '【随机私人来信】${picked.name}主动联系当前玩家。',
      actingPlayerId: human.playerId,
      privateInteraction: true,
      memoryTokenBudget: _memoryTokenBudget,
    );
    messages[0] = {
      ...messages[0],
      'content':
          '''${messages[0]['content']}

【随机私信事件】
发信人：${picked.name}
身份资料：${picked.context}
本次类型：$kind
这不是每回合固定发生的系统通知，而是角色基于当前剧情主动发来的私人消息。
只写一条自然、具体、符合角色立场的中文私信；可以聊天、给情报、提出请求或派发任务。不要写旁白，不要替玩家回复，不要输出标签或 JSON，不要泄露 GM 隐藏信息。''',
    };
    final response = await _toolCompletion(
      profile: profile.copyWith(stream: false),
      apiKey: apiKey,
      messages: messages,
      tools: const [],
    );
    final raw = await _ensureDisplayableChineseNarration(
      response: response,
      messages: messages,
      action: '随机私人来信',
      profile: profile,
      apiKey: apiKey,
    );
    final parsed = _parseNarration(raw);
    final matching = parsed.aiPlayers
        .where((section) => section.name == picked.name)
        .firstOrNull;
    final content = matching?.content.isNotEmpty == true
        ? matching!.content
        : parsed.gm.isNotEmpty
        ? parsed.gm
        : raw.trim();
    final now = DateTime.now();
    final message = TRPGPrivateMessage(
      id: _uuid.v4(),
      senderId: picked.id,
      recipientIds: [human.playerId, picked.id],
      content: content,
      createdAt: now,
    );
    final createsQuest = selectedKindIndex >= 2;
    final questId = createsQuest ? 'private-quest-${message.id}' : null;
    final quest = createsQuest
        ? QuestState(
            questId: questId!,
            title: selectedKindIndex == 2
                ? '${picked.name}的私人委托'
                : '${picked.name}的紧急求助',
            description: content,
            objectives: [
              QuestObjective(
                id: '$questId-objective',
                description: '回应 ${picked.name}，并决定如何处理这项私人请求',
              ),
            ],
            status: QuestStatus.active,
            progress: '通过私信收到，等待你的回应',
            discoveredAt: now,
          )
        : null;
    return session.copyWith(
      campaignState: quest == null
          ? session.campaignState
          : session.campaignState.copyWith(
              quests: [...session.campaignState.quests, quest],
              activeQuests: [
                ...session.campaignState.activeQuests,
                quest.questId,
              ],
            ),
      immersionState: session.immersionState.copyWith(
        privateMessages: [...session.immersionState.privateMessages, message],
      ),
      eventLog: [
        ...session.eventLog,
        TRPGEvent(
          id: _uuid.v4(),
          type: TRPGEventType.privateMessage,
          timestamp: now,
          actorId: picked.id,
          payload: {
            'messageId': message.id,
            'randomIncoming': true,
            'sourceActionId': sourceActionId,
            'eventKind': kind,
            'questId': ?questId,
            'visibility': DiceVisibility.playerPrivate.name,
            'visibilityPlayerIds': [human.playerId],
          },
          visibleToAi: false,
        ),
      ],
      updatedAt: now,
      lastPlayedAt: now,
    );
  }

  TRPGSession _appendTableChat(TRPGSession session, String raw) {
    final now = DateTime.now();
    final parsed = _parseNarration(raw);
    final messages = <TRPGMessage>[];
    if (parsed.gm.isNotEmpty) {
      messages.add(
        TRPGMessage(
          id: _uuid.v4(),
          messageType: TRPGMessageType.gmMessage,
          content: parsed.gm,
          createdAt: now,
        ),
      );
    }
    final aiPlayers = session.players.where((player) => player.isAiControlled);
    for (final section in parsed.aiPlayers) {
      final player = aiPlayers.where((candidate) {
        final character = session.playerCharacters
            .where((item) => item.playerId == candidate.playerId)
            .firstOrNull;
        return candidate.displayName == section.name ||
            character?.name == section.name;
      }).firstOrNull;
      messages.add(
        TRPGMessage(
          id: _uuid.v4(),
          messageType: TRPGMessageType.npcPlayerMessage,
          content: section.content,
          playerId: player?.playerId,
          createdAt: now,
        ),
      );
    }
    if (messages.isEmpty) {
      messages.add(
        TRPGMessage(
          id: _uuid.v4(),
          messageType: TRPGMessageType.gmMessage,
          content: raw.trim(),
          createdAt: now,
        ),
      );
    }
    return session.copyWith(
      chatHistory: [...session.chatHistory, ...messages],
      updatedAt: now,
      lastPlayedAt: now,
    );
  }

  TRPGSession _appendPrivateReply(
    TRPGSession session,
    String raw, {
    required String humanPlayerId,
    String? targetPlayerId,
    String? targetName,
  }) {
    final now = DateTime.now();
    final parsed = _parseNarration(raw);
    final replies = <TRPGPrivateMessage>[];
    if (targetPlayerId != null) {
      final targeted = parsed.aiPlayers
          .where((section) => section.name == targetName)
          .firstOrNull;
      final content =
          targeted?.content ??
          (parsed.aiPlayers.isNotEmpty
              ? parsed.aiPlayers.first.content
              : parsed.gm);
      replies.add(
        TRPGPrivateMessage(
          id: _uuid.v4(),
          senderId: targetPlayerId,
          recipientIds: [humanPlayerId, targetPlayerId],
          content: content.isEmpty ? raw.trim() : content,
          createdAt: now,
        ),
      );
    } else {
      if (parsed.gm.isNotEmpty) {
        replies.add(
          TRPGPrivateMessage(
            id: _uuid.v4(),
            senderId: 'gm',
            recipientIds: [humanPlayerId],
            content: parsed.gm,
            createdAt: now,
            toGm: true,
          ),
        );
      }
      final aiPlayers = session.players.where(
        (player) => player.isAiControlled,
      );
      for (final section in parsed.aiPlayers) {
        final player = aiPlayers.where((candidate) {
          final character = session.playerCharacters
              .where((item) => item.playerId == candidate.playerId)
              .firstOrNull;
          return candidate.displayName == section.name ||
              character?.name == section.name;
        }).firstOrNull;
        if (player == null) continue;
        replies.add(
          TRPGPrivateMessage(
            id: _uuid.v4(),
            senderId: player.playerId,
            recipientIds: [humanPlayerId, player.playerId],
            content: section.content,
            createdAt: now,
          ),
        );
      }
      if (replies.isEmpty) {
        replies.add(
          TRPGPrivateMessage(
            id: _uuid.v4(),
            senderId: 'gm',
            recipientIds: [humanPlayerId],
            content: raw.trim(),
            createdAt: now,
            toGm: true,
          ),
        );
      }
    }
    return session.copyWith(
      immersionState: session.immersionState.copyWith(
        privateMessages: [
          ...session.immersionState.privateMessages,
          ...replies,
        ],
      ),
      updatedAt: now,
      lastPlayedAt: now,
    );
  }

  Future<TRPGSession> _runToolLoop({
    required TRPGSession session,
    required String action,
    required String actionId,
    required ApiProfile profile,
    required String apiKey,
    ToolSaveCallback? onToolMutation,
  }) async {
    final actionEvent = session.eventLog
        .where((event) => event.payload['actionId'] == actionId)
        .lastOrNull;
    final checked = _checks.resolveAction(
      session: session,
      action: action,
      actionId: actionId,
      playerId: actionEvent?.actorId,
      characterId: actionEvent?.payload['characterId'] as String?,
      targetId: actionEvent?.payload['targetId'] as String?,
      turnId: actionEvent?.payload['turnId'] as String?,
    );
    var current = _withoutLeakedAnalysis(checked.session);
    final messages = _prompts.build(
      session: current,
      action: action,
      memoryTokenBudget: _memoryTokenBudget,
    );
    for (var round = 0; round < maxToolRounds; round++) {
      final response = await _toolCompletion(
        profile: profile.copyWith(stream: false),
        apiKey: apiKey,
        messages: messages,
        tools: _tools.schemas,
      );
      if (response.toolCalls.isEmpty) {
        final narration = await _ensureDisplayableChineseNarration(
          response: response,
          messages: messages,
          action: action,
          profile: profile,
          apiKey: apiKey,
        );
        if (narration.isEmpty) {
          throw StateError('AI GM 没有返回叙事或工具调用');
        }
        return _longTermMemory.process(
          _appendNarration(current, narration, actionId),
          force: true,
        );
      }
      messages.add({
        'role': 'assistant',
        'content': response.content,
        'tool_calls': response.toolCalls
            .map((call) => call.toAssistantJson())
            .toList(),
      });
      for (final call in response.toolCalls) {
        final outcome = await _tools.execute(
          session: current,
          actionId: actionId,
          call: call,
          onMutated: onToolMutation,
        );
        current = outcome.session;
        messages.add({
          'role': 'tool',
          'tool_call_id': call.id,
          'name': call.name,
          'content': jsonEncode(outcome.result),
        });
      }
    }
    final now = DateTime.now();
    final limited = current.copyWith(
      eventLog: [
        ...current.eventLog,
        TRPGEvent(
          id: _uuid.v4(),
          type: TRPGEventType.toolError,
          timestamp: now,
          payload: {
            'actionId': actionId,
            'error': 'tool_loop_limit',
            'maxRounds': maxToolRounds,
          },
        ),
      ],
      updatedAt: now,
    );
    if (onToolMutation != null) await onToolMutation(limited);
    throw StateError('AI GM 工具调用超过 $maxToolRounds 轮，已安全停止；可以重试本次行动。');
  }

  Future<String> _ensureDisplayableChineseNarration({
    required ToolChatResponse response,
    required List<Map<String, Object?>> messages,
    required String action,
    required ApiProfile profile,
    required String apiKey,
  }) async {
    var candidate = response.content.trim();
    if (!response.usedReasoningFallback &&
        AIGMOutputGuard.isDisplayableChinese(candidate)) {
      return candidate;
    }

    final repairMessages = <Map<String, Object?>>[
      ...messages,
      {'role': 'assistant', 'content': candidate},
      {
        'role': 'user',
        'content':
            '''上一条内容是内部分析、英文说明或未完成的思考，不得展示给玩家。
请根据已给出的游戏状态和工具结果，将它重写为自然、沉浸的简体中文剧情。
只写角色能够感知的场景、动作、对白与结果；不要解释 TRPG、提示词、结构化状态或你的推理。
不要再次调用工具，不要添加标题、Markdown 或元说明。
玩家本轮行动：$action
现在直接输出中文剧情正文。''',
      },
    ];

    for (var attempt = 0; attempt < 3; attempt++) {
      final repaired = await _toolCompletion(
        profile: profile.copyWith(
          stream: false,
          maxTokens: profile.maxTokens < 3000 ? 3000 : profile.maxTokens,
          temperature: profile.temperature > .8 ? .8 : profile.temperature,
        ),
        apiKey: apiKey,
        messages: repairMessages,
        tools: const [],
      );
      candidate = repaired.content.trim();
      if (!repaired.usedReasoningFallback &&
          AIGMOutputGuard.isDisplayableChinese(candidate)) {
        return candidate;
      }
      repairMessages
        ..add({'role': 'assistant', 'content': candidate})
        ..add({'role': 'user', 'content': '仍然不是可展示的简体中文剧情。停止分析，只输出中文故事正文。'});
    }

    throw StateError('AI 连续返回英文分析或思考过程，已阻止错误内容显示。请重试本次行动。');
  }

  TRPGSession _withoutLeakedAnalysis(TRPGSession session) {
    final leakedMessageIds = session.chatHistory
        .where(
          (message) =>
              message.messageType == TRPGMessageType.gmMessage &&
              AIGMOutputGuard.looksLikeInternalAnalysis(message.content),
        )
        .map((message) => message.id)
        .toSet();
    if (leakedMessageIds.isEmpty) return session;
    return session.copyWith(
      chatHistory: session.chatHistory
          .where((message) => !leakedMessageIds.contains(message.id))
          .toList(),
      eventLog: session.eventLog.where((event) {
        if (event.type != TRPGEventType.gmNarration) return true;
        final content = event.payload['content']?.toString() ?? '';
        return !AIGMOutputGuard.looksLikeInternalAnalysis(content);
      }).toList(),
    );
  }

  TRPGSession _appendNarration(
    TRPGSession session,
    String narration,
    String actionId,
  ) {
    final now = DateTime.now();
    final parsed = _parseNarration(narration);
    final messages = <TRPGMessage>[];
    final events = <TRPGEvent>[];

    if (parsed.gm.trim().isNotEmpty) {
      messages.add(
        TRPGMessage(
          id: _uuid.v4(),
          messageType: TRPGMessageType.gmMessage,
          content: parsed.gm.trim(),
          createdAt: now,
        ),
      );
      events.add(
        TRPGEvent(
          id: _uuid.v4(),
          type: TRPGEventType.gmNarration,
          timestamp: now,
          payload: {'content': parsed.gm.trim(), 'actionId': actionId},
        ),
      );
    }

    final aiPlayers = session.players
        .where((player) => player.isAiControlled)
        .toList();
    for (final section in parsed.aiPlayers) {
      final player = aiPlayers.where((candidate) {
        final character = session.playerCharacters
            .where((item) => item.playerId == candidate.playerId)
            .firstOrNull;
        return candidate.displayName == section.name ||
            character?.name == section.name;
      }).firstOrNull;
      final content = section.content.trim();
      if (content.isEmpty) continue;
      messages.add(
        TRPGMessage(
          id: _uuid.v4(),
          messageType: TRPGMessageType.npcPlayerMessage,
          content: content,
          playerId: player?.playerId,
          createdAt: now,
        ),
      );
      events.add(
        TRPGEvent(
          id: _uuid.v4(),
          type: TRPGEventType.playerAction,
          timestamp: now,
          actorId: player?.playerId,
          payload: {
            'action': content,
            'actionId': actionId,
            'source': 'ai_player',
          },
        ),
      );
    }

    if (messages.isEmpty) {
      messages.add(
        TRPGMessage(
          id: _uuid.v4(),
          messageType: TRPGMessageType.gmMessage,
          content: narration,
          createdAt: now,
        ),
      );
      events.add(
        TRPGEvent(
          id: _uuid.v4(),
          type: TRPGEventType.gmNarration,
          timestamp: now,
          payload: {'content': narration, 'actionId': actionId},
        ),
      );
    }

    final updated = session.copyWith(
      status: TRPGSessionStatus.active,
      chatHistory: [...session.chatHistory, ...messages],
      eventLog: [...session.eventLog, ...events],
      updatedAt: now,
      lastPlayedAt: now,
    );
    return _memory.compact(updated);
  }

  ({String gm, List<({String name, String content})> aiPlayers})
  _parseNarration(String raw) {
    final gm = <String>[];
    final ai = <({String name, List<String> lines})>[];
    String? currentName;
    final gmMarker = RegExp(r'^\s*\[GM\]\s*$');
    final aiMarker = RegExp(r'^\s*\[(?:AI玩家|NPC玩家|玩家)[:：]\s*(.+?)\s*\]\s*$');
    for (final line in raw.split('\n')) {
      if (gmMarker.hasMatch(line)) {
        currentName = null;
        continue;
      }
      final aiMatch = aiMarker.firstMatch(line);
      if (aiMatch != null) {
        currentName = aiMatch.group(1)!.trim();
        ai.add((name: currentName, lines: []));
        continue;
      }
      if (currentName == null) {
        gm.add(line);
      } else {
        ai.last.lines.add(line);
      }
    }
    return (
      gm: gm.join('\n').trim(),
      aiPlayers: ai
          .map(
            (section) =>
                (name: section.name, content: section.lines.join('\n').trim()),
          )
          .where((section) => section.content.isNotEmpty)
          .toList(),
    );
  }

  @override
  Future<TRPGSession> continueNarration({
    required TRPGSession session,
    required ApiProfile profile,
    required String apiKey,
    ToolSaveCallback? onToolMutation,
  }) => handlePlayerAction(
    session: session,
    action: '我观察局势，等待世界继续发展。',
    profile: profile,
    apiKey: apiKey,
    onToolMutation: onToolMutation,
  );

  @override
  Future<GMStateSnapshot> summarizeSession(TRPGSession session) async =>
      GMStateSnapshot(
        campaignSummary: session.sessionSummary,
        currentScene: session.currentScene,
        worldStateSummary: session.worldState.location,
        playersSummary: session.playerCharacters
            .map(
              (character) =>
                  '${character.name} ${character.hp}/${character.maxHp}',
            )
            .join('\n'),
        activeQuestSummary: session.campaignState.quests
            .where((quest) => quest.status == QuestStatus.active)
            .map((quest) => quest.title)
            .join('\n'),
        hiddenGmNotes: session.gmState.privateNotes,
        recentEvents: _memory
            .selectImportantEvents(session)
            .map((event) => event.type.name)
            .toList(),
        recentMessages: _memory
            .selectRecentMessages(session)
            .map((message) => message.content)
            .toList(),
        longTermMemory: session.memoryState.entries
            .where((memory) => memory.importance >= 7 || memory.pinned)
            .take(30)
            .map(
              (memory) =>
                  memory.summary.isEmpty ? memory.content : memory.summary,
            )
            .toList(),
        npcMemorySummaries: session.memoryState.companionSummaries,
        worldMemorySummary: session.memoryState.sessionSummary,
      );

  @override
  Future<void> restoreSession(TRPGSession session) async {}

  @override
  void dispose() => _aiService.cancel();
}
