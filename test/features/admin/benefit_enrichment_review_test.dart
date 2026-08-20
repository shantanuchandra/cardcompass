import 'package:cardcompass/features/admin/data/admin_catalog_repository.dart';
import 'package:cardcompass/features/admin/models/benefit_enrichment_review.dart';
import 'package:cardcompass/features/admin/screens/card_catalog_review_screen.dart';
import 'package:cardcompass/features/admin/widgets/benefit_enrichment_review_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

const _jobJson = <String, dynamic>{
  'id': 'job-1',
  'card_id': 'card-1',
  'issuer': 'Horizon Bank',
  'canonical_url': 'https://issuer.example/cards/astra',
  'parser_version': 'benefits-v1',
  'status': 'staged',
  'run_mode': 'scheduled',
  'attempt_count': 2,
  'staging_id': 'staging-1',
  'crawler_discovered_without_statement_signal': true,
  'normalized_fields': {'proposed_count': 1},
  'result_summary': {
    'run_id': 'run-1',
    'additions': 1,
    'evidence_passed': true,
  },
  'card': {'id': 'card-1', 'bank': 'Horizon Bank', 'card_name': 'Astra Travel'},
  'staging': {
    'id': 'staging-1',
    'status': 'pending',
    'source_url': 'https://issuer.example/cards/astra',
    'calculated_confidence': 0.92,
    'validation_warnings': [],
    'source_evidence': [
      {
        'dedupe_key': 'dining-credit',
        'source_url': 'https://issuer.example/terms',
        'source_excerpt': 'Receive a ₹500 dining credit every month.',
        'evidence': {'title': '₹500 dining credit'},
      },
    ],
    'extracted_data': {
      'parser_version': 'benefits-v1',
      'diff': {
        'additions': [
          {
            'dedupeKey': 'dining-credit',
            'title': 'Dining credit',
            'description': '₹500 every month',
            'category': 'dining',
            'confidence': {'title': 0.92},
            'evidence': {'title': '₹500 dining credit'},
            'warnings': ['crawler_discovered'],
          },
        ],
        'modifications': [
          {
            'current': {'title': 'Old dining credit', 'value': '300'},
            'proposed': {'title': 'Dining credit', 'value': '500'},
          },
        ],
      },
    },
    'benefit_decisions': [
      {
        'action': 'approve',
        'benefit': {'title': 'Dining credit'},
      },
    ],
  },
};

final _v6JobJson = <String, dynamic>{
  ..._jobJson,
  'parser_version': 'benefits-v6',
  'crawler_discovered_without_statement_signal': false,
  'staging': {
    ...(_jobJson['staging'] as Map<String, dynamic>),
    'card_id': 'card-1',
    'parser_version': 'benefits-v6',
    'source_evidence': [
      {
        'dedupe_key': 'card-benefit-v2:card-1:${'a' * 64}',
        'offer_subject': 'dining-points',
        'source_identity': 'd' * 64,
        'source_identities': ['d' * 64, 'e' * 64],
        'source_url': 'https://issuer.example/cards/astra',
        'source_excerpt': 'Earn 10 dining points per ₹100.',
        'content_hash': 'f' * 64,
        'evidence': {'rate': '10 dining points'},
      },
    ],
    'benefit_decisions': [
      {
        'action': 'approve',
        'change_type': 'identity_migration',
        'dedupe_key': 'card-benefit-v2:card-1:${'a' * 64}',
        'benefit_id': '11111111-1111-4111-8111-111111111111',
        'proposed': {
          'benefitId': 'card-benefit-v2:card-1:${'a' * 64}',
          'dedupeKey': 'card-benefit-v2:card-1:${'a' * 64}',
          'conditionHash': 'a' * 64,
          'title': 'Dining points',
          'description': '10 points per ₹100',
          'valueConfig': {'rate': 10, 'period': 'transaction'},
        },
      },
    ],
    'extracted_data': {
      'parser_version': 'benefits-v6',
      'retrieved_at': '2026-08-20T10:11:12.123456Z',
      'crawl_observation': {
        'observed_at': '2026-08-20T10:11:12.123456Z',
        'crawl_complete': false,
        'crawl_reason': 'required_source_failed',
        'source_attempts': [
          {
            'url': 'https://issuer.example/cards/astra',
            'role': 'primary',
            'status': 'success',
            'httpStatus': 200,
            'attemptedAt': '2026-08-20T10:11:12.123456Z',
          },
          {
            'url': 'https://issuer.example/cards/astra/terms',
            'role': 'required_supporting',
            'status': 'failed',
            'httpStatus': 503,
            'errorCode': 'http_5xx',
            'attemptedAt': '2026-08-20T10:11:13.123456Z',
          },
        ],
      },
      'diff': {
        'modifications': [
          {
            'changeType': 'identity_migration',
            'current': {
              'liveBenefitId': '11111111-1111-4111-8111-111111111111',
              'benefitId': 'card-benefit-v2:card-1:${'b' * 64}',
              'dedupeKey': 'card-benefit-v2:card-1:${'b' * 64}',
              'conditionHash': 'b' * 64,
              'title': 'Dining points',
              'rate': 5,
            },
            'proposed': {
              'benefitId': 'card-benefit-v2:card-1:${'a' * 64}',
              'dedupeKey': 'card-benefit-v2:card-1:${'a' * 64}',
              'conditionHash': 'a' * 64,
              'title': 'Dining points',
              'rate': 10,
            },
          },
        ],
        'possibleRemovals': [
          {
            'benefit': {
              'liveBenefitId': '22222222-2222-4222-8222-222222222222',
              'benefitId': 'card-benefit-v2:card-1:${'c' * 64}',
              'dedupeKey': 'legacy:approved:lounge-visit',
              'title': 'Legacy lounge visit',
            },
            'informational': true,
            'retirementEligible': true,
            'retirementReason': 'two_complete_observations',
            'completeAbsenceObservedAt': [
              '2026-08-12T00:00:00Z',
              '2026-08-20T00:00:00Z',
            ],
          },
        ],
      },
    },
  },
};

