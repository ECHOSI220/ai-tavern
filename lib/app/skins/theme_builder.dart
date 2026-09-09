import 'package:flutter/material.dart';
import 'theme_definition.dart';
import 'theme_preferences.dart';
import 'theme_craft.dart';
import 'skin_artwork.dart';
import 'character_theme.dart';

abstract final class SkinThemeBuilder {
  static ThemeData build(
    ThemeDefinition definition,
    Brightness brightness, {
    ThemeSettings settings = const ThemeSettings(),
    bool transparentScaffold = false,
  }) {
    final c = definition.scheme(brightness);
    final oath = definition.material == SkinMaterial.oath;
    final tactical = definition.material == SkinMaterial.tactical;
    final digitalStage = definition.material == SkinMaterial.digitalStage;
    final clockworkVoice = definition.material == SkinMaterial.clockworkVoice;
    final vocalSkin = digitalStage || clockworkVoice;
    final characterTheme = definition.category == 'character_theme';
    final t = definition
        .tokens(brightness)
        .withUiOpacity(
          settings.uiOpacity *
              (oath
                  ? .94
                  : tactical
                  ? .97
                  : vocalSkin
                  ? .96
                  : 1),
        );
    final craft = SkinCraft(
      material: definition.material,
      accent: t.accentPrimary,
      secondary: t.accentSecondary,
      line: t.borderSecondary,
      radius: t.radius,
    );
    final shape = craft.refined
        ? craft.frame()
        : RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(t.radius),
            side: BorderSide(color: t.borderSecondary, width: t.borderWidth),
          );
    final buttonShape = craft.refined
        ? craft.frame(ornament: false, border: t.borderPrimary, corner: 8)
        : RoundedRectangleBorder(borderRadius: BorderRadius.circular(t.radius));
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: c,
      fontFamily: definition.fontFamilyPreference,
      fontFamilyFallback: const [
        'Microsoft YaHei',
        'Noto Sans CJK SC',
        'sans-serif',
      ],
    );
    final text = base.textTheme.apply(
      bodyColor: t.textPrimary,
      displayColor: t.textPrimary,
    );
    return base.copyWith(
      extensions: [
        t,
        craft,
        SkinArtworkTheme(definition),
        if (characterTheme)
          CharacterThemeExtension(
            motion: settings.animated,
            effects: settings.effectsLevel != ThemeEffectsLevel.off,
            gold: t.accentPrimary,
            ivory: t.textPrimary,
            blue: t.accentSecondary,
            ink: t.backgroundPrimary,
            wine: t.privateBubble,
          ),
      ],
      pageTransitionsTheme: characterTheme
          ? PageTransitionsTheme(
              builders: {
                for (final platform in TargetPlatform.values)
                  platform: OathPageTransitionsBuilder(
                    enabled: settings.animated,
                  ),
              },
            )
          : base.pageTransitionsTheme,
      scaffoldBackgroundColor: transparentScaffold
          ? Colors.transparent
          : t.backgroundPrimary,
      canvasColor: t.surfacePrimary,
      shadowColor: t.shadow,
      textTheme: text.copyWith(
        headlineSmall: text.headlineSmall?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: craft.refined ? 1.0 : null,
        ),
        titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w600),
        labelLarge: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        bodyLarge: text.bodyLarge?.copyWith(
          height: 1.5,
          letterSpacing: definition.letterSpacing,
        ),
        bodyMedium: text.bodyMedium?.copyWith(
          height: 1.5,
          letterSpacing: definition.letterSpacing,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: definition.immersiveArtwork
            ? t.backgroundPrimary.withValues(alpha: .45)
            : t.backgroundPrimary,
        foregroundColor: t.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: t.surfacePrimary,
        surfaceTintColor: Colors.transparent,
        elevation: settings.complexEffects ? t.elevation : 0,
        shape: shape,
        clipBehavior: Clip.antiAlias,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: t.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        shape: shape,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: t.surfaceElevated,
        modalBackgroundColor: t.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        shape: shape,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: t.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        shape: shape,
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: t.backgroundPrimary,
        surfaceTintColor: Colors.transparent,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: t.backgroundPrimary,
        indicatorColor: t.userBubble,
        selectedIconTheme: IconThemeData(color: t.accentPrimary),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: t.backgroundPrimary,
        indicatorColor: t.userBubble,
        surfaceTintColor: Colors.transparent,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: t.backgroundPrimary,
        selectedItemColor: t.accentPrimary,
        unselectedItemColor: t.textSecondary,
      ),
      dividerTheme: DividerThemeData(color: t.borderSecondary),
      iconTheme: IconThemeData(color: t.textSecondary),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: t.surfaceSecondary,
        hintStyle: TextStyle(color: t.textMuted),
        labelStyle: TextStyle(color: t.textSecondary),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(t.radius),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(t.radius),
          borderSide: BorderSide(color: t.borderPrimary),
        ),
        focusedBorder: characterTheme
            ? OathInputBorder(
                focused: true,
                borderRadius: BorderRadius.circular(t.radius),
                borderSide: BorderSide(color: t.accentPrimary, width: 1.5),
              )
            : OutlineInputBorder(
                borderRadius: BorderRadius.circular(t.radius),
                borderSide: BorderSide(color: t.accentPrimary, width: 1.5),
              ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: oath
              ? const Color(0xff233e60)
              : tactical
              ? const Color(0xff841b25)
              : digitalStage
              ? const Color(0xff087b7c)
              : clockworkVoice
              ? const Color(0xff9c2634)
              : null,
          foregroundColor: oath || tactical || vocalSkin ? t.textPrimary : null,
          disabledBackgroundColor: oath || tactical || vocalSkin
              ? t.surfaceSecondary
              : null,
          disabledForegroundColor: oath || tactical || vocalSkin
              ? t.textMuted.withValues(alpha: .5)
              : null,
          side: oath || tactical || vocalSkin
              ? BorderSide(color: t.borderPrimary)
              : null,
          shape: buttonShape,
          minimumSize: const Size(48, 44),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          backgroundColor: oath
              ? const Color(0xffeee8da)
              : tactical
              ? const Color(0xff0e1318)
              : digitalStage
              ? const Color(0xff071f29)
              : clockworkVoice
              ? const Color(0xff25171a)
              : null,
          foregroundColor: oath
              ? const Color(0xff203047)
              : tactical
              ? t.textPrimary
              : vocalSkin
              ? t.textPrimary
              : null,
          disabledBackgroundColor: oath || tactical || vocalSkin
              ? t.surfaceSecondary
              : null,
          disabledForegroundColor: oath || tactical || vocalSkin
              ? t.textMuted.withValues(alpha: .5)
              : null,
          shape: buttonShape,
          side: BorderSide(color: t.borderPrimary),
          minimumSize: const Size(48, 44),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(shape: buttonShape),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: c.primary,
        foregroundColor: c.onPrimary,
        shape: tactical || vocalSkin
            ? craft.frame(ornament: false, corner: 6)
            : RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(t.radius),
              ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: t.textPrimary,
          borderRadius: BorderRadius.circular(6),
        ),
        textStyle: TextStyle(color: t.backgroundPrimary),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: t.surfaceElevated,
        contentTextStyle: TextStyle(color: t.textPrimary),
        actionTextColor: t.accentPrimary,
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: t.surfaceSecondary,
        selectedColor: t.userBubble,
        side: BorderSide(color: t.borderSecondary),
        labelStyle: text.labelLarge?.copyWith(color: t.textPrimary),
        shape: tactical || vocalSkin
            ? craft.frame(ornament: false, corner: 4)
            : RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(
                  craft.refined ? 5 : t.radius,
                ),
              ),
      ),
    );
  }
}
