import 'package:flutter_test/flutter_test.dart';
import 'package:cardcompass/core/services/merchant_category_seed.dart';
import 'package:cardcompass/core/services/ambiguous_merchants.dart';

const _validCategories = {
  'food', 'fuel', 'grocery', 'entertainment', 'travel', 'shopping',
  'utilities', 'insurance', 'medical', 'education', 'investment',
  'transport', 'rental', 'subscription', 'gift', 'other',
};

void main() {
  group('merchantCategorySeed', () {
    test('every value is one of the 16 valid categories', () {
      for (final entry in merchantCategorySeed.entries) {
        expect(
          _validCategories.contains(entry.value),
          isTrue,
          reason: '${entry.key} -> ${entry.value} is not a valid category',
        );
      }
    });

    test('every key is already uppercase-normalized', () {
      for (final key in merchantCategorySeed.keys) {
        expect(key, key.toUpperCase(), reason: '$key should be uppercase');
      }
    });

    test('never seeds a denylisted ambiguous merchant', () {
      for (final merchant in ambiguousMerchants) {
        expect(
          merchantCategorySeed.containsKey(merchant),
          isFalse,
          reason: '$merchant is denylisted as ambiguous and must never be seeded '
              'with a single fixed category (spec §1)',
        );
      }
    });

    test('covers known Indian merchants', () {
      expect(merchantCategorySeed['SWIGGY'], 'food');
      expect(merchantCategorySeed['ZOMATO'], 'food');
      expect(merchantCategorySeed['FLIPKART'], 'shopping');
      expect(merchantCategorySeed['OLA'], 'transport');
      expect(merchantCategorySeed['UBER'], 'transport');
    });

    test('covers known UAE merchants', () {
      expect(merchantCategorySeed['CARREFOUR'], 'grocery');
      expect(merchantCategorySeed['TALABAT'], 'food');
      expect(merchantCategorySeed['CAREEM'], 'transport');
      expect(merchantCategorySeed['ADNOC'], 'fuel');
      expect(merchantCategorySeed['ENOC'], 'fuel');
      expect(merchantCategorySeed['NOON'], 'shopping');
    });

    test('has no duplicate keys (Map construction would already prevent this, '
        'but guards against a future accidental re-declaration in a merge)', () {
      expect(merchantCategorySeed.keys.toSet().length, merchantCategorySeed.length);
    });
  });
}
