import 'dart:math';

import 'package:uuid/uuid.dart';

import '../../models/trpg_dice_models.dart';
import '../../models/trpg_gameplay_models.dart';
import '../../models/trpg_models.dart';
import 'action_check_analyzer.dart';
import 'dice_engine.dart';
import 'key_event_reward_resolver.dart';
import 'trait_unlock_resolver.dart';
import 'trpg_rule_pack.dart';

class CheckPipelineOutcome {
  const CheckPipelineOutcome({
    required this.session,
    this.decision,
    this.result,
  });
  final TRPGSession session;
  final ActionCheckDecision? decision;
  final ActionCheckResult? result;
}

class GroupCheckOutcome {
  const GroupCheckOutcome({
    required this.session,
    required this.individual,
    this.partyResolution,
  });
  final TRPGSession session;
  final List<CheckPipelineOutcome> individual;
  final PlayerResolution? partyResolution;
}

class TRPGCheckPipeline {
  TRPGCheckPipeline({
    this.analyzer = const ActionCheckAnalyzer(),
    TRPGRulePack rulePack = const TRPGRulePack(),
    DiceEngine? diceEngine,
    this.rewards = const KeyEventRewardResolver(),
    this.traitResolver = const TraitUnlockResolver(),
    Random? random,
  }) : _rules = rulePack,
       _dice = diceEngine ?? DiceEngine(random: random);

  final ActionCheckAnalyzer analyzer;
  final TRPGRulePack _rules;
  final DiceEngine _dice;
  final KeyEventRewardResolver rewards;
  final TraitUnlockResolver traitResolver;
  static const _uuid = Uuid();

