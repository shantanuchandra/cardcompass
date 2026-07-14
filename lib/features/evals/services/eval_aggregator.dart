import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cardcompass/core/services/pruning_audit_service.dart';
import 'package:cardcompass/core/services/gemini_call_log_service.dart';
import 'package:cardcompass/features/evals/models/eval_metric.dart';
import 'package:cardcompass/features/evals/models/eval_fixture.dart';

/// Pulls live data from all AI subsystems and computes per-subsystem scores
/// and a weighted Overall AI Health Score (0–100).
class EvalAggregator {
  EvalAggregator({
    PruningAuditService? pruningService,
    GeminiCallLogService? callLogService,
    SupabaseClient? supabase,
  })  : _pruning = pruningService ?? PruningAuditService(),
        _callLog = callLogService ?? GeminiCallLogService(),
        _supabase = supabase ?? Supabase.instance.client;

  final PruningAuditService _pruning;
  final GeminiCallLogService _callLog;
  final SupabaseClient _supabase;

  // ── Weights (must sum to 1.0) ────────────────────────────────────────────
  static const Map<String, double> _weights = {
    'Benefit Extraction': 0.25,
    'Statement Pruning': 0.20,
    'Transaction Parsing': 0.20,
    'Reward Intelligence': 0.15,
    'Benefit Repair': 0.10,
    'Card Recommendations': 0.05,
    'Spending Optimizations': 0.05,
  };

  // ─────────────────────────────────────────────────────────────────────────
  // Public API
  // ─────────────────────────────────────────────────────────────────────────

  /// Fetches live data and returns all subsystem scores.
  Future<List<SubsystemScore>> computeAll() async {
    final results = await Future.wait([
      _benefitExtractionScore(),
      _pruningScore(),
      _transactionParsingScore(),
      _rewardIntelligenceScore(),
      _benefitRepairScore(),
      _recommendationsScore(),
      _optimizationsScore(),
    ]);
    return results;
  }

  /// Fetches live data and computes all subsystem scores from a fixture.
  Future<List<SubsystemScore>> computeFromFixture(EvalFixture fixture) async {
    return [
      _benefitExtractionScoreFromData(fixture.benefitStagingRecords),
      _pruningScoreFromData(fixture.pruningLogs),
      _transactionParsingScoreFromStats(fixture.transactionParsingStats),
      _rewardIntelligenceScoreFromData(fixture.rewardBalances),
      _benefitRepairScoreFromData(fixture.repairMetadata),
      _recommendationsScoreFromData(fixture.recommendationCalls),
      _optimizationsScoreFromData(fixture.optimizationCalls),
    ];
  }

  /// Weighted overall score 0–100.
  double computeHealthScore(List<SubsystemScore> scores) {
    double weighted = 0;
    double totalWeight = 0;
    for (final s in scores) {
      final w = _weights[s.name] ?? 0.05;
      weighted += s.score * w;
      totalWeight += w;
    }
    if (totalWeight == 0) return 0;
    return (weighted / totalWeight * 100).clamp(0, 100);
  }

