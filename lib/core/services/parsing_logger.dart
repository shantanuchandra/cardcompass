class ParsingLogger {
  /// Toggle detailed, verbose debugging logs
  static bool verbose = false;

  /// Log a detailed error (always printed)
  static void error(String message, [Object? error, StackTrace? stackTrace]) {
    print('❌ ERROR: $message${error != null ? ' ($error)' : ''}');
  }

  /// Log a detailed warning (always printed)
  static void warning(String message) {
    print('⚠️ WARNING: $message');
  }

  /// Log an extracted transaction in detail (always printed)
  static void transaction(String message) {
    print('✅ TRANSACTION: $message');
  }

  /// Log a concise, high-level summary of a stage (always printed)
  static void summary(String message) {
    print('📋 SUMMARY: $message');
  }

  /// Log micro-level internal debugging details (muted by default)
  static void debug(String message) {
    if (verbose) {
      print('🔍 DEBUG: $message');
    }
  }
}
