// Reads compile-time dart-defines injected via --dart-define-from-file=dart_defines.json
class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const googleClientId = String.fromEnvironment('GOOGLE_CLIENT_ID');
  static const geminiApiKey = String.fromEnvironment('GEMINI_API_KEY');

  static void assertConfigured() {
    assert(supabaseUrl.isNotEmpty, 'SUPABASE_URL is not set');
    assert(supabaseAnonKey.isNotEmpty, 'SUPABASE_ANON_KEY is not set');
    assert(googleClientId.isNotEmpty, 'GOOGLE_CLIENT_ID is not set');
  }
}
