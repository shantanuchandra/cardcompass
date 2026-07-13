import 'package:flutter_test/flutter_test.dart';
import 'package:cardcompass/core/services/reward_intelligence_service.dart';

void main() {
  group('pointExpiryMonthsFor', () {
    test('matches a known points card to its expiry window', () {
      expect(pointExpiryMonthsFor('HDFC Diners Black'), 24);
    });

    test('matches a cashback card to the non-expiring window', () {
      expect(pointExpiryMonthsFor('HDFC Millennia'), 999);
    });

    test('falls back to the bank-level default when card name is unmatched', () {
      expect(pointExpiryMonthsFor('SBI Unknown Variant'), 36);
    });

    test('falls back to the global default for an unrecognised bank', () {
      expect(pointExpiryMonthsFor('Some Random Card'), 24);
    });

    test('is case-insensitive', () {
      expect(pointExpiryMonthsFor('axis atlas'), pointExpiryMonthsFor('AXIS ATLAS'));
    });
  });
}
