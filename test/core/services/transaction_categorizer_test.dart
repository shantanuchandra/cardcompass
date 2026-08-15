import 'package:flutter_test/flutter_test.dart';
import 'package:cardcompass/core/services/transaction_categorizer.dart';

void main() {
  group('normalizeMerchantName', () {
    test('uppercases and trims', () {
      expect(normalizeMerchantName('  Swiggy  '), 'SWIGGY');
    });

    test('collapses internal whitespace', () {
      expect(normalizeMerchantName('Big   Basket'), 'BIG BASKET');
    });
  });

  group('isValidCategory', () {
    test('accepts all 16 valid categories', () {
      const valid = {
        'food', 'fuel', 'grocery', 'entertainment', 'travel', 'shopping',
        'utilities', 'insurance', 'medical', 'education', 'investment',
        'transport', 'rental', 'subscription', 'gift', 'other',
      };
      for (final c in valid) {
        expect(isValidCategory(c), isTrue, reason: c);
      }
    });

    test('rejects legacy vocabulary values', () {
      expect(isValidCategory('bills'), isFalse);
      expect(isValidCategory('transfer'), isFalse);
      expect(isValidCategory('fee'), isFalse);
      expect(isValidCategory('payment'), isFalse);
      expect(isValidCategory('cash'), isFalse);
      expect(isValidCategory('dining'), isFalse); // superseded by 'food'
    });

    test('rejects null and empty', () {
      expect(isValidCategory(null), isFalse);
      expect(isValidCategory(''), isFalse);
    });

    test('is case-insensitive', () {
      expect(isValidCategory('FOOD'), isTrue);
      expect(isValidCategory('Food'), isTrue);
    });
  });

  group('keywordCategoryFor — covers the 13 categories with deterministic '
      'signals (investment/rental/gift have none, per spec Taxonomy section)', () {
    test('matches Indian merchant keywords in description', () {
      expect(keywordCategoryFor('SWIGGY ORDER #1234'), 'food');
      expect(keywordCategoryFor('PAYMENT TO ZOMATO LTD'), 'food');
      expect(keywordCategoryFor('AMAZON.IN PURCHASE'), 'shopping');
      expect(keywordCategoryFor('OLA CABS TRIP'), 'transport');
      expect(keywordCategoryFor('INDIAN OIL PETROL PUMP'), 'fuel');
    });

    test('matches UAE merchant keywords in description', () {
      expect(keywordCategoryFor('CARREFOUR HYPERMARKET DUBAI'), 'grocery');
      expect(keywordCategoryFor('TALABAT DELIVERY'), 'food');
      expect(keywordCategoryFor('CAREEM RIDE'), 'transport');
      expect(keywordCategoryFor('ADNOC FUEL STATION'), 'fuel');
    });

    test('matches generic category keywords not tied to a specific merchant', () {
      expect(keywordCategoryFor('RESTAURANT BILL PAYMENT'), 'food');
      expect(keywordCategoryFor('PHARMACY PURCHASE'), 'medical');
      expect(keywordCategoryFor('HOSPITAL CONSULTATION FEE'), 'medical');
      expect(keywordCategoryFor('ELECTRICITY BILL PAYMENT'), 'utilities');
      expect(keywordCategoryFor('INSURANCE PREMIUM'), 'insurance');
    });

    test('returns null for descriptions belonging to the 3 Gemini-only '
        'categories (investment/rental/gift) — this is tier 3\'s honest '
        'failure mode for those three, not a false positive', () {
      expect(keywordCategoryFor('MUTUAL FUND SIP INSTALLMENT'), isNull);
      expect(keywordCategoryFor('MONTHLY RENT PAYMENT LANDLORD'), isNull);
      expect(keywordCategoryFor('GIFT CARD PURCHASE'), isNull);
    });

    test('returns null when nothing matches at all', () {
      expect(keywordCategoryFor('XYZ CORP TRANSACTION 998271'), isNull);
    });

    test('is case-insensitive', () {
      expect(keywordCategoryFor('swiggy order'), 'food');
    });
  });

  group('categorize', () {
    test('merchant lookup takes priority over a valid Gemini-provided category', () {
      final result = categorize(
        merchantName: 'Carrefour',
        description: 'CARREFOUR HYPERMARKET',
        geminiCategory: 'shopping', // deliberately wrong, to prove priority
        merchantLookup: (normalized) => normalized == 'CARREFOUR' ? 'grocery' : null,
      );
      expect(result.category, 'grocery');
      expect(result.source, CategorizationSource.merchantMap);
    });

    test('a denylisted ambiguous merchant skips merchant lookup entirely, '
        'even if merchantLookup would have returned a value', () {
      final result = categorize(
        merchantName: 'Amazon',
        description: 'AMAZON PRIME MEMBERSHIP',
        geminiCategory: 'subscription',
        // This lookup function would return 'shopping' if consulted — proving
        // the denylist check happens before merchantLookup is ever called.
        merchantLookup: (_) => 'shopping',
      );
      expect(result.category, 'subscription'); // from Gemini, not the lookup
      expect(result.source, CategorizationSource.geminiValidated);
    });

    test("falls through to keyword matching when Gemini's category is invalid", () {
      final result = categorize(
        merchantName: 'Some New Restaurant',
        description: 'SOME NEW RESTAURANT PAYMENT',
        geminiCategory: 'dining', // not one of the 16 — superseded by 'food'
        merchantLookup: (_) => null,
      );
      expect(result.category, 'food'); // matched via 'restaurant' keyword
      expect(result.source, CategorizationSource.keywordFallback);
    });

    test("trusts Gemini's category when it IS one of the 16 valid values", () {
      final result = categorize(
        merchantName: 'Some New Merchant',
        description: 'SOME NEW MERCHANT XYZ',
        geminiCategory: 'travel',
        merchantLookup: (_) => null,
      );
      expect(result.category, 'travel');
      expect(result.source, CategorizationSource.geminiValidated);
    });

    test('falls through to keyword matching when Gemini category is null', () {
      final result = categorize(
        merchantName: 'Netflix',
        description: 'NETFLIX SUBSCRIPTION',
        geminiCategory: null,
        merchantLookup: (_) => null,
      );
      expect(result.category, 'entertainment');
      expect(result.source, CategorizationSource.keywordFallback);
    });

    test('returns other with unresolved source when nothing matches anything', () {
      final result = categorize(
        merchantName: 'XYZ Corp',
        description: 'XYZ CORP TRANSACTION 998271',
        geminiCategory: null,
        merchantLookup: (_) => null,
      );
      expect(result.category, 'other');
      expect(result.source, CategorizationSource.unresolved);
    });

    test('calling categorize twice with the same never-before-seen merchant '
        're-resolves via keyword matching both times — proves there is no '
        'caching or write-back side effect (spec §3: privacy fix)', () {
      var lookupCallCount = 0;
      String? lookup(String _) {
        lookupCallCount++;
        return null; // never in the map
      }

      final first = categorize(
        merchantName: 'Local Restaurant XYZ',
        description: 'RESTAURANT PAYMENT',
        geminiCategory: null,
        merchantLookup: lookup,
      );
      final second = categorize(
        merchantName: 'Local Restaurant XYZ',
        description: 'RESTAURANT PAYMENT',
        geminiCategory: null,
        merchantLookup: lookup,
      );

      expect(first.category, 'food');
      expect(second.category, 'food');
      expect(first.source, CategorizationSource.keywordFallback);
      expect(second.source, CategorizationSource.keywordFallback);
      // Called once per categorize() invocation — nothing was cached/learned
      // between calls that would let the second call skip re-resolving.
      expect(lookupCallCount, 2);
    });
  });
}
