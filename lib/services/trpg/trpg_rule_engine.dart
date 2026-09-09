// ignore_for_file: use_null_aware_elements

import 'dart:math';

import 'package:uuid/uuid.dart';

import '../../models/trpg_game_models.dart';
import '../../models/trpg_models.dart';
import '../../models/trpg_dice_models.dart';
import 'dice_engine.dart';
import 'dice_service.dart';

class TRPGRuleException implements Exception {
  const TRPGRuleException(this.message);
  final String message;
  @override
  String toString() => message;
}

class TRPGRuleEngine {
  TRPGRuleEngine({DiceService? diceService})
    : _dice = diceService ?? DiceService();

  final DiceService _dice;
  static const _uuid = Uuid();
  static const validStats = {'STR', 'DEX', 'INT', 'PER', 'CHA'};
  static const skills = <SkillDefinition>[
    SkillDefinition(id: 'athletics', name: '运动', stat: 'STR'),
    SkillDefinition(id: 'stealth', name: '潜行', stat: 'DEX'),
    SkillDefinition(id: 'investigation', name: '调查', stat: 'INT'),
    SkillDefinition(id: 'perception', name: '感知', stat: 'PER'),
    SkillDefinition(id: 'persuasion', name: '说服', stat: 'CHA'),
    SkillDefinition(id: 'deception', name: '欺瞒', stat: 'CHA'),
  ];

  int statModifier(num stat) => ((stat - 10) / 2).floor();

  int validateDifficulty(int difficulty) {
    if (difficulty < 5 || difficulty > 25) {
      throw const TRPGRuleException('检定难度必须在 5 到 25 之间');
    }
    return difficulty;
  }

  SkillCheckResult skillCheck({
    required PlayerCharacter character,
    String? stat,
    String? skillId,
    required int difficulty,
    required String reason,
    AdvantageMode advantageMode = AdvantageMode.normal,
  }) {
    final skill = skills.where((item) => item.id == skillId).firstOrNull;
    final resolvedStat = (skill?.stat ?? stat ?? '').toUpperCase();
    if (!validStats.contains(resolvedStat) ||
        !character.stats.containsKey(resolvedStat)) {
      throw TRPGRuleException('角色不存在可用属性：$resolvedStat');
    }
    validateDifficulty(difficulty);
    final count = advantageMode == AdvantageMode.normal ? 1 : 2;
    final roll = _dice.roll(
      sides: 20,
      count: count,
      playerId: character.playerId,
    );
    final chosen = switch (advantageMode) {
      AdvantageMode.advantage => roll.rolls.reduce(max),
      AdvantageMode.disadvantage => roll.rolls.reduce(min),
      AdvantageMode.normal => roll.rolls.single,
    };
    final proficiency = skill != null && character.skills[skill.id] != null
        ? (character.skills[skill.id]! > 0 ? 2 : 0)
        : 0;
    final modifier = statModifier(character.stats[resolvedStat]!) + proficiency;
    final total = chosen + modifier;
    return SkillCheckResult(
      stat: resolvedStat,
      skillId: skill?.id,
      rawRolls: roll.rolls,
      chosenRoll: chosen,
      modifier: modifier,
      total: total,
      difficulty: difficulty,
      success: chosen == 20 || (chosen != 1 && total >= difficulty),
      criticalSuccess: chosen == 20,
      criticalFailure: chosen == 1,
      reason: reason,
    );
  }

  TRPGSession recordSkillCheck(
    TRPGSession session,
    SkillCheckResult result, {
    required String characterId,
    required String actionId,
    String? turnId,
  }) {
    final character = _character(session, characterId);
    final now = DateTime.now();
    final diceRoll = DiceRoll(
      diceType: result.rawRolls.length == 2 ? '2D20' : 'D20',
      count: result.rawRolls.length,
      rolls: result.rawRolls,
      modifier: result.modifier,
      total: result.total,
      playerId: character.playerId,
      timestamp: now,
      characterId: characterId,
      turnId: turnId,
      actionId: actionId,
    );
    final diceResult = DiceEngine().evaluate(
      formula: DiceFormula(diceCount: 1, sides: 20, modifier: result.modifier),
      individualResults: [result.chosenRoll],
      playerId: character.playerId,
      characterId: characterId,
      action: result.skillId == null
          ? '${result.stat} 属性检定'
          : '${result.skillId} 技能检定',
      reason: result.reason,
      difficulty: result.difficulty,
      metadata: {
        'rawRolls': result.rawRolls,
        'turnId': turnId,
        'actionId': actionId,
      },
    );
    final history2 = [...session.ruleState.diceHistory2, diceResult];
    final history = [...session.ruleState.diceHistory, diceRoll];
    return session.copyWith(
      ruleState: session.ruleState.copyWith(
        diceHistory: history.length > 50
            ? history.sublist(history.length - 50)
            : history,
        diceHistory2: history2.length > 50
            ? history2.sublist(history2.length - 50)
            : history2,
      ),
      eventLog: [
        ...session.eventLog,
        TRPGEvent(
          id: _uuid.v4(),
          type: TRPGEventType.skillCheck,
          timestamp: now,
          actorId: characterId,
          payload: {
            ...result.toJson(),
            'actionId': actionId,
            'turnId': turnId,
            'playerId': character.playerId,
            'characterId': characterId,
            'diceResult': diceResult.toJson(),
            'explanation': diceResult.explanation,
          },
        ),
      ],
      updatedAt: now,
      lastPlayedAt: now,
    );
  }

