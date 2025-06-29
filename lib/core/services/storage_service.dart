import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cardcompass/shared/models/user.dart';
import 'package:cardcompass/shared/models/credit_card.dart';
import 'package:cardcompass/shared/models/transaction.dart';

class StorageService {
  static const String _userKey = 'user_data';
  static const String _cardsKey = 'user_cards';
  static const String _transactionsKey = 'user_transactions';
  static const String _settingsKey = 'app_settings';

  final SharedPreferences _prefs;

  StorageService(this._prefs);

  // User operations
  Future<void> saveUser(User user) async {
    await _prefs.setString(_userKey, jsonEncode(user.toJson()));
  }

  Future<User?> getUser() async {
    final userJson = _prefs.getString(_userKey);
    if (userJson != null) {
      try {
        return User.fromJson(jsonDecode(userJson));
      } catch (e) {
        // Handle corrupted data
        await clearUser();
        return null;
      }
    }
    return null;
  }

  Future<void> clearUser() async {
    await _prefs.remove(_userKey);
  }

  // Cards operations
  Future<void> saveCards(List<CreditCard> cards) async {
    final cardsJson = cards.map((card) => card.toJson()).toList();
    await _prefs.setString(_cardsKey, jsonEncode(cardsJson));
  }

  Future<List<CreditCard>> getCards() async {
    final cardsJson = _prefs.getString(_cardsKey);
    if (cardsJson != null) {
      try {
        final List<dynamic> cardsList = jsonDecode(cardsJson);
        return cardsList.map((json) => CreditCard.fromJson(json)).toList();
      } catch (e) {
        // Handle corrupted data
        await clearCards();
        return [];
      }
    }
    return [];
  }

  Future<void> clearCards() async {
    await _prefs.remove(_cardsKey);
  }

  // Transactions operations
  Future<void> saveTransactions(List<Transaction> transactions) async {
    final transactionsJson = transactions.map((transaction) => transaction.toJson()).toList();
    await _prefs.setString(_transactionsKey, jsonEncode(transactionsJson));
  }

  Future<List<Transaction>> getTransactions() async {
    final transactionsJson = _prefs.getString(_transactionsKey);
    if (transactionsJson != null) {
      try {
        final List<dynamic> transactionsList = jsonDecode(transactionsJson);
        return transactionsList.map((json) => Transaction.fromJson(json)).toList();
      } catch (e) {
        // Handle corrupted data
        await clearTransactions();
        return [];
      }
    }
    return [];
  }

  Future<void> clearTransactions() async {
    await _prefs.remove(_transactionsKey);
  }

  // Settings operations
  Future<void> saveSetting(String key, dynamic value) async {
    final settings = await getSettings();
    settings[key] = value;
    await _prefs.setString(_settingsKey, jsonEncode(settings));
  }

  Future<T?> getSetting<T>(String key) async {
    final settings = await getSettings();
    return settings[key] as T?;
  }

  Future<Map<String, dynamic>> getSettings() async {
    final settingsJson = _prefs.getString(_settingsKey);
    if (settingsJson != null) {
      try {
        return Map<String, dynamic>.from(jsonDecode(settingsJson));
      } catch (e) {
        // Handle corrupted data
        return {};
      }
    }
    return {};
  }

  Future<void> clearSettings() async {
    await _prefs.remove(_settingsKey);
  }

  // Clear all data
  Future<void> clearAll() async {
    await Future.wait([
      clearUser(),
      clearCards(),
      clearTransactions(),
      clearSettings(),
    ]);
  }

  // Utility methods
  Future<bool> hasKey(String key) async {
    return _prefs.containsKey(key);
  }

  Future<Set<String>> getAllKeys() async {
    return _prefs.getKeys();
  }

  // First launch detection
  Future<bool> isFirstLaunch() async {
    const key = 'is_first_launch';
    final isFirst = _prefs.getBool(key) ?? true;
    if (isFirst) {
      await _prefs.setBool(key, false);
    }
    return isFirst;
  }

  // Theme persistence
  Future<void> saveThemeMode(String mode) async {
    await _prefs.setString('theme_mode', mode);
  }

  Future<String?> getThemeMode() async {
    return _prefs.getString('theme_mode');
  }

  // Language persistence
  Future<void> saveLanguage(String languageCode) async {
    await _prefs.setString('language_code', languageCode);
  }

  Future<String?> getLanguage() async {
    return _prefs.getString('language_code');
  }

  // Onboarding completion
  Future<void> setOnboardingCompleted() async {
    await _prefs.setBool('onboarding_completed', true);
  }

  Future<bool> isOnboardingCompleted() async {
    return _prefs.getBool('onboarding_completed') ?? false;
  }

  // Cache timestamps for data freshness
  Future<void> setCacheTimestamp(String key) async {
    await _prefs.setInt('${key}_timestamp', DateTime.now().millisecondsSinceEpoch);
  }

  Future<bool> isCacheValid(String key, Duration maxAge) async {
    final timestamp = _prefs.getInt('${key}_timestamp');
    if (timestamp == null) return false;
    
    final cacheTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return DateTime.now().difference(cacheTime) < maxAge;
  }

  Future<void> clearCacheTimestamp(String key) async {
    await _prefs.remove('${key}_timestamp');
  }
}
