class ParsingLogger {
  /// Toggle detailed, verbose debugging logs
  static bool verbose = false;

  static final List<void Function(String)> _listeners = [];

  /// Add a listener to receive real-time log updates
  static void addListener(void Function(String) listener) {
    _listeners.add(listener);
  }

  /// Remove a listener
  static void removeListener(void Function(String) listener) {
    _listeners.remove(listener);
  }

  static void _notifyListeners(String message) {
    for (final listener in List.from(_listeners)) {
      try {
        listener(message);
      } catch (e) {
        // Suppress listener callback errors
      }
    }
  }

  /// Log a detailed error (always printed)
  static void error(String message, [Object? error, StackTrace? stackTrace]) {
    final formatted = '❌ ERROR: $message${error != null ? ' ($error)' : ''}';
    print(formatted);
    _notifyListeners(formatted);
  }

  /// Log a detailed warning (always printed)
  static void warning(String message) {
    final formatted = '⚠️ WARNING: $message';
    print(formatted);
    _notifyListeners(formatted);
  }

  /// Log an extracted transaction in detail (always printed)
  static void transaction(String message) {
    final formatted = '✅ TRANSACTION: $message';
    print(formatted);
    _notifyListeners(formatted);
  }

  /// Log a concise, high-level summary of a stage (always printed)
  static void summary(String message) {
    final formatted = '📋 SUMMARY: $message';
    print(formatted);
    _notifyListeners(formatted);
  }

  /// Log micro-level internal debugging details (muted by default)
  static void debug(String message) {
    final formatted = '🔍 DEBUG: $message';
    if (verbose) {
      print(formatted);
    }
    _notifyListeners(formatted);
  }
}