  TRPGSession modifyHp(
    TRPGSession session, {
    required String characterId,
    required int amount,
    required String reason,
    String? damageType,
    String? actionId,
  }) {
    if (amount < -1000 || amount > 1000) {
      throw const TRPGRuleException('单次 HP 变化超出允许范围');
    }
    final character = _character(session, characterId);
    final hp = (character.hp + amount).clamp(0, character.maxHp);
    var effects = [...character.structuredStatusEffects];
    var legacyEffects = [...character.statusEffects];
    if (hp == 0 && !effects.any((item) => item.id == 'downed')) {
      effects.add(
        StatusEffect(
          id: 'downed',
          name: '倒下',
          description: 'HP 降至 0，无法正常行动。',
          source: reason,
        ),
      );
      if (!legacyEffects.contains('downed')) legacyEffects.add('downed');
    } else if (hp > 0) {
      effects.removeWhere((item) => item.id == 'downed');
      legacyEffects.remove('downed');
    }
    final updated = character.copyWith(
      hp: hp,
      structuredStatusEffects: effects,
      statusEffects: legacyEffects,
    );
    final now = DateTime.now();
    return session.copyWith(
      playerCharacters: _replaceCharacter(session, updated),
      eventLog: [
        ...session.eventLog,
        TRPGEvent(
          id: _uuid.v4(),
          type: TRPGEventType.hpChange,
          timestamp: now,
          actorId: characterId,
          payload: {
            'amount': amount,
            'before': character.hp,
            'after': hp,
            'reason': reason,
            if (damageType != null) 'damageType': damageType,
            if (actionId != null) 'actionId': actionId,
          },
        ),
      ],
      updatedAt: now,
      lastPlayedAt: now,
    );
  }

  TRPGSession addStatus(
    TRPGSession session, {
    required String characterId,
    required StatusEffect effect,
    String? actionId,
  }) {
    if (effect.id.trim().isEmpty || effect.name.trim().isEmpty) {
      throw const TRPGRuleException('状态 id 和名称不能为空');
    }
    final character = _character(session, characterId);
    final effects = [...character.structuredStatusEffects]
      ..removeWhere((item) => item.id == effect.id)
      ..add(effect);
    final legacy = [...character.statusEffects];
    if (!legacy.contains(effect.id)) legacy.add(effect.id);
    return _statusChanged(
      session,
      character.copyWith(
        structuredStatusEffects: effects,
        statusEffects: legacy,
      ),
      operation: 'add',
      effectId: effect.id,
      actionId: actionId,
    );
  }

  TRPGSession removeStatus(
    TRPGSession session, {
    required String characterId,
    required String statusId,
    String? actionId,
  }) {
    final character = _character(session, characterId);
    if (!character.structuredStatusEffects.any((item) => item.id == statusId) &&
        !character.statusEffects.contains(statusId)) {
      throw TRPGRuleException('角色没有状态：$statusId');
    }
    return _statusChanged(
      session,
      character.copyWith(
        structuredStatusEffects: character.structuredStatusEffects
            .where((item) => item.id != statusId)
            .toList(),
        statusEffects: character.statusEffects
            .where((item) => item != statusId)
            .toList(),
      ),
      operation: 'remove',
      effectId: statusId,
      actionId: actionId,
    );
  }

  TRPGSession giveItem(
    TRPGSession session, {
    required String characterId,
    required InventoryItem item,
    required String reason,
    String? actionId,
  }) {
    if (item.id.trim().isEmpty || item.quantity <= 0 || item.quantity > 999) {
      throw const TRPGRuleException('物品 id 或数量无效');
    }
    final character = _character(session, characterId);
    final inventory = [...character.inventoryItems];
    final index = inventory.indexWhere((existing) => existing.id == item.id);
    if (index >= 0) {
      inventory[index] = inventory[index].copyWith(
        quantity: inventory[index].quantity + item.quantity,
      );
    } else {
      inventory.add(item);
    }
    final legacy = inventory.map((entry) => entry.name).toList();
    return _inventoryChanged(
      session,
      character.copyWith(inventoryItems: inventory, inventory: legacy),
      type: TRPGEventType.itemGain,
      payload: {
        'item': item.toJson(),
        'reason': reason,
        if (actionId != null) 'actionId': actionId,
      },
    );
  }

