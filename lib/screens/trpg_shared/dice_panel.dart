import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../app/skins/theme_tokens.dart';
import '../../app/skins/theme_manager.dart';
import '../../app/skins/theme_definition.dart';
import '../../app/skins/character_theme.dart';

import '../../models/trpg_dice_models.dart';
import '../../services/trpg/dice_animation_controller.dart';
import '../../services/trpg/dice_engine.dart';
import 'polyhedral_dice_3d.dart';

typedef DiceRollCallback = Future<DiceRollResult> Function(String formula);
typedef DiceSettingsCallback = Future<void> Function(DiceSettings settings);

class DicePanel extends StatefulWidget {
  const DicePanel({
    required this.history,
    required this.settings,
    required this.onRoll,
    required this.onSettingsChanged,
    super.key,
  });

  final List<DiceRollResult> history;
  final DiceSettings settings;
  final DiceRollCallback onRoll;
  final DiceSettingsCallback onSettingsChanged;

  @override
  State<DicePanel> createState() => _DicePanelState();
}

class _DicePanelState extends State<DicePanel> {
  final _formula = TextEditingController(text: '1D20');
  final _parser = const DiceFormulaParser();
  DiceDefinition _selected = DiceLibrary.bySides(20);
  bool _rolling = false;
  String? _error;
  bool _tutorialScheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!widget.settings.tutorialShown && !_tutorialScheduled) {
      _tutorialScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _showTutorial());
    }
  }

  Future<void> _showTutorial() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.casino_outlined),
        title: const Text('骰子由系统自动用于剧情检定'),
        content: const Text(
          '正常游玩时，你只要描述角色行动。遇到攻击、调查、潜行、说服等不确定行动，系统会自动选择骰子、叠加属性与技能修正，并要求 AI 主持按照真实成败继续剧情。这里的手动投骰是自由工具，不会自动替代正式剧情检定。',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('明白了'),
          ),
        ],
      ),
    );
    await widget.onSettingsChanged(
      widget.settings.copyWith(tutorialShown: true),
    );
  }

  Future<void> _roll() async {
    try {
      _parser.parse(_formula.text);
      setState(() {
        _rolling = true;
        _error = null;
      });
      final result = await widget.onRoll(_formula.text);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) =>
            DiceResultDialog(result: result, settings: widget.settings),
      );
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _rolling = false);
    }
  }

  @override
  void dispose() {
    _formula.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    DiceFormula? parsed;
    try {
      parsed = _parser.parse(_formula.text);
    } catch (_) {}
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.casino_outlined),
            const SizedBox(width: 10),
            Text('骰子与检定', style: Theme.of(context).textTheme.headlineSmall),
            const Spacer(),
            IconButton(
              tooltip: '投骰设置',
              onPressed: _showSettings,
              icon: const Icon(Icons.tune),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          color: colors.primaryContainer.withValues(alpha: .72),
          child: const Padding(
            padding: EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.auto_awesome_outlined),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '正式检定：直接在主界面描述行动，系统会自动投骰并让结果改变剧情。\n'
                    '手动自由骰：只用于自定义随机数或桌外约定，本身不会判定剧情成败。',
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: DiceLibrary.definitions.map((definition) {
              final selected = definition.sides == _selected.sides;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  selected: selected,
                  avatar: DiceGlyph(sides: definition.sides, size: 24),
                  label: Text(definition.id),
                  onSelected: (_) => setState(() {
                    _selected = definition;
                    _formula.text = '1D${definition.sides}';
                  }),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          color: colors.surfaceContainerHigh.withValues(alpha: .76),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _selected.displayName,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text('范围：${_selected.rangeLabel}'),
                Text('用途：${_selected.usage}'),
                Text(_selected.description),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _formula,
          decoration: const InputDecoration(
            labelText: '骰子公式',
            hintText: '例如 2D6+3',
            prefixIcon: Icon(Icons.functions),
          ),
          textCapitalization: TextCapitalization.characters,
          onChanged: (value) {
            try {
              _selected = DiceLibrary.bySides(_parser.parse(value).sides);
            } catch (_) {}
            setState(() {});
          },
          onSubmitted: (_) => _roll(),
        ),
        if (parsed != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Text('解释：${parsed.explanation}'),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_error!, style: TextStyle(color: colors.error)),
          ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: _rolling ? null : _roll,
          icon: _rolling
              ? const SizedBox.square(
                  dimension: 18,
                  child: ThemedLoadingIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.casino),
          label: Text(
            _rolling ? '正在投掷…' : '自由投掷 ${parsed?.normalized ?? _formula.text}',
          ),
        ),
        const SizedBox(height: 22),
        Text('最近投骰', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        if (widget.history.isEmpty) const Text('还没有投骰记录。正式检定会在你提交有风险的行动后自动出现。'),
        ...widget.history.reversed
            .take(50)
            .map((result) => _HistoryTile(result: result)),
      ],
    );
  }

  Future<void> _showSettings() async {
    var settings = widget.settings;
    final updated = await showModalBottomSheet<DiceSettings>(
      context: context,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                title: const Text('3D 多面骰动画'),
                value: settings.animationEnabled,
                onChanged: (value) => setSheetState(
                  () => settings = settings.copyWith(animationEnabled: value),
                ),
              ),
              SwitchListTile(
                title: const Text('声音'),
                value: settings.soundEnabled,
                onChanged: (value) => setSheetState(
                  () => settings = settings.copyWith(soundEnabled: value),
                ),
              ),
              SwitchListTile(
                title: const Text('震动'),
                value: settings.hapticsEnabled,
                onChanged: (value) => setSheetState(
                  () => settings = settings.copyWith(hapticsEnabled: value),
                ),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, settings),
                child: const Text('保存'),
              ),
            ],
          ),
        ),
      ),
    );
    if (updated != null) await widget.onSettingsChanged(updated);
  }
}

