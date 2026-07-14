import 'package:flutter/foundation.dart';

/// Compile-time environment values, injected via `--dart-define-from-file`.
///
/// Nothing in this file is a secret by itself - the actual values live in a
/// gitignored `dart_defines.json` (see `dart_defines.example.json` for the
/// shape) and are baked in at build/run time, e.g.:
///
///   flutter run --dart-define-from-file=dart_defines.json
///
/// This intentionally throws instead of silently falling back to an empty
/// string: a card-rewards app talking to the wrong (or no) backend is worse
/// than a build that fails loudly and tells you to set up your defines file.
class Env {
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
  );
  static const String googleClientId = String.fromEnvironment(
    'GOOGLE_CLIENT_ID',
  );
  static const String geminiApiKey = String.fromEnvironment('GEMINI_API_KEY');
  static const String geminiApiKey2 =
      String.fromEnvironment('GEMINI_API_KEY_2');
  static const String groqApiKey = String.fromEnvironment('GROQ_API_KEY');

  /// Call once, early in `main()`, so a missing dart-defines file fails at
  /// startup with a clear message instead of much later with a confusing
  /// network/auth error.
  static void assertConfigured() {
    final missing = <String>[
      if (supabaseUrl.isEmpty) 'SUPABASE_URL',
      if (supabaseAnonKey.isEmpty) 'SUPABASE_ANON_KEY',
      if (googleClientId.isEmpty) 'GOOGLE_CLIENT_ID',
      if (!kIsWeb && geminiApiKey.isEmpty) 'GEMINI_API_KEY',
      // GEMINI_API_KEY_2 is optional (second key for higher quota via rotation)
    ];
    if (missing.isNotEmpty) {
      throw StateError(
        'Missing required dart-define values: ${missing.join(', ')}.\n'
        'Copy dart_defines.example.json to dart_defines.json, fill in the '
        'real values, and run with:\n'
        '  flutter run --dart-define-from-file=dart_defines.json',
      );
    }
  }
}
