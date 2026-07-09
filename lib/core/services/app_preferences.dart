import 'package:shared_preferences/shared_preferences.dart';

/// Thin wrapper around SharedPreferences for app-wide user preferences
/// that need to persist locally regardless of guest/authenticated mode.
class AppPreferences {
  static const _keyNotifications = 'pref_notifications_enabled';
  static const _keyBiometric = 'pref_biometric_enabled';
  static const _keyDarkMode = 'pref_dark_mode_enabled';
  static const _keyLanguage = 'pref_language';
  static const _keyCurrency = 'pref_currency';
  static const _keyAutoSync = 'pref_auto_sync';

  final SharedPreferences _prefs;

  AppPreferences(this._prefs);

  bool get notificationsEnabled => _prefs.getBool(_keyNotifications) ?? true;
  Future<void> setNotificationsEnabled(bool value) => _prefs.setBool(_keyNotifications, value);

  bool get biometricEnabled => _prefs.getBool(_keyBiometric) ?? false;
  Future<void> setBiometricEnabled(bool value) => _prefs.setBool(_keyBiometric, value);

  bool get darkModeEnabled => _prefs.getBool(_keyDarkMode) ?? false;
  Future<void> setDarkModeEnabled(bool value) => _prefs.setBool(_keyDarkMode, value);

  String get language => _prefs.getString(_keyLanguage) ?? 'English';
  Future<void> setLanguage(String value) => _prefs.setString(_keyLanguage, value);

  String get currency => _prefs.getString(_keyCurrency) ?? 'INR';
  Future<void> setCurrency(String value) => _prefs.setString(_keyCurrency, value);

  bool get autoSyncEnabled => _prefs.getBool(_keyAutoSync) ?? true;
  Future<void> setAutoSyncEnabled(bool value) => _prefs.setBool(_keyAutoSync, value);
}