  CheckPipelineOutcome resolveAction({
    required TRPGSession session,
    required String action,
    required String actionId,
    String? playerId,
    String? characterId,
    String? targetId,
    String? turnId,
    RollVisibility? visibilityOverride,
  }) {
    if (session.ruleState.checkHistory.any(
      (value) => value.actionId == actionId,
    )) {
      return CheckPipelineOutcome(session: session);
    }
    final character = _findCharacter(session, playerId, characterId);
    if (character == null) return CheckPipelineOutcome(session: session);
    var decision = _rules.validate(
      analyzer.analyze(
        action: action,
        session: session,
        character: character,
        targetId: targetId,
      ),
    );
    if (visibilityOverride != null && decision.requiresCheck) {
      decision = ActionCheckDecision.fromJson({
        ...decision.toJson(),
        'visibility': visibilityOverride.name,
        if (visibilityOverride == RollVisibility.gmHidden)
          'presentationMode': DicePresentationMode.none.name,
      });
    }
    if (!decision.requiresCheck) {
      return CheckPipelineOutcome(session: session, decision: decision);
    }
    final modifiers = _resolveModifiers(session, character, decision);
    final repeated = _repeatRecord(session, character, decision);
    final hasNewApproach = _hasNewApproach(action);
    if (repeated != null && !repeated.lastSuccess && !hasNewApproach) {
      final blocked = _blockedResult(
        decision: decision,
        character: character,
        actionId: actionId,
        turnId: turnId,
        modifiers: modifiers,
      );
      return CheckPipelineOutcome(
        session: _record(
          session,
          blocked,
          decision,
          repeated: repeated.copyWith(attempts: repeated.attempts + 1),
        ),
        decision: decision,
        result: blocked,
      );
    }

    final package = session.ruleState.diceSettings.rulePackage;
    final isD100 = decision.suggestedDiceFormula.toUpperCase().contains('D100');
    final totalModifier = modifiers.fold<int>(
      0,
      (sum, value) => sum + value.value,
    );
    final effectiveDifficulty = isD100
        ? _d100Target(character, decision, modifiers)
        : (decision.difficulty ?? 12) +
              (repeated != null &&
                      decision.repeatedCheckPolicy ==
                          RepeatedCheckPolicy.increaseDifficulty
                  ? repeated.attempts * 2
                  : 0);
    final visibility = _diceVisibility(decision.visibility);
    final owners = decision.visibility == RollVisibility.public
        ? const <String>[]
        : [character.playerId];

    final passive = decision.checkType == ActionCheckType.passive;
    final automatic =
        !passive &&
        decision.riskLevel == ActionRiskLevel.low &&
        (isD100
            ? effectiveDifficulty >= 80
            : 10 + totalModifier >= effectiveDifficulty + 5);
    late final int base;
    late final int finalValue;
    late final List<int> individual;
    DiceRollResult? diceResult;
    if (passive || automatic) {
      base = isD100 ? (automatic ? 1 : 50) : 10;
      finalValue = isD100
          ? (automatic ? max(1, effectiveDifficulty - 10) : base)
          : base + totalModifier;
      individual = const [];
    } else {
      diceResult = _dice.roll(
        formula: decision.suggestedDiceFormula,
        playerId: character.playerId,
        characterId: character.id,
        action: decision.reason,
        reason: decision.reason,
        difficulty: effectiveDifficulty,
        extraModifier: isD100 ? 0 : totalModifier,
        rulePackage: package,
        visibility: visibility,
        ownerPlayerIds: owners,
        metadata: {
          'actionId': actionId,
          'turnId': turnId ?? actionId,
          'checkType': decision.checkType.name,
          'attributeId': decision.attributeId,
          'skillId': decision.skillId,
          'presentationMode': decision.presentationMode.name,
          'modifierSources': modifiers.map((value) => value.toJson()).toList(),
        },
      );
      base = diceResult.baseResult;
      finalValue = diceResult.finalResult;
      individual = diceResult.individualResults;
    }
    var margin = isD100
        ? effectiveDifficulty - finalValue
        : finalValue - effectiveDifficulty;
    int? opposedResult;
    if (decision.checkType == ActionCheckType.opposed) {
      opposedResult = _opposedTargetRoll(session, decision, d100: isD100);
      margin = isD100 ? opposedResult - finalValue : finalValue - opposedResult;
    }
    final level = automatic
        ? ActionOutcomeLevel.automaticSuccess
        : _outcome(
            natural: individual.firstOrNull,
            margin: margin,
            d100: isD100,
            risk: decision.riskLevel,
          );
    final check = ActionCheckResult(
      checkId: diceResult?.rollId ?? _uuid.v4(),
      turnId: turnId ?? actionId,
      actionId: actionId,
      playerId: character.playerId,
      characterId: character.id,
      checkType: decision.checkType,
      attributeId: decision.attributeId,
      skillId: decision.skillId,
      targetId: decision.targetId,
      diceFormula: passive ? 'PASSIVE' : decision.suggestedDiceFormula,
      individualRolls: individual,
      baseRoll: base,
      modifierSources: modifiers,
      difficulty: effectiveDifficulty,
      finalResult: finalValue,
      successLevel: level,
      margin: margin,
      visibility: decision.visibility,
      presentationMode: decision.presentationMode,
      reason: decision.reason,
      opposedResult: opposedResult,
      createdAt: DateTime.now(),
    );
    final record = RepeatedCheckRecord(
      semanticKey: decision.semanticKey,
      characterId: character.id,
      sceneId: session.worldState.currentScene.sceneId,
      attempts: (repeated?.attempts ?? 0) + 1,
      lastSuccess: _successful(level),
      updatedAt: DateTime.now(),
    );
    return CheckPipelineOutcome(
      session: _record(
        session,
        check,
        decision,
        diceResult: diceResult,
        repeated: record,
      ),
      decision: decision,
      result: check,
    );
  }

