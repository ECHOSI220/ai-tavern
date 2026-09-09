import 'package:ai_tavern/models/api_profile.dart';
import 'package:ai_tavern/models/trpg_game_models.dart';
import 'package:ai_tavern/models/trpg_models.dart';
import 'package:ai_tavern/services/ai/openai_compatible_provider.dart';
import 'package:ai_tavern/services/ai_service.dart';
import 'package:ai_tavern/services/trpg/ai_gm_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const profile = ApiProfile(
    id: 'test',
    name: 'test',
    baseUrl: 'https://example.test/v1',
    model: 'tool-model',
    stream: false,
  );

  test(
    'AI GM performs multiple real tools then returns natural narration',
    () async {
      var requestCount = 0;
      final service = AIGMService(
        AiService(),
        toolCompletion:
            ({
              required profile,
              required apiKey,
              required messages,
              required tools,
            }) async {
              requestCount++;
              if (requestCount == 1) {
                return const OpenAIChatResponse(
                  content: '',
                  toolCalls: [
                    OpenAIToolCall(
                      id: 'check-1',
                      name: 'skill_check',
                      arguments: {
                        'characterId': 'character',
                        'skillId': 'perception',
                        'difficulty': 10,
                        'reason': '观察港口脚印',
                      },
                    ),
                  ],
                );
              }
              if (requestCount == 2) {
                return const OpenAIChatResponse(
                  content: '',
                  toolCalls: [
                    OpenAIToolCall(
                      id: 'clue-1',
                      name: 'discover_clue',
                      arguments: {
                        'clueId': 'muddy_bootprints',
                        'name': '泥泞脚印',
                        'description': '脚印延伸到仓库侧门。',
                        'characterId': 'character',
                      },
                    ),
                    OpenAIToolCall(
                      id: 'reward-1',
                      name: 'give_item',
                      arguments: {
                        'characterId': 'character',
                        'itemId': 'warehouse_key',
                        'name': '旧仓库钥匙',
                        'quantity': 1,
                        'category': 'keyItem',
                        'reason': '守卫认可了调查能力',
                      },
                    ),
                  ],
                );
              }
              return const OpenAIChatResponse(
                content: '你在雨水中辨认出通往侧门的脚印，守卫沉默片刻，把黄铜钥匙交给了你。',
                toolCalls: [],
              );
            },
      );

      final session = await service.handlePlayerAction(
        session: _session(),
        action: '我观察周围是否有异常痕迹。',
        profile: profile,
        apiKey: 'secret',
        actionId: 'action-1',
      );

      expect(requestCount, 3);
      expect(
        session.eventLog.any((e) => e.type == TRPGEventType.skillCheck),
        true,
      );
      expect(session.campaignState.clues.single.discovered, true);
      expect(
        session.playerCharacters.single.inventoryItems.single.id,
        'warehouse_key',
      );
      expect(session.chatHistory.last.messageType, TRPGMessageType.gmMessage);
      expect(session.chatHistory.last.content, contains('黄铜钥匙'));
    },
  );

  test('retry with same toolCallId does not duplicate HP or items', () async {
    var turn = 0;
    final service = AIGMService(
      AiService(),
      toolCompletion:
          ({
            required profile,
            required apiKey,
            required messages,
            required tools,
          }) async {
            turn++;
            if (turn == 1 || turn == 3) {
              return const OpenAIChatResponse(
                content: '',
                toolCalls: [
                  OpenAIToolCall(
                    id: 'same-damage',
                    name: 'modify_hp',
                    arguments: {
                      'characterId': 'character',
                      'amount': -3,
                      'reason': '跌落伤害',
                    },
                  ),
                ],
              );
            }
            return const OpenAIChatResponse(content: '你稳住了身体。', toolCalls: []);
          },
    );
    final first = await service.handlePlayerAction(
      session: _session(),
      action: '我跳下矮墙。',
      profile: profile,
      apiKey: '',
      actionId: 'action-retry',
    );
    final retry = await service.respondToRecordedAction(
      session: first,
      action: '我跳下矮墙。',
      actionId: 'action-retry',
      profile: profile,
      apiKey: '',
    );
    expect(retry.playerCharacters.single.hp, 17);
    expect(
      retry.toolExecutions.where(
        (record) => record.toolCallId == 'same-damage',
      ),
      hasLength(1),
    );
  });

  test('tool loop limit persists an error and fails visibly', () async {
    TRPGSession? persisted;
    final service = AIGMService(
      AiService(),
      maxToolRounds: 2,
      toolCompletion:
          ({
            required profile,
            required apiKey,
            required messages,
            required tools,
          }) async => const OpenAIChatResponse(
            content: '',
            toolCalls: [
              OpenAIToolCall(
                id: 'repeated-read',
                name: 'get_world_state',
                arguments: {},
              ),
            ],
          ),
    );

    await expectLater(
      service.handlePlayerAction(
        session: _session(),
        action: '继续调查。',
        profile: profile,
        apiKey: '',
        onToolMutation: (session) async => persisted = session,
      ),
      throwsA(isA<StateError>()),
    );
    expect(
      persisted!.eventLog.any((event) => event.type == TRPGEventType.toolError),
      isTrue,
    );
  });

  test('English reasoning fallback is rewritten as Chinese narration', () async {
    var requestCount = 0;
    final service = AIGMService(
      AiService(),
      toolCompletion:
          ({
            required profile,
            required apiKey,
            required messages,
            required tools,
          }) async {
            requestCount++;
            if (requestCount == 1) {
              expect(
                messages.first['content'],
                contains('所有展示给玩家的正文必须使用自然、流畅的简体中文'),
              );
              expect(messages.last['content'], contains('现在立即用简体中文输出'));
              return const OpenAIChatResponse(
                content:
                    'Let me understand the situation. Looking at the structured state, the current player action is summon servant.',
                toolCalls: [],
                usedReasoningFallback: true,
              );
            }
            expect(tools, isEmpty);
            expect(messages.last['content'], contains('直接输出中文剧情正文'));
            return const OpenAIChatResponse(
              content: '召唤阵泛起银白色的光，英灵的身影在翻涌的魔力中逐渐清晰。',
              toolCalls: [],
            );
          },
    );

    final session = await service.handlePlayerAction(
      session: _session().copyWith(
        chatHistory: [
          TRPGMessage(
            id: 'old-leak',
            messageType: TRPGMessageType.gmMessage,
            content:
                'Let me understand the situation. Looking at the structured state.',
            createdAt: DateTime.utc(2026, 8, 13),
          ),
        ],
      ),
      action: '召唤从者',
      profile: profile,
      apiKey: '',
    );

    expect(requestCount, 2);
    expect(session.chatHistory.last.content, contains('召唤阵'));
    expect(session.chatHistory.last.content, isNot(contains('Let me')));
    expect(
      session.chatHistory.any((message) => message.id == 'old-leak'),
      isFalse,
    );
  });
}

TRPGSession _session() {
  final now = DateTime.utc(2026, 8, 13);
  return TRPGSession(
    id: 'session',
    title: '雾港疑云',
    mode: TRPGMode.solo,
    createdAt: now,
    updatedAt: now,
    lastPlayedAt: now,
    campaignId: 'mist_harbor_test',
    players: [
      TRPGPlayer(
        playerId: 'player',
        displayName: '玩家',
        characterId: 'character',
        joinedAt: now,
      ),
    ],
    playerCharacters: const [
      PlayerCharacter(
        id: 'character',
        playerId: 'player',
        name: '晨歌',
        stats: {'STR': 10, 'DEX': 12, 'INT': 14, 'PER': 14, 'CHA': 10},
        skills: {'perception': 2},
      ),
    ],
    campaignState: CampaignState(
      clues: const [
        ClueState(
          clueId: 'muddy_bootprints',
          name: '泥泞脚印',
          description: '尚未发现',
        ),
      ],
    ),
    worldState: const WorldState(
      location: '旧港',
      currentScene: SceneState(
        sceneId: 'arrival',
        locationId: 'old_harbor',
        title: '旧港',
      ),
    ),
  );
}
