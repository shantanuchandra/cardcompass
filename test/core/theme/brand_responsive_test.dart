import 'package:cardcompass/core/theme/app_theme.dart';
import 'package:cardcompass/core/theme/brand_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpBrand(
    WidgetTester tester, {
    required Widget child,
    double width = 1280,
    double textScale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.work,
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(body: child),
        ),
      ),
    );
  }

  testWidgets('ResponsiveValueRow stacks at 390px and 200 percent text', (
    tester,
  ) async {
    await pumpBrand(
      tester,
      width: 390,
      textScale: 2,
      child: const ResponsiveValueRow(children: [Text('One'), Text('Two')]),
    );

    expect(
      tester.getTopLeft(find.text('Two')).dy,
      greaterThan(tester.getTopLeft(find.text('One')).dy),
    );
  });

  testWidgets('ResponsiveValueRow stays horizontal at desktop width', (
    tester,
  ) async {
    await pumpBrand(
      tester,
      width: 1280,
      child: const ResponsiveValueRow(children: [Text('One'), Text('Two')]),
    );

    expect(
      tester.getTopLeft(find.text('Two')).dy,
      tester.getTopLeft(find.text('One')).dy,
    );
  });

  testWidgets('ResponsiveValueRow applies its requested horizontal spacing', (
    tester,
  ) async {
    await pumpBrand(
      tester,
      width: 1280,
      child: const ResponsiveValueRow(
        spacing: 40,
        children: [
          Text('One', key: Key('spaced-one')),
          Text('Two', key: Key('spaced-two')),
        ],
      ),
    );

    final one = tester.getRect(find.byKey(const Key('spaced-one')));
    final two = tester.getRect(find.byKey(const Key('spaced-two')));
    expect(two.left - one.right, 40);
  });

  testWidgets(
    'content frame gives data and prose their intended inner widths',
    (tester) async {
      await pumpBrand(
        tester,
        width: 1600,
        child: const Column(
          children: [
            BrandContentFrame(
              mode: BrandContentMode.fullWidthData,
              child: SizedBox(
                key: Key('data-width'),
                width: double.infinity,
                child: Text('Data view'),
              ),
            ),
            BrandContentFrame(
              child: SizedBox(
                key: Key('prose-width'),
                width: double.infinity,
                child: Text('Measured prose'),
              ),
            ),
          ],
        ),
      );

      expect(tester.getSize(find.byKey(const Key('data-width'))).width, 1440);
      expect(tester.getSize(find.byKey(const Key('prose-width'))).width, 960);
    },
  );

  for (final width in [390.0, 768.0, 1280.0]) {
    for (final textScale in [1.0, 1.5, 2.0]) {
      testWidgets(
        'shared primitives remain responsive at ${width.toInt()}px / $textScale×',
        (tester) async {
          await pumpBrand(
            tester,
            width: width,
            textScale: textScale,
            child: SingleChildScrollView(
              child: BrandContentFrame(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const BrandPageHeader(
                      eyebrow: 'Wallet',
                      title: 'Rewards overview',
                      description: 'See your next best card.',
                      trailing: Text('Manage'),
                    ),
                    const SizedBox(height: 24),
                    const BrandMetric(
                      label: 'Potential reward',
                      value: '₹1,200',
                      supportingText: 'For your selected category',
                    ),
                    const SizedBox(height: 24),
                    BrandActionRow(
                      title: 'Manage cards',
                      description: 'Update your wallet',
                      onTap: () {},
                    ),
                    const BrandActionRow(
                      title: 'Notifications',
                      unavailable: true,
                    ),
                    const SizedBox(height: 24),
                    BrandStateView(
                      title: 'No matching cards',
                      message: 'Try a different category.',
                      icon: Icons.search_off_rounded,
                      actionLabel: 'Clear filters',
                      onAction: () {},
                    ),
                    const SizedBox(height: 24),
                    const BrandEvidenceStrip(
                      rows: [
                        BrandEvidence(label: 'Expected return', value: '₹120'),
                      ],
                    ),
                    const SizedBox(height: 24),
                    const ResponsiveValueRow(
                      children: [
                        Text('First value', key: Key('matrix-first')),
                        Text('Second value', key: Key('matrix-second')),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );

          final first = tester.getTopLeft(
            find.byKey(const Key('matrix-first')),
          );
          final second = tester.getTopLeft(
            find.byKey(const Key('matrix-second')),
          );
          final shouldStack = width < 600 || textScale >= 1.5;
          if (shouldStack) {
            expect(second.dy, greaterThan(first.dy));
          } else {
            expect(second.dy, first.dy);
            expect(second.dx, greaterThan(first.dx));
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
