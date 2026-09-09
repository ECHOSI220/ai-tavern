import 'package:flutter/material.dart';
import 'theme_tokens.dart';
import 'theme_craft.dart';
import 'character_theme.dart';

class ThemedPanel extends StatelessWidget {
  const ThemedPanel({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.radius,
    this.color,
    super.key,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double? radius;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    if (SkinCraft.of(context).refined) {
      return CraftedSurface(
        color: color ?? t.surfacePrimary,
        border: t.borderSecondary,
        radius: radius,
        margin: margin,
        padding: padding,
        child: child,
      );
    }
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? t.surfacePrimary,
        borderRadius: BorderRadius.circular(radius ?? t.radius),
        border: Border.all(color: t.borderSecondary, width: t.borderWidth),
      ),
      child: Material(type: MaterialType.transparency, child: child),
    );
  }
}

// Wrappers reuse Material behavior/accessibility; the theme supplies visuals.
class ThemedButton extends StatelessWidget {
  const ThemedButton({required this.child, required this.onPressed, super.key});
  final Widget child;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) =>
      FilledButton(onPressed: onPressed, child: child);
}

class ThemedInput extends StatelessWidget {
  const ThemedInput({
    this.controller,
    required this.label,
    this.readOnly = false,
    super.key,
  });
  final TextEditingController? controller;
  final String label;
  final bool readOnly;
  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    readOnly: readOnly,
    decoration: InputDecoration(labelText: label),
  );
}

class ThemedCard extends StatelessWidget {
  const ThemedCard({required this.child, super.key});
  final Widget child;
  @override
  Widget build(BuildContext context) => Card(child: child);
}

class ThemedDialog extends StatelessWidget {
  const ThemedDialog({
    required this.title,
    required this.content,
    this.actions = const [],
    super.key,
  });
  final Widget title, content;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) =>
      AlertDialog(title: title, content: content, actions: actions);
}

enum ChatBubbleKind { user, ai, system, private, gm }

class ThemedChatBubble extends StatelessWidget {
  const ThemedChatBubble({required this.child, required this.kind, super.key});
  final Widget child;
  final ChatBubbleKind kind;
  static Color foreground(BuildContext context, ChatBubbleKind kind) {
    final t = ThemeTokens.of(context);
    return kind == ChatBubbleKind.ai ? t.aiForeground : t.textPrimary;
  }

  static Color background(BuildContext context, ChatBubbleKind kind) {
    final t = ThemeTokens.of(context);
    return switch (kind) {
      ChatBubbleKind.user => t.userBubble,
      ChatBubbleKind.ai => t.aiBubble,
      ChatBubbleKind.system => t.systemBubble,
      ChatBubbleKind.private => t.privateBubble,
      ChatBubbleKind.gm => t.gmBubble,
    };
  }

  @override
  Widget build(BuildContext context) => ThemedPanel(
    color: background(context, kind),
    child: DefaultTextStyle.merge(
      style: TextStyle(color: foreground(context, kind)),
      child: child,
    ),
  );
}

/// Scoped light parchment foreground; keeps routes, callbacks and message data.
class ThemedMessageContent extends StatelessWidget {
  const ThemedMessageContent({
    required this.light,
    required this.builder,
    super.key,
  });
  final bool light;
  final WidgetBuilder builder;
  @override
  Widget build(BuildContext context) {
    final ext = CharacterThemeExtension.of(context);
    // Only the oath skin uses a light parchment AI card. Other character
    // themes (notably Rapi's dark tactical HUD) must keep their native dark
    // color scheme; applying the parchment ink there made AI replies black on
    // an almost-black panel.
    if (!light ||
        ext == null ||
        SkinCraft.of(context).material != SkinMaterial.oath) {
      return builder(context);
    }
    final parent = Theme.of(context);
    final lightScheme =
        ColorScheme.fromSeed(
          seedColor: ext.ink,
          brightness: Brightness.light,
          surface: ext.ivory,
        ).copyWith(
          primary: const Color(0xff675327),
          onSurface: ext.ink,
          onSurfaceVariant: const Color(0xff455469),
        );
    return Theme(
      data: parent.copyWith(
        colorScheme: lightScheme,
        textTheme: parent.textTheme.apply(
          bodyColor: ext.ink,
          displayColor: ext.ink,
        ),
        iconTheme: IconThemeData(color: ext.ink),
        iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(foregroundColor: ext.ink),
        ),
        popupMenuTheme: parent.popupMenuTheme.copyWith(color: ext.ivory),
        extensions: [
          ...parent.extensions.values.where((e) => e is! SkinCraft),
          SkinCraft.of(context).copyWith(accent: const Color(0xff675327)),
        ],
      ),
      child: Builder(builder: builder),
    );
  }
}

class ThemedNavigation extends StatelessWidget {
  const ThemedNavigation({required this.child, super.key});
  final Widget child;
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: ThemeTokens.of(context).backgroundPrimary,
    child: child,
  );
}

class ThemedTooltip extends StatelessWidget {
  const ThemedTooltip({required this.message, required this.child, super.key});
  final String message;
  final Widget child;
  @override
  Widget build(BuildContext context) => Tooltip(message: message, child: child);
}
