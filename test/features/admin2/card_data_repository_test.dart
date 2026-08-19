import 'package:cardcompass/features/admin2/card_data/card_data_models.dart';
import 'package:cardcompass/features/admin2/card_data/card_data_repository.dart';
import 'package:cardcompass/features/admin2/data/admin_operator_api.dart';
import 'package:cardcompass/features/admin2/data/admin_operator_repository.dart';
import 'package:flutter_test/flutter_test.dart';

final class RecordingAdminOperatorApi implements AdminOperatorApi {
  RecordingAdminOperatorApi(this.response);

  final AdminOperatorResponse response;
  final bodies = <Map<String, dynamic>>[];

  @override
  Future<AdminOperatorResponse> invoke(Map<String, dynamic> body) async {
    bodies.add(body);
    return response;
  }
}

void main() {
  const identityId = '22222222-2222-4222-8222-222222222222';
  const stagingId = '33333333-3333-4333-8333-333333333333';
  const observed = '2026-08-19T09:00:00Z';

  test(
    'maps identity and benefit pages with safe evidence and pagination',
    () async {
      final api = RecordingAdminOperatorApi(
        const AdminOperatorResponse(200, {
          'lane': 'identity',
          'items': [
            {
              'id': identityId,
              'status': 'pending',
              'updated_at': observed,
              'confidence': 0.82,
              'proposed_fields': {'card_name': 'Premier'},
              'source_evidence': {
                'official_url': 'https://issuer.example/card',
                'source_excerpt': 'Official product page',
                'retrieved_at': observed,
              },
              'existing_candidates': [],
              'validation_warnings': [
                {'code': 'ambiguous_match'},
              ],
              'discovery_job': {'attempt_count': 2},
            },
          ],
          'page': 2,
          'limit': 25,
          'has_more': true,
        }),
      );
      final repository = CardDataRepository(
        AdminOperatorRepository(api),
        now: () => DateTime.utc(2026, 8, 19, 10),
      );

      final page = await repository.list(
        CardReviewLane.identity,
        page: 2,
        limit: 25,
        status: 'pending',
      );

      expect(page.lane, CardReviewLane.identity);
      expect(page.hasMore, isTrue);
      expect(page.refreshedAt, DateTime.utc(2026, 8, 19, 10));
      expect(
        page.items.single.evidence.single.officialUrl,
        'https://issuer.example/card',
      );
      expect(page.items.single.warningCodes, ['ambiguous_match']);
      expect(api.bodies.single, {
        'action': 'card-review-list',
        'lane': 'identity',
        'page': 2,
        'limit': 25,
        'status': 'pending',
      });
    },
  );

  test('benefit page captures staging and card metadata', () async {
    final api = RecordingAdminOperatorApi(
      const AdminOperatorResponse(200, {
        'lane': 'benefit',
        'items': [
          {
            'id': identityId,
            'status': 'review_required',
            'updated_at': observed,
            'parser_version': 'benefit-v2',
            'staging_id': stagingId,
            'card': {'bank': 'Issuer', 'card_name': 'Premier'},
            'staging': {
              'source_url': 'https://issuer.example/benefits',
              'source_evidence': [
                {
                  'source_url': 'https://issuer.example/benefits',
                  'source_excerpt': 'Dining credit',
                },
              ],
            },
          },
        ],
        'page': 1,
        'limit': 25,
        'has_more': false,
      }),
    );

    final page = await CardDataRepository(
      AdminOperatorRepository(api),
    ).list(CardReviewLane.benefit);

    expect(page.items.single.stagingId, stagingId);
    expect(page.items.single.parserVersion, 'benefit-v2');
    expect(page.items.single.cardName, 'Premier');
    expect(page.items.single.evidence.single.excerpt, 'Dining credit');
  });

  for (final operation in CardReviewOperation.values) {
    test('${operation.name} serializes its exact operation', () async {
      final api = RecordingAdminOperatorApi(
        const AdminOperatorResponse(200, {'result': {}}),
      );
      final repository = CardDataRepository(
        AdminOperatorRepository(api),
        requestIds: () => '11111111-1111-4111-8111-111111111111',
      );
      await repository.act(
        CardReviewAction(
          lane:
              operation == CardReviewOperation.quarantine ||
                  operation == CardReviewOperation.unquarantine
              ? CardReviewLane.benefit
              : CardReviewLane.identity,
          operation: operation,
          targetId: identityId,
          observedUpdatedAt: observed,
          stagingId:
              operation == CardReviewOperation.approve ||
                  operation == CardReviewOperation.editApprove ||
                  operation == CardReviewOperation.reject
              ? stagingId
              : null,
          reason:
              operation == CardReviewOperation.reject ||
                  operation == CardReviewOperation.quarantine
              ? 'operator reason'
              : null,
          payload: operation == CardReviewOperation.editApprove
              ? const {
                  'proposed_fields': {'card_name': 'Corrected'},
                }
              : operation == CardReviewOperation.merge
              ? const {'merge_card_id': '44444444-4444-4444-8444-444444444444'}
              : const {},
        ),
      );

      expect(api.bodies.single['operation'], operation.wireValue);
      expect(
        api.bodies.single['request_id'],
        '11111111-1111-4111-8111-111111111111',
      );
      expect(api.bodies.single['observed_updated_at'], observed);
    });
  }

  test('benefit retry includes request id and observed state', () async {
    final api = RecordingAdminOperatorApi(
      const AdminOperatorResponse(200, {'result': {}}),
    );
    final repository = CardDataRepository(
      AdminOperatorRepository(api),
      requestIds: () => '11111111-1111-4111-8111-111111111111',
    );

    await repository.act(
      CardReviewAction(
        lane: CardReviewLane.benefit,
        operation: CardReviewOperation.retry,
        targetId: identityId,
        observedUpdatedAt: observed,
      ),
    );

    expect(api.bodies.single, {
      'action': 'card-review-action',
      'lane': 'benefit',
      'operation': 'retry',
      'target_id': identityId,
      'request_id': '11111111-1111-4111-8111-111111111111',
      'observed_updated_at': observed,
    });
  });

  test('benefit approval serializes staging and decisions', () async {
    final api = RecordingAdminOperatorApi(
      const AdminOperatorResponse(200, {'result': {}}),
    );
    final repository = CardDataRepository(
      AdminOperatorRepository(api),
      requestIds: () => '11111111-1111-4111-8111-111111111111',
    );

    await repository.act(
      CardReviewAction(
        lane: CardReviewLane.benefit,
        operation: CardReviewOperation.approve,
        targetId: identityId,
        observedUpdatedAt: observed,
        stagingId: stagingId,
        payload: {
          'decisions': [
            {'action': 'approve', 'dedupe_key': 'dining-credit'},
          ],
        },
      ),
    );

    expect(api.bodies.single['staging_id'], stagingId);
    expect(api.bodies.single['decisions'], [
      {'action': 'approve', 'dedupe_key': 'dining-credit'},
    ]);
  });

  test('malformed card response becomes a safe request failure', () async {
    final api = RecordingAdminOperatorApi(
      const AdminOperatorResponse(200, {
        'lane': 'identity',
        'items': [
          {'id': 7},
        ],
        'page': 1,
        'limit': 25,
        'has_more': false,
      }),
    );

    expect(
      CardDataRepository(
        AdminOperatorRepository(api),
      ).list(CardReviewLane.identity),
      throwsA(isA<AdminRequestFailed>()),
    );
  });
}
