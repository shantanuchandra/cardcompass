import 'dart:convert';

/// Schema version — bump when the fixture format changes.
const _kFixtureVersion = 1;

/// A portable snapshot of eval data from all 7 AI subsystems.
/// Can be exported from / imported into the AI Evals Dashboard.
class EvalFixture {
  const EvalFixture({
    required this.version,
    required this.exportedAt,
    required this.label,
    this.pruningLogs = const [],
    this.benefitStagingRecords = const [],
    this.transactionParsingStats = const {},
    this.recommendationCalls = const [],
    this.optimizationCalls = const [],
    this.rewardBalances = const [],
    this.repairMetadata = const [],
  });

  /// Schema version for forward-compat.
  final int version;

  /// ISO 8601 timestamp when this fixture was exported.
  final String exportedAt;

  /// Human label for this golden dataset, e.g. "Prod snapshot 2026-07-14".
  final String label;

  // ── Per-subsystem data ───────────────────────────────────────────────────

  /// Tab 2 — pruning audit logs (same shape as PruningAuditService.getLogs()).
  final List<Map<String, dynamic>> pruningLogs;

  /// Tab 1 — benefit staging records from card_benefit_staging table.
  final List<Map<String, dynamic>> benefitStagingRecords;

  /// Tab 3 — aggregated transaction parsing statistics.
  final Map<String, dynamic> transactionParsingStats;

  /// Tab 4 — raw GeminiCallLog entries for recommendation calls.
  final List<Map<String, dynamic>> recommendationCalls;

  /// Tab 5 — raw GeminiCallLog entries for optimisation calls.
  final List<Map<String, dynamic>> optimizationCalls;

  /// Tab 6 — reward balance rows.
  final List<Map<String, dynamic>> rewardBalances;

  /// Tab 7 — benefit staging records that contain repair_metadata.
  final List<Map<String, dynamic>> repairMetadata;

  // ── Serialisation ────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
        'version': version,
        'exportedAt': exportedAt,
        'label': label,
        'pruningLogs': pruningLogs,
        'benefitStagingRecords': benefitStagingRecords,
        'transactionParsingStats': transactionParsingStats,
        'recommendationCalls': recommendationCalls,
        'optimizationCalls': optimizationCalls,
        'rewardBalances': rewardBalances,
        'repairMetadata': repairMetadata,
      };

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());

  factory EvalFixture.fromJson(Map<String, dynamic> json) {
    final version = (json['version'] as num?)?.toInt() ?? 0;
    if (version < 1) {
      throw FormatException(
        'EvalFixture: unsupported schema version $version '
        '(expected >= $_kFixtureVersion)',
      );
    }

    List<Map<String, dynamic>> _list(dynamic v) {
      if (v is List) {
        return v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      }
      return [];
    }

    return EvalFixture(
      version: version,
      exportedAt: json['exportedAt']?.toString() ?? '',
      label: json['label']?.toString() ?? 'Imported fixture',
      pruningLogs: _list(json['pruningLogs']),
      benefitStagingRecords: _list(json['benefitStagingRecords']),
      transactionParsingStats: json['transactionParsingStats'] is Map
          ? Map<String, dynamic>.from(json['transactionParsingStats'] as Map)
          : {},
      recommendationCalls: _list(json['recommendationCalls']),
      optimizationCalls: _list(json['optimizationCalls']),
      rewardBalances: _list(json['rewardBalances']),
      repairMetadata: _list(json['repairMetadata']),
    );
  }

  factory EvalFixture.fromJsonString(String raw) =>
      EvalFixture.fromJson(jsonDecode(raw) as Map<String, dynamic>);

  /// Creates an empty fixture with the current timestamp.
  factory EvalFixture.empty({String label = 'Empty fixture'}) => EvalFixture(
        version: _kFixtureVersion,
        exportedAt: DateTime.now().toIso8601String(),
        label: label,
      );
}
