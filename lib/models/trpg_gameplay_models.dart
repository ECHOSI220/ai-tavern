enum ActionCheckType { none, attribute, skill, passive, opposed, group, help }

enum ActionRiskLevel { none, low, medium, high, critical }

enum RollVisibility { public, playerPrivate, gmHidden }

enum DicePresentationMode { compact, dramatic, none }

enum ActionOutcomeLevel {
  criticalFailure,
  failure,
  partialSuccess,
  success,
  greatSuccess,
  criticalSuccess,
  automaticSuccess,
  blocked,
}

enum RepeatedCheckPolicy {
  allow,
  increaseDifficulty,
  requireNewApproach,
  block,
}

enum GrowthRuleType {
  rollOverCurrent,
  rollUnderTarget,
  milestone,
  xp,
  training,
  eventBased,
  customRule,
}

enum GrowthType { skill, attribute, trait }

enum GrowthCandidateStatus { pending, resolved, rejected, expired }

enum ResolutionVisibility { public, playerPrivate, party }

T _gameplayEnum<T extends Enum>(List<T> values, Object? raw, T fallback) =>
    values.where((value) => value.name == raw).firstOrNull ?? fallback;

List<String> _gameplayStrings(Object? raw) =>
    raw is List ? raw.map((value) => value.toString()).toList() : const [];

class ModifierSource {
  const ModifierSource({
    required this.id,
    required this.label,
    required this.value,
    required this.category,
    this.detail = '',
  });

  final String id, label, category, detail;
  final int value;

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    'value': value,
    'category': category,
    'detail': detail,
  };

  factory ModifierSource.fromJson(Map<String, Object?> json) => ModifierSource(
    id: json['id'] as String? ?? '',
    label: json['label'] as String? ?? '',
    value: (json['value'] as num?)?.toInt() ?? 0,
    category: json['category'] as String? ?? 'other',
    detail: json['detail'] as String? ?? '',
  );
}

class ActionCheckDecision {
  const ActionCheckDecision({
    required this.requiresCheck,
    this.checkType = ActionCheckType.none,
    this.attributeId,
    this.skillId,
    this.targetId,
    this.difficulty,
    this.opposedTargetId,
    this.riskLevel = ActionRiskLevel.none,
    this.reason = '',
    this.visibility = RollVisibility.public,
    this.presentationMode = DicePresentationMode.compact,
    this.suggestedDiceFormula = '1D20',
    this.repeatedCheckPolicy = RepeatedCheckPolicy.requireNewApproach,
    this.semanticKey = '',
    this.autoSuccess = false,
  });

  final bool requiresCheck, autoSuccess;
  final ActionCheckType checkType;
  final String? attributeId, skillId, targetId, opposedTargetId;
  final int? difficulty;
  final ActionRiskLevel riskLevel;
  final String reason, suggestedDiceFormula, semanticKey;
  final RollVisibility visibility;
  final DicePresentationMode presentationMode;
  final RepeatedCheckPolicy repeatedCheckPolicy;

  Map<String, Object?> toJson() => {
    'requiresCheck': requiresCheck,
    'checkType': checkType.name,
    'attributeId': attributeId,
    'skillId': skillId,
    'targetId': targetId,
    'difficulty': difficulty,
    'opposedTargetId': opposedTargetId,
    'riskLevel': riskLevel.name,
    'reason': reason,
    'visibility': visibility.name,
    'presentationMode': presentationMode.name,
    'suggestedDiceFormula': suggestedDiceFormula,
    'repeatedCheckPolicy': repeatedCheckPolicy.name,
    'semanticKey': semanticKey,
    'autoSuccess': autoSuccess,
  };

  factory ActionCheckDecision.fromJson(Map<String, Object?> json) =>
      ActionCheckDecision(
        requiresCheck: json['requiresCheck'] as bool? ?? false,
        checkType: _gameplayEnum(
          ActionCheckType.values,
          json['checkType'],
          ActionCheckType.none,
        ),
        attributeId: json['attributeId'] as String?,
        skillId: json['skillId'] as String?,
        targetId: json['targetId'] as String?,
        difficulty: (json['difficulty'] as num?)?.toInt(),
        opposedTargetId: json['opposedTargetId'] as String?,
        riskLevel: _gameplayEnum(
          ActionRiskLevel.values,
          json['riskLevel'],
          ActionRiskLevel.none,
        ),
        reason: json['reason'] as String? ?? '',
        visibility: _gameplayEnum(
          RollVisibility.values,
          json['visibility'],
          RollVisibility.public,
        ),
        presentationMode: _gameplayEnum(
          DicePresentationMode.values,
          json['presentationMode'],
          DicePresentationMode.compact,
        ),
        suggestedDiceFormula: json['suggestedDiceFormula'] as String? ?? '1D20',
        repeatedCheckPolicy: _gameplayEnum(
          RepeatedCheckPolicy.values,
          json['repeatedCheckPolicy'],
          RepeatedCheckPolicy.requireNewApproach,
        ),
        semanticKey: json['semanticKey'] as String? ?? '',
        autoSuccess: json['autoSuccess'] as bool? ?? false,
      );
}

