import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import '../env.dart';

enum AIProvider { gemini, ollama }

/// Configuration for AI services with automatic fallback mechanism.
///
/// Strategy on 429 Too Many Requests:
///   1. Switch to key 2 (same model) — doubles effective free-tier quota
///   2. If key 2 also 429s, advance to next model in the fallback chain
///   3. If all models exhausted, wait 60 s and reset (handled in parser)
class AIConfig {
  // ──────────────────────────────────────────────────────────────────────────
  // Provider Selection & Settings (dynamic runtime selections)
  // ──────────────────────────────────────────────────────────────────────────
  static AIProvider activeProvider = AIProvider.gemini;
  static String _ollamaUrl = 'http://localhost:11434';
  static String ollamaModel = 'gemma4';

  static String get ollamaUrl {
    // Premium loopback rewrite for Android Emulator accessing local host server
    if (defaultTargetPlatform == TargetPlatform.android &&
        (_ollamaUrl.contains('localhost') || _ollamaUrl.contains('127.0.0.1'))) {
      return _ollamaUrl
          .replaceAll('localhost', '10.0.2.2')
          .replaceAll('127.0.0.1', '10.0.2.2');
    }
    return _ollamaUrl;
  }

  static set ollamaUrl(String val) {
    _ollamaUrl = val;
  }

  /// Initialize and load saved LLM settings from SharedPreferences
  static Future<void> loadSavedConfiguration() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final providerStr = prefs.getString('llm_provider') ?? 'gemini';
      activeProvider = providerStr == 'ollama' ? AIProvider.ollama : AIProvider.gemini;
      _ollamaUrl = prefs.getString('ollama_url') ?? 'http://localhost:11434';
      ollamaModel = prefs.getString('ollama_model') ?? 'gemma4';
      print('💾 Loaded AIConfig: provider=$activeProvider, url=$ollamaUrl, model=$ollamaModel');
    } catch (e) {
      print('⚠️ Failed to load AIConfig from SharedPreferences: $e');
    }
  }

  /// Save LLM settings to SharedPreferences and apply immediately
  static Future<void> saveConfiguration(AIProvider provider, String url, String model) async {
    activeProvider = provider;
    _ollamaUrl = url;
    ollamaModel = model;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('llm_provider', provider == AIProvider.ollama ? 'ollama' : 'gemini');
      await prefs.setString('ollama_url', url);
      await prefs.setString('ollama_model', model);
      print('💾 Saved AIConfig: provider=$provider, url=$url, model=$model');
    } catch (e) {
      print('⚠️ Failed to save AIConfig to SharedPreferences: $e');
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // API Keys — two keys for double free-tier RPM capacity
  // ──────────────────────────────────────────────────────────────────────────
  static const List<String> _apiKeys = [
    Env.geminiApiKey,   // Primary key
    Env.geminiApiKey2,  // Secondary key (set GEMINI_API_KEY_2 in dart_defines.json)
  ];

  /// Index into _apiKeys for the current request
  static int _currentKeyIndex = 0;

  // ──────────────────────────────────────────────────────────────────────────
  // Model Fallback Chain
  // ──────────────────────────────────────────────────────────────────────────
  static const List<String> geminiModelFallbackChain = [
    'gemini-3.5-flash',  // Primary
    'gemini-2.5-flash',  // Fallback 1
    'gemini-2.0-flash',  // Fallback 2
    'gemini-2.5-pro',    // Fallback 3 (last resort)
  ];

  static int _currentModelIndex = 0;

  static final Map<String, int> _modelRateLimitCount = {};

  // ──────────────────────────────────────────────────────────────────────────
  // Accessors
  // ──────────────────────────────────────────────────────────────────────────
  static String get geminiModel => geminiModelFallbackChain[_currentModelIndex];

  static String get _activeKey => _apiKeys[_currentKeyIndex];

  static const String geminiBaseUrl =
      'https://generativelanguage.googleapis.com/v1';

  /// Deprecated; prefer geminiGenerateUrl (uses active key automatically).
  static String get geminiApiKey => _activeKey;

  static String get geminiGenerateUrl =>
      '$geminiBaseUrl/models/$geminiModel:generateContent?key=$_activeKey';

  static String getGeminiGenerateUrlForModel(String model) =>
      '$geminiBaseUrl/models/$model:generateContent?key=$_activeKey';

  static Map<String, String> get geminiHeaders => {
        'Content-Type': 'application/json',
      };

  // ──────────────────────────────────────────────────────────────────────────
  // Rotation Logic
  // ──────────────────────────────────────────────────────────────────────────

  /// Try rotating to the next available API key first (same model).
  /// If all keys are exhausted, advances to the next model and resets keys.
  /// Returns true if there is still something left to try.
  static bool switchToFallbackModel() {
    final currentModel = geminiModel;
    _modelRateLimitCount[currentModel] =
        (_modelRateLimitCount[currentModel] ?? 0) + 1;

    // Try next key first (same model, different quota)
    final nextKeyIndex = _currentKeyIndex + 1;
    final hasAnotherKey =
        nextKeyIndex < _apiKeys.length && _apiKeys[nextKeyIndex].isNotEmpty;

    if (hasAnotherKey) {
      _currentKeyIndex = nextKeyIndex;
      print('⚠️  Rate limit on key $_currentKeyIndex for $currentModel');
      print('🔑 Rotating to API key ${_currentKeyIndex + 1}/${_apiKeys.length} (same model)');
      return true;
    }

    // All keys exhausted for this model — advance to next model, reset keys
    _currentKeyIndex = 0;

    if (_currentModelIndex < geminiModelFallbackChain.length - 1) {
      _currentModelIndex++;
      print('⚠️  All keys exhausted on $currentModel');
      print('🔄 Switching to fallback model: $geminiModel');
      print('📊 Fallback chain position: ${_currentModelIndex + 1}/${geminiModelFallbackChain.length}');
      return true;
    }

    print('❌ All Gemini models + keys exhausted. Rate limit counts: $_modelRateLimitCount');
    return false;
  }

  /// Reset to primary model AND primary key (call at start of new sync session).
  static void resetToPrimaryModel() {
    if (_currentModelIndex != 0 || _currentKeyIndex != 0) {
      print('🔄 Resetting to primary model (${geminiModelFallbackChain[0]}) + key 1');
      _currentModelIndex = 0;
      _currentKeyIndex = 0;
    }
  }

  /// Reset all statistics (for testing).
  static void resetStats() {
    _currentModelIndex = 0;
    _currentKeyIndex = 0;
    _modelRateLimitCount.clear();
  }

  static Map<String, dynamic> getModelStats() => {
        'currentModel': geminiModel,
        'currentKeyIndex': _currentKeyIndex + 1,
        'totalKeys': _apiKeys.where((k) => k.isNotEmpty).length,
        'currentModelIndex': _currentModelIndex,
        'totalModels': geminiModelFallbackChain.length,
        'rateLimitCounts': Map.from(_modelRateLimitCount),
        'remainingFallbacks':
            geminiModelFallbackChain.length - _currentModelIndex - 1,
      };

  // ──────────────────────────────────────────────────────────────────────────
  // Error Detection
  // ──────────────────────────────────────────────────────────────────────────
  static bool isRateLimitError(int statusCode, String? responseBody) {
    if (statusCode == 429) return true;
    if (statusCode == 503) return true;

    if (responseBody != null) {
      final lower = responseBody.toLowerCase();
      return lower.contains('quota') ||
          lower.contains('rate limit') ||
          lower.contains('too many requests') ||
          lower.contains('overloaded') ||
          lower.contains('resource_exhausted');
    }

    return false;
  }
}
