import 'package:flutter/material.dart';
import 'theme_tokens.dart';
import 'theme_craft.dart';

/// Art-directed palettes avoid deriving every surface from the same seed.
@immutable
class SkinPalette {
  const SkinPalette({
    required this.surface,
    required this.recessed,
    required this.raised,
    required this.text,
    required this.muted,
    required this.line,
    required this.softLine,
    required this.accent,
    required this.onAccent,
    required this.secondary,
  });
  final Color surface, recessed, raised, text, muted, line, softLine;
  final Color accent, onAccent, secondary;
}

enum SkinMode { system, light, dark }

enum BackgroundPattern {
  plain,
  city,
  stars,
  wood,
  arches,
  mountains,
  petals,
  grid,
  waves,
  scanlines,
}

enum ThemeEffectsLevel { off, low, normal, high }

@immutable
class ThemeDefinition {
  const ThemeDefinition({
    required this.id,
    required this.name,
    required this.description,
    required this.mode,
    required this.seed,
    required this.background,
    this.secondary,
    this.backgroundImage,
    this.artworkAlignment = Alignment.center,
    this.portraitArtworkScale = 1,
    this.pattern = BackgroundPattern.plain,
    this.backgroundOpacity = .3,
    this.backgroundBlur = 6,
    this.overlayOpacity = .3,
    this.radius = 16,
    this.elevation = 1,
    this.animatedBackground = false,
    this.fontFamilyPreference,
    this.letterSpacing = 0,
    this.metadata = const {},
    this.material = SkinMaterial.standard,
    this.palette,
    this.category = 'theme',
    this.chatBackgroundImage,
    this.characterImage,
    this.portraitBackgroundImage,
    this.immersiveArtwork = false,
    this.assetManifest,
  });
  final String id, name, description;
  final String category;
  final String? chatBackgroundImage, assetManifest;

  /// Decorative skin character, never a player/NPC identity or story injection.
  final String? characterImage;

  /// A separately composed mobile wallpaper, not a crop of a character card.
  final String? portraitBackgroundImage;
  final bool immersiveArtwork;
  final SkinMode mode;
  final Color seed, background;
  final Color? secondary;
  final String? backgroundImage, fontFamilyPreference;
  final Alignment artworkAlignment;
  final double portraitArtworkScale;
  final BackgroundPattern pattern;
  final double backgroundOpacity,
      backgroundBlur,
      overlayOpacity,
      radius,
      elevation,
      letterSpacing;
  final bool animatedBackground;
  final Map<String, String> metadata;
  final SkinMaterial material;
  final SkinPalette? palette;

  Brightness brightness(Brightness system) => switch (mode) {
    SkinMode.system => system,
    SkinMode.light => Brightness.light,
    SkinMode.dark => Brightness.dark,
  };
  ColorScheme scheme(Brightness system) {
    final b = brightness(system);
    final generated = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: b,
      secondary: secondary,
      surface: mode == SkinMode.system
          ? null
          : Color.lerp(
              background,
              b == Brightness.dark ? Colors.white : Colors.black,
              .035,
            ),
    );
    final p = palette;
    if (p == null) return generated;
    return generated.copyWith(
      primary: p.accent,
      onPrimary: p.onAccent,
      primaryContainer: Color.lerp(p.surface, p.accent, .12),
      onPrimaryContainer: p.text,
      secondary: p.secondary,
      onSecondary: p.onAccent,
      secondaryContainer: Color.lerp(p.surface, p.secondary, .12),
      onSecondaryContainer: p.text,
      surface: p.surface,
      onSurface: p.text,
      onSurfaceVariant: p.muted,
      surfaceDim: p.recessed,
      surfaceBright: p.raised,
      surfaceContainerLowest: background,
      surfaceContainerLow: p.surface,
      surfaceContainer: p.recessed,
      surfaceContainerHigh: p.raised,
      surfaceContainerHighest: p.raised,
      outline: p.line,
      outlineVariant: p.softLine,
    );
  }

  ThemeTokens tokens(Brightness system) {
    final c = scheme(system);
    final tokens = ThemeTokens.fromScheme(
      c,
      background: mode == SkinMode.system
          ? (system == Brightness.dark
                ? const Color(0xff141619)
                : const Color(0xfff6f7f9))
          : background,
      radius: radius,
      elevation: elevation,
    );
    return switch (material) {
      SkinMaterial.oath => tokens.copyWith(
        userBubble: const Color(0xff172d50),
        aiBubble: const Color(0xffeee8da),
        aiForeground: const Color(0xff203047),
        privateBubble: const Color(0xff382031),
        gmBubble: const Color(0xff10253c),
      ),
      SkinMaterial.tactical => tokens.copyWith(
        userBubble: const Color(0xff43141a),
        aiBubble: const Color(0xff15191e),
        aiForeground: const Color(0xfff2f3f4),
        privateBubble: const Color(0xff29141b),
        gmBubble: const Color(0xff10171d),
      ),
      SkinMaterial.digitalStage => tokens.copyWith(
        userBubble: const Color(0xff063f46),
        aiBubble: const Color(0xff0b2633),
        aiForeground: const Color(0xffecffff),
        privateBubble: const Color(0xff15394a),
        gmBubble: const Color(0xff082e39),
      ),
      SkinMaterial.clockworkVoice => tokens.copyWith(
        userBubble: const Color(0xff5a1720),
        aiBubble: const Color(0xff25191c),
        aiForeground: const Color(0xfffff2dc),
        privateBubble: const Color(0xff3a1821),
        gmBubble: const Color(0xff21191a),
      ),
      _ => tokens,
    };
  }

  Map<String, Object?> get typography => {
    'fontFamily': fontFamilyPreference,
    'letterSpacing': letterSpacing,
    'bodyHeight': 1.5,
  };
  Map<String, Object> get panels => {'radius': radius, 'elevation': elevation};
  Map<String, Object> get buttons => {'radius': radius, 'accent': seed};
  Map<String, Object> get inputBox => {'radius': radius, 'filled': true};
  Map<String, Object> get navigation => {'selectedAccent': seed};
  Map<String, Object> get icons => {
    'style': 'material-outlined',
    'accent': seed,
  };
  Map<String, Object> get borders => {'width': 1.0, 'radius': radius};
  Map<String, Object> get shadows => {'elevation': elevation};
  Map<String, Object> get effects => {
    'pattern': pattern.name,
    'animated': animatedBackground,
  };
  Map<String, Object> get animations => {
    'durationMs': 220,
    'lowIntensity': true,
  };
  Map<String, Object> get diceStyle => {'accent': seed, 'radius': radius};
  Map<String, Object> get trpgStyle => {
    'radius': radius,
    'semanticColors': true,
  };
  Map<String, Color> colors(Brightness system) => tokens(system).colors;
  Color backgroundOverlay(Brightness system) => tokens(system).overlay;
  Map<String, Color> chatBubbles(Brightness system) {
    final t = tokens(system);
    return {
      'user': t.userBubble,
      'ai': t.aiBubble,
      'system': t.systemBubble,
      'private': t.privateBubble,
      'gm': t.gmBubble,
    };
  }
}

/// Future packs contain data and assets only. No executable/script fields.
abstract final class ThemePackSchema {
  static const version = 1;
  static const allowedFiles = [
    'theme.json',
    'background.png',
    'preview.png',
    'icons/',
    'effects/',
  ];
}

/// Reserved outside campaign/character data; overrides default to disabled.
class CharacterBackgroundOverride {
  const CharacterBackgroundOverride(
    this.characterId, {
    this.path,
    this.enabled = false,
  });
  final String characterId;
  final String? path;
  final bool enabled;
}
