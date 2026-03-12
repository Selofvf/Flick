import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'core/theme/dark_theme.dart';
import 'core/theme/light_theme.dart';
import 'core/router.dart';
import 'main.dart';

final themeModeProvider =
    StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  return ThemeModeNotifier();
});

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  final _box = Hive.box('settings');
  ThemeModeNotifier()
      : super(_load(Hive.box('settings').get('theme', defaultValue: 'dark')));
  static ThemeMode _load(String v) =>
      v == 'light' ? ThemeMode.light : ThemeMode.dark;
  void toggle() {
    final next = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    _box.put('theme', next == ThemeMode.dark ? 'dark' : 'light');
    state = next;
  }
}

class FlickApp extends ConsumerWidget {
  const FlickApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final router    = ref.watch(routerProvider);

    // Передаём router в main.dart чтобы FCM мог навигировать
    setRouter(router);

    return MaterialApp.router(
      title: 'Flick',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: FlickLightTheme.theme,
      darkTheme: FlickDarkTheme.theme,
      routerConfig: router,
    );
  }
}