  GroupCheckOutcome resolveGroup({
    required TRPGSession session,
    required Map<String, String> actionsByPlayer,
    required String turnId,
    Map<String, String> actionIdsByPlayer = const {},
    Map<String, String> characterIdsByPlayer = const {},
    Map<String, String> targetIdsByPlayer = const {},
    Map<String, RollVisibility> visibilityByPlayer = const {},
  }) {
    var current = session;
    final results = <CheckPipelineOutcome>[];
    final helpers = actionsByPlayer.entries.where(
      (entry) => _isHelpAction(entry.value),
    );
    final leaders = actionsByPlayer.entries.where(
      (entry) => !_isHelpAction(entry.value),
    );
    var successfulHelpers = 0;
    for (final entry in helpers) {
      final outcome = resolveAction(
        session: current,
        action: entry.value,
        actionId: actionIdsByPlayer[entry.key] ?? '$turnId-${entry.key}',
        playerId: entry.key,
        characterId: characterIdsByPlayer[entry.key],
        targetId: targetIdsByPlayer[entry.key],
        turnId: turnId,
        visibilityOverride: visibilityByPlayer[entry.key],
      );
      current = outcome.session;
      results.add(outcome);
      if (outcome.result != null &&
          outcome.result!.visibility == RollVisibility.public &&
          _successful(outcome.result!.successLevel)) {
        successfulHelpers++;
      }
    }
    final originalModifiers = current.ruleState.temporaryModifiers;
    if (successfulHelpers > 0) {
      final existing = (originalModifiers['all'] as num?)?.toInt() ?? 0;
      current = current.copyWith(
        ruleState: current.ruleState.copyWith(
          temporaryModifiers: {
            ...originalModifiers,
            'all': existing + successfulHelpers * 2,
          },
        ),
      );
    }
    for (final entry in leaders) {
      final outcome = resolveAction(
        session: current,
        action: entry.value,
        actionId: actionIdsByPlayer[entry.key] ?? '$turnId-${entry.key}',
        playerId: entry.key,
        characterId: characterIdsByPlayer[entry.key],
        targetId: targetIdsByPlayer[entry.key],
        turnId: turnId,
        visibilityOverride: visibilityByPlayer[entry.key],
      );
      current = outcome.session;
      results.add(outcome);
    }
    current = current.copyWith(
      ruleState: current.ruleState.copyWith(
        temporaryModifiers: originalModifiers,
      ),
    );
    final checked = results
        .map((value) => value.result)
        .nonNulls
        .where((value) => value.visibility == RollVisibility.public)
        .toList();
    if (checked.length < 2) {
      return GroupCheckOutcome(session: current, individual: results);
    }
    final successes = checked
        .where((value) => _successful(value.successLevel))
        .length;
    final partyResolution = PlayerResolution(
      id: _uuid.v4(),
      playerIds: checked.map((value) => value.playerId).toSet().toList(),
      title: '队伍共同检定',
      entries: [
        '参与 ${checked.length} 人，成功 $successes 人',
        successfulHelpers > 0
            ? '成功协助 $successfulHelpers 人，主行动获得 +${successfulHelpers * 2}'
            : '本次没有获得协助加成',
        successes * 2 >= checked.length ? '队伍成功' : '队伍未成功',
      ],
      visibility: ResolutionVisibility.party,
      createdAt: DateTime.now(),
      sourceEventId: turnId,
    );
    current = current.copyWith(
      ruleState: current.ruleState.copyWith(
        privateResolutions: [
          ...current.ruleState.privateResolutions,
          partyResolution,
        ],
      ),
    );
    return GroupCheckOutcome(
      session: current,
      individual: results,
      partyResolution: partyResolution,
    );
  }

  PlayerCharacter? _findCharacter(
    TRPGSession session,
    String? playerId,
    String? characterId,
  ) {
    if (characterId != null) {
      return session.playerCharacters
          .where((value) => value.id == characterId)
          .firstOrNull;
    }
    final resolvedPlayer = playerId ?? session.players.firstOrNull?.playerId;
    return session.playerCharacters
            .where((value) => value.playerId == resolvedPlayer)
            .firstOrNull ??
        session.playerCharacters.firstOrNull;
  }

