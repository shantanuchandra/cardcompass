import 'package:cardcompass/core/theme/brand_components.dart';
import 'package:cardcompass/core/theme/app_theme.dart';
import 'package:cardcompass/core/theme/brand_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget host(Widget child) => MaterialApp(
    theme: AppTheme.work,
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

  testWidgets('disabled action row announces unavailable and has no chevron', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(const BrandActionRow(title: 'Notifications', unavailable: true)),
    );

    expect(find.text('Coming soon'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
    expect(
      tester.getSemantics(find.byType(BrandActionRow)),
      matchesSemantics(
        label: 'Notifications, unavailable',
        isButton: true,
        hasEnabledState: true,
        isEnabled: false,
      ),
    );
  });

  testWidgets('state view exposes a minimum-size recovery action', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        BrandStateView(
          title: 'No matching cards',
          message: 'Try a different category.',
          icon: Icons.search_off_rounded,
          actionLabel: 'Clear filters',
          onAction: () {},
        ),
      ),
    );

    expect(find.text('No matching cards'), findsOneWidget);
    expect(find.text('Try a different category.'), findsOneWidget);
    expect(find.byIcon(Icons.search_off_rounded), findsOneWidget);
    expect(
      tester
          .getSize(find.widgetWithText(OutlinedButton, 'Clear filters'))
          .height,
      greaterThanOrEqualTo(44),
    );
  });

  testWidgets('page header and metric establish a clear summary hierarchy', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const Column(
          children: [
            BrandPageHeader(
              eyebrow: 'Wallet overview',
              title: 'Your rewards at a glance',
              description: 'A concise summary of your earning potential.',
            ),
            BrandMetric(label: 'Potential reward', value: '₹1,200'),
          ],
        ),
      ),
    );

    expect(find.text('WALLET OVERVIEW'), findsOneWidget);
    expect(find.text('Your rewards at a glance'), findsOneWidget);
    expect(find.text('Potential reward'), findsOneWidget);
    expect(find.text('₹1,200'), findsOneWidget);
  });

  testWidgets('metric supporting text and action descriptions stay at 14px', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        Column(
          children: [
            const BrandMetric(
              label: 'Potential reward',
              value: '₹1,200',
              supportingText: 'Based on your selected category',
            ),
            BrandActionRow(
              title: 'Manage cards',
              description: 'Update your wallet',
              onTap: () {},
            ),
          ],
        ),
      ),
    );

    expect(
      tester
          .widget<Text>(find.text('Based on your selected category'))
          .style!
          .fontSize,
      14,
    );
    expect(
      tester.widget<Text>(find.text('Update your wallet')).style!.fontSize,
      14,
    );
  });

  test('action row requires exactly one interaction state', () {
    expect(() => BrandActionRow(title: 'Notifications'), throwsAssertionError);
    expect(
      () => BrandActionRow(
        title: 'Notifications',
        unavailable: true,
        onTap: () {},
      ),
      throwsAssertionError,
    );
  });

  testWidgets('evidence strip uses readable evidence type sizes', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const BrandEvidenceStrip(
          rows: [BrandEvidence(label: 'Expected return', value: '₹120')],
        ),
      ),
    );

    expect(
      tester.widget<Text>(find.text('EXPECTED RETURN')).style!.fontSize,
      12,
    );
    expect(
      tester.widget<Text>(find.text('₹120')).style!.fontSize,
      greaterThanOrEqualTo(14),
    );
  });
}
