import '../../app/skins/skin_icon.dart';
import '../../app/skins/character_theme.dart';
import 'package:flutter/material.dart';
import '../../app/skins/theme_tokens.dart';
import '../../app/skins/themed_components.dart';
import '../../app/skins/theme_background.dart';
import '../../app/skins/theme_manager.dart';
import '../../app/skins/theme_craft.dart';

import '../../models/trpg_party_models.dart';

/// Shared visual language for solo and multiplayer TRPG play screens.
///
/// These widgets intentionally contain no game logic. They keep the two play
/// modes visually consistent while allowing each screen to own its state.
class TrpgPlaySurface extends StatelessWidget {
  const TrpgPlaySurface({
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.margin = EdgeInsets.zero,
    this.radius = 20,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return ThemedPanel(
      margin: margin,
      padding: padding,
      radius: ThemeTokens.of(context).radius,
      child: child,
    );
  }
}

class TrpgFact {
  const TrpgFact(this.icon, this.label, {this.emphasized = false});

  final IconData icon;
  final String label;
  final bool emphasized;
}

class TrpgSceneSummary extends StatelessWidget {
  const TrpgSceneSummary({
    required this.title,
    required this.subtitle,
    this.facts = const [],
    this.trailing,
    this.dense = false,
    super.key,
  });

  final String title;
  final String subtitle;
  final List<TrpgFact> facts;
  final Widget? trailing;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return TrpgPlaySurface(
      margin: EdgeInsets.fromLTRB(12, dense ? 5 : 8, 12, 4),
      padding: EdgeInsets.fromLTRB(12, dense ? 8 : 11, 12, dense ? 8 : 11),
      radius: dense ? 16 : 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: dense ? 34 : 40,
                height: dense ? 34 : 40,
                decoration: BoxDecoration(
                  color: colors.primaryContainer.withValues(alpha: .7),
                  borderRadius: BorderRadius.circular(dense ? 11 : 13),
                ),
                child: SkinIcon(
                  Icons.explore_outlined,
                  size: dense ? 19 : 24,
                  color: colors.primary,
                ),
              ),
              SizedBox(width: dense ? 9 : 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            ],
          ),
          if (facts.isNotEmpty) ...[
            SizedBox(height: dense ? 6 : 10),
            if (dense)
              SizedBox(
                height: 30,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: facts.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 6),
                  itemBuilder: (context, index) =>
                      _factChip(context, facts[index], dense: true),
                ),
              )
            else
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: facts
                    .map((fact) => _factChip(context, fact))
                    .toList(),
              ),
          ],
        ],
      ),
    );
  }

  Widget _factChip(BuildContext context, TrpgFact fact, {bool dense = false}) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final foreground = fact.emphasized
        ? colors.onErrorContainer
        : colors.onSurfaceVariant;
    final background = fact.emphasized
        ? colors.errorContainer
        : colors.surfaceContainerHighest.withValues(alpha: .72);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 9, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SkinIcon(fact.icon, size: 14, color: foreground),
          const SizedBox(width: 5),
          Text(
            fact.label,
            style: theme.textTheme.labelMedium?.copyWith(color: foreground),
          ),
        ],
      ),
    );
  }
}

