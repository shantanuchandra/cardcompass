import 'package:cardcompass/features/admin2/card_data/card_data_models.dart';
import 'package:cardcompass/features/admin2/data/admin_operator_api.dart';
import 'package:cardcompass/features/admin2/data/admin_operator_repository.dart';
import 'package:cardcompass/features/admin2/inbox/inbox_models.dart';
import 'package:cardcompass/features/admin2/inbox/inbox_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final class _Api implements AdminOperatorApi {
  _Api(this.response, {this.error});
  final AdminOperatorResponse response;
  final Object? error;
  final bodies = <Map<String, dynamic>>[];

  @override
  Future<AdminOperatorResponse> invoke(Map<String, dynamic> body) async {
    bodies.add(body);
    if (error != null) throw error!;
    return response;
  }
}

void main() {
  test(
    'maps ranked inbox destinations, partial failures and refresh time',
    () async {
      final api = _Api(
        const AdminOperatorResponse(200, {
          'items': [
            {
              'id': 'benefit-enrichment:job-1',
              'type': 'benefit_enrichment_review',
              'severity': 'high',
              'title': 'Recover benefits',
              'explanation': 'Needs recovery.',
              'source_status': 'failed',
              'age_seconds': 7200,
              'destination': {
                'section': 'cardData',
                'lane': 'benefit',
                'target_id': 'job-1',
              },
            },
          ],
          'partial_failures': ['card_identity'],
          'refreshed_at': '2026-08-19T09:00:00.000Z',
        }),
      );

      final snapshot = await InboxRepository(
        AdminOperatorRepository(api),
      ).load();

      expect(snapshot.partialFailures, [InboxSource.cardIdentity]);
      expect(snapshot.refreshedAt, DateTime.utc(2026, 8, 19, 9));
      expect(snapshot.items.single.severity, AdminInboxSeverity.high);
      expect(snapshot.items.single.destination.lane, CardReviewLane.benefit);
      expect(snapshot.items.single.destination.targetId, 'job-1');
      expect(api.bodies.single, {'action': 'inbox-list'});
    },
  );

  test('rejects malformed inbox data without a dynamic crash', () async {
    final api = _Api(
      const AdminOperatorResponse(200, {
        'items': [
          {'id': 'x', 'severity': 'urgent'},
        ],
        'partial_failures': [],
        'refreshed_at': 'not-a-date',
      }),
    );

    expect(
      InboxRepository(AdminOperatorRepository(api)).load(),
      throwsA(isA<AdminRequestFailed>()),
    );
  });

  for (final status in [401, 403, 409, 500]) {
    test('$status uses the common stable error mapping', () async {
      final api = _Api(
        AdminOperatorResponse(status, {
          'error': status == 409 ? 'state_conflict' : 'request_failed',
        }),
      );
      final matcher = switch (status) {
        401 => isA<AdminAuthenticationRequired>(),
        403 => isA<AdminAccessDenied>(),
        409 => isA<AdminStateConflict>(),
        _ => isA<AdminRequestFailed>(),
      };
      expect(
        InboxRepository(AdminOperatorRepository(api)).load(),
        throwsA(matcher),
      );
    });
  }

  test('FunctionException conflict uses the common state mapping', () async {
    final api = _Api(
      const AdminOperatorResponse(500, {}),
      error: const FunctionException(
        status: 409,
        details: {'error': 'state_conflict'},
      ),
    );

    expect(
      InboxRepository(AdminOperatorRepository(api)).load(),
      throwsA(isA<AdminStateConflict>()),
    );
  });

  test('unknown invocation failure is sanitized without raw detail', () async {
    final api = _Api(
      const AdminOperatorResponse(500, {}),
      error: StateError('socket leaked-internal-host.example'),
    );

    try {
      await InboxRepository(AdminOperatorRepository(api)).load();
      fail('expected a safe failure');
    } on AdminRequestFailed catch (error) {
      expect(error.message, 'request_failed');
      expect(error.toString(), isNot(contains('leaked-internal-host')));
    }
  });
}
