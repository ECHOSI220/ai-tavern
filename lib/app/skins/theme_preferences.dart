import 'theme_definition.dart';

class ThemeSettings {
  const ThemeSettings({
    this.brightness = 1,
    this.blur,
    this.opacity,
    this.overlay,
    this.uiOpacity = 1,
    this.effectsLevel = ThemeEffectsLevel.low,
    this.reduceMotion = false,
    this.customBackground,
    this.chatBackground,
  });
  final double brightness;
  final double? blur, opacity, overlay;

  /// Opacity of UI surfaces (cards, panels and message bubbles), independent
  /// from the wallpaper opacity below them.
  final double uiOpacity;
  final ThemeEffectsLevel effectsLevel;
  final bool reduceMotion;
  final String? customBackground, chatBackground;
  bool get animated =>
      !reduceMotion &&
      (effectsLevel == ThemeEffectsLevel.normal ||
          effectsLevel == ThemeEffectsLevel.high);
  bool get complexEffects =>
      effectsLevel == ThemeEffectsLevel.normal ||
      effectsLevel == ThemeEffectsLevel.high;
  ThemeSettings copyWith({
    double? brightness,
    double? blur,
    double? opacity,
    double? overlay,
    double? uiOpacity,
    ThemeEffectsLevel? effectsLevel,
    bool? reduceMotion,
    String? customBackground,
    String? chatBackground,
    bool resetBackground = false,
    bool resetChat = false,
  }) => ThemeSettings(
    brightness: resetBackground ? 1 : brightness ?? this.brightness,
    blur: resetBackground ? null : blur ?? this.blur,
    opacity: resetBackground ? null : opacity ?? this.opacity,
    overlay: resetBackground ? null : overlay ?? this.overlay,
    uiOpacity: uiOpacity ?? this.uiOpacity,
    effectsLevel: effectsLevel ?? this.effectsLevel,
    reduceMotion: reduceMotion ?? this.reduceMotion,
    customBackground: resetBackground
        ? null
        : customBackground ?? this.customBackground,
    chatBackground: resetChat ? null : chatBackground ?? this.chatBackground,
  );
  Map<String, Object?> toJson() => {
    'brightness': brightness,
    'blur': blur,
    'opacity': opacity,
    'overlay': overlay,
    'uiOpacity': uiOpacity,
    'effectsLevel': effectsLevel.name,
    'reduceMotion': reduceMotion,
    'customBackground': customBackground,
    'chatBackground': chatBackground,
  };
  factory ThemeSettings.fromJson(Map<String, Object?> json) {
    double? number(String key, double min, double max) {
      final v = json[key];
      return v is num && v.isFinite ? v.toDouble().clamp(min, max) : null;
    }

    return ThemeSettings(
      brightness: number('brightness', .4, 1.4) ?? 1,
      blur: number('blur', 0, 20),
      opacity: number('opacity', 0, 1),
      overlay: number('overlay', 0, 1),
      uiOpacity: number('uiOpacity', .35, 1) ?? 1,
      effectsLevel: ThemeEffectsLevel.values.firstWhere(
        (v) => v.name == json['effectsLevel'],
        orElse: () => ThemeEffectsLevel.low,
      ),
      reduceMotion: json['reduceMotion'] == true,
      customBackground: json['customBackground'] is String
          ? json['customBackground'] as String
          : null,
      chatBackground: json['chatBackground'] is String
          ? json['chatBackground'] as String
          : null,
    );
  }
}

class ThemePreference {
  const ThemePreference({
    this.themeId = 'default_clean',
    this.themeSettings = const {},
    this.sessionOverrideIds = const {},
  });
  final String themeId;
  final Map<String, ThemeSettings> themeSettings;

  /// Interface reserved for opt-in per-session skins; no save payload changes.
  final Map<String, String> sessionOverrideIds;
  ThemeSettings get settings => themeSettings[themeId] ?? const ThemeSettings();
  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'themeId': themeId,
    'themeSettings': themeSettings.map((k, v) => MapEntry(k, v.toJson())),
    'sessionOverrideIds': sessionOverrideIds,
  };
  factory ThemePreference.fromJson(Map<String, Object?> json) {
    final raw = json['themeSettings'];
    return ThemePreference(
      themeId: json['themeId'] is String
          ? json['themeId'] as String
          : 'default_clean',
      themeSettings: raw is Map
          ? {
              for (final e in raw.entries)
                if (e.key is String && e.value is Map)
                  e.key as String: ThemeSettings.fromJson(
                    Map<String, Object?>.from(e.value as Map),
                  ),
            }
          : const {},
      sessionOverrideIds: json['sessionOverrideIds'] is Map
          ? {
              for (final e in (json['sessionOverrideIds'] as Map).entries)
                if (e.key is String && e.value is String)
                  e.key as String: e.value as String,
            }
          : const {},
    );
  }
}
