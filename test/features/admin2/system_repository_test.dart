import 'dart:convert';

import 'package:cardcompass/features/admin2/data/admin_operator_api.dart';
import 'package:cardcompass/features/admin2/data/admin_operator_repository.dart';
import 'package:cardcompass/features/admin2/system/system_models.dart';
import 'package:cardcompass/features/admin2/system/system_repository.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Api implements AdminOperatorApi {
  _Api(this.responses);
  final List<AdminOperatorResponse> responses;
  final bodies = <Map<String, dynamic>>[];
  @override
  Future<AdminOperatorResponse> invoke(Map<String, dynamic> body) async {
    bodies.add(jsonDecode(jsonEncode(body)) as Map<String, dynamic>);
    return responses.removeAt(0);
  }
}

void main() {
  const jobId = '22222222-2222-4222-8222-222222222222';
  const observed = '2026-08-19T09:00:00Z';

  test('strictly decodes status and deeply immutable source state', () async {
    final api = _Api([
      const AdminOperatorResponse(200, {
        'pipelines': [
          {
            'key': 'benefit_enrichment',
            'status': 'degraded',
            'queued': 4,
            'running': 1,
            'failed': 2,
            'quarantined': 1,
            'last_success_at': observed,
            'source_error': null,
          },
          {
            'key': 'card_discovery',
            'status': 'unknown',
            'queued': 0,
            'running': 0,
            'failed': 0,
            'quarantined': 0,
            'last_success_at': null,
            'source_error': 'source_unavailable',
          },
        ],
        'controls': [
          {
            'control_key': 'benefit_enrichment_scheduled',
            'is_paused': false,
            'reason': null,
            'updated_at': observed,
          },
        ],
        'control_source_error': null,
      }),
    ]);
    final status = await SystemRepository(
      AdminOperatorRepository(api),
      now: () => DateTime.utc(2026, 8, 19, 10),
    ).status();
    expect(status.pipelines.first.failed, 2);
    expect(
      status.pipelines.last.sourceError,
      SystemSourceError.sourceUnavailable,
    );
    expect(status.refreshedAt, DateTime.utc(2026, 8, 19, 10));
    expect(
      () => status.pipelines.add(status.pipelines.first),
      throwsUnsupportedError,
    );
    expect(api.bodies.single, {'action': 'system-status'});
  });

  test('rejects coercible or incomplete DTOs as request_failed', () async {
    final api = _Api([
      const AdminOperatorResponse(200, {
        'pipelines': [
          {
            'key': 'benefit_enrichment',
            'status': 'healthy',
            'queued': '0',
            'running': 0,
            'failed': 0,
            'quarantined': 0,
            'last_success_at': null,
            'source_error': null,
          },
        ],
        'controls': [],
        'control_source_error': null,
      }),
    ]);
    await expectLater(
      SystemRepository(AdminOperatorRepository(api)).status(),
      throwsA(isA<AdminRequestFailed>()),
    );
  });

  test('decodes exact jobs pagination and sends allowlisted fields', () async {
    final api = _Api([
      const AdminOperatorResponse(200, {
        'items': [
          {
            'id': jobId,
            'family': 'benefit_enrichment',
            'status': 'failed',
            'failure_category': 'source_timeout',
            'attempt_count': 3,
            'next_retry_at': null,
            'updated_at': observed,
          },
        ],
        'page': 2,
        'limit': 25,
        'has_more': true,
      }),
    ]);
    final page = await SystemRepository(
      AdminOperatorRepository(api),
    ).jobs(SystemJobFamily.benefitEnrichment, page: 2, status: 'failed');
    expect(page.items.single.attemptCount, 3);
    expect(page.hasMore, isTrue);
    expect(api.bodies.single, {
      'action': 'system-jobs',
      'family': 'benefit_enrichment',
      'page': 2,
      'limit': 25,
      'status': 'failed',
    });
  });

  test('serializes every mutation exactly with a fresh request id', () async {
    final api = _Api([
      const AdminOperatorResponse(200, {
        'result': {'job_id': jobId, 'resulting_status': 'queued'},
      }),
      const AdminOperatorResponse(200, {
        'result': {'job_id': jobId, 'resulting_status': 'quarantined'},
      }),
      const AdminOperatorResponse(200, {
          'result': {'job_id': jobId, 'resulting_status': 'queued'},
      }),
    ]);
    var next = 0;
    final ids = [
      '11111111-1111-4111-8111-111111111111',
      '33333333-3333-4333-8333-333333333333',
      '44444444-4444-4444-8444-444444444444',
    ];
    final repository = SystemRepository(
      AdminOperatorRepository(api),
      requestIds: () => ids[next++],
    );
    await repository.mutate(
      const RetrySystemJob(
        family: SystemJobFamily.benefitEnrichment,
        targetId: jobId,
        status: 'failed',
        observedUpdatedAt: observed,
      ),
    );
    await repository.mutate(
      const QuarantineSystemJob(
        family: SystemJobFamily.benefitEnrichment,
        targetId: jobId,
        status: 'failed',
        observedUpdatedAt: observed,
        reason: 'Bad source',
      ),
    );
    await repository.mutate(
      const UnquarantineSystemJob(
        family: SystemJobFamily.benefitEnrichment,
        targetId: jobId,
        status: 'quarantined',
        observedUpdatedAt: observed,
      ),
    );
    expect(api.bodies[0], {
      'action': 'system-retry',
      'operation': 'retry',
      'family': 'benefit_enrichment',
      'target_id': jobId,
      'status': 'failed',
      'request_id': ids[0],
      'observed_updated_at': observed,
    });
    expect(api.bodies[1]['action'], 'system-quarantine');
    expect(api.bodies[1]['operation'], 'quarantine');
    expect(api.bodies[1]['reason'], 'Bad source');
    expect(api.bodies[2]['operation'], 'unquarantine');
    expect(api.bodies.map((e) => e['request_id']).toSet(), hasLength(3));
  });

  test(
    'serializes pause and resume with exact control version and reason',
    () async {
      final api = _Api(
        List.generate(
          2,
          (index) => AdminOperatorResponse(200, {
            'result': {
              'control_key': 'benefit_enrichment_scheduled',
              'is_paused': index == 0,
              'reason': index == 0 ? 'Incident' : 'Recovered',
              'updated_at': '2026-08-19T10:00:0${index}Z',
            },
          }),
        ),
      );
      var n = 1;
      final repository = SystemRepository(
        AdminOperatorRepository(api),
        requestIds: () => '11111111-1111-4111-8111-11111111111${n++}',
      );
      await repository.mutate(
        const PauseSystemControl(
          observedUpdatedAt: observed,
          reason: 'Incident',
        ),
      );
      await repository.mutate(
        const ResumeSystemControl(
          observedUpdatedAt: observed,
          reason: 'Recovered',
        ),
      );
      expect(api.bodies.first['is_paused'], isTrue);
      expect(api.bodies.last['is_paused'], isFalse);
      expect(api.bodies.last['control_key'], 'benefit_enrichment_scheduled');
    },
  );

  test(
    'rejects missing reasons and oversized UTF-8 requests preflight',
    () async {
      final api = _Api([]);
      final repository = SystemRepository(AdminOperatorRepository(api));
      await expectLater(
        repository.mutate(
          const QuarantineSystemJob(
            family: SystemJobFamily.benefitEnrichment,
            targetId: jobId,
            status: 'failed',
            observedUpdatedAt: observed,
            reason: ' ',
          ),
        ),
        throwsA(isA<AdminRequestFailed>()),
      );
      await expectLater(
        repository.mutate(
          PauseSystemControl(observedUpdatedAt: observed, reason: '€' * 11000),
        ),
        throwsA(isA<AdminRequestFailed>()),
      );
      expect(api.bodies, isEmpty);
    },
  );

  test('rejects a malformed or mismatched mutation receipt', () async {
    final api = _Api([
      const AdminOperatorResponse(200, {
        'result': {'job_id': jobId, 'resulting_status': 'completed'},
      }),
    ]);
    await expectLater(
      SystemRepository(
        AdminOperatorRepository(api),
        requestIds: () => '11111111-1111-4111-8111-111111111111',
      ).mutate(
        const RetrySystemJob(
          family: SystemJobFamily.benefitEnrichment,
          targetId: jobId,
          status: 'failed',
          observedUpdatedAt: observed,
        ),
      ),
      throwsA(isA<AdminRequestFailed>()),
    );
  });
}
