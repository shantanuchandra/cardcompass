enum EvalConfigRole { baseline, candidate, judge }

enum EvalFeature { all, statementProcessing, cardData, recommendation }

enum EvalDecision { candidateSupported, reviewRequired }

EvalFeature _feature(Object? value) => switch (value) {
  'all' => EvalFeature.all,
  'statement_processing' => EvalFeature.statementProcessing,
  'card_data' => EvalFeature.cardData,
  'recommendation' => EvalFeature.recommendation,
  _ => throw const FormatException('Invalid eval feature'),
};
EvalConfigRole _role(Object? value) => switch (value) {
  'baseline' => EvalConfigRole.baseline,
  'candidate' => EvalConfigRole.candidate,
  'judge' => EvalConfigRole.judge,
  _ => throw const FormatException('Invalid eval role'),
};

final class EvalConfig {
  const EvalConfig({
    required this.key,
    required this.role,
    required this.feature,
    required this.provider,
    required this.model,
    required this.promptVersion,
    required this.taskScope,
    required this.estimatedMaximumCostUsd,
    required this.scopeNote,
  });
  final String key;
  final EvalConfigRole role;
  final EvalFeature feature;
  final String provider;
  final String model;
  final String promptVersion;
  final String taskScope;
  final double estimatedMaximumCostUsd;
  final String? scopeNote;
  bool get doesNotEvaluateRanking =>
      taskScope == 'fixed_selection_explanation_and_arithmetic' &&
      scopeNote == 'Does not evaluate ranking.';
  factory EvalConfig.fromJson(Map<String, dynamic> json) {
    exactEvalKeys(json, const {
      'key',
      'role',
      'feature',
      'provider',
      'model',
      'prompt_version',
      'task_scope',
      'estimated_maximum_cost_usd',
      'scope_note',
    });
    return EvalConfig(
      key: evalString(json['key']),
      role: _role(json['role']),
      feature: _feature(json['feature']),
      provider: evalString(json['provider']),
      model: evalString(json['model']),
      promptVersion: evalString(json['prompt_version']),
      taskScope: evalString(json['task_scope']),
      estimatedMaximumCostUsd: evalDouble(json['estimated_maximum_cost_usd']),
      scopeNote: evalNullableString(json['scope_note']),
    );
  }
}

final class EvalConfigCatalog {
  EvalConfigCatalog({
    required this.datasetVersion,
    required this.baseline,
    required this.judge,
    required List<EvalConfig> candidates,
  }) : candidates = List.unmodifiable(candidates);
  final int datasetVersion;
  final EvalConfig baseline;
  final EvalConfig judge;
  final List<EvalConfig> candidates;
}

final class EvalRun {
  EvalRun({
    required this.id,
    required this.datasetVersion,
    required this.feature,
    required this.taskScope,
    required this.scopeNote,
    required this.baselineConfigKey,
    required this.candidateConfigKey,
    required this.judgeConfigKey,
    required this.status,
    required this.maximumCaseCount,
    required this.costCeilingUsd,
    required this.latencyCeilingMs,
    required this.aggregateMetrics,
    required this.tokenUsage,
    required this.estimatedCostUsd,
    required this.safeFailureCategory,
    required this.createdAt,
    required this.startedAt,
    required this.completedAt,
    required this.updatedAt,
  });
  final String id;
  final int datasetVersion;
  final EvalFeature feature;
  final String taskScope;
  final String? scopeNote;
  final String baselineConfigKey;
  final String candidateConfigKey;
  final String judgeConfigKey;
  final String status;
  final int maximumCaseCount;
  final double costCeilingUsd;
  final int latencyCeilingMs;
  final Map<String, dynamic> aggregateMetrics;
  final Map<String, dynamic> tokenUsage;
  final double estimatedCostUsd;
  final String? safeFailureCategory;
  final DateTime createdAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final DateTime updatedAt;
  factory EvalRun.fromJson(Map<String, dynamic> json) {
    exactEvalKeys(json, const {
      'id',
      'dataset_version',
      'feature',
      'task_scope',
      'scope_note',
      'baseline_config_key',
      'candidate_config_key',
      'judge_config_key',
      'status',
      'maximum_case_count',
      'cost_ceiling_usd',
      'latency_ceiling_ms',
      'aggregate_metrics',
      'token_usage',
      'estimated_cost_usd',
      'safe_failure_category',
      'created_at',
      'started_at',
      'completed_at',
      'updated_at',
    });
    return EvalRun(
      id: evalUuid(json['id']),
      datasetVersion: evalInt(json['dataset_version']),
      feature: _feature(json['feature']),
      taskScope: evalString(json['task_scope']),
      scopeNote: evalNullableString(json['scope_note']),
      baselineConfigKey: evalString(json['baseline_config_key']),
      candidateConfigKey: evalString(json['candidate_config_key']),
      judgeConfigKey: evalString(json['judge_config_key']),
      status: evalString(json['status']),
      maximumCaseCount: evalInt(json['maximum_case_count']),
      costCeilingUsd: evalDouble(json['cost_ceiling_usd']),
      latencyCeilingMs: evalInt(json['latency_ceiling_ms']),
      aggregateMetrics: Map.unmodifiable(evalMap(json['aggregate_metrics'])),
      tokenUsage: Map.unmodifiable(evalMap(json['token_usage'])),
      estimatedCostUsd: evalDouble(json['estimated_cost_usd']),
      safeFailureCategory: evalNullableString(json['safe_failure_category']),
      createdAt: evalDate(json['created_at']),
      startedAt: evalNullableDate(json['started_at']),
      completedAt: evalNullableDate(json['completed_at']),
      updatedAt: evalDate(json['updated_at']),
    );
  }
}

