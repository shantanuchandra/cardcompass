import 'package:cardcompass/core/router/app_router.dart';
import 'package:cardcompass/features/auth/providers/auth_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _AuthenticatedAuthNotifier extends AuthNotifier {
  @override
  Future<AuthStatus> build() async => AuthStatus.authenticated;
}

void main() {
  test('legacy catalog route redirects to the card-data workspace', () async {
    final container = ProviderContainer(
      overrides: [
        authNotifierProvider.overrideWith(_AuthenticatedAuthNotifier.new),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authNotifierProvider.future);
    final router = container.read(routerProvider);
    final legacy = router.configuration.findMatch(
      Uri.parse('/app/admin/catalog-review'),
    );

    expect(legacy.error, isNull);
    expect(legacyCatalogReviewDestination, '/app/admin2?section=card-data');
  });

  test('direct admin2 route remains mounted for its access check', () async {
    final container = ProviderContainer(
      overrides: [
        authNotifierProvider.overrideWith(_AuthenticatedAuthNotifier.new),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authNotifierProvider.future);
    final router = container.read(routerProvider);
    final direct = router.configuration.findMatch(Uri.parse('/app/admin2'));

    expect(direct.error, isNull);
    expect(direct.uri.path, '/app/admin2');
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
