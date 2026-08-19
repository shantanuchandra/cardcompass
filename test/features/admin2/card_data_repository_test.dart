import 'dart:convert';

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

Map<String, dynamic> benefitPayloadWithUtf8Bytes(int targetBytes) {
  final decisions = List.generate(
    20,
    (_) => <String, dynamic>{
      'action': 'approve',
      'benefit': <String, dynamic>{'description': ''},
    },
  );
  final payload = <String, dynamic>{'decisions': decisions};
  var remaining = targetBytes - utf8.encode(jsonEncode(payload)).length;
  if (remaining < 0 || remaining > 20 * 2000) {
    throw ArgumentError.value(targetBytes, 'targetBytes');
  }
  for (final decision in decisions) {
    final length = remaining.clamp(0, 2000);
    (decision['benefit'] as Map<String, dynamic>)['description'] = 'a' * length;
    remaining -= length;
  }
  assert(remaining == 0);
  assert(utf8.encode(jsonEncode(payload)).length == targetBytes);
  return payload;
}

void main() {
  const identityId = '22222222-2222-4222-8222-222222222222';
  const stagingId = '33333333-3333-4333-8333-333333333333';
  const observed = '2026-08-19T09:00:00Z';

  test('maps decision-critical identity candidates and benefit diffs', () {
    final identity = CardReviewItem.fromJson(CardReviewLane.identity, {
      'id': identityId,
      'status': 'pending',
      'updated_at': observed,
      'proposed_fields': {'card_name': 'New name'},
      'source_evidence': {},
      'existing_candidates': [
        {'id': identityId, 'bank': 'Issuer', 'card_name': 'Current name'},
      ],
    });
    expect(identity.identityCandidates.single.cardName, 'Current name');

    final benefit = CardReviewItem.fromJson(CardReviewLane.benefit, {
      'id': identityId,
      'status': 'review_required',
      'updated_at': observed,
      'staging_id': stagingId,
      'card': {'bank': 'Issuer', 'card_name': 'Premier'},
      'staging': {
        'id': stagingId,
        'source_evidence': [],
        'extracted_data': {
          'retrieved_at': observed,
          'diff': {
            'additions': [
              {'dedupeKey': 'lounge', 'title': 'Lounge access'},
            ],
            'modifications': [
              {
                'current': {'dedupeKey': 'dining', 'rate': 5},
                'proposed': {'dedupeKey': 'dining', 'rate': 10},
              },
            ],
            'possibleRemovals': [],
            'unchanged': [],
            'conflicts': [],
          },
        },
      },
    });
    expect(benefit.benefitProposals, hasLength(2));
    expect(benefit.benefitProposals.last.current['rate'], 5);
    expect(benefit.benefitProposals.last.proposed['rate'], 10);
    expect(benefit.retrievedAt, DateTime.parse(observed));
  });

  test('exact target list request is deterministic', () async {
    final api = RecordingAdminOperatorApi(
      const AdminOperatorResponse(200, {
        'lane': 'identity',
        'items': [],
        'page': 1,
        'limit': 1,
        'has_more': false,
      }),
    );
    await CardDataRepository(
      AdminOperatorRepository(api),
    ).list(CardReviewLane.identity, targetId: identityId);
    expect(api.bodies.single['target_id'], identityId);
    expect(api.bodies.single['page'], 1);
    expect(api.bodies.single['limit'], 1);
  });

  test('invalid exact target is rejected before invocation', () async {
    final api = RecordingAdminOperatorApi(
      const AdminOperatorResponse(200, {'unused': true}),
    );
    await expectLater(
      CardDataRepository(
        AdminOperatorRepository(api),
      ).list(CardReviewLane.identity, targetId: 'not-an-id'),
      throwsA(isA<AdminRequestFailed>()),
    );
    expect(api.bodies, isEmpty);
  });

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

  test('benefit DTO surfaces validation evidence and recovery context', () {
    final item = CardReviewItem.fromJson(CardReviewLane.benefit, {
      'id': identityId,
      'status': 'failed',
      'updated_at': observed,
      'attempt_count': 3,
      'failure_category': 'source_timeout',
      'next_retry_at': '2026-08-19T10:00:00Z',
      'staging': {
        'calculated_confidence': 0.73,
        'validation_reasons': [
          {'code': 'missing_identity'},
        ],
        'validation_warnings': [
          {'code': 'stale_source'},
        ],
        'source_evidence': [
          {
            'source_excerpt': 'Official terms',
            'field_evidence': {'title': 'Issuer terms title'},
          },
        ],
        'benefit_decisions': [
          {'action': 'reject', 'dedupe_key': 'dining', 'reason': 'unsupported'},
        ],
      },
    });
    expect(item.confidence, 0.73);
    expect(item.validationReasonCodes, ['missing_identity']);
    expect(item.warningCodes, ['stale_source']);
    expect(item.evidence.single.excerpt, 'Official terms');
    expect(item.evidence.single.fieldEvidence['title'], 'Issuer terms title');
    expect(item.attemptCount, 3);
    expect(item.failureCategory, 'source_timeout');
    expect(item.nextRetryAt, DateTime.parse('2026-08-19T10:00:00Z'));
    expect(item.priorDecisionSummaries.single, contains('unsupported'));
  });

  test(
    'production BOGO, cashback, points, and milestone proposals round-trip without loss',
    () async {
      const proposals = [
        {
          'dedupe_key': 'bogo',
          'title': 'Buy 1 get 1',
          'benefit_category': 'entertainment',
          'benefit_type': 'bogo',
          'value_config': {
            'category': 'movie_tickets',
            'discount_type': 'bogo',
            'max_discount_per_transaction': 500,
            'max_usage_per_period': 2,
            'usage_period': 'quarter',
          },
          'partners': ['BookMyShow'],
          'exclusions': ['convenience fees'],
        },
        {
          'dedupe_key': 'points',
          'title': '5 reward points',
          'benefit_category': 'rewards',
          'benefit_type': 'reward_points',
          'value_config': {
            'value': 5,
            'threshold': 100,
            'restrictions': ['dining'],
          },
          'exclusions': ['fuel', 'emi transactions'],
        },
        {
          'dedupe_key': 'cashback',
          'title': '5% cashback',
          'benefit_category': 'cashback',
          'benefit_type': 'cashback',
          'value_config': {
            'rate': 5,
            'cap': 750,
            'period': 'month',
            'restrictions': ['online groceries'],
          },
          'exclusions': ['wallet reloads'],
        },
        {
          'dedupe_key': 'milestone',
          'title': 'Movie milestone',
          'benefit_category': 'entertainment',
          'benefit_type': 'milestone',
          'value_config': {
            'category': 'movie_tickets',
            'milestone_type': 'monthly',
            'threshold_amount': 50000,
            'reward_value': 400,
          },
          'exclusions': <String>[],
        },
      ];
      final item = CardReviewItem.fromJson(CardReviewLane.benefit, {
        'id': identityId,
        'status': 'staged',
        'updated_at': observed,
        'staging_id': stagingId,
        'staging': {
          'source_evidence': [],
          'extracted_data': {
            'diff': {'additions': proposals},
          },
        },
      });
      final decisions = item.benefitProposals
          .map((proposal) => proposal.decision('approve'))
          .toList();
      expect(decisions.map((value) => value['proposed']), proposals);
      final api = RecordingAdminOperatorApi(
        const AdminOperatorResponse(200, {'result': {}}),
      );
      await CardDataRepository(
        AdminOperatorRepository(api),
        requestIds: () => '11111111-1111-4111-8111-111111111111',
      ).act(
        CardReviewAction(
          lane: CardReviewLane.benefit,
          operation: CardReviewOperation.approve,
          targetId: identityId,
          observedUpdatedAt: observed,
          stagingId: stagingId,
          payload: {'decisions': decisions},
        ),
      );
      expect(api.bodies.single['decisions'], decisions);
    },
  );

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

  Map<String, dynamic> wholeRequest(Map<String, dynamic> payload) => {
    'action': 'card-review-action',
    'lane': 'benefit',
    'operation': 'approve',
    'target_id': identityId,
    'request_id': '11111111-1111-4111-8111-111111111111',
    'observed_updated_at': observed,
    'staging_id': stagingId,
    ...payload,
  };

  Map<String, dynamic> payloadForWholeRequestBytes(int bytes) {
    final seed = benefitPayloadWithUtf8Bytes(2000);
    final overhead = utf8.encode(jsonEncode(wholeRequest(seed))).length - 2000;
    return benefitPayloadWithUtf8Bytes(bytes - overhead);
  }

  for (final bytes in [32767, 32768]) {
    test(
      'accepts a whole gateway request of exactly $bytes UTF-8 bytes',
      () async {
        final payload = payloadForWholeRequestBytes(bytes);
        final api = RecordingAdminOperatorApi(
          const AdminOperatorResponse(200, {'result': {}}),
        );
        await CardDataRepository(
          AdminOperatorRepository(api),
          requestIds: () => '11111111-1111-4111-8111-111111111111',
        ).act(
          CardReviewAction(
            lane: CardReviewLane.benefit,
            operation: CardReviewOperation.approve,
            targetId: identityId,
            observedUpdatedAt: observed,
            stagingId: stagingId,
            payload: payload,
          ),
        );
        expect(utf8.encode(jsonEncode(wholeRequest(payload))).length, bytes);
        expect(api.bodies, hasLength(1));
      },
    );
  }

  test('rejects a 32769-byte whole request with multibyte content', () {
    final payload = payloadForWholeRequestBytes(32768);
    final decisions = payload['decisions'] as List<dynamic>;
    final populated = decisions.cast<Map<String, dynamic>>().firstWhere(
      (decision) =>
          ((decision['benefit'] as Map<String, dynamic>)['description']
                  as String)
              .isNotEmpty,
    );
    final benefit = populated['benefit'] as Map<String, dynamic>;
    final ascii = benefit['description'] as String;
    benefit['description'] = '${ascii.substring(0, ascii.length - 1)}é';
    expect(utf8.encode(jsonEncode(wholeRequest(payload))).length, 32769);
    final action = CardReviewAction(
      lane: CardReviewLane.benefit,
      operation: CardReviewOperation.approve,
      targetId: identityId,
      observedUpdatedAt: observed,
      stagingId: stagingId,
      payload: payload,
    );
    final api = RecordingAdminOperatorApi(
      const AdminOperatorResponse(200, {'result': {}}),
    );
    expect(
      CardDataRepository(AdminOperatorRepository(api)).act(action),
      throwsA(isA<AdminRequestFailed>()),
    );
    expect(api.bodies, isEmpty);
  });

  test('caps the normalized reject payload after reason injection', () {
    final payload = benefitPayloadWithUtf8Bytes(32768);
    for (final decision in payload['decisions'] as List<dynamic>) {
      (decision as Map<String, dynamic>)['action'] = 'reject';
    }
    expect(utf8.encode(jsonEncode(payload)).length, lessThanOrEqualTo(32768));
    final api = RecordingAdminOperatorApi(
      const AdminOperatorResponse(200, {'result': {}}),
    );
    expect(
      CardDataRepository(AdminOperatorRepository(api)).act(
        CardReviewAction(
          lane: CardReviewLane.benefit,
          operation: CardReviewOperation.reject,
          targetId: identityId,
          observedUpdatedAt: observed,
          stagingId: stagingId,
          reason: 'r' * 1000,
          payload: payload,
        ),
      ),
      throwsA(isA<AdminRequestFailed>()),
    );
    expect(api.bodies, isEmpty);
  });

  test('enforces timestamp, identity text, and reason boundaries', () async {
    final api = RecordingAdminOperatorApi(
      const AdminOperatorResponse(200, {'result': {}}),
    );
    final repository = CardDataRepository(
      AdminOperatorRepository(api),
      requestIds: () => '11111111-1111-4111-8111-111111111111',
    );
    CardReviewAction edit(String name, {String timestamp = observed}) =>
        CardReviewAction(
          lane: CardReviewLane.identity,
          operation: CardReviewOperation.editApprove,
          targetId: identityId,
          observedUpdatedAt: timestamp,
          payload: {
            'proposed_fields': {'card_name': name},
          },
        );

    await repository.act(edit('x' * 500));
    await repository.act(
      CardReviewAction(
        lane: CardReviewLane.identity,
        operation: CardReviewOperation.reject,
        targetId: identityId,
        observedUpdatedAt: observed,
        reason: 'r' * 1000,
      ),
    );
    expect(repository.act(edit('x' * 501)), throwsA(isA<AdminRequestFailed>()));
    final longButParseableTimestamp = '2026-08-19T09:00:00.${'1' * 80}Z';
    expect(longButParseableTimestamp.length, greaterThan(100));
    expect(DateTime.tryParse(longButParseableTimestamp), isNotNull);
    expect(
      repository.act(edit('x', timestamp: longButParseableTimestamp)),
      throwsA(isA<AdminRequestFailed>()),
    );
    expect(
      repository.act(
        CardReviewAction(
          lane: CardReviewLane.identity,
          operation: CardReviewOperation.reject,
          targetId: identityId,
          observedUpdatedAt: observed,
          reason: 'r' * 1001,
        ),
      ),
      throwsA(isA<AdminRequestFailed>()),
    );
    expect(api.bodies, hasLength(2));
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
