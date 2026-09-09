import '../../models/campaign_models.dart';
import '../../models/trpg_models.dart';

/// Builds the public, spoiler-safe briefing shown before the first playable
/// turn of every campaign.
class CampaignOpeningBriefing {
  const CampaignOpeningBriefing();

  String build({
    required Campaign campaign,
    CampaignDocument? document,
    List<String> playerCharacters = const [],
  }) {
    final world = _firstNonEmpty([
      document?.description,
      campaign.description,
      _metadataText(document?.metadata ?? campaign.metadata, const [
        'worldview',
        'worldView',
        'worldSetting',
        'setting',
      ]),
      document?.theme.isNotEmpty == true
          ? '主题：${document!.theme}${document.tone.isEmpty ? '' : '；基调：${document.tone}'}'
          : null,
      '这是《${campaign.title}》的世界。',
    ]);

    final people = <String>[];
    for (final name in playerCharacters) {
      if (name.trim().isNotEmpty) people.add('$name（玩家角色）');
    }
    final documentNpcs =
        document?.npcs
            .where((npc) => npc.knownToPlayers)
            .take(6)
            .map(
              (npc) => npc.description.trim().isEmpty
                  ? npc.name
                  : '${npc.name}：${_compact(npc.description)}',
            ) ??
        const Iterable<String>.empty();
    people.addAll(documentNpcs);
    if (people.length == playerCharacters.length) {
      people.addAll(
        campaign.npcs.take(6).map((npc) {
          final name = (npc['name'] ?? npc['title'] ?? '未命名人物').toString();
          final description = (npc['description'] ?? '').toString().trim();
          return description.isEmpty ? name : '$name：${_compact(description)}';
        }),
      );
    }
    if (people.isEmpty) people.add('你的角色将在开场行动中结识这个世界的人物。');

    final event = _firstNonEmpty([
      document?.opening,
      campaign.opening,
      '故事即将开始，等待你作出第一个决定。',
    ]);

    return [
      '【世界观】\n${_compact(world, maxLength: 900)}',
      '【主要人物】\n${people.map((item) => '• $item').join('\n')}',
      '【正在发生】\n${_compact(event, maxLength: 1200)}',
    ].join('\n\n');
  }

  String _firstNonEmpty(List<String?> values) => values
      .whereType<String>()
      .map((value) => value.trim())
      .firstWhere((value) => value.isNotEmpty);

  String? _metadataText(Map<String, Object?> metadata, List<String> keys) {
    for (final key in keys) {
      final value = metadata[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  String _compact(String value, {int maxLength = 180}) {
    final compact = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compact.length <= maxLength) return compact;
    return '${compact.substring(0, maxLength)}…';
  }
}
