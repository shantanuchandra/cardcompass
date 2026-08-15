import 'package:cardcompass/core/repositories/transactions_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseMerchantCategoryRow', () {
    test('extracts category from a valid row', () {
      expect(parseMerchantCategoryRow({'category': 'grocery'}), 'grocery');
    });

    test('returns null for an empty result', () {
      expect(parseMerchantCategoryRow(null), isNull);
    });

    test('returns null when category field is missing', () {
      expect(
        parseMerchantCategoryRow({'merchant_name_normalized': 'CARREFOUR'}),
        isNull,
      );
    });
  });
}
