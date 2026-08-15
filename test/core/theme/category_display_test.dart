import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:cardcompass/core/theme/category_display.dart';
import 'package:cardcompass/core/theme/app_theme.dart';

void main() {
  const categories = [
    'food', 'fuel', 'grocery', 'entertainment', 'travel', 'shopping',
    'utilities', 'insurance', 'medical', 'education', 'investment',
    'transport', 'rental', 'subscription', 'gift', 'other',
  ];

  group('categoryIcon', () {
    test('returns a specific (non-default) icon for every one of the 16 '
        'valid categories except other, which shares the default icon '
        'by design', () {
      for (final c in categories) {
        final icon = categoryIcon(c);
        expect(icon, isA<IconData>(), reason: c);
      }
    });

    test('falls back to the generic receipt icon for null/unrecognized', () {
      expect(categoryIcon(null), Icons.receipt_rounded);
      expect(categoryIcon('not_a_real_category'), Icons.receipt_rounded);
    });

    test('is case-insensitive', () {
      expect(categoryIcon('FOOD'), categoryIcon('food'));
    });
  });

  group('categoryColor', () {
    test('returns a specific color for every one of the 16 valid categories', () {
      for (final c in categories) {
        final color = categoryColor(c);
        expect(color, isA<Color>(), reason: c);
      }
    });

    test('falls back to textSecondary for null/unrecognized', () {
      expect(categoryColor(null), AppColors.textSecondary);
      expect(categoryColor('not_a_real_category'), AppColors.textSecondary);
    });
  });
}
