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

  final validActions =
      <({String name, CardReviewAction action, Map<String, dynamic> extras})>[
        (
          name: 'identity approve',
          action: CardReviewAction(
            lane: CardReviewLane.identity,
            operation: CardReviewOperation.approve,
            targetId: identityId,
            observedUpdatedAt: observed,
          ),
          extras: const {},
        ),
        (
          name: 'identity edit approve',
          action: CardReviewAction(
            lane: CardReviewLane.identity,
            operation: CardReviewOperation.editApprove,
            targetId: identityId,
            observedUpdatedAt: observed,
            payload: const {
              'proposed_fields': {'card_name': 'Corrected'},
            },
          ),
          extras: const {
            'proposed_fields': {'card_name': 'Corrected'},
          },
        ),
        (
          name: 'identity merge',
          action: CardReviewAction(
            lane: CardReviewLane.identity,
            operation: CardReviewOperation.merge,
            targetId: identityId,
            observedUpdatedAt: observed,
            payload: const {
              'merge_card_id': '44444444-4444-4444-8444-444444444444',
            },
          ),
          extras: const {
            'merge_card_id': '44444444-4444-4444-8444-444444444444',
          },
        ),
        (
          name: 'identity reject',
          action: CardReviewAction(
            lane: CardReviewLane.identity,
            operation: CardReviewOperation.reject,
            targetId: identityId,
            observedUpdatedAt: observed,
            reason: 'not a product',
          ),
          extras: const {'reason': 'not a product'},
        ),
        (
          name: 'identity retry',
          action: CardReviewAction(
            lane: CardReviewLane.identity,
            operation: CardReviewOperation.retry,
            targetId: identityId,
            observedUpdatedAt: observed,
          ),
          extras: const {},
        ),
        for (final configuration in [
          (operation: CardReviewOperation.approve, decision: 'approve'),
          (operation: CardReviewOperation.editApprove, decision: 'edit'),
        ])
          (
            name: 'benefit ${configuration.operation.name}',
            action: CardReviewAction(
              lane: CardReviewLane.benefit,
              operation: configuration.operation,
              targetId: identityId,
              observedUpdatedAt: observed,
              stagingId: stagingId,
              payload: {
                'decisions': [
                  {'action': configuration.decision},
                ],
              },
            ),
            extras: {
              'staging_id': stagingId,
              'decisions': [
                {'action': configuration.decision},
              ],
            },
          ),
        (
          name: 'benefit reject',
          action: CardReviewAction(
            lane: CardReviewLane.benefit,
            operation: CardReviewOperation.reject,
            targetId: identityId,
            observedUpdatedAt: observed,
            stagingId: stagingId,
            reason: 'unsupported',
            payload: const {
              'decisions': [
                {'action': 'reject'},
              ],
            },
          ),
          extras: const {
            'staging_id': stagingId,
            'reason': 'unsupported',
            'decisions': [
              {'action': 'reject'},
            ],
          },
        ),
        (
          name: 'benefit retry',
          action: CardReviewAction(
            lane: CardReviewLane.benefit,
            operation: CardReviewOperation.retry,
            targetId: identityId,
            observedUpdatedAt: observed,
          ),
          extras: const {},
        ),
        (
          name: 'benefit quarantine',
          action: CardReviewAction(
            lane: CardReviewLane.benefit,
            operation: CardReviewOperation.quarantine,
            targetId: identityId,
            observedUpdatedAt: observed,
            reason: 'bad extraction',
          ),
          extras: const {'reason': 'bad extraction'},
        ),
        (
          name: 'benefit unquarantine',
          action: CardReviewAction(
            lane: CardReviewLane.benefit,
            operation: CardReviewOperation.unquarantine,
            targetId: identityId,
            observedUpdatedAt: observed,
          ),
          extras: const {},
        ),
      ];

  for (final request in validActions) {
    test('${request.name} serializes an exact body', () async {
      final api = RecordingAdminOperatorApi(
        const AdminOperatorResponse(200, {'result': {}}),
      );
      final repository = CardDataRepository(
        AdminOperatorRepository(api),
        requestIds: () => '11111111-1111-4111-8111-111111111111',
      );
      await repository.act(request.action);

      expect(api.bodies.single, {
        'action': 'card-review-action',
        'lane': request.action.lane.wireValue,
        'operation': request.action.operation.wireValue,
        'target_id': identityId,
        'request_id': '11111111-1111-4111-8111-111111111111',
        'observed_updated_at': observed,
        ...request.extras,
      });
    });
  }

  final invalidActions = [
    CardReviewAction(
      lane: CardReviewLane.identity,
      operation: CardReviewOperation.quarantine,
      targetId: identityId,
      observedUpdatedAt: observed,
      reason: 'why',
    ),
    CardReviewAction(
      lane: CardReviewLane.benefit,
      operation: CardReviewOperation.merge,
      targetId: identityId,
      observedUpdatedAt: observed,
      payload: const {'merge_card_id': identityId},
    ),
    CardReviewAction(
      lane: CardReviewLane.identity,
      operation: CardReviewOperation.editApprove,
      targetId: identityId,
      observedUpdatedAt: observed,
    ),
    CardReviewAction(
      lane: CardReviewLane.identity,
      operation: CardReviewOperation.merge,
      targetId: identityId,
      observedUpdatedAt: observed,
    ),
    CardReviewAction(
      lane: CardReviewLane.identity,
      operation: CardReviewOperation.reject,
      targetId: identityId,
      observedUpdatedAt: observed,
    ),
    CardReviewAction(
      lane: CardReviewLane.benefit,
      operation: CardReviewOperation.approve,
      targetId: identityId,
      observedUpdatedAt: observed,
      stagingId: stagingId,
    ),
    CardReviewAction(
      lane: CardReviewLane.benefit,
      operation: CardReviewOperation.reject,
      targetId: identityId,
      observedUpdatedAt: observed,
      stagingId: stagingId,
      reason: 'why',
      payload: const {'decisions': []},
    ),
    CardReviewAction(
      lane: CardReviewLane.benefit,
      operation: CardReviewOperation.quarantine,
      targetId: identityId,
      observedUpdatedAt: observed,
    ),
    CardReviewAction(
      lane: CardReviewLane.benefit,
      operation: CardReviewOperation.retry,
      targetId: identityId,
      observedUpdatedAt: observed,
      payload: const {
        'decisions': [
          {'action': 'approve'},
        ],
      },
    ),
    CardReviewAction(
      lane: CardReviewLane.benefit,
      operation: CardReviewOperation.approve,
      targetId: identityId,
      observedUpdatedAt: observed,
      stagingId: stagingId,
      payload: const {
        'decisions': [
          {'action': 'approve', 'raw_provider_response': 'forbidden'},
        ],
      },
    ),
    CardReviewAction(
      lane: CardReviewLane.benefit,
      operation: CardReviewOperation.approve,
      targetId: identityId,
      observedUpdatedAt: observed,
      stagingId: stagingId,
      payload: const {
        'decisions': [
          {
            'action': 'approve',
            'benefit': {'raw_body': 'forbidden'},
          },
        ],
      },
    ),
  ];

  for (var index = 0; index < invalidActions.length; index++) {
    test(
      'invalid lane action combination $index is rejected locally',
      () async {
        final api = RecordingAdminOperatorApi(
          const AdminOperatorResponse(200, {'result': {}}),
        );
        final repository = CardDataRepository(AdminOperatorRepository(api));
        expect(
          repository.act(invalidActions[index]),
          throwsA(
            isA<AdminRequestFailed>().having(
              (error) => error.message,
              'message',
              'invalid_request',
            ),
          ),
        );
        expect(api.bodies, isEmpty);
      },
    );
  }

  test('actions deeply copy and freeze nested JSON payloads', () {
    final nested = <String, dynamic>{
      'proposed_fields': <String, dynamic>{
        'aliases': <dynamic>['Original'],
      },
    };
    final action = CardReviewAction(
      lane: CardReviewLane.identity,
      operation: CardReviewOperation.editApprove,
      targetId: identityId,
      observedUpdatedAt: observed,
      payload: nested,
    );
    (nested['proposed_fields'] as Map<String, dynamic>)['aliases'] = [
      'Changed',
    ];
    expect(
      ((action.payload['proposed_fields'] as Map)['aliases'] as List).single,
      'Original',
    );
    expect(
      () => (action.payload['proposed_fields'] as Map)['name'] = 'x',
      throwsUnsupportedError,
    );
    expect(
      () => ((action.payload['proposed_fields'] as Map)['aliases'] as List).add(
        'x',
      ),
      throwsUnsupportedError,
    );
  });

  test('parsed DTO maps deeply copy and freeze decoder data', () async {
    final proposed = <String, dynamic>{
      'metadata': <String, dynamic>{
        'aliases': <dynamic>['Original'],
      },
    };
    final api = RecordingAdminOperatorApi(
      AdminOperatorResponse(200, {
        'lane': 'identity',
        'items': [
          {
            'id': identityId,
            'status': 'pending',
            'updated_at': observed,
            'proposed_fields': proposed,
            'source_evidence': <String, dynamic>{},
          },
        ],
        'page': 1,
        'limit': 25,
        'has_more': false,
      }),
    );
    final item = (await CardDataRepository(
      AdminOperatorRepository(api),
    ).list(CardReviewLane.identity)).items.single;
    (proposed['metadata'] as Map<String, dynamic>)['aliases'] = ['Changed'];
    expect(
      ((item.proposedFields['metadata'] as Map)['aliases'] as List).single,
      'Original',
    );
    expect(
      () => ((item.proposedFields['metadata'] as Map)['aliases'] as List).add(
        'x',
      ),
      throwsUnsupportedError,
    );
  });

  test('actions reject non-JSON nested values safely', () {
    expect(
      () => CardReviewAction(
        lane: CardReviewLane.identity,
        operation: CardReviewOperation.editApprove,
        targetId: identityId,
        observedUpdatedAt: observed,
        payload: {
          'proposed_fields': {'bad': DateTime.now()},
        },
      ),
      throwsFormatException,
    );
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
