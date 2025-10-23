import 'package:flutter/foundation.dart';

/// Real-time debugger for tracking sync flow execution
/// 
/// Usage:
/// ```dart
/// SyncFlowDebugger.start('user-123');
/// SyncFlowDebugger.logStep('GMAIL_SEARCH', 'Found 5 emails', data: {'count': 5});
/// SyncFlowDebugger.logStep('PDF_UNLOCK', 'Password found', data: {'password': '****'});
/// final report = SyncFlowDebugger.generateReport();
/// ```
class SyncFlowDebugger {
  static final List<DebugStep> _steps = [];
  static DateTime? _startTime;
  static String? _userId;
  static final Map<String, int> _stepCounts = {};
  static final Map<String, Duration> _stepDurations = {};
  static final List<String> _errors = [];
  
  /// Start a new debugging session
  static void start(String userId) {
    _steps.clear();
    _stepCounts.clear();
    _stepDurations.clear();
    _errors.clear();
    _startTime = DateTime.now();
    _userId = userId;
    
    debugPrint('🐛 [SYNC DEBUG] Session started for user: $userId');
    debugPrint('=' * 80);
  }
  
  /// Log a step in the sync flow
  static void logStep(
    String stepName, 
    String message, {
    Map<String, dynamic>? data,
    bool isError = false,
  }) {
    if (_startTime == null) {
      start('unknown');
    }
    
    final now = DateTime.now();
    final elapsed = now.difference(_startTime!);
    
    final step = DebugStep(
      stepName: stepName,
      message: message,
      timestamp: now,
      elapsedTime: elapsed,
      data: data,
      isError: isError,
    );
    
    _steps.add(step);
    _stepCounts[stepName] = (_stepCounts[stepName] ?? 0) + 1;
    
    if (isError) {
      _errors.add('[$stepName] $message');
    }
    
    // Print with proper formatting
    final icon = isError ? '❌' : _getStepIcon(stepName);
    final dataStr = data != null ? ' | Data: ${data.toString()}' : '';
    debugPrint('$icon [$elapsed] $stepName: $message$dataStr');
  }
  
  /// Log the start of a timed operation
  static DateTime startTimer(String operationName) {
    logStep('TIMER_START', operationName);
    return DateTime.now();
  }
  
  /// Log the end of a timed operation and calculate duration
  static void endTimer(String operationName, DateTime startTime) {
    final duration = DateTime.now().difference(startTime);
    _stepDurations[operationName] = duration;
    logStep('TIMER_END', operationName, data: {
      'duration_ms': duration.inMilliseconds,
      'duration_sec': duration.inSeconds,
    });
  }
  
  /// Log an error
  static void logError(String stepName, String error, {Object? exception, StackTrace? stackTrace}) {
    logStep(stepName, error, data: {
      'error': error,
      'exception': exception?.toString(),
    }, isError: true);
    
    if (stackTrace != null) {
      debugPrint('Stack trace: $stackTrace');
    }
  }
  
  /// Generate a comprehensive debug report
  static String generateReport() {
    if (_startTime == null) return 'No debug session started';
    
    final totalDuration = DateTime.now().difference(_startTime!);
    final buffer = StringBuffer();
    
    buffer.writeln('╔════════════════════════════════════════════════════════════════════╗');
    buffer.writeln('║              SYNC FLOW DEBUG REPORT                                ║');
    buffer.writeln('╚════════════════════════════════════════════════════════════════════╝');
    buffer.writeln('');
    buffer.writeln('📊 Session Summary');
    buffer.writeln('  User ID: $_userId');
    buffer.writeln('  Start Time: ${_startTime?.toIso8601String()}');
    buffer.writeln('  Total Duration: ${totalDuration.inSeconds}s (${totalDuration.inMilliseconds}ms)');
    buffer.writeln('  Total Steps: ${_steps.length}');
    buffer.writeln('  Errors: ${_errors.length}');
    buffer.writeln('');
    
    // Step counts
    buffer.writeln('📈 Step Execution Counts');
    final sortedCounts = _stepCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final entry in sortedCounts) {
      buffer.writeln('  ${entry.key.padRight(30)} ${entry.value.toString().padLeft(5)} times');
    }
    buffer.writeln('');
    
    // Timed operations
    if (_stepDurations.isNotEmpty) {
      buffer.writeln('⏱️  Timed Operations');
      final sortedDurations = _stepDurations.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      for (final entry in sortedDurations) {
        buffer.writeln('  ${entry.key.padRight(30)} ${entry.value.inMilliseconds.toString().padLeft(7)}ms');
      }
      buffer.writeln('');
    }
    