  List<ModifierSource> _resolveModifiers(
    TRPGSession session,
    PlayerCharacter character,
    ActionCheckDecision decision,
  ) {
    final result = <ModifierSource>[];
    final statValue = (character.stats[decision.attributeId] ?? 10).toInt();
    result.add(
      ModifierSource(
        id: decision.attributeId ?? 'attribute',
        label:
            TRPGRulePack.attributes[decision.attributeId]?.name ??
            decision.attributeId ??
            '属性',
        value: ((statValue - 10) / 2).floor(),
        category: 'attribute',
        detail: '属性值 $statValue',
      ),
    );
    if (decision.skillId case final skillId?) {
      final skillValue = (character.skills[skillId] ?? 0).toInt();
      final skillModifier = skillValue <= 10
          ? skillValue
          : ((skillValue - 30) / 10).floor().clamp(-2, 7);
      result.add(
        ModifierSource(
          id: skillId,
          label: TRPGRulePack.skills[skillId]?.name ?? skillId,
          value: skillModifier,
          category: 'skill',
          detail: '技能值 $skillValue',
        ),
      );
    }
    for (final item in character.inventoryItems.where(
      (value) =>
          character.equipment.contains(value.id) ||
          character.equipment.contains(value.name),
    )) {
      final map = item.metadata['checkModifiers'];
      final raw = map is Map
          ? map[decision.skillId] ?? map[decision.attributeId] ?? map['all']
          : item.metadata['checkModifier'];
      final value = (raw as num?)?.toInt() ?? 0;
      if (value != 0) {
        result.add(
          ModifierSource(
            id: item.id,
            label: item.name,
            value: value,
            category: 'equipment',
          ),
        );
      }
    }
    for (final status in character.structuredStatusEffects) {
      final map = status.metadata['checkModifiers'];
      final raw = map is Map
          ? map[decision.skillId] ?? map[decision.attributeId] ?? map['all']
          : status.metadata['checkModifier'];
      final value = (raw as num?)?.toInt() ?? 0;
      if (value != 0) {
        result.add(
          ModifierSource(
            id: status.id,
            label: status.name,
            value: value,
            category: 'status',
          ),
        );
      }
    }
    final temporary = session.ruleState.temporaryModifiers;
    final environment =
        (temporary[decision.skillId] ??
                temporary[decision.attributeId] ??
                temporary['all'])
            as num?;
    if (environment != null && environment != 0) {
      result.add(
        ModifierSource(
          id: 'environment',
          label: '环境',
          value: environment.toInt(),
          category: 'environment',
        ),
      );
    }
    final target = session.worldState.npcs
        .where((value) => value.npcId == decision.targetId)
        .firstOrNull;
    if (target != null &&
        const [
          'persuasion',
          'insight',
          'deception',
          'intimidation',
        ].contains(decision.skillId)) {
      final relation = (target.relationship / 20).truncate().clamp(-5, 5);
      if (relation != 0) {
        result.add(
          ModifierSource(
            id: target.npcId,
            label: '${target.name}的关系',
            value: relation,
            category: 'relationship',
          ),
        );
      }
    }
    for (final trait in session.ruleState.traits.where(
      (value) => value.characterId == character.id && value.unlocked,
    )) {
      final parts = trait.effect.split(':');
      if (parts.length == 3 &&
          parts[0] == 'check' &&
          (parts[1] == decision.skillId || parts[1] == 'all')) {
        final value = int.tryParse(parts[2]) ?? 0;
        if (value != 0) {
          result.add(
            ModifierSource(
              id: trait.id,
              label: trait.name,
              value: value,
              category: 'trait',
              detail: trait.description,
            ),
          );
        }
      }
    }
    _addHolyGrailModifier(session, character, decision, result);
    return result;
  }

  void _addHolyGrailModifier(
    TRPGSession session,
    PlayerCharacter character,
    ActionCheckDecision decision,
    List<ModifierSource> result,
  ) {
    if (!session.holyGrailState.initialized) return;
    final master = session.holyGrailState.masters
        .where(
          (value) =>
              value.ownerPlayerId == character.playerId ||
              value.characterId == character.id,
        )
        .firstOrNull;
    final servant = master == null
        ? null
        : session.holyGrailState.servants
              .where((value) => value.masterId == master.masterId)
              .firstOrNull;
    if (servant == null) return;
    final rank = _rules.servantRankFor(servant.parameters, decision.skillId);
    if (rank == null) return;
    result.add(
      ModifierSource(
        id: 'servant-${rank.name}',
        label: '从者${_rankName(decision.skillId)} ${rank.name.toUpperCase()}',
        value: _rules.rankModifier(rank),
        category: 'holyGrailRank',
      ),
    );
  }

  int _d100Target(
    PlayerCharacter character,
    ActionCheckDecision decision,
    List<ModifierSource> modifiers,
  ) {
    final skill = (character.skills[decision.skillId] ?? 0).toInt();
    final stat = (character.stats[decision.attributeId] ?? 10).toInt();
    final base = skill > 10 ? skill : stat * 5 + skill * 5;
    final riskAdjustment = switch (decision.riskLevel) {
      ActionRiskLevel.none => 20,
      ActionRiskLevel.low => 10,
      ActionRiskLevel.medium => 0,
      ActionRiskLevel.high => -15,
      ActionRiskLevel.critical => -30,
    };
    // 属性和技能已经组成 D100 的基础成功率，不能再二次叠加。
    final situational = modifiers
        .where(
          (value) => value.category != 'attribute' && value.category != 'skill',
        )
        .fold<int>(0, (sum, value) => sum + value.value);
    return (base + situational * 5 + riskAdjustment).clamp(5, 95);
  }

