import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File(
    'lib/features/dashboard/screens/dashboard_screen.dart',
  ).readAsStringSync();
  test('dashboard is an ink and paper wallet briefing', () {
    expect(source, contains('BrandColors.paper'));
    expect(source, contains('BrandColors.ledger'));
    expect(source, contains("fontFamily: 'Fraunces'"));
    expect(source, isNot(contains('GoogleFonts.spaceGrotesk')));
  });
}
