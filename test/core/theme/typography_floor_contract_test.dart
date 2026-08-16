import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reviewed Flutter surfaces contain no text literal below 12 pixels', () {
    const paths = [
      'lib/core/theme/app_theme.dart',
      'lib/core/theme/brand_components.dart',
      'lib/features/auth/screens/login_screen.dart',
      'lib/features/dashboard/screens/dashboard_screen.dart',
      'lib/features/transactions/screens/transactions_screen.dart',
      'lib/features/transactions/widgets/spend_trend_panel.dart',
      'lib/features/benefits/movie_deals/screens/movie_deals_results.dart',
    ];
    final literal = RegExp(r'fontSize:\s*([0-9]+(?:\.[0-9]+)?)');

    for (final path in paths) {
      final source = File(path).readAsStringSync();
      for (final match in literal.allMatches(source)) {
        final size = double.parse(match.group(1)!);
        expect(
          size,
          greaterThanOrEqualTo(12),
          reason: '$path contains a $size px non-decorative text literal',
        );
      }
    }
  });
}
