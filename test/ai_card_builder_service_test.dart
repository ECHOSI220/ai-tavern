import 'dart:convert';

import 'package:ai_tavern/models/api_profile.dart';
import 'package:ai_tavern/models/card_build_target.dart';
import 'package:ai_tavern/models/play_mode.dart';
import 'package:ai_tavern/services/ai_card_builder_service.dart';
import 'package:ai_tavern/services/ai_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAiService extends AiService {
  _FakeAiService(this.output);

  final String output;
  final requests = <List<Map<String, String>>>[];

  @override
  Stream<String> streamChat({
    required ApiProfile profile,
    required String apiKey,
    required List<Map<String, String>> messages,
  }) async* {
    requests.add(messages);
    final split = output.length ~/ 2;
    yield output.substring(0, split);
    yield output.substring(split);
  }
}

class _EmptyThenValidAiService extends AiService {
  var calls = 0;
  final profiles = <ApiProfile>[];

  @override
  Stream<String> streamChat({
    required ApiProfile profile,
    required String apiKey,
    required List<Map<String, String>> messages,
  }) async* {
    calls++;
    profiles.add(profile);
    if (calls == 1) return;
    yield jsonEncode({
      'name': '重试成功的角色',
      'description': '第一次空响应后生成成功',
      'personality': '沉着',
      'appearance': '黑发',
      'background': '来自远方',
      'speakingStyle': '简洁',
      'relationship': '初次见面',
      'goals': '完成任务',
      'secrets': '未知',
      'exampleDialogue': '你好。',
      'scenarioNotes': '保持一致',
      'enabled': true,
    });
  }
}

class _DelayedAiService extends AiService {
  _DelayedAiService(this.output);

  final String output;
  ApiProfile? receivedProfile;

  @override
  Stream<String> streamChat({
    required ApiProfile profile,
    required String apiKey,
    required List<Map<String, String>> messages,
  }) async* {
    receivedProfile = profile;
    await Future<void>.delayed(const Duration(milliseconds: 80));
    yield output;
  }
}

class _EmptyThenValidStoryAiService extends AiService {
  var calls = 0;

  @override
  Stream<String> streamChat({
    required ApiProfile profile,
    required String apiKey,
    required List<Map<String, String>> messages,
  }) async* {
    calls++;
    if (calls == 1) return;
    yield jsonEncode({
      'name': '自动重试剧情',
      'description': '重试后成功',
      'scenario': '新的事件开始。',
      'worldSetting': '测试世界。',
      'openingMessage': '门开了。',
      'characters': <Object?>[],
      'lorebook': <Object?>[],
    });
  }
}

const _profile = ApiProfile(
  id: 'test',
  name: '测试 API',
  baseUrl: 'https://example.invalid/v1',
  model: 'test-model',
);

