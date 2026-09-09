import 'dart:math';

import 'package:uuid/uuid.dart';

import '../../models/trpg_dice_models.dart';

class DiceFormulaParser {
  const DiceFormulaParser();
  static final _pattern = RegExp(
    r'^\s*(\d*)[dD](4|6|8|10|12|20|100)\s*([+-]\s*\d+)?\s*$',
  );

  DiceFormula parse(String source) {
    final match = _pattern.firstMatch(source);
    if (match == null) {
      throw const FormatException('骰子公式无效；支持 1D20、2D6、2D6+3、1D100+20');
    }
    final count = int.tryParse(match.group(1) ?? '') ?? 1;
    final sides = int.parse(match.group(2)!);
    final modifier =
        int.tryParse((match.group(3) ?? '0').replaceAll(' ', '')) ?? 0;
    if (count < 1 || count > 100) {
      throw const FormatException('骰子数量必须在 1～100 之间');
    }
    return DiceFormula(diceCount: count, sides: sides, modifier: modifier);
  }
}

class DiceRulePackage {
  const DiceRulePackage({required this.type});
  final DiceRulePackageType type;

  DiceSuccessLevel evaluate({
    required DiceFormula formula,
    required List<int> results,
    required int finalResult,
    int? difficulty,
  }) {
    if (difficulty == null) return DiceSuccessLevel.unopposed;
    final natural = results.length == 1 ? results.single : null;
    if (type == DiceRulePackageType.coc ||
        (formula.sides == 100 && type != DiceRulePackageType.holyGrailWar)) {
      if (natural != null && natural >= 96) {
        return DiceSuccessLevel.criticalFailure;
      }
      if (natural == 1) return DiceSuccessLevel.criticalSuccess;
      if (finalResult <= (difficulty / 5).floor()) {
        return DiceSuccessLevel.criticalSuccess;
      }
      if (finalResult <= (difficulty / 2).floor()) {
        return DiceSuccessLevel.greatSuccess;
      }
      return finalResult <= difficulty
          ? DiceSuccessLevel.success
          : DiceSuccessLevel.failure;
    }
    if (formula.sides == 20 && natural == 1) {
      return DiceSuccessLevel.criticalFailure;
    }
    if (formula.sides == 20 && natural == 20) {
      return DiceSuccessLevel.criticalSuccess;
    }
    if (finalResult >= difficulty + 10) return DiceSuccessLevel.greatSuccess;
    return finalResult >= difficulty
        ? DiceSuccessLevel.success
        : DiceSuccessLevel.failure;
  }
}

class DiceEngine {
  DiceEngine({Random? random, this.parser = const DiceFormulaParser()})
    : _random = random ?? Random.secure();

  static const _uuid = Uuid();
  final Random _random;
  final DiceFormulaParser parser;

  DiceRollResult roll({
    required String formula,
    required String playerId,
    String action = '手动投骰',
    String reason = '',
    String? characterId,
    int? difficulty,
    int extraModifier = 0,
    DiceRulePackageType rulePackage = DiceRulePackageType.genericD20,
    DiceVisibility visibility = DiceVisibility.public,
    List<String> ownerPlayerIds = const [],
    Map<String, Object?> metadata = const {},
  }) {
    final parsed = parser.parse(formula);
    final results = List.generate(
      parsed.diceCount,
      (_) => _random.nextInt(parsed.sides) + 1,
    );
    return evaluate(
      formula: parsed,
      individualResults: results,
      playerId: playerId,
      action: action,
      reason: reason,
      characterId: characterId,
      difficulty: difficulty,
      extraModifier: extraModifier,
      rulePackage: rulePackage,
      visibility: visibility,
      ownerPlayerIds: ownerPlayerIds,
      metadata: metadata,
    );
  }

  DiceRollResult evaluate({
    required DiceFormula formula,
    required List<int> individualResults,
    required String playerId,
    String action = '检定',
    String reason = '',
    String? characterId,
    int? difficulty,
    int extraModifier = 0,
    DiceRulePackageType rulePackage = DiceRulePackageType.genericD20,
    DiceVisibility visibility = DiceVisibility.public,
    List<String> ownerPlayerIds = const [],
    Map<String, Object?> metadata = const {},
  }) {
    if (individualResults.length != formula.diceCount ||
        individualResults.any((value) => value < 1 || value > formula.sides)) {
      throw ArgumentError('骰子结果与公式不匹配');
    }
    final base = individualResults.fold<int>(0, (sum, value) => sum + value);
    final modifier = formula.modifier + extraModifier;
    final finalResult = base + modifier;
    final level = DiceRulePackage(type: rulePackage).evaluate(
      formula: formula,
      results: individualResults,
      finalResult: finalResult,
      difficulty: difficulty,
    );
    return DiceRollResult(
      rollId: _uuid.v4(),
      playerId: playerId,
      diceFormula: DiceFormula(
        diceCount: formula.diceCount,
        sides: formula.sides,
        modifier: modifier,
      ).normalized,
      diceType: formula.diceType,
      individualResults: individualResults,
      baseResult: base,
      modifier: modifier,
      finalResult: finalResult,
      difficulty: difficulty,
      successLevel: level,
      timestamp: DateTime.now(),
      action: action,
      reason: reason,
      explanation: explain(
        formula: formula,
        results: individualResults,
        modifier: modifier,
        finalResult: finalResult,
        difficulty: difficulty,
        successLevel: level,
        reason: reason,
      ),
      characterId: characterId,
      rulePackage: rulePackage,
      visibility: visibility,
      ownerPlayerIds: ownerPlayerIds,
      metadata: metadata,
    );
  }

  DiceRollResult holyGrailNoblePhantasmCheck({
    required String playerId,
    required String rank,
    String reason = '判断宝具在当前环境中的发挥',
    int? difficulty,
  }) {
    const rankModifiers = {
      'E': 0,
      'D': 10,
      'C': 20,
      'B': 30,
      'A': 40,
      'EX': 60,
    };
    final modifier = rankModifiers[rank.toUpperCase()] ?? 20;
    return roll(
      formula: '1D100',
      playerId: playerId,
      action: '宝具判定',
      reason: reason,
      difficulty: difficulty,
      extraModifier: modifier,
      rulePackage: DiceRulePackageType.holyGrailWar,
      metadata: {
        'noblePhantasmRank': rank.toUpperCase(),
        'rankModifier': modifier,
      },
    );
  }

  String explain({
    required DiceFormula formula,
    required List<int> results,
    required int modifier,
    required int finalResult,
    required DiceSuccessLevel successLevel,
    int? difficulty,
    String reason = '',
  }) {
    final definition = DiceLibrary.bySides(formula.sides);
    final modifierText = modifier == 0
        ? '无修正'
        : '${modifier > 0 ? '+' : ''}$modifier';
    final dcText = difficulty == null ? '无固定难度' : '难度 $difficulty';
    return '${definition.displayName}投出 ${results.join('、')}；$modifierText；最终 $finalResult；$dcText；${successLevelLabel(successLevel)}。${reason.isEmpty ? '' : ' 原因：$reason'}';
  }

  static String successLevelLabel(DiceSuccessLevel level) => switch (level) {
    DiceSuccessLevel.criticalFailure => '大失败',
    DiceSuccessLevel.failure => '失败',
    DiceSuccessLevel.success => '成功',
    DiceSuccessLevel.greatSuccess => '卓越成功',
    DiceSuccessLevel.criticalSuccess => '大成功',
    DiceSuccessLevel.unopposed => '仅显示结果',
  };
}