class DiceResultDialog extends StatefulWidget {
  const DiceResultDialog({
    required this.result,
    required this.settings,
    super.key,
  });
  final DiceRollResult result;
  final DiceSettings settings;

  @override
  State<DiceResultDialog> createState() => _DiceResultDialogState();
}

class _DiceResultDialogState extends State<DiceResultDialog> {
  late final DiceAnimationController _controller;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _controller = DiceAnimationController()..addListener(_onAnimationChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final reduce =
          CharacterThemeExtension.of(context) != null &&
          _reduceEffects(context);
      _controller.play(
        widget.result,
        reduce
            ? widget.settings.copyWith(animationEnabled: false)
            : widget.settings,
      );
    });
  }

  void _onAnimationChanged() {
    if (!_completed &&
        _controller.phase == DiceAnimationPhase.result &&
        mounted) {
      setState(() => _completed = true);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onAnimationChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _completed,
    child: AlertDialog(
      scrollable: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
      content: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final done = _controller.phase == DiceAnimationPhase.result;
          final color = _resultColor(context, widget.result.successLevel);
          final critical =
              widget.result.successLevel == DiceSuccessLevel.criticalSuccess;
          final failure =
              widget.result.successLevel == DiceSuccessLevel.criticalFailure;
          return SizedBox(
            width: 390,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_phaseLabel(_controller.phase)),
                const SizedBox(height: 16),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: failure ? .82 : .7, end: 1),
                  duration: _reduceEffects(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 380),
                  curve: Curves.elasticOut,
                  builder: (context, scale, child) =>
                      Transform.scale(scale: scale, child: child),
                  child: ThemedDiceCard(
                    size: 250,
                    failure:
                        widget.result.successLevel ==
                            DiceSuccessLevel.failure ||
                        failure,
                    critical: critical,
                    phase: _controller.rotationTurns,
                    child: SizedBox(
                      width: 240,
                      child: Dice3DStage(
                        sides: _diceSides(widget.result.diceType),
                        values: _controller.displayNumbers,
                        rotationTurns: _reduceEffects(context)
                            ? 0
                            : _controller.rotationTurns,
                        color: color,
                        settled:
                            done ||
                            _controller.phase == DiceAnimationPhase.stopped,
                        reducedMotion: _reduceEffects(context),
                      ),
                    ),
                  ),
                ),
                if (done) ...[
                  const SizedBox(height: 6),
                  Text('最终结果', style: Theme.of(context).textTheme.labelMedium),
                  Text(
                    '${widget.result.finalResult}',
                    key: const ValueKey('dice-final-total'),
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    _rollMath(widget.result),
                    key: const ValueKey('dice-roll-math'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                AnimatedOpacity(
                  opacity: done ? 1 : 0,
                  duration: _reduceEffects(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 260),
                  child: Column(
                    children: [
                      Text(
                        DiceEngine.successLevelLabel(
                          widget.result.successLevel,
                        ),
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              color: color,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.result.explanation,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
      actions: [
        TextButton(
          onPressed: _completed ? () => Navigator.pop(context) : null,
          child: const Text('完成'),
        ),
      ],
    ),
  );
}

class DiceGlyph extends StatelessWidget {
  const DiceGlyph({required this.sides, this.size = 32, this.color, super.key});
  final int sides;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _DiceGlyphPainter(
      sides: sides,
      color: color ?? Theme.of(context).colorScheme.primary,
    ),
  );
}

class _DiceGlyphPainter extends CustomPainter {
  const _DiceGlyphPainter({required this.sides, required this.color});
  final int sides;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final vertices = switch (sides) {
      4 => 3,
      6 => 4,
      8 => 6,
      _ => 8,
    };
    final center = size.center(Offset.zero);
    final radius = size.shortestSide * .46;
    final path = Path();
    for (var index = 0; index < vertices; index++) {
      final angle = -math.pi / 2 + index * math.pi * 2 / vertices;
      final point = Offset(
        center.dx + math.cos(angle) * radius,
        center.dy + math.sin(angle) * radius,
      );
      index == 0
          ? path.moveTo(point.dx, point.dy)
          : path.lineTo(point.dx, point.dy);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.5, size.shortestSide * .025)
        ..color = Colors.white.withValues(alpha: .7),
    );
  }

  @override
  bool shouldRepaint(covariant _DiceGlyphPainter oldDelegate) =>
      oldDelegate.sides != sides || oldDelegate.color != color;
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.result});
  final DiceRollResult result;

  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    contentPadding: EdgeInsets.zero,
    leading: DiceGlyph(
      sides: int.tryParse(result.diceType.substring(1)) ?? 20,
      color: _resultColor(context, result.successLevel),
    ),
    title: Text('${result.playerId} · ${result.action}'),
    subtitle: Text(_historyExplanation(result)),
    trailing: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          '${result.finalResult}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        Text(DiceEngine.successLevelLabel(result.successLevel)),
      ],
    ),
  );
}

