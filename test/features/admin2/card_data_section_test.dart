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
  Completer<void>? actionCompletion;
  Object? listError;
  Object? actionError;
  var calls = 0;

  @override
  Future<CardReviewPage> list(CardReviewQuery query) async {
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
    expect(find.byKey(const Key('card-data-wide-layout')), findsOneWidget);
    expect(find.text('Refreshed 19 Aug 2026, 09:05 UTC'), findsOneWidget);
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
    await tester.tap(find.text('Reject'));
    await tester.pumpAndSettle();
    expect(find.text('Reason'), findsOneWidget);
    await tester.tap(find.text('Confirm rejection'));
    await tester.pump();
    expect(find.text('Add a reason to continue.'), findsOneWidget);
    await tester.enterText(
      find.byType(TextField),
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
