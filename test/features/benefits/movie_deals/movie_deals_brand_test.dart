import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File(
    'lib/features/benefits/movie_deals/screens/movie_deals_screen.dart',
  ).readAsStringSync();
  test('movie offers use paper tickets and reward evidence', () {
    expect(source, contains('BrandColors.paper'));
    expect(source, contains('BrandColors.reward'));
    expect(source, isNot(contains('AppColors.neonCyan')));
  });
}
