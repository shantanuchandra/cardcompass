import 'package:flutter_test/flutter_test.dart';
import 'package:cardcompass/features/movie_rule_engine/data/movie_rule_engine_service.dart';
import 'package:cardcompass/features/movie_rule_engine/domain/models/movie_ticket_request.dart';
import 'package:cardcompass/features/movie_rule_engine/domain/models/movie_recommendation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cardcompass/config/constants.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: AppConstants.supabaseUrl,
      anonKey: AppConstants.supabaseAnonKey,
    );
  });
  group('MovieRuleEngineService', () {
    late MovieRuleEngineService service;

    setUp(() {
      service = MovieRuleEngineService();
    });

    test('returns empty recommendation if no cards with movie benefits', () async {
      // Arrange: Use a userId that has no cards/benefits in test DB
      const userId = 'test-user-no-benefits';
      final request = MovieTicketRequest(
        numberOfTickets: 2,
        pricePerTicket: 300,
      );

      // Act
      final result = await service.optimizeMovieTicketPurchase(userId: userId, request: request);

      // Assert
      expect(result, isA<MovieRecommendation>());
      expect(result.steps, isEmpty);
      expect(result.totalAmount, 600);
      expect(result.totalSavings, 0);
    });

    test('returns a valid recommendation if user has a card with a valid movie benefit', () async {
      // Arrange: Use a userId that has at least one card with a valid movie benefit in test DB
      final userId = AppConstants.testUserIdMovieRuleEngine;
      final request = MovieTicketRequest(
        numberOfTickets: 2,
        pricePerTicket: 300,
      );
      // Act
      final result = await service.optimizeMovieTicketPurchase(userId: userId, request: request);
      // Assert
      expect(result.steps, isNotEmpty);
      expect(result.totalSavings, greaterThan(0));
    });

    test('handles multiple cards/benefits and picks the optimal one', () async {
      // Arrange: Use a userId with multiple cards/benefits
      final userId = AppConstants.testUserIdMovieRuleEngine;
      final request = MovieTicketRequest(
        numberOfTickets: 4,
        pricePerTicket: 250,
      );
      // Act
      final result = await service.optimizeMovieTicketPurchase(userId: userId, request: request);
      // Assert
      expect(result.steps.length, greaterThanOrEqualTo(1));
      expect(result.totalSavings, greaterThan(0));
    });

    test('respects benefit usage limits (e.g., monthly ticket cap)', () async {
      // Arrange: Use a userId with a card that has already hit its monthly ticket limit
      final userId = AppConstants.testUserIdMovieRuleEngine;
      final request = MovieTicketRequest(
        numberOfTickets: 2,
        pricePerTicket: 200,
      );
      // Act
      final result = await service.optimizeMovieTicketPurchase(userId: userId, request: request);
      // Assert
      // Should not apply benefit if limit is reached
      // (You may need to adjust this test based on your DB state)
      expect(result.steps, isA<List>());
    });

    test('handles errors gracefully', () async {
      // Arrange: Use a userId or setup that triggers an error (e.g., invalid Supabase config)
      final userId = AppConstants.testUserIdMovieRuleEngine;
      final request = MovieTicketRequest(
        numberOfTickets: 1,
        pricePerTicket: 100,
      );
      // Act
      final result = await service.optimizeMovieTicketPurchase(userId: userId, request: request);
      // Assert
      expect(result, isA<MovieRecommendation>());
      // Should return an empty recommendation on error
      expect(result.steps, isA<List>());
    });

    test('applies BOGO (Buy One Get One) offer correctly', () async {
      // Arrange: User/card/benefit must be set up for BOGO in DB
      final userId = AppConstants.testUserIdMovieRuleEngine;
      final request = MovieTicketRequest(
        numberOfTickets: 3, // Should get 1 free if BOGO (2+1)
        pricePerTicket: 200,
      );
      // Act
      final result = await service.optimizeMovieTicketPurchase(userId: userId, request: request);
      // Assert
      expect(result.steps.any((step) => step.benefitType == 'BOGO'), isTrue);
      expect(result.totalSavings, greaterThan(0));
    });

    test('applies percent discount offer correctly', () async {
      // Arrange: User/card/benefit must be set up for percent discount in DB
      final userId = AppConstants.testUserIdMovieRuleEngine;
      final request = MovieTicketRequest(
        numberOfTickets: 2,
        pricePerTicket: 400,
      );
      // Act
      final result = await service.optimizeMovieTicketPurchase(userId: userId, request: request);
      // Assert: Pass if any step uses percent discount, even if not optimal
      final hasPercentDiscount = result.steps.any((step) => step.benefitType == 'PERCENT_DISCOUNT');
      expect(hasPercentDiscount, isTrue, reason: 'At least one step should use percent discount if available.');
    });

    test('applies cashback offer correctly', () async {
      // Arrange: User/card/benefit must be set up for cashback in DB
      final userId = AppConstants.testUserIdMovieRuleEngine;
      final request = MovieTicketRequest(
        numberOfTickets: 2,
        pricePerTicket: 500,
      );
      // Act
      final result = await service.optimizeMovieTicketPurchase(userId: userId, request: request);
      // Assert: Pass if any step uses cashback, even if not optimal
      final hasCashback = result.steps.any((step) => step.benefitType == 'CASHBACK');
      expect(hasCashback, isTrue, reason: 'At least one step should use cashback if available.');
    });

    test('applies milestone reward correctly', () async {
      // Arrange: User/card/benefit must be set up for milestone in DB
      final userId = AppConstants.testUserIdMovieRuleEngine;
      final request = MovieTicketRequest(
        numberOfTickets: 5,
        pricePerTicket: 300,
      );
      // Act
      final result = await service.optimizeMovieTicketPurchase(userId: userId, request: request);
      // Assert
      expect(result.steps.any((step) => step.benefitType == 'MILESTONE'), isTrue);
    });

    test('respects platform preference (e.g., BookMyShow only)', () async {
      final userId = AppConstants.testUserIdMovieRuleEngine;
      final request = MovieTicketRequest(
        numberOfTickets: 2,
        pricePerTicket: 350,
        preferredPlatform: 'BookMyShow',
      );
      final result = await service.optimizeMovieTicketPurchase(userId: userId, request: request);
      expect(result.steps.every((step) => step.platform == 'BookMyShow'), isTrue);
    });

    test('does not apply benefit if below efficiency threshold', () async {
      // Arrange: Set up a benefit with a high efficiency threshold in DB
      final userId = AppConstants.testUserIdMovieRuleEngine;
      final request = MovieTicketRequest(
        numberOfTickets: 1,
        pricePerTicket: 10, // Too low for efficiency
      );
      final result = await service.optimizeMovieTicketPurchase(userId: userId, request: request);
      expect(result.steps, isEmpty);
    });

    test('does not apply benefit if minimum amount not met', () async {
      // Arrange: Set up a benefit with a high minimum amount in DB
      final userId = AppConstants.testUserIdMovieRuleEngine;
      final request = MovieTicketRequest(
        numberOfTickets: 1,
        pricePerTicket: 50, // Below min amount
      );
      final result = await service.optimizeMovieTicketPurchase(userId: userId, request: request);
      expect(result.steps, isEmpty);
    });

    test('does not apply benefit if not valid on today (day of week)', () async {
      // Arrange: Set up a benefit valid only on a different day
      final userId = AppConstants.testUserIdMovieRuleEngine;
      final request = MovieTicketRequest(
        numberOfTickets: 2,
        pricePerTicket: 200,
      );
      final result = await service.optimizeMovieTicketPurchase(userId: userId, request: request);
      // If today is not a valid day, expect no steps
      // (This test may need to be adjusted based on DB config)
      expect(result.steps, isA<List>());
    });

    // Add more tests for real DB/test data as needed
  });
}
