import 'package:flutter_test/flutter_test.dart';
import 'package:cardcompass/core/services/card_normalizer_service.dart';

void main() {
  group('CardNormalizerService.normalizeBankName — UAE recognition', () {
    test('recognizes UAE banks with no Indian namesake', () {
      expect(CardNormalizerService.normalizeBankName('FAB'), 'FAB');
      expect(CardNormalizerService.normalizeBankName('Emirates NBD Bank'), 'Emirates NBD');
      expect(CardNormalizerService.normalizeBankName('ADCB'), 'ADCB');
      expect(CardNormalizerService.normalizeBankName('Mashreq Bank'), 'Mashreq');
      expect(CardNormalizerService.normalizeBankName('RAKBANK'), 'RAKBANK');
    });

    test('recognizes shared-brand UAE banks when the raw name says UAE '
        '(the ordering bug this fix corrects — these must NOT fall through '
        'to the generic Indian HSBC/Citi checks)', () {
      expect(CardNormalizerService.normalizeBankName('HSBC UAE'), 'HSBC UAE');
      expect(CardNormalizerService.normalizeBankName('Citibank UAE'), 'Citibank UAE');
    });

    test('still recognizes plain Indian HSBC/Citi when the raw name does '
        'not say UAE (unchanged behavior)', () {
      expect(CardNormalizerService.normalizeBankName('HSBC'), 'HSBC');
      expect(CardNormalizerService.normalizeBankName('Citibank'), 'Citibank');
    });
  });
}
