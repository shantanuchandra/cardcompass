import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

/// Type tag for a logged Gemini call.
enum GeminiCallType {
  cardRecommendation,
  spendingOptimization,
}

/// A single persisted log entry for one Gemini AI call.
class GeminiCallLog {
  const GeminiCallLog({
    required this.id,
    required this.type,
    required this.timestamp,
    required this.provider,
    required this.durationMs,
    required this.usedMockFallback,
    required this.inputSummary,
    required this.output,
    this.errorMessage,
  });

  final String id;
  final GeminiCallType type;
  final String timestamp; // ISO 8601
  final String provider; // 'gemini' | 'groq' | 'ollama'
  final int durationMs;
  final bool usedMockFallback;

  /// Lightweight summary of the input (never stores raw PII / full PDF text).
  final Map<String, dynamic> inputSummary;

  /// The full structured output list returned by the call.
  final List<Map<String, dynamic>> output;

  /// Non-null when the call threw or fell back due to an error.
  final String? errorMessage;

  Map<String, dynamic> toHive() => {
        'id': id,
        'type': type.name,
        'timestamp': timestamp,
        'provider': provider,
        'durationMs': durationMs,
        'usedMockFallback': usedMockFallback,
        'inputSummary': jsonEncode(inputSummary),
        'output': jsonEncode(output),
        'errorMessage': errorMessage,
      };

  factory GeminiCallLog.fromHive(Map<dynamic, dynamic> raw) {
    List<Map<String, dynamic>> _decodeOutput(dynamic v) {
      if (v is String) {
        final decoded = jsonDecode(v);
        if (decoded is List) {
          return decoded
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      }
      return [];
    }

    Map<String, dynamic> _decodeInputSummary(dynamic v) {
      if (v is String) {
        final decoded = jsonDecode(v);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      }
      return {};
    }

    return GeminiCallLog(
      id: raw['id']?.toString() ?? '',
      type: GeminiCallType.values.firstWhere(
        (t) => t.name == raw['type'],
        orElse: () => GeminiCallType.cardRecommendation,
      ),
      timestamp: raw['timestamp']?.toString() ?? '',
      provider: raw['provider']?.toString() ?? 'gemini',
      durationMs: (raw['durationMs'] as num?)?.toInt() ?? 0,
      usedMockFallback: raw['usedMockFallback'] == true,
      inputSummary: _decodeInputSummary(raw['inputSummary']),
      output: _decodeOutput(raw['output']),
      errorMessage: raw['errorMessage']?.toString(),
    );
  }
}

/// Singleton service for persisting [GeminiCallLog] entries to a local Hive
/// box. Logs are capped at [maxEntries] (newest wins) to avoid unbounded disk
/// growth. No user PII or raw statement text is ever persisted here.
class GeminiCallLogService {
  static final GeminiCallLogService _instance =
      GeminiCallLogService._internal();
  factory GeminiCallLogService() => _instance;
  GeminiCallLogService._internal();

  static const String _boxName = 'gemini_call_logs';

  /// Maximum number of log entries kept on disk.
  static const int maxEntries = 200;

  // ─── Write ────────────────────────────────────────────────────────────────

  Future<void> logRecommendationCall({
    required String provider,
    required int durationMs,
    required Map<String, dynamic> userProfile,
    required List<Map<String, dynamic>> spendingData,
    required List<Map<String, dynamic>> result,
    bool usedMockFallback = false,
    String? errorMessage,
  }) async {
    await _write(GeminiCallLog(
      id: _newId(),
      type: GeminiCallType.cardRecommendation,
      timestamp: DateTime.now().toIso8601String(),
      provider: provider,
      durationMs: durationMs,
      usedMockFallback: usedMockFallback,
      inputSummary: {
        'spendingCategoryCount': spendingData.length,
        'topCategories': spendingData
            .take(3)
            .map((e) => e['category']?.toString() ?? '')
            .toList(),
        'annualIncome': userProfile['annualIncome'],
        'creditScore': userProfile['creditScore'],
      },
      output: result,
      errorMessage: errorMessage,
    ));
  }

  Future<void> logOptimizationCall({
    required String provider,
    required int durationMs,
    required int transactionCount,
    required int cardCount,
    required List<Map<String, dynamic>> result,
    bool usedMockFallback = false,
    String? errorMessage,
  }) async {
    await _write(GeminiCallLog(
      id: _newId(),
      type: GeminiCallType.spendingOptimization,
      timestamp: DateTime.now().toIso8601String(),
      provider: provider,
      durationMs: durationMs,
      usedMockFallback: usedMockFallback,
      inputSummary: {
        'transactionCount': transactionCount,
        'cardCount': cardCount,
      },
      output: result,
      errorMessage: errorMessage,
    ));
  }

