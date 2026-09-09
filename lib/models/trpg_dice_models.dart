enum DiceAnimationType {
  tetrahedron,
  cube,
  octahedron,
  decahedron,
  dodecahedron,
  icosahedron,
  percentile,
}

enum DiceSuccessLevel {
  criticalFailure,
  failure,
  success,
  greatSuccess,
  criticalSuccess,
  unopposed,
}

enum DiceRulePackageType {
  genericD20,
  dnd,
  coc,
  dicePool,
  holyGrailWar,
  custom,
}

enum DiceVisibility { public, playerPrivate, gmOnly }

T _enumValue<T extends Enum>(List<T> values, Object? raw, T fallback) =>
    values.where((value) => value.name == raw).firstOrNull ?? fallback;

List<int> _ints(Object? raw) => raw is List
    ? raw.whereType<num>().map((value) => value.toInt()).toList()
    : const [];

List<String> _strings(Object? raw) =>
    raw is List ? raw.map((value) => value.toString()).toList() : const [];

class DiceDefinition {
  const DiceDefinition({
    required this.id,
    required this.name,
    required this.chineseName,
    required this.sides,
    required this.description,
    required this.usage,
    required this.icon,
    required this.animationType,
  });

  final String id, name, chineseName, description, usage, icon;
  final int sides;
  final DiceAnimationType animationType;

  String get rangeLabel => '1-$sides';
  String get displayName => '$id（$chineseName）';

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'chineseName': chineseName,
    'sides': sides,
    'description': description,
    'usage': usage,
    'icon': icon,
    'animationType': animationType.name,
  };

  factory DiceDefinition.fromJson(Map<String, Object?> json) => DiceDefinition(
    id: json['id'] as String? ?? 'D20',
    name: json['name'] as String? ?? 'Twenty Sided Dice',
    chineseName: json['chineseName'] as String? ?? '二十面骰',
    sides: (json['sides'] as num?)?.toInt() ?? 20,
    description: json['description'] as String? ?? '',
    usage: json['usage'] as String? ?? '',
    icon: json['icon'] as String? ?? 'casino',
    animationType: _enumValue(
      DiceAnimationType.values,
      json['animationType'],
      DiceAnimationType.icosahedron,
    ),
  );
}

class DiceFormula {
  const DiceFormula({
    required this.diceCount,
    required this.sides,
    this.modifier = 0,
  });

  final int diceCount, sides, modifier;
  String get diceType => 'D$sides';
  String get normalized =>
      '${diceCount}D$sides${modifier == 0
          ? ''
          : modifier > 0
          ? '+$modifier'
          : '$modifier'}';
  String get explanation {
    final lines = <String>[
      '投掷$diceCount个${DiceLibrary.bySides(sides).chineseName}',
      if (diceCount > 1) '将$diceCount个结果相加',
      if (modifier > 0) '最后增加$modifier点',
      if (modifier < 0) '最后减少${modifier.abs()}点',
    ];
    return lines.join('；');
  }

  Map<String, Object?> toJson() => {
    'diceCount': diceCount,
    'sides': sides,
    'modifier': modifier,
    'diceType': diceType,
    'normalized': normalized,
  };
}

class DiceRollResult {
  const DiceRollResult({
    required this.rollId,
    required this.playerId,
    required this.diceFormula,
    required this.diceType,
    required this.individualResults,
    required this.baseResult,
    required this.modifier,
    required this.finalResult,
    required this.successLevel,
    required this.timestamp,
    this.difficulty,
    this.action = '手动投骰',
    this.reason = '',
    this.explanation = '',
    this.characterId,
    this.rulePackage = DiceRulePackageType.genericD20,
    this.visibility = DiceVisibility.public,
    this.ownerPlayerIds = const [],
    this.metadata = const {},
  });

  final String rollId, playerId, diceFormula, diceType, action, reason;
  final String explanation;
  final String? characterId;
  final List<int> individualResults;
  final int baseResult, modifier, finalResult;
  final int? difficulty;
  final DiceSuccessLevel successLevel;
  final DateTime timestamp;
  final DiceRulePackageType rulePackage;
  final DiceVisibility visibility;
  final List<String> ownerPlayerIds;
  final Map<String, Object?> metadata;

  bool get isSuccess => switch (successLevel) {
    DiceSuccessLevel.success ||
    DiceSuccessLevel.greatSuccess ||
    DiceSuccessLevel.criticalSuccess => true,
    _ => false,
  };

  bool visibleTo(String? playerId, {bool isGm = false}) {
    if (isGm || visibility == DiceVisibility.public) return true;
    if (playerId == null) return false;
    return ownerPlayerIds.contains(playerId) || this.playerId == playerId;
  }

  Map<String, Object?> toJson() => {
    'rollId': rollId,
    'playerId': playerId,
    'diceFormula': diceFormula,
    'diceType': diceType,
    'individualResults': individualResults,
    'baseResult': baseResult,
    'modifier': modifier,
    'finalResult': finalResult,
    'difficulty': difficulty,
    'successLevel': successLevel.name,
    'timestamp': timestamp.toIso8601String(),
    'action': action,
    'reason': reason,
    'explanation': explanation,
    'characterId': characterId,
    'rulePackage': rulePackage.name,
    'visibility': visibility.name,
    'ownerPlayerIds': ownerPlayerIds,
    'metadata': metadata,
  };

