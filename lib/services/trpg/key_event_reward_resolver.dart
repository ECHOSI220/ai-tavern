import 'package:uuid/uuid.dart';

import '../../models/trpg_gameplay_models.dart';

class KeyEventRewardResolver {
  const KeyEventRewardResolver();
  static const _uuid = Uuid();

  PlayerResolution? fromCheck(
    ActionCheckResult check, {
    required bool growthCandidateCreated,
    String? traitUpdate,
  }) {
    final key =
        check.successLevel == ActionOutcomeLevel.criticalSuccess ||
        check.successLevel == ActionOutcomeLevel.greatSuccess ||
        check.margin.abs() >= 5;
    if (!key && !growthCandidateCreated && traitUpdate == null) return null;
    final entries = <String>[
      '${check.reason}：${ActionCheckResult.successLevelLabel(check.successLevel)}（差值 ${check.margin >= 0 ? '+' : ''}${check.margin}）',
      if (growthCandidateCreated)
        '获得成长候选：${check.skillId ?? check.attributeId}',
    ];
    entries.addAll(<String?>[traitUpdate].whereType<String>());
    return PlayerResolution(
      id: _uuid.v4(),
      playerIds: [check.playerId],
      title: '本次关键行动结算',
      entries: entries,
      visibility: check.visibility == RollVisibility.public
          ? ResolutionVisibility.public
          : ResolutionVisibility.playerPrivate,
      createdAt: DateTime.now(),
      sourceEventId: check.checkId,
    );
  }
}