class ActionCheckResult {
  const ActionCheckResult({
    required this.checkId,
    required this.turnId,
    required this.actionId,
    required this.playerId,
    required this.characterId,
    required this.checkType,
    required this.diceFormula,
    required this.individualRolls,
    required this.baseRoll,
    required this.modifierSources,
    required this.difficulty,
    required this.finalResult,
    required this.successLevel,
    required this.margin,
    required this.visibility,
    required this.presentationMode,
    required this.reason,
    required this.createdAt,
    this.attributeId,
    this.skillId,
    this.targetId,
    this.opposedResult,
  });

  final String checkId, turnId, actionId, playerId, characterId;
  final String diceFormula, reason;
  final String? attributeId, skillId, targetId;
  final ActionCheckType checkType;
  final List<int> individualRolls;
  final int baseRoll, difficulty, finalResult, margin;
  final int? opposedResult;
  final List<ModifierSource> modifierSources;
  final ActionOutcomeLevel successLevel;
  final RollVisibility visibility;
  final DicePresentationMode presentationMode;
  final DateTime createdAt;

  int get totalModifier =>
      modifierSources.fold(0, (sum, item) => sum + item.value);

  String get displayExplanation {
    final lines = <String>['【$reason】', diceFormula, '基础骰：$baseRoll'];
    for (final source in modifierSources.where((value) => value.value != 0)) {
      lines.add(
        '${source.label}：${source.value >= 0 ? '+' : ''}${source.value}',
      );
    }
    lines
      ..add('最终：$finalResult')
      ..add('难度：$difficulty')
      ..add('结果：${successLevelLabel(successLevel)}');
    return lines.join('\n');
  }

  static String successLevelLabel(ActionOutcomeLevel value) => switch (value) {
    ActionOutcomeLevel.criticalFailure => '大失败',
    ActionOutcomeLevel.failure => '失败',
    ActionOutcomeLevel.partialSuccess => '部分成功',
    ActionOutcomeLevel.success => '成功',
    ActionOutcomeLevel.greatSuccess => '优秀成功',
    ActionOutcomeLevel.criticalSuccess => '大成功',
    ActionOutcomeLevel.automaticSuccess => '自动成功',
    ActionOutcomeLevel.blocked => '被规则阻止',
  };

  Map<String, Object?> toJson() => {
    'checkId': checkId,
    'turnId': turnId,
    'actionId': actionId,
    'playerId': playerId,
    'characterId': characterId,
    'checkType': checkType.name,
    'attributeId': attributeId,
    'skillId': skillId,
    'targetId': targetId,
    'diceFormula': diceFormula,
    'individualRolls': individualRolls,
    'baseRoll': baseRoll,
    'modifierSources': modifierSources.map((value) => value.toJson()).toList(),
    'difficulty': difficulty,
    'finalResult': finalResult,
    'successLevel': successLevel.name,
    'margin': margin,
    'visibility': visibility.name,
    'presentationMode': presentationMode.name,
    'reason': reason,
    'opposedResult': opposedResult,
    'createdAt': createdAt.toIso8601String(),
  };

  factory ActionCheckResult.fromJson(
    Map<String, Object?> json,
  ) => ActionCheckResult(
    checkId: json['checkId'] as String? ?? '',
    turnId: json['turnId'] as String? ?? '',
    actionId: json['actionId'] as String? ?? '',
    playerId: json['playerId'] as String? ?? '',
    characterId: json['characterId'] as String? ?? '',
    checkType: _gameplayEnum(
      ActionCheckType.values,
      json['checkType'],
      ActionCheckType.skill,
    ),
    attributeId: json['attributeId'] as String?,
    skillId: json['skillId'] as String?,
    targetId: json['targetId'] as String?,
    diceFormula: json['diceFormula'] as String? ?? '1D20',
    individualRolls: (json['individualRolls'] as List? ?? const [])
        .whereType<num>()
        .map((value) => value.toInt())
        .toList(),
    baseRoll: (json['baseRoll'] as num?)?.toInt() ?? 0,
    modifierSources: (json['modifierSources'] as List? ?? const [])
        .whereType<Map>()
        .map((value) => ModifierSource.fromJson(value.cast<String, Object?>()))
        .toList(),
    difficulty: (json['difficulty'] as num?)?.toInt() ?? 10,
    finalResult: (json['finalResult'] as num?)?.toInt() ?? 0,
    successLevel: _gameplayEnum(
      ActionOutcomeLevel.values,
      json['successLevel'],
      ActionOutcomeLevel.failure,
    ),
    margin: (json['margin'] as num?)?.toInt() ?? 0,
    visibility: _gameplayEnum(
      RollVisibility.values,
      json['visibility'],
      RollVisibility.public,
    ),
    presentationMode: _gameplayEnum(
      DicePresentationMode.values,
      json['presentationMode'],
      DicePresentationMode.compact,
    ),
    reason: json['reason'] as String? ?? '行动检定',
    opposedResult: (json['opposedResult'] as num?)?.toInt(),
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
  );
}

