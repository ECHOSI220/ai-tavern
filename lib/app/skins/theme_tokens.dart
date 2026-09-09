import 'package:flutter/material.dart';

/// All application colors, including semantic message colors, live here.
@immutable
class ThemeTokens extends ThemeExtension<ThemeTokens> {
  const ThemeTokens({
    required this.backgroundPrimary,
    required this.backgroundSecondary,
    required this.surfacePrimary,
    required this.surfaceSecondary,
    required this.surfaceElevated,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.accentPrimary,
    required this.accentSecondary,
    required this.borderPrimary,
    required this.borderSecondary,
    required this.success,
    required this.warning,
    required this.danger,
    required this.info,
    required this.shadow,
    required this.overlay,
    required this.userBubble,
    required this.aiBubble,
    required this.systemBubble,
    required this.privateBubble,
    required this.gmBubble,
    Color? aiForeground,
    this.radius = 16,
    this.borderWidth = 1,
    this.elevation = 1,
  }) : aiForeground = aiForeground ?? textPrimary;

  final Color backgroundPrimary, backgroundSecondary;
  final Color surfacePrimary, surfaceSecondary, surfaceElevated;
  final Color textPrimary, textSecondary, textMuted;
  final Color accentPrimary, accentSecondary, borderPrimary, borderSecondary;
  final Color success, warning, danger, info, shadow, overlay;
  final Color userBubble, aiBubble, systemBubble, privateBubble, gmBubble;
  final Color aiForeground;
  final double radius, borderWidth, elevation;

