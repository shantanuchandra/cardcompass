/// Minimal Gemini configuration — this project always routes through the
/// gemini-proxy Supabase Edge Function (see gemini_request_service.dart),
/// so no API key or multi-provider fallback logic is needed here.
class AIConfig {
  static const String geminiModel = 'gemini-2.0-flash';

  /// True if the response indicates a rate-limit (429) error.
  static bool isRateLimitError(int statusCode, String body) {
    return statusCode == 429;
  }
}