class GrowthCandidate {
  const GrowthCandidate({
    required this.candidateId,
    required this.characterId,
    required this.sourceEventId,
    required this.reason,
    required this.difficulty,
    required this.importance,
    required this.growthType,
    required this.createdAt,
    this.attributeId,
    this.skillId,
    this.status = GrowthCandidateStatus.pending,
    this.sceneId = '',
  });

  final String candidateId, characterId, sourceEventId, reason, sceneId;
  final String? attributeId, skillId;
  final int difficulty, importance;
  final GrowthType growthType;
  final GrowthCandidateStatus status;
  final DateTime createdAt;

  GrowthCandidate copyWith({GrowthCandidateStatus? status}) => GrowthCandidate(
    candidateId: candidateId,
    characterId: characterId,
    sourceEventId: sourceEventId,
    attributeId: attributeId,
    skillId: skillId,
    reason: reason,
    difficulty: difficulty,
    importance: importance,
    growthType: growthType,
    status: status ?? this.status,
    sceneId: sceneId,
    createdAt: createdAt,
  );

  Map<String, Object?> toJson() => {
    'candidateId': candidateId,
    'characterId': characterId,
    'sourceEventId': sourceEventId,
    'attributeId': attributeId,
    'skillId': skillId,
    'reason': reason,
    'difficulty': difficulty,
    'importance': importance,
    'growthType': growthType.name,
    'status': status.name,
    'sceneId': sceneId,
    'createdAt': createdAt.toIso8601String(),
  };

  factory GrowthCandidate.fromJson(Map<String, Object?> json) =>
      GrowthCandidate(
        candidateId: json['candidateId'] as String? ?? '',
        characterId: json['characterId'] as String? ?? '',
        sourceEventId: json['sourceEventId'] as String? ?? '',
        attributeId: json['attributeId'] as String?,
        skillId: json['skillId'] as String?,
        reason: json['reason'] as String? ?? '',
        difficulty: (json['difficulty'] as num?)?.toInt() ?? 10,
        importance: (json['importance'] as num?)?.toInt() ?? 1,
        growthType: _gameplayEnum(
          GrowthType.values,
          json['growthType'],
          GrowthType.skill,
        ),
        status: _gameplayEnum(
          GrowthCandidateStatus.values,
          json['status'],
          GrowthCandidateStatus.pending,
        ),
        sceneId: json['sceneId'] as String? ?? '',
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
      );
}

class CharacterGrowthEntry {
  const CharacterGrowthEntry({
    required this.id,
    required this.characterId,
    required this.targetId,
    required this.growthType,
    required this.before,
    required this.after,
    required this.reason,
    required this.createdAt,
    this.roll,
    this.ruleType = GrowthRuleType.rollOverCurrent,
  });

  final String id, characterId, targetId, reason;
  final GrowthType growthType;
  final num before, after;
  final int? roll;
  final GrowthRuleType ruleType;
  final DateTime createdAt;

  Map<String, Object?> toJson() => {
    'id': id,
    'characterId': characterId,
    'targetId': targetId,
    'growthType': growthType.name,
    'before': before,
    'after': after,
    'reason': reason,
    'roll': roll,
    'ruleType': ruleType.name,
    'createdAt': createdAt.toIso8601String(),
  };

