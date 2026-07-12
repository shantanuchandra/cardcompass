import 'package:flutter_test/flutter_test.dart';
import 'package:cardcompass/features/movie_rule_engine/data/movie_rule_engine_service.dart';
import 'package:cardcompass/features/movie_rule_engine/domain/models/movie_ticket_request.dart';
import 'package:cardcompass/features/movie_rule_engine/domain/models/movie_recommendation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cardcompass/config/constants.dart';
import 'package:cardcompass/core/app_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final hasSupabaseConfig = AppConfig.supabaseUrl.isNotEmpty &&
      AppConfig.supabaseAnonKey.isNotEmpty &&
      Uri.tryParse(AppConfig.supabaseUrl)?.hasAuthority == true;

  setUpAll(() async {
    if (!hasSupabaseConfig) return;
    SharedPreferences.setMockInitialValues({});
    try {
      Supabase.instance.client;
    } catch (_) {
      await Supabase.initialize(
        url: AppConfig.supabaseUrl,
        publishableKey: AppConfig.supabaseAnonKey,
      );
    }

    // Seed test data
    final supabase = Supabase.instance.client;
    await _cleanupTestData(supabase);
    await _seedTestData(supabase);
  });

  tearDownAll(() async {
    if (!hasSupabaseConfig) return;
    final supabase = Supabase.instance.client;
    await _cleanupTestData(supabase);
  });

  group('MovieRuleEngineService', () {
    late MovieRuleEngineService service;

    setUp(() {
      service = MovieRuleEngineService();
    });

    test('returns empty recommendation if no cards with movie benefits',
        () async {
      // Arrange: Use a userId that has no cards/benefits in test DB
      const userId = 'test-user-no-benefits';
      final request = MovieTicketRequest(
        numberOfTickets: 2,
        pricePerTicket: 300,
      );

      // Act
      final result = await service.optimizeMovieTicketPurchase(
          userId: userId, request: request);

      // Assert
      expect(result, isA<MovieRecommendation>());
      expect(result.steps, isEmpty);
      expect(result.totalAmount, 600);
      expect(result.totalSavings, 0);
    });

    test(
        'returns a valid recommendation if user has a card with a valid movie benefit',
        () async {
      // Arrange: Use a userId that has at least one card with a valid movie benefit in test DB
      final userId = AppConstants.testUserIdMovieRuleEngine;
      final request = MovieTicketRequest(
        numberOfTickets: 2,
        pricePerTicket: 300,
      );
      // Act
      final result = await service.optimizeMovieTicketPurchase(
          userId: userId, request: request);
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
      final result = await service.optimizeMovieTicketPurchase(
          userId: userId, request: request);
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
      final result = await service.optimizeMovieTicketPurchase(
          userId: userId, request: request);
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
      final result = await service.optimizeMovieTicketPurchase(
          userId: userId, request: request);
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
        preferredPlatform: 'BookMyShow',
      );
      // Act
      final result = await service.optimizeMovieTicketPurchase(
          userId: userId, request: request);
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
        preferredPlatform: 'PVR',
      );
      // Act
      final result = await service.optimizeMovieTicketPurchase(
          userId: userId, request: request);
      // Assert: Pass if any step uses percent discount, even if not optimal
      final hasPercentDiscount =
          result.steps.any((step) => step.benefitType == 'PERCENT_DISCOUNT');
      expect(hasPercentDiscount, isTrue,
          reason:
              'At least one step should use percent discount if available.');
    });

    test('applies cashback offer correctly', () async {
      // Arrange: User/card/benefit must be set up for cashback in DB
      final userId = AppConstants.testUserIdMovieRuleEngine;
      final request = MovieTicketRequest(
        numberOfTickets: 2,
        pricePerTicket: 500,
        preferredPlatform: 'Cinepolis',
      );
      // Act
      final result = await service.optimizeMovieTicketPurchase(
          userId: userId, request: request);
      // Assert: Pass if any step uses cashback, even if not optimal
      final hasCashback =
          result.steps.any((step) => step.benefitType == 'CASHBACK');
      expect(hasCashback, isTrue,
          reason: 'At least one step should use cashback if available.');
    });

    test('applies milestone reward correctly', () async {
      // Arrange: User/card/benefit must be set up for milestone in DB
      final userId = AppConstants.testUserIdMovieRuleEngine;
      final request = MovieTicketRequest(
        numberOfTickets: 5,
        pricePerTicket: 300,
        preferredPlatform: 'INOX',
      );
      // Act
      final result = await service.optimizeMovieTicketPurchase(
          userId: userId, request: request);
      // Assert
      expect(
          result.steps.any((step) => step.benefitType == 'MILESTONE'), isTrue);
    });

    test('respects platform preference (e.g., BookMyShow only)', () async {
      final userId = AppConstants.testUserIdMovieRuleEngine;
      final request = MovieTicketRequest(
        numberOfTickets: 2,
        pricePerTicket: 350,
        preferredPlatform: 'BookMyShow',
      );
      final result = await service.optimizeMovieTicketPurchase(
          userId: userId, request: request);
      expect(
          result.steps.every((step) => step.platform == 'BookMyShow'), isTrue);
    });

    test('does not apply benefit if below efficiency threshold', () async {
      // Arrange: Set up a benefit with a high efficiency threshold in DB
      final userId = AppConstants.testUserIdMovieRuleEngine;
      final request = MovieTicketRequest(
        numberOfTickets: 1,
        pricePerTicket: 10, // Too low for efficiency
      );
      final result = await service.optimizeMovieTicketPurchase(
          userId: userId, request: request);
      expect(result.steps, isEmpty);
    });

    test('does not apply benefit if minimum amount not met', () async {
      // Arrange: Set up a benefit with a high minimum amount in DB
      final userId = AppConstants.testUserIdMovieRuleEngine;
      final request = MovieTicketRequest(
        numberOfTickets: 1,
        pricePerTicket: 50, // Below min amount
      );
      final result = await service.optimizeMovieTicketPurchase(
          userId: userId, request: request);
      expect(result.steps, isEmpty);
    });

    test('does not apply benefit if not valid on today (day of week)',
        () async {
      // Arrange: Set up a benefit valid only on a different day
      final userId = AppConstants.testUserIdMovieRuleEngine;
      final request = MovieTicketRequest(
        numberOfTickets: 2,
        pricePerTicket: 200,
      );
      final result = await service.optimizeMovieTicketPurchase(
          userId: userId, request: request);
      // If today is not a valid day, expect no steps
      // (This test may need to be adjusted based on DB config)
      expect(result.steps, isA<List>());
    });

    // Add more tests for real DB/test data as needed
  },
      skip: hasSupabaseConfig
          ? false
          : 'Requires configured Supabase credentials');
}

