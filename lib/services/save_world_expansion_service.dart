import '../models/api_profile.dart';
import '../models/character.dart';
import '../models/lore_entry.dart';
import '../models/save_slot.dart';
import 'world_expansion_service.dart';

class SaveWorldExpansionDraft {
  const SaveWorldExpansionDraft({
    required this.original,
    required this.expanded,
    required this.plan,
    required this.addedWorldSetting,
    required this.addedCharacters,
    required this.addedLore,
    this.usedPlanningFallback = false,
  });

  final SaveSlot original;
  final SaveSlot expanded;
  final String plan;
  final String addedWorldSetting;
  final List<Character> addedCharacters;
  final List<LoreEntry> addedLore;
  final bool usedPlanningFallback;
}

class SaveWorldExpansionService {
  SaveWorldExpansionService(this._worldExpansion);

  final WorldExpansionService _worldExpansion;

  void cancel() => _worldExpansion.cancel();

  Future<SaveWorldExpansionDraft> expand({
    required SaveSlot save,
    required ApiProfile profile,
    required String apiKey,
    String guidance = '',
    void Function(String status)? onProgress,
  }) async {
    final source = _sourceFor(save, guidance);
    final result = await _worldExpansion.expand(
      profile: profile,
      apiKey: apiKey,
      seedCharacters: save.characters,
      source: source,
      onProgress: onProgress,
    );
    final generated = result.storyCard.template;
    final existingNames = save.characters
        .map((item) => item.name.trim().toLowerCase())
        .toSet();
    final addedCharacters = generated.characters
        .where(
          (item) => !existingNames.contains(item.name.trim().toLowerCase()),
        )
        .toList();
    final existingLore = save.lorebook
        .map((item) => item.title.trim().toLowerCase())
        .toSet();
    final addedLore = generated.lorebook
        .where(
          (item) => !existingLore.contains(item.title.trim().toLowerCase()),
        )
        .toList();
    final addedWorld = _onlyNewWorldText(
      original: save.worldSetting,
      generated: generated.worldSetting,
    );

    // 只更新世界资料。游玩状态、剧情前提、记忆和所有时间线字段原样保留。
    final expanded = save.copyWith(
      worldSetting: _appendExpansion(save.worldSetting, addedWorld),
      characters: [...save.characters, ...addedCharacters],
      lorebook: [...save.lorebook, ...addedLore],
      messages: save.messages,
      memorySummary: save.memorySummary,
      pendingChoices: save.pendingChoices,
      updatedAt: DateTime.now(),
      lastPlayedAt: save.lastPlayedAt,
    );
    return SaveWorldExpansionDraft(
      original: save,
      expanded: expanded,
      plan: result.plan,
      addedWorldSetting: addedWorld,
      addedCharacters: addedCharacters,
      addedLore: addedLore,
      usedPlanningFallback: result.usedPlanningFallback,
    );
  }

  String _sourceFor(SaveSlot save, String guidance) {
    final lore = save.lorebook
        .map(
          (item) =>
              '- ${item.title}｜关键词：${item.keywords.join('、')}｜${item.content}',
        )
        .join('\n');
    return '''这是对现有游玩存档的“增量世界观拓展”，不是重开游戏，也不是续写当前一轮对话。
必须保留现有世界、角色和世界书的明确设定，只补充新的地域、势力、规则、历史、文化、冲突、新角色与世界书。
不要修改剧情前提、开场白、当前选项、消息、长期记忆或已经发生的游玩进度。

【现有世界观】
${save.worldSetting.trim().isEmpty ? '尚未填写，请从剧情前提和角色资料自然推导。' : save.worldSetting}

【现有剧情前提（只作一致性参考，不得改写）】
${save.scenario}

【现有世界书】
${lore.isEmpty ? '暂无' : lore}

【用户拓展方向】
${guidance.trim().isEmpty ? '没有额外要求。请 AI 自主思考，从原世界观自然延伸可持续游玩的新内容。' : guidance.trim()}''';
  }

  String _onlyNewWorldText({
    required String original,
    required String generated,
  }) {
    final clean = generated.trim();
    if (clean.isEmpty || clean == original.trim()) return '';
    if (original.trim().isNotEmpty && clean.startsWith(original.trim())) {
      return clean.substring(original.trim().length).trim();
    }
    return clean;
  }

  String _appendExpansion(String original, String addition) {
    if (addition.trim().isEmpty) return original;
    if (original.trim().isEmpty) return addition.trim();
    return '${original.trim()}\n\n【AI 拓展世界观】\n${addition.trim()}';
  }
}
