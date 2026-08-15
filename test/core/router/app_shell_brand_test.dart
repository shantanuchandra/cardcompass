import 'dart:io';
import 'dart:ui' show Tristate;

import 'package:cardcompass/core/router/app_router.dart';
import 'package:cardcompass/core/router/app_tab_selection.dart';
import 'package:cardcompass/features/dashboard/screens/dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

class _TabHarness extends StatefulWidget {
  const _TabHarness({required this.child});

  final Widget child;

  @override
  State<_TabHarness> createState() => _TabHarnessState();
}

class _TabHarnessState extends State<_TabHarness> {
  var _tab = AppTab.dashboard;

  @override
  Widget build(BuildContext context) => AppTabSelection(
    onSelect: (tab) => setState(() => _tab = tab),
    child: Column(
      children: [
        Text('Rendered destination: ${_tab.name}'),
        Expanded(child: widget.child),
      ],
    ),
  );
}

class _MobileNavHarness extends StatefulWidget {
  const _MobileNavHarness();

  @override
  State<_MobileNavHarness> createState() => _MobileNavHarnessState();
}

class _MobileNavHarnessState extends State<_MobileNavHarness> {
  var _selectedIndex = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Text(
        'Rendered destination: ${AppTab.values[_selectedIndex].name}',
      ),
    ),
    bottomNavigationBar: AppBottomNav(
      selectedIndex: _selectedIndex,
      onTap: (index) => setState(() => _selectedIndex = index),
    ),
  );
}

void main() {
  final source = File('lib/core/router/app_router.dart').readAsStringSync();

  test('desktop and mobile navigation use semantic brand roles', () {
    expect(source, contains('BrandColors.inkSoft'));
    expect(source, contains('BrandColors.signal'));
    expect(source, contains('BrandColors.mutedPaper'));
    expect(source, isNot(contains('AppColors.neonCyan')));
  });

  test('shell identity uses the shared compass mark', () {
    expect(source, contains('BrandCompassMark'));
  });

  test('navigation keeps existing routing behavior and accessible targets', () {
    expect(source, contains("replaceBrowserHistory('#\${_kTabPaths[i]}')"));
    expect(source, contains('height: navigationHeight'));
    expect(source, contains('Semantics('));
  });

  testWidgets('mobile shell renders concise labels and selects a destination', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: _MobileNavHarness()));

    for (final label in const [
      'Dashboard',
      'Cards',
      'Transactions',
      'Movies',
      'Settings',
    ]) {
      expect(find.text(label), findsOneWidget);
      expect(tester.widget<Text>(find.text(label)).style?.fontSize, 14);
    }

    await tester.tap(find.text('Transactions'));
    await tester.pump();
    expect(find.text('Rendered destination: transactions'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop rail action labels meet the 14px text floor', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AppSideRail(selectedIndex: 0, onTap: (_) {})),
      ),
    );

    final label = tester.widget<Text>(find.text('Dashboard').last);
    expect(label.style?.fontSize, 14);
  });

  testWidgets('mobile semantic item announces once and activates its tab', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(const MaterialApp(home: _MobileNavHarness()));

    final node = tester.getSemantics(find.text('Transactions'));
    expect(node.label, 'Transactions');
    expect(node.flagsCollection.isSelected, Tristate.isFalse);
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    tester.semantics.tap(find.semantics.byLabel('Transactions'));
    await tester.pump();
    expect(find.text('Rendered destination: transactions'), findsOneWidget);
    expect(
      tester.getSemantics(find.text('Transactions')).flagsCollection.isSelected,
      Tristate.isTrue,
    );
    semantics.dispose();
  });

  testWidgets('rail semantic item announces once and activates its tab', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var selectedIndex = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppSideRail(
            selectedIndex: selectedIndex,
            onTap: (index) => selectedIndex = index,
          ),
        ),
      ),
    );

    final node = tester.getSemantics(find.text('Transactions'));
    expect(node.label, 'Transactions');
    expect(
      tester.getSemantics(find.text('Dashboard')).flagsCollection.isSelected,
      Tristate.isTrue,
    );
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    tester.semantics.tap(find.semantics.byLabel('Transactions'));
    expect(selectedIndex, 2);
    semantics.dispose();
  });

  testWidgets('mobile Transactions label stays whole at 390px and 2x text', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: const _MobileNavHarness(),
        ),
      ),
    );

    final label = tester.widget<Text>(find.text('Transactions'));
    final paragraph = tester.renderObject<RenderParagraph>(
      find.text('Transactions'),
    );
    expect(label.style?.fontSize, 14);
    expect(label.maxLines, 2);
    expect(label.overflow, isNot(TextOverflow.ellipsis));
    expect(
      paragraph
          .getBoxesForSelection(
            const TextSelection(baseOffset: 0, extentOffset: 12),
          )
          .length,
      greaterThanOrEqualTo(2),
    );
    expect(paragraph.size.height, greaterThanOrEqualTo(48));
    expect(
      tester.getSemantics(find.text('Transactions')).label,
      'Transactions',
    );
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('Dashboard section actions select their rendered app tabs', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: _TabHarness(
          child: Builder(
            builder: (context) => Column(
              children: [
                DashboardSectionHeader(
                  title: 'Your Cards',
                  action: 'Manage',
                  onTap: () => AppTabSelection.of(context).select(AppTab.cards),
                ),
                DashboardSectionHeader(
                  title: 'Recent Spend',
                  action: 'View All',
                  onTap: () =>
                      AppTabSelection.of(context).select(AppTab.transactions),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Manage'));
    await tester.pump();
    expect(find.text('Rendered destination: cards'), findsOneWidget);

    await tester.tap(find.text('View All'));
    await tester.pump();
    expect(find.text('Rendered destination: transactions'), findsOneWidget);
  });
}
