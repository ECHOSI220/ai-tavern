import 'dart:math';

import 'package:ai_tavern/models/trpg_dice_models.dart';
import 'package:ai_tavern/models/trpg_models.dart';
import 'package:ai_tavern/services/trpg/dice_animation_controller.dart';
import 'package:ai_tavern/services/trpg/dice_engine.dart';
import 'package:ai_tavern/services/trpg/dice_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const parser = DiceFormulaParser();

  test('1 D20 点数始终在 1 到 20', () {
    final engine = DiceEngine(random: Random(42));
    for (var i = 0; i < 200; i++) {
      final result = engine.roll(formula: '1D20', playerId: 'p1');
      expect(result.finalResult, inInclusiveRange(1, 20));
    }
  });

  test('2 D100 支持 COC 百分检定', () {
    final result = DiceEngine().evaluate(
      formula: parser.parse('1D100'),
      individualResults: const [20],
      playerId: 'p1',
      difficulty: 50,
      rulePackage: DiceRulePackageType.coc,
    );
    expect(result.successLevel, DiceSuccessLevel.greatSuccess);
  });

  test('3 2D6+3 公式解析与计算正确', () {
    final formula = parser.parse('2d6 + 3');
    final result = DiceEngine().evaluate(
      formula: formula,
      individualResults: const [2, 5],
      playerId: 'p1',
    );
    expect(formula.normalized, '2D6+3');
    expect(result.baseResult, 7);
    expect(result.finalResult, 10);
    expect(formula.explanation, contains('最后增加3点'));
  });

  test('4 D20 自然 20 是大成功', () {
    final result = DiceEngine().evaluate(
      formula: parser.parse('1D20'),
      individualResults: const [20],
      playerId: 'p1',
      difficulty: 25,
    );
    expect(result.successLevel, DiceSuccessLevel.criticalSuccess);
  });

  test('5 D20 自然 1 是大失败', () {
    final result = DiceEngine().evaluate(
      formula: parser.parse('1D20+99'),
      individualResults: const [1],
      playerId: 'p1',
      difficulty: 5,
    );
    expect(result.successLevel, DiceSuccessLevel.criticalFailure);
  });

  test('6 多人私骰只对投骰玩家与 GM 可见', () {
    final result = DiceEngine().roll(
      formula: '1D20',
      playerId: 'player-a',
      visibility: DiceVisibility.playerPrivate,
      ownerPlayerIds: const ['player-a'],
    );
    final restored = DiceRollResult.fromJson(result.toJson());
    expect(restored.visibleTo('player-a'), isTrue);
    expect(restored.visibleTo('player-b'), isFalse);
    expect(restored.visibleTo('player-b', isGm: true), isTrue);
  });

  test('7 圣杯战争 A 级宝具获得 +40 修正', () {
    final result = DiceService(random: Random(7)).holyGrailNoblePhantasmCheck(
      playerId: 'master-a',
      rank: 'A',
      difficulty: 80,
    );
    expect(result.diceType, 'D100');
    expect(result.modifier, 40);
    expect(result.metadata['rankModifier'], 40);
    expect(result.rulePackage, DiceRulePackageType.holyGrailWar);
  });

  test('8 骰子历史与设置可保存加载', () {
    final result = DiceEngine().evaluate(
      formula: parser.parse('1D20'),
      individualResults: const [12],
      playerId: 'p1',
    );
    const settings = DiceSettings(
      animationEnabled: false,
      soundEnabled: false,
      tutorialShown: true,
      rulePackage: DiceRulePackageType.dnd,
    );
    final restored = RuleState.fromJson(
      RuleState(diceHistory2: [result], diceSettings: settings).toJson(),
    );
    expect(restored.diceHistory2.single.finalResult, 12);
    expect(restored.diceSettings.animationEnabled, isFalse);
    expect(restored.diceSettings.rulePackage, DiceRulePackageType.dnd);
  });

  test('9 投骰历史最多保留最近 50 条', () {
    final now = DateTime.now();
    var session = TRPGSession(
      id: 's',
      title: '骰子测试',
      mode: TRPGMode.solo,
      createdAt: now,
      updatedAt: now,
      lastPlayedAt: now,
      campaignId: 'c',
      players: [TRPGPlayer(playerId: 'p1', displayName: '玩家', joinedAt: now)],
    );
    final dice = DiceService(random: Random(1));
    for (var index = 0; index < 55; index++) {
      final result = dice.rollResult(formula: '1D6', playerId: 'p1');
      session = dice.recordResult(session, result);
    }
    expect(session.ruleState.diceHistory2, hasLength(50));
  });

  test('10 动画控制器可快速完成并显示最终点数', () async {
    final result = DiceEngine().evaluate(
      formula: parser.parse('1D20'),
      individualResults: const [18],
      playerId: 'p1',
    );
    final controller = DiceAnimationController();
    await controller.play(
      result,
      const DiceSettings(soundEnabled: false, hapticsEnabled: false),
      phaseDuration: Duration.zero,
      rollingDuration: const Duration(milliseconds: 5),
    );
    expect(controller.phase, DiceAnimationPhase.result);
    expect(controller.displayNumber, 18);
    controller.dispose();
  });
}