  factory DiceRollResult.fromJson(Map<String, Object?> json) => DiceRollResult(
    rollId: json['rollId'] as String? ?? '',
    playerId: json['playerId'] as String? ?? '',
    diceFormula: json['diceFormula'] as String? ?? '1D20',
    diceType: json['diceType'] as String? ?? 'D20',
    individualResults: _ints(json['individualResults']),
    baseResult: (json['baseResult'] as num?)?.toInt() ?? 0,
    modifier: (json['modifier'] as num?)?.toInt() ?? 0,
    finalResult: (json['finalResult'] as num?)?.toInt() ?? 0,
    difficulty: (json['difficulty'] as num?)?.toInt(),
    successLevel: _enumValue(
      DiceSuccessLevel.values,
      json['successLevel'],
      DiceSuccessLevel.unopposed,
    ),
    timestamp:
        DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
    action: json['action'] as String? ?? '手动投骰',
    reason: json['reason'] as String? ?? '',
    explanation: json['explanation'] as String? ?? '',
    characterId: json['characterId'] as String?,
    rulePackage: _enumValue(
      DiceRulePackageType.values,
      json['rulePackage'],
      DiceRulePackageType.genericD20,
    ),
    visibility: _enumValue(
      DiceVisibility.values,
      json['visibility'],
      DiceVisibility.public,
    ),
    ownerPlayerIds: _strings(json['ownerPlayerIds']),
    metadata: json['metadata'] is Map
        ? (json['metadata'] as Map).cast<String, Object?>()
        : const {},
  );
}

class DiceSettings {
  const DiceSettings({
    this.animationEnabled = true,
    this.soundEnabled = true,
    this.hapticsEnabled = true,
    this.tutorialShown = false,
    this.rulePackage = DiceRulePackageType.genericD20,
    this.customFormula = '1D20',
  });

  final bool animationEnabled, soundEnabled, hapticsEnabled, tutorialShown;
  final DiceRulePackageType rulePackage;
  final String customFormula;

  DiceSettings copyWith({
    bool? animationEnabled,
    bool? soundEnabled,
    bool? hapticsEnabled,
    bool? tutorialShown,
    DiceRulePackageType? rulePackage,
    String? customFormula,
  }) => DiceSettings(
    animationEnabled: animationEnabled ?? this.animationEnabled,
    soundEnabled: soundEnabled ?? this.soundEnabled,
    hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
    tutorialShown: tutorialShown ?? this.tutorialShown,
    rulePackage: rulePackage ?? this.rulePackage,
    customFormula: customFormula ?? this.customFormula,
  );

  Map<String, Object?> toJson() => {
    'animationEnabled': animationEnabled,
    'soundEnabled': soundEnabled,
    'hapticsEnabled': hapticsEnabled,
    'tutorialShown': tutorialShown,
    'rulePackage': rulePackage.name,
    'customFormula': customFormula,
  };

  factory DiceSettings.fromJson(Map<String, Object?> json) => DiceSettings(
    animationEnabled: json['animationEnabled'] as bool? ?? true,
    soundEnabled: json['soundEnabled'] as bool? ?? true,
    hapticsEnabled: json['hapticsEnabled'] as bool? ?? true,
    tutorialShown: json['tutorialShown'] as bool? ?? false,
    rulePackage: _enumValue(
      DiceRulePackageType.values,
      json['rulePackage'],
      DiceRulePackageType.genericD20,
    ),
    customFormula: json['customFormula'] as String? ?? '1D20',
  );
}

abstract final class DiceLibrary {
  static const definitions = <DiceDefinition>[
    DiceDefinition(
      id: 'D4',
      name: 'Four Sided Dice',
      chineseName: '四面骰',
      sides: 4,
      description: '点数范围较小、波动稳定。',
      usage: '小型伤害、简单随机',
      icon: 'change_history',
      animationType: DiceAnimationType.tetrahedron,
    ),
    DiceDefinition(
      id: 'D6',
      name: 'Six Sided Dice',
      chineseName: '六面骰',
      sides: 6,
      description: '最常见的立方体骰子。',
      usage: '基础伤害、随机事件',
      icon: 'casino',
      animationType: DiceAnimationType.cube,
    ),
    DiceDefinition(
      id: 'D8',
      name: 'Eight Sided Dice',
      chineseName: '八面骰',
      sides: 8,
      description: '适合中等威力的伤害区间。',
      usage: '武器伤害',
      icon: 'diamond',
      animationType: DiceAnimationType.octahedron,
    ),
    DiceDefinition(
      id: 'D10',
      name: 'Ten Sided Dice',
      chineseName: '十面骰',
      sides: 10,
      description: '十进制体系的基础骰。',
      usage: '技能效果、百分计算辅助',
      icon: 'filter_9_plus',
      animationType: DiceAnimationType.decahedron,
    ),
    DiceDefinition(
      id: 'D12',
      name: 'Twelve Sided Dice',
      chineseName: '十二面骰',
      sides: 12,
      description: '高伤害武器常用骰。',
      usage: '高级伤害',
      icon: 'token',
      animationType: DiceAnimationType.dodecahedron,
    ),
    DiceDefinition(
      id: 'D20',
      name: 'Twenty Sided Dice',
      chineseName: '二十面骰',
      sides: 20,
      description: '决定行动是否成功的核心检定骰。',
      usage: '核心检定、攻击、潜行、说服、侦查',
      icon: 'casino',
      animationType: DiceAnimationType.icosahedron,
    ),
    DiceDefinition(
      id: 'D100',
      name: 'Percentile Dice',
      chineseName: '百分骰',
      sides: 100,
      description: '直接表达百分概率或大型参数判定。',
      usage: '概率检定、调查、克苏鲁规则、圣杯战争宝具',
      icon: 'percent',
      animationType: DiceAnimationType.percentile,
    ),
  ];

  static DiceDefinition bySides(int sides) =>
      definitions.where((value) => value.sides == sides).firstOrNull ??
      definitions[5];
}
