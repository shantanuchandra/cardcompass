import 'package:flutter/foundation.dart';

/// Central error handling service for AI and app-wide error management
class ErrorHandlingService {
  /// Log error with context information
  static void logError(
    String context,
    dynamic error, {
    StackTrace? stackTrace,
    Map<String, dynamic>? additionalData,
  }) {
    if (kDebugMode) {
      print('ERROR [$context]: $error');
      if (stackTrace != null) {
        print('STACK TRACE: $stackTrace');
      }
      if (additionalData != null) {
        print('ADDITIONAL DATA: $additionalData');
      }
    }
    
    // In production, you could send to crash reporting service like:
    // FirebaseCrashlytics.instance.recordError(error, stackTrace);
    // or Sentry.captureException(error, stackTrace: stackTrace);
  }

  /// Handle AI service errors with user-friendly messages
  static String getAiErrorMessage(dynamic error) {
    final errorString = error.toString().toLowerCase();
    
    if (errorString.contains('network') || errorString.contains('connection')) {
      return 'Unable to connect to AI service. Please check your internet connection and try again.';
    } else if (errorString.contains('timeout')) {
      return 'AI service is taking too long to respond. Please try again later.';
    } else if (errorString.contains('quota') || errorString.contains('limit')) {
      return 'AI service is temporarily unavailable due to high demand. Please try again later.';
    } else if (errorString.contains('api key') || errorString.contains('authentication')) {
      return 'AI service configuration error. Please contact support.';
    } else if (errorString.contains('rate limit')) {
      return 'Too many requests. Please wait a moment and try again.';
    } else {
      return 'AI recommendations are temporarily unavailable. Using fallback recommendations.';
    }
  }

  /// Handle general app errors
  static String getGeneralErrorMessage(dynamic error) {
    final errorString = error.toString().toLowerCase();
    
    if (errorString.contains('network') || errorString.contains('connection')) {
      return 'Network connection error. Please check your internet and try again.';
    } else if (errorString.contains('permission')) {
      return 'Permission denied. Please check app permissions in settings.';
    } else if (errorString.contains('storage') || errorString.contains('database')) {
      return 'Storage error. Please check available storage space.';
    } else if (errorString.contains('format') || errorString.contains('parse')) {
      return 'Data format error. Please try refreshing the app.';
    } else {
      return 'An unexpected error occurred. Please try again.';
    }
  }

  /// Check if error is retryable
  static bool isRetryableError(dynamic error) {
    final errorString = error.toString().toLowerCase();
    
    return errorString.contains('network') ||
           errorString.contains('connection') ||
           errorString.contains('timeout') ||
           errorString.contains('server') ||
           errorString.contains('503') ||
           errorString.contains('502') ||
           errorString.contains('504');
  }

  /// Create standardized error result for failed operations
  static Map<String, dynamic> createErrorResult(
    String operation,
    dynamic error, {
    bool useAiFallback = false,
  }) {
    logError(operation, error);
    
    return {
      'success': false,
      'error': true,
      'message': useAiFallback 
          ? getAiErrorMessage(error)
          : getGeneralErrorMessage(error),
      'retryable': isRetryableError(error),
      'operation': operation,
      'timestamp': DateTime.now().toIso8601String(),
    };
  }
}

/// Custom exception for AI service errors
class AiServiceException implements Exception {
  final String message;
  final String? code;
  final dynamic originalError;
  final bool isRetryable;

  const AiServiceException(
    this.message, {
    this.code,
    this.originalError,
    this.isRetryable = false,
  });

  @override
  String toString() => 'AiServiceException: $message';
}

/// Custom exception for data processing errors
class DataProcessingException implements Exception {
  final String message;
  final String? context;
  final dynamic originalError;

  const DataProcessingException(
    this.message, {
    this.context,
    this.originalError,
  });

  @override
  String toString() => 'DataProcessingException: $message';
}

/// Retry mechanism for network operations
class RetryHelper {
  /// Retry an async operation with exponential backoff
  static Future<T> retryOperation<T>(
    Future<T> Function() operation, {
    int maxRetries = 3,
    Duration initialDelay = const Duration(seconds: 1),
    double backoffMultiplier = 2.0,
    bool Function(dynamic error)? retryCondition,
  }) async {
    int attempt = 0;
    Duration delay = initialDelay;

    while (attempt < maxRetries) {
      try {
        return await operation();
      } catch (error) {
        attempt++;
        
        // Check if we should retry
        if (attempt >= maxRetries || 
            (retryCondition != null && !retryCondition(error))) {
          rethrow;
        }

        // Check if error is retryable by default
        if (retryCondition == null && !ErrorHandlingService.isRetryableError(error)) {
          rethrow;
        }

        ErrorHandlingService.logError(
          'RetryHelper',
          'Attempt $attempt failed, retrying in ${delay.inMilliseconds}ms: $error',
        );

        // Wait before retrying
        await Future.delayed(delay);
        delay = Duration(milliseconds: (delay.inMilliseconds * backoffMultiplier).round());
      }
    }

    throw Exception('Max retries ($maxRetries) exceeded');
  }
}

/// Enum for different error severity levels
enum ErrorSeverity {
  low,     // Non-critical errors, app continues normally
  medium,  // Important errors, some features may be affected
  high,    // Critical errors, core functionality impacted
  critical // App-breaking errors, immediate attention required
}

/// Error context data class
class ErrorContext {
  final String operation;
  final String? userId;
  final Map<String, dynamic> metadata;
  final ErrorSeverity severity;
  final DateTime timestamp;

  ErrorContext({
    required this.operation,
    this.userId,
    this.metadata = const {},
    this.severity = ErrorSeverity.medium,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'operation': operation,
    'userId': userId,
    'metadata': metadata,
    'severity': severity.name,
    'timestamp': timestamp.toIso8601String(),
  };
}