String _historyExplanation(DiceRollResult result) {
  final sources = result.metadata['modifierSources'];
  final modifiers = sources is List
      ? sources
            .whereType<Map>()
            .map((raw) {
              final label = raw['label']?.toString() ?? '修正';
              final value = (raw['value'] as num?)?.toInt() ?? 0;
              return '$label ${value >= 0 ? '+' : ''}$value';
            })
            .join(' · ')
      : '';
  final rolls = result.individualResults.isEmpty
      ? '自动/被动判定'
      : result.individualResults.join(' + ');
  return [
    '${result.diceFormula} · $rolls',
    if (modifiers.isNotEmpty) modifiers,
    if (result.explanation.trim().isNotEmpty) result.explanation.trim(),
  ].join('\n');
}

int _diceSides(String diceType) {
  final match = RegExp(r'D(\d+)', caseSensitive: false).firstMatch(diceType);
  return int.tryParse(match?.group(1) ?? '') ?? 20;
}

String _rollMath(DiceRollResult result) {
  final rolls = result.individualResults.isEmpty
      ? '${result.baseResult}'
      : result.individualResults.join(' + ');
  final modifier = result.modifier == 0
      ? ''
      : result.modifier > 0
      ? ' + ${result.modifier}'
      : ' − ${result.modifier.abs()}';
  return '骰面 $rolls$modifier ＝ ${result.finalResult}';
}

Color _resultColor(BuildContext context, DiceSuccessLevel level) {
  final character = CharacterThemeExtension.of(context);
  if (character != null) {
    return switch (level) {
      DiceSuccessLevel.criticalSuccess => character.gold,
      DiceSuccessLevel.failure ||
      DiceSuccessLevel.criticalFailure => const Color(0xffe3a3a8),
      _ => character.blue,
    };
  }
  return switch (level) {
    DiceSuccessLevel.criticalSuccess => ThemeTokens.of(context).warning,
    DiceSuccessLevel.greatSuccess => ThemeTokens.of(context).success,
    DiceSuccessLevel.success => ThemeTokens.of(context).success,
    DiceSuccessLevel.failure => ThemeTokens.of(context).danger,
    DiceSuccessLevel.criticalFailure => ThemeTokens.of(context).danger,
    DiceSuccessLevel.unopposed => ThemeTokens.of(context).info,
  };
}

bool _reduceEffects(BuildContext context) {
  final character = CharacterThemeExtension.of(context);
  if (character != null && !character.motion) return true;
  final settings = ThemeScope.maybeOf(context)?.settings;
  return MediaQuery.disableAnimationsOf(context) ||
      settings?.reduceMotion == true ||
      settings?.effectsLevel == ThemeEffectsLevel.low ||
      settings?.effectsLevel == ThemeEffectsLevel.off;
}

String _phaseLabel(DiceAnimationPhase phase) => switch (phase) {
  DiceAnimationPhase.idle => '准备投骰',
  DiceAnimationPhase.preparing => '正在准备…',
  DiceAnimationPhase.appearing => '骰子出现',
  DiceAnimationPhase.rolling => '滚动中…',
  DiceAnimationPhase.stopped => '骰子停止',
  DiceAnimationPhase.result => '投骰结果',
};
