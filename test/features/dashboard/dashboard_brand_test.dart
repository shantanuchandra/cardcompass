import 'dart:async';
import 'dart:io';

import 'package:cardcompass/core/providers/supabase_provider.dart';
import 'package:cardcompass/core/router/app_tab_selection.dart';
import 'package:cardcompass/core/services/card_discovery_service.dart';
import 'package:cardcompass/core/services/gmail_sync_service.dart';
import 'package:cardcompass/core/theme/app_theme.dart';
import 'package:cardcompass/features/dashboard/providers/dashboard_provider.dart';
import 'package:cardcompass/features/dashboard/providers/gmail_sync_provider.dart';
import 'package:cardcompass/features/dashboard/screens/dashboard_screen.dart';
import 'package:cardcompass/shared/models/transaction.dart';
import 'package:cardcompass/shared/models/user_card.dart';
import 'package:cardcompass/shared/models/statement.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _fixture = DashboardData(
  cards: [
    UserCard(
      id: 'card-1',
      userId: 'user-1',
      catalogCardId: 'catalog-1',
      cardName: 'Horizon Card',
      bank: 'Horizon Bank',
      creditLimit: 100000,
      createdAt: DateTime(2026),
    ),
  ],
  recentTransactions: [
    Transaction(
      id: 'transaction-1',
      userId: 'user-1',
      userCardId: 'card-1',
      amount: 1250,
      description: 'Groceries',
      transactionType: TransactionType.debit,
      transactionDate: DateTime(2026, 8, 15),
      createdAt: DateTime(2026, 8, 15),
    ),
  ],
  latestStatements: {},
  totalCreditLimit: 100000,
  monthlySpend: 1250,
  rewardsEarned: 75,
  monthlySpendTrend: const [800, 950, 1100, 1000, 1300, 1250],
  monthlyRewardsTrend: const [40, 55, 60, 50, 70, 75],
  trendMonths: [
    DateTime(2026, 3),
    DateTime(2026, 4),
    DateTime(2026, 5),
    DateTime(2026, 6),
    DateTime(2026, 7),
    DateTime(2026, 8),
  ],
);

final _cardlessFixture = DashboardData(
  cards: const [],
  recentTransactions: const [],
  latestStatements: const {},
  totalCreditLimit: 0,
  monthlySpend: 0,
  rewardsEarned: 0,
  monthlySpendTrend: const [0, 0, 0, 0, 0, 0],
  monthlyRewardsTrend: const [0, 0, 0, 0, 0, 0],
  trendMonths: [
    DateTime(2026, 3),
    DateTime(2026, 4),
    DateTime(2026, 5),
    DateTime(2026, 6),
    DateTime(2026, 7),
    DateTime(2026, 8),
  ],
);

class _FailingGmailSyncNotifier extends GmailSyncNotifier {
  @override
  Future<GmailSyncResult?> build() async {
    throw StateError('internal Gmail credential must not be displayed');
  }
}

class _ExpiredGmailSyncNotifier extends GmailSyncNotifier {
  @override
  Future<GmailSyncResult?> build() async {
    throw const GmailAuthException('expired private Google credential');
  }
}

