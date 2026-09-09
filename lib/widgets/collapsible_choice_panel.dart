import 'package:flutter/material.dart';

/// A compact bottom panel that can be pulled down to reveal the conversation
/// and pulled back up when the player is ready to choose an action.
class CollapsibleChoicePanel extends StatefulWidget {
  const CollapsibleChoicePanel({
    required this.title,
    required this.child,
    this.action,
    this.busy = false,
    this.initiallyExpanded = true,
    this.onExpansionChanged,
    super.key,
  });

  final String title;
  final Widget child;
  final Widget? action;
  final bool busy;
  final bool initiallyExpanded;
  final ValueChanged<bool>? onExpansionChanged;

  @override
  State<CollapsibleChoicePanel> createState() => _CollapsibleChoicePanelState();
}

class _CollapsibleChoicePanelState extends State<CollapsibleChoicePanel>
    with SingleTickerProviderStateMixin {
  static const _dragThreshold = 24.0;

  late bool _expanded;
  double _dragDistance = 0;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  void _setExpanded(bool value) {
    if (_expanded == value) return;
    setState(() => _expanded = value);
    widget.onExpansionChanged?.call(value);
  }

  void _toggle() => _setExpanded(!_expanded);

  void _onVerticalDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (_dragDistance > _dragThreshold || velocity > 250) {
      _setExpanded(false);
    } else if (_dragDistance < -_dragThreshold || velocity < -250) {
      _setExpanded(true);
    }
    _dragDistance = 0;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final hint = _expanded ? '下拉收起，查看完整剧情' : '上拉展开剧情选项';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          key: const ValueKey('choice-panel-drag-area'),
          behavior: HitTestBehavior.opaque,
          onVerticalDragStart: (_) => _dragDistance = 0,
          onVerticalDragUpdate: (details) {
            _dragDistance += details.delta.dy;
          },
          onVerticalDragEnd: _onVerticalDragEnd,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 4,
                margin: const EdgeInsets.only(bottom: 7),
                decoration: BoxDecoration(
                  color: colors.onSurfaceVariant.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Row(
                children: [
                  const Icon(Icons.alt_route, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: InkWell(
                      onTap: _toggle,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            Text(
                              hint,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(color: colors.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  ?widget.action,
                  IconButton(
                    key: const ValueKey('choice-panel-toggle'),
                    tooltip: _expanded ? '收起选项' : '展开选项',
                    onPressed: _toggle,
                    icon: AnimatedRotation(
                      turns: _expanded ? 0 : 0.5,
                      duration: const Duration(milliseconds: 180),
                      child: const Icon(Icons.keyboard_arrow_down),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (widget.busy) const LinearProgressIndicator(minHeight: 2),
        ClipRect(
          child: AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _expanded
                ? KeyedSubtree(
                    key: const ValueKey('choice-panel-expanded-content'),
                    child: widget.child,
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }
}
