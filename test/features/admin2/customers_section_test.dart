import 'dart:async';

import 'package:cardcompass/features/admin2/customers/customer_models.dart';
import 'package:cardcompass/features/admin2/customers/customer_repository.dart';
import 'package:cardcompass/features/admin2/customers/customers_section.dart';
import 'package:cardcompass/features/admin2/data/admin_operator_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const user = '00000000-0000-4000-8000-000000000002';
final summary = CustomerSummary(
  id: user,
  email: 'user@example.com',
  createdAt: DateTime.utc(2026),
  lastActivityAt: DateTime.utc(2026),
  isActive: true,
);
final customerDetail = CustomerDetail(
  summary: summary,
  gmailConnected: true,
  gmailStatus: CustomerOperationStatus.failed,
  gmailFailure: CustomerFailure.gmailUnavailable,
  gmailUpdatedAt: DateTime.utc(2026),
  ownedCardCount: 2,
  statementCount: 3,
  processedStatementCount: 1,
  emailCount: 4,
  processedEmailCount: 2,
  latestStatementAt: DateTime.utc(2026),
  latestEmailAt: DateTime.utc(2026),
  deletionStatus: DeletionStatus.verified,
  deletionUpdatedAt: DateTime.utc(2026),
);

final class _Source implements CustomerDataSource {
  List<CustomerSummary> results = [summary];
  Completer<List<CustomerSummary>>? pendingSearch;
  final mutations = <CustomerMutation>[];
  Object? mutationError;
  @override
  Future<List<CustomerSummary>> search(String query) =>
      pendingSearch?.future ?? Future.value(results);
  @override
  Future<CustomerDetail> detail(String targetId) async => customerDetail;
  @override
  Future<CustomerReceipt> mutate(CustomerMutation mutation) async {
    mutations.add(mutation);
    if (mutationError case final e?) throw e;
    return mutation is QueueGmailRetry
        ? const GmailRetryReceipt(
            requestId: '00000000-0000-4000-8000-000000000003',
            status: CustomerOperationStatus.queued,
          )
        : mutation is DisableCustomer
        ? const DisableCustomerReceipt(userId: user, authBanned: true)
        : CustomerDeletionReceipt(
            userId: user,
            status: (mutation as SetCustomerDeletionStatus).status,
            updatedAt: DateTime.utc(2026),
          );
  }
}

Future<void> _pump(
  WidgetTester tester,
  _Source source, {
  Size size = const Size(1200, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: CustomersSection(repository: source)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('wide search/list/detail shows only approved support metadata', (
    tester,
  ) async {
    final source = _Source();
    await _pump(tester, source);
    await tester.enterText(
      find.byKey(const Key('customer-search-field')),
      'user',
    );
    await tester.tap(find.byKey(const Key('customer-search-submit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('customers-wide-layout')), findsOneWidget);
    expect(find.text('user@example.com'), findsWidgets);
    expect(find.text('Gmail unavailable'), findsOneWidget);
    expect(find.textContaining('subject'), findsNothing);
    expect(find.textContaining('transaction'), findsNothing);
  });

  testWidgets(
    'retains results during refresh and ignores stale racing result',
    (tester) async {
      final source = _Source();
      await _pump(tester, source);
      await tester.enterText(
        find.byKey(const Key('customer-search-field')),
        'user',
      );
      await tester.tap(find.byKey(const Key('customer-search-submit')));
      await tester.pumpAndSettle();
      source.pendingSearch = Completer<List<CustomerSummary>>();
      await tester.tap(find.byKey(const Key('customer-refresh')));
      await tester.pump();
      expect(find.text('user@example.com'), findsWidgets);
      source.results = [];
      source.pendingSearch = null;
      await tester.enterText(
        find.byKey(const Key('customer-search-field')),
        'other',
      );
      await tester.tap(find.byKey(const Key('customer-search-submit')));
      await tester.pumpAndSettle();
      source.pendingSearch = Completer<List<CustomerSummary>>()
        ..complete([summary]);
      await tester.pumpAndSettle();
      expect(find.text('No customers found.'), findsOneWidget);
    },
  );

  testWidgets('compact layout drills into detail at 390 logical pixels', (
    tester,
  ) async {
    final source = _Source();
    await _pump(tester, source, size: const Size(390, 844));
    await tester.enterText(
      find.byKey(const Key('customer-search-field')),
      'user',
    );
    await tester.tap(find.byKey(const Key('customer-search-submit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('customers-compact-layout')), findsOneWidget);
    await tester.tap(find.text('user@example.com').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('customer-compact-detail')), findsOneWidget);
    expect(find.byTooltip('Back to customer results'), findsOneWidget);
  });

  testWidgets('retry explains queued execution and disables double submit', (
    tester,
  ) async {
    final source = _Source();
    await _pump(tester, source);
    await tester.enterText(
      find.byKey(const Key('customer-search-field')),
      'user',
    );
    await tester.tap(find.byKey(const Key('customer-search-submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('customer-retry')));
    await tester.pumpAndSettle();
    expect(find.textContaining("next authenticated session"), findsOneWidget);
  });

  testWidgets('auth ban pending clearly distinguishes database block', (
    tester,
  ) async {
    final source = _Source()
      ..mutationError = const AdminRequestFailed('auth_ban_pending');
    await _pump(tester, source);
    await tester.enterText(
      find.byKey(const Key('customer-search-field')),
      'user',
    );
    await tester.tap(find.byKey(const Key('customer-search-submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('customer-disable')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('customer-confirm-reason')),
      'suspected abuse',
    );
    await tester.enterText(
      find.byKey(const Key('customer-confirm-target')),
      user,
    );
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('customer-confirm-submit')),
          )
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.byKey(const Key('customer-confirm-submit')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Database access is blocked'), findsOneWidget);
    expect(find.textContaining('Auth ban needs retry'), findsOneWidget);
  });
}
