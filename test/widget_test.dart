import 'package:cardcompass/core/theme/app_theme.dart';
import 'package:cardcompass/core/theme/brand_tokens.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('application theme boots with the canonical editorial background', () {
    expect(AppTheme.editorial.scaffoldBackgroundColor, BrandColors.ink);
  });
}