  int _opposedTargetRoll(
    TRPGSession session,
    ActionCheckDecision decision, {
    required bool d100,
  }) {
    final target = session.worldState.npcs
        .where((value) => value.npcId == decision.targetId)
        .firstOrNull;
    final modifier = target == null
        ? 2
        : (target.hp / max(1, target.maxHp) * 4).round() +
              (target.relationship < 0 ? 2 : 0);
    return _dice
        .roll(
          formula: d100 ? '1D100' : '1D20',
          playerId: 'gm',
          action: '对抗检定',
          extraModifier: modifier,
          visibility: DiceVisibility.gmOnly,
        )
        .finalResult;
  }

  ActionOutcomeLevel _outcome({
    required int? natural,
    required int margin,
    required bool d100,
    required ActionRiskLevel risk,
  }) {
    if ((!d100 && natural == 1) || (d100 && natural != null && natural >= 96)) {
      return ActionOutcomeLevel.criticalFailure;
    }
    if ((!d100 && natural == 20) || (d100 && natural == 1)) {
      return ActionOutcomeLevel.criticalSuccess;
    }
    if (margin >= 10) return ActionOutcomeLevel.greatSuccess;
    if (margin >= 0) return ActionOutcomeLevel.success;
    if (margin >= -2 && risk != ActionRiskLevel.critical) {
      return ActionOutcomeLevel.partialSuccess;
    }
    return ActionOutcomeLevel.failure;
  }

  TRPGSession _record(
    TRPGSession session,
    ActionCheckResult result,
    ActionCheckDecision decision, {
    DiceRollResult? diceResult,
    RepeatedCheckRecord? repeated,
  }) {
    final visibilityIds = switch (result.visibility) {
      RollVisibility.public => const <String>[],
      RollVisibility.playerPrivate => [result.playerId],
      RollVisibility.gmHidden => const ['__gm__'],
    };
    final event = TRPGEvent(
      id: _uuid.v4(),
      type: TRPGEventType.skillCheck,
      timestamp: DateTime.now(),
      actorId: result.playerId,
      payload: {
        'actionId': result.actionId,
        'checkId': result.checkId,
        'decision': decision.toJson(),
        'result': result.toJson(),
        'explanation': result.displayExplanation,
        'visibility': result.visibility.name,
        'visibilityPlayerIds': visibilityIds,
      },
    );
    final candidates = [...session.ruleState.growthCandidates];
    var candidateCreated = false;
    final important =
        result.successLevel == ActionOutcomeLevel.criticalSuccess ||
        result.successLevel == ActionOutcomeLevel.greatSuccess ||
        decision.riskLevel == ActionRiskLevel.high ||
        decision.riskLevel == ActionRiskLevel.critical;
    final growthTarget = result.skillId ?? result.attributeId;
    final sceneId = session.worldState.currentScene.sceneId;
    final alreadyCandidate = candidates.any(
      (value) =>
          value.characterId == result.characterId &&
          value.sceneId == sceneId &&
          (value.skillId ?? value.attributeId) == growthTarget,
    );
    if (important &&
        growthTarget != null &&
        !alreadyCandidate &&
        result.successLevel != ActionOutcomeLevel.blocked) {
      candidates.add(
        GrowthCandidate(
          candidateId: _uuid.v4(),
          characterId: result.characterId,
          sourceEventId: event.id,
          skillId: result.skillId,
          attributeId: result.skillId == null ? result.attributeId : null,
          reason: result.reason,
          difficulty: result.difficulty,
          importance:
              decision.riskLevel.index * 2 + (result.margin.abs() >= 5 ? 2 : 0),
          growthType: result.skillId != null
              ? GrowthType.skill
              : GrowthType.attribute,
          sceneId: sceneId,
          createdAt: DateTime.now(),
        ),
      );
      candidateCreated = true;
    }
    final traits = traitResolver.applyCheck(session, result);
    String? traitUpdate;
    if (traits.length > session.ruleState.traits.length) {
      final trait = traits.last;
      traitUpdate = '特质进度：${trait.name} ${trait.progress}/${trait.target}';
    } else {
      for (final trait in traits) {
        final previous = session.ruleState.traits
            .where(
              (value) =>
                  value.id == trait.id &&
                  value.characterId == trait.characterId,
            )
            .firstOrNull;
        if (previous != null && previous.progress != trait.progress) {
          traitUpdate = trait.unlocked
              ? '解锁特质：${trait.name}（${trait.description}）'
              : '特质进度：${trait.name} ${trait.progress}/${trait.target}';
          break;
        }
      }
    }
    final resolution = rewards.fromCheck(
      result,
      growthCandidateCreated: candidateCreated,
      traitUpdate: traitUpdate,
    );
    final repeats = [...session.ruleState.repeatedChecks]
      ..removeWhere(
        (value) =>
            value.semanticKey == repeated?.semanticKey &&
            value.characterId == repeated?.characterId,
      );
    if (repeated != null) repeats.add(repeated);
    return session.copyWith(
      ruleState: session.ruleState.copyWith(
        diceHistory2: diceResult == null
            ? null
            : [...session.ruleState.diceHistory2, diceResult],
        checkHistory: [...session.ruleState.checkHistory, result],
        growthCandidates: candidates,
        privateResolutions: resolution == null
            ? null
            : [...session.ruleState.privateResolutions, resolution],
        traits: traits,
        repeatedChecks: repeats,
      ),
      eventLog: [...session.eventLog, event],
      updatedAt: DateTime.now(),
    );
  }

