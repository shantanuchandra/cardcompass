import 'package:cardcompass/core/theme/app_theme.dart';
import 'package:cardcompass/core/theme/brand_components.dart';
import 'package:cardcompass/features/settings/screens/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('settings hides Admin unless database-backed access is allowed', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.work,
        home: const Scaffold(body: SettingsActionList(showAdmin: false)),
      ),
    );
    expect(find.text('Admin'), findsNothing);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.work,
        home: Scaffold(
          body: SettingsActionList(showAdmin: true, onOpenAdmin: () {}),
        ),
      ),
    );
    expect(find.widgetWithText(BrandActionRow, 'Admin'), findsOneWidget);
  });

  testWidgets(
    'Admin settings entry is semantic, keyboard-safe, and actionable',
    (tester) async {
      var opened = false;
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.work,
          home: Scaffold(
            body: SettingsActionList(
              showAdmin: true,
              onOpenAdmin: () => opened = true,
            ),
          ),
        ),
      );

      final row = find.widgetWithText(BrandActionRow, 'Admin');
      expect(tester.getSemantics(row).label, contains('Admin'));
      expect(tester.getSize(row).height, greaterThanOrEqualTo(44));
      await tester.tap(find.text('Admin'));
      expect(opened, isTrue);
      semantics.dispose();
    },
  );
}
