import 'package:flutter/material.dart';

class FlickDarkTheme {
  FlickDarkTheme._();

  static const bg       = Color(0xFF0A0A0F);
  static const surface  = Color(0xFF13131A);
  static const surface2 = Color(0xFF1C1C27);
  static const accent   = Color(0xFF7C6FFF);
  static const accent2  = Color(0xFF38BDF8);
  static const textCol  = Color(0xFFF0F0F5);
  static const muted    = Color(0xFF8B8B9E);
  static const green    = Color(0xFF34D399);
  static const red      = Color(0xFFFF5E7D);
  static const msgOut   = Color(0xFF2D2A5E);
  static const msgIn    = Color(0xFF1C1C27);

  static final theme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: bg,
    colorScheme: const ColorScheme.dark(
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
        borderSide: BorderSide(color: Colors.white.withOpacity(0.06)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.white.withOpacity(0.06)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: accent, width: 1.5),
      ),
    ),
    dividerColor: Colors.white.withOpacity(0.06),
    fontFamily: 'DM Sans',
  );
}