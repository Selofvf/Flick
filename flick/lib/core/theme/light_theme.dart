import 'package:flutter/material.dart';

class FlickLightTheme {
  FlickLightTheme._();

  static const bg       = Color(0xFFF0F2F8);
  static const surface  = Color(0xFFFFFFFF);
  static const surface2 = Color(0xFFF0F2F8);
  static const accent   = Color(0xFF7C6FFF);
  static const accent2  = Color(0xFF38BDF8);
  static const textCol  = Color(0xFF0F0F1A);
  static const muted    = Color(0xFF6B7280);
  static const green    = Color(0xFF34D399);
  static const red      = Color(0xFFFF5E7D);
  static const msgOut   = Color(0xFFDDD9FF);
  static const msgIn    = Color(0xFFE8EAF5);

  static final theme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: bg,
    colorScheme: const ColorScheme.light(
      background: bg,
      surface: surface,
      primary: accent,
      onPrimary: Colors.white,
      secondary: accent2,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: surface,
      foregroundColor: textCol,
      elevation: 0,
      titleTextStyle: TextStyle(
        fontFamily: 'Syne', fontSize: 18,
        fontWeight: FontWeight.w800, color: textCol,
      ),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: surface,
      selectedItemColor: accent,
      unselectedItemColor: muted,
      type: BottomNavigationBarType.fixed,
      elevation: 0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface2,
      hintStyle: const TextStyle(color: muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.black.withOpacity(0.08)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.black.withOpacity(0.08)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: accent, width: 1.5),
      ),
    ),
    dividerColor: Colors.black.withOpacity(0.08),
    fontFamily: 'DM Sans',
  );
}