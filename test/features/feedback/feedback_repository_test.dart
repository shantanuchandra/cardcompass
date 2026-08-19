import 'dart:convert';

import 'package:cardcompass/features/feedback/feedback_models.dart';
import 'package:cardcompass/features/feedback/feedback_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const firstId = '10000000-0000-4000-8000-000000000001';
  const secondId = '10000000-0000-4000-8000-000000000002';
  const outputId = '20000000-0000-4000-8000-000000000001';

  test('submits the exact transaction feedback contract', () async {
    final api = _RecordingApi([
      const FeedbackApiResponse(202, {
        'feedback_id': '30000000-0000-4000-8000-000000000001',
        'triage_status': 'awaiting_triage',
      }),
    ]);
    final repository = FeedbackRepository(api, requestIds: _ids([firstId]));

    final submission = repository.newSubmission(
      const TransactionFeedbackTarget(outputId),
      'The category should be groceries.',
    );
    final result = await repository.submit(submission);

    expect(api.requests.single, {
      'action': 'feedback-submit',
      'feature_key': 'statement_processing',
      'output_ref_type': 'transaction',
      'output_ref_id': outputId,
      'feedback_text': 'The category should be groceries.',
      'request_id': firstId,
    });
    expect(result.feedbackId, '30000000-0000-4000-8000-000000000001');
    expect(result.triageStatus, 'awaiting_triage');
  });

  test('retry keeps an id while an edited submission gets a new id', () async {
    final api = _RecordingApi([
      const FeedbackApiResponse(500, {'error': 'request_failed'}),
      const FeedbackApiResponse(202, {
        'feedback_id': '30000000-0000-4000-8000-000000000001',
        'triage_status': 'awaiting_triage',
      }),
      const FeedbackApiResponse(202, {
        'feedback_id': '30000000-0000-4000-8000-000000000002',
        'triage_status': 'awaiting_triage',
      }),
    ]);
    final repository = FeedbackRepository(
      api,
      requestIds: _ids([firstId, secondId]),
    );
    final initial = repository.newSubmission(
      const UserCardFeedbackTarget(outputId),
      'This annual fee is out of date.',
    );

    await expectLater(
      repository.submit(initial),
      throwsA(isA<FeedbackFailed>()),
    );
    await repository.submit(initial);
    final edited = repository.newSubmission(
      initial.target,
      'This annual fee and renewal date are out of date.',
    );
    await repository.submit(edited);

    expect(api.requests[0]['request_id'], firstId);
    expect(api.requests[1]['request_id'], firstId);
    expect(api.requests[2]['request_id'], secondId);
  });

  test(
    'creates a recommendation trace without client model metadata',
    () async {
      final api = _RecordingApi([
        const FeedbackApiResponse(201, {
          'trace_id': outputId,
          'expires_at': '2026-08-20T00:00:00Z',
        }),
      ]);
      final repository = FeedbackRepository(api, requestIds: _ids([firstId]));

      final target = await repository.createRecommendationTarget(
        const RecommendationTraceInput(
          safeInputContext: {'merchant': 'Cinema'},
          outputSnapshot: {'winner': 'Card A'},
          cardIds: ['30000000-0000-4000-8000-000000000001'],
          benefitIds: ['40000000-0000-4000-8000-000000000001'],
          engineVersion: 'movie-deals-v2',
        ),
      );

      expect(target, const RecommendationFeedbackTarget(outputId));
      expect(api.requests.single, {
        'action': 'trace-create',
        'feature_key': 'recommendation',
        'safe_input_context': {'merchant': 'Cinema'},
        'output_snapshot': {'winner': 'Card A'},
        'card_ids': ['30000000-0000-4000-8000-000000000001'],
        'benefit_ids': ['40000000-0000-4000-8000-000000000001'],
        'engine_version': 'movie-deals-v2',
        'request_id': firstId,
      });
      expect(api.requests.single.keys, isNot(contains('model')));
      expect(
        utf8.encode(jsonEncode(api.requests.single)).length,
        lessThanOrEqualTo(32768),
      );
    },
  );

  test('rejects oversized requests before invoking the API', () async {
    final api = _RecordingApi(const []);
    final repository = FeedbackRepository(api, requestIds: _ids([firstId]));

    await expectLater(
      repository.createRecommendationTarget(
        RecommendationTraceInput(
          safeInputContext: const {},
          outputSnapshot: {'explanation': List.filled(33000, 'x').join()},
          cardIds: const [],
          benefitIds: const [],
          engineVersion: 'movie-deals-v2',
        ),
      ),
      throwsA(isA<FeedbackInvalidRequest>()),
    );
    expect(api.requests, isEmpty);
  });

  test(
    'maps malformed and unsafe endpoint failures to stable errors',
    () async {
      for (final response in [
        const FeedbackApiResponse(202, {'feedback_id': 7}),
        const FeedbackApiResponse(500, {'error': 'database_secret'}),
      ]) {
        final repository = FeedbackRepository(
          _RecordingApi([response]),
          requestIds: _ids([firstId]),
        );
        final submission = repository.newSubmission(
          const UserCardFeedbackTarget(outputId),
          'The displayed issuer name is incorrect.',
        );
        await expectLater(
          repository.submit(submission),
          throwsA(
            isA<FeedbackFailed>().having(
              (error) => error.code,
              'code',
              'request_failed',
            ),
          ),
        );
      }
    },
  );

  test(
    'rejects a malformed output reference before invoking the API',
    () async {
      final api = _RecordingApi(const []);
      final repository = FeedbackRepository(api, requestIds: _ids([firstId]));
      final submission = repository.newSubmission(
        const TransactionFeedbackTarget('not-a-uuid'),
        'This category should be groceries.',
      );

      await expectLater(
        repository.submit(submission),
        throwsA(isA<FeedbackInvalidRequest>()),
      );
      expect(api.requests, isEmpty);
    },
  );

  test('rejects malformed success identifiers as a safe failure', () async {
    for (final fixture in [
      const FeedbackApiResponse(202, {
        'feedback_id': 'not-a-uuid',
        'triage_status': 'awaiting_triage',
      }),
      const FeedbackApiResponse(201, {
        'trace_id': 'not-a-uuid',
        'expires_at': '2026-08-20T00:00:00Z',
      }),
    ]) {
      final repository = FeedbackRepository(
        _RecordingApi([fixture]),
        requestIds: _ids([firstId]),
      );
      final operation = fixture.status == 202
          ? repository.submit(
              repository.newSubmission(
                const TransactionFeedbackTarget(outputId),
                'This category should be groceries.',
              ),
            )
          : repository.createRecommendationTarget(
              const RecommendationTraceInput(
                safeInputContext: {},
                outputSnapshot: {},
                cardIds: [],
                benefitIds: [],
                engineVersion: 'movie-deals-v2',
              ),
            );

      await expectLater(
        operation,
        throwsA(
          isA<FeedbackFailed>().having(
            (error) => error.code,
            'code',
            'request_failed',
          ),
        ),
      );
    }
  });
}

Iterator<String> _ids(List<String> values) => values.iterator;

class _RecordingApi implements FeedbackApi {
  _RecordingApi(this._responses);

  final List<FeedbackApiResponse> _responses;
  final List<Map<String, Object?>> requests = [];

  @override
  Future<FeedbackApiResponse> invoke(Map<String, Object?> body) async {
    requests.add(body);
    return _responses.removeAt(0);
  }
}
