import 'dart:async';

import 'package:cardcompass/core/theme/app_theme.dart';
import 'package:cardcompass/features/admin2/card_data/card_data_models.dart';
import 'package:cardcompass/features/admin2/card_data/card_data_section.dart';
import 'package:cardcompass/features/admin2/data/admin_operator_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final class _FakeSource implements CardDataSource {
  _FakeSource(this.pages);

  final List<CardReviewPage> pages;
  final actions = <CardReviewAction>[];
  final queries = <CardReviewQuery>[];
  Completer<void>? actionCompletion;
  Object? listError;
  Object? actionError;
  var calls = 0;

  @override
  Future<CardReviewPage> list(CardReviewQuery query) async {
    queries.add(query);
    calls++;
    if (listError case final error?) throw error;
    return pages[(calls - 1).clamp(0, pages.length - 1)];
  }

  @override
  Future<void> act(CardReviewAction action) async {
    actions.add(action);
    if (actionError case final error?) throw error;
    await actionCompletion?.future;
  }
}

CardReviewItem _item({
  String id = '11111111-1111-4111-8111-111111111111',
  CardReviewLane lane = CardReviewLane.identity,
  String status = 'pending',
}) => CardReviewItem(
  id: id,
  lane: lane,
  status: status,
  updatedAt: DateTime.utc(2026, 8, 19, 9),
  evidence: [
    CardEvidence(
      officialUrl: 'https://issuer.example/card',
      excerpt: 'Annual fee is ₹999 and waived above ₹2 lakh spend.',
      retrievedAt: DateTime.utc(2026, 8, 19, 8, 30),
    ),
  ],
  warningCodes: const ['issuer_name_mismatch'],
  proposedFields: const {
    'bank': 'Example Bank',
    'card_name': 'Compass Rewards',
    'annual_fee': 999,
  },
  confidence: .86,
  stagingId: lane == CardReviewLane.benefit
      ? '22222222-2222-4222-8222-222222222222'
      : null,
  parserVersion: lane == CardReviewLane.benefit ? 'benefits-v2' : null,
  bank: 'Example Bank',
  cardName: 'Compass Rewards',
);

CardReviewPage _page({
  CardReviewLane lane = CardReviewLane.identity,
  List<CardReviewItem>? items,
  bool hasMore = false,
  int page = 1,
}) => CardReviewPage(
  lane: lane,
  items: items ?? [_item(lane: lane)],
  page: page,
  limit: 25,
  hasMore: hasMore,
  refreshedAt: DateTime.utc(2026, 8, 19, 9, 5),
);

