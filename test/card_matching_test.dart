import 'package:flutter_test/flutter_test.dart';
import 'package:cardcompass/core/services/data_pipeline_debug_service.dart';
import 'package:cardcompass/shared/models/credit_card.dart';

CreditCard _card({
  required String id,
  required String bankName,
  required String cardName,
  String? catalogCardId,
}) {
  final now = DateTime(2026, 1, 1);
  return CreditCard(
    id: id,
    userId: 'user-1',
    cardName: cardName,
    bankName: bankName,
    network: CardNetwork.visa,
    type: CardType.credit,
    issuedDate: now,
    createdAt: now,
    updatedAt: now,
    catalogCardId: catalogCardId,
  );
}

void main() {
  group('DataPipelineDebugService.findMatchingUserCard', () {
    test('Pass 1: matches when bank and card name both match an existing card', () {
      final cards = [
        _card(id: 'card-1', bankName: 'HDFC Bank', cardName: 'Tata Neu Infinity', catalogCardId: 'cat-1'),
      ];

      final result = DataPipelineDebugService.findMatchingUserCard(
        existingUserCards: cards,
        bankName: 'HDFC Bank',
        expectedCardName: 'Tata Neu Infinity',
      );

      expect(result?.userCardId, 'card-1');
      expect(result?.catalogCardId, 'cat-1');
    });

    test(
        'does NOT merge into an unrelated card of the same bank when a distinct card variant was detected '
        '(the Diners Black → Tata Neu Infinity misattribution bug)', () {
      final cards = [
        _card(id: 'card-tata-neu', bankName: 'HDFC Bank', cardName: 'Tata Neu Infinity', catalogCardId: 'cat-tata-neu'),
      ];

      final result = DataPipelineDebugService.findMatchingUserCard(
        existingUserCards: cards,
        bankName: 'HDFC Bank',
        expectedCardName: 'Diners Black',
      );

      expect(result, isNull,
          reason: 'A statement for a distinct, named card variant that does not match any existing card '
              'must fall through to catalog lookup/creation (Pass 3), not merge into an unrelated card from the same bank.');
    });

    test('Pass 2: falls back to the single existing card from the bank when no specific variant was detected', () {
      final cards = [
        _card(id: 'card-bpcl', bankName: 'SBI Card', cardName: 'BPCL', catalogCardId: 'cat-bpcl'),
      ];

      // Gemini/regex couldn't detect a variant, so expectedCardName is just the bank name.
      final result = DataPipelineDebugService.findMatchingUserCard(
        existingUserCards: cards,
        bankName: 'SBI Card',
        expectedCardName: 'SBI Card',
      );

      expect(result?.userCardId, 'card-bpcl',
          reason: 'With no detected variant and exactly one card from the bank, it is safe to attach the statement to it.');
    });

    test('does not fall back via Pass 2 when the user has multiple cards from the same bank and no variant was detected', () {
      final cards = [
        _card(id: 'card-diners', bankName: 'HDFC Bank', cardName: 'Diners Black', catalogCardId: 'cat-diners'),
        _card(id: 'card-tata-neu', bankName: 'HDFC Bank', cardName: 'Tata Neu Infinity', catalogCardId: 'cat-tata-neu'),
      ];

      final result = DataPipelineDebugService.findMatchingUserCard(
        existingUserCards: cards,
        bankName: 'HDFC Bank',
        expectedCardName: 'HDFC Bank',
      );

      expect(result, isNull,
          reason: 'With no detected variant and more than one existing card for the bank, attaching to any single one would be a guess.');
    });

    test('returns null when no card from the bank exists at all', () {
      final cards = [
        _card(id: 'card-bpcl', bankName: 'SBI Card', cardName: 'BPCL', catalogCardId: 'cat-bpcl'),
      ];

      final result = DataPipelineDebugService.findMatchingUserCard(
        existingUserCards: cards,
        bankName: 'HDFC Bank',
        expectedCardName: 'Tata Neu Infinity',
      );

      expect(result, isNull);
    });
  });
}
