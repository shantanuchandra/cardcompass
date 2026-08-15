import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

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
    expect(
      source,
      contains("window.history.replaceState(null, '', '#\${_kTabPaths[i]}')"),
    );
    expect(source, contains('height: 68'));
    expect(source, contains('Semantics('));
  });

  test('mobile navigation uses concise consistent labels', () {
    for (final label in const [
      'Dashboard',
      'Cards',
      'Transactions',
      'Movies',
      'Settings',
    ]) {
      expect(source, contains("label: '$label'"));
    }
  });
}