  // ─── Read ─────────────────────────────────────────────────────────────────

  /// All logs, newest first.
  Future<List<GeminiCallLog>> getLogs() async {
    try {
      final box = await Hive.openBox(_boxName);
      final raw = box.values
          .whereType<Map>()
          .map((e) => GeminiCallLog.fromHive(e))
          .toList();
      raw.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return raw;
    } catch (e) {
      debugPrint('⚠️ GeminiCallLogService.getLogs failed: $e');
      return [];
    }
  }

  /// Logs filtered to [type], newest first.
  Future<List<GeminiCallLog>> getLogsForType(GeminiCallType type) async {
    final all = await getLogs();
    return all.where((log) => log.type == type).toList();
  }

  /// Aggregate stats for the Evals dashboard.
  Future<Map<String, dynamic>> getStats() async {
    final logs = await getLogs();
    if (logs.isEmpty) {
      return {
        'totalCalls': 0,
        'mockFallbackRate': 0.0,
        'avgDurationMs': 0,
        'providerCounts': <String, int>{},
        'recommendationCallCount': 0,
        'optimizationCallCount': 0,
        'avgConfidenceScore': 0.0,
        'avgRewardRateDelta': 0.0,
      };
    }

    final recLogs = logs
        .where((l) => l.type == GeminiCallType.cardRecommendation)
        .toList();
    final optLogs = logs
        .where((l) => l.type == GeminiCallType.spendingOptimization)
        .toList();

    final mockCount = logs.where((l) => l.usedMockFallback).length;

    final providerCounts = <String, int>{};
    for (final log in logs) {
      providerCounts[log.provider] =
          (providerCounts[log.provider] ?? 0) + 1;
    }

    // Average confidence across all recommendation calls
    double totalConf = 0;
    int confCount = 0;
    for (final log in recLogs) {
      for (final rec in log.output) {
        final conf = (rec['confidenceScore'] as num?)?.toDouble();
        if (conf != null) {
          totalConf += conf;
          confCount++;
        }
      }
    }

    // Average reward rate delta across all optimization calls
    double totalDelta = 0;
    int deltaCount = 0;
    for (final log in optLogs) {
      for (final opt in log.output) {
        final current = (opt['currentRewardRate'] as num?)?.toDouble() ?? 0;
        final optimized =
            (opt['optimizedRewardRate'] as num?)?.toDouble() ?? 0;
        if (optimized > 0) {
          totalDelta += (optimized - current);
          deltaCount++;
        }
      }
    }

    final totalDurationMs =
        logs.fold<int>(0, (sum, l) => sum + l.durationMs);

    return {
      'totalCalls': logs.length,
      'mockFallbackRate':
          logs.isEmpty ? 0.0 : mockCount / logs.length,
      'avgDurationMs':
          logs.isEmpty ? 0 : (totalDurationMs / logs.length).round(),
      'providerCounts': providerCounts,
      'recommendationCallCount': recLogs.length,
      'optimizationCallCount': optLogs.length,
      'avgConfidenceScore':
          confCount == 0 ? 0.0 : totalConf / confCount,
      'avgRewardRateDelta':
          deltaCount == 0 ? 0.0 : totalDelta / deltaCount,
    };
  }

  Future<void> clearLogs() async {
    try {
      final box = await Hive.openBox(_boxName);
      await box.clear();
      debugPrint('🗑️ GeminiCallLogService: cleared all logs');
    } catch (e) {
      debugPrint('⚠️ GeminiCallLogService.clearLogs failed: $e');
    }
  }

  // ─── Internal ─────────────────────────────────────────────────────────────

  Future<void> _write(GeminiCallLog log) async {
    try {
      final box = await Hive.openBox(_boxName);

      // Evict oldest entries if over cap
      if (box.length >= maxEntries) {
        final keys = box.keys.toList();
        // Keys are time-based IDs; sort ascending and remove oldest
        keys.sort();
        final toRemove = keys.take(box.length - maxEntries + 1);
        await box.deleteAll(toRemove);
      }

      await box.put(log.id, log.toHive());
      debugPrint(
          '💾 GeminiCallLog saved: ${log.type.name} via ${log.provider} '
          '(${log.durationMs}ms, mockFallback=${log.usedMockFallback})');
    } catch (e) {
      debugPrint('⚠️ GeminiCallLogService._write failed: $e');
    }
  }

  String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch}_'
      '${Object().hashCode.toRadixString(16)}';
}
