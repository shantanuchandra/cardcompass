import 'package:cardcompass/core/router/app_router.dart';
import 'package:cardcompass/features/admin2/card_data/card_data_section.dart';
import 'package:cardcompass/features/admin2/data/admin_operator_api.dart';
import 'package:cardcompass/features/admin2/data/admin_operator_repository.dart';
import 'package:cardcompass/features/admin2/inbox/action_inbox_section.dart';
import 'package:cardcompass/features/admin2/models/admin_access.dart';
import 'package:cardcompass/features/admin2/providers/admin_access_provider.dart';
import 'package:cardcompass/features/auth/providers/auth_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _AuthenticatedAuthNotifier extends AuthNotifier {
  @override
  Future<AuthStatus> build() async => AuthStatus.authenticated;
}

class _RouterAdminApi implements AdminOperatorApi {
  @override
  Future<AdminOperatorResponse> invoke(Map<String, dynamic> body) async {
    return switch (body['action']) {
      'card-review-list' => AdminOperatorResponse(200, {
        'lane': body['lane'],
        'items': const [],
        'page': 1,
        'limit': 25,
        'has_more': false,
      }),
      'inbox-list' => const AdminOperatorResponse(200, {
        'items': [],
        'partial_failures': [],
        'refreshed_at': '2026-08-19T00:00:00Z',
      }),
      _ => const AdminOperatorResponse(400, {'error': 'invalid_request'}),
    };
  }
}

Future<(ProviderContainer, GoRouter)> _pumpRouter(
  WidgetTester tester,
  String location,
) async {
  final container = ProviderContainer(
    overrides: [
      authNotifierProvider.overrideWith(_AuthenticatedAuthNotifier.new),
      adminAccessProvider.overrideWith(
        (_) async => const AdminAccess(isAdmin: true),
      ),
      adminOperatorRepositoryProvider.overrideWithValue(
        AdminOperatorRepository(_RouterAdminApi()),
      ),
    ],
  );
  await container.read(authNotifierProvider.future);
  final router = container.read(routerProvider);
  router.go(location);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return (container, router);
}

void main() {
  testWidgets('legacy catalog route opens the selected Card Data workspace', (
    tester,
  ) async {
    final (container, router) = await _pumpRouter(
      tester,
      '/app/admin/catalog-review',
    );
    addTearDown(router.dispose);
    addTearDown(container.dispose);

    expect(
      router.routeInformationProvider.value.uri.toString(),
      '/app/admin2?section=card-data',
    );
    expect(find.byType(CardDataSection), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('admin-section-content')),
        matching: find.text('Card Data'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('direct admin2 route defaults to Action Inbox', (tester) async {
    final (container, router) = await _pumpRouter(tester, '/app/admin2');
    addTearDown(router.dispose);
    addTearDown(container.dispose);

    expect(router.routeInformationProvider.value.uri.toString(), '/app/admin2');
    expect(find.byType(ActionInboxSection), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('admin-section-content')),
        matching: find.text('Action Inbox'),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'desktop rail exposes Admin only as an allowed secondary action',
    (tester) async {
      var opened = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppSideRail(
              selectedIndex: 0,
              onTap: (_) {},
              showAdmin: false,
              onAdminTap: () => opened = true,
            ),
          ),
        ),
      );
      expect(find.text('Admin'), findsNothing);
      expect(find.byType(AppSideRail), findsOneWidget);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppSideRail(
              selectedIndex: 0,
              onTap: (_) {},
              showAdmin: true,
              onAdminTap: () => opened = true,
            ),
          ),
        ),
      );
      expect(find.text('Admin'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
      expect(tester.getSize(find.text('Admin')).height, lessThanOrEqualTo(48));

      await tester.tap(find.text('Admin'));
      expect(opened, isTrue);
    },
  );
}
