import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../data/admin_operator_repository.dart';
import 'eval_models.dart';

typedef EvalRequestIdFactory = String Function();

final class EvalRepository {
  EvalRepository(this._operator, {EvalRequestIdFactory? requestIds})
    : _requestIds = requestIds ?? const Uuid().v4;
  final AdminOperatorRepository _operator;
  final EvalRequestIdFactory _requestIds;
  Future<EvalConfigCatalog> configs() => _guard(() async {
    final j = await _invoke('eval-config-list');
    exactEvalKeys(j, const {'dataset_version', 'baseline', 'judge', 'configs'});
    return EvalConfigCatalog(
      datasetVersion: evalInt(j['dataset_version']),
      baseline: EvalConfig.fromJson(evalMap(j['baseline'])),
      judge: EvalConfig.fromJson(evalMap(j['judge'])),
      candidates: evalList(
        j['configs'],
      ).map((v) => EvalConfig.fromJson(evalMap(v))).toList(),
    );
  });
  Future<EvalRunsPage> runs({
    int page = 1,
    int limit = 20,
    String? status,
    EvalFeature? feature,
  }) => _guard(() async {
    if (page < 1 || page > 10000 || limit < 1 || limit > 50) {
      throw const FormatException();
    }
    final j = await _invoke('eval-run-list', {
      'page': page,
      'limit': limit,
      'status': ?status,
      'feature': ?switch (feature) {
        EvalFeature.statementProcessing => 'statement_processing',
        EvalFeature.cardData => 'card_data',
        EvalFeature.recommendation => 'recommendation',
        _ => null,
      },
    });
    exactEvalKeys(j, const {'items', 'page', 'limit', 'total'});
    if (j['page'] != page || j['limit'] != limit) throw const FormatException();
    return EvalRunsPage(
      items: evalList(
        j['items'],
      ).map((v) => EvalRun.fromJson(evalMap(v))).toList(),
      page: page,
      limit: limit,
      total: evalInt(j['total']),
    );
  });
  Future<EvalRunDetail> detail(
    String runId, {
    int resultPage = 1,
    int resultLimit = 25,
  }) => _guard(() async {
    evalUuid(runId);
    if (resultPage < 1 ||
        resultPage > 10000 ||
        resultLimit < 1 ||
        resultLimit > 50) {
      throw const FormatException();
    }
    final j = await _invoke('eval-run-detail', {
      'run_id': runId,
      'request_id': _id(),
      'result_page': resultPage,
      'result_limit': resultLimit,
    });
    exactEvalKeys(j, const {'run', 'metrics', 'decision', 'results'});
    final m = evalMap(j['metrics']);
    exactEvalKeys(m, const {
      'baseline_pass_rate',
      'candidate_pass_rate',
      'p95_candidate_latency_ms',
      'manual_review_count',
    });
    final d = evalMap(j['decision']);
    exactEvalKeys(d, const {'status', 'blockers'});
    final resultPageJson = evalMap(j['results']);
    exactEvalKeys(resultPageJson, const {'items', 'page', 'limit', 'total'});
    if (resultPageJson['page'] != resultPage ||
        resultPageJson['limit'] != resultLimit) {
      throw const FormatException();
    }
    final status = switch (d['status']) {
      'candidate_supported' => EvalDecision.candidateSupported,
      'review_required' => EvalDecision.reviewRequired,
      _ => throw const FormatException(),
    };
    return EvalRunDetail(
      run: EvalRun.fromJson(evalMap(j['run'])),
      metrics: EvalMetrics(
        baselinePassRate: evalDouble(m['baseline_pass_rate']),
        candidatePassRate: evalDouble(m['candidate_pass_rate']),
        p95CandidateLatencyMs: evalInt(m['p95_candidate_latency_ms']),
        manualReviewCount: evalInt(m['manual_review_count']),
      ),
      decision: status,
      blockers: evalList(d['blockers']).map(evalString).toList(),
      results: evalList(
        resultPageJson['items'],
      ).map((v) => _result(evalMap(v))).toList(),
      resultPage: resultPage,
      resultLimit: resultLimit,
      resultTotal: evalInt(resultPageJson['total']),
    );
  });
  Future<EvalRunReceipt> start(EvalStartRequest r) => _guard(() async {
    if (r.datasetVersion < 1 ||
        r.maximumCaseCount < 1 ||
        r.maximumCaseCount > 100 ||
        r.latencyCeilingMs < 1 ||
        r.latencyCeilingMs > 600000 ||
        r.candidate.role != EvalConfigRole.candidate) {
      throw const FormatException();
    }
    final judgeCost = r.candidate.feature == EvalFeature.recommendation
        ? .01
        : 0.0;
    final minimum =
        (r.candidate.estimatedMaximumCostUsd + judgeCost) * r.maximumCaseCount;
    if (r.costCeilingUsd + 1e-9 < minimum || r.costCeilingUsd > 100) {
      throw const FormatException();
    }
    return _receipt(
      await _invoke('eval-run-action', {
        'operation': 'start',
        'request_id': _id(),
        'dataset_version': r.datasetVersion,
        'baseline_config_key': 'captured-production-v1',
        'candidate_config_key': r.candidate.key,
        'judge_config_key': 'gemini-3.6-flash-blind-judge-v1',
        'maximum_case_count': r.maximumCaseCount,
        'cost_ceiling_usd': r.costCeilingUsd,
        'latency_ceiling_ms': r.latencyCeilingMs,
      }),
      start: true,
      max: r.maximumCaseCount,
    );
  });
  Future<EvalRunReceipt> cancel(String id, String observed) =>
      _mutate('cancel', id, observed);
  Future<EvalRunReceipt> resumeFailed(String id, String observed) =>
      _mutate('resume_failed', id, observed);
  Future<EvalRunReceipt> _mutate(
    String operation,
    String id,
    String observed,
  ) => _guard(() async {
    evalUuid(id);
    evalDate(observed);
    return _receipt(
      await _invoke('eval-run-action', {
        'operation': operation,
        'run_id': id,
        'request_id': _id(),
        'observed_updated_at': observed,
      }),
      expectedId: id,
      expectedStatus: operation == 'cancel' ? 'cancelled' : 'queued',
    );
  });
  String _id() {
    final id = _requestIds();
    evalUuid(id);
    return id;
  }

