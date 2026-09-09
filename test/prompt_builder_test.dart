import 'package:ai_tavern/models/app_settings.dart';
import 'package:ai_tavern/models/chat_message.dart';
import 'package:ai_tavern/models/lore_entry.dart';
import 'package:ai_tavern/models/nsfw_prompt_template.dart';
import 'package:ai_tavern/models/save_slot.dart';
import 'package:ai_tavern/services/prompt_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PromptBuilder 世界书触发', () {
    final now = DateTime.utc(2026, 8, 10);
    final messages = [
      ChatMessage(
        id: 'm1',
        saveId: 's1',
        role: ChatRole.user,
        content: '我想去骑士团看看。',
        createdAt: now,
        updatedAt: now,
      ),
    ];
    const entries = [
      LoreEntry(
        id: 'always',
        title: '基础历法',
        content: '当前为王国历231年。',
        alwaysActive: true,
      ),
      LoreEntry(
        id: 'knights',
        title: '王国骑士团',
        keywords: ['骑士', '骑士团'],
        content: '第三骑士队由塞西尔率领。',
        priority: 10,
      ),
      LoreEntry(
        id: 'disabled',
        title: '帝国机密',
        keywords: ['我'],
        content: '不应出现。',
        enabled: false,
      ),
    ];

    test('仅返回始终启用和命中关键词的条目', () {
      final active = const PromptBuilder().activeLore(entries, messages);

      expect(active.map((entry) => entry.id), ['knights', 'always']);
    });

    test('构建内容不包含未触发世界书', () {
      final save = SaveSlot.create(
        name: '测试存档',
        playerName: '洛恩',
        worldSetting: '剑与魔法世界。',
        scenario: '玩家到达王都。',
      ).copyWith(lorebook: entries);

      final prompt = const PromptBuilder().buildSystemPrompt(save, messages);

      expect(prompt, contains('王国骑士团'));
      expect(prompt, contains('基础历法'));
      expect(prompt, isNot(contains('帝国机密')));
    });

    test('跨会话自动记忆始终加入 Prompt', () {
      final save = SaveSlot.create(
        name: '测试存档',
      ).copyWith(conversationMemory: '洛恩已经答应清晨前往北门。');

      final prompt = const PromptBuilder().buildSystemPrompt(save, const []);

      expect(prompt, contains('跨会话自动记忆'));
      expect(prompt, contains('清晨前往北门'));
    });

    test('NSFW 仅在总开关开启时固定注入已选择的模板', () {
      final save = SaveSlot.create(name: '测试存档');
      const selected = NsfwPromptTemplate(
        id: 'selected',
        name: '已选择',
        content: 'SELECTED_ADULT_PROMPT',
        enabled: true,
      );
      const unselected = NsfwPromptTemplate(
        id: 'unselected',
        name: '未选择',
        content: 'UNSELECTED_ADULT_PROMPT',
      );
      const builder = PromptBuilder();

      final enabledPrompt = builder.buildSystemPrompt(
        save,
        const [],
        settings: const AppSettings(
          nsfwEnabled: true,
          nsfwPromptTemplates: [selected, unselected],
        ),
      );
      final disabledPrompt = builder.buildSystemPrompt(
        save,
        const [],
        settings: const AppSettings(nsfwPromptTemplates: [selected]),
      );

      expect(enabledPrompt, contains('[全局 NSFW 提示词]'));
      expect(enabledPrompt, contains('SELECTED_ADULT_PROMPT'));
      expect(enabledPrompt, isNot(contains('UNSELECTED_ADULT_PROMPT')));
      expect(disabledPrompt, isNot(contains('SELECTED_ADULT_PROMPT')));
    });

    test('对话文风增强默认开启且可关闭', () {
      final save = SaveSlot.create(name: '测试存档');
      const builder = PromptBuilder();

      final enabledPrompt = builder.buildSystemPrompt(save, const []);
      final disabledPrompt = builder.buildSystemPrompt(
        save,
        const [],
        settings: const AppSettings(dialogueImmersionEnabled: false),
      );

      expect(enabledPrompt, contains('[文风与沉浸感增强]'));
      expect(enabledPrompt, contains('活人感'));
      expect(enabledPrompt, contains('小说感'));
      expect(disabledPrompt, isNot(contains('[文风与沉浸感增强]')));
    });
  });
}
