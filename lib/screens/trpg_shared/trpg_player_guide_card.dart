import 'package:flutter/material.dart';

import '../../app/skins/skin_icon.dart';
import '../../models/trpg_models.dart';
import '../../services/trpg/trpg_player_guidance_service.dart';
import 'trpg_play_ui.dart';

class TrpgPlayerGuideCard extends StatefulWidget {
  const TrpgPlayerGuideCard({
    required this.session,
    required this.controller,
    this.playerId,
    this.actionEnabled = true,
    this.inputEnabled = true,
    this.initiallyExpanded = true,
    super.key,
  });

  final TRPGSession session;
  final TextEditingController controller;
  final String? playerId;
  final bool actionEnabled;
  final bool inputEnabled;
  final bool initiallyExpanded;

  @override
  State<TrpgPlayerGuideCard> createState() => _TrpgPlayerGuideCardState();
}

class _TrpgPlayerGuideCardState extends State<TrpgPlayerGuideCard> {
  static const _guidanceService = TrpgPlayerGuidanceService();
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
    widget.controller.addListener(_onDraftChanged);
  }

  @override
  void didUpdateWidget(covariant TrpgPlayerGuideCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onDraftChanged);
      widget.controller.addListener(_onDraftChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onDraftChanged);
    super.dispose();
  }

  void _onDraftChanged() {
    if (mounted) setState(() {});
  }

  void _useSuggestion(String value) {
    if (!widget.inputEnabled) return;
    widget.controller
      ..text = value
      ..selection = TextSelection.collapsed(offset: value.length);
    setState(() => _expanded = false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final guidance = _guidanceService.build(
      session: widget.session,
      playerId: widget.playerId,
    );
    final dice = _guidanceService.dicePreview(
      session: widget.session,
      action: widget.controller.text,
      playerId: widget.playerId,
      actionEnabled: widget.actionEnabled,
    );
    return TrpgPlaySurface(
      key: const ValueKey('trpg-player-guide'),
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 5),
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
      radius: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  SkinIcon(
                    Icons.assistant_direction_outlined,
                    color: colors.primary,
                    size: 21,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '接下来做什么',
                          style: textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (!_expanded)
                          Text(
                            guidance.objective,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            child: !_expanded
                ? const SizedBox.shrink()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 9),
                      _GuideLine(
                        icon: Icons.bolt_outlined,
                        label: '正在发生',
                        content: guidance.situation,
                      ),
                      const SizedBox(height: 7),
                      _GuideLine(
                        icon: Icons.flag_outlined,
                        label: '当前目标',
                        content: guidance.objective,
                      ),
                      const SizedBox(height: 9),
                      Text(
                        '可以这样行动 · 点击填入',
                        style: textTheme.labelLarge?.copyWith(
                          color: colors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 58,
                        child: ListView.separated(
                          key: const ValueKey('trpg-suggested-actions'),
                          scrollDirection: Axis.horizontal,
                          itemCount: guidance.suggestedActions.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 7),
                          itemBuilder: (context, index) {
                            final action = guidance.suggestedActions[index];
                            return SizedBox(
                              width: 250,
                              child: OutlinedButton(
                                key: ValueKey('trpg-suggestion-$index'),
                                onPressed: widget.inputEnabled
                                    ? () => _useSuggestion(action)
                                    : null,
                                style: OutlinedButton.styleFrom(
                                  alignment: Alignment.centerLeft,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                ),
                                child: Text(
                                  '${index + 1}. $action',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: textTheme.bodySmall,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        key: const ValueKey('trpg-dice-guidance'),
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          color: colors.tertiaryContainer.withValues(
                            alpha: .55,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SkinIcon(
                              Icons.casino_outlined,
                              color: colors.onTertiaryContainer,
                              size: 19,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    dice.title,
                                    style: textTheme.labelLarge?.copyWith(
                                      color: colors.onTertiaryContainer,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    dice.detail,
                                    style: textTheme.bodySmall?.copyWith(
                                      color: colors.onTertiaryContainer,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: '骰子说明',
                              visualDensity: VisualDensity.compact,
                              onPressed: () => showTrpgDiceHelp(context),
                              icon: const Icon(Icons.help_outline, size: 20),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _GuideLine extends StatelessWidget {
  const _GuideLine({
    required this.icon,
    required this.label,
    required this.content,
  });

  final IconData icon;
  final String label;
  final String content;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SkinIcon(icon, size: 17, color: colors.primary),
        const SizedBox(width: 7),
        SizedBox(
          width: 70,
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        Expanded(
          child: Text(
            content,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

Future<void> showTrpgDiceHelp(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    icon: const SkinIcon(Icons.casino_outlined),
    title: const Text('骰子到底怎么用？'),
    content: const SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('1. 你只需要描述角色想做什么，不用先投骰。'),
          SizedBox(height: 8),
          Text('2. 攻击、调查、潜行、说服等结果不确定的行动，会由规则系统自动选择骰子、属性、技能和难度。'),
          SizedBox(height: 8),
          Text('3. 骰点与修正会产生成功、部分成功或失败；AI 主持必须按照这个真实结果继续剧情。'),
          SizedBox(height: 8),
          Text('4. 涉及陷阱或隐藏情报时可能暗骰，玩家看不到数值，但结果仍然生效。'),
          SizedBox(height: 8),
          Text('5. “手动自由骰”和“私骰”适合自定义随机数或桌外约定；除非主持明确采用，否则不会替代正式剧情检定。'),
        ],
      ),
    ),
    actions: [
      FilledButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('知道了'),
      ),
    ],
  ),
);