    // Errors
    if (_errors.isNotEmpty) {
      buffer.writeln('❌ Errors Encountered');
      for (final error in _errors) {
        buffer.writeln('  • $error');
      }
      buffer.writeln('');
    }
    
    // Timeline
    buffer.writeln('📅 Execution Timeline');
    buffer.writeln('─' * 80);
    for (final step in _steps) {
      final icon = step.isError ? '❌' : _getStepIcon(step.stepName);
      final timeStr = '[${step.elapsedTime.inSeconds}s]'.padLeft(8);
      final stepStr = step.stepName.padRight(25);
      buffer.writeln('$icon $timeStr $stepStr ${step.message}');
      
      if (step.data != null && step.data!.isNotEmpty) {
        for (final entry in step.data!.entries) {
          buffer.writeln('          └─ ${entry.key}: ${entry.value}');
        }
      }
    }
    buffer.writeln('─' * 80);
    
    // Key metrics
    buffer.writeln('');
    buffer.writeln('🎯 Key Metrics');
    final emailsProcessed = _stepCounts['EMAIL_PROCESSED'] ?? 0;
    final emailsStored = _stepCounts['DB_STORED'] ?? 0;
    final transactionsStored = _steps
        .where((s) => s.stepName == 'TRANSACTION_STORED')
        .fold<int>(0, (sum, s) => sum + (s.data?['count'] as int? ?? 1));
    final pdfsUnlocked = _stepCounts['PDF_UNLOCKED'] ?? 0;
    
    buffer.writeln('  📧 Emails Processed: $emailsProcessed');
    buffer.writeln('  💾 Statements Stored: $emailsStored');
    buffer.writeln('  💰 Transactions Stored: $transactionsStored');
    buffer.writeln('  🔓 PDFs Unlocked: $pdfsUnlocked');
    buffer.writeln('  ❌ Errors: ${_errors.length}');
    
    return buffer.toString();
  }
  
  /// Print the report to console
  static void printReport() {
    debugPrint(generateReport());
  }
  
  /// Get all steps for programmatic access
  static List<DebugStep> getSteps() => List.unmodifiable(_steps);
  
  /// Get steps by name
  static List<DebugStep> getStepsByName(String stepName) {
    return _steps.where((s) => s.stepName == stepName).toList();
  }
  
  /// Get all errors
  static List<String> getErrors() => List.unmodifiable(_errors);
  
  /// Clear the current session
  static void clear() {
    _steps.clear();
    _stepCounts.clear();
    _stepDurations.clear();
    _errors.clear();
    _startTime = null;
    _userId = null;
  }
  
  /// Get icon for step type
  static String _getStepIcon(String stepName) {
    const iconMap = {
      'GMAIL_AUTH': '🔐',
      'GMAIL_SEARCH': '🔍',
      'EMAIL_FOUND': '📧',
      'EMAIL_PROCESSED': '📄',
      'PDF_DOWNLOAD': '📥',
      'PDF_UNLOCKED': '🔓',
      'PDF_LOCKED': '🔒',
      'GEMINI_PARSE': '🤖',
      'STATEMENT_INFO': '📊',
      'TRANSACTION_PARSE': '💳',
      'CARD_MAPPING': '🗂️',
      'DB_STORED': '💾',
      'TRANSACTION_STORED': '✅',
      'VALIDATION_FAIL': '⚠️',
      'SKIP_EMAIL': '⏭️',
      'TIMER_START': '⏱️',
      'TIMER_END': '⏹️',
    };
    return iconMap[stepName] ?? '•';
  }
}

/// Represents a single step in the debug flow
class DebugStep {
  final String stepName;
  final String message;
  final DateTime timestamp;
  final Duration elapsedTime;
  final Map<String, dynamic>? data;
  final bool isError;
  
  DebugStep({
    required this.stepName,
    required this.message,
    required this.timestamp,
    required this.elapsedTime,
    this.data,
    this.isError = false,
  });
  
  @override
  String toString() {
    return '$stepName [$elapsedTime]: $message${data != null ? ' | $data' : ''}';
  }
}

/// Mixin to add debugging to services
mixin SyncFlowDebugging {
  void debugStep(String stepName, String message, {Map<String, dynamic>? data}) {
    SyncFlowDebugger.logStep(stepName, message, data: data);
  }
  
  void debugError(String stepName, String error, {Object? exception}) {
    SyncFlowDebugger.logError(stepName, error, exception: exception);
  }
  
  DateTime debugStartTimer(String operationName) {
    return SyncFlowDebugger.startTimer(operationName);
  }
  
  void debugEndTimer(String operationName, DateTime startTime) {
    SyncFlowDebugger.endTimer(operationName, startTime);
  }
}
