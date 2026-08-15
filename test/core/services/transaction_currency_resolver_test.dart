import 'package:flutter_test/flutter_test.dart';
import 'package:cardcompass/core/services/transaction_currency_resolver.dart';

void main() {
  group('resolveTransactionCurrency', () {
    test('trusts a non-INR Gemini value directly, no cross-check needed', () {
      expect(
        resolveTransactionCurrency(geminiCurrency: 'AED', bankMarketCurrency: 'INR'),
        'AED',
      );
      expect(
        resolveTransactionCurrency(geminiCurrency: 'USD', bankMarketCurrency: 'AED'),
        'USD',
      );
    });

    test('a non-INR value is trusted even if not a real currency code — '
        'validation is intentionally out of scope, see doc comment', () {
      expect(
        resolveTransactionCurrency(geminiCurrency: 'XYZ', bankMarketCurrency: 'INR'),
        'XYZ',
      );
    });

    test('overrides a bare "INR" value when the bank resolves to a '
        'non-INR market — the core INR-distrust logic', () {
      expect(
        resolveTransactionCurrency(geminiCurrency: 'INR', bankMarketCurrency: 'AED'),
        'AED',
      );
    });

    test('keeps "INR" when the bank also resolves to INR', () {
      expect(
        resolveTransactionCurrency(geminiCurrency: 'INR', bankMarketCurrency: 'INR'),
        'INR',
      );
    });

    test('keeps "INR" when the bank market is unresolved (null)', () {
      expect(
        resolveTransactionCurrency(geminiCurrency: 'INR', bankMarketCurrency: null),
        'INR',
      );
    });

    test('missing/null Gemini value falls through to the bank market, '
        'same as a bare "INR" response would', () {
      expect(
        resolveTransactionCurrency(geminiCurrency: null, bankMarketCurrency: 'AED'),
        'AED',
      );
      expect(
        resolveTransactionCurrency(geminiCurrency: null, bankMarketCurrency: null),
        'INR', // final fallback when nothing resolves anything
      );
    });

    test('empty string Gemini value is treated the same as null', () {
      expect(
        resolveTransactionCurrency(geminiCurrency: '', bankMarketCurrency: 'AED'),
        'AED',
      );
    });
  });
}