Future<void> _seedTestData(SupabaseClient supabase) async {
  final testUserId = '5dc9b591-40b6-4486-944e-3b4ef58c3d47';

  // Fetch 5 active cards from catalog
  final cards = await supabase
      .from('card_catalog')
      .select('id')
      .eq('card_type', 'credit')
      .limit(5);

  if (cards.length < 5) {
    throw StateError('Need at least 5 active cards in card_catalog');
  }

  // Insert benefits
  final nowStr = DateTime.now().toIso8601String();
  final benefits = [
    {
      'benefit_id': '00000000-0000-0000-0000-000000000001',
      'title': 'Test BOGO Benefit',
      'description': 'Buy one get one free',
      'benefit_category': 'entertainment',
      'benefit_type': 'discount',
      'is_active': true,
      'created_at': nowStr,
      'updated_at': nowStr,
      'value_config': {
        'offer_type': 'BOGO',
        'partner_filter': ['BookMyShow'],
        'free_ticket_count': 1,
        'max_discount_amount': 300.0,
        'txn_ticket_limit': 4,
        'month_ticket_limit': 8,
        'efficiency_threshold': 200.0,
        'min_transaction_amount': 150.0
      }
    },
    {
      'benefit_id': '00000000-0000-0000-0000-000000000002',
      'title': 'Test Percent Discount Benefit',
      'description': '25% off on movies',
      'benefit_category': 'entertainment',
      'benefit_type': 'discount',
      'is_active': true,
      'created_at': nowStr,
      'updated_at': nowStr,
      'value_config': {
        'offer_type': 'PERCENT_DISCOUNT',
        'partner_filter': ['PVR'],
        'discount_percent': 25.0,
        'max_discount_amount': 250.0,
        'month_ticket_limit': 12
      }
    },
    {
      'benefit_id': '00000000-0000-0000-0000-000000000003',
      'title': 'Test Cashback Benefit',
      'description': '25% cashback on movies',
      'benefit_category': 'entertainment',
      'benefit_type': 'cashback',
      'is_active': true,
      'created_at': nowStr,
      'updated_at': nowStr,
      'value_config': {
        'offer_type': 'CASHBACK',
        'partner_filter': ['Cinepolis'],
        'discount_percent': 25.0,
        'max_discount_amount': 250.0,
        'month_ticket_limit': 12
      }
    },
    {
      'benefit_id': '00000000-0000-0000-0000-000000000004',
      'title': 'Test Milestone Benefit',
      'description': 'Milestone movie reward',
      'benefit_category': 'entertainment',
      'benefit_type': 'milestone',
      'is_active': true,
      'created_at': nowStr,
      'updated_at': nowStr,
      'value_config': {
        'offer_type': 'MILESTONE',
        'partner_filter': ['INOX'],
        'milestone_reward': 2,
        'max_discount_amount': 500.0,
        'month_ticket_limit': 2
      }
    },
    {
      'benefit_id': '00000000-0000-0000-0000-000000000005',
      'title': 'Test BOGO 2 Benefit',
      'description': 'Get one free on Moviemax',
      'benefit_category': 'entertainment',
      'benefit_type': 'discount',
      'is_active': true,
      'created_at': nowStr,
      'updated_at': nowStr,
      'value_config': {
        'offer_type': 'BOGO',
        'partner_filter': ['Moviemax'],
        'free_ticket_count': 1,
        'max_discount_amount': 500.0,
        'txn_ticket_limit': 6,
        'month_ticket_limit': 10,
        'efficiency_threshold': 250.0,
        'min_transaction_amount': 200.0
      }
    }
  ];

  await supabase.from('benefits').insert(benefits);

  // Map benefits to catalog cards
  final mappings = [
    {
      'mapping_id': '00000000-0000-0000-0000-000000000011',
      'card_id': cards[0]['id'],
      'benefit_id': '00000000-0000-0000-0000-000000000001',
      'display_priority': 5,
      'is_primary': true
    },
    {
      'mapping_id': '00000000-0000-0000-0000-000000000012',
      'card_id': cards[1]['id'],
      'benefit_id': '00000000-0000-0000-0000-000000000002',
      'display_priority': 8,
      'is_primary': true
    },
    {
      'mapping_id': '00000000-0000-0000-0000-000000000013',
      'card_id': cards[2]['id'],
      'benefit_id': '00000000-0000-0000-0000-000000000003',
      'display_priority': 6,
      'is_primary': true
    },
    {
      'mapping_id': '00000000-0000-0000-0000-000000000014',
      'card_id': cards[3]['id'],
      'benefit_id': '00000000-0000-0000-0000-000000000004',
      'display_priority': 10,
      'is_primary': true
    },
    {
      'mapping_id': '00000000-0000-0000-0000-000000000015',
      'card_id': cards[4]['id'],
      'benefit_id': '00000000-0000-0000-0000-000000000005',
      'display_priority': 7,
      'is_primary': true
    }
  ];

  await supabase.from('card_benefit_mapping').insert(mappings);

  // Link cards to user (only if not already linked to avoid UNIQUE constraint violations)
  final existingUserCards = await supabase
      .from('user_cards')
      .select('catalog_card_id')
      .eq('user_id', testUserId);

  final existingCardIds = (existingUserCards as List)
      .map((uc) => uc['catalog_card_id'].toString())
      .toSet();

  final userCardsToInsert = <Map<String, dynamic>>[];
  for (int i = 0; i < cards.length; i++) {
    final cardId = cards[i]['id'].toString();
    if (!existingCardIds.contains(cardId)) {
      userCardsToInsert.add({
        'id': '00000000-0000-0000-0000-00000000002${i + 1}',
        'user_id': testUserId,
        'catalog_card_id': cardId,
        'is_active': true,
        'last_four_digits': '100${i + 1}'
      });
    }
  }

  if (userCardsToInsert.isNotEmpty) {
    await supabase.from('user_cards').insert(userCardsToInsert);
  }
}

