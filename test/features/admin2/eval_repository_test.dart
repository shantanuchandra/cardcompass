import 'dart:convert';
import 'package:cardcompass/features/admin2/data/admin_operator_api.dart';
import 'package:cardcompass/features/admin2/data/admin_operator_repository.dart';
import 'package:cardcompass/features/admin2/system/eval_models.dart';
import 'package:cardcompass/features/admin2/system/eval_repository.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Api implements AdminOperatorApi {
  _Api(this.responses);
  final List<AdminOperatorResponse> responses;
  final requests = <Map<String, dynamic>>[];
  @override
  Future<AdminOperatorResponse> invoke(Map<String, dynamic> body) async {
    requests.add(jsonDecode(jsonEncode(body)) as Map<String, dynamic>);
    return responses.removeAt(0);
  }
}

const runId = '00000000-0000-4000-8000-000000000010';
const requestId = '00000000-0000-4000-8000-000000000020';
const updated = '2026-08-19T10:02:00Z';
Map<String, dynamic> run() => {
  'id': runId,
  'dataset_version': 12,
  'feature': 'recommendation',
  'task_scope': 'fixed_selection_explanation_and_arithmetic',
  'scope_note': 'Does not evaluate ranking.',
  'baseline_config_key': 'captured-production-v1',
  'candidate_config_key': 'gemini-3.6-flash-recommendation-v1',
  'judge_config_key': 'gemini-3.6-flash-blind-judge-v1',
  'status': 'completed',
  'maximum_case_count': 10,
  'cost_ceiling_usd': 0.4,
  'latency_ceiling_ms': 5000,
  'aggregate_metrics': {'case_count': 2, 'severe_regressions': 0},
  'token_usage': {'candidate_input': 10},
  'estimated_cost_usd': 0.02,
  'safe_failure_category': null,
  'created_at': updated,
  'started_at': updated,
  'completed_at': updated,
  'updated_at': updated,
};

void main() {
  test(
    'decodes exact configs and labels fixed selection as not ranking',
    () async {
      final api = _Api([
        AdminOperatorResponse(200, {
          'dataset_version': 12,
          'baseline': {
            'key': 'captured-production-v1',
            'role': 'baseline',
            'feature': 'all',
            'provider': 'captured',
            'model': 'captured-production',
            'prompt_version': 'captured-production-v1',
            'task_scope': 'captured_production_output',
            'estimated_maximum_cost_usd': 0,
            'scope_note': null,
          },
          'judge': {
            'key': 'gemini-3.6-flash-blind-judge-v1',
            'role': 'judge',
            'feature': 'recommendation',
            'provider': 'gemini',
            'model': 'gemini-3.6-flash',
            'prompt_version': 'blind-judge-v1',
            'task_scope': 'blind_output_comparison',
            'estimated_maximum_cost_usd': 0.01,
            'scope_note': null,
          },
          'configs': [
            {
              'key': 'gemini-3.6-flash-recommendation-v1',
              'role': 'candidate',
              'feature': 'recommendation',
              'provider': 'gemini',
              'model': 'gemini-3.6-flash',
              'prompt_version': 'recommendation-v1',
              'task_scope': 'fixed_selection_explanation_and_arithmetic',
              'estimated_maximum_cost_usd': 0.03,
              'scope_note': 'Does not evaluate ranking.',
            },
          ],
        }),
      ]);
      final configs = await EvalRepository(
        AdminOperatorRepository(api),
      ).configs();
      expect(configs.candidates.single.doesNotEvaluateRanking, isTrue);
      expect(api.requests.single, {'action': 'eval-config-list'});
    },
  );

  test('preflights start cost and validates exact receipt', () async {
    final api = _Api([
      const AdminOperatorResponse(200, {
        'result': {'run_id': runId, 'status': 'queued', 'case_count': 3},
      }),
    ]);
    final repository = EvalRepository(
      AdminOperatorRepository(api),
      requestIds: () => requestId,
    );
    final config = EvalConfig(
      key: 'gemini-3.6-flash-recommendation-v1',
      role: EvalConfigRole.candidate,
      feature: EvalFeature.recommendation,
      provider: 'gemini',
      model: 'gemini-3.6-flash',
      promptVersion: 'recommendation-v1',
      taskScope: 'fixed_selection_explanation_and_arithmetic',
      estimatedMaximumCostUsd: .03,
      scopeNote: 'Does not evaluate ranking.',
    );
    await repository.start(
      EvalStartRequest(
        datasetVersion: 12,
        candidate: config,
        maximumCaseCount: 3,
        costCeilingUsd: .12,
        latencyCeilingMs: 5000,
      ),
    );
    expect(api.requests.single['request_id'], requestId);
    expect(api.requests.single['operation'], 'start');
    await expectLater(
      repository.start(
        EvalStartRequest(
          datasetVersion: 12,
          candidate: config,
          maximumCaseCount: 3,
          costCeilingUsd: .11,
          latencyCeilingMs: 5000,
        ),
      ),
      throwsA(isA<AdminRequestFailed>()),
    );
  });

  test('decodes paginated list and audited safe detail decision', () async {
    final api = _Api([
      AdminOperatorResponse(200, {
        'items': [run()],
        'page': 1,
        'limit': 20,
        'total': 1,
      }),
      AdminOperatorResponse(200, {
        'run': run(),
        'metrics': {
          'baseline_pass_rate': .5,
          'candidate_pass_rate': 1.0,
          'p95_candidate_latency_ms': 30,
          'manual_review_count': 0,
        },
        'decision': {'status': 'candidate_supported', 'blockers': []},
        'results': {'items': [], 'page': 1, 'limit': 25, 'total': 0},
      }),
    ]);
    final repository = EvalRepository(
      AdminOperatorRepository(api),
      requestIds: () => requestId,
    );
    final page = await repository.runs();
    final detail = await repository.detail(runId);
    expect(page.items.single.scopeNote, 'Does not evaluate ranking.');
    expect(detail.decision, EvalDecision.candidateSupported);
    expect(api.requests.last['request_id'], requestId);
  });

  test('cancel preserves observed version and validates receipt', () async {
    final api = _Api([
      const AdminOperatorResponse(200, {
        'result': {'run_id': runId, 'status': 'cancelled'},
      }),
    ]);
    await EvalRepository(
      AdminOperatorRepository(api),
      requestIds: () => requestId,
    ).cancel(runId, updated);
    expect(api.requests.single, {
      'action': 'eval-run-action',
      'operation': 'cancel',
      'run_id': runId,
      'request_id': requestId,
      'observed_updated_at': updated,
    });
  });
}
