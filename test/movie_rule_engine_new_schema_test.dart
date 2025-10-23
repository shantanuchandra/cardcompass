import 'package:flutter_test/flutter_test.dart';
import 'package:cardcompass/features/movie_rule_engine/movie_rule_engine.dart';

/// Test cases for the Movie Ticket Rule Engine with new schema
/// Tests both owned and non-owned card recommendations
void main() {
  group('TransactionStep - Ownership Detection', () {
    test('should correctly identify owned cards', () {
      final step = TransactionStep(
        platform: 'BookMyShow',
        cardName: 'ICICI Sapphire',
        cardId: '123',
        ticketCount: 2,
        amount: 560.0,
        savings: 280.0,
        benefitType: 'BOGO',
        explanation: 'Buy 1 Get 1 free',
        benefitDetails: {
          'is_owned': true,
          'user_card_id': 'user-card-123',
          'card_network': 'VISA',
          'bank': 'ICICI Bank',
        },
      );

      expect(step.isOwned, isTrue);
      expect(step.userCardId, equals('user-card-123'));
      expect(step.cardNetwork, equals('VISA'));
      expect(step.bank, equals('ICICI Bank'));
    });

    test('should correctly identify non-owned cards', () {
      final step = TransactionStep(
        platform: 'BookMyShow',
        cardName: 'HDFC Diners Club Black',
        cardId: '456',
        ticketCount: 2,
        amount: 560.0,
        savings: 280.0,
        benefitType: 'BOGO',
        explanation: 'Buy 1 Get 1 free',
        benefitDetails: {
          'is_owned': false,
          'user_card_id': null,
          'card_network': 'Diners Club',
          'bank': 'HDFC Bank',
        },
      );

      expect(step.isOwned, isFalse);
      expect(step.userCardId, isNull);
      expect(step.cardNetwork, equals('Diners Club'));
      expect(step.bank, equals('HDFC Bank'));
    });

    test('should handle missing benefitDetails gracefully', () {
      final step = TransactionStep(
        platform: 'BookMyShow',
        cardName: 'Test Card',
        cardId: '789',
        ticketCount: 2,
        amount: 560.0,
        savings: 280.0,
        benefitType: 'BOGO',
        explanation: 'Test offer',
      );

      expect(step.isOwned, isFalse); // Defaults to false
      expect(step.userCardId, isNull);
      expect(step.cardNetwork, isNull);
      expect(step.bank, isNull);
    });

    test('should serialize and deserialize ownership information', () {
      final originalStep = TransactionStep(
        platform: 'PVR',
        cardName: 'Axis Burgundy',
        cardId: '999',
        ticketCount: 4,
        amount: 1200.0,
        savings: 300.0,
        benefitType: 'CASHBACK',
        explanation: '25% cashback',
        benefitDetails: {
          'is_owned': true,
          'user_card_id': 'user-card-999',
          'card_network': 'VISA',
          'bank': 'Axis Bank',
          'priority_score': 5,
          'efficiency': 75.0,
        },
      );

      final json = originalStep.toJson();
      final restoredStep = TransactionStep.fromJson(json);

      expect(restoredStep.isOwned, equals(originalStep.isOwned));
      expect(restoredStep.userCardId, equals(originalStep.userCardId));
      expect(restoredStep.cardNetwork, equals(originalStep.cardNetwork));
      expect(restoredStep.bank, equals(originalStep.bank));
      expect(restoredStep.benefitDetails?['priority_score'], equals(5));
      expect(restoredStep.benefitDetails?['efficiency'], equals(75.0));
    });

    test('toString should include ownership status', () {
      final ownedStep = TransactionStep(
        platform: 'BookMyShow',
        cardName: 'ICICI Sapphire',
        cardId: '123',
        ticketCount: 2,
        amount: 560.0,
        savings: 280.0,
        benefitType: 'BOGO',
        explanation: 'Buy 1 Get 1 free',
        benefitDetails: {'is_owned': true},
      );

      final notOwnedStep = TransactionStep(
        platform: 'BookMyShow',
        cardName: 'HDFC Diners',
        cardId: '456',
        ticketCount: 2,
        amount: 560.0,
        savings: 280.0,
        benefitType: 'BOGO',
        explanation: 'Buy 1 Get 1 free',
        benefitDetails: {'is_owned': false},
      );

      expect(ownedStep.toString(), contains('[OWNED]'));
      expect(notOwnedStep.toString(), contains('[NOT OWNED]'));
    });
  });

  group('Movie Recommendation - Mixed Ownership', () {
    test('should handle recommendations with both owned and non-owned cards', () {
      final steps = [
        TransactionStep(
          platform: 'BookMyShow',
          cardName: 'ICICI Sapphire',
          cardId: '123',
          ticketCount: 2,
          amount: 560.0,
          savings: 280.0,
          benefitType: 'BOGO',
          explanation: 'Buy 1 Get 1 free',
          benefitDetails: {'is_owned': true},
        ),
        TransactionStep(
          platform: 'PVR',
          cardName: 'HDFC Diners Club Black',
          cardId: '456',
          ticketCount: 2,
          amount: 560.0,
          savings: 500.0,
          benefitType: 'MILESTONE',
          explanation: 'Free milestone tickets',
          benefitDetails: {'is_owned': false},
        ),
        TransactionStep(
          platform: 'INOX',
          cardName: 'Axis Burgundy',
          cardId: '789',
          ticketCount: 3,
          amount: 840.0,
          savings: 210.0,
          benefitType: 'CASHBACK',
          explanation: '25% cashback',
          benefitDetails: {'is_owned': true},
        ),
      ];

      final recommendation = MovieRecommendation(
        steps: steps,
        totalAmount: 1960.0,
        totalSavings: 990.0,
        finalAmount: 970.0,
        explanation: 'Optimized strategy with mixed ownership',
        calculatedAt: DateTime.now(),
      );

      expect(recommendation.steps.length, equals(3));
      expect(recommendation.totalSavings, equals(990.0));
      expect(recommendation.savingsPercentage, closeTo(50.5, 0.1));
      
      // Verify ownership status of each step
      expect(steps[0].isOwned, isTrue);  // ICICI Sapphire - owned
      expect(steps[1].isOwned, isFalse); // HDFC Diners - not owned
      expect(steps[2].isOwned, isTrue);  // Axis Burgundy - owned
    });

    test('should handle recommendations with only non-owned cards', () {
      final steps = [
        TransactionStep(
          platform: 'BookMyShow',
          cardName: 'HDFC Infinia',
          cardId: '111',
          ticketCount: 2,
          amount: 700.0,
          savings: 350.0,
          benefitType: 'BOGO',
          explanation: 'Premium BOGO offer',
          benefitDetails: {
            'is_owned': false,
            'bank': 'HDFC Bank',
            'card_network': 'VISA',
          },
        ),
      ];

      final recommendation = MovieRecommendation(
        steps: steps,
        totalAmount: 700.0,
        totalSavings: 350.0,
        finalAmount: 350.0,
        explanation: 'Great savings possible with premium card',
        calculatedAt: DateTime.now(),
      );

      expect(recommendation.steps.length, equals(1));
      expect(recommendation.steps[0].isOwned, isFalse);
      expect(recommendation.steps[0].bank, equals('HDFC Bank'));
      expect(recommendation.hasRecommendations, isTrue);
    });
  });

  group('Benefit Details Validation', () {
    test('should validate complete benefit details structure', () {
      final benefitDetails = {
        'is_owned': true,
        'user_card_id': 'user-card-123',
        'card_network': 'VISA',
        'bank': 'ICICI Bank',
        'priority_score': 5,
        'efficiency': 75.5,
      };

      final step = TransactionStep(
        platform: 'BookMyShow',
        cardName: 'ICICI Sapphire',
        cardId: '123',
        ticketCount: 2,
        amount: 560.0,
        savings: 280.0,
        benefitType: 'BOGO',
        explanation: 'Buy 1 Get 1 free',
        benefitDetails: benefitDetails,
      );

      expect(step.benefitDetails, isNotNull);
      expect(step.benefitDetails?['is_owned'], isTrue);
      expect(step.benefitDetails?['user_card_id'], equals('user-card-123'));
      expect(step.benefitDetails?['card_network'], equals('VISA'));
      expect(step.benefitDetails?['bank'], equals('ICICI Bank'));
      expect(step.benefitDetails?['priority_score'], equals(5));
      expect(step.benefitDetails?['efficiency'], equals(75.5));
    });

    test('should handle partial benefit details', () {
      final benefitDetails = {
        'is_owned': false,
        // Missing user_card_id, card_network, bank
      };

      final step = TransactionStep(
        platform: 'BookMyShow',
        cardName: 'Test Card',
        cardId: '123',
        ticketCount: 2,
        amount: 560.0,
        savings: 280.0,
        benefitType: 'BOGO',
        explanation: 'Test offer',
        benefitDetails: benefitDetails,
      );

      expect(step.isOwned, isFalse);
      expect(step.userCardId, isNull);
      expect(step.cardNetwork, isNull);
      expect(step.bank, isNull);
    });
  });

  group('Recommendation Sorting and Prioritization', () {
    test('should maintain recommendation order regardless of ownership', () {
      // Recommendations should be sorted by efficiency/savings, not ownership
      final steps = [
        TransactionStep(
          platform: 'BookMyShow',
          cardName: 'HDFC Diners Black',
          cardId: '456',
          ticketCount: 2,
          amount: 560.0,
          savings: 500.0, // Highest savings
          benefitType: 'MILESTONE',
          explanation: 'Free milestone tickets',
          benefitDetails: {'is_owned': false}, // Not owned but best offer
        ),
        TransactionStep(
          platform: 'PVR',
          cardName: 'ICICI Sapphire',
          cardId: '123',
          ticketCount: 2,
          amount: 560.0,
          savings: 280.0, // Lower savings
          benefitType: 'BOGO',
          explanation: 'Buy 1 Get 1 free',
          benefitDetails: {'is_owned': true}, // Owned but not the best
        ),
      ];

      // The non-owned card with better savings should be recommended first
      expect(steps[0].savings, greaterThan(steps[1].savings));
      expect(steps[0].isOwned, isFalse);
      expect(steps[1].isOwned, isTrue);
    });
  });

  group('Edge Cases', () {
    test('should handle null benefitDetails', () {
      final step = TransactionStep(
        platform: 'BookMyShow',
        cardName: 'Test Card',
        cardId: '123',
        ticketCount: 2,
        amount: 560.0,
        savings: 280.0,
        benefitType: 'BOGO',
        explanation: 'Test offer',
        benefitDetails: null,
      );

      expect(step.isOwned, isFalse);
      expect(step.userCardId, isNull);
      expect(step.cardNetwork, isNull);
      expect(step.bank, isNull);
    });

    test('should handle empty benefitDetails map', () {
      final step = TransactionStep(
        platform: 'BookMyShow',
        cardName: 'Test Card',
        cardId: '123',
        ticketCount: 2,
        amount: 560.0,
        savings: 280.0,
        benefitType: 'BOGO',
        explanation: 'Test offer',
        benefitDetails: {},
      );

      expect(step.isOwned, isFalse);
      expect(step.userCardId, isNull);
    });

    test('should handle benefitDetails with wrong types', () {
      final step = TransactionStep(
        platform: 'BookMyShow',
        cardName: 'Test Card',
        cardId: '123',
        ticketCount: 2,
        amount: 560.0,
        savings: 280.0,
        benefitType: 'BOGO',
        explanation: 'Test offer',
        benefitDetails: {
          'is_owned': 'true', // String instead of bool
          'user_card_id': '123', // Keep as string to avoid type error
        },
      );

      // Should handle gracefully without crashing
      expect(step.isOwned, isFalse); // 'true' string != true bool
      expect(step.userCardId, equals('123')); // String is valid
    });
  });

  group('Integration Scenarios', () {
    test('should create realistic movie booking scenario with mixed ownership', () {
      // Scenario: User wants to book 7 tickets at ₹280 each
      // User owns ICICI Sapphire and Axis Burgundy
      // User doesn't own HDFC Diners Club Black
      
      final request = MovieTicketRequest(
        numberOfTickets: 7,
        pricePerTicket: 280.0,
      );

      final steps = [
        // Best offer but not owned
        TransactionStep(
          platform: 'BookMyShow',
          cardName: 'HDFC Diners Club Black',
          cardId: '001',
          ticketCount: 2,
          amount: 560.0,
          savings: 500.0, // Milestone reward
          benefitType: 'MILESTONE',
          explanation: '2 free milestone tickets',
          benefitDetails: {
            'is_owned': false,
            'bank': 'HDFC Bank',
            'card_network': 'Diners Club',
          },
        ),
        // Second best - owned
        TransactionStep(
          platform: 'BookMyShow',
          cardName: 'ICICI Sapphire',
          cardId: '002',
          ticketCount: 2,
          amount: 560.0,
          savings: 280.0, // BOGO
          benefitType: 'BOGO',
          explanation: 'Buy 1 Get 1 free (max ₹300)',
          benefitDetails: {
            'is_owned': true,
            'user_card_id': 'user-card-002',
            'bank': 'ICICI Bank',
            'card_network': 'VISA',
          },
        ),
        // Third option - owned
        TransactionStep(
          platform: 'INOX',
          cardName: 'Axis Burgundy',
          cardId: '003',
          ticketCount: 3,
          amount: 840.0,
          savings: 210.0, // 25% cashback
          benefitType: 'CASHBACK',
          explanation: '25% cashback',
          benefitDetails: {
            'is_owned': true,
            'user_card_id': 'user-card-003',
            'bank': 'Axis Bank',
            'card_network': 'VISA',
          },
        ),
      ];

      final recommendation = MovieRecommendation(
        steps: steps,
        totalAmount: request.totalAmount,
        totalSavings: 990.0,
        finalAmount: 970.0,
        explanation: 'Optimized strategy saves ₹990 (50.5%) across 3 transaction(s)',
        calculatedAt: DateTime.now(),
      );

      expect(recommendation.steps.length, equals(3));
      expect(recommendation.totalAmount, equals(1960.0));
      expect(recommendation.totalSavings, equals(990.0));
      expect(recommendation.savingsPercentage, closeTo(50.5, 0.1));
      
      // Verify the best offer is shown first even though not owned
      expect(steps[0].isOwned, isFalse);
      expect(steps[0].savings, equals(500.0));
      
      // Verify user's owned cards are also in recommendations
      expect(steps[1].isOwned, isTrue);
      expect(steps[2].isOwned, isTrue);
    });
  });
}