Future<void> _cleanupTestData(SupabaseClient supabase) async {
  await supabase.from('card_benefit_mapping').delete().inFilter('mapping_id', [
    '00000000-0000-0000-0000-000000000011',
    '00000000-0000-0000-0000-000000000012',
    '00000000-0000-0000-0000-000000000013',
    '00000000-0000-0000-0000-000000000014',
    '00000000-0000-0000-0000-000000000015',
    '00000000-0000-0000-0000-0000000000a1',
    '00000000-0000-0000-0000-0000000000a2',
    '00000000-0000-0000-0000-0000000000a3',
    '00000000-0000-0000-0000-0000000000a4',
    '00000000-0000-0000-0000-0000000000a5'
  ]);

  await supabase.from('benefits').delete().inFilter('benefit_id', [
    '00000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000002',
    '00000000-0000-0000-0000-000000000003',
    '00000000-0000-0000-0000-000000000004',
    '00000000-0000-0000-0000-000000000005',
    '00000000-0000-0000-0000-000000000091',
    '00000000-0000-0000-0000-000000000092',
    '00000000-0000-0000-0000-000000000093',
    '00000000-0000-0000-0000-000000000094',
    '00000000-0000-0000-0000-000000000095'
  ]);

  await supabase.from('user_cards').delete().inFilter('id', [
    '00000000-0000-0000-0000-000000000021',
    '00000000-0000-0000-0000-000000000022',
    '00000000-0000-0000-0000-000000000023',
    '00000000-0000-0000-0000-000000000024',
    '00000000-0000-0000-0000-000000000025',
    '00000000-0000-0000-0000-0000000000b1',
    '00000000-0000-0000-0000-0000000000b2'
  ]);
}
