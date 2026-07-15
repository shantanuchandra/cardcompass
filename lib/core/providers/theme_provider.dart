import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Theme mode provider for CardCompass.
///
/// Uses a simple [Provider] that reads the stored theme preference.
/// To change the theme, call [updateThemeMode] which writes to
/// SharedPreferences and invalidates the provider to trigger a rebuild.

const String _kThemeModeKey = 'theme_mode';

/// Global ref holder — set once in the app's ConsumerWidget build.
/// This avoids the Riverpod 3 complexity with Notifier codegen.
WidgetRef? _globalRef;

/// Internal mutable state — the provider reads this on build.
ThemeMode _currentThemeMode = ThemeMode.dark;

final themeModeProvider = Provider<ThemeMode>((ref) {
  return _currentThemeMode;
});

/// Call from app startup to hydrate the theme from SharedPreferences.
Future<void> loadPersistedThemeMode() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_kThemeModeKey);
    if (stored != null) {
      _currentThemeMode = ThemeMode.values.firstWhere(
        (m) => m.name == stored,
        orElse: () => ThemeMode.dark,
      );
    }
  } catch (_) {
    // Default to dark
  }
}

/// Updates theme mode, persists to SharedPreferences, and rebuilds.
Future<void> setThemeMode(WidgetRef ref, ThemeMode mode) async {
  _currentThemeMode = mode;
  ref.invalidate(themeModeProvider);
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemeModeKey, mode.name);
  } catch (_) {
    // Ignore persistence failures
  }
}
