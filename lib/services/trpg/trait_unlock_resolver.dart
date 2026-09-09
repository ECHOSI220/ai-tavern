import '../../models/trpg_gameplay_models.dart';
import '../../models/trpg_models.dart';

/// Rule-owned trait progress. AI narration cannot create or unlock traits.
class TraitUnlockResolver {
  const TraitUnlockResolver();

  List<CharacterTrait> applyCheck(
    TRPGSession session,
    ActionCheckResult check,
  ) {
    final traits = [...session.ruleState.traits];
    if (!_isCharacterMoment(check)) return traits;

    const traitId = 'calm_under_pressure';
    final index = traits.indexWhere(
      (value) => value.characterId == check.characterId && value.id == traitId,
    );
    if (index < 0) {
      traits.add(
        CharacterTrait(
          id: traitId,
          characterId: check.characterId,
          name: '冷静判断',
          description: '在两次关键危机中依然坚持理性判断。',
          effect: 'check:insight:+1',
          progress: 1,
          target: 2,
          unlockedAt: DateTime.now(),
        ),
      );
      return traits;
    }
    final current = traits[index];
    if (!current.unlocked) {
      traits[index] = current.copyWith(
        progress: (current.progress + 1).clamp(0, current.target),
      );
    }
    return traits;
  }

  bool _isCharacterMoment(ActionCheckResult check) =>
      check.successLevel == ActionOutcomeLevel.criticalSuccess ||
      check.successLevel == ActionOutcomeLevel.criticalFailure ||
      (check.margin.abs() >= 8 &&
          check.successLevel != ActionOutcomeLevel.blocked);
}