  RepeatedCheckRecord? _repeatRecord(
    TRPGSession session,
    PlayerCharacter character,
    ActionCheckDecision decision,
  ) => session.ruleState.repeatedChecks
      .where(
        (value) =>
            value.semanticKey == decision.semanticKey &&
            value.characterId == character.id &&
            value.sceneId == session.worldState.currentScene.sceneId,
      )
      .firstOrNull;

  ActionCheckResult _blockedResult({
    required ActionCheckDecision decision,
    required PlayerCharacter character,
    required String actionId,
    required String? turnId,
    required List<ModifierSource> modifiers,
  }) => ActionCheckResult(
    checkId: _uuid.v4(),
    turnId: turnId ?? actionId,
    actionId: actionId,
    playerId: character.playerId,
    characterId: character.id,
    checkType: decision.checkType,
    attributeId: decision.attributeId,
    skillId: decision.skillId,
    targetId: decision.targetId,
    diceFormula: 'BLOCKED',
    individualRolls: const [],
    baseRoll: 0,
    modifierSources: modifiers,
    difficulty: decision.difficulty ?? 12,
    finalResult: 0,
    successLevel: ActionOutcomeLevel.blocked,
    margin: 0,
    visibility: decision.visibility,
    presentationMode: DicePresentationMode.none,
    reason: '重复检定被阻止：需要新的方法、工具、线索或场景变化',
    createdAt: DateTime.now(),
  );

  static bool _successful(ActionOutcomeLevel level) => switch (level) {
    ActionOutcomeLevel.partialSuccess ||
    ActionOutcomeLevel.success ||
    ActionOutcomeLevel.greatSuccess ||
    ActionOutcomeLevel.criticalSuccess ||
    ActionOutcomeLevel.automaticSuccess => true,
    _ => false,
  };

  static bool _hasNewApproach(String value) => const [
    '改用',
    '借助',
    '使用工具',
    '换一种',
    '根据线索',
    '让队友',
    '付出时间',
    '另一条路',
  ].any(value.contains);

  static bool _isHelpAction(String value) =>
      const ['帮助', '协助', '支援', '掩护'].any(value.contains);

  static DiceVisibility _diceVisibility(RollVisibility value) =>
      switch (value) {
        RollVisibility.public => DiceVisibility.public,
        RollVisibility.playerPrivate => DiceVisibility.playerPrivate,
        RollVisibility.gmHidden => DiceVisibility.gmOnly,
      };

  static String _rankName(String? skillId) => switch (skillId) {
    'combat' => '力量',
    'defense' || 'stealth' || 'chase' => '敏捷',
    'magic' || 'commandSpell' => '魔力',
    'luck' => '幸运',
    'noblePhantasm' => '宝具',
    _ => '参数',
  };
}