Future<void> _pump(
  WidgetTester tester,
  _FakeSource source, {
  Size size = const Size(1280, 900),
  double textScale = 1,
  String? initialTargetId,
  CardReviewLane initialLane = CardReviewLane.identity,
  Future<bool> Function(Uri)? openExternalUrl,
  Future<void> Function()? onAuthenticationRequired,
  VoidCallback? onAccessDenied,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: AppTheme.work,
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: CardDataSection(
              repository: source,
              initialTargetId: initialTargetId,
              initialLane: initialLane,
              openExternalUrl: openExternalUrl,
              onAuthenticationRequired: onAuthenticationRequired,
              onAccessDenied: onAccessDenied,
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('shows loading then the exact initially targeted review', (
    tester,
  ) async {
    final second = _item(id: '33333333-3333-4333-8333-333333333333');
    final source = _FakeSource([
      _page(items: [_item(), second]),
    ]);
    await _pump(tester, source, initialTargetId: second.id);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text(second.id), findsOneWidget);
    expect(source.queries.single.targetId, second.id);
    expect(find.byKey(const Key('card-data-wide-layout')), findsOneWidget);
    expect(find.text('Refreshed 19 Aug 2026, 09:05 UTC'), findsOneWidget);
  });

  testWidgets('compact exact target opens its detail immediately', (
    tester,
  ) async {
    final target = _item(id: '33333333-3333-4333-8333-333333333333');
    final source = _FakeSource([
      _page(items: [target]),
    ]);
    await _pump(
      tester,
      source,
      size: const Size(390, 844),
      initialTargetId: target.id,
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('card-data-compact-layout')), findsOneWidget);
    expect(find.text(target.id), findsOneWidget);
    expect(find.text('Back to review queue'), findsOneWidget);

    await tester.binding.setSurfaceSize(const Size(1280, 900));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('card-data-wide-layout')), findsOneWidget);
    expect(find.text(target.id), findsOneWidget);

    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpAndSettle();
    expect(find.text('Back to review queue'), findsOneWidget);

    await tester.tap(find.text('Back to review queue'));
    await tester.pumpAndSettle();
    expect(find.text('Compass Rewards'), findsOneWidget);
  });

  testWidgets('missing exact target never falls back to an unrelated row', (
    tester,
  ) async {
    final source = _FakeSource([_page(items: const [])]);
    await _pump(
      tester,
      source,
      initialTargetId: '33333333-3333-4333-8333-333333333333',
    );
    await tester.pumpAndSettle();
    expect(
      find.text('This review is no longer available in the latest state.'),
      findsOneWidget,
    );
    expect(find.text('Compass Rewards'), findsNothing);
  });

  testWidgets('identity actions follow the pending-only SQL status gate', (
    tester,
  ) async {
    for (final status in ['pending', 'approved', 'merged', 'rejected']) {
      final source = _FakeSource([
        _page(items: [_item(status: status)]),
      ]);
      await _pump(tester, source);
      await tester.pumpAndSettle();

      expect(
        find.text('Retry'),
        status == 'pending' ? findsOneWidget : findsNothing,
        reason: 'identity retry matrix mismatch for status=$status',
      );
      expect(
        find.text('Approve'),
        status == 'pending' ? findsOneWidget : findsNothing,
        reason: 'identity decision matrix mismatch for status=$status',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });

  testWidgets('failed and quarantined benefits expose only recovery actions', (
    tester,
  ) async {
    final failed = _item(lane: CardReviewLane.benefit, status: 'failed');
    final quarantined = _item(
      id: '33333333-3333-4333-8333-333333333333',
      lane: CardReviewLane.benefit,
      status: 'quarantined',
    );
    final source = _FakeSource([
      _page(lane: CardReviewLane.benefit, items: [failed, quarantined]),
    ]);
    await _pump(tester, source, initialLane: CardReviewLane.benefit);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).last, const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Quarantine'), findsOneWidget);
    expect(find.text('Approve'), findsNothing);
    await tester.tap(find.widgetWithText(ListTile, 'Compass Rewards').last);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).last, const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('Unquarantine'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Quarantine'), findsNothing);
  });

  testWidgets('queued and incomplete staged benefits can be quarantined only', (
    tester,
  ) async {
    final queued = _item(lane: CardReviewLane.benefit, status: 'queued');
    final staged = _item(
      id: '33333333-3333-4333-8333-333333333333',
      lane: CardReviewLane.benefit,
      status: 'staged',
    );
    final source = _FakeSource([
      _page(lane: CardReviewLane.benefit, items: [queued, staged]),
    ]);
    await _pump(tester, source, initialLane: CardReviewLane.benefit);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).last, const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('Quarantine'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
    await tester.tap(find.widgetWithText(ListTile, 'Compass Rewards').last);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).last, const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('Quarantine'), findsOneWidget);
    expect(find.text('Submit benefit decisions'), findsNothing);
  });

  testWidgets('identity edit approval submits all visible edited fields', (
    tester,
  ) async {
    final source = _FakeSource([_page(), _page()]);
    await _pump(tester, source);
    await tester.pumpAndSettle();
    final cardName = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.labelText == 'Proposed card name',
    );
    await tester.enterText(cardName, 'Compass Rewards Plus');
    await tester.drag(find.byType(ListView).last, const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit & approve'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm edits'));
    await tester.pumpAndSettle();
    expect(source.actions.single.operation, CardReviewOperation.editApprove);
    expect(
      (source.actions.single.payload['proposed_fields'] as Map)['card_name'],
      'Compass Rewards Plus',
    );
  });

  testWidgets('benefit decisions submit one complete decision per proposal', (
    tester,
  ) async {
    final benefit = CardReviewItem(
      id: '11111111-1111-4111-8111-111111111111',
      lane: CardReviewLane.benefit,
      status: 'staged',
      updatedAt: DateTime.utc(2026, 8, 19, 9),
      evidence: const [],
      warningCodes: const [],
      proposedFields: const {},
      stagingId: '22222222-2222-4222-8222-222222222222',
      benefitProposals: [
        BenefitReviewProposal(
          key: 'lounge',
          kind: BenefitProposalKind.addition,
          current: const {},
          proposed: const {
            'dedupeKey': 'lounge',
            'title': 'Lounge access',
            'category': 'travel',
          },
        ),
        BenefitReviewProposal(
          key: 'dining',
          kind: BenefitProposalKind.modification,
          current: const {'dedupeKey': 'dining', 'rate': 5},
          proposed: const {
            'dedupeKey': 'dining',
            'title': 'Dining rewards',
            'category': 'dining',
            'rate': 10,
          },
        ),
      ],
    );
    final source = _FakeSource([
      _page(lane: CardReviewLane.benefit, items: [benefit]),
      _page(lane: CardReviewLane.benefit, items: [benefit]),
    ]);
    await _pump(tester, source, initialLane: CardReviewLane.benefit);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit proposal').last);
    await tester.pumpAndSettle();
    Future<void> edit(String key, String value) =>
        tester.enterText(find.byKey(Key('benefit-edit-lounge-$key')), value);
    await edit('title', 'Airport lounge access');
    await edit('rate', '2.5');
    await edit('currency', 'INR');
    await edit('unit', 'visits');
    await edit('cap', '8');
    await edit('frequency', 'annual');
    await edit('eligibility', 'Primary cardholders');
    await edit('partners', 'Lounge A, Lounge B');
    await edit('redemptionRules', 'Show the eligible card');
    await edit('effectiveFrom', '2026-09-01');
    await tester.scrollUntilVisible(
      find.text('Submit benefit decisions'),
      1000,
      scrollable: find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('Submit benefit decisions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm edits'));
    await tester.pumpAndSettle();
    final decisions = source.actions.single.payload['decisions'] as List;
    expect(source.actions.single.operation, CardReviewOperation.editApprove);
    expect(decisions, hasLength(2));
    expect(
      decisions.every((value) => (value as Map).containsKey('dedupe_key')),
      isTrue,
    );
    final edited = (decisions.first as Map)['edited_benefit'] as Map;
    expect(edited['title'], 'Airport lounge access');
    expect(edited['rate'], 2.5);
    expect(edited['currency'], 'INR');
    expect(edited['unit'], 'visits');
    expect(edited['cap'], 8);
    expect(edited['frequency'], 'annual');
    expect(edited['eligibility'], 'Primary cardholders');
    expect(edited['partners'], ['Lounge A', 'Lounge B']);
    expect(edited['redemptionRules'], 'Show the eligible card');
    expect(edited['effectiveFrom'], '2026-09-01');
    expect(edited['category'], 'travel');
  });

  testWidgets('safe evidence URL is actionable and shows retrieval freshness', (
    tester,
  ) async {
    Uri? opened;
    final source = _FakeSource([_page()]);
    await _pump(
      tester,
      source,
      openExternalUrl: (url) async {
        opened = url;
        return true;
      },
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('https://issuer.example/card'));
    await tester.tap(find.text('https://issuer.example/card'));
    expect(opened, Uri.parse('https://issuer.example/card'));
    expect(find.textContaining('Retrieved 19 Aug 08:30 UTC'), findsOneWidget);
  });

  testWidgets('switches lanes and paginates through typed queries', (
    tester,
  ) async {
    final source = _FakeSource([
      _page(hasMore: true),
      _page(lane: CardReviewLane.benefit, hasMore: true),
      _page(lane: CardReviewLane.benefit, page: 2),
    ]);
    await _pump(tester, source);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Benefits'));
    await tester.pumpAndSettle();
    expect(find.text('benefits-v2'), findsOneWidget);
    await tester.tap(find.text('Next page'));
    await tester.pumpAndSettle();
    expect(source.calls, 3);
  });

  testWidgets('reject requires a reason and waits for server confirmation', (
    tester,
  ) async {
    final source = _FakeSource([_page()])..actionCompletion = Completer<void>();
    await _pump(tester, source);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).last, const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reject'));
    await tester.pumpAndSettle();
    expect(find.text('Reason'), findsOneWidget);
    await tester.tap(find.text('Confirm rejection'));
    await tester.pump();
    expect(find.text('Add a reason to continue.'), findsOneWidget);
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == 'Reason',
      ),
      'Official page is not a card product',
    );
    await tester.tap(find.text('Confirm rejection'));
    await tester.pump();
    expect(source.actions.single.operation, CardReviewOperation.reject);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Approve'), findsOneWidget);
    source.actionCompletion!.complete();
    await tester.pumpAndSettle();
    expect(source.calls, 2);
  });

  testWidgets('a conflict reloads and explains that the state changed', (
    tester,
  ) async {
    final source = _FakeSource([_page(), _page()])
      ..actionError = AdminStateConflict();
    await _pump(tester, source);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).last, const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm approval'));
    await tester.pumpAndSettle();
    expect(
      find.text('This review changed. Check the latest state.'),
      findsOneWidget,
    );
    expect(source.calls, 2);
  });

  testWidgets('conflict disappearance retains target context without fallback', (
    tester,
  ) async {
    final target = _item();
    final source = _FakeSource([
      _page(items: [target]),
      _page(items: const []),
    ])..actionError = AdminStateConflict();
    await _pump(tester, source, initialTargetId: target.id);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).last, const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm approval'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'This review changed and is no longer available. The prior review context was not replaced.',
      ),
      findsOneWidget,
    );
    expect(find.text(target.id), findsOneWidget);
    expect(source.queries.last.targetId, target.id);
  });

  testWidgets(
    'same target conflict resets decisions and controllers to new version',
    (tester) async {
      CardReviewItem version(DateTime updatedAt, String title) =>
          CardReviewItem(
            id: '11111111-1111-4111-8111-111111111111',
            lane: CardReviewLane.benefit,
            status: 'staged',
            updatedAt: updatedAt,
            evidence: const [],
            warningCodes: const [],
            proposedFields: const {},
            stagingId: '22222222-2222-4222-8222-222222222222',
            benefitProposals: [
              BenefitReviewProposal(
                key: 'lounge',
                kind: BenefitProposalKind.addition,
                current: const {},
                proposed: {
                  'dedupeKey': 'lounge',
                  'title': title,
                  'category': 'travel',
                },
              ),
            ],
          );
      final source = _FakeSource([
        _page(
          lane: CardReviewLane.benefit,
          items: [version(DateTime.utc(2026, 8, 19, 9), 'Old title')],
        ),
        _page(
          lane: CardReviewLane.benefit,
          items: [version(DateTime.utc(2026, 8, 19, 10), 'Server title')],
        ),
      ])..actionError = AdminStateConflict();
      await _pump(tester, source, initialLane: CardReviewLane.benefit);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButton<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit proposal').last);
      await tester.pumpAndSettle();
      final title = find.byKey(const Key('benefit-edit-lounge-title'));
      await tester.enterText(title, 'Stale local title');
      await tester.scrollUntilVisible(
        find.text('Submit benefit decisions'),
        1000,
        scrollable: find
            .descendant(
              of: find.byType(ListView).last,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.text('Submit benefit decisions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm edits'));
      await tester.pumpAndSettle();

      expect(
        find.text('This review changed. Check the latest state.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<DropdownButton<String>>(
              find.byType(DropdownButton<String>).first,
            )
            .value,
        'approve',
      );
      await tester.tap(find.byType(DropdownButton<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit proposal').last);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(title).controller!.text, 'Server title');
    },
  );

  testWidgets('failed refresh retains stale queue and offers retry', (
    tester,
  ) async {
    final source = _FakeSource([_page()]);
    await _pump(tester, source);
    await tester.pumpAndSettle();
    source.listError = const AdminRequestFailed('request_failed');
    await tester.tap(find.byTooltip('Refresh queue'));
    await tester.pumpAndSettle();
    expect(find.text('Compass Rewards'), findsWidgets);
    expect(
      find.text('Refresh failed. Showing the last loaded queue.'),
      findsOneWidget,
    );
  });

  testWidgets('compact 2x text uses drill-in without overflow', (tester) async {
    final source = _FakeSource([_page()]);
    await _pump(tester, source, size: const Size(390, 844), textScale: 2);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('card-data-compact-layout')), findsOneWidget);
    await tester.tap(find.text('Compass Rewards').first);
    await tester.pumpAndSettle();
    expect(find.text('Back to review queue'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'authentication and authorization failures invoke access effects',
    (tester) async {
      var auth = 0;
      var denied = 0;
      final source = _FakeSource([_page()])
        ..listError = AdminAuthenticationRequired();
      await _pump(
        tester,
        source,
        onAuthenticationRequired: () async => auth++,
        onAccessDenied: () => denied++,
      );
      await tester.pumpAndSettle();
      expect(auth, 1);

      source.listError = AdminAccessDenied();
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(denied, 1);
    },
  );
}
