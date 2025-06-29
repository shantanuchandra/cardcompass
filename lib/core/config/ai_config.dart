/// Configuration for AI services
class AIConfig {
  // Gemini AI API Configuration
  static const String _geminiApiKey = 'AIzaSyD4XddoqY3zquAPiEyuhi_wdH4uaY4LvjE';
  // 'AIzaSyBzvpqB_TnB4HYcmjH3Je_mofieVQU5bWc';
  static const String geminiModel = 'gemini-2.0-flash';
  static const String geminiBaseUrl = 'https://generativelanguage.googleapis.com/v1beta';
  
  /// Get Gemini API key (internal use only)
  static String get geminiApiKey => _geminiApiKey;
  
  /// Get Gemini API endpoint for generating content
  static String get geminiGenerateUrl => '$geminiBaseUrl/models/$geminiModel:generateContent?key=$_geminiApiKey';
  
  /// Common request headers for Gemini API
  static Map<String, String> get geminiHeaders => {
    'Content-Type': 'application/json',
  };
}
