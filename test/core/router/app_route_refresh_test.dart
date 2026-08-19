import 'package:cardcompass/core/router/app_router.dart';
import 'package:cardcompass/features/auth/providers/auth_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _AuthenticatedAuthNotifier extends AuthNotifier {
  @override
  Future<AuthStatus> build() async => AuthStatus.authenticated;
}

void main() {
  test('every visible app tab URL resolves after a browser refresh', () async {
    final container = ProviderContainer(
      overrides: [
        authNotifierProvider.overrideWith(_AuthenticatedAuthNotifier.new),
      ],
    );
    addTearDown(container.dispose);

    await container.read(authNotifierProvider.future);
    final router = container.read(routerProvider);

    for (final path in const [
      '/app',
      '/app/cards',
      '/app/cards/add',
      '/app/cards/card-123',
      '/app/transactions',
      '/app/movie-deals',
      '/app/settings',
    ]) {
      final match = router.configuration.findMatch(Uri.parse(path));
      expect(match.error, isNull, reason: '$path must survive refresh');
      expect(match.uri.path, path);
    }
  });

  test('admin2 survives a browser refresh', () async {
    final container = ProviderContainer(
      overrides: [
        authNotifierProvider.overrideWith(_AuthenticatedAuthNotifier.new),
      ],
    );
    addTearDown(container.dispose);

    await container.read(authNotifierProvider.future);
    final router = container.read(routerProvider);
    final match = router.configuration.findMatch(Uri.parse('/app/admin2'));

    expect(match.error, isNull);
    expect(match.uri.path, '/app/admin2');
  });

  testWidgets('pushed card routes update the browser-visible location', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        authNotifierProvider.overrideWith(_AuthenticatedAuthNotifier.new),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authNotifierProvider.future);
    container.read(routerProvider);

    final router = GoRouter(
      initialLocation: '/app/cards',
      routes: [
        GoRoute(
          path: '/app/cards',
          builder: (context, _) => TextButton(
            onPressed: () => context.push('/app/cards/add'),
            child: const Text('Add card'),
          ),
          routes: [
            GoRoute(
              path: 'add',
              builder: (_, _) => const Text('Add Card screen'),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    await tester.tap(find.text('Add card'));
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/app/cards/add');
  });
}
