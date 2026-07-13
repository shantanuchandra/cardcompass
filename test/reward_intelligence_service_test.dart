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

    test(
      'matches the real "bank cardName" shape from card_catalog, '
      'where bank always includes a suffix word like "Bank"/"Card"',
      () {
        // card_catalog.bank is "HDFC Bank", never bare "HDFC" — callers
        // building "$bank $cardName" (e.g. SupabaseRewardBalanceRepository,
        // RewardsNudgeService) produce "HDFC Bank Millennia Cc New", not
        // "HDFC Millennia". Caught by a real-database integration test;
        // regressed here so it can't silently reappear.
        expect(pointExpiryMonthsFor('HDFC Bank Millennia Cc New'), 999);
        expect(pointExpiryMonthsFor('SBI Card Cashback'), 999);
      },
    );
  });

  group('pointValueFor', () {
    test(
      'matches the real "bank cardName" shape from card_catalog',
      () {
        expect(pointValueFor('HDFC Bank Millennia Cc New'), 0.20);
      },
    );
  });
}