  TRPGSession removeItem(
    TRPGSession session, {
    required String characterId,
    required String itemId,
    required int amount,
    required String reason,
    String? actionId,
  }) {
    if (amount <= 0 || amount > 999) {
      throw const TRPGRuleException('移除数量必须大于 0');
    }
    final character = _character(session, characterId);
    final inventory = [...character.inventoryItems];
    final index = inventory.indexWhere((item) => item.id == itemId);
    if (index < 0 || inventory[index].quantity < amount) {
      throw TRPGRuleException('背包中没有足够数量的物品：$itemId');
    }
    final old = inventory[index];
    if (old.quantity == amount) {
      inventory.removeAt(index);
    } else {
      inventory[index] = old.copyWith(quantity: old.quantity - amount);
    }
    return _inventoryChanged(
      session,
      character.copyWith(
        inventoryItems: inventory,
        inventory: inventory.map((item) => item.name).toList(),
      ),
      type: TRPGEventType.itemLoss,
      payload: {
        'itemId': itemId,
        'amount': amount,
        'reason': reason,
        if (actionId != null) 'actionId': actionId,
      },
    );
  }

  TRPGSession startCombat(
    TRPGSession session, {
    required List<String> participantIds,
    required String reason,
    String? actionId,
  }) {
    if (participantIds.isEmpty) {
      throw const TRPGRuleException('战斗参与者不能为空');
    }
    final unique = participantIds.toSet().toList();
    final rolls = <String, int>{};
    for (final id in unique) {
      final character = session.playerCharacters
          .where((item) => item.id == id)
          .firstOrNull;
      final dex = character == null
          ? 0
          : statModifier(character.stats['DEX'] ?? 10);
      rolls[id] = _dice.roll(sides: 20, playerId: id, modifier: dex).total;
    }
    unique.sort((a, b) => rolls[b]!.compareTo(rolls[a]!));
    final now = DateTime.now();
    return session.copyWith(
      ruleState: session.ruleState.copyWith(
        combatActive: true,
        initiative: unique,
        activeTurn: unique.first,
        round: 1,
      ),
      eventLog: [
        ...session.eventLog,
        TRPGEvent(
          id: _uuid.v4(),
          type: TRPGEventType.combatStarted,
          timestamp: now,
          payload: {
            'initiative': unique,
            'rolls': rolls,
            'reason': reason,
            if (actionId != null) 'actionId': actionId,
          },
        ),
      ],
      updatedAt: now,
    );
  }

  TRPGSession endCombat(
    TRPGSession session, {
    required String reason,
    String? actionId,
  }) {
    if (!session.ruleState.combatActive) {
      throw const TRPGRuleException('当前没有进行中的战斗');
    }
    final now = DateTime.now();
    return session.copyWith(
      ruleState: session.ruleState.copyWith(
        combatActive: false,
        initiative: const [],
        activeTurn: '',
        round: 0,
      ),
      eventLog: [
        ...session.eventLog,
        TRPGEvent(
          id: _uuid.v4(),
          type: TRPGEventType.combatEnded,
          timestamp: now,
          payload: {
            'reason': reason,
            if (actionId != null) 'actionId': actionId,
          },
        ),
      ],
      updatedAt: now,
    );
  }

  PlayerCharacter _character(TRPGSession session, String id) =>
      session.playerCharacters.where((item) => item.id == id).firstOrNull ??
      (throw TRPGRuleException('角色不存在：$id'));

  List<PlayerCharacter> _replaceCharacter(
    TRPGSession session,
    PlayerCharacter character,
  ) => session.playerCharacters
      .map((item) => item.id == character.id ? character : item)
      .toList();

  TRPGSession _statusChanged(
    TRPGSession session,
    PlayerCharacter character, {
    required String operation,
    required String effectId,
    String? actionId,
  }) {
    final now = DateTime.now();
    return session.copyWith(
      playerCharacters: _replaceCharacter(session, character),
      eventLog: [
        ...session.eventLog,
        TRPGEvent(
          id: _uuid.v4(),
          type: TRPGEventType.statusChange,
          timestamp: now,
          actorId: character.id,
          payload: {
            'operation': operation,
            'statusId': effectId,
            if (actionId != null) 'actionId': actionId,
          },
        ),
      ],
      updatedAt: now,
    );
  }

  TRPGSession _inventoryChanged(
    TRPGSession session,
    PlayerCharacter character, {
    required TRPGEventType type,
    required Map<String, Object?> payload,
  }) {
    final now = DateTime.now();
    return session.copyWith(
      playerCharacters: _replaceCharacter(session, character),
      eventLog: [
        ...session.eventLog,
        TRPGEvent(
          id: _uuid.v4(),
          type: type,
          timestamp: now,
          actorId: character.id,
          payload: payload,
        ),
      ],
      updatedAt: now,
    );
  }
}
