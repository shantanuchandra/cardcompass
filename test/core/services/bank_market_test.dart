import 'package:flutter_test/flutter_test.dart';
import 'package:cardcompass/core/services/bank_market.dart';

void main() {
  group('currencyForBank', () {
    test('returns INR for Indian banks', () {
      expect(currencyForBank('HDFC Bank'), 'INR');
      expect(currencyForBank('SBI Card'), 'INR');
      expect(currencyForBank('ICICI Bank'), 'INR');
      expect(currencyForBank('Axis Bank'), 'INR');
    });

    test('returns AED for UAE banks', () {
      expect(currencyForBank('FAB'), 'AED');
      expect(currencyForBank('Emirates NBD'), 'AED');
      expect(currencyForBank('ADCB'), 'AED');
      expect(currencyForBank('Mashreq'), 'AED');
      expect(currencyForBank('Dubai Islamic Bank'), 'AED');
      expect(currencyForBank('HSBC UAE'), 'AED');
      expect(currencyForBank('Citibank UAE'), 'AED');
    });

    test('returns null (not a silent INR default) for an unrecognized bank name', () {
      // Confirmed as a design requirement (spec §4, layer 3): a caller must
      // be able to distinguish "resolved to INR" from "couldn't resolve at
      // all" — silently defaulting to INR here would mask exactly the
      // failure this function exists to catch.
      expect(currencyForBank('Some New Bank Nobody Has Heard Of'), isNull);
    });
  });
}