void main() {
  test('把 API JSON 转换为可保存的完整角色卡', () async {
    final ai = _FakeAiService(
      jsonEncode({
        'name': '伊芙琳',
        'description': '雾港的龙族医生',
        'personality': '克制而仁慈',
        'appearance': '银发与琥珀色竖瞳',
        'background': '十年前失去了部分记忆',
        'speakingStyle': '短句，诊断时十分精确',
        'relationship': '初次救下玩家',
        'goals': '查明龙晶病的来源',
        'secrets': '她本人是第一位感染者',
        'exampleDialogue': '“先别动。伤口会说话。”',
        'scenarioNotes': '不要替玩家作重大决定',
        'enabled': true,
      }),
    );

    final result = await AiCardBuilderService(ai).build(
      target: CardBuildTarget.character,
      profile: _profile,
      apiKey: 'key',
      source: '一位失忆的龙族医生。',
    );

    expect(result.character!.name, '伊芙琳');
    expect(result.character!.secrets, contains('感染者'));
    expect(result.character!.id, isNotEmpty);
    expect(ai.requests.single.last['content'], contains('<source_material>'));
  });

  test('把 API JSON 打包为带角色、世界书和开局记忆的剧情卡', () async {
    final ai = _FakeAiService(
      '```json\n${jsonEncode({
        'name': '雾港诊疗所',
        'description': '龙晶疫病下的悬疑冒险',
        'author': '测试作者',
        'playerName': '调查员',
        'playerDescription': '受议会委托调查疫病',
        'scenario': '调查病例并揭开议会隐瞒的事故。',
        'worldSetting': '漂浮城市以龙晶供能。',
        'roleplayRules': '保持悬疑节奏，不替玩家决定。',
        'openingMessage': '钟声响起，诊疗所的门被风推开。',
        'characters': [
          {'name': '伊芙琳', 'description': '龙族医生', 'personality': '冷静'},
        ],
        'lorebook': [
          {
            'title': '龙晶',
            'keywords': ['龙晶', '能源'],
            'content': '城市能源，也会造成晶化病。',
            'alwaysActive': true,
            'priority': 50,
          },
        ],
        'playMode': 'choice',
        'choiceCount': 4,
        'pendingChoices': ['检查病历', '询问医生', '查看窗外', '联系议会'],
        'memorySummary': '玩家是调查员；伊芙琳刚刚救下玩家；疫病来源未明。',
      })}\n```',
    );

    final result = await AiCardBuilderService(ai).build(
      target: CardBuildTarget.story,
      profile: _profile,
      apiKey: 'key',
      source: '构筑一个龙晶疫病悬疑故事。',
    );
    final card = result.storyCard!;
    final save = card.createSave();

    expect(card.name, '雾港诊疗所');
    expect(card.template.characters.single.name, '伊芙琳');
    expect(card.template.lorebook.single.keywords, contains('龙晶'));
    expect(save.playMode, PlayMode.choice);
    expect(save.pendingChoices, hasLength(4));
    expect(save.memorySummary.content, contains('疫病来源未明'));
    expect(save.sourceStoryCardId, card.id);
  });

  test('API 第一次返回空内容时自动以非流式和更高预算重试', () async {
    final ai = _EmptyThenValidAiService();

    final result = await AiCardBuilderService(ai).build(
      target: CardBuildTarget.character,
      profile: _profile,
      apiKey: 'key',
      source: '创建一个沉着的角色。',
    );

    expect(result.character!.name, '重试成功的角色');
    expect(ai.calls, 2);
    expect(ai.profiles.last.stream, isFalse);
    expect(ai.profiles.last.maxTokens, greaterThanOrEqualTo(2500));
  });

  test('超长文档会完整分段整理后再制卡', () async {
    final ai = _FakeAiService(
      jsonEncode({
        'name': '长文角色',
        'description': '从长文抽取',
        'personality': '沉着',
        'appearance': '黑发',
        'background': '长篇故事',
        'speakingStyle': '简洁',
        'relationship': '同伴',
        'goals': '完成任务',
        'secrets': '未知',
        'exampleDialogue': '你好。',
        'scenarioNotes': '保持一致',
        'enabled': true,
      }),
    );
    final longSource = List.generate(
      9000,
      (index) => '第$index章 世界观设定：漂浮城市与角色关系。',
    ).join('\n');

    final result = await AiCardBuilderService(ai).build(
      target: CardBuildTarget.character,
      profile: _profile,
      apiKey: 'key',
      source: longSource,
    );

    expect(result.character!.name, '长文角色');
    expect(ai.requests.length, greaterThan(2));
    expect(ai.requests.first.last['content'], contains('第0章 世界观设定'));
    expect(
      ai.requests
          .take(ai.requests.length - 1)
          .any((request) => request.last['content']!.contains('第8999章')),
      isTrue,
    );
    final finalRequest = ai.requests.last.last['content']!;
    expect(finalRequest, contains('超长文档完整分段整理结果'));
    expect(finalRequest, contains('全部'));
  });

  test('超过等待提示时间仍继续生成且制卡请求禁用超时', () async {
    final ai = _DelayedAiService(
      jsonEncode({
        'name': '慢速成功角色',
        'description': '允许长时间思考',
        'personality': '耐心',
      }),
    );
    final statuses = <String>[];
    final result =
        await AiCardBuilderService(
          ai,
          longWaitNoticeDelay: const Duration(milliseconds: 20),
        ).build(
          target: CardBuildTarget.character,
          profile: _profile.copyWith(timeoutSeconds: 1),
          apiKey: 'key',
          source: '创建一个允许长时间思考的角色。',
          onProgress: statuses.add,
        );

    expect(result.character!.name, '慢速成功角色');
    expect(ai.receivedProfile!.timeoutSeconds, 0);
    expect(statuses.any((status) => status.contains('不会因耗时自动停止')), isTrue);
  });

  test('空响应会自动重试直到获得完整剧情卡', () async {
    final ai = _EmptyThenValidStoryAiService();
    final result = await AiCardBuilderService(ai).build(
      target: CardBuildTarget.story,
      profile: _profile,
      apiKey: 'key',
      source: '创建一个故事。',
    );

    expect(result.storyCard!.name, '自动重试剧情');
    expect(ai.calls, 2);
  });
}
