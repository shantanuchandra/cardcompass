import 'package:cardcompass/app.dart';
import 'package:cardcompass/core/router/app_router.dart';
import 'package:cardcompass/core/theme/app_theme.dart';
import 'package:cardcompass/core/theme/brand_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app respects platform text scaling', (tester) async {
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (_, _) => const SizedBox.shrink())],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: ProviderScope(
          overrides: [routerProvider.overrideWithValue(router)],
          child: const CardCompassApp(),
        ),
      ),
    );

    expect(
      MediaQuery.textScalerOf(tester.element(find.byType(MaterialApp))),
      const TextScaler.linear(2),
    );
  });

  testWidgets('app applies the marketing theme to the splash surface', (
    tester,
  ) async {
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (_, _) => const SizedBox.shrink())],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [routerProvider.overrideWithValue(router)],
        child: const CardCompassApp(),
      ),
    );

    expect(
      Theme.of(tester.element(find.byType(SizedBox))).brightness,
      Brightness.dark,
    );
  });

  test('work theme is light and marketing theme is dark', () {
    expect(AppTheme.work.brightness, Brightness.light);
    expect(AppTheme.marketing.brightness, Brightness.dark);
  });

  test('editorial theme uses the canonical brand roles', () {
    final theme = AppTheme.editorial;

    expect(theme.scaffoldBackgroundColor, BrandColors.ink);
    expect(theme.colorScheme.primary, BrandColors.signal);
    expect(theme.colorScheme.secondary, BrandColors.reward);
    expect(theme.colorScheme.surface, BrandColors.paper);
    expect(theme.colorScheme.onSurface, BrandColors.ink);
    expect(theme.cardTheme.color, BrandColors.paper);
    expect(theme.appBarTheme.backgroundColor, BrandColors.ink);
  });

  test(
    'issuer identity colors remain factual and separate from UI accents',
    () {
      expect(AppTheme.issuerColor('hdfc'), const Color(0xFF004C8F));
      expect(AppTheme.issuerColor('unknown'), BrandColors.mutedInk);
    },
  );

  test('primary controls use compact editorial geometry', () {
    final theme = AppTheme.editorial;
    final style = theme.elevatedButtonTheme.style!;

    expect(style.backgroundColor!.resolve({}), BrandColors.signal);
    expect(style.foregroundColor!.resolve({}), BrandColors.ink);
    expect(style.minimumSize!.resolve({}), const Size(0, 48));
    final shape = style.shape!.resolve({})! as RoundedRectangleBorder;
    expect(shape.borderRadius, BorderRadius.circular(BrandRadius.control));
  });
}
