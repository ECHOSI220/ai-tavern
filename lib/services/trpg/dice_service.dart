import 'dart:math';

import 'package:uuid/uuid.dart';

import '../../models/trpg_models.dart';
import '../../models/trpg_dice_models.dart';
import 'dice_engine.dart';

class DiceService {
  DiceService({Random? random})
    : _engine = DiceEngine(random: random ?? Random.secure());

  final DiceEngine _engine;
  static const supportedSides = [4, 6, 8, 10, 12, 20, 100];

  DiceRoll roll({
    required int sides,
    required String playerId,
    int count = 1,
    int modifier = 0,
    String? characterId,
    String? turnId,
    String? actionId,
  }) {
    if (!supportedSides.contains(sides)) {
      throw ArgumentError('unsupported dice');
    }
    if (count < 1 || count > 100) throw ArgumentError('invalid dice count');
    final result = _engine.roll(
      formula:
          '${count}D$sides${modifier == 0
              ? ''
              : modifier > 0
              ? '+$modifier'
              : '$modifier'}',
      playerId: playerId,
      characterId: characterId,
      metadata: {'turnId': turnId, 'actionId': actionId},
    );
    return DiceRoll(
      diceType: 'D$sides',
      count: count,
      rolls: result.individualResults,
      modifier: modifier,
      total: result.finalResult,
      playerId: playerId,
      timestamp: DateTime.now(),
      characterId: characterId,
      turnId: turnId,
      actionId: actionId,
    );
  }

  DiceRollResult rollResult({
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
  }) => _engine.roll(
    formula: formula,
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

  DiceRollResult holyGrailNoblePhantasmCheck({
    required String playerId,
    required String rank,
    String reason = '判断宝具在当前环境中的发挥',
    int? difficulty,
  }) => _engine.holyGrailNoblePhantasmCheck(
    playerId: playerId,
    rank: rank,
    reason: reason,
    difficulty: difficulty,
  );

  TRPGSession record(
    TRPGSession session,
    DiceRoll roll, {
    String reason = 'manual_roll',
  }) {
    final formula = DiceFormula(
      diceCount: roll.count,
      sides:
          int.tryParse(roll.diceType.replaceAll(RegExp(r'[^0-9]'), '')) ?? 20,
      modifier: roll.modifier,
    );
    final result = _engine.evaluate(
      formula: formula,
      individualResults: roll.rolls,
      playerId: roll.playerId,
      action: reason == 'manual_roll' ? '手动投骰' : reason,
      reason: reason,
      characterId: roll.characterId,
      metadata: {'turnId': roll.turnId, 'actionId': roll.actionId},
    );
    return recordResult(session, result, legacyRoll: roll);
  }

  TRPGSession recordResult(
    TRPGSession session,
    DiceRollResult result, {
    DiceRoll? legacyRoll,
  }) {
    final now = DateTime.now();
    final history = [...session.ruleState.diceHistory2, result];
    final oldHistory = legacyRoll == null
        ? session.ruleState.diceHistory
        : [...session.ruleState.diceHistory, legacyRoll];
    final definition = DiceLibrary.bySides(
      int.tryParse(result.diceType.substring(1)) ?? 20,
    );
    final modifier = result.modifier == 0
        ? '无修正'
        : '${result.modifier > 0 ? '+' : ''}${result.modifier}';
    final difficulty = result.difficulty == null
        ? '无固定难度'
        : '${result.difficulty}';
    return session.copyWith(
      ruleState: session.ruleState.copyWith(
        diceHistory: oldHistory.length > 50
            ? oldHistory.sublist(oldHistory.length - 50)
            : oldHistory,
        diceHistory2: history.length > 50
            ? history.sublist(history.length - 50)
            : history,
      ),
      chatHistory: [
        ...session.chatHistory,
        TRPGMessage(
          id: const Uuid().v4(),
          messageType: TRPGMessageType.diceMessage,
          content:
              '【${result.action}】\n'
              '骰子：${definition.displayName}\n'
              '结果：${result.individualResults.join('、')}\n'
              '修正：$modifier\n'
              '最终：${result.finalResult}\n'
              '难度：$difficulty\n'
              '判定：${DiceEngine.successLevelLabel(result.successLevel)}\n'
              '说明：${result.explanation}',
          playerId: result.playerId,
          createdAt: now,
        ),
      ],
      eventLog: [
        ...session.eventLog,
        TRPGEvent(
          id: const Uuid().v4(),
          type: TRPGEventType.diceRoll,
          actorId: result.playerId,
          timestamp: now,
          payload: {
            ...result.toJson(),
            'diceResult': result.toJson(),
            'result': result.finalResult,
            'total': result.finalResult,
          },
          // Manual dice remain entertainment-only unless a formal skill check
          // explicitly consumes a program-generated result.
          visibleToAi: true,
        ),
      ],
      updatedAt: now,
      lastPlayedAt: now,
    );
  }
}
