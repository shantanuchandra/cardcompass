import 'package:cardcompass/features/admin2/data/admin_operator_api.dart';
import 'package:cardcompass/features/admin2/data/admin_operator_repository.dart';
import 'package:cardcompass/features/admin2/feedback/feedback_models.dart';
import 'package:cardcompass/features/admin2/feedback/feedback_repository.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Api implements AdminOperatorApi {
  final requests = <Map<String, dynamic>>[];
  var failFirst = true;
  @override
  Future<AdminOperatorResponse> invoke(Map<String, dynamic> body) async {
    requests.add(body);
    if (failFirst) {
      failFirst = false;
      throw const AdminRequestFailed('request_failed');
    }
    return AdminOperatorResponse(200, {
      'feedback_id': body['feedback_id'],
      'triage_status': 'awaiting_triage',
    });
  }
}

void main() {
  test(
    'list decodes page metadata and forwards stable pagination filters',
    () async {
      final api = _ListApi();
      final page = await FeedbackAdminRepository(
        AdminOperatorRepository(api),
      ).list(page: 5, limit: 25, reviewStatus: 'eval_created');
      expect(page.page, 5);
      expect(page.total, 126);
      expect(page.hasMore, isTrue);
      expect(api.request, {
        'action': 'feedback-list',
        'page': 5,
        'limit': 25,
        'review_status': 'eval_created',
      });
    },
  );
  test(
    'triage retry preserves one request identity across response-loss retry',
    () async {
      final api = _Api();
      var repository = FeedbackAdminRepository(AdminOperatorRepository(api));
      const mutation = FeedbackTriageRetry(
        feedbackId: '10000000-0000-4000-8000-000000000001',
        requestId: '20000000-0000-4000-8000-000000000001',
      );
      await expectLater(
        repository.retryTriage(mutation),
        throwsA(isA<AdminRequestFailed>()),
      );
      repository = FeedbackAdminRepository(AdminOperatorRepository(api));
      await repository.retryTriage(mutation);
      expect(api.requests, hasLength(2));
      expect(api.requests[0]['request_id'], api.requests[1]['request_id']);
      expect(api.requests[0]['action'], 'feedback-triage-retry');
    },
  );
  test('detail decodes every ordered eval revision', () async {
    final detail = await FeedbackAdminRepository(
      AdminOperatorRepository(_DetailApi()),
    ).detail('10000000-0000-4000-8000-000000000001');
    expect(detail.evalCases.map((item) => item.revision), [2, 1]);
    expect(detail.evalCases.last.status, 'retired');
    expect(detail.evalCases.last.capturedOutput, {'captured': 1});
    expect(detail.evalCases.last.retiredAt, isNotNull);
  });
}

final class _ListApi implements AdminOperatorApi {
  Map<String, dynamic>? request;
  @override
  Future<AdminOperatorResponse> invoke(Map<String, dynamic> body) async {
    request = body;
    return const AdminOperatorResponse(200, {
      'items': [],
      'page': 5,
      'limit': 25,
      'total': 126,
    });
  }
}

final class _DetailApi implements AdminOperatorApi {
  @override
  Future<AdminOperatorResponse> invoke(Map<String, dynamic> body) async =>
      AdminOperatorResponse(200, {
        'feedback': {
          'id': '10000000-0000-4000-8000-000000000001',
          'feature': 'card_data',
          'feedback_text': 'Wrong benefit amount',
          'captured_output': {},
          'safe_context': {},
          'authoritative_context': {},
          'triage_status': 'triaged',
          'review_status': 'eval_created',
          'triage_proposal': {},
          'severity': 'normal',
          'model': null,
          'prompt_version': null,
          'created_at': '2026-08-19T00:00:00Z',
          'provider': null,
          'engine_version': null,
          'parser_version': null,
          'trace_id': null,
          'route_destination': {},
          'review_reason': null,
        },
        'eval_cases': [
          for (final revision in [2, 1])
            {
              'id': '20000000-0000-4000-8000-00000000000$revision',
              'status': revision == 1 ? 'retired' : 'draft',
              'revision': revision,
              'updated_at': '2026-08-19T0$revision:00:00Z',
              'input_fixture': {'input': revision},
              'captured_output': {'captured': revision},
              'expected_output': {'expected': revision},
              'operator_feedback': 'Revision $revision',
              'scoring_rubric': {'exact': true},
              'severe_failure_conditions': {'wrong': true},
              'approved_in_dataset_version': revision,
              'retired_in_dataset_version': revision == 1 ? 2 : null,
              'approved_at': '2026-08-19T00:00:00Z',
              'retired_at': revision == 1 ? '2026-08-20T00:00:00Z' : null,
            },
        ],
      });
}
