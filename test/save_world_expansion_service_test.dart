import 'dart:convert';

import 'package:ai_tavern/models/api_profile.dart';
import 'package:ai_tavern/models/character.dart';
import 'package:ai_tavern/models/chat_message.dart';
import 'package:ai_tavern/models/lore_entry.dart';
import 'package:ai_tavern/models/memory_summary.dart';
import 'package:ai_tavern/models/play_mode.dart';
import 'package:ai_tavern/models/save_slot.dart';
import 'package:ai_tavern/services/ai_card_builder_service.dart';
import 'package:ai_tavern/services/ai_service.dart';
import 'package:ai_tavern/services/save_world_expansion_service.dart';
import 'package:ai_tavern/services/world_expansion_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _ExpansionAi extends AiService {
  var calls = 0;

  @override
  Stream<String> streamChat({
    required ApiProfile profile,
    required String apiKey,
    required List<Map<String, String>> messages,
  }) async* {
    calls++;
    if (calls == 1) {
      yield '向北拓展港口都市，引入商会与潮汐魔法冲突。';
      return;
    }
    yield jsonEncode({
      'name': 'AI 错误改名',
      'scenario': 'AI 错误改写剧情前提',
      'worldSetting': '旧王国坐落于南方。北方新增潮汐港与三家商会。',
      'openingMessage': 'AI 错误改写开场',
      'characters': [
        {'name': '莉亚', 'description': 'AI 错误修改原角色'},
        {'name': '诺兰', 'description': '潮汐港商会的年轻会计'},
      ],
      'lorebook': [
        {'title': '旧王国', 'content': 'AI 错误覆盖原词条'},
        {
          'title': '潮汐港',
          'keywords': ['潮汐港'],
          'content': '北方港口，潮汐魔法影响航运。',
        },
      ],
      'playMode': 'freeform',
      'pendingChoices': ['AI 错误覆盖选项'],
      'memorySummary': 'AI 错误覆盖记忆',
    });
  }
}

void main() {
  test('存档世界拓展只追加世界资料并完整保留游玩进度', () async {
    final now = DateTime.utc(2026, 8, 13, 2);
    const originalCharacter = Character(
      id: 'lia',
      name: '莉亚',
      description: '原始权威角色设定',
    );
    const originalLore = LoreEntry(
      id: 'old-lore',
      title: '旧王国',
      content: '位于南方的古老王国。',
    );
    final original = SaveSlot(
      id: 'save-1',
      name: '正在游玩的故事',
      playerName: '玩家',
      scenario: '玩家正在追查失踪事件。',
      worldSetting: '旧王国坐落于南方。',
      openingMessage: '原始开场白',
      characters: const [originalCharacter],
      lorebook: const [originalLore],
      messages: [
        ChatMessage(
          id: 'message-1',
          saveId: 'save-1',
          role: ChatRole.user,
          content: '已经发生的游玩进度',
          createdAt: now,
          updatedAt: now,
        ),
      ],
      conversationMemory: '跨会话记忆不能改变',
      playMode: PlayMode.choice,
      choiceCount: 6,
      pendingChoices: const ['继续调查', '返回旅店'],
      memorySummary: MemorySummary(
        content: '长期记忆不能改变',
        coveredMessageId: 'message-1',
        updatedAt: now,
      ),
      createdAt: now,
      updatedAt: now,
      lastPlayedAt: now,
    );
    final ai = _ExpansionAi();
    final result =
        await SaveWorldExpansionService(
          WorldExpansionService(ai, AiCardBuilderService(ai)),
        ).expand(
          save: original,
          profile: const ApiProfile(
            id: 'api',
            name: 'API',
            baseUrl: 'https://example.invalid/v1',
            model: 'test',
          ),
          apiKey: 'key',
          guidance: '向北拓展商业城市。',
        );

    final expanded = result.expanded;
    expect(expanded.id, original.id);
    expect(expanded.name, original.name);
    expect(expanded.scenario, original.scenario);
    expect(expanded.openingMessage, original.openingMessage);
    expect(expanded.messages.single.id, 'message-1');
    expect(expanded.messages.single.content, '已经发生的游玩进度');
    expect(expanded.conversationMemory, original.conversationMemory);
    expect(expanded.memorySummary.toJson(), original.memorySummary.toJson());
    expect(expanded.playMode, PlayMode.choice);
    expect(expanded.pendingChoices, original.pendingChoices);
    expect(expanded.lastPlayedAt, original.lastPlayedAt);
    expect(expanded.characters.first.toJson(), originalCharacter.toJson());
    expect(expanded.characters.last.name, '诺兰');
    expect(expanded.lorebook.first.toJson(), originalLore.toJson());
    expect(expanded.lorebook.last.title, '潮汐港');
    expect(expanded.worldSetting, contains('潮汐港'));
    expect(result.addedCharacters.map((item) => item.name), ['诺兰']);
    expect(result.addedLore.map((item) => item.title), ['潮汐港']);
  });
}