Map<String, dynamic> get _stagingOnlyV6Corruption => <String, dynamic>{
  ..._jobJson,
  'staging': {
    ...(_jobJson['staging'] as Map<String, dynamic>),
    'card_id': 'card-1',
    'parser_version': 'benefits-v6',
  },
};

Map<String, dynamic> _v6AdditionWithIdentity({
  required String benefitId,
  required String conditionHash,
}) => <String, dynamic>{
  ..._v6JobJson,
  'staging': {
    ...(_v6JobJson['staging'] as Map<String, dynamic>),
    'benefit_decisions': const [],
    'extracted_data': {
      ...((_v6JobJson['staging'] as Map<String, dynamic>)['extracted_data']
          as Map<String, dynamic>),
      'diff': {
        'additions': [
          {
            'benefitId': benefitId,
            'dedupeKey': benefitId,
            'conditionHash': conditionHash,
            'title': 'Canonical test proposal',
          },
        ],
      },
    },
  },
};

void _noop() {}
void _noopValue(String _) {}

BenefitEnrichmentReviewPage _page() =>
    BenefitEnrichmentReviewPage.fromJson(const {
      'counts': {
        'total': 3,
        'by_status': {'staged': 1, 'completed': 1, 'failed': 1},
        'by_run_mode': {'scheduled': 2, 'pilot': 1},
      },
      'movie_mapping_health': [
        {'metric': 'active_movie_benefits', 'value': 49},
        {'metric': 'mapped_active_movie_benefits', 'value': 8},
        {'metric': 'orphaned_active_movie_benefits', 'value': 41},
      ],
      'page': 1,
      'limit': 25,
      'has_more': false,
    }).copyWith(items: [BenefitEnrichmentReview.fromJson(_jobJson)]);

class _FakeApi implements AdminCatalogEntryApi {
  _FakeApi(this.response, {this.error});

  AdminCatalogEntryResponse response;
  Object? error;
  final bodies = <Map<String, dynamic>>[];

  @override
  Future<AdminCatalogEntryResponse> invoke(Map<String, dynamic> body) async {
    bodies.add(body);
    if (error != null) throw error!;
    return response;
  }
}

class _FakeRepository implements BenefitEnrichmentRepository {
  _FakeRepository(this.page, {this.error});

  final BenefitEnrichmentReviewPage page;
  final Object? error;
  final actions = <String>[];
  String? retirementReason;
  String? retiredBenefitId;

  @override
  Future<BenefitEnrichmentReviewPage> loadReviewPage({
    int page = 1,
    int limit = 25,
    String? status,
  }) async {
    if (error != null) throw error!;
    return this.page;
  }

  @override
  Future<void> approve(BenefitEnrichmentReview item) async =>
      actions.add('approve');

  @override
  Future<void> editApprove(
    BenefitEnrichmentReview item,
    List<BenefitReviewDecision> decisions,
  ) async => actions.add('edit-approve');

  @override
  Future<void> reject(BenefitEnrichmentReview item, String reason) async =>
      actions.add('reject');

  @override
  Future<void> retry(BenefitEnrichmentReview item) async =>
      actions.add('retry');

  @override
  Future<void> quarantine(BenefitEnrichmentReview item, String reason) async =>
      actions.add('quarantine');

  @override
  Future<void> unquarantine(BenefitEnrichmentReview item) async =>
      actions.add('unquarantine');

  @override
  Future<void> retire(
    BenefitEnrichmentReview item,
    BenefitPossibleRemoval removal,
    String reason,
  ) async {
    actions.add('retire');
    retirementReason = reason;
    retiredBenefitId = removal.benefit.liveBenefitId;
  }
}

