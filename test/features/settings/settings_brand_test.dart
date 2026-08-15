import 'dart:io';
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
}
