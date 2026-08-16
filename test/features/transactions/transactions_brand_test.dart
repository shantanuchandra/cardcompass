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
  test(
    'transaction UI uses the shared ledger metric and mono evidence roles',
    () {
      expect(sources, contains('BrandSurfaceTone.ledger'));
      expect(sources, contains('BrandMetric('));
      expect(sources, contains("fontFamily: 'IBM Plex Mono'"));
      expect(sources, isNot(contains('GoogleFonts.inter')));
    },
  );
}
