import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final sources =
      ['transactions_screen.dart', '../widgets/spend_trend_panel.dart']
          .map(
            (name) => File(
              'lib/features/transactions/screens/$name',
            ).readAsStringSync(),
          )
          .join('\n');
  test('transaction UI uses ledger and mono evidence roles', () {
    expect(sources, contains('BrandColors.ledger'));
    expect(sources, contains("fontFamily: 'IBM Plex Mono'"));
    expect(sources, isNot(contains('GoogleFonts.inter')));
  });
}
