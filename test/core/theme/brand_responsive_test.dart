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

  testWidgets('content frame can expand data views without stretching prose', (
    tester,
  ) async {
    await pumpBrand(
      tester,
      width: 1600,
      child: const BrandContentFrame(
        mode: BrandContentMode.fullWidthData,
        child: Text('Data view'),
      ),
    );

    expect(
      tester.getSize(find.byType(BrandContentFrame)).width,
      greaterThan(1200),
    );
  });

  testWidgets(
    'constrained content frame keeps prose readable on wide screens',
    (tester) async {
      await pumpBrand(
        tester,
        width: 1600,
        child: const BrandContentFrame(
          child: SizedBox(
            key: Key('prose-width'),
            width: double.infinity,
            child: Text('Measured prose'),
          ),
        ),
      );

      expect(
        tester.getSize(find.byKey(const Key('prose-width'))).width,
        lessThan(1100),
      );
    },
  );

  for (final width in [390.0, 768.0, 1280.0]) {
    for (final textScale in [1.0, 1.5, 2.0]) {
      testWidgets(
        'content frame remains usable at ${width.toInt()}px / $textScale×',
        (tester) async {
          await pumpBrand(
            tester,
            width: width,
            textScale: textScale,
            child: const BrandContentFrame(child: Text('Readable content')),
          );

          expect(find.text('Readable content'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
