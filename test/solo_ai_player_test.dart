import 'package:ai_tavern/models/api_profile.dart';
import 'package:ai_tavern/models/trpg_models.dart';
import 'package:ai_tavern/models/trpg_dice_models.dart';
import 'package:ai_tavern/models/trpg_game_models.dart';
import 'package:ai_tavern/services/ai/openai_compatible_provider.dart';
import 'package:ai_tavern/services/ai_service.dart';
import 'package:ai_tavern/services/trpg/ai_gm_prompt_builder.dart';
import 'package:ai_tavern/services/trpg/ai_gm_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AI 玩家植入', () {
    test('TRPGPlayer 序列化保留 isAiControlled', () {
      final now = DateTime.utc(2026, 8, 16);
      final player = TRPGPlayer(
        playerId: 'ai-1',
        displayName: '阿黛尔',
        characterId: 'char-1',
        role: TRPGPlayerRole.player,
        joinedAt: now,
        isReady: true,
        isAiControlled: true,
      );

      final restored = TRPGPlayer.fromJson(player.toJson());

      expect(restored.isAiControlled, isTrue);
      expect(restored.displayName, '阿黛尔');
    });

    test('npcPlayerMessage JSON 往返', () {
      final now = DateTime.utc(2026, 8, 16);
      final message = TRPGMessage(
        id: 'm1',
        messageType: TRPGMessageType.npcPlayerMessage,
        content: '阿黛尔把短剑放在桌上，盯着对方没有说话。',
        playerId: 'ai-1',
        createdAt: now,
      );

      final restored = TRPGMessage.fromJson(message.toJson());

      expect(restored.messageType, TRPGMessageType.npcPlayerMessage);
      expect(restored.playerId, 'ai-1');
      expect(restored.content, contains('短剑'));
    });

    test('AIGMPromptBuilder 为 AI 玩家注入独立行动指令', () {
      final now = DateTime.utc(2026, 8, 16);
      final aiPlayer = TRPGPlayer(
        playerId: 'ai-1',
        displayName: '阿黛尔',
        characterId: 'char-1',
        joinedAt: now,
        isReady: true,
        isAiControlled: true,
      );
      final humanPlayer = TRPGPlayer(
        playerId: 'human-1',
        displayName: '玩家',
        characterId: 'char-0',
        joinedAt: now,
        isReady: true,
      );
      final session = TRPGSession(
        id: 's1',
        title: '测试',
        mode: TRPGMode.solo,
        createdAt: now,
        updatedAt: now,
        lastPlayedAt: now,
        campaignId: 'c1',
        players: [humanPlayer, aiPlayer],
        playerCharacters: [
          PlayerCharacter(id: 'char-0', playerId: 'human-1', name: '洛恩'),
          PlayerCharacter(
            id: 'char-1',
            playerId: 'ai-1',
            name: '阿黛尔',
            personality: '谨慎多疑，嘴硬心软。',
            background: '流浪佣兵',
          ),
        ],
        worldState: const WorldState(location: '旧港'),
      );

      final messages = const AIGMPromptBuilder().build(
        session: session,
        action: '洛恩走进仓库。',
      );

      final system = messages.first['content']! as String;
      expect(system, contains('AI 玩家角色'));
      expect(system, contains('阿黛尔'));
      expect(system, contains('[AI玩家：角色名]'));
      expect(system, contains('不能替真正的人类玩家做决定'));
      expect(system, contains('禁止使用“阿黛尔对你说'));
    });

    test('AIGMPromptBuilder 明确注入存档选择的规则包', () {
      final now = DateTime.utc(2026, 9, 2);
      final session = TRPGSession(
        id: 'coc-session',
        title: 'COC 测试',
        mode: TRPGMode.solo,
        createdAt: now,
        updatedAt: now,
        lastPlayedAt: now,
        campaignId: 'c1',
        ruleState: const RuleState(
          diceSettings: DiceSettings(rulePackage: DiceRulePackageType.coc),
        ),
      );

      final messages = const AIGMPromptBuilder().build(
        session: session,
        action: '我检查门锁。',
      );
      final system = messages.first['content']! as String;

      expect(system, contains('【当前规则包】'));
      expect(system, contains('COC 7版'));
      expect(system, contains('D100 百分骰'));
    });

    test('单人闲聊由 GM 与 AI 玩家拆分回复且不推进事件', () async {
      final session = _soloSession();
      final service = AIGMService(
        AiService(),
        toolCompletion:
            ({
              required profile,
              required apiKey,
              required messages,
              required tools,
            }) async {
              expect(tools, isEmpty);
              expect(messages.first['content'], contains('本轮是桌边闲聊'));
              return const OpenAIChatResponse(
                content: '[GM]\n火炉安静地噼啪作响。\n[AI玩家：阿黛尔]\n你终于想起来问我了？',
                toolCalls: [],
              );
            },
      );

      final updated = await service.handleSoloInteraction(
        session: session,
        content: '阿黛尔，你觉得我们该往哪走？',
        type: SoloAIInteractionType.tableChat,
        profile: _profile,
        apiKey: '',
      );

      expect(updated.eventLog, isEmpty);
      expect(updated.chatHistory, hasLength(3));
      expect(
        updated.chatHistory.last.messageType,
        TRPGMessageType.npcPlayerMessage,
      );
      expect(updated.chatHistory.last.playerId, 'ai-1');
    });

    test('单人秘密行动与 AI 队友私信不会进入公共时间线', () async {
      var request = 0;
      final service = AIGMService(
        AiService(),
        toolCompletion:
            ({
              required profile,
              required apiKey,
              required messages,
              required tools,
            }) async {
              request++;
              expect(tools, isEmpty);
              return OpenAIChatResponse(
                content: request == 1
                    ? '[GM]\n门后传来两短一长的敲击声。'
                    : '[AI玩家：阿黛尔]\n我会守住出口，你去查暗门。',
                toolCalls: const [],
              );
            },
      );

      final secret = await service.handleSoloInteraction(
        session: _soloSession(),
        content: '趁守卫转身时检查暗门。',
        type: SoloAIInteractionType.secretAction,
        profile: _profile,
        apiKey: '',
      );
      final privateReply = await service.handleSoloInteraction(
        session: secret,
        content: '你替我望风。',
        type: SoloAIInteractionType.privateMessage,
        targetPlayerId: 'ai-1',
        targetName: '阿黛尔',
        profile: _profile,
        apiKey: '',
      );

      expect(privateReply.chatHistory, isEmpty);
      expect(
        privateReply.eventLog.any(
          (event) =>
              event.type == TRPGEventType.secretAction && !event.visibleToAi,
        ),
        isTrue,
      );
      expect(
        privateReply.immersionState.timeline.single.visibility,
        InformationVisibility.playerPrivate,
      );
      expect(privateReply.immersionState.privateMessages, hasLength(4));
      expect(privateReply.immersionState.privateMessages.last.senderId, 'ai-1');
      expect(
        privateReply.immersionState.privateMessages.last.content,
        contains('守住出口'),
      );
    });

    test('随机私信未命中时不请求 AI 也不修改存档', () async {
      var requests = 0;
      final service = AIGMService(
        AiService(),
        toolCompletion:
            ({
              required profile,
              required apiKey,
              required messages,
              required tools,
            }) async {
              requests++;
              return const OpenAIChatResponse(content: '不应调用', toolCalls: []);
            },
      );

      final original = _soloSession();
      final updated = await service.maybeTriggerSoloPrivateMessage(
        session: original,
        profile: _profile,
        apiKey: '',
        sourceActionId: 'turn-no-message',
        triggerRoll: .99,
      );

      expect(identical(updated, original), isTrue);
      expect(requests, 0);
    });

    test('随机私信命中后由角色主动来信且同一回合不会重复', () async {
      var requests = 0;
      final service = AIGMService(
        AiService(),
        toolCompletion:
            ({
              required profile,
              required apiKey,
              required messages,
              required tools,
            }) async {
              requests++;
              expect(tools, isEmpty);
              expect(messages.first['content'], contains('随机私信事件'));
              expect(messages.first['content'], contains('私人委托'));
              return const OpenAIChatResponse(
                content: '港口仓库今晚会换岗。你愿意替我取回被扣下的航海日志吗？',
                toolCalls: [],
              );
            },
      );

      final first = await service.maybeTriggerSoloPrivateMessage(
        session: _soloSession(),
        profile: _profile,
        apiKey: '',
        sourceActionId: 'turn-private-message',
        triggerRoll: 0,
        senderIndex: 0,
        eventKindIndex: 2,
      );
      final repeated = await service.maybeTriggerSoloPrivateMessage(
        session: first,
        profile: _profile,
        apiKey: '',
        sourceActionId: 'turn-private-message',
        triggerRoll: 0,
        senderIndex: 0,
        eventKindIndex: 2,
      );

      expect(requests, 1);
      expect(first.chatHistory, isEmpty);
      expect(first.immersionState.privateMessages, hasLength(1));
      expect(first.immersionState.privateMessages.single.senderId, 'ai-1');
      expect(
        first.immersionState.privateMessages.single.content,
        contains('航海日志'),
      );
      expect(first.campaignState.quests, hasLength(1));
      expect(first.campaignState.quests.single.status, QuestStatus.active);
      expect(first.campaignState.quests.single.title, contains('私人委托'));
      expect(first.eventLog.single.payload['randomIncoming'], isTrue);
      expect(repeated.immersionState.privateMessages, hasLength(1));
    });
  });
}

const _profile = ApiProfile(
  id: 'test',
  name: 'test',
  baseUrl: 'https://example.test/v1',
  model: 'test-model',
  stream: false,
);

TRPGSession _soloSession() {
  final now = DateTime.utc(2026, 9, 6);
  return TRPGSession(
    id: 'solo-channels',
    title: '单人频道测试',
    mode: TRPGMode.solo,
    createdAt: now,
    updatedAt: now,
    lastPlayedAt: now,
    campaignId: 'c1',
    players: [
      TRPGPlayer(
        playerId: 'human-1',
        displayName: '玩家',
        characterId: 'char-0',
        joinedAt: now,
      ),
      TRPGPlayer(
        playerId: 'ai-1',
        displayName: '阿黛尔',
        characterId: 'char-1',
        joinedAt: now,
        isAiControlled: true,
      ),
    ],
    playerCharacters: const [
      PlayerCharacter(id: 'char-0', playerId: 'human-1', name: '洛恩'),
      PlayerCharacter(id: 'char-1', playerId: 'ai-1', name: '阿黛尔'),
    ],
    worldState: const WorldState(location: '旧港'),
  );
}