class TrpgActionSpec {
  const TrpgActionSpec({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
}

class TrpgQuickActions extends StatelessWidget {
  const TrpgQuickActions({required this.actions, super.key});

  final List<TrpgActionSpec> actions;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        itemCount: actions.length,
        separatorBuilder: (_, _) => const SizedBox(width: 7),
        itemBuilder: (context, index) {
          final action = actions[index];
          return Material(
            color: colors.surfaceContainerLow,
            shape: StadiumBorder(
              side: BorderSide(
                color: colors.outlineVariant.withValues(alpha: .55),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: action.onPressed,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    SkinIcon(action.icon, size: 17, color: colors.primary),
                    const SizedBox(width: 6),
                    Text(action.label),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Fixed background used by every TRPG play timeline.
///
/// This is intentionally explicit instead of inheriting a transparent engine
/// surface. Some Android renderers expose that surface as a light-gray block
/// when an empty scroll viewport fills the remaining screen.
const Color kTrpgTimelineBackground = Color(0xFF171311);

Color trpgTimelineBackground(BuildContext context) =>
    Theme.of(context).extension<ThemeTokens>()?.backgroundPrimary ??
    kTrpgTimelineBackground;

/// Scrollable play timeline with a guaranteed dark backing surface.
class TrpgTimelineViewport extends StatelessWidget {
  const TrpgTimelineViewport({
    required this.children,
    this.controller,
    this.padding = const EdgeInsets.fromLTRB(12, 8, 12, 4),
    super.key,
  });

  final List<Widget> children;
  final ScrollController? controller;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final immersive =
        ThemeScope.maybeOf(context)?.getCurrentTheme().immersiveArtwork ??
        false;
    final body = children.isEmpty
        ? ColoredBox(
            key: const ValueKey('trpg_timeline_empty_space'),
            color: immersive
                ? Colors.transparent
                : trpgTimelineBackground(context),
          )
        : LayoutBuilder(
            builder: (context, constraints) {
              final messages = Padding(
                padding: padding,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: children,
                ),
              );
              return SingleChildScrollView(
                key: const ValueKey('trpg_timeline_scroll_view'),
                controller: controller,
                physics: const ClampingScrollPhysics(),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.hasBoundedHeight
                        ? constraints.maxHeight
                        : 0,
                  ),
                  child: ColoredBox(
                    key: const ValueKey('trpg_timeline_content_backdrop'),
                    color: immersive
                        ? Colors.transparent
                        : trpgTimelineBackground(context),
                    child: immersive
                        ? messages
                        : _TimelineSkin(child: messages),
                  ),
                ),
              );
            },
          );
    // This outer paint is always fully opaque, including empty/error states.
    // For immersive art the wallpaper belongs to the VIEWPORT, not the growing
    // scroll child. New messages and scrolling cannot stretch or multiply Saber.
    return ColoredBox(
      key: const ValueKey('trpg_timeline_dark_backdrop'),
      color: trpgTimelineBackground(context),
      child: immersive ? ThemeBackground(chat: true, child: body) : body,
    );
  }
}

enum TrpgMessageTone { gm, npc, player, system, dice, private }

class _TimelineSkin extends StatelessWidget {
  const _TimelineSkin({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => ThemeScope.maybeOf(context) == null
      ? child
      : ThemeBackground(chat: true, child: child);
}

class TrpgMessageBubble extends StatelessWidget {
  const TrpgMessageBubble({
    required this.label,
    required this.content,
    required this.tone,
    this.time,
    super.key,
  });

  final String label;
  final String content;
  final TrpgMessageTone tone;
  final DateTime? time;

  @override
  Widget build(BuildContext context) {
    if (content.trim().isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isPlayer = tone == TrpgMessageTone.player;
    final tokens = ThemeTokens.of(context);
    final craft = SkinCraft.of(context);
    final parchment =
        tone == TrpgMessageTone.npc && craft.material == SkinMaterial.oath;
    final foreground = parchment ? tokens.aiForeground : tokens.textPrimary;
    final accent = switch (tone) {
      TrpgMessageTone.player => colors.primary,
      TrpgMessageTone.dice => colors.tertiary,
      TrpgMessageTone.private =>
        craft.material == SkinMaterial.oath ? colors.primary : colors.secondary,
      TrpgMessageTone.system => colors.outline,
      _ => parchment ? const Color(0xff675327) : colors.primary,
    };
    final background = switch (tone) {
      TrpgMessageTone.player => tokens.userBubble,
      TrpgMessageTone.dice => tokens.systemBubble,
      TrpgMessageTone.private => tokens.privateBubble,
      TrpgMessageTone.system => tokens.systemBubble,
      TrpgMessageTone.gm => tokens.gmBubble,
      _ => tokens.aiBubble,
    };

    return Align(
      alignment: isPlayer ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 760),
        margin: EdgeInsets.only(
          left: isPlayer ? 38 : 0,
          right: isPlayer ? 0 : 38,
          bottom: craft.refined ? 18 : 10,
        ),
        padding: craft.refined
            ? const EdgeInsets.fromLTRB(18, 16, 18, 20)
            : const EdgeInsets.fromLTRB(13, 10, 13, 12),
        decoration: craft.refined
            ? ShapeDecoration(
                shape: craft.frame(
                  border: tokens.borderSecondary,
                  ornament:
                      tone == TrpgMessageTone.private ||
                      (craft.material == SkinMaterial.oath &&
                          tone == TrpgMessageTone.gm),
                ),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color.lerp(background, accent, .025)!, background],
                ),
              )
            : BoxDecoration(
                color: background,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(tokens.radius),
                  topRight: Radius.circular(tokens.radius),
                  bottomLeft: Radius.circular(isPlayer ? tokens.radius : 5),
                  bottomRight: Radius.circular(isPlayer ? 5 : tokens.radius),
                ),
                // Keep the edge deliberately dark/subtle on Android.  A bright
                // outline combined with the platform text-selection compositing
                // used to leave a white strip under every message paragraph.
                border: Border.all(
                  color: colors.onSurface.withValues(
                    alpha: isPlayer ? .10 : .06,
                  ),
                ),
              ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              runSpacing: 4,
              children: [
                if (craft.refined)
                  SkinIcon(
                    switch (tone) {
                      TrpgMessageTone.private => Icons.lock_outline,
                      TrpgMessageTone.player => Icons.person_outline,
                      TrpgMessageTone.dice => Icons.casino_outlined,
                      _ => Icons.auto_awesome_outlined,
                    },
                    size: 14,
                    color: accent,
                  )
                else
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (time != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    _formatTime(time!),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: parchment
                          ? const Color(0xff455469)
                          : colors.onSurfaceVariant.withValues(alpha: .85),
                    ),
                  ),
                ],
              ],
            ),
            SizedBox(height: craft.refined ? 12 : 6),
            Text(
              content,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: foreground,
                height: craft.refined ? 1.75 : 1.55,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatTime(DateTime value) {
    final local = value.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}

class TrpgPartyDistribution extends StatelessWidget {
  const TrpgPartyDistribution({
    required this.groups,
    required this.names,
    super.key,
  });

  final List<PartyGroup> groups;
  final Map<String, String> names;

  @override
  Widget build(BuildContext context) {
    if (groups.isEmpty) return const SizedBox.shrink();
    return ExpansionTile(
      dense: true,
      title: const Text('队伍位置'),
      leading: const SkinIcon(Icons.groups_outlined),
      children: groups
          .where((group) => group.status == PartyGroupStatus.active)
          .map(
            (group) => ListTile(
              dense: true,
              leading: const SkinIcon(Icons.place_outlined, size: 19),
              title: Text(group.locationId.isEmpty ? '未定位' : group.locationId),
              subtitle: Text(
                group.characterIds.map((id) => names[id] ?? id).join('、'),
              ),
            ),
          )
          .toList(),
    );
  }
}

class TrpgEventTile extends StatelessWidget {
  const TrpgEventTile({
    required this.icon,
    required this.title,
    required this.details,
    super.key,
  });

  final IconData icon;
  final String title;
  final String details;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Align(
      alignment: Alignment.center,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 640),
        margin: const EdgeInsets.only(bottom: 9),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow.withValues(alpha: .82),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: colors.outlineVariant.withValues(alpha: .38),
          ),
        ),
        child: Row(
          children: [
            SkinIcon(icon, size: 18, color: colors.secondary),
            const SizedBox(width: 9),
            Text(
              title,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                details,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TrpgComposer extends StatelessWidget {
  const TrpgComposer({
    required this.controller,
    required this.hintText,
    required this.onSend,
    this.enabled = true,
    this.sending = false,
    this.modeSelector,
    this.onCancelConfirmation,
    super.key,
  });

  final TextEditingController controller;
  final String hintText;
  final VoidCallback onSend;
  final bool enabled;
  final bool sending;
  final Widget? modeSelector;
  final VoidCallback? onCancelConfirmation;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: TrpgPlaySurface(
        margin: const EdgeInsets.fromLTRB(10, 3, 10, 9),
        padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
        radius: 21,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (modeSelector != null) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 0, 2, 7),
                child: modeSelector!,
              ),
              Divider(
                height: 1,
                color: colors.outlineVariant.withValues(alpha: .4),
              ),
              const SizedBox(height: 6),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('trpg_action_input'),
                    controller: controller,
                    enabled: enabled,
                    minLines: 1,
                    maxLines: 5,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: hintText,
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: CharacterThemeExtension.of(context) != null
                          ? UnderlineInputBorder(
                              borderSide: BorderSide(color: colors.primary),
                            )
                          : InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 10,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 46,
                  height: 46,
                  child: IconButton.filled(
                    key: const ValueKey('trpg_send_action'),
                    tooltip: onCancelConfirmation == null ? '发送' : '撤回确认',
                    onPressed:
                        !sending && (enabled || onCancelConfirmation != null)
                        ? onCancelConfirmation ?? onSend
                        : null,
                    icon: sending
                        ? const SizedBox(
                            width: 19,
                            height: 19,
                            child: ThemedLoadingIndicator(strokeWidth: 2),
                          )
                        : SkinIcon(
                            onCancelConfirmation == null
                                ? Icons.arrow_upward_rounded
                                : Icons.close_rounded,
                            color: colors.onPrimary,
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class TrpgInlineNotice extends StatelessWidget {
  const TrpgInlineNotice({
    required this.message,
    this.isError = false,
    this.action,
    super.key,
  });

  final String message;
  final bool isError;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: isError ? colors.errorContainer : colors.secondaryContainer,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: [
          SkinIcon(
            isError ? Icons.error_outline : Icons.info_outline,
            size: 19,
            color: isError
                ? colors.onErrorContainer
                : colors.onSecondaryContainer,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(message, maxLines: 3)),
          ?action,
        ],
      ),
    );
  }
}