Future<void> _pumpPanel(
  WidgetTester tester,
  BenefitEnrichmentRepository repository, {
  VoidCallback? onAuthorizationRequired,
  ValueChanged<Uri>? onOpenUrl,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: BenefitEnrichmentReviewPanel(
          repository: repository,
          onAuthorizationRequired: onAuthorizationRequired ?? () {},
          onOpenUrl: onOpenUrl ?? (_) {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('legacy and v6 review DTOs preserve server identity and evidence', () {
    expect(BenefitEnrichmentReview.fromJson(_jobJson).canReview, isTrue);

    final review = BenefitEnrichmentReview.fromJson(_v6JobJson);
    final modification = review.staging.extractedData.diff.modifications.single;
    final decision = review.staging.decisions.single;
    final edited = decision.withEditedBenefit(
      decision.proposed!.copyWith(description: 'Reviewed wording'),
    );

    expect(
      review.staging.extractedData.retrievedAt,
      '2026-08-20T10:11:12.123456Z',
    );
    expect(review.staging.extractedData.crawl.complete, isFalse);
    expect(review.staging.extractedData.crawl.reason, 'required_source_failed');
    expect(review.staging.cardId, 'card-1');
    expect(review.staging.parserVersion, 'benefits-v6');
    expect(review.staging.extractedData.crawl.sourceAttempts, hasLength(2));
    expect(review.staging.sourceEvidence.single.offerSubject, 'dining-points');
    expect(review.staging.sourceEvidence.single.sourceIdentities, hasLength(2));
    expect(review.staging.sourceEvidence.single.contentHash, 'f' * 64);
    expect(modification.changeType, 'identity_migration');
    expect(
      modification.proposed.benefitId,
      'card-benefit-v2:card-1:${'a' * 64}',
    );
    expect(modification.proposed.conditionHash, 'a' * 64);
    expect(edited.changeType, decision.changeType);
    expect(edited.liveBenefitId, decision.liveBenefitId);
    expect(edited.dedupeKey, decision.dedupeKey);
    expect(edited.toJson()['benefit_id'], decision.liveBenefitId);
    expect(
      (edited.toJson()['edited_benefit'] as Map)['benefitId'],
      'card-benefit-v2:card-1:${'a' * 64}',
    );
  });

  test(
    'v6 accepts production current and legacy live rows while validating proposed identity',
    () {
      final productionShape = <String, dynamic>{
        ..._v6JobJson,
        'staging': {
          ...(_v6JobJson['staging'] as Map<String, dynamic>),
          'extracted_data': {
            ...((_v6JobJson['staging']
                    as Map<String, dynamic>)['extracted_data']
                as Map<String, dynamic>),
            'diff': {
              'modifications': [
                {
                  'current': {
                    'liveBenefitId': '11111111-1111-4111-8111-111111111111',
                    'benefitId': 'card-benefit-v2:card-1:${'4' * 64}',
                    'dedupeKey': 'card-benefit-v2:card-1:${'4' * 64}',
                    'title': 'Approved dining benefit',
                    'parserVersion': 'current-approved-benefit',
                  },
                  'proposed': {
                    'benefitId': 'card-benefit-v2:card-1:${'1' * 64}',
                    'dedupeKey': 'card-benefit-v2:card-1:${'1' * 64}',
                    'conditionHash': '1' * 64,
                    'title': 'Updated dining benefit',
                  },
                },
              ],
              'unchanged': [
                {
                  'current': {
                    'liveBenefitId': '22222222-2222-4222-8222-222222222222',
                    'dedupeKey': 'legacy-lounge-benefit',
                    'title': 'Legacy lounge benefit',
                    'parserVersion': 'current-approved-benefit',
                  },
                  'proposed': {
                    'benefitId': 'card-benefit-v2:card-1:${'2' * 64}',
                    'dedupeKey': 'card-benefit-v2:card-1:${'2' * 64}',
                    'conditionHash': '2' * 64,
                    'title': 'Legacy lounge benefit',
                  },
                },
              ],
              'possibleRemovals': [
                {
                  'benefit': {
                    'liveBenefitId': '33333333-3333-4333-8333-333333333333',
                    'benefitId': 'card-benefit-v2:card-1:${'3' * 64}',
                    'dedupeKey': 'legacy-movie-benefit',
                    'title': 'Legacy movie benefit',
                    'parserVersion': 'current-approved-benefit',
                  },
                  'informational': true,
                  'retirementEligible': false,
                },
              ],
            },
          },
        },
      };

      final review = BenefitEnrichmentReview.fromJson(productionShape);
      final diff = review.staging.extractedData.diff;

      expect(diff.modifications.single.current.conditionHash, isNull);
      expect(
        diff.modifications.single.current.liveBenefitId,
        '11111111-1111-4111-8111-111111111111',
      );
      expect(diff.unchanged.single.current.benefitId, isNull);
      expect(diff.unchanged.single.current.dedupeKey, 'legacy-lounge-benefit');
      expect(
        diff.possibleRemovals.single.benefit.dedupeKey,
        'legacy-movie-benefit',
      );
      expect(
        diff.possibleRemovals.single.benefit.benefitId,
        'card-benefit-v2:card-1:${'3' * 64}',
      );
    },
  );

  test(
    'malformed required v6 identity fails closed while legacy remains readable',
    () {
      final malformed = <String, dynamic>{
        ..._v6JobJson,
        'staging': {
          ...(_v6JobJson['staging'] as Map<String, dynamic>),
          'extracted_data': {
            ...((_v6JobJson['staging']
                    as Map<String, dynamic>)['extracted_data']
                as Map<String, dynamic>),
            'diff': {
              'additions': [
                {'title': 'Missing identity'},
              ],
            },
          },
        },
      };

      expect(
        () => BenefitEnrichmentReview.fromJson(malformed),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => BenefitEnrichmentReview.fromJson({
          ..._v6JobJson,
          'staging': {
            ...(_v6JobJson['staging'] as Map<String, dynamic>),
            'extracted_data': {
              ...((_v6JobJson['staging']
                      as Map<String, dynamic>)['extracted_data']
                  as Map<String, dynamic>),
              'diff': {
                'possibleRemovals': [
                  {
                    'benefit': {
                      'dedupeKey': 'legacy-without-live-id',
                      'title': 'Structurally incomplete current benefit',
                    },
                  },
                ],
              },
            },
          },
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => BenefitEnrichmentReview.fromJson({
          ..._v6JobJson,
          'staging': {
            ...(_v6JobJson['staging'] as Map<String, dynamic>),
            'extracted_data': {
              ...((_v6JobJson['staging']
                      as Map<String, dynamic>)['extracted_data']
                  as Map<String, dynamic>),
              'diff': {
                'possibleRemovals': [
                  {
                    'benefit': {
                      'liveBenefitId': '33333333-3333-4333-8333-333333333333',
                      'benefitId': 'card-benefit-v2:different-card:${'3' * 64}',
                      'dedupeKey': 'legacy-movie-benefit',
                      'title': 'Malformed decorated legacy removal',
                    },
                  },
                ],
              },
            },
          },
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => BenefitEnrichmentReview.fromJson({
          ..._v6JobJson,
          'staging': {
            ...(_v6JobJson['staging'] as Map<String, dynamic>),
            'card_id': 'different-card',
          },
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => BenefitEnrichmentReview.fromJson(_stagingOnlyV6Corruption),
        throwsA(isA<FormatException>()),
      );
      expect(() => BenefitEnrichmentReview.fromJson(_jobJson), returnsNormally);
    },
  );

  test('v6 proposed identity is the exact review-card condition key', () {
    expect(
      () => BenefitEnrichmentReview.fromJson(
        _v6AdditionWithIdentity(
          benefitId: 'card-benefit-v2:card-1:${'d' * 64}',
          conditionHash: 'd' * 64,
        ),
      ),
      returnsNormally,
    );

    final malformed = [
      _v6AdditionWithIdentity(
        benefitId: 'card-benefit-v2:other-card:${'d' * 64}',
        conditionHash: 'd' * 64,
      ),
      _v6AdditionWithIdentity(
        benefitId: 'card-benefit-v2:card-1:${'e' * 64}',
        conditionHash: 'd' * 64,
      ),
      _v6AdditionWithIdentity(
        benefitId: 'benefit-v2:card-1:${'d' * 64}',
        conditionHash: 'd' * 64,
      ),
    ];
    for (final row in malformed) {
      expect(
        () => BenefitEnrichmentReview.fromJson(row),
        throwsA(isA<FormatException>()),
      );
    }
  });

  test('admin reauthorization clears the stale session before login', () async {
    final events = <String>[];

    await requestAdminReauthorization(
      clearSession: () async => events.add('session-cleared'),
      showLogin: () => events.add('login-shown'),
    );

    expect(events, ['session-cleared', 'login-shown']);
  });

  testWidgets(
    'admin review exposes card identity and benefit enrichment tabs',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: DefaultTabController(
            length: 2,
            child: Scaffold(appBar: AppBar(bottom: AdminCatalogReviewTabs())),
          ),
        ),
      );

      expect(find.text('Card identity'), findsOneWidget);
      expect(find.text('Benefit enrichment'), findsOneWidget);
      expect(find.byTooltip('About card identity review'), findsOneWidget);

      await tester.tap(find.byTooltip('About card identity review'));
      await tester.pumpAndSettle();

      expect(find.text('What this queue is for'), findsOneWidget);
      expect(find.text('Evidence'), findsOneWidget);
      expect(find.text('Confidence'), findsOneWidget);
      expect(find.text('Warnings'), findsOneWidget);
      expect(find.text('Approve as new card'), findsOneWidget);
      expect(find.text('Edit and approve'), findsOneWidget);
      expect(find.text('Merge with existing'), findsOneWidget);
      expect(find.text('Retry discovery'), findsOneWidget);
      expect(find.text('Reject proposal'), findsOneWidget);
    },
  );

  testWidgets(
    'issuer discovery quarantine exposes only retry or keep actions',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CatalogIdentityReviewCard(
              item: const {
                'status': 'pending',
                'proposed_fields': {
                  'issuer': 'Axis Bank',
                  'cardName': 'Issuer discovery quarantine',
                  'source_observation': {
                    'kind': 'issuer_discovery_quarantine',
                    'classification': 'issuer_discovery_quarantine',
                    'anchor_job_id': 'anchor-123',
                    'issuer': 'Axis Bank',
                    'reason': 'resume_attempts_exhausted',
                    'retryable': true,
                    'retryability_reason': 'attempt_budget_reset_allowed',
                    'public_evidence':
                        'Issuer directory retry budget exhausted.',
                  },
                },
                'validation_warnings': ['issuer_discovery_quarantine'],
                'existing_candidates': [],
                'card_discovery_jobs': {
                  'issuer': 'Axis Bank',
                  'evidence': {
                    'source_observation': {
                      'kind': 'issuer_discovery_quarantine',
                    },
                  },
                },
              },
              onApprove: _noop,
              onEditApprove: _noop,
              onMerge: _noopValue,
              onRetry: _noop,
              onReject: _noop,
            ),
          ),
        ),
      );

      expect(find.text('Issuer discovery quarantine'), findsOneWidget);
      expect(
        find.textContaining('Issuer directory retry budget exhausted'),
        findsOneWidget,
      );
      expect(find.textContaining('anchor-123'), findsNothing);
      expect(find.text('Retry issuer discovery'), findsOneWidget);
      expect(find.text('Keep quarantined'), findsOneWidget);
      expect(find.text('Approve as new card'), findsNothing);
      expect(find.text('Edit and approve'), findsNothing);
      expect(find.textContaining('lease_token'), findsNothing);
    },
  );

  testWidgets(
    'catalog review never renders statement identifiers or customer prose',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CatalogIdentityReviewCard(
              item: const {
                'status': 'pending',
                'proposed_fields': {
                  'issuer': 'Horizon Bank',
                  'cardName': 'Astra Reserve',
                },
                'card_discovery_jobs': {
                  'issuer': 'Horizon Bank',
                  'proposed_product': 'Astra Reserve',
                  'evidence': {
                    'subject_product': 'Astra Reserve',
                    'last_four': '4242',
                    'pdf_header_excerpt':
                        'PRIYA SHARMA · card ending 4242 · private statement',
                    'customer_name': 'PRIYA SHARMA',
                  },
                },
              },
              onApprove: _noop,
              onEditApprove: _noop,
              onMerge: _noopValue,
              onRetry: _noop,
              onReject: _noop,
            ),
          ),
        ),
      );

      expect(find.textContaining('4242'), findsNothing);
      expect(find.textContaining('PRIYA SHARMA'), findsNothing);
      expect(find.textContaining('private statement'), findsNothing);
      expect(find.textContaining('Astra Reserve'), findsWidgets);
    },
  );

  testWidgets(
    'catalog lifecycle review shows before-after evidence and explicit action only for strong evidence',
    (tester) async {
      var discontinued = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CatalogIdentityReviewCard(
              item: const {
                'id': 'review-lifecycle',
                'status': 'pending',
                'proposed_fields': {
                  'cardName': 'Astra Reserve',
                  'network': 'Visa Infinite',
                  'joining_fee': 5000,
                  'apr': 42,
                  'official_url': 'https://issuer.example/astra-reserve',
                  'suggested_action': 'mark_discontinued',
                  'catalog_baseline': {
                    'card_name': 'Astra',
                    'network': 'Visa Signature',
                    'joining_fee': 3000,
                    'annual_fee': 3000,
                    'apr': 40,
                    'card_url': 'https://issuer.example/astra',
                    'is_discontinued': false,
                  },
                  'source_observation': {
                    'kind': 'strong_explicit_discontinuation',
                    'source_status': 200,
                    'identity_validated': true,
                    'explicit_discontinuation': true,
                    'retrieved_at': '2026-08-20T12:00:00.123456Z',
                    'matched_excerpt':
                        'Astra Reserve credit card has been discontinued.',
                  },
                },
                'source_evidence': {
                  'target_excerpt':
                      'Astra Reserve credit card has been discontinued.',
                },
                'card_discovery_jobs': {
                  'issuer': 'Horizon Bank',
                  'proposed_product': 'Astra Reserve',
                  'evidence': {},
                },
              },
              onApprove: _noop,
              onEditApprove: _noop,
              onMerge: _noopValue,
              onRetry: _noop,
              onReject: _noop,
              onMarkDiscontinued: () => discontinued = true,
              onReactivate: _noop,
            ),
          ),
        ),
      );

      expect(find.textContaining('Astra → Astra Reserve'), findsOneWidget);
      expect(
        find.textContaining('Visa Signature → Visa Infinite'),
        findsOneWidget,
      );
      expect(find.textContaining('3000 → 5000'), findsOneWidget);
      expect(
        find.textContaining('Annual fee: 3000 → No proposal'),
        findsOneWidget,
      );
      expect(find.textContaining('40 → 42'), findsOneWidget);
      expect(
        find.textContaining(
          'issuer.example/astra → https://issuer.example/astra-reserve',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('Astra Reserve credit card has been discontinued'),
        findsOneWidget,
      );
      expect(
        find.textContaining('2026-08-20T12:00:00.123456Z'),
        findsOneWidget,
      );
      expect(find.text('Mark discontinued'), findsOneWidget);
      expect(find.text('Reactivate'), findsNothing);

      await tester.tap(find.text('Mark discontinued'));
      expect(discontinued, isTrue);
    },
  );

  testWidgets('raw status alone never exposes a card lifecycle mutation', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CatalogIdentityReviewCard(
            item: const {
              'status': 'pending',
              'proposed_fields': {
                'suggested_action': 'mark_discontinued',
                'catalog_baseline': {
                  'card_name': 'Astra',
                  'is_discontinued': false,
                },
                'source_observation': {
                  'kind': 'raw_fetch_error',
                  'source_status': 410,
                  'identity_validated': false,
                },
              },
            },
            onApprove: _noop,
            onEditApprove: _noop,
            onMerge: _noopValue,
            onRetry: _noop,
            onReject: _noop,
            onMarkDiscontinued: _noop,
            onReactivate: _noop,
          ),
        ),
      ),
    );

    expect(find.text('Mark discontinued'), findsNothing);
    expect(find.text('Reactivate'), findsNothing);
  });

  testWidgets('reviewed exact reappearance exposes Reactivate, not Retire', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CatalogIdentityReviewCard(
            item: const {
              'status': 'pending',
              'proposed_fields': {
                'suggested_action': 'reactivate',
                'catalog_baseline': {
                  'card_name': 'Astra',
                  'is_discontinued': true,
                },
                'source_observation': {
                  'kind': 'exact_card_reappearance',
                  'source_status': 200,
                  'identity_validated': true,
                  'explicit_discontinuation': false,
                  'matched_excerpt': 'Apply for the Astra card.',
                },
              },
            },
            onApprove: _noop,
            onEditApprove: _noop,
            onMerge: _noopValue,
            onRetry: _noop,
            onReject: _noop,
            onMarkDiscontinued: _noop,
            onReactivate: _noop,
          ),
        ),
      ),
    );

    expect(find.text('Reactivate'), findsOneWidget);
    expect(find.text('Mark discontinued'), findsNothing);
  });

  testWidgets(
    'nonretryable issuer quarantine explains manual repair and hides Retry',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CatalogIdentityReviewCard(
              item: const {
                'status': 'pending',
                'proposed_fields': {
                  'source_observation': {
                    'kind': 'issuer_discovery_quarantine',
                    'classification': 'issuer_discovery_quarantine',
                    'anchor_job_id': 'anchor-corrupt',
                    'issuer': 'Axis Bank',
                    'reason': 'anchor_identity_conflict',
                    'retryable': false,
                    'retryability_reason': 'manual_repair_required',
                  },
                },
              },
              onApprove: _noop,
              onEditApprove: _noop,
              onMerge: _noopValue,
              onRetry: _noop,
              onReject: _noop,
            ),
          ),
        ),
      );

      expect(find.text('Retry issuer discovery'), findsNothing);
      expect(find.text('Keep quarantined'), findsOneWidget);
      expect(find.textContaining('Manual repair required'), findsOneWidget);
    },
  );

  testWidgets(
    'identity loader explicitly merges newest quarantine beyond one hundred older reviews',
    (tester) async {
      final calls = <Map<String, dynamic>>[];
      final older = List.generate(
        100,
        (index) => <String, dynamic>{
          'id': 'older-$index',
          'status': 'pending',
          'proposed_fields': const {'cardName': 'Older review'},
        },
      );
      final newest = <String, dynamic>{
        'id': 'newest-quarantine',
        'status': 'pending',
        'proposed_fields': const {
          'source_observation': {
            'kind': 'issuer_discovery_quarantine',
            'classification': 'issuer_discovery_quarantine',
            'anchor_job_id': 'anchor-newest',
            'issuer': 'Axis Bank',
            'reason': 'resume_attempts_exhausted',
            'retryable': true,
            'retryability_reason': 'attempt_budget_reset_allowed',
          },
        },
      };
      final items = await loadCatalogIdentityReviewItems(
        status: 'pending',
        invoke: (body) async {
          calls.add(Map<String, dynamic>.from(body));
          return body['action'] == 'issuer-quarantine-list'
              ? {
                  'items': [newest],
                  'next_cursor': null,
                }
              : {'items': older};
        },
      );

      expect(calls.map((call) => call['action']), [
        'list',
        'issuer-quarantine-list',
      ]);
      expect(items.length, 101);
      expect(items.first['id'], 'newest-quarantine');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CatalogIdentityReviewCard(
              item: items.first,
              onApprove: _noop,
              onEditApprove: _noop,
              onMerge: _noopValue,
              onRetry: _noop,
              onReject: _noop,
            ),
          ),
        ),
      );
      expect(find.text('Issuer discovery quarantine'), findsOneWidget);
      expect(find.text('Retry issuer discovery'), findsOneWidget);
      expect(find.text('Keep quarantined'), findsOneWidget);
    },
  );

  test(
    'identity loader consumes every quarantine page and dedupes boundaries',
    () async {
      final calls = <Map<String, dynamic>>[];
      final items = await loadCatalogIdentityReviewItems(
        status: 'pending',
        invoke: (body) async {
          calls.add(Map<String, dynamic>.from(body));
          if (body['action'] == 'list') {
            return {
              'items': [
                {'id': 'general-1'},
                {'id': 'q-2'},
              ],
            };
          }
          if (body['cursor'] == null) {
            return {
              'items': [
                {'id': 'q-1'},
                {'id': 'q-2'},
              ],
              'has_more': true,
              'next_cursor': 'cursor-2',
            };
          }
          return {
            'items': [
              {'id': 'q-2'},
              {'id': 'q-3'},
            ],
            'has_more': false,
            'next_cursor': null,
          };
        },
      );

      expect(
        calls.where((call) => call['action'] == 'issuer-quarantine-list'),
        hasLength(2),
      );
      expect(items.map((item) => item['id']), [
        'q-1',
        'q-2',
        'q-3',
        'general-1',
      ]);
    },
  );

  test(
    'identity loader reports bounded truncation instead of returning partial work',
    () async {
      expect(
        () => loadCatalogIdentityReviewItems(
          status: 'pending',
          maxQuarantinePages: 2,
          invoke: (body) async => body['action'] == 'list'
              ? {'items': const []}
              : {
                  'items': [
                    {'id': 'q-${body['cursor'] ?? 'first'}'},
                  ],
                  'has_more': true,
                  'next_cursor': '${body['cursor'] ?? ''}x',
                },
        ),
        throwsA(
          isA<AdminCatalogRequestFailed>().having(
            (error) => error.message,
            'message',
            contains('truncated'),
          ),
        ),
      );
    },
  );

  test('issuer quarantine action requests require a nonempty reason', () {
    expect(
      () => catalogIdentityReviewActionBody(
        action: 'retry',
        reviewItemId: 'review-1',
        reason: ' ',
      ),
      throwsArgumentError,
    );
    expect(
      () => catalogIdentityReviewActionBody(
        action: 'mark_discontinued',
        reviewItemId: 'review-1',
        reason: ' ',
      ),
      throwsArgumentError,
    );
    expect(
      () => catalogIdentityReviewActionBody(
        action: 'reject',
        reviewItemId: 'review-1',
      ),
      throwsArgumentError,
    );
    expect(
      catalogIdentityReviewActionBody(
        action: 'retry',
        reviewItemId: 'review-1',
        reason: 'Verified temporary upstream outage',
      ),
      {
        'action': 'retry',
        'review_item_id': 'review-1',
        'reason': 'Verified temporary upstream outage',
      },
    );
  });

  test('catalog edit request contains only explicit editable proposals', () {
    final fields = catalogIdentityEditableFields(
      const {
        'cardName': 'Astra Reserve',
        'official_url': 'https://issuer.example/astra',
        'content_hash': 'immutable-hash',
        'source_observation': {'kind': 'strong_existing_official_card'},
      },
      cardName: 'Astra Reserve Plus',
      network: '',
    );

    expect(fields, {'cardName': 'Astra Reserve Plus'});
    expect(fields, isNot(contains('annual_fee')));
    expect(fields, isNot(contains('network')));
    expect(fields, isNot(contains('official_url')));
    expect(fields, isNot(contains('source_observation')));
  });

  test(
    'repository maps a paginated benefit response and sends its API action',
    () async {
      final api = _FakeApi(
        AdminCatalogEntryResponse(200, {
          'items': [_jobJson],
          'counts': {
            'total': 3,
            'by_status': {'staged': 1},
            'by_run_mode': {'scheduled': 2},
          },
          'movie_mapping_health': [
            {'metric': 'active_movie_benefits', 'value': 49},
            {'metric': 'mapped_active_movie_benefits', 'value': 8},
            {'metric': 'orphaned_active_movie_benefits', 'value': 41},
          ],
          'page': 2,
          'limit': 25,
          'has_more': true,
        }),
      );
      final repository = AdminCatalogRepository(api);

      final page = await repository.loadReviewPage(
        page: 2,
        limit: 25,
        status: 'staged',
      );

      expect(page.items.single.cardName, 'Astra Travel');
      expect(page.counts.byStatus['staged'], 1);
      expect(page.movieMappingHealth.active, 49);
      expect(page.movieMappingHealth.mapped, 8);
      expect(page.movieMappingHealth.orphaned, 41);
      expect(page.hasMore, isTrue);
      expect(api.bodies.first, {
        'action': 'benefit-list',
        'page': 2,
        'limit': 25,
        'status': 'staged',
      });
      expect(api.bodies.last['action'], 'benefit-status');
    },
  );

  test(
    'repository turns an expired admin session into an authorization requirement',
    () async {
      final repository = AdminCatalogRepository(
        _FakeApi(
          AdminCatalogEntryResponse(500, const {}),
          error: const FunctionException(
            status: 401,
            details: {'error': 'authentication_required'},
          ),
        ),
      );

      expect(
        repository.loadReviewPage(),
        throwsA(isA<AdminAuthorizationRequired>()),
      );
    },
  );

  test(
    'repository reports a browser fetch failure as a request failure',
    () async {
      final repository = AdminCatalogRepository(
        _FakeApi(
          AdminCatalogEntryResponse(500, const {}),
          error: http.ClientException(
            'Failed to fetch',
            Uri.parse(
              'https://example.supabase.co/functions/v1/admin-catalog-entry',
            ),
          ),
        ),
      );

      expect(
        repository.loadReviewPage(),
        throwsA(
          isA<AdminCatalogRequestFailed>().having(
            (error) => error.message,
            'message',
            'Could not reach the admin service. Try again.',
          ),
        ),
      );
    },
  );

  test(
    'repository derives approval decisions from the safe diff when staging decisions are empty',
    () async {
      final api = _FakeApi(
        AdminCatalogEntryResponse(200, const {'success': true}),
      );
      final item = BenefitEnrichmentReview.fromJson({
        ..._jobJson,
        'staging': {
          ...(_jobJson['staging'] as Map<String, dynamic>),
          'benefit_decisions': [],
          'extracted_data': {
            'diff': {
              'additions': [
                {'dedupeKey': 'new', 'title': 'New benefit'},
              ],
              'modifications': [
                {
                  'current': {'dedupeKey': 'old', 'title': 'Old'},
                  'proposed': {'dedupeKey': 'old', 'title': 'Updated'},
                },
              ],
              'possibleRemovals': [
                {'dedupeKey': 'legacy', 'title': 'Legacy'},
              ],
              'conflicts': [
                {
                  'code': 'duplicate',
                  'current': [
                    {'dedupeKey': 'current', 'title': 'Current'},
                  ],
                  'proposed': [
                    {'dedupeKey': 'candidate', 'title': 'Candidate'},
                  ],
                },
              ],
            },
          },
        },
      });

      await AdminCatalogRepository(api).approve(item);

      final decisions = api.bodies.single['decisions'] as List;
      expect(decisions, hasLength(5));
      expect(decisions.first, containsPair('change_type', 'addition'));
      expect(decisions[1], containsPair('change_type', 'modification'));
      expect(decisions[2], containsPair('action', 'keep_existing'));
      expect(decisions.last, containsPair('dedupe_key', 'candidate'));
    },
  );

  test('repository submits exact v6 retirement and edit identifiers', () async {
    final api = _FakeApi(
      AdminCatalogEntryResponse(200, const {'success': true}),
    );
    final repository = AdminCatalogRepository(api);
    final item = BenefitEnrichmentReview.fromJson(_v6JobJson);
    final removal = item.staging.extractedData.diff.possibleRemovals.single;

    await repository.retire(item, removal, 'Issuer corroborated retirement');
    final retirement = api.bodies.single;
    final retirementDecision = (retirement['decisions'] as List).single as Map;
    expect(retirement['action'], 'benefit-approve');
    expect(
      retirementDecision['benefit_id'],
      '22222222-2222-4222-8222-222222222222',
    );
    expect(retirementDecision['dedupe_key'], 'legacy:approved:lounge-visit');
    expect(
      (retirementDecision['benefit'] as Map)['benefitId'],
      'card-benefit-v2:card-1:${'c' * 64}',
    );
    expect(
      (retirementDecision['benefit'] as Map)['dedupeKey'],
      'legacy:approved:lounge-visit',
    );
    expect(
      (retirementDecision['benefit'] as Map)['liveBenefitId'],
      '22222222-2222-4222-8222-222222222222',
    );
    expect(retirementDecision['reason'], 'Issuer corroborated retirement');

    api.bodies.clear();
    final decision = item.staging.decisions.single;
    await repository.editApprove(item, [
      decision.withEditedBenefit(
        decision.proposed!.copyWith(description: 'Reviewed wording'),
      ),
    ]);
    final editDecision = (api.bodies.single['decisions'] as List).single as Map;
    expect(editDecision['benefit_id'], decision.liveBenefitId);
    expect(editDecision['dedupe_key'], decision.dedupeKey);
    expect(
      (editDecision['edited_benefit'] as Map)['benefitId'],
      'card-benefit-v2:card-1:${'a' * 64}',
    );
    expect(editDecision, isNot(contains('change_type')));
  });

  testWidgets(
    'benefit panel renders progress, diffs, evidence, and individual controls',
    (tester) async {
      final openedUrls = <Uri>[];
      await _pumpPanel(
        tester,
        _FakeRepository(_page()),
        onOpenUrl: openedUrls.add,
      );

      expect(find.text('Benefit enrichment'), findsOneWidget);
      expect(
        find.text('Job run coverage: 2 scheduled · 1 pilot'),
        findsOneWidget,
      );
      expect(
        find.text('All jobs by status: 1 completed · 1 failed'),
        findsOneWidget,
      );
      expect(
        find.text('Movies mapping health: 8 / 49 mapped · 41 orphaned'),
        findsOneWidget,
      );
      expect(find.text('Current'), findsOneWidget);
      expect(find.text('Proposed'), findsAtLeastNWidgets(1));
      expect(
        find.textContaining('₹500 dining credit'),
        findsAtLeastNWidgets(1),
      );
      expect(
        find.textContaining(
          'Crawler-discovered card — statement evidence is unavailable',
        ),
        findsOneWidget,
      );
      expect(find.text('Approve benefit changes'), findsOneWidget);
      expect(find.text('Edit proposed changes'), findsOneWidget);
      expect(find.text('Reject changes'), findsOneWidget);
      expect(find.text('Retry processing'), findsOneWidget);
      expect(find.text('Quarantine'), findsOneWidget);
      expect(
        find.textContaining('Crawler discovery: verify against a statement'),
        findsOneWidget,
      );
      expect(find.textContaining('crawler_discovered'), findsNothing);
      expect(find.textContaining('Approve all'), findsNothing);

      await tester.tap(find.text('Open official source'));
      expect(
        openedUrls.single,
        Uri.parse('https://issuer.example/cards/astra'),
      );
    },
  );

  testWidgets(
    'v6 panel shows completeness attempts identity migration and eligible retirement',
    (tester) async {
      final repository = _FakeRepository(
        BenefitEnrichmentReviewPage.fromJson(const {
          'counts': {'total': 1, 'by_status': {}, 'by_run_mode': {}},
          'page': 1,
          'limit': 25,
          'has_more': false,
        }).copyWith(items: [BenefitEnrichmentReview.fromJson(_v6JobJson)]),
      );
      await _pumpPanel(tester, repository);

      expect(find.textContaining('Incomplete crawl'), findsOneWidget);
      expect(find.textContaining('required source failed'), findsOneWidget);
      expect(find.textContaining('required supporting'), findsOneWidget);
      expect(find.textContaining('503'), findsOneWidget);
      expect(find.textContaining('2026-08-20T10:11:12.123456Z'), findsWidgets);
      expect(find.textContaining('Identity migration'), findsOneWidget);
      expect(
        find.textContaining('rate 5 → Dining points · rate 10'),
        findsOneWidget,
      );
      expect(
        find.textContaining('card-benefit-v2:card-1:${'a' * 64}'),
        findsWidgets,
      );
      expect(find.textContaining('Condition hash: ${'a' * 64}'), findsWidgets);
      expect(find.text('Retirement eligible: Yes'), findsOneWidget);
      expect(find.text('Retire benefit'), findsOneWidget);

      final retireButton = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Retire benefit'),
      );
      retireButton.onPressed!();
      await tester.pumpAndSettle();
      expect(find.text('Retire Legacy lounge visit?'), findsOneWidget);
      await tester.enterText(
        find.byType(TextField).last,
        'Issuer corroborated retirement',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Retire'));
      await tester.pumpAndSettle();

      expect(repository.actions, ['retire']);
      expect(repository.retirementReason, 'Issuer corroborated retirement');
      expect(
        repository.retiredBenefitId,
        '22222222-2222-4222-8222-222222222222',
      );
    },
  );

  testWidgets('ineligible retirement stays informational and has no action', (
    tester,
  ) async {
    final ineligible = <String, dynamic>{
      ..._v6JobJson,
      'staging': {
        ...(_v6JobJson['staging'] as Map<String, dynamic>),
        'extracted_data': {
          ...((_v6JobJson['staging'] as Map<String, dynamic>)['extracted_data']
              as Map<String, dynamic>),
          'diff': {
            'possibleRemovals': [
              {
                'benefit': {
                  'liveBenefitId': '22222222-2222-4222-8222-222222222222',
                  'benefitId': 'card-benefit-v2:card-1:${'c' * 64}',
                  'dedupeKey': 'legacy:approved:lounge-visit',
                  'title': 'Legacy lounge visit',
                },
                'informational': true,
                'retirementEligible': false,
                'retirementReason': 'needs_second_complete_observation',
              },
            ],
          },
        },
      },
    };
    final repository = _FakeRepository(
      BenefitEnrichmentReviewPage.fromJson(const {
        'counts': {'total': 1, 'by_status': {}, 'by_run_mode': {}},
        'page': 1,
        'limit': 25,
        'has_more': false,
      }).copyWith(items: [BenefitEnrichmentReview.fromJson(ineligible)]),
    );
    await _pumpPanel(tester, repository);

    expect(
      find.textContaining('Needs second complete observation'),
      findsOneWidget,
    );
    expect(find.text('Retire benefit'), findsNothing);
  });

  testWidgets(
    'benefit panel keeps a 401 actionable instead of spinning forever',
    (tester) async {
      var requestedAuthorization = false;
      await _pumpPanel(
        tester,
        _FakeRepository(_page(), error: AdminAuthorizationRequired()),
        onAuthorizationRequired: () => requestedAuthorization = true,
      );

      expect(find.text('Your session needs authorization.'), findsOneWidget);
      expect(find.text('Sign in again'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await tester.tap(find.text('Sign in again'));
      expect(requestedAuthorization, isTrue);
    },
  );

  testWidgets('malformed v6 review data fails closed with a visible error', (
    tester,
  ) async {
    await _pumpPanel(
      tester,
      _FakeRepository(
        _page(),
        error: const FormatException('Malformed required v6 benefit identity.'),
      ),
    );

    expect(find.textContaining('Malformed v6 review data'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('staging-only v6 corruption reaches the visible repair state', (
    tester,
  ) async {
    final response = AdminCatalogEntryResponse(200, {
      'items': [_stagingOnlyV6Corruption],
      'counts': {'total': 1, 'by_status': {}, 'by_run_mode': {}},
      'page': 1,
      'limit': 25,
      'has_more': false,
    });

    await _pumpPanel(tester, AdminCatalogRepository(_FakeApi(response)));

    expect(find.textContaining('Malformed v6 review data'), findsOneWidget);
    expect(find.textContaining('repaired'), findsOneWidget);
    expect(find.text('Approved dining benefit'), findsNothing);
  });

  testWidgets(
    'malformed proposed v6 identities reach the visible repair state',
    (tester) async {
      final malformed = [
        _v6AdditionWithIdentity(
          benefitId: 'card-benefit-v2:other-card:${'d' * 64}',
          conditionHash: 'd' * 64,
        ),
        _v6AdditionWithIdentity(
          benefitId: 'card-benefit-v2:card-1:${'e' * 64}',
          conditionHash: 'd' * 64,
        ),
        _v6AdditionWithIdentity(
          benefitId: 'benefit-v2:card-1:${'d' * 64}',
          conditionHash: 'd' * 64,
        ),
      ];

      for (final row in malformed) {
        final response = AdminCatalogEntryResponse(200, {
          'items': [row],
          'counts': {'total': 1, 'by_status': {}, 'by_run_mode': {}},
          'page': 1,
          'limit': 25,
          'has_more': false,
        });

        await _pumpPanel(tester, AdminCatalogRepository(_FakeApi(response)));

        expect(find.textContaining('Malformed v6 review data'), findsOneWidget);
        expect(find.textContaining('repaired'), findsOneWidget);
        expect(find.text('Added dining benefit'), findsNothing);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
    },
  );

  testWidgets('benefit approval explains its consequence before applying', (
    tester,
  ) async {
    final repository = _FakeRepository(_page());
    await _pumpPanel(tester, repository);

    final approveButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Approve benefit changes'),
    );
    approveButton.onPressed!();
    await tester.pumpAndSettle();

    expect(find.text('Apply these benefit changes?'), findsOneWidget);
    expect(
      find.textContaining('updates the existing catalog card'),
      findsOneWidget,
    );
    expect(repository.actions, isEmpty);

    await tester.tap(find.widgetWithText(FilledButton, 'Apply changes'));
    await tester.pumpAndSettle();
    expect(repository.actions, ['approve']);
  });
}
