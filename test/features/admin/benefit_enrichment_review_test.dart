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
      expect(find.textContaining('anchor-123'), findsOneWidget);
      expect(find.text('Retry issuer discovery'), findsOneWidget);
      expect(find.text('Keep quarantined'), findsOneWidget);
      expect(find.text('Approve as new card'), findsNothing);
      expect(find.text('Edit and approve'), findsNothing);
      expect(find.textContaining('lease_token'), findsNothing);
    },
  );

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