  static ThemeTokens of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<ThemeTokens>() ?? fromScheme(theme.colorScheme);
  }

  static ThemeTokens fromScheme(
    ColorScheme c, {
    Color? background,
    double radius = 16,
    double elevation = 1,
  }) {
    final dark = c.brightness == Brightness.dark;
    Color semantic(Color light, Color night) => dark ? night : light;
    return ThemeTokens(
      backgroundPrimary: background ?? c.surface,
      backgroundSecondary: c.surfaceContainerLow,
      surfacePrimary: c.surface,
      surfaceSecondary: c.surfaceContainer,
      surfaceElevated: c.surfaceContainerHigh,
      textPrimary: c.onSurface,
      textSecondary: c.onSurfaceVariant,
      textMuted: c.onSurfaceVariant,
      accentPrimary: c.primary,
      accentSecondary: c.secondary,
      borderPrimary: c.outline,
      borderSecondary: c.outlineVariant,
      success: semantic(const Color(0xff17683b), const Color(0xff80dcaa)),
      warning: semantic(const Color(0xff7a4b00), const Color(0xffffcc75)),
      danger: c.error,
      info: semantic(const Color(0xff215ab5), const Color(0xffa1c7ff)),
      shadow: c.shadow,
      overlay: dark ? Colors.black : Colors.white,
      userBubble: Color.alphaBlend(c.primary.withValues(alpha: .13), c.surface),
      aiBubble: c.surfaceContainerLow,
      systemBubble: c.surfaceContainer,
      privateBubble: Color.alphaBlend(
        c.secondary.withValues(alpha: .14),
        c.surface,
      ),
      gmBubble: c.surfaceContainerLow,
      radius: radius,
      elevation: elevation,
    );
  }

  ThemeTokens withUiOpacity(double opacity) {
    final value = opacity.clamp(.35, 1.0);
    Color surface(Color color) => color.withValues(alpha: value);
    return ThemeTokens(
      backgroundPrimary: backgroundPrimary,
      backgroundSecondary: surface(backgroundSecondary),
      surfacePrimary: surface(surfacePrimary),
      surfaceSecondary: surface(surfaceSecondary),
      surfaceElevated: surface(surfaceElevated),
      textPrimary: textPrimary,
      textSecondary: textSecondary,
      textMuted: textMuted,
      accentPrimary: accentPrimary,
      accentSecondary: accentSecondary,
      borderPrimary: borderPrimary,
      borderSecondary: borderSecondary,
      success: success,
      warning: warning,
      danger: danger,
      info: info,
      shadow: shadow,
      overlay: overlay,
      userBubble: surface(userBubble),
      // Light parchment needs a readable backing even at minimum UI opacity.
      aiBubble: aiForeground == textPrimary
          ? surface(aiBubble)
          : aiBubble.withValues(alpha: .88 + value * .12),
      aiForeground: aiForeground,
      systemBubble: surface(systemBubble),
      privateBubble: surface(privateBubble),
      gmBubble: surface(gmBubble),
      radius: radius,
      borderWidth: borderWidth,
      elevation: elevation,
    );
  }

  Map<String, Color> get colors => {
    'backgroundPrimary': backgroundPrimary,
    'backgroundSecondary': backgroundSecondary,
    'surfacePrimary': surfacePrimary,
    'surfaceSecondary': surfaceSecondary,
    'surfaceElevated': surfaceElevated,
    'textPrimary': textPrimary,
    'textSecondary': textSecondary,
    'textMuted': textMuted,
    'accentPrimary': accentPrimary,
    'accentSecondary': accentSecondary,
    'borderPrimary': borderPrimary,
    'borderSecondary': borderSecondary,
    'success': success,
    'warning': warning,
    'danger': danger,
    'info': info,
    'shadow': shadow,
    'overlay': overlay,
    'userBubble': userBubble,
    'aiBubble': aiBubble,
    'aiForeground': aiForeground,
    'systemBubble': systemBubble,
    'privateBubble': privateBubble,
    'gmBubble': gmBubble,
  };

  @override
  ThemeTokens copyWith({
    double? radius,
    double? elevation,
    Color? userBubble,
    Color? aiBubble,
    Color? aiForeground,
    Color? privateBubble,
    Color? gmBubble,
  }) => ThemeTokens(
    backgroundPrimary: backgroundPrimary,
    backgroundSecondary: backgroundSecondary,
    surfacePrimary: surfacePrimary,
    surfaceSecondary: surfaceSecondary,
    surfaceElevated: surfaceElevated,
    textPrimary: textPrimary,
    textSecondary: textSecondary,
    textMuted: textMuted,
    accentPrimary: accentPrimary,
    accentSecondary: accentSecondary,
    borderPrimary: borderPrimary,
    borderSecondary: borderSecondary,
    success: success,
    warning: warning,
    danger: danger,
    info: info,
    shadow: shadow,
    overlay: overlay,
    userBubble: userBubble ?? this.userBubble,
    aiBubble: aiBubble ?? this.aiBubble,
    aiForeground: aiForeground ?? this.aiForeground,
    systemBubble: systemBubble,
    privateBubble: privateBubble ?? this.privateBubble,
    gmBubble: gmBubble ?? this.gmBubble,
    radius: radius ?? this.radius,
    borderWidth: borderWidth,
    elevation: elevation ?? this.elevation,
  );

  @override
  ThemeTokens lerp(covariant ThemeTokens? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return ThemeTokens(
      backgroundPrimary: mix(backgroundPrimary, other.backgroundPrimary),
      backgroundSecondary: mix(backgroundSecondary, other.backgroundSecondary),
      surfacePrimary: mix(surfacePrimary, other.surfacePrimary),
      surfaceSecondary: mix(surfaceSecondary, other.surfaceSecondary),
      surfaceElevated: mix(surfaceElevated, other.surfaceElevated),
      textPrimary: mix(textPrimary, other.textPrimary),
      textSecondary: mix(textSecondary, other.textSecondary),
      textMuted: mix(textMuted, other.textMuted),
      accentPrimary: mix(accentPrimary, other.accentPrimary),
      accentSecondary: mix(accentSecondary, other.accentSecondary),
      borderPrimary: mix(borderPrimary, other.borderPrimary),
      borderSecondary: mix(borderSecondary, other.borderSecondary),
      success: mix(success, other.success),
      warning: mix(warning, other.warning),
      danger: mix(danger, other.danger),
      info: mix(info, other.info),
      shadow: mix(shadow, other.shadow),
      overlay: mix(overlay, other.overlay),
      userBubble: mix(userBubble, other.userBubble),
      aiBubble: mix(aiBubble, other.aiBubble),
      aiForeground: mix(aiForeground, other.aiForeground),
      systemBubble: mix(systemBubble, other.systemBubble),
      privateBubble: mix(privateBubble, other.privateBubble),
      gmBubble: mix(gmBubble, other.gmBubble),
      radius: radius + (other.radius - radius) * t,
      borderWidth: borderWidth + (other.borderWidth - borderWidth) * t,
      elevation: elevation + (other.elevation - elevation) * t,
    );
  }
}
