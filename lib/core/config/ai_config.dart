/// Minimal Gemini configuration — this project always routes through the
/// gemini-proxy Supabase Edge Function (see gemini_request_service.dart),
/// so no API key or multi-provider fallback logic is needed here.
class AIConfig {
  // Must match one of the models in the gemini-proxy Edge Function's
  // allowedModels set (supabase/functions/gemini-proxy/index.ts on main) —
  // any other model name is rejected with a 400 "Invalid Gemini request".
  static const String geminiModel = 'gemini-3.6-flash';

  /// True if the response indicates a rate-limit (429) error.
  static bool isRateLimitError(int statusCode, String body) {
    return statusCode == 429;
  }
}
