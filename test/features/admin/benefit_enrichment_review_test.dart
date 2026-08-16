import 'package:cardcompass/features/admin/data/admin_catalog_repository.dart';
import 'package:cardcompass/features/admin/models/benefit_enrichment_review.dart';
import 'package:cardcompass/features/admin/screens/card_catalog_review_screen.dart';
import 'package:cardcompass/features/admin/widgets/benefit_enrichment_review_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
    'validation_warnings': [
      {'code': 'crawler_discovered'},
    ],
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

BenefitEnrichmentReviewPage _page() =>
    BenefitEnrichmentReviewPage.fromJson(const {
      'counts': {
        'total': 3,
        'by_status': {'staged': 1, 'completed': 1, 'failed': 1},
        'by_run_mode': {'scheduled': 2, 'pilot': 1},
      },
      'page': 1,
      'limit': 25,
      'has_more': false,
    }).copyWith(items: [BenefitEnrichmentReview.fromJson(_jobJson)]);

class _FakeApi implements AdminCatalogEntryApi {
  _FakeApi(this.response);

  AdminCatalogEntryResponse response;
  final bodies = <Map<String, dynamic>>[];

  @override
  Future<AdminCatalogEntryResponse> invoke(Map<String, dynamic> body) async {
    bodies.add(body);
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
    },
  );

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
      expect(page.hasMore, isTrue);
      expect(api.bodies.single, {
        'action': 'benefit-list',
        'page': 2,
        'limit': 25,
        'status': 'staged',
      });
    },
  );

  test(
    'repository turns an expired admin session into an authorization requirement',
    () async {
      final repository = AdminCatalogRepository(
        _FakeApi(
          AdminCatalogEntryResponse(401, {'error': 'authentication_required'}),
        ),
      );

      expect(
        repository.loadReviewPage(),
        throwsA(isA<AdminAuthorizationRequired>()),
      );
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
        find.text('Issuer coverage: 2 scheduled · 1 pilot'),
        findsOneWidget,
      );
      expect(find.text('Last run: 1 completed · 1 failed'), findsOneWidget);
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
      expect(find.text('Approve'), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Reject'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Quarantine'), findsOneWidget);
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
}