Future<void> _pumpDashboard(
  WidgetTester tester, {
  required ValueNotifier<AppTab> selectedAppTab,
  DashboardData? data,
  bool failDashboard = false,
  bool failGmailSync = false,
  bool expireGmailSync = false,
  GmailReconnect? gmailReconnect,
  VoidCallback? onDashboardLoad,
  List<Map<String, dynamic>> pendingAssignments = const [],
  BankCatalogSearch? catalogSearch,
  CardResolution? cardResolution,
  CardUrlResolver? cardUrlResolver,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserProvider.overrideWithValue(null),
        pendingCardAssignmentsProvider.overrideWith(
          (ref) async => pendingAssignments,
        ),
        if (catalogSearch != null)
          bankCatalogSearchProvider.overrideWithValue(catalogSearch),
        if (cardResolution != null)
          cardResolutionProvider.overrideWithValue(cardResolution),
        if (cardUrlResolver != null)
          cardUrlResolverProvider.overrideWithValue(cardUrlResolver),
        dashboardProvider.overrideWith((ref) async {
          onDashboardLoad?.call();
          if (failDashboard) {
            throw StateError(
              'internal dashboard request must not be displayed',
            );
          }
          return data ?? _fixture;
        }),
        if (failGmailSync)
          gmailSyncProvider.overrideWith(_FailingGmailSyncNotifier.new),
        if (expireGmailSync)
          gmailSyncProvider.overrideWith(_ExpiredGmailSyncNotifier.new),
        if (gmailReconnect != null)
          gmailReconnectProvider.overrideWithValue(gmailReconnect),
      ],
      child: MaterialApp(
        theme: AppTheme.work,
        home: AppTabSelection(
          onSelect: (tab) => selectedAppTab.value = tab,
          child: const DashboardScreen(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _startPendingAssignment(
  WidgetTester tester, {
  required Completer<void> resolution,
  required ValueChanged<int> onResolution,
  VoidCallback? onDashboardLoad,
  bool startResolution = true,
}) async {
  var resolutionCount = 0;
  final selectedAppTab = ValueNotifier(AppTab.dashboard);
  addTearDown(selectedAppTab.dispose);
  await _pumpDashboard(
    tester,
    selectedAppTab: selectedAppTab,
    onDashboardLoad: onDashboardLoad,
    pendingAssignments: const [
      {'email_id': 'email-1', 'bank_detected': 'Horizon Bank'},
    ],
    catalogSearch: (_, _) async => const [
      {
        'id': 'catalog-1',
        'card_name': 'Astra Preferred',
        'bank': 'Horizon Bank',
      },
    ],
    cardResolution: (_, _) {
      resolutionCount++;
      onResolution(resolutionCount);
      return resolution.future;
    },
  );
  await tester.scrollUntilVisible(
    find.text('Your Cards'),
    300,
    scrollable: find
        .descendant(
          of: find.byType(CustomScrollView),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.drag(find.byType(PageView), const Offset(-500, 0));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('resolve-bank-email-1')));
  await tester.pumpAndSettle();
  if (startResolution) {
    await tester.tap(find.text('Astra Preferred'));
    await tester.pump();
  }
}

void main() {
  testWidgets(
    'bill section distinguishes statement balances from monthly spend',
    (tester) async {
      final selectedAppTab = ValueNotifier(AppTab.dashboard);
      addTearDown(selectedAppTab.dispose);
      final statement = Statement(
        id: 'statement-1',
        userId: 'user-1',
        cardId: 'catalog-1',
        userCardId: 'card-1',
        statementDate: DateTime(2026, 8, 1),
        dueDate: DateTime(2026, 8, 21),
        totalAmount: 476612,
        closingBalance: 476612,
        paymentStatus: PaymentStatus.pending,
        createdAt: DateTime(2026, 8, 1),
      );
      final data = DashboardData(
        cards: _fixture.cards,
        recentTransactions: const [],
        latestStatements: {'card-1': statement},
        totalCreditLimit: 1000000,
        monthlySpend: 0,
        rewardsEarned: 0,
        monthlySpendTrend: const [0, 0, 0, 0, 0, 0],
        monthlyRewardsTrend: const [0, 0, 0, 0, 0, 0],
        trendMonths: _fixture.trendMonths,
      );

      await _pumpDashboard(tester, selectedAppTab: selectedAppTab, data: data);

      expect(find.text('Statement balances due'), findsOneWidget);
      expect(find.textContaining("not this month's purchases"), findsOneWidget);
    },
  );

  final source = File(
    'lib/features/dashboard/screens/dashboard_screen.dart',
  ).readAsStringSync();
  test('dashboard is an ink and paper wallet briefing', () {
    expect(source, contains('BrandColors.paper'));
    expect(source, contains('BrandColors.ledger'));
    expect(source, contains("fontFamily: 'Fraunces'"));
    expect(source, isNot(contains('GoogleFonts.spaceGrotesk')));
    expect(source, isNot(contains('GestureDetector')));
  });

  testWidgets('dashboard view-all actions select their destinations', (
    tester,
  ) async {
    final selectedAppTab = ValueNotifier(AppTab.dashboard);
    addTearDown(selectedAppTab.dispose);
    await _pumpDashboard(tester, selectedAppTab: selectedAppTab);

    await tester.scrollUntilVisible(
      find.text('Manage cards'),
      300,
      scrollable: find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('Manage cards'));
    expect(selectedAppTab.value, AppTab.cards);

    await tester.scrollUntilVisible(
      find.text('View all transactions'),
      300,
      scrollable: find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('View all transactions'));
    expect(selectedAppTab.value, AppTab.transactions);
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('cardless dashboard focuses one setup action for Cards', (
    tester,
  ) async {
    final selectedAppTab = ValueNotifier(AppTab.dashboard);
    addTearDown(selectedAppTab.dispose);
    await _pumpDashboard(
      tester,
      selectedAppTab: selectedAppTab,
      data: _cardlessFixture,
    );

    expect(find.text('Build your dashboard'), findsOneWidget);
    expect(find.byKey(const Key('primary-spend-metric')), findsNothing);
    await tester.tap(find.text('Add a card'));
    expect(selectedAppTab.value, AppTab.cards);
  });

  testWidgets('dashboard failures redact internal details and offer Retry', (
    tester,
  ) async {
    final selectedAppTab = ValueNotifier(AppTab.dashboard);
    var dashboardLoads = 0;
    addTearDown(selectedAppTab.dispose);
    await _pumpDashboard(
      tester,
      selectedAppTab: selectedAppTab,
      failDashboard: true,
      onDashboardLoad: () => dashboardLoads++,
    );

    expect(find.text("Couldn't load dashboard"), findsOneWidget);
    expect(find.text('Check your connection and try again.'), findsOneWidget);
    expect(find.textContaining('internal dashboard request'), findsNothing);
    expect(find.text('Retry'), findsOneWidget);
    expect(dashboardLoads, 1);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(dashboardLoads, 2);
  });

  testWidgets('Gmail sync failures never render internal exception text', (
    tester,
  ) async {
    final selectedAppTab = ValueNotifier(AppTab.dashboard);
    addTearDown(selectedAppTab.dispose);
    await _pumpDashboard(
      tester,
      selectedAppTab: selectedAppTab,
      failGmailSync: true,
    );

    expect(
      find.textContaining('internal Gmail credential must not be displayed'),
      findsNothing,
    );
    expect(
      find.text("Couldn't sync Gmail. Check your connection and try again."),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('dashboard card is a labeled keyboard-sized button', (
    tester,
  ) async {
    final selectedAppTab = ValueNotifier(AppTab.dashboard);
    addTearDown(selectedAppTab.dispose);
    await _pumpDashboard(tester, selectedAppTab: selectedAppTab);

    final card = find.byKey(const Key('dashboard-card-card-1'));
    await tester.scrollUntilVisible(
      card,
      300,
      scrollable: find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(tester.getSize(card).height, greaterThanOrEqualTo(44));
    expect(
      tester.getSemantics(card),
      matchesSemantics(
        label: 'Open Horizon Card card details',
        isButton: true,
        hasTapAction: true,
      ),
    );
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('cards carousel responds to a pressed mouse drag', (
    tester,
  ) async {
    final selectedAppTab = ValueNotifier(AppTab.dashboard);
    addTearDown(selectedAppTab.dispose);
    await _pumpDashboard(
      tester,
      selectedAppTab: selectedAppTab,
      pendingAssignments: const [
        {'email_id': 'email-mouse', 'bank_detected': 'Horizon Bank'},
        {'email_id': 'email-mouse-2', 'bank_detected': 'Horizon Bank'},
        {'email_id': 'email-mouse-3', 'bank_detected': 'Horizon Bank'},
      ],
      catalogSearch: (_, _) async => const [],
    );

    await tester.scrollUntilVisible(
      find.text('Your Cards'),
      300,
      scrollable: find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    final pageView = find.byType(PageView);
    final pageScrollable = find.descendant(
      of: pageView,
      matching: find.byType(Scrollable),
    );
    final position = tester.state<ScrollableState>(pageScrollable).position;
    expect(position.maxScrollExtent, greaterThan(0));
    expect(
      ScrollConfiguration.of(tester.element(pageView)).dragDevices,
      contains(PointerDeviceKind.mouse),
    );
    final before = position.pixels;
    await tester.drag(
      pageView,
      const Offset(-420, 0),
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryMouseButton,
    );
    await tester.pumpAndSettle();

    expect(
      tester.state<ScrollableState>(pageScrollable).position.pixels,
      greaterThan(before),
    );
  });

  testWidgets('pending card shows statement identity evidence', (tester) async {
    final selectedAppTab = ValueNotifier(AppTab.dashboard);
    addTearDown(selectedAppTab.dispose);
    await _pumpDashboard(
      tester,
      selectedAppTab: selectedAppTab,
      pendingAssignments: const [
        {
          'email_id': 'email-evidence',
          'bank_detected': 'HDFC Bank',
          'received_date': '2026-08-13T10:30:00Z',
          'metadata': {
            'needsCardAssignment': true,
            'identityHints': {
              'last4': '4821',
              'productName': 'Regalia Gold',
              'statementDate': '2026-08-12',
              'dueDate': '2026-09-02',
              'totalAmount': 18420.50,
            },
          },
        },
      ],
      catalogSearch: (_, _) async => const [],
    );

    await tester.scrollUntilVisible(
      find.text('Your Cards'),
      300,
      scrollable: find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.drag(find.byType(PageView), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(find.text('HDFC Bank •••• 4821'), findsOneWidget);
    expect(find.text('Possible card: Regalia Gold'), findsOneWidget);
    expect(find.textContaining('₹18,420.50 due 2 Sep'), findsOneWidget);
    expect(find.text('Confirm card'), findsOneWidget);
  });

  testWidgets('older pending card shows available email evidence', (
    tester,
  ) async {
    final selectedAppTab = ValueNotifier(AppTab.dashboard);
    addTearDown(selectedAppTab.dispose);
    await _pumpDashboard(
      tester,
      selectedAppTab: selectedAppTab,
      pendingAssignments: const [
        {
          'email_id': 'email-legacy',
          'bank_detected': 'ICICI Bank',
          'subject': 'Your ICICI Bank credit card statement is ready',
          'received_date': '2026-08-13T10:30:00Z',
          'metadata': {'attachmentFilename': 'ICICI-Aug-Statement.pdf'},
        },
      ],
      catalogSearch: (_, _) async => const [],
    );

    await tester.scrollUntilVisible(
      find.text('Your Cards'),
      300,
      scrollable: find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.drag(find.byType(PageView), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(
      find.text('Your ICICI Bank credit card statement is ready'),
      findsOneWidget,
    );
    expect(find.text('Statement email · 13 Aug'), findsOneWidget);
    expect(find.text('ICICI-Aug-Statement.pdf'), findsOneWidget);
    expect(find.text('Confirm card'), findsOneWidget);
  });

  testWidgets(
    'missing bank variant can be resolved from an official product URL',
    (tester) async {
      String? assignedCardId;
      String? submittedUrl;
      final selectedAppTab = ValueNotifier(AppTab.dashboard);
      addTearDown(selectedAppTab.dispose);
      await _pumpDashboard(
        tester,
        selectedAppTab: selectedAppTab,
        pendingAssignments: const [
          {
            'email_id': 'email-url',
            'bank_detected': 'Kotak Bank',
            'subject': 'Statement for White Reserve Credit Card',
            'metadata': {
              'identityHints': {
                'productName': 'White Reserve',
                'last4': '0771',
              },
            },
          },
        ],
        catalogSearch: (_, _) async => const [],
        cardUrlResolver: (email, url) async {
          submittedUrl = url;
          return const CardUrlResolution(
            jobId: 'job-url',
            status: 'resolved',
            resolvedCardId: 'catalog-white-reserve',
          );
        },
        cardResolution: (_, catalogCardId) async {
          assignedCardId = catalogCardId;
        },
      );

      await tester.scrollUntilVisible(
        find.text('Your Cards'),
        300,
        scrollable: find
            .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.drag(find.byType(PageView), const Offset(-500, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('resolve-bank-email-url')));
      await tester.pumpAndSettle();

      expect(
        find.text("Can't find it? Paste official card page"),
        findsOneWidget,
      );
      await tester.tap(find.text("Can't find it? Paste official card page"));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('official-card-url-field')),
        'http://www.kotak.com/rd/white-reserve',
      );
      await tester.tap(find.text('Verify card page'));
      await tester.pump();
      expect(find.text('Enter a valid HTTPS card page URL.'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('official-card-url-field')),
        'https://www.kotak.com/rd/white-reserve',
      );
      await tester.tap(find.text('Verify card page'));
      await tester.pumpAndSettle();

      expect(submittedUrl, 'https://www.kotak.com/rd/white-reserve');
      expect(assignedCardId, 'catalog-white-reserve');
      expect(find.byType(Dialog), findsNothing);
    },
  );

  testWidgets(
    'bank resolution redacts failures, clears stale errors, and retries',
    (tester) async {
      var searchFails = true;
      var resolutionFails = true;
      final selectedAppTab = ValueNotifier(AppTab.dashboard);
      addTearDown(selectedAppTab.dispose);
      await _pumpDashboard(
        tester,
        selectedAppTab: selectedAppTab,
        pendingAssignments: const [
          {'email_id': 'email-1', 'bank_detected': 'Horizon Bank'},
        ],
        catalogSearch: (bank, query) async {
          if (searchFails) throw StateError('secret catalog stack');
          return const [
            {
              'id': 'catalog-1',
              'card_name': 'Astra Preferred',
              'bank': 'Horizon Bank',
            },
          ];
        },
        cardResolution: (email, catalogCardId) async {
          if (resolutionFails) throw StateError('secret assignment stack');
        },
      );

      await tester.scrollUntilVisible(
        find.text('Your Cards'),
        300,
        scrollable: find
            .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.drag(find.byType(PageView), const Offset(-500, 0));
      await tester.pumpAndSettle();
      final resolveControl = find.byKey(const Key('resolve-bank-email-1'));
      expect(tester.getSize(resolveControl).height, greaterThanOrEqualTo(44));
      expect(
        tester.getSemantics(resolveControl),
        matchesSemantics(
          label: 'Resolve Horizon Bank card',
          tooltip: 'Resolve Horizon Bank card',
          isButton: true,
          hasTapAction: true,
          hasFocusAction: true,
          hasEnabledState: true,
          isEnabled: true,
          isFocusable: true,
        ),
      );
      await tester.tap(resolveControl);
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Could not load matching cards. Check your connection and try again.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('secret catalog stack'), findsNothing);
      expect(find.text('Retry search'), findsOneWidget);

      searchFails = false;
      await tester.tap(find.text('Retry search'));
      await tester.pumpAndSettle();
      expect(find.text('Astra Preferred'), findsOneWidget);
      expect(find.text('Retry search'), findsNothing);

      await tester.tap(find.text('Astra Preferred'));
      await tester.pumpAndSettle();
      expect(
        find.text('Could not assign this card. Try again.'),
        findsOneWidget,
      );
      expect(find.textContaining('secret assignment stack'), findsNothing);
      expect(find.text('Retry assignment'), findsOneWidget);

      resolutionFails = false;
      await tester.tap(find.text('Retry assignment'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
    },
  );

  testWidgets(
    'cancelled assignment invalidates once after success without duplicate work',
    (tester) async {
      final resolution = Completer<void>();
      var resolutionCount = 0;
      var dashboardLoads = 0;
      await _startPendingAssignment(
        tester,
        resolution: resolution,
        onResolution: (count) => resolutionCount = count,
        onDashboardLoad: () => dashboardLoads++,
      );

      await tester.tap(find.text('Astra Preferred'));
      await tester.pump();
      expect(resolutionCount, 1);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);

      resolution.complete();
      await tester.pumpAndSettle();
      expect(resolutionCount, 1);
      expect(dashboardLoads, 2);
    },
  );

  testWidgets('missing Gmail authorization explains how to resume assignment', (
    tester,
  ) async {
    var reconnectRequests = 0;
    final selectedAppTab = ValueNotifier(AppTab.dashboard);
    addTearDown(selectedAppTab.dispose);
    await _pumpDashboard(
      tester,
      selectedAppTab: selectedAppTab,
      pendingAssignments: const [
        {'email_id': 'email-1', 'bank_detected': 'Horizon Bank'},
      ],
      catalogSearch: (_, _) async => const [
        {
          'id': 'catalog-1',
          'card_name': 'Astra Preferred',
          'bank': 'Horizon Bank',
        },
      ],
      cardResolution: (_, _) async {
        throw const NoGmailTokenException('private token detail');
      },
      gmailReconnect: () async => reconnectRequests++,
    );

    await tester.scrollUntilVisible(
      find.text('Your Cards'),
      300,
      scrollable: find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.drag(find.byType(PageView), const Offset(-500, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('resolve-bank-email-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Astra Preferred'));
    await tester.pumpAndSettle();

    expect(
      find.text('Reconnect Gmail to download and process this statement.'),
      findsOneWidget,
    );
    expect(find.text('Reconnect Gmail'), findsOneWidget);
    expect(find.textContaining('private token detail'), findsNothing);
    expect(reconnectRequests, 1);
  });

  testWidgets('expired Gmail authorization immediately requests reconnection', (
    tester,
  ) async {
    var reconnectRequests = 0;
    final selectedAppTab = ValueNotifier(AppTab.dashboard);
    addTearDown(selectedAppTab.dispose);

    await _pumpDashboard(
      tester,
      selectedAppTab: selectedAppTab,
      expireGmailSync: true,
      gmailReconnect: () async => reconnectRequests++,
    );

    expect(reconnectRequests, 1);
    expect(find.text('Reconnect Gmail to continue syncing.'), findsOneWidget);
    expect(
      find.textContaining('expired private Google credential'),
      findsNothing,
    );
  });

  testWidgets(
    'assignment survives barrier dismissal and invalidates dashboard once',
    (tester) async {
      final resolution = Completer<void>();
      var dashboardLoads = 0;
      var resolutionCount = 0;
      final selectedAppTab = ValueNotifier(AppTab.dashboard);
      addTearDown(selectedAppTab.dispose);
      await _pumpDashboard(
        tester,
        selectedAppTab: selectedAppTab,
        onDashboardLoad: () => dashboardLoads++,
        pendingAssignments: const [
          {'email_id': 'email-1', 'bank_detected': 'Horizon Bank'},
        ],
        catalogSearch: (_, _) async => const [
          {
            'id': 'catalog-1',
            'card_name': 'Astra Preferred',
            'bank': 'Horizon Bank',
          },
        ],
        cardResolution: (_, _) {
          resolutionCount++;
          return resolution.future;
        },
      );
      await tester.scrollUntilVisible(
        find.text('Your Cards'),
        300,
        scrollable: find
            .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.drag(find.byType(PageView), const Offset(-500, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('resolve-bank-email-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Astra Preferred'));
      await tester.pump();

      final dialogRect = tester.getRect(find.byType(Dialog));
      await tester.tapAt(Offset(dialogRect.left / 2, dialogRect.center.dy));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);

      resolution.complete();
      await tester.pumpAndSettle();
      expect(resolutionCount, 1);
      expect(dashboardLoads, 2);
      expect(find.byType(Dialog), findsNothing);
    },
  );

  testWidgets('Back-dismissed assignment still invalidates after success', (
    tester,
  ) async {
    final resolution = Completer<void>();
    var resolutionCount = 0;
    var dashboardLoads = 0;
    await _startPendingAssignment(
      tester,
      resolution: resolution,
      onResolution: (count) => resolutionCount = count,
      onDashboardLoad: () => dashboardLoads++,
    );

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    await navigator.maybePop();
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);

    resolution.complete();
    await tester.pumpAndSettle();
    expect(resolutionCount, 1);
    expect(dashboardLoads, 2);
  });

  testWidgets(
    'two assignment activations before rebuild start one workflow and refresh',
    (tester) async {
      final resolution = Completer<void>();
      var resolutionCount = 0;
      var dashboardLoads = 0;
      await _startPendingAssignment(
        tester,
        resolution: resolution,
        onResolution: (count) => resolutionCount = count,
        onDashboardLoad: () => dashboardLoads++,
        startResolution: false,
      );

      await tester.tap(find.text('Astra Preferred'));
      await tester.tap(find.text('Astra Preferred'));
      expect(resolutionCount, 1);

      resolution.complete();
      await tester.pumpAndSettle();
      expect(dashboardLoads, 2);
      expect(find.byType(Dialog), findsNothing);
    },
  );

  testWidgets(
    'dismissed assignment failure does not refresh and retry refreshes once',
    (tester) async {
      final firstResolution = Completer<void>();
      final retryResolution = Completer<void>();
      var resolutionCount = 0;
      var dashboardLoads = 0;
      final selectedAppTab = ValueNotifier(AppTab.dashboard);
      addTearDown(selectedAppTab.dispose);
      await _pumpDashboard(
        tester,
        selectedAppTab: selectedAppTab,
        onDashboardLoad: () => dashboardLoads++,
        pendingAssignments: const [
          {'email_id': 'email-1', 'bank_detected': 'Horizon Bank'},
        ],
        catalogSearch: (_, _) async => const [
          {
            'id': 'catalog-1',
            'card_name': 'Astra Preferred',
            'bank': 'Horizon Bank',
          },
        ],
        cardResolution: (_, _) {
          resolutionCount++;
          return resolutionCount == 1
              ? firstResolution.future
              : retryResolution.future;
        },
      );

      Future<void> openDialogAndResolve() async {
        await tester.scrollUntilVisible(
          find.text('Your Cards'),
          300,
          scrollable: find
              .descendant(
                of: find.byType(CustomScrollView),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.drag(find.byType(PageView), const Offset(-500, 0));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('resolve-bank-email-1')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Astra Preferred'));
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
      }

      await openDialogAndResolve();
      firstResolution.completeError(StateError('private assignment failure'));
      await tester.pumpAndSettle();
      expect(resolutionCount, 1);
      expect(dashboardLoads, 1);
      expect(find.textContaining('private assignment failure'), findsNothing);

      await openDialogAndResolve();
      retryResolution.complete();
      await tester.pumpAndSettle();
      expect(resolutionCount, 2);
      expect(dashboardLoads, 2);
      expect(find.byType(Dialog), findsNothing);
    },
  );
}