  Future<Map<String, dynamic>> _invoke(
    String action, [
    Map<String, dynamic> body = const {},
  ]) async {
    final request = {'action': action, ...body};
    if (utf8.encode(jsonEncode(request)).length > 32768) {
      throw const FormatException('Oversized eval request');
    }
    final response = await _operator.invoke(action, body);
    if (utf8.encode(jsonEncode(response)).length > 32768) {
      throw const FormatException('Oversized eval response');
    }
    return response;
  }

  EvalRunReceipt _receipt(
    Map<String, dynamic> json, {
    bool start = false,
    int? max,
    String? expectedId,
    String? expectedStatus,
  }) {
    exactEvalKeys(json, const {'result'});
    final r = evalMap(json['result']);
    exactEvalKeys(
      r,
      start
          ? const {'run_id', 'status', 'case_count'}
          : const {'run_id', 'status'},
    );
    final id = evalUuid(r['run_id']);
    final status = evalString(r['status']);
    if (expectedId != null && id != expectedId ||
        expectedStatus != null && status != expectedStatus) {
      throw const FormatException();
    }
    final count = start ? evalInt(r['case_count']) : null;
    if (count != null && (count < 1 || count > (max ?? 100))) {
      throw const FormatException();
    }
    return EvalRunReceipt(runId: id, status: status, caseCount: count);
  }

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      final result = await action();
      return result;
    } on FormatException {
      throw const AdminRequestFailed('request_failed');
    } on TypeError {
      throw const AdminRequestFailed('request_failed');
    }
  }
}

EvalResultSummary _result(Map<String, dynamic> j) {
  exactEvalKeys(j, const {
    'case_id',
    'case_revision',
    'feature',
    'execution_status',
    'baseline_passed',
    'candidate_passed',
    'regression',
    'severe_regression',
    'requires_review',
    'safe_failure_category',
    'baseline_latency_ms',
    'candidate_latency_ms',
    'baseline_input_tokens',
    'baseline_output_tokens',
    'candidate_input_tokens',
    'candidate_output_tokens',
    'estimated_cost_usd',
    'attempt_count',
    'updated_at',
  });
  return EvalResultSummary(
    caseId: evalUuid(j['case_id']),
    caseRevision: evalInt(j['case_revision']),
    feature: switch (j['feature']) {
      'statement_processing' => EvalFeature.statementProcessing,
      'card_data' => EvalFeature.cardData,
      'recommendation' => EvalFeature.recommendation,
      _ => throw const FormatException(),
    },
    executionStatus: evalString(j['execution_status']),
    baselinePassed: evalBool(j['baseline_passed']),
    candidatePassed: evalBool(j['candidate_passed']),
    regression: evalBool(j['regression']),
    severeRegression: evalBool(j['severe_regression']),
    requiresReview: evalBool(j['requires_review']),
    safeFailureCategory: evalNullableString(j['safe_failure_category']),
    candidateLatencyMs: evalInt(j['candidate_latency_ms']),
  );
}
