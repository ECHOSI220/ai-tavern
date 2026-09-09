enum RuleReferenceSystem { dnd5e, coc7, quickStart }

extension RuleReferenceSystemX on RuleReferenceSystem {
  String get label => switch (this) {
    RuleReferenceSystem.dnd5e => 'D&D 5E',
    RuleReferenceSystem.coc7 => 'COC 7版',
    RuleReferenceSystem.quickStart => '快速开团',
  };

  String get description => switch (this) {
    RuleReferenceSystem.dnd5e => '属性检定、战斗、法术与冒险流程',
    RuleReferenceSystem.coc7 => '调查、理智、幸运与追逐规则',
    RuleReferenceSystem.quickStart => '从零建立一场清晰、流畅的 AI 跑团',
  };
}

class RuleReferenceEntry {
  const RuleReferenceEntry({
    required this.id,
    required this.system,
    required this.category,
    required this.title,
    required this.summary,
    required this.points,
    this.example,
    this.keywords = const [],
  });

  final String id;
  final RuleReferenceSystem system;
  final String category;
  final String title;
  final String summary;
  final List<String> points;
  final String? example;
  final List<String> keywords;

  bool matches(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return true;
    final searchable = <String>[
      system.label,
      category,
      title,
      summary,
      ...points,
      ?example,
      ...keywords,
    ].join('\n').toLowerCase();
    return normalized
        .split(RegExp(r'\s+'))
        .where((term) => term.isNotEmpty)
        .every(searchable.contains);
  }
}
