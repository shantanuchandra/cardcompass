import 'package:cardcompass/core/theme/brand_components.dart';
import 'package:cardcompass/core/theme/brand_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget host(Widget child) => MaterialApp(
    theme: ThemeData.light(),
    home: Scaffold(body: child),
  );

  testWidgets('brand surface assigns a semantic background', (tester) async {
    await tester.pumpWidget(
      host(
        const BrandSurface(
          key: Key('surface'),
          tone: BrandSurfaceTone.ledger,
          child: Text('Recommendation'),
        ),
      ),
    );

    final decoration =
        tester
                .widget<Container>(
                  find.descendant(
                    of: find.byKey(const Key('surface')),
                    matching: find.byType(Container),
                  ),
                )
                .decoration
            as BoxDecoration;
    expect(decoration.color, BrandColors.ledger);
    expect(decoration.borderRadius, BorderRadius.circular(BrandRadius.card));
    expect(find.text('Recommendation'), findsOneWidget);
  });

  testWidgets('section header exposes hierarchy as selectable text', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const BrandSectionHeader(
          eyebrow: 'YOUR WALLET',
          title: 'Make the next swipe count.',
          description: 'Recommendations explain the rule behind the result.',
        ),
      ),
    );

    expect(find.byType(SelectionArea), findsOneWidget);
    expect(find.text('YOUR WALLET'), findsOneWidget);
    expect(find.text('Make the next swipe count.'), findsOneWidget);
  });

  testWidgets('evidence strip renders label-value pairs in order', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const BrandEvidenceStrip(
          rows: [
            BrandEvidence(label: 'Expected return', value: '₹120'),
            BrandEvidence(label: 'Rule checked', value: 'Today'),
          ],
        ),
      ),
    );

    expect(find.text('EXPECTED RETURN'), findsOneWidget);
    expect(find.text('₹120'), findsOneWidget);
    expect(find.text('RULE CHECKED'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
  });

  testWidgets('status chip provides a compact semantic label', (tester) async {
    await tester.pumpWidget(
      host(
        const BrandStatusChip(
          label: 'Recommended',
          tone: BrandStatusTone.success,
        ),
      ),
    );

    final semantics = tester.widget<Semantics>(
      find
          .ancestor(
            of: find.text('Recommended'),
            matching: find.byType(Semantics),
          )
          .first,
    );
    expect(semantics.properties.label, 'Recommended');
    expect(find.text('Recommended'), findsOneWidget);
  });
}
