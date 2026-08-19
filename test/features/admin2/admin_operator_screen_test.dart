import 'dart:async';

import 'package:cardcompass/app.dart';
import 'package:cardcompass/core/router/app_router.dart';
import 'package:cardcompass/core/theme/app_theme.dart';
import 'package:cardcompass/features/admin2/data/admin_operator_api.dart';
import 'package:cardcompass/features/admin2/card_data/card_data_models.dart';
import 'package:cardcompass/features/admin2/card_data/card_data_section.dart';
import 'package:cardcompass/features/admin2/data/admin_operator_repository.dart';
import 'package:cardcompass/features/admin2/models/admin_access.dart';
import 'package:cardcompass/features/admin2/inbox/inbox_models.dart';
import 'package:cardcompass/features/admin2/providers/admin_access_provider.dart';
import 'package:cardcompass/features/admin2/screens/admin_operator_screen.dart';
import 'package:cardcompass/features/admin2/widgets/admin_workspace_navigation.dart';
import 'package:cardcompass/features/auth/providers/auth_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _RecordingAuthNotifier extends AuthNotifier {
  var signOutCalls = 0;

  @override
  Future<AuthStatus> build() async => AuthStatus.authenticated;

  @override
  Future<void> signOut() async {
    signOutCalls++;
    state = const AsyncValue.data(AuthStatus.unauthenticated);
  }
}

class _AccessApi implements AdminOperatorApi {
  var calls = 0;

  @override
  Future<AdminOperatorResponse> invoke(Map<String, dynamic> body) async {
    calls++;
    return const AdminOperatorResponse(200, {'is_admin': true});
  }
}

final class _ShellCardSource implements CardDataSource {
  @override
  Future<void> act(CardReviewAction action) async {}

