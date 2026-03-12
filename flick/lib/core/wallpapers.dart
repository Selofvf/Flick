import 'package:flutter/material.dart';

class WallpaperItem {
  final String id;
  final String label;
  final String category;
  final Color  color1;
  final Color  color2;
  const WallpaperItem({
    required this.id,
    required this.label,
    required this.category,
    required this.color1,
    required this.color2,
  });
}

const wallpapers = [
  // ── Тёмные ────────────────────────────────────────────────────────────────
  WallpaperItem(id: 'dark_1', label: 'Ночь',    category: 'Тёмные',
    color1: Color(0xFF0A0A0F), color2: Color(0xFF14142A)),
  WallpaperItem(id: 'dark_2', label: 'Мистика', category: 'Тёмные',
    color1: Color(0xFF0F051E), color2: Color(0xFF1E0A3C)),
  WallpaperItem(id: 'dark_3', label: 'Океан',   category: 'Тёмные',
    color1: Color(0xFF050F14), color2: Color(0xFF0A232D)),
  WallpaperItem(id: 'dark_4', label: 'Вулкан',  category: 'Тёмные',
    color1: Color(0xFF140A0A), color2: Color(0xFF2D0F0F)),

  // ── Светлые ───────────────────────────────────────────────────────────────
  WallpaperItem(id: 'light_1', label: 'Лаванда', category: 'Светлые',
    color1: Color(0xFFF0F2FF), color2: Color(0xFFE1E6FF)),
  WallpaperItem(id: 'light_2', label: 'Персик',  category: 'Светлые',
    color1: Color(0xFFFFF8F0), color2: Color(0xFFFFEBDC)),
  WallpaperItem(id: 'light_3', label: 'Мята',    category: 'Светлые',
    color1: Color(0xFFF0FFF8), color2: Color(0xFFDCFFEB)),
  WallpaperItem(id: 'light_4', label: 'Сирень',  category: 'Светлые',
    color1: Color(0xFFF8F0FF), color2: Color(0xFFEBDCFF)),

  // ── Природа ───────────────────────────────────────────────────────────────
  WallpaperItem(id: 'season_autumn', label: 'Осень', category: 'Природа',
    color1: Color(0xFFFFB830), color2: Color(0xFFC85A1E)),
  WallpaperItem(id: 'season_winter', label: 'Зима',  category: 'Природа',
    color1: Color(0xFFC8E6FF), color2: Color(0xFF64A0E6)),
  WallpaperItem(id: 'season_spring', label: 'Весна', category: 'Природа',
    color1: Color(0xFF96DC64), color2: Color(0xFF3C8C1E)),
  WallpaperItem(id: 'season_summer', label: 'Лето',  category: 'Природа',
    color1: Color(0xFF64B4FF), color2: Color(0xFF1E78C8)),

  // ── Градиенты ─────────────────────────────────────────────────────────────
  WallpaperItem(id: 'grad_1', label: 'Космос',  category: 'Градиенты',
    color1: Color(0xFF7C6FFF), color2: Color(0xFF38BDF8)),
  WallpaperItem(id: 'grad_2', label: 'Закат',   category: 'Градиенты',
    color1: Color(0xFFFF5E7D), color2: Color(0xFFFF9A3C)),
  WallpaperItem(id: 'grad_3', label: 'Аврора',  category: 'Градиенты',
    color1: Color(0xFF34D399), color2: Color(0xFF38BDF8)),
  WallpaperItem(id: 'grad_4', label: 'Сумерки', category: 'Градиенты',
    color1: Color(0xFFA78BFA), color2: Color(0xFFF472B6)),
];

WallpaperItem? wallpaperById(String id) {
  try {
    return wallpapers.firstWhere((w) => w.id == id);
  } catch (_) {
    return null;
  }
}
