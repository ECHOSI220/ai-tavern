import '../../models/trpg_gameplay_models.dart';
import '../../models/trpg_models.dart';

/// Deterministic first-pass intent classifier. The AI may suggest a check, but
/// this service and the rule pack remain authoritative.
class ActionCheckAnalyzer {
  const ActionCheckAnalyzer();

  ActionCheckDecision analyze({
    required String action,
    required TRPGSession session,
    required PlayerCharacter character,
    String? targetId,
  }) {
    final text = action.trim().toLowerCase();
    if (text.isEmpty || _isOrdinaryAction(text)) {
      return const ActionCheckDecision(requiresCheck: false);
    }

    final match = _rules.where((rule) => rule.matches(text)).firstOrNull;
    if (match == null) return const ActionCheckDecision(requiresCheck: false);

    final hasPotentialHiddenInformation = _hasPotentialHiddenInformation(
      session,
    );
    if (match.passive &&
        !match.forceHidden &&
        !hasPotentialHiddenInformation &&
        _isCasualObservation(text)) {
      return const ActionCheckDecision(requiresCheck: false);
    }
    final hidden =
        match.hidden && (match.forceHidden || hasPotentialHiddenInformation);
    final risk = _risk(text, match.defaultRisk);
    final isOpposed =
        match.opposed ||
        _containsAny(text, const [
          '对方',
          '敌人',
          '敌方',
          '御主',
          '从者',
          '守卫',
          'npc',
          '撒谎',
          '结盟',
          '追击',
        ]);
    final isGroup = _containsAny(text, const ['一起', '共同', '全队', '合作']);
    final isHelp = _containsAny(text, const ['帮助', '协助', '支援', '掩护']);
    final checkType = isHelp
        ? ActionCheckType.help
        : isGroup
        ? ActionCheckType.group
        : isOpposed
        ? ActionCheckType.opposed
        : hidden && match.passive
        ? ActionCheckType.passive
        : match.skillId == null
        ? ActionCheckType.attribute
        : ActionCheckType.skill;
    final visibility = hidden
        ? RollVisibility.gmHidden
        : match.privateResult
        ? RollVisibility.playerPrivate
        : RollVisibility.public;
    final dramatic =
        risk == ActionRiskLevel.critical ||
        _containsAny(text, const ['宝具', '最后一道令咒', '生死', '决战', '致命']);
    final package = session.ruleState.diceSettings.rulePackage;
    final diceFormula = switch (package.name) {
      'coc' => '1D100',
      'dicePool' => '3D6',
      'custom' => session.ruleState.diceSettings.customFormula,
      _ when session.ruleSystemId.contains('d100') => '1D100',
      _ => '1D20',
    };
    final difficulty = switch (risk) {
      ActionRiskLevel.none => 8,
      ActionRiskLevel.low => 10,
      ActionRiskLevel.medium => 13,
      ActionRiskLevel.high => 17,
      ActionRiskLevel.critical => 21,
    };
    final semanticTarget = targetId ?? match.skillId ?? match.attributeId;
    return ActionCheckDecision(
      requiresCheck: true,
      checkType: checkType,
      attributeId: match.attributeId,
      skillId: match.skillId,
      targetId: targetId,
      opposedTargetId: isOpposed ? targetId : null,
      difficulty: difficulty,
      riskLevel: risk,
      reason: match.reason,
      visibility: visibility,
      presentationMode: hidden
          ? DicePresentationMode.none
          : dramatic
          ? DicePresentationMode.dramatic
          : DicePresentationMode.compact,
      suggestedDiceFormula: diceFormula,
      repeatedCheckPolicy: RepeatedCheckPolicy.requireNewApproach,
      semanticKey: '${session.worldState.currentScene.sceneId}:$semanticTarget',
    );
  }

  bool _isOrdinaryAction(String text) {
    if (_containsAny(text, const [
      '攻击',
      '偷',
      '骗',
      '调查',
      '搜索',
      '观察',
      '检查',
      '尝试',
      '试着',
      '说服',
      '威胁',
      '跳',
      '追',
      '逃',
      '躲',
      '潜行',
      '破解',
      '治疗',
      '制作',
      '魔术',
      '宝具',
      '令咒',
      '判断',
      '恢复',
      '解毒',
      '挣脱',
    ])) {
      return false;
    }
    return _containsAny(text, const [
      '晚上好',
      '你好',
      '早上好',
      '坐下',
      '站起来',
      '走过去',
      '打开没锁',
      '打开没有锁',
      '点头',
      '挥手',
      '喝水',
      '休息一下',
      '看看时间',
    ]);
  }

  bool _hasPotentialHiddenInformation(TRPGSession session) =>
      session.gmState.undiscoveredClues.isNotEmpty ||
      session.campaignState.clues.any((value) => !value.discovered) ||
      session.worldState.currentScene.tags.any(
        (value) => const ['hidden', 'secret', 'ambush', 'trap'].contains(value),
      );

  bool _isCasualObservation(String text) =>
      !_containsAny(text, const ['推断', '真名', '秘密', '线索', '寻找', '搜索', '分析']) &&
      _containsAny(text, const ['看看', '看一眼', '环顾', '观察一下']);

  ActionRiskLevel _risk(String text, ActionRiskLevel fallback) {
    if (_containsAny(text, const ['宝具', '生死', '致命', '决战', '最后一道'])) {
      return ActionRiskLevel.critical;
    }
    if (_containsAny(text, const ['危险', '断裂', '偷袭', '战斗', '强行', '追击'])) {
      return ActionRiskLevel.high;
    }
    if (_containsAny(text, const ['谨慎', '偷偷', '尝试', '试着'])) {
      return ActionRiskLevel.medium;
    }
    return fallback;
  }

