import 'dart:convert';

import 'package:ai_tavern/models/api_profile.dart';
import 'package:ai_tavern/models/character.dart';
import 'package:ai_tavern/services/ai_card_builder_service.dart';
import 'package:ai_tavern/services/ai_service.dart';
import 'package:ai_tavern/services/world_expansion_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _WorldExpansionAiService extends AiService {
  final requests = <List<Map<String, String>>>[];

  @override
  Stream<String> streamChat({
    required ApiProfile profile,
    required String apiKey,
    required List<Map<String, String>> messages,
  }) async* {
    requests.add(messages);
    if (requests.length == 1) {
      yield '世界围绕失控星核展开；三方势力争夺能源，主角将经历调查、结盟与阻止灾变三个阶段。';
      return;
    }
    yield jsonEncode({
      'name': '星核边境',
      'description': '围绕失控星核展开的边境冒险',
      'author': 'AI 制卡工坊',
      'playerName': '',
      'playerDescription': '与莉亚同行的调查者',
      'scenario': '调查星核并阻止边境灾变。',
      'worldSetting': '三方势力围绕星核争夺能源。',
      'roleplayRules': '保持角色一致。',
      'openingMessage': '警报声穿过边境城。',
      'characters': [
        {
          'name': '莉亚',
          'description': '被 AI 错误修改的描述',
          'personality': '被篡改',
          'background': '被篡改',
          'secrets': '被篡改',
        },
        {
          'name': '赫克托',
          'description': '星核监察官',
          'personality': '严厉务实',
          'relationship': '怀疑莉亚隐瞒真相',
        },
      ],
      'lorebook': [
        {
          'title': '星核',
          'keywords': ['星核'],
          'content': '能提供能源，也会侵蚀现实。',
          'alwaysActive': true,
          'enabled': true,
          'priority': 100,
        },
      ],
      'playMode': 'choice',
      'choiceCount': 6,
      'pendingChoices': ['调查警报', '询问莉亚'],
      'memorySummary': '莉亚与玩家抵达边境城，星核即将失控。',
    });
  }
}

class _MalformedDetailAiService extends AiService {
  var calls = 0;

  @override
  Stream<String> streamChat({
    required ApiProfile profile,
    required String apiKey,
    required List<Map<String, String>> messages,
  }) async* {
    calls++;
    if (calls == 1) {
      yield '北方出现潮汐港、航海商会与潮汐法师的利益冲突。';
    } else {
      yield '这不是 JSON，但规划本身已经可用。';
    }
  }
}

void main() {
  const profile = ApiProfile(
    id: 'world-api',
    name: '世界扩展 API',
    baseUrl: 'https://example.invalid/v1',
    model: 'test-model',
  );

  test('先规划后构筑世界，并锁定核心角色卡设定', () async {
    const seed = Character(
      id: 'seed-lia',
      name: '莉亚',
      description: '流亡的星术师',
      personality: '善良、谨慎、面对危险时坚定',
      appearance: '银发，佩戴破损星盘',
      background: '故乡因星核事故毁灭',
      speakingStyle: '温和而精确',
      relationship: '与玩家互相依赖',
      goals: '查明事故真相',
      secrets: '她能听见星核的声音',
      exampleDialogue: '“别碰它，我听见它在呼吸。”',
      scenarioNotes: '不能随意相信监察官',
    );
    final ai = _WorldExpansionAiService();
    final result = await WorldExpansionService(ai, AiCardBuilderService(ai))
        .expand(
          profile: profile,
          apiKey: 'key',
          seedCharacters: const [seed],
          source: '拓展成边境城市的政治悬疑，并增加一个监察官。',
        );

    expect(ai.requests, hasLength(2));
    expect(result.plan, contains('三方势力'));
    expect(ai.requests.first.first['content'], contains('先规划'));
    expect(ai.requests[1].last['content'], contains('已完成的世界观规划'));
    final characters = result.storyCard.template.characters;
    expect(characters, hasLength(2));
    expect(characters.first.toJson(), seed.toJson());
    expect(characters.last.name, '赫克托');
    expect(result.storyCard.template.lorebook.single.title, '星核');
  });

  test('既没有角色卡也没有提示词时拒绝空扩展', () async {
    final ai = _WorldExpansionAiService();

    expect(
      () => WorldExpansionService(ai, AiCardBuilderService(ai)).expand(
        profile: profile,
        apiKey: 'key',
        seedCharacters: const [],
        source: ' ',
      ),
      throwsArgumentError,
    );
  });

  test('结构化连续三次失败时使用已成功的规划，不无限重试', () async {
    final ai = _MalformedDetailAiService();
    final result = await WorldExpansionService(ai, AiCardBuilderService(ai))
        .expand(
          profile: profile,
          apiKey: 'key',
          seedCharacters: const [Character(id: 'seed', name: '莉亚')],
          source: '拓展北方地区。',
        );

    expect(ai.calls, 4);
    expect(result.usedPlanningFallback, isTrue);
    expect(result.storyCard.template.worldSetting, contains('潮汐港'));
    expect(result.storyCard.template.characters.single.name, '莉亚');
  });
}
