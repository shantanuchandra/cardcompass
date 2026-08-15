// Reads compile-time dart-defines injected via --dart-define-from-file=dart_defines.json
class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const googleClientId = String.fromEnvironment('GOOGLE_CLIENT_ID');
  static const geminiApiKey = String.fromEnvironment('GEMINI_API_KEY');

  static void assertConfigured() {
    validateValues(
      supabaseUrl: supabaseUrl,
      supabaseAnonKey: supabaseAnonKey,
      googleClientId: googleClientId,
    );
  }

  static void validateValues({
    required String supabaseUrl,
    required String supabaseAnonKey,
    required String googleClientId,
  }) {
    final uri = Uri.tryParse(supabaseUrl);
    if (supabaseUrl.isEmpty ||
        uri == null ||
        !uri.hasScheme ||
        uri.host.isEmpty ||
        (uri.scheme != 'https' && uri.scheme != 'http')) {
      throw StateError(
        'SUPABASE_URL is missing or invalid. Build with '
        '--dart-define-from-file=dart_defines.json.',
      );
    }
    if (supabaseAnonKey.isEmpty) {
      throw StateError('SUPABASE_ANON_KEY is not set.');
    }
    if (googleClientId.isEmpty) {
      throw StateError('GOOGLE_CLIENT_ID is not set.');
    }
  }
}