  factory CharacterGrowthEntry.fromJson(Map<String, Object?> json) =>
      CharacterGrowthEntry(
        id: json['id'] as String? ?? '',
        characterId: json['characterId'] as String? ?? '',
        targetId: json['targetId'] as String? ?? '',
        growthType: _gameplayEnum(
          GrowthType.values,
          json['growthType'],
          GrowthType.skill,
        ),
        before: json['before'] as num? ?? 0,
        after: json['after'] as num? ?? 0,
        reason: json['reason'] as String? ?? '',
        roll: (json['roll'] as num?)?.toInt(),
        ruleType: _gameplayEnum(
          GrowthRuleType.values,
          json['ruleType'],
          GrowthRuleType.rollOverCurrent,
        ),
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
      );
}

class CharacterTrait {
  const CharacterTrait({
    required this.id,
    required this.characterId,
    required this.name,
    required this.description,
    required this.effect,
    required this.unlockedAt,
    this.progress = 0,
    this.target = 1,
  });
  final String id, characterId, name, description, effect;
  final int progress, target;
  final DateTime unlockedAt;

  bool get unlocked => progress >= target;

  CharacterTrait copyWith({int? progress}) => CharacterTrait(
    id: id,
    characterId: characterId,
    name: name,
    description: description,
    effect: effect,
    progress: progress ?? this.progress,
    target: target,
    unlockedAt: unlockedAt,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'characterId': characterId,
    'name': name,
    'description': description,
    'effect': effect,
    'progress': progress,
    'target': target,
    'unlockedAt': unlockedAt.toIso8601String(),
  };

  factory CharacterTrait.fromJson(Map<String, Object?> json) => CharacterTrait(
    id: json['id'] as String? ?? '',
    characterId: json['characterId'] as String? ?? '',
    name: json['name'] as String? ?? '',
    description: json['description'] as String? ?? '',
    effect: json['effect'] as String? ?? '',
    progress: (json['progress'] as num?)?.toInt() ?? 0,
    target: (json['target'] as num?)?.toInt() ?? 1,
    unlockedAt:
        DateTime.tryParse(json['unlockedAt'] as String? ?? '') ??
        DateTime.now(),
  );
}

class PlayerResolution {
  const PlayerResolution({
    required this.id,
    required this.playerIds,
    required this.title,
    required this.entries,
    required this.visibility,
    required this.createdAt,
    this.sourceEventId = '',
  });
  final String id, title, sourceEventId;
  final List<String> playerIds, entries;
  final ResolutionVisibility visibility;
  final DateTime createdAt;

  bool visibleTo(String playerId) =>
      visibility != ResolutionVisibility.playerPrivate ||
      playerIds.contains(playerId);

  Map<String, Object?> toJson() => {
    'id': id,
    'playerIds': playerIds,
    'title': title,
    'entries': entries,
    'visibility': visibility.name,
    'createdAt': createdAt.toIso8601String(),
    'sourceEventId': sourceEventId,
  };

  factory PlayerResolution.fromJson(Map<String, Object?> json) =>
      PlayerResolution(
        id: json['id'] as String? ?? '',
        playerIds: _gameplayStrings(json['playerIds']),
        title: json['title'] as String? ?? '行动结算',
        entries: _gameplayStrings(json['entries']),
        visibility: _gameplayEnum(
          ResolutionVisibility.values,
          json['visibility'],
          ResolutionVisibility.playerPrivate,
        ),
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
        sourceEventId: json['sourceEventId'] as String? ?? '',
      );
}

class RepeatedCheckRecord {
  const RepeatedCheckRecord({
    required this.semanticKey,
    required this.characterId,
    required this.sceneId,
    required this.attempts,
    required this.lastSuccess,
    required this.updatedAt,
  });
  final String semanticKey, characterId, sceneId;
  final int attempts;
  final bool lastSuccess;
  final DateTime updatedAt;

  RepeatedCheckRecord copyWith({int? attempts, bool? lastSuccess}) =>
      RepeatedCheckRecord(
        semanticKey: semanticKey,
        characterId: characterId,
        sceneId: sceneId,
        attempts: attempts ?? this.attempts,
        lastSuccess: lastSuccess ?? this.lastSuccess,
        updatedAt: DateTime.now(),
      );

  Map<String, Object?> toJson() => {
    'semanticKey': semanticKey,
    'characterId': characterId,
    'sceneId': sceneId,
    'attempts': attempts,
    'lastSuccess': lastSuccess,
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory RepeatedCheckRecord.fromJson(Map<String, Object?> json) =>
      RepeatedCheckRecord(
        semanticKey: json['semanticKey'] as String? ?? '',
        characterId: json['characterId'] as String? ?? '',
        sceneId: json['sceneId'] as String? ?? '',
        attempts: (json['attempts'] as num?)?.toInt() ?? 0,
        lastSuccess: json['lastSuccess'] as bool? ?? false,
        updatedAt:
            DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
            DateTime.now(),
      );
}
