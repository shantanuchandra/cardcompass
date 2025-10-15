import 'package:flutter_test/flutter_test.dart';
import 'package:cardcompass/features/movie_rule_engine/movie_rule_engine.dart';

/// Test cases for the Movie Ticket Rule Engine
void main() {
  group('Movie Ticket Request', () {
    test('should calculate total amount correctly', () {
      final request = MovieTicketRequest(
        numberOfTickets: 4,
        pricePerTicket: 280.0,
      );

      expect(request.totalAmount, equals(1120.0));
      expect(request.numberOfTickets, equals(4));
      expect(request.pricePerTicket, equals(280.0));
    });

    test('should handle JSON serialization', () {
      final request = MovieTicketRequest(
        numberOfTickets: 2,
        pricePerTicket: 350.0,
        preferredPlatform: 'BookMyShow',
        preferredCinema: 'PVR',
      );

      final json = request.toJson();
      final restored = MovieTicketRequest.fromJson(json);

      expect(restored.numberOfTickets, equals(request.numberOfTickets));
      expect(restored.pricePerTicket, equals(request.pricePerTicket));
      expect(restored.preferredPlatform, equals(request.preferredPlatform));
      expect(restored.preferredCinema, equals(request.preferredCinema));
      expect(restored.totalAmount, equals(request.totalAmount));
    });
  });

  group('Transaction Step', () {
    test('should calculate effective amount and savings percentage', () {
      final step = TransactionStep(
        platform: 'BookMyShow',
        cardName: 'ICICI Sapphire',
        cardId: '123',
        ticketCount: 2,
        amount: 560.0,
        savings: 280.0,
        benefitType: 'BOGO',
        explanation: 'Buy 1 Get 1 free',
      );

      expect(step.effectiveAmount, equals(280.0));
      expect(step.savingsPercentage, equals(50.0));
    });

    test('should handle zero amount gracefully', () {
      final step = TransactionStep(
        platform: 'PVR',
        cardName: 'Test Card',
        cardId: '456',
        ticketCount: 0,
        amount: 0.0,
        savings: 0.0,
        benefitType: 'NONE',
        explanation: 'No benefit',
      );

      expect(step.effectiveAmount, equals(0.0));
      expect(step.savingsPercentage, equals(0.0));
    });
  });

  group('Movie Benefit Config', () {
    test('should parse JSON configuration correctly', () {
      final configJson = {
        'offer_type': 'BOGO',
        'partner_filter': ['BookMyShow', 'PVR'],
        'free_ticket_count': 1,
        'max_discount_amount': 300.0,
        'txn_ticket_limit': 4,
        'month_ticket_limit': 8,
        'efficiency_threshold': 200.0,
        'min_transaction_amount': 150.0,
        'start_date': '2025-01-01T00:00:00.000Z',
        'end_date': '2025-12-31T23:59:59.000Z',
      };

      final config = MovieBenefitConfig.fromJson(configJson);

      expect(config.offerType, equals('BOGO'));
      expect(config.partnerFilter, contains('BookMyShow'));
      expect(config.partnerFilter, contains('PVR'));
      expect(config.freeTicketCount, equals(1));
      expect(config.maxDiscountAmount, equals(300.0));
      expect(config.transactionTicketLimit, equals(4));
      expect(config.monthlyTicketLimit, equals(8));
      expect(config.efficiencyThreshold, equals(200.0));
      expect(config.minTransactionAmount, equals(150.0));
      expect(config.isValid, isTrue);
    });

    test('should validate platform compatibility', () {
      final config = MovieBenefitConfig(
        offerType: 'BOGO',
        partnerFilter: ['BookMyShow', 'PVR'],
      );

      expect(config.appliesToPlatform('BookMyShow'), isTrue);
      expect(config.appliesToPlatform('PVR'), isTrue);
      expect(config.appliesToPlatform('INOX'), isFalse);
      expect(config.appliesToPlatform('bookmyshow'), isTrue); // Case insensitive
    });

    test('should validate efficiency threshold', () {
      final config = MovieBenefitConfig(
        offerType: 'BOGO',
        efficiencyThreshold: 300.0,
      );

      expect(config.isEfficient(350.0), isTrue);
      expect(config.isEfficient(300.0), isTrue);
      expect(config.isEfficient(250.0), isFalse);
    });

    test('should validate minimum amount requirement', () {
      final config = MovieBenefitConfig(
        offerType: 'PERCENT_DISCOUNT',
        minTransactionAmount: 200.0,
      );

      expect(config.meetsMinimumAmount(250.0), isTrue);
      expect(config.meetsMinimumAmount(200.0), isTrue);
      expect(config.meetsMinimumAmount(150.0), isFalse);
    });

    test('should validate day of week restrictions', () {
      final config = MovieBenefitConfig(
        offerType: 'BOGO',
        validDayOfWeek: ['SAT', 'SUN'],
      );

      // Test with a Saturday (assuming weekday 6)
      final saturday = DateTime(2025, 7, 5); // Assuming this is a Saturday
      final monday = DateTime(2025, 7, 7); // Assuming this is a Monday

      expect(config.validForDay(saturday), isTrue);
      expect(config.validForDay(monday), isFalse);
    });

    test('should handle null restrictions gracefully', () {
      final config = MovieBenefitConfig(
        offerType: 'CASHBACK',
        partnerFilter: null,
        validDayOfWeek: null,
        efficiencyThreshold: null,
        minTransactionAmount: null,
      );

      expect(config.appliesToPlatform('AnyPlatform'), isTrue);
      expect(config.validForDay(DateTime.now()), isTrue);
      expect(config.isEfficient(50.0), isTrue);
      expect(config.meetsMinimumAmount(10.0), isTrue);
    });
  });

  group('Movie Recommendation', () {
    test('should calculate totals correctly', () {
      final steps = [
        TransactionStep(
          platform: 'BookMyShow',
          cardName: 'ICICI Sapphire',
          cardId: '123',
          ticketCount: 2,
          amount: 560.0,
          savings: 280.0,
          benefitType: 'BOGO',
          explanation: 'BOGO offer',
        ),
        TransactionStep(
          platform: 'PVR',
          cardName: 'Axis Burgundy',
          cardId: '456',
          ticketCount: 2,
          amount: 560.0,
          savings: 140.0,
          benefitType: 'CASHBACK',
          explanation: '25% cashback',
        ),
      ];

      final recommendation = MovieRecommendation(
        steps: steps,
        totalAmount: 1120.0,
        totalSavings: 420.0,
        finalAmount: 700.0,
        explanation: 'Optimized strategy',
        calculatedAt: DateTime.now(),
      );

      expect(recommendation.totalTickets, equals(4));
      expect(recommendation.savingsPercentage, closeTo(37.5, 0.1));
      expect(recommendation.hasRecommendations, isTrue);
      expect(recommendation.topRecommendations.length, equals(2));
    });

    test('should create empty recommendation correctly', () {
      final recommendation = MovieRecommendation.empty(
        totalAmount: 1000.0,
        tickets: 3,
      );

      expect(recommendation.totalSavings, equals(0.0));
      expect(recommendation.finalAmount, equals(1000.0));
      expect(recommendation.hasRecommendations, isFalse);
      expect(recommendation.savingsPercentage, equals(0.0));
      expect(recommendation.explanation, contains('No suitable movie benefits found'));
    });

    test('should limit top recommendations to 3', () {
      final steps = List.generate(5, (index) => TransactionStep(
        platform: 'Platform$index',
        cardName: 'Card$index',
        cardId: index.toString(),
        ticketCount: 1,
        amount: 100.0,
        savings: 10.0,
        benefitType: 'TEST',
        explanation: 'Test step $index',
      ));

      final recommendation = MovieRecommendation(
        steps: steps,
        totalAmount: 500.0,
        totalSavings: 50.0,
        finalAmount: 450.0,
        explanation: 'Test recommendation',
        calculatedAt: DateTime.now(),
      );

      expect(recommendation.steps.length, equals(5));
      expect(recommendation.topRecommendations.length, equals(3));
    });

    test('should handle JSON serialization', () {
      final steps = [
        TransactionStep(
          platform: 'BookMyShow',
          cardName: 'Test Card',
          cardId: '123',
          ticketCount: 2,
          amount: 600.0,
          savings: 300.0,
          benefitType: 'BOGO',
          explanation: 'Test explanation',
        ),
      ];

      final original = MovieRecommendation(
        steps: steps,
        totalAmount: 600.0,
        totalSavings: 300.0,
        finalAmount: 300.0,
        explanation: 'Test recommendation',
        calculatedAt: DateTime.now(),
        metadata: {'test': 'value'},
      );

      final json = original.toJson();
      final restored = MovieRecommendation.fromJson(json);

      expect(restored.steps.length, equals(original.steps.length));
      expect(restored.totalAmount, equals(original.totalAmount));
      expect(restored.totalSavings, equals(original.totalSavings));
      expect(restored.finalAmount, equals(original.finalAmount));
      expect(restored.explanation, equals(original.explanation));
      expect(restored.metadata?['test'], equals('value'));
    });
  });

  group('Efficiency Threshold Logic', () {
    test('should prevent high-value benefits on low-value tickets', () {
      // ICICI Emerald BOGO (₹750 max discount) vs ICICI Sapphire BOGO (₹300 max discount)
      final emeraldConfig = MovieBenefitConfig(
        offerType: 'BOGO',
        maxDiscountAmount: 750.0,
        efficiencyThreshold: 400.0, // High threshold
      );

      final sapphireConfig = MovieBenefitConfig(
        offerType: 'BOGO',
        maxDiscountAmount: 300.0,
        efficiencyThreshold: 200.0, // Lower threshold
      );

      final lowValueTicket = 280.0;

      // Emerald should NOT be efficient for ₹280 tickets
      expect(emeraldConfig.isEfficient(lowValueTicket), isFalse);
      
      // Sapphire should be efficient for ₹280 tickets
      expect(sapphireConfig.isEfficient(lowValueTicket), isTrue);
    });

    test('should allow high-value benefits for appropriate ticket prices', () {
      final emeraldConfig = MovieBenefitConfig(
        offerType: 'BOGO',
        maxDiscountAmount: 750.0,
        efficiencyThreshold: 400.0,
      );

      final highValueTicket = 500.0;

      // Emerald should be efficient for ₹500 tickets
      expect(emeraldConfig.isEfficient(highValueTicket), isTrue);
    });
  });
}
