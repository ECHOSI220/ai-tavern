import '../../models/holy_grail_war_models.dart';
import '../../models/trpg_dice_models.dart';
import '../../models/trpg_gameplay_models.dart';

class AttributeDefinition {
  const AttributeDefinition(this.id, this.name, {this.min = 1, this.max = 30});
  final String id, name;
  final int min, max;
}

class SkillDefinition2 {
  const SkillDefinition2(
    this.id,
    this.name,
    this.attributeId, {
    this.min = 0,
    this.max = 100,
  });
  final String id, name, attributeId;
  final int min, max;
}

class GrowthRuleDefinition {
  const GrowthRuleDefinition({
    required this.type,
    this.skillIncreaseMin = 1,
    this.skillIncreaseMax = 3,
    this.attributeIncrease = 1,
  });
  final GrowthRuleType type;
  final int skillIncreaseMin, skillIncreaseMax, attributeIncrease;
}

class TRPGRulePack {
  const TRPGRulePack();

  static const attributes = {
    'STR': AttributeDefinition('STR', '力量'),
    'DEX': AttributeDefinition('DEX', '敏捷'),
    'INT': AttributeDefinition('INT', '智力'),
    'PER': AttributeDefinition('PER', '感知'),
    'CHA': AttributeDefinition('CHA', '魅力'),
  };

  static const skills = {
    'athletics': SkillDefinition2('athletics', '运动', 'STR'),
    'stealth': SkillDefinition2('stealth', '潜行', 'DEX'),
    'investigation': SkillDefinition2('investigation', '调查', 'INT'),
    'perception': SkillDefinition2('perception', '感知', 'PER'),
    'insight': SkillDefinition2('insight', '洞察', 'PER'),
    'persuasion': SkillDefinition2('persuasion', '说服', 'CHA'),
    'deception': SkillDefinition2('deception', '欺骗', 'CHA'),
    'intimidation': SkillDefinition2('intimidation', '威吓', 'CHA'),
    'magic': SkillDefinition2('magic', '魔术', 'INT'),
    'combat': SkillDefinition2('combat', '战斗', 'STR'),
    'defense': SkillDefinition2('defense', '防御', 'DEX'),
    'chase': SkillDefinition2('chase', '追逐', 'DEX'),
    'medicine': SkillDefinition2('medicine', '医疗', 'INT'),
    'technology': SkillDefinition2('technology', '破解', 'INT'),
    'crafting': SkillDefinition2('crafting', '制作', 'INT'),
    'willpower': SkillDefinition2('willpower', '意志', 'PER'),
    'luck': SkillDefinition2('luck', '幸运', 'CHA'),
    'noblePhantasm': SkillDefinition2('noblePhantasm', '宝具', 'INT'),
    'commandSpell': SkillDefinition2('commandSpell', '令咒', 'INT'),
  };

  ActionCheckDecision validate(ActionCheckDecision value) {
    if (!value.requiresCheck) return value;
    final skill = value.skillId == null ? null : skills[value.skillId];
    final attribute = value.attributeId ?? skill?.attributeId;
    if (attribute == null || !attributes.containsKey(attribute)) {
      return const ActionCheckDecision(requiresCheck: false);
    }
    return ActionCheckDecision.fromJson({
      ...value.toJson(),
      'attributeId': attribute,
      'difficulty': (value.difficulty ?? 12).clamp(3, 40),
    });
  }

  GrowthRuleDefinition growthRule(DiceRulePackageType package) =>
      package == DiceRulePackageType.coc
      ? const GrowthRuleDefinition(type: GrowthRuleType.rollOverCurrent)
      : const GrowthRuleDefinition(type: GrowthRuleType.milestone);

  int rankModifier(ParameterRank rank) => switch (rank) {
    ParameterRank.e => 0,
    ParameterRank.d => 1,
    ParameterRank.c => 2,
    ParameterRank.b => 3,
    ParameterRank.a => 5,
    ParameterRank.ex => 8,
  };

  ParameterRank? servantRankFor(ServantParameters p, String? skillId) =>
      switch (skillId) {
        'combat' => p.strength,
        'defense' || 'stealth' || 'chase' => p.agility,
        'magic' || 'commandSpell' => p.mana,
        'luck' => p.luck,
        'noblePhantasm' => p.noblePhantasm,
        _ => null,
      };
}
