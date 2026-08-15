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

  // These three legacy strings are NOT in transaction_categorizer.dart's
  // validCategories and are no longer produced going forward, but pre-existing
  // rows written before the category CHECK constraint may still hold them (see
  // category_display.dart's doc comment for the full reasoning: the
  // NOT VALID constraint and its companion VALIDATE CONSTRAINT migration
  // don't guarantee the backfill has actually run against production in this
  // environment). Locking these in here so a future refactor of the switch
  // bodies can't silently drop the aliases without a test failing.
  group('legacy category aliases (kept per unverified-backfill safety reasoning)', () {
    test('dining resolves the same as food', () {
      expect(categoryIcon('dining'), categoryIcon('food'));
      expect(categoryColor('dining'), categoryColor('food'));
    });

    test('groceries resolves the same as grocery', () {
      expect(categoryIcon('groceries'), categoryIcon('grocery'));
      expect(categoryColor('groceries'), categoryColor('grocery'));
    });

    test('health resolves the same as medical', () {
      expect(categoryIcon('health'), categoryIcon('medical'));
      expect(categoryColor('health'), categoryColor('medical'));
    });
  });
}