  @override
  Future<CardReviewPage> list(CardReviewQuery query) async => CardReviewPage(
    lane: query.lane,
    items: const [],
    page: 1,
    limit: 25,
    hasMore: false,
    refreshedAt: DateTime.utc(2026, 8, 19),
  );
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required FutureOr<AdminAccess> Function(Ref ref) access,
  Size size = const Size(1280, 900),
  double textScale = 1,
  Future<void> Function()? onAuthenticationRequired,
  VoidCallback? onAccessDenied,
  List<Override> extraOverrides = const [],
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [adminAccessProvider.overrideWith(access), ...extraOverrides],
      child: MaterialApp(
        theme: AppTheme.work,
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: AdminOperatorScreen(
            onAuthenticationRequired: onAuthenticationRequired,
            onAccessDenied: onAccessDenied,
            cardDataSource: _ShellCardSource(),
            inboxLoader: () async => InboxSnapshot(
              items: const [],
              partialFailures: const [],
              refreshedAt: DateTime.utc(2026, 8, 19),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  test('adminAccessProvider delegates access to the repository', () async {
    final api = _AccessApi();
    final container = ProviderContainer(
      overrides: [
        adminOperatorRepositoryProvider.overrideWithValue(
          AdminOperatorRepository(api),
        ),
      ],
    );
    addTearDown(container.dispose);

    final access = await container.read(adminAccessProvider.future);

    expect(access.isAdmin, isTrue);
    expect(api.calls, 1);
  });

  testWidgets('loading access shows a stable semantic skeleton', (
    tester,
  ) async {
    final pending = Completer<AdminAccess>();
    addTearDown(() {
      if (!pending.isCompleted) {
        pending.complete(const AdminAccess(isAdmin: true));
      }
    });

    await _pumpScreen(tester, access: (_) => pending.future);
    await tester.pump();

    expect(
      find.bySemanticsLabel('Checking administrator access'),
      findsOneWidget,
    );
    expect(find.byType(AdminWorkspaceNavigation), findsNothing);
  });

  testWidgets('authorized operator opens on Action Inbox', (tester) async {
    await _pumpScreen(
      tester,
      access: (_) async => const AdminAccess(isAdmin: true),
    );
    await tester.pumpAndSettle();

    expect(find.text('Action Inbox'), findsWidgets);
    expect(find.text('Customers'), findsOneWidget);
    expect(find.text('Card Data'), findsOneWidget);
    expect(find.text('System'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('admin-section-content')),
        matching: find.text('Action Inbox'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('all four workspace sections can be selected', (tester) async {
    await _pumpScreen(
      tester,
      size: const Size(768, 900),
      access: (_) async => const AdminAccess(isAdmin: true),
    );
    await tester.pumpAndSettle();

    for (final entry in const [
      ('Customers', AdminWorkspaceSection.customers),
      ('Card Data', AdminWorkspaceSection.cardData),
      ('System', AdminWorkspaceSection.system),
      ('Action Inbox', AdminWorkspaceSection.inbox),
    ]) {
      await tester.tap(find.byKey(Key('admin-section-${entry.$2.name}')));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const Key('admin-section-content')),
          matching: find.text(entry.$1),
        ),
        findsOneWidget,
      );
    }
  });

  testWidgets('401 invokes its injected handler once per occurrence', (
    tester,
  ) async {
    var calls = 0;
    await _pumpScreen(
      tester,
      access: (_) async => throw AdminAuthenticationRequired(),
      onAuthenticationRequired: () async => calls++,
    );
    await tester.pumpAndSettle();
    await tester.pump();

    expect(calls, 1);
    expect(find.text('Sign in again to continue.'), findsOneWidget);
  });

  testWidgets('401 defaults to clearing the stale local session', (
    tester,
  ) async {
    late _RecordingAuthNotifier auth;
    await _pumpScreen(
      tester,
      access: (_) async => throw AdminAuthenticationRequired(),
      extraOverrides: [
        authNotifierProvider.overrideWith(
          () => auth = _RecordingAuthNotifier(),
        ),
      ],
    );
    await tester.pumpAndSettle();

    expect(auth.signOutCalls, 1);
  });

  testWidgets('401 session clear lets the app router lead to sign-in', (
    tester,
  ) async {
    final auth = _RecordingAuthNotifier();
    final container = ProviderContainer(
      overrides: [
        adminAccessProvider.overrideWith(
          (_) async => throw AdminAuthenticationRequired(),
        ),
        authNotifierProvider.overrideWith(() => auth),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authNotifierProvider.future);
    final router = container.read(routerProvider);
    router.go('/app/admin2');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const CardCompassApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(auth.signOutCalls, 1);
    expect(router.routeInformationProvider.value.uri.path, '/login');
  });

  testWidgets('403 returns to ordinary app without signing out', (
    tester,
  ) async {
    final auth = _RecordingAuthNotifier();
    final router = GoRouter(
      initialLocation: '/app/admin2',
      routes: [
        GoRoute(path: '/app', builder: (_, _) => const Text('Ordinary app')),
        GoRoute(
          path: '/app/admin2',
          builder: (_, _) => const AdminOperatorScreen(),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          adminAccessProvider.overrideWith(
            (_) async => throw AdminAccessDenied(),
          ),
          authNotifierProvider.overrideWith(() => auth),
        ],
        child: MaterialApp.router(theme: AppTheme.work, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ordinary app'), findsOneWidget);
    expect(auth.signOutCalls, 0);
  });

  testWidgets('retryable failure stays safe and can retry', (tester) async {
    var attempts = 0;
    await _pumpScreen(
      tester,
      access: (_) async {
        attempts++;
        if (attempts == 1) throw const AdminRequestFailed('request_failed');
        return const AdminAccess(isAdmin: true);
      },
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Administrator access could not be checked.'),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(find.byType(AdminWorkspaceNavigation), findsOneWidget);
  });

  for (final width in [390.0, 768.0, 1280.0]) {
    testWidgets('workspace adapts without overflow at ${width.toInt()}px', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        size: Size(width, 900),
        access: (_) async => const AdminAccess(isAdmin: true),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        find.byKey(
          Key(
            width >= 1024
                ? 'admin-wide-navigation'
                : 'admin-compact-navigation',
          ),
        ),
        findsOneWidget,
      );
    });
  }

  testWidgets('compact selector remains usable at 2.0 text scale', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      size: const Size(390, 900),
      textScale: 2,
      access: (_) async => const AdminAccess(isAdmin: true),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    for (final section in AdminWorkspaceSection.values) {
      expect(
        tester.getSize(find.byKey(Key('admin-section-${section.name}'))).height,
        greaterThanOrEqualTo(44),
      );
    }
  });

  testWidgets('section controls are keyboard operable', (tester) async {
    await _pumpScreen(
      tester,
      size: const Size(768, 900),
      access: (_) async => const AdminAccess(isAdmin: true),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(
      find.descendant(
        of: find.byKey(const Key('admin-section-content')),
        matching: find.text('Customers'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('section controls expose unique selected semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pumpScreen(
      tester,
      size: const Size(1280, 900),
      access: (_) async => const AdminAccess(isAdmin: true),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getSemantics(find.byKey(const Key('admin-section-inbox'))),
      matchesSemantics(
        label: 'Admin section: Action Inbox',
        isButton: true,
        hasSelectedState: true,
        isSelected: true,
        hasTapAction: true,
      ),
    );
    final labels = AdminWorkspaceSection.values.map((section) {
      return tester
          .getSemantics(find.byKey(Key('admin-section-${section.name}')))
          .label;
    }).toSet();
    expect(labels, hasLength(4));
    semantics.dispose();
  });

  testWidgets('ordinary navigation has no admin2 destination', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.work,
        home: Scaffold(
          body: AppSideRail(selectedIndex: 0, onTap: (_) {}),
          bottomNavigationBar: AppBottomNav(selectedIndex: 0, onTap: (_) {}),
        ),
      ),
    );

    expect(find.textContaining('Admin'), findsNothing);
    expect(find.text('Catalog Review'), findsNothing);
  });
}
