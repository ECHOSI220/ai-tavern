import 'dart:math';

import 'package:uuid/uuid.dart';

import '../../models/trpg_gameplay_models.dart';
import '../../models/trpg_models.dart';
import 'dice_engine.dart';
import 'trpg_rule_pack.dart';

class GrowthResolutionResult {
  const GrowthResolutionResult({required this.session, required this.entries});
  final TRPGSession session;
  final List<CharacterGrowthEntry> entries;
}

class GrowthResolver {
  GrowthResolver({DiceEngine? diceEngine, Random? random})
    : _dice = diceEngine ?? DiceEngine(random: random);

  final DiceEngine _dice;
  static const _uuid = Uuid();

  GrowthResolutionResult resolvePending(
    TRPGSession session, {
    String? characterId,
    bool sceneEnded = true,
  }) {
    if (!sceneEnded) {
      return GrowthResolutionResult(session: session, entries: const []);
    }
    var characters = [...session.playerCharacters];
    final candidates = [...session.ruleState.growthCandidates];
    final entries = <CharacterGrowthEntry>[];
    final package = session.ruleState.diceSettings.rulePackage;
    final rule = const TRPGRulePack().growthRule(package);

    for (var index = 0; index < candidates.length; index++) {
      final candidate = candidates[index];
      if (candidate.status != GrowthCandidateStatus.pending ||
          characterId != null && candidate.characterId != characterId) {
        continue;
      }
      final characterIndex = characters.indexWhere(
        (value) => value.id == candidate.characterId,
      );
      if (characterIndex < 0) {
        candidates[index] = candidate.copyWith(
          status: GrowthCandidateStatus.rejected,
        );
        continue;
      }
      final character = characters[characterIndex];
      final targetId = candidate.skillId ?? candidate.attributeId;
      if (targetId == null || candidate.growthType == GrowthType.trait) {
        continue;
      }
      final isAttribute = candidate.growthType == GrowthType.attribute;
      if (isAttribute && candidate.importance < 8) {
        candidates[index] = candidate.copyWith(
          status: GrowthCandidateStatus.rejected,
        );
        continue;
      }
      final before = isAttribute
          ? character.stats[targetId] ?? 10
          : character.skills[targetId] ?? 0;
      var succeeds = false;
      int? roll;
      if (rule.type == GrowthRuleType.rollOverCurrent) {
        roll = _dice
            .roll(
              formula: '1D100',
              playerId: character.playerId,
              characterId: character.id,
              action: '成长检定',
              reason: candidate.reason,
            )
            .baseResult;
        succeeds = roll > before.clamp(1, 95);
      } else {
        succeeds = candidate.importance >= (isAttribute ? 9 : 5);
      }
      candidates[index] = candidate.copyWith(
        status: succeeds
            ? GrowthCandidateStatus.resolved
            : GrowthCandidateStatus.rejected,
      );
      if (!succeeds) continue;
      final increase = isAttribute
          ? rule.attributeIncrease
          : rule.skillIncreaseMin + (candidate.importance >= 8 ? 1 : 0);
      final max = isAttribute
          ? TRPGRulePack.attributes[targetId]?.max ?? 30
          : TRPGRulePack.skills[targetId]?.max ?? 100;
      final after = (before + increase).clamp(0, max);
      characters[characterIndex] = isAttribute
          ? character.copyWith(stats: {...character.stats, targetId: after})
          : character.copyWith(skills: {...character.skills, targetId: after});
      entries.add(
        CharacterGrowthEntry(
          id: _uuid.v4(),
          characterId: character.id,
          targetId: targetId,
          growthType: candidate.growthType,
          before: before,
          after: after,
          reason: candidate.reason,
          roll: roll,
          ruleType: rule.type,
          createdAt: DateTime.now(),
        ),
      );
    }
    return GrowthResolutionResult(
      session: session.copyWith(
        playerCharacters: characters,
        ruleState: session.ruleState.copyWith(
          growthCandidates: candidates,
          growthHistory: [...session.ruleState.growthHistory, ...entries],
        ),
        updatedAt: DateTime.now(),
      ),
      entries: entries,
    );
  }

  /// Tool/API callers cannot mutate numbers without a resolved, matching entry.
  TRPGSession applyValidatedGrowth({
    required TRPGSession session,
    required String growthEntryId,
  }) {
    final entry = session.ruleState.growthHistory
        .where((value) => value.id == growthEntryId)
        .firstOrNull;
    if (entry == null) throw StateError('属性或技能修改被拒绝：没有合法成长结算');
    return session;
  }
}
