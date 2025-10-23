/// Configuration for AI services with automatic fallback mechanism
class AIConfig {
  // Gemini AI API Configuration
  static const String _geminiApiKey = 'AIzaSyD4XddoqY3zquAPiEyuhi_wdH4uaY4LvjE';
  // 'AIzaSyBzvpqB_TnB4HYcmjH3Je_mofieVQU5bWc';
  
  /// List of Gemini models to try in order (fallback chain)
  /// First model is primary, subsequent models are fallbacks when rate limits hit
  static const List<String> geminiModelFallbackChain = [
    'gemini-2.5-flash',          // Primary: Best price-performance, fast and intelligent
    'gemini-2.0-flash',          // Fallback 1: Second gen workhorse, 1M context
    'gemini-2.5-pro',            // Fallback 2: Most advanced, complex reasoning
  ];
  
  /// Current model index in the fallback chain (0 = primary)
  static int _currentModelIndex = 0;
  
  /// Track rate limit errors per model to prevent rapid switching
  static final Map<String, int> _modelRateLimitCount = {};
  
  /// Get current active model
  static String get geminiModel => geminiModelFallbackChain[_currentModelIndex];
  
  // Use v1 API for stable Gemini 2.0 and 2.5 models
  static const String geminiBaseUrl = 'https://generativelanguage.googleapis.com/v1';
  
  /// Get Gemini API key (internal use only)
  static String get geminiApiKey => _geminiApiKey;
  
  /// Get Gemini API endpoint for generating content
  static String get geminiGenerateUrl => '$geminiBaseUrl/models/$geminiModel:generateContent?key=$_geminiApiKey';
  
  /// Get Gemini API endpoint for a specific model
  static String getGeminiGenerateUrlForModel(String model) => 
      '$geminiBaseUrl/models/$model:generateContent?key=$_geminiApiKey';
  
  /// Common request headers for Gemini API
  static Map<String, String> get geminiHeaders => {
    'Content-Type': 'application/json',
  };
  
  /// Switch to next fallback model when rate limit is hit
  /// Returns true if switched successfully, false if no more fallbacks available
  static bool switchToFallbackModel() {
    final currentModel = geminiModel;
    _modelRateLimitCount[currentModel] = (_modelRateLimitCount[currentModel] ?? 0) + 1;
    
    if (_currentModelIndex < geminiModelFallbackChain.length - 1) {
      _currentModelIndex++;
      print('⚠️  Rate limit hit on $currentModel');
      print('🔄 Switching to fallback model: ${geminiModel}');
      print('📊 Fallback chain position: ${_currentModelIndex + 1}/${geminiModelFallbackChain.length}');
      return true;
    } else {
      print('❌ All Gemini models exhausted. No more fallbacks available.');
      print('📊 Rate limit counts: $_modelRateLimitCount');
      return false;
    }
  }
  
  /// Reset to primary model (call this at start of new sync session or after cooldown)
  static void resetToPrimaryModel() {
    if (_currentModelIndex != 0) {
      print('🔄 Resetting to primary model: ${geminiModelFallbackChain[0]}');
      _currentModelIndex = 0;
    }
  }
  
  /// Reset all statistics (for testing purposes)
  static void resetStats() {
    _currentModelIndex = 0;
    _modelRateLimitCount.clear();
  }
  
  /// Get model statistics
  static Map<String, dynamic> getModelStats() {
    return {
      'currentModel': geminiModel,
      'currentIndex': _currentModelIndex,
      'totalModels': geminiModelFallbackChain.length,
      'rateLimitCounts': Map.from(_modelRateLimitCount),
      'remainingFallbacks': geminiModelFallbackChain.length - _currentModelIndex - 1,
    };
  }
  
  /// Check if a response indicates a rate limit error
  static bool isRateLimitError(int statusCode, String? responseBody) {
    if (statusCode == 429) return true; // HTTP 429: Too Many Requests
    if (statusCode == 503) return true; // HTTP 503: Service Unavailable (overloaded)
    
    // Check response body for rate limit messages
    if (responseBody != null) {
      final lowerBody = responseBody.toLowerCase();
      return lowerBody.contains('quota') ||
             lowerBody.contains('rate limit') ||
             lowerBody.contains('too many requests') ||
             lowerBody.contains('overloaded') ||
             lowerBody.contains('resource_exhausted');
    }
    
    return false;
  }
}