  static bool _containsAny(String text, List<String> values) =>
      values.any(text.contains);

  static final List<_CheckRule> _rules = [
    _CheckRule(['力量检定', '纯力量'], 'STR', null, '力量检定'),
    _CheckRule(['敏捷检定', '纯敏捷'], 'DEX', null, '敏捷检定'),
    _CheckRule(['智力检定', '纯智力'], 'INT', null, '智力检定'),
    _CheckRule(['感知检定', '纯感知'], 'PER', null, '感知检定'),
    _CheckRule(['魅力检定', '纯魅力'], 'CHA', null, '魅力检定'),
    _CheckRule(
      ['说服', '交涉', '谈判', '结盟'],
      'CHA',
      'persuasion',
      '说服检定',
      opposed: true,
    ),
    _CheckRule(
      ['判断', '洞察', '有没有撒谎', '对方撒谎', '语气'],
      'PER',
      'insight',
      '洞察检定',
      opposed: true,
      privateResult: true,
    ),
    _CheckRule(
      ['欺骗', '我撒谎', '隐瞒', '伪装说法'],
      'CHA',
      'deception',
      '欺骗检定',
      opposed: true,
    ),
    _CheckRule(
      ['威吓', '威胁', '恐吓'],
      'CHA',
      'intimidation',
      '威吓检定',
      opposed: true,
    ),
    _CheckRule(
      ['潜行', '偷偷靠近', '悄悄', '隐藏自己'],
      'DEX',
      'stealth',
      '潜行检定',
      opposed: true,
    ),
    _CheckRule(
      ['观察', '环顾', '聆听', '感知', '看看', '看一眼'],
      'PER',
      'perception',
      '感知检定',
      hidden: true,
      passive: true,
    ),
    _CheckRule(
      ['突然偷袭', '遭到偷袭', '伏击'],
      'PER',
      'perception',
      '突袭感知检定',
      hidden: true,
      passive: true,
      forceHidden: true,
      defaultRisk: ActionRiskLevel.high,
    ),
    _CheckRule(
      ['调查', '搜索', '寻找', '检查房间', '推断真名', '分析'],
      'INT',
      'investigation',
      '调查检定',
      hidden: true,
    ),
    _CheckRule(['魔术', '结界', '术式', '灵脉', '魔力'], 'INT', 'magic', '魔术检定'),
    _CheckRule(
      ['攻击', '挥剑', '射击', '近战'],
      'STR',
      'combat',
      '攻击检定',
      opposed: true,
      defaultRisk: ActionRiskLevel.high,
    ),
    _CheckRule(
      ['防御', '格挡', '闪避'],
      'DEX',
      'defense',
      '防御检定',
      opposed: true,
      defaultRisk: ActionRiskLevel.high,
    ),
    _CheckRule(
      ['追逐', '追击', '逃跑', '逃离'],
      'DEX',
      'chase',
      '追逐检定',
      opposed: true,
      defaultRisk: ActionRiskLevel.high,
    ),
    _CheckRule(['跳过', '攀爬', '破门', '搬运', '推开'], 'STR', 'athletics', '运动检定'),
    _CheckRule(
      ['救援', '急救', '治疗', '医疗'],
      'INT',
      'medicine',
      '医疗检定',
      privateResult: true,
    ),
    _CheckRule(['破解', '开锁', '黑客', '入侵系统'], 'INT', 'technology', '破解检定'),
    _CheckRule(['制作', '修理', '改造'], 'INT', 'crafting', '制作检定'),
    _CheckRule(
      ['恢复状态', '解毒', '稳定伤势'],
      'INT',
      'medicine',
      '状态恢复检定',
      privateResult: true,
    ),
    _CheckRule(
      ['挣脱', '摆脱精神', '克服恐惧'],
      'PER',
      'willpower',
      '抗性检定',
      privateResult: true,
    ),
    _CheckRule(['帮助', '协助', '支援', '掩护'], 'STR', 'athletics', '协助检定'),
    _CheckRule(
      ['抵抗', '意志', '精神干扰', '恐惧'],
      'PER',
      'willpower',
      '意志检定',
      privateResult: true,
    ),
    _CheckRule(['幸运', '碰运气', '随机抽取'], 'CHA', 'luck', '幸运检定'),
    _CheckRule(
      ['宝具'],
      'INT',
      'noblePhantasm',
      '宝具判定',
      opposed: true,
      defaultRisk: ActionRiskLevel.critical,
    ),
    _CheckRule(
      ['令咒'],
      'INT',
      'commandSpell',
      '令咒干涉检定',
      opposed: true,
      defaultRisk: ActionRiskLevel.high,
    ),
  ];
}

class _CheckRule {
  const _CheckRule(
    this.keywords,
    this.attributeId,
    this.skillId,
    this.reason, {
    this.opposed = false,
    this.hidden = false,
    this.forceHidden = false,
    this.passive = false,
    this.privateResult = false,
    this.defaultRisk = ActionRiskLevel.medium,
  });
  final List<String> keywords;
  final String attributeId, reason;
  final String? skillId;
  final bool opposed, hidden, forceHidden, passive, privateResult;
  final ActionRiskLevel defaultRisk;
  bool matches(String value) => keywords.any(value.contains);
}
