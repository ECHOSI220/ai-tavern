import 'package:flutter/material.dart';

abstract final class TavernTheme {
  static const _gold = Color(0xFFD6A84B);
  static const _ink = Color(0xFF171311);
  static const _surface = Color(0xFF28201D);

  static ThemeData get dark {
    final scheme = ColorScheme.fromSeed(
      seedColor: _gold,
      brightness: Brightness.dark,
      surface: _surface,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: _ink,
      canvasColor: _ink,
      navigationRailTheme: const NavigationRailThemeData(backgroundColor: _ink),
      drawerTheme: const DrawerThemeData(backgroundColor: _ink),
      appBarTheme: const AppBarTheme(
        backgroundColor: _ink,
        foregroundColor: Color(0xFFF3E8D0),
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: _surface,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFF5C4933)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF211A18),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _gold, width: 1.5),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: _gold,
        foregroundColor: Color(0xFF21160A),
      ),
    );
  }
}