final class EvalRunsPage {
  EvalRunsPage({
    required List<EvalRun> items,
    required this.page,
    required this.limit,
    required this.total,
  }) : items = List.unmodifiable(items);
  final List<EvalRun> items;
  final int page;
  final int limit;
  final int total;
  bool get hasMore => page * limit < total;
}

final class EvalMetrics {
  const EvalMetrics({
    required this.baselinePassRate,
    required this.candidatePassRate,
    required this.p95CandidateLatencyMs,
    required this.manualReviewCount,
  });
  final double baselinePassRate;
  final double candidatePassRate;
  final int p95CandidateLatencyMs;
  final int manualReviewCount;
}

final class EvalResultSummary {
  const EvalResultSummary({
    required this.caseId,
    required this.caseRevision,
    required this.feature,
    required this.executionStatus,
    required this.baselinePassed,
    required this.candidatePassed,
    required this.regression,
    required this.severeRegression,
    required this.requiresReview,
    required this.safeFailureCategory,
    required this.candidateLatencyMs,
  });
  final String caseId;
  final int caseRevision;
  final EvalFeature feature;
  final String executionStatus;
  final bool baselinePassed;
  final bool candidatePassed;
  final bool regression;
  final bool severeRegression;
  final bool requiresReview;
  final String? safeFailureCategory;
  final int candidateLatencyMs;
}

final class EvalRunDetail {
  EvalRunDetail({
    required this.run,
    required this.metrics,
    required this.decision,
    required List<String> blockers,
    required List<EvalResultSummary> results,
    required this.resultPage,
    required this.resultLimit,
    required this.resultTotal,
  }) : blockers = List.unmodifiable(blockers),
       results = List.unmodifiable(results);
  final EvalRun run;
  final EvalMetrics metrics;
  final EvalDecision decision;
  final List<String> blockers;
  final List<EvalResultSummary> results;
  final int resultPage;
  final int resultLimit;
  final int resultTotal;
}

final class EvalStartRequest {
  const EvalStartRequest({
    required this.datasetVersion,
    required this.candidate,
    required this.maximumCaseCount,
    required this.costCeilingUsd,
    required this.latencyCeilingMs,
  });
  final int datasetVersion;
  final EvalConfig candidate;
  final int maximumCaseCount;
  final double costCeilingUsd;
  final int latencyCeilingMs;
}

final class EvalRunReceipt {
  const EvalRunReceipt({
    required this.runId,
    required this.status,
    this.caseCount,
  });
  final String runId;
  final String status;
  final int? caseCount;
}

final _evalUuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  caseSensitive: false,
);
void exactEvalKeys(Map<String, dynamic> json, Set<String> keys) {
  if (json.length != keys.length || !json.keys.toSet().containsAll(keys)) {
    throw const FormatException('Invalid eval DTO');
  }
}

String evalString(Object? v) {
  if (v is! String || v.isEmpty || v.length > 200) {
    throw const FormatException('Invalid string');
  }
  return v;
}

String evalUuid(Object? v) {
  final s = evalString(v);
  if (!_evalUuid.hasMatch(s)) throw const FormatException('Invalid UUID');
  return s;
}

String? evalNullableString(Object? v) => v == null ? null : evalString(v);
int evalInt(Object? v) {
  if (v is! int || v < 0) throw const FormatException('Invalid integer');
  return v;
}

double evalDouble(Object? v) {
  if (v is! num || !v.isFinite || v < 0) {
    throw const FormatException('Invalid number');
  }
  return v.toDouble();
}

bool evalBool(Object? v) {
  if (v is! bool) throw const FormatException('Invalid boolean');
  return v;
}

Map<String, dynamic> evalMap(Object? v) {
  if (v is! Map) throw const FormatException('Invalid object');
  return Map<String, dynamic>.from(v);
}

List<dynamic> evalList(Object? v) {
  if (v is! List) throw const FormatException('Invalid list');
  return v;
}

DateTime evalDate(Object? v) {
  final s = evalString(v);
  final d = DateTime.tryParse(s);
  if (d == null) throw const FormatException('Invalid date');
  return d;
}

DateTime? evalNullableDate(Object? v) => v == null ? null : evalDate(v);
