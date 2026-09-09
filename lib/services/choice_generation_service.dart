import 'dart:convert';

class ChoiceGenerationService {
  const ChoiceGenerationService();

  static const fallbackPool = <String>[
    '观察周围环境，寻找异常细节',
    '向当前角色询问更多信息',
    '检查自己的身体、装备和状态',
    '谨慎向前推进，看看会发生什么',
    '暂时停下，评估眼前的风险',
    '主动提出一个新的行动方案',
    '回顾刚才的线索，寻找遗漏之处',
    '尝试用不同的态度与对方交涉',
    '离开当前位置，探索另一条道路',
    '保持沉默，观察其他人的反应',
  ];

  String instruction(int count) =>
      '''
你现在只负责为互动剧情生成玩家下一步可以选择的行动。
请根据已经发生的剧情，给出恰好 $count 个彼此明显不同、能推动后续剧情的选项。
选项应使用玩家视角、每项一句话，不替玩家预言结果，不复述相同动作。
只输出 JSON 字符串数组，不要输出标题、编号、Markdown 或解释。
示例：["调查门后的声音","询问同伴是否发现异常"]
'''
          .trim();

  String refinementInstruction({
    required List<String> currentChoices,
    required int count,
    required String playerName,
  }) {
    final numbered = currentChoices
        .asMap()
        .entries
        .map((entry) => '${entry.key + 1}. ${entry.value}')
        .join('\n');
    final actor = playerName.trim().isEmpty ? '玩家角色' : playerName.trim();
    return '''
下面这些是当前剧情的“大致发展方向”：
$numbered

请重新思考并生成恰好 $count 个可直接发送的细化选项。要求：
1. 保留当前选项覆盖的主要方向，但把笼统意图改写成具体可演出的行动。
2. 每个选项都必须同时包含“$actor 本人的动作”和“$actor 说出的具体台词”；可以用动作描写加中文引号内台词。
3. 台词符合当前角色身份、性格、关系和现场信息，语言自然，有明显差异。
4. 不替 NPC 回答，不预言行动结果，不把剧情推进到对方回应之后。
5. 每项是一段可直接作为玩家下一条输入的文字，不要写“选择/方案/细化”等说明。
只输出 JSON 字符串数组，不要输出标题、编号、Markdown 或解释。
'''
        .trim();
  }

  List<String> parseAndFill(
    String raw,
    int count, {
    List<String> fallbackChoices = fallbackPool,
  }) {
    final target = count.clamp(2, 10);
    final parsed = <String>[];
    final arrayStart = raw.indexOf('[');
    final arrayEnd = raw.lastIndexOf(']');
    if (arrayStart >= 0 && arrayEnd > arrayStart) {
      try {
        final value = jsonDecode(raw.substring(arrayStart, arrayEnd + 1));
        if (value is List) {
          parsed.addAll(value.whereType<String>());
        }
      } on FormatException {
        // 继续尝试兼容编号或项目符号格式。
      }
    }
    if (parsed.isEmpty) {
      for (final line in const LineSplitter().convert(raw)) {
        final cleaned = line
            .replaceFirst(RegExp(r'^\s*(?:[-*•]|\d+[.)、])\s*'), '')
            .replaceAll(RegExp(r'^["“]|["”]$'), '')
            .trim();
        if (cleaned.isNotEmpty && cleaned.length <= 240) parsed.add(cleaned);
      }
    }

    final result = <String>[];
    for (final item in [...parsed, ...fallbackChoices, ...fallbackPool]) {
      final value = item.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (value.isNotEmpty && !result.contains(value)) result.add(value);
      if (result.length == target) break;
    }
    return result;
  }

  List<String> fallback(int count) => parseAndFill('', count);

  List<String> refinementFallback({
    required List<String> currentChoices,
    required int count,
    required String playerName,
  }) {
    final actor = playerName.trim().isEmpty ? '我' : playerName.trim();
    final source = currentChoices.isEmpty ? fallbackPool : currentChoices;
    final target = count.clamp(2, 10);
    return List.generate(target, (index) {
      final choice = source[index % source.length];
      final cleaned = choice.replaceAll(RegExp(r'[。！？!?]+$'), '').trim();
      return '$actor稳住呼吸，目光落向眼前的人，抬手示意自己的决定：“我想先$cleaned，别急着替我下结论。”（行动细化 ${index + 1}）';
    });
  }
}