  /// Export current live state as a portable [EvalFixture].
  Future<EvalFixture> exportFixture({String label = ''}) async {
    final pruningLogs = await _pruning.getLogs();
    final callLogs = await _callLog.getLogs();

    List<Map<String, dynamic>> stagingRecords = [];
    try {
      final raw = await _supabase
          .from('card_benefit_staging')
          .select(
              'id, card_id, status, calculated_confidence, validation_reasons, validation_warnings, source_url, validated_at, repair_metadata')
          .order('validated_at', ascending: false)
          .limit(500);
      stagingRecords = (raw as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {}

    List<Map<String, dynamic>> rewardBalances = [];
    try {
      final raw = await _supabase
          .from('reward_balances')
          .select('*')
          .limit(200);
      rewardBalances = (raw as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {}

    final recCalls = callLogs
        .where((l) => l.type == GeminiCallType.cardRecommendation)
        .map((l) => l.toHive())
        .toList();
    final optCalls = callLogs
        .where((l) => l.type == GeminiCallType.spendingOptimization)
        .map((l) => l.toHive())
        .toList();

    final repairRecords = stagingRecords.where((r) {
      final rm = r['repair_metadata'];
      return rm is Map && (rm['attempted'] == true);
    }).toList();

    return EvalFixture(
      version: 1,
      exportedAt: DateTime.now().toIso8601String(),
      label: label.isEmpty
          ? 'Live export ${DateTime.now().toLocal().toString().substring(0, 16)}'
          : label,
      pruningLogs: pruningLogs,
      benefitStagingRecords: stagingRecords,
      recommendationCalls: recCalls,
      optimizationCalls: optCalls,
      rewardBalances: rewardBalances,
      repairMetadata: repairRecords,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Benefit Extraction
  // ─────────────────────────────────────────────────────────────────────────

  Future<SubsystemScore> _benefitExtractionScore() async {
    try {
      final raw = await _supabase
          .from('card_benefit_staging')
          .select('status, calculated_confidence, validation_reasons, validation_warnings')
          .order('validated_at', ascending: false)
          .limit(500);
      final records = (raw as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      return _benefitExtractionScoreFromData(records);
    } catch (_) {
      return _noDataSubsystem('Benefit Extraction', '🧬');
    }
  }

  SubsystemScore _benefitExtractionScoreFromData(
      List<Map<String, dynamic>> records) {
    if (records.isEmpty) return _noDataSubsystem('Benefit Extraction', '🧬');

    final total = records.length;
    final accepted =
        records.where((r) => r['status'] == 'pending').length;
    final rejected =
        records.where((r) => r['status'] == 'rejected').length;

    final confidences = records
        .map((r) => (r['calculated_confidence'] as num?)?.toDouble() ?? 0.0)
        .toList();
    final avgConf =
        confidences.fold(0.0, (s, v) => s + v) / confidences.length;

    // Reason code frequency
    final reasonCounts = <String, int>{};
    for (final r in records) {
      final reasons = r['validation_reasons'];
      if (reasons is List) {
        for (final reason in reasons) {
          if (reason is Map) {
            final code = reason['code']?.toString() ?? 'unknown';
            reasonCounts[code] = (reasonCounts[code] ?? 0) + 1;
          }
        }
      }
    }

    final acceptanceRate = total > 0 ? accepted / total : 0.0;
    final groundingScore = avgConf;
    final score = ((acceptanceRate * 0.6) + (groundingScore * 0.4)).clamp(0.0, 1.0);

    return SubsystemScore(
      name: 'Benefit Extraction',
      icon: '🧬',
      score: score,
      weight: _weights['Benefit Extraction']!,
      metrics: [
        EvalMetric(
          name: 'Acceptance rate',
          value: acceptanceRate,
          displayValue: '${(acceptanceRate * 100).toStringAsFixed(1)} %',
          description: 'Extractions that passed grounding validation',
          sampleSize: total,
        ),
        EvalMetric(
          name: 'Avg grounding confidence',
          value: groundingScore,
          displayValue: '${(groundingScore * 100).toStringAsFixed(1)} %',
          description: 'Mean calculated_confidence across all staging records',
          sampleSize: total,
        ),
        EvalMetric(
          name: 'Rejection count',
          value: total > 0 ? 1 - (rejected / total) : 1.0,
          displayValue: '$rejected rejected',
          sampleSize: total,
        ),
        EvalMetric(
          name: 'Top rejection reason',
          value: 1.0,
          displayValue: reasonCounts.isEmpty
              ? 'None'
              : (reasonCounts.entries.toList()
                    ..sort((a, b) => b.value.compareTo(a.value)))
                  .first
                  .key,
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Statement Pruning
  // ─────────────────────────────────────────────────────────────────────────

  Future<SubsystemScore> _pruningScore() async {
    try {
      final logs = await _pruning.getLogs();
      return _pruningScoreFromData(logs);
    } catch (_) {
      return _noDataSubsystem('Statement Pruning', '✂️');
    }
  }

  SubsystemScore _pruningScoreFromData(List<Map<String, dynamic>> logs) {
    if (logs.isEmpty) return _noDataSubsystem('Statement Pruning', '✂️');

    final total = logs.length;
    final flagged = logs.where((l) => l['isFlagged'] == true).length;
    final clean = total - flagged;
    final leakFreeRate = clean / total;

    final reductions = logs
        .map((l) => (l['reductionRatio'] as num?)?.toDouble() ?? 0.0)
        .toList();
    final avgReduction =
        reductions.fold(0.0, (s, v) => s + v) / reductions.length;

    // Cut marker counts
    final markerCounts = <String, int>{};
    for (final log in logs) {
      final marker = log['cutMarker']?.toString() ?? 'None';
      markerCounts[marker] = (markerCounts[marker] ?? 0) + 1;
    }
    final topMarker = markerCounts.isEmpty
        ? 'None'
        : (markerCounts.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value)))
            .first
            .key;

    final score = (leakFreeRate * 0.7 +
            (avgReduction.clamp(0, 80) / 80 * 0.3))
        .clamp(0.0, 1.0);

    return SubsystemScore(
      name: 'Statement Pruning',
      icon: '✂️',
      score: score,
      weight: _weights['Statement Pruning']!,
      metrics: [
        EvalMetric(
          name: 'Leak-free rate',
          value: leakFreeRate,
          displayValue: '${(leakFreeRate * 100).toStringAsFixed(1)} %',
          description: 'Pruned statements with no detected transaction leaks',
          sampleSize: total,
        ),
        EvalMetric(
          name: 'Flagged runs',
          value: total > 0 ? 1 - (flagged / total) : 1.0,
          displayValue: '$flagged / $total flagged',
          sampleSize: total,
        ),
        EvalMetric(
          name: 'Avg text reduction',
          value: (avgReduction / 100).clamp(0.0, 1.0),
          displayValue: '${avgReduction.toStringAsFixed(1)} %',
          description: 'Average characters removed vs original',
          sampleSize: total,
        ),
        EvalMetric(
          name: 'Top cut marker',
          value: 1.0,
          displayValue: topMarker,
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Transaction Parsing
  // ─────────────────────────────────────────────────────────────────────────

  Future<SubsystemScore> _transactionParsingScore() async {
    try {
      final statementsRaw = await _supabase
          .from('statements')
          .select('id, bank_name, statement_date')
          .limit(500);
      final statements = (statementsRaw as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      int withTransactions = 0;
      int totalTxns = 0;
      for (final stmt in statements) {
        final sid = stmt['id'];
        if (sid == null) continue;
        final txnRaw = await _supabase
            .from('transactions')
            .select('id')
            .eq('statement_id', sid);
        final count = (txnRaw as List).length;
        if (count > 0) withTransactions++;
        totalTxns += count;
      }

      final stats = {
        'totalStatements': statements.length,
        'statementsWithTransactions': withTransactions,
        'totalTransactions': totalTxns,
        'avgTransactionsPerStatement':
            statements.isEmpty ? 0 : totalTxns / statements.length,
      };
      return _transactionParsingScoreFromStats(stats);
    } catch (_) {
      return _noDataSubsystem('Transaction Parsing', '🔬');
    }
  }

  SubsystemScore _transactionParsingScoreFromStats(
      Map<String, dynamic> stats) {
    if (stats.isEmpty) return _noDataSubsystem('Transaction Parsing', '🔬');

    final total = (stats['totalStatements'] as num?)?.toInt() ?? 0;
    final withTxns =
        (stats['statementsWithTransactions'] as num?)?.toInt() ?? 0;
    final totalTxns = (stats['totalTransactions'] as num?)?.toInt() ?? 0;
    final avgTxns =
        (stats['avgTransactionsPerStatement'] as num?)?.toDouble() ?? 0.0;

    final successRate = total > 0 ? withTxns / total : 0.0;
    // Avg > 5 txns/statement is "good"
    final volumeScore = (avgTxns / 20).clamp(0.0, 1.0);
    final score = (successRate * 0.75 + volumeScore * 0.25).clamp(0.0, 1.0);

    return SubsystemScore(
      name: 'Transaction Parsing',
      icon: '🔬',
      score: score,
      weight: _weights['Transaction Parsing']!,
      metrics: [
        EvalMetric(
          name: 'Parse success rate',
          value: successRate,
          displayValue: '${(successRate * 100).toStringAsFixed(1)} %',
          description: 'Statements that yielded at least one transaction',
          sampleSize: total,
        ),
        EvalMetric(
          name: 'Total transactions',
          value: 1.0,
          displayValue: '$totalTxns',
          sampleSize: total,
        ),
        EvalMetric(
          name: 'Avg txns / statement',
          value: volumeScore,
          displayValue: avgTxns.toStringAsFixed(1),
          sampleSize: total,
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Reward Intelligence
  // ─────────────────────────────────────────────────────────────────────────

  Future<SubsystemScore> _rewardIntelligenceScore() async {
    try {
      final raw =
          await _supabase.from('reward_balances').select('*').limit(200);
      final balances = (raw as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      return _rewardIntelligenceScoreFromData(balances);
    } catch (_) {
      return _noDataSubsystem('Reward Intelligence', '💎');
    }
  }

  SubsystemScore _rewardIntelligenceScoreFromData(
      List<Map<String, dynamic>> balances) {
    if (balances.isEmpty) return _noDataSubsystem('Reward Intelligence', '💎');

    final total = balances.length;
    final withValue = balances.where((b) {
      final v = (b['inr_value'] as num?)?.toDouble() ?? 0;
      return v > 0;
    }).length;
    final coverageRate = withValue / total;

    final inrValues = balances
        .map((b) => (b['inr_value'] as num?)?.toDouble() ?? 0.0)
        .toList();
    final totalInr = inrValues.fold(0.0, (s, v) => s + v);
    final highValue =
        balances.where((b) => ((b['inr_value'] as num?)?.toDouble() ?? 0) >= 500).length;

    final score = coverageRate;

    return SubsystemScore(
      name: 'Reward Intelligence',
      icon: '💎',
      score: score,
      weight: _weights['Reward Intelligence']!,
      metrics: [
        EvalMetric(
          name: 'Conversion coverage',
          value: coverageRate,
          displayValue: '${(coverageRate * 100).toStringAsFixed(1)} %',
          description: 'Cards with a known point-to-INR conversion rate',
          sampleSize: total,
        ),
        EvalMetric(
          name: 'Total unredeemed value',
          value: 1.0,
          displayValue: '₹${totalInr.toStringAsFixed(0)}',
          sampleSize: total,
        ),
        EvalMetric(
          name: 'High-value balances (≥ ₹500)',
          value: total > 0 ? highValue / total : 0.0,
          displayValue: '$highValue cards',
          sampleSize: total,
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Benefit Repair
  // ─────────────────────────────────────────────────────────────────────────

  Future<SubsystemScore> _benefitRepairScore() async {
    try {
      final raw = await _supabase
          .from('card_benefit_staging')
          .select('repair_metadata')
          .not('repair_metadata', 'is', null)
          .limit(200);
      final records = (raw as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      return _benefitRepairScoreFromData(records);
    } catch (_) {
      return _noDataSubsystem('Benefit Repair', '🔧');
    }
  }

  SubsystemScore _benefitRepairScoreFromData(
      List<Map<String, dynamic>> records) {
    if (records.isEmpty) return _noDataSubsystem('Benefit Repair', '🔧');

    int totalTargets = 0;
    int totalAccepted = 0;

    for (final r in records) {
      final rm = r['repair_metadata'];
      if (rm is! Map) continue;
      final targets = (rm['targets'] as List?)?.length ?? 0;
      final accepted = (rm['accepted_count'] as num?)?.toInt() ?? 0;
      totalTargets += targets;
      totalAccepted += accepted;
    }

    final hitRate =
        totalTargets > 0 ? totalAccepted / totalTargets : 0.0;
    final attemptedRate = records.length;

    return SubsystemScore(
      name: 'Benefit Repair',
      icon: '🔧',
      score: hitRate.clamp(0.0, 1.0),
      weight: _weights['Benefit Repair']!,
      metrics: [
        EvalMetric(
          name: 'Repair target hit rate',
          value: hitRate,
          displayValue: '${(hitRate * 100).toStringAsFixed(1)} %',
          description: 'Fraction of repair targets that produced accepted items',
          sampleSize: totalTargets,
        ),
        EvalMetric(
          name: 'Repair attempts',
          value: 1.0,
          displayValue: '$attemptedRate records',
        ),
        EvalMetric(
          name: 'Accepted repairs',
          value: 1.0,
          displayValue: '$totalAccepted / $totalTargets targets',
          sampleSize: totalTargets,
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Card Recommendations
  // ─────────────────────────────────────────────────────────────────────────

  Future<SubsystemScore> _recommendationsScore() async {
    try {
      final logs = await _callLog.getLogsForType(GeminiCallType.cardRecommendation);
      return _recommendationsScoreFromData(
          logs.map((l) => l.toHive()).toList());
    } catch (_) {
      return _noDataSubsystem('Card Recommendations', '🃏');
    }
  }

  SubsystemScore _recommendationsScoreFromData(
      List<Map<String, dynamic>> calls) {
    if (calls.isEmpty) return _noDataSubsystem('Card Recommendations', '🃏');

    double totalConf = 0;
    int confCount = 0;
    int mockCount = 0;

    for (final call in calls) {
      if (call['usedMockFallback'] == true) mockCount++;
      final output = _decodeList(call['output']);
      for (final rec in output) {
        final conf = (rec['confidenceScore'] as num?)?.toDouble();
        if (conf != null) {
          totalConf += conf;
          confCount++;
        }
      }
    }

    final avgConf = confCount > 0 ? totalConf / confCount : 0.0;
    final realRate = calls.isNotEmpty ? 1 - (mockCount / calls.length) : 0.0;
    final score = (avgConf * 0.6 + realRate * 0.4).clamp(0.0, 1.0);

    return SubsystemScore(
      name: 'Card Recommendations',
      icon: '🃏',
      score: score,
      weight: _weights['Card Recommendations']!,
      metrics: [
        EvalMetric(
          name: 'Avg confidence score',
          value: avgConf,
          displayValue: avgConf.toStringAsFixed(2),
          description: 'Mean confidence across all recommendations',
          sampleSize: confCount,
        ),
        EvalMetric(
          name: 'Real AI calls',
          value: realRate,
          displayValue: '${(realRate * 100).toStringAsFixed(0)} %',
          description: 'Calls that returned AI output (not mock)',
          sampleSize: calls.length,
        ),
        EvalMetric(
          name: 'Total calls logged',
          value: 1.0,
          displayValue: '${calls.length}',
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Spending Optimizations
  // ─────────────────────────────────────────────────────────────────────────

  Future<SubsystemScore> _optimizationsScore() async {
    try {
      final logs = await _callLog.getLogsForType(GeminiCallType.spendingOptimization);
      return _optimizationsScoreFromData(
          logs.map((l) => l.toHive()).toList());
    } catch (_) {
      return _noDataSubsystem('Spending Optimizations', '📊');
    }
  }

  SubsystemScore _optimizationsScoreFromData(
      List<Map<String, dynamic>> calls) {
    if (calls.isEmpty) return _noDataSubsystem('Spending Optimizations', '📊');

    int mockCount = 0;
    double totalDelta = 0;
    int deltaCount = 0;

    for (final call in calls) {
      if (call['usedMockFallback'] == true) mockCount++;
      final output = _decodeList(call['output']);
      for (final opt in output) {
        final cur = (opt['currentRewardRate'] as num?)?.toDouble() ?? 0;
        final optimised = (opt['optimizedRewardRate'] as num?)?.toDouble() ?? 0;
        if (optimised > 0) {
          totalDelta += (optimised - cur);
          deltaCount++;
        }
      }
    }

    final realRate =
        calls.isNotEmpty ? 1 - (mockCount / calls.length) : 0.0;
    final avgDelta = deltaCount > 0 ? totalDelta / deltaCount : 0.0;
    // Delta of 4x = perfect score
    final deltaScore = (avgDelta / 4.0).clamp(0.0, 1.0);
    final score = (realRate * 0.6 + deltaScore * 0.4).clamp(0.0, 1.0);

    return SubsystemScore(
      name: 'Spending Optimizations',
      icon: '📊',
      score: score,
      weight: _weights['Spending Optimizations']!,
      metrics: [
        EvalMetric(
          name: 'Real AI output rate',
          value: realRate,
          displayValue: '${(realRate * 100).toStringAsFixed(0)} %',
          description: 'Calls that returned live AI results (not mock fallback)',
          sampleSize: calls.length,
        ),
        EvalMetric(
          name: 'Mock fallback calls',
          value: calls.isNotEmpty ? 1 - (mockCount / calls.length) : 1.0,
          displayValue: '$mockCount / ${calls.length}',
          sampleSize: calls.length,
        ),
        EvalMetric(
          name: 'Avg reward rate delta',
          value: deltaScore,
          displayValue: '+${avgDelta.toStringAsFixed(1)} %',
          description: 'Avg improvement in reward rate (optimised − current)',
          sampleSize: deltaCount,
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────────

  static SubsystemScore _noDataSubsystem(String name, String icon) {
    return SubsystemScore(
      name: name,
      icon: icon,
      score: 0.0,
      metrics: [
        EvalMetric(
          name: 'No data',
          value: 0.0,
          displayValue: 'No data',
          description: 'Run the pipeline to collect eval data',
        ),
      ],
    );
  }

  static List<Map<String, dynamic>> _decodeList(dynamic v) {
    if (v is String) {
      try {
        final decoded = jsonDecode(v);
        if (decoded is List) {
          return decoded
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      } catch (_) {}
    }
    if (v is List) {
      return v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    return [];
  }
}
