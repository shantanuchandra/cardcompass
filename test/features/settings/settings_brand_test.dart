import 'dart:io';
import 'package:cardcompass/core/theme/app_theme.dart';
import 'package:cardcompass/core/theme/brand_components.dart';
import 'package:cardcompass/features/settings/screens/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File(
    'lib/features/settings/screens/settings_screen.dart',
  ).readAsStringSync();
  test('settings uses quiet paper surfaces and semantic destructive color', () {
    expect(source, contains('BrandColors.paper'));
    expect(source, contains('BrandColors.error'));
    expect(source, isNot(contains('AppColors.neonCyan')));
  });

  test('successful reset captures shared refresh actions before the RPC', () {
    const refreshCapture =
        'final refreshImportedData = ref.read(importedDataRefreshProvider);';
    const containerCapture =
        'final providerContainer = ProviderScope.containerOf(';
    const resetCall = ').resetAll();';
    const refreshCall = 'refreshImportedData();';
    const gmailInvalidation =
        'providerContainer.invalidate(gmailSyncProvider);';

    final refreshCaptureIndex = source.indexOf(refreshCapture);
    final containerCaptureIndex = source.indexOf(containerCapture);
    final resetCallIndex = source.indexOf(resetCall);
    final refreshCallIndex = source.indexOf(refreshCall);
    final gmailInvalidationIndex = source.indexOf(gmailInvalidation);

    expect(refreshCaptureIndex, greaterThanOrEqualTo(0));
    expect(containerCaptureIndex, greaterThanOrEqualTo(0));
    expect(resetCallIndex, greaterThan(refreshCaptureIndex));
    expect(resetCallIndex, greaterThan(containerCaptureIndex));
    expect(refreshCallIndex, greaterThan(resetCallIndex));
    expect(gmailInvalidationIndex, greaterThan(refreshCallIndex));
  });

  testWidgets('every enabled settings row has an action', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.work, home: const SettingsActionList()),
    );

    for (final title in const [
      'Privacy',
      'Data & Security',
      'Terms',
      'About',
    ]) {
      final row = find.widgetWithText(BrandActionRow, title);
      expect(tester.widget<BrandActionRow>(row).onTap, isNotNull);
    }

    final notifications = tester.widget<BrandActionRow>(
      find.widgetWithText(BrandActionRow, 'Notifications'),
    );
    expect(notifications.unavailable, isTrue);
    expect(notifications.onTap, isNull);
  });

  testWidgets('settings offers a guarded CardCompass data reset', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.work, home: const SettingsActionList()),
    );

    expect(find.text('Delete all CardCompass data'), findsOneWidget);
    await tester.tap(find.text('Delete all CardCompass data'));
    await tester.pumpAndSettle();

    expect(find.text('Type DELETE to confirm'), findsOneWidget);
    final deleteButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Delete data'),
    );
    expect(deleteButton.onPressed, isNull);
  });

  testWidgets('settings actions use the public routes and version dialog', (
    tester,
  ) async {
    final opened = <Uri>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.work,
        home: SettingsActionList(
          onOpenUri: (uri) async {
            opened.add(uri);
            return true;
          },
        ),
      ),
    );

    await tester.tap(find.text('Privacy'));
    await tester.pump();
    expect(opened.single.path, '/privacy/');

    await tester.tap(find.text('About'));
    await tester.pumpAndSettle();
    expect(find.text('CardCompass'), findsOneWidget);
    expect(find.text('2.0.0'), findsOneWidget);
  });
}
