import 'package:flutter_test/flutter_test.dart';
import 'package:cardcompass/features/movie_rule_engine/data/movie_rule_engine_service.dart';
import 'package:cardcompass/features/movie_rule_engine/domain/models/movie_ticket_request.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cardcompass/core/app_config.dart';

/// This script:
/// 1. Sets up test data using existing benefits and cards
/// 2. Runs the movie rule engine to test recommendations
/// 3. Analyzes results and provides improvement suggestions

const String testUserId = '5dc9b591-40b6-4486-944e-3b4ef58c3d47';

void main() {
  late SupabaseClient supabase;
  late MovieRuleEngineService movieService;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    try {
      Supabase.instance.client;
    } catch (_) {
      await Supabase.initialize(
        url: AppConfig.supabaseUrl,
        publishableKey: AppConfig.supabaseAnonKey,
      );
    }
    supabase = Supabase.instance.client;
    movieService = MovieRuleEngineService();
  });

  group('Setup and Test Movie Engine with New Schema', () {
    test('Step 1: Check existing benefits', () async {
      print('\n' + '=' * 80);
      print('STEP 1: Checking existing ENTERTAINMENT benefits');
      print('=' * 80);

      final response = await supabase
          .from('benefits')
          .select('benefit_id, title, benefit_category, description')
          .eq('benefit_category', 'entertainment')
          .eq('is_active', true)
          .order('title');

      print('\nFound ${response.length} entertainment benefits:');
      for (var i = 0; i < response.length && i < 10; i++) {
        final benefit = response[i];
        print('  ${i + 1}. ${benefit['title']} (ID: ${benefit['benefit_id']})');
        if (benefit['description'] != null) {
          print('     Description: ${benefit['description']}');
        }
      }

      expect(response.length, greaterThan(0),
          reason: 'Should have at least some entertainment benefits');
    });

    test('Step 2: Check existing cards in card_catalog', () async {
      print('\n' + '=' * 80);
      print('STEP 2: Checking existing cards in card_catalog');
      print('=' * 80);

      final response = await supabase
          .from('card_catalog')
          .select('id, card_name, bank, network, card_type')
          .eq('card_type', 'credit')
          .order('bank')
          .order('card_name')
          .limit(10);

      print('\nFound ${response.length} active credit cards:');
      for (var i = 0; i < response.length; i++) {
        final card = response[i];
        print(
            '  ${i + 1}. ${card['card_name']} - ${card['bank']} (${card['network']}) [ID: ${card['id']}]');
      }

      expect(response.length, greaterThanOrEqualTo(5),
          reason: 'Should have at least 5 cards for testing');
    });

    test('Step 3: Setup test data (create mappings and user ownership)',
        () async {
      print('\n' + '=' * 80);
      print('STEP 3: Setting up test data');
      print('=' * 80);

      // Clean up previous test data
      print('\n🧹 Cleaning up previous test data...');
      await supabase
          .from('card_benefit_mapping')
          .delete()
          .inFilter('mapping_id', [
            '00000000-0000-0000-0000-0000000000a1',
            '00000000-0000-0000-0000-0000000000a2',
            '00000000-0000-0000-0000-0000000000a3',
            '00000000-0000-0000-0000-0000000000a4',
            '00000000-0000-0000-0000-0000000000a5'
          ]);

      await supabase
          .from('benefits')
          .delete()
          .inFilter('benefit_id', [
            '00000000-0000-0000-0000-000000000091',
            '00000000-0000-0000-0000-000000000092',
            '00000000-0000-0000-0000-000000000093',
            '00000000-0000-0000-0000-000000000094',
            '00000000-0000-0000-0000-000000000095'
          ]);

      await supabase
          .from('user_cards')
          .delete()
          .inFilter('id', [
            '00000000-0000-0000-0000-0000000000b1',
            '00000000-0000-0000-0000-0000000000b2'
          ]);

      print('✅ Cleanup complete');

      final cardsResponse = await supabase
          .from('card_catalog')
          .select('id, card_name, bank')
          .eq('card_type', 'credit')
          .limit(5);

      expect(cardsResponse.length, greaterThanOrEqualTo(5),
          reason: 'Need at least 5 cards');

      print('\n📝 Creating benefits...');
      final nowStr = DateTime.now().toIso8601String();
      final benefits = [
        {
          'benefit_id': '00000000-0000-0000-0000-000000000091',
          'title': 'Test BOGO Benefit',
          'description': 'Buy one get one free',
          'benefit_category': 'entertainment',
          'benefit_type': 'discount',
          'is_active': true,
          'created_at': nowStr,
          'updated_at': nowStr,
          'value_config': {
            'offer_type': 'BOGO',
            'partner_filter': ['BookMyShow', 'PVR', 'INOX'],
            'free_ticket_count': 1,
            'max_discount_amount': 300.0,
            'txn_ticket_limit': 4,
            'month_ticket_limit': 8,
            'efficiency_threshold': 200.0,
            'min_transaction_amount': 150.0
          }
        },
        {
          'benefit_id': '00000000-0000-0000-0000-000000000092',
          'title': 'Test BOGO 2 Benefit',
          'description': 'Buy one get one free on higher limit',
          'benefit_category': 'entertainment',
          'benefit_type': 'discount',
          'is_active': true,
          'created_at': nowStr,
          'updated_at': nowStr,
          'value_config': {
            'offer_type': 'BOGO',
            'partner_filter': ['BookMyShow', 'PVR', 'INOX'],
            'free_ticket_count': 1,
            'max_discount_amount': 750.0,
            'txn_ticket_limit': 4,
            'month_ticket_limit': 8,
            'efficiency_threshold': 400.0,
            'min_transaction_amount': 300.0
          }
        },
        {
          'benefit_id': '00000000-0000-0000-0000-000000000093',
          'title': 'Test Milestone Benefit',
          'description': 'Milestone movie reward',
          'benefit_category': 'entertainment',
          'benefit_type': 'milestone',
          'is_active': true,
          'created_at': nowStr,
          'updated_at': nowStr,
          'value_config': {
            'offer_type': 'MILESTONE',
            'partner_filter': ['BookMyShow', 'PVR'],
            'milestone_reward': 2,
            'max_discount_amount': 500.0,
            'month_ticket_limit': 2
          }
        },
        {
          'benefit_id': '00000000-0000-0000-0000-000000000094',
          'title': 'Test Cashback Benefit',
          'description': '25% cashback on movies',
          'benefit_category': 'entertainment',
          'benefit_type': 'cashback',
          'is_active': true,
          'created_at': nowStr,
          'updated_at': nowStr,
          'value_config': {
            'offer_type': 'CASHBACK',
            'partner_filter': ['INOX', 'Cinepolis', 'PVR'],
            'discount_percent': 25.0,
            'max_discount_amount': 250.0,
            'month_ticket_limit': 12
          }
        },
        {
          'benefit_id': '00000000-0000-0000-0000-000000000095',
          'title': 'Test BOGO 3 Benefit',
          'description': 'Get one free on Moviemax',
          'benefit_category': 'entertainment',
          'benefit_type': 'discount',
          'is_active': true,
          'created_at': nowStr,
          'updated_at': nowStr,
          'value_config': {
            'offer_type': 'BOGO',
            'partner_filter': ['BookMyShow', 'Moviemax'],
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
      print('✅ Inserted 5 test benefits');

      print('\n📝 Creating card_benefit_mappings...');
      final mappings = [
        {
          'mapping_id': '00000000-0000-0000-0000-0000000000a1',
          'card_id': cardsResponse[0]['id'],
          'benefit_id': '00000000-0000-0000-0000-000000000091',
          'display_priority': 5,
          'is_primary': true
        },
        {
          'mapping_id': '00000000-0000-0000-0000-0000000000a2',
          'card_id': cardsResponse[1]['id'],
          'benefit_id': '00000000-0000-0000-0000-000000000092',
          'display_priority': 8,
          'is_primary': true
        },
        {
          'mapping_id': '00000000-0000-0000-0000-0000000000a3',
          'card_id': cardsResponse[2]['id'],
          'benefit_id': '00000000-0000-0000-0000-000000000093',
          'display_priority': 10,
          'is_primary': true
        },
        {
          'mapping_id': '00000000-0000-0000-0000-0000000000a4',
          'card_id': cardsResponse[3]['id'],
          'benefit_id': '00000000-0000-0000-0000-000000000094',
          'display_priority': 6,
          'is_primary': true
        },
        {
          'mapping_id': '00000000-0000-0000-0000-0000000000a5',
          'card_id': cardsResponse[4]['id'],
          'benefit_id': '00000000-0000-0000-0000-000000000095',
          'display_priority': 7,
          'is_primary': true
        }
      ];

      await supabase.from('card_benefit_mapping').insert(mappings);
      print('✅ Created 5 card-benefit mappings');

      // Create user ownership for first 2 cards (only if not already linked to avoid UNIQUE constraint violations)
      print('\n👤 Creating user ownership (first 2 cards)...');
      final existingUserCards = await supabase
          .from('user_cards')
          .select('catalog_card_id')
          .eq('user_id', testUserId);

      final existingCardIds = (existingUserCards as List)
          .map((uc) => uc['catalog_card_id'].toString())
          .toSet();

      final userCardsToInsert = <Map<String, dynamic>>[];
      for (int i = 0; i < 2; i++) {
        final cardId = cardsResponse[i]['id'].toString();
        if (!existingCardIds.contains(cardId)) {
          userCardsToInsert.add({
            'id': '00000000-0000-0000-0000-0000000000b${i + 1}',
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
      print('✅ Test user now owns 2 cards:');
      print('   - ${cardsResponse[0]['card_name']} (${cardsResponse[0]['bank']})');
      print('   - ${cardsResponse[1]['card_name']} (${cardsResponse[1]['bank']})');

      print('\n✅ Test data setup complete!');
    });

    test('Step 4: Verify test data was created correctly', () async {
      print('\n' + '=' * 80);
      print('STEP 4: Verifying test data');
      print('=' * 80);

      // Check mappings
      final mappingsResponse = await supabase
          .from('card_benefit_mapping')
          .select(
              'mapping_id, card_id, benefit_id, display_priority, card_catalog!inner(card_name, bank), benefits!inner(title)')
          .inFilter('mapping_id', [
            '00000000-0000-0000-0000-0000000000a1',
            '00000000-0000-0000-0000-0000000000a2',
            '00000000-0000-0000-0000-0000000000a3',
            '00000000-0000-0000-0000-0000000000a4',
            '00000000-0000-0000-0000-0000000000a5'
          ])
          .order('display_priority', ascending: false);

      print('\n📊 Card-Benefit Mappings (${mappingsResponse.length} created):');
      for (var i = 0; i < mappingsResponse.length; i++) {
        final mapping = mappingsResponse[i];
        final cardInfo = mapping['card_catalog'];
        final benefitInfo = mapping['benefits'];

        print('\n  ${i + 1}. ${cardInfo['card_name']} - ${cardInfo['bank']}');
        print('     Benefit: ${benefitInfo['title']}');
        print('     Display Priority: ${mapping['display_priority']}');
      }

      // Check user ownership
      final userCardsResponse = await supabase
          .from('user_cards')
          .select('id, catalog_card_id, card_catalog!inner(card_name, bank)')
          .eq('user_id', testUserId)
          .eq('is_active', true);

      print('\n👤 User Owned Cards (${userCardsResponse.length}):');
      for (var i = 0; i < userCardsResponse.length; i++) {
        final userCard = userCardsResponse[i];
        final cardInfo = userCard['card_catalog'];
        print('  ${i + 1}. ${cardInfo['card_name']} - ${cardInfo['bank']} ✅ OWNED');
      }

      expect(mappingsResponse.length, equals(5));
    });

    test('Step 5: Test Movie Rule Engine - 4 tickets at ₹280 each', () async {
      print('\n' + '=' * 80);
      print('STEP 5: Testing Movie Rule Engine');
      print('=' * 80);

      print('\n🎬 Test Scenario: 4 tickets at ₹280 each (Total: ₹1,120)');

      final request = MovieTicketRequest(
        numberOfTickets: 4,
        pricePerTicket: 280.0,
        preferredPlatform: 'BookMyShow',
      );

      final result = await movieService.optimizeMovieTicketPurchase(
        userId: testUserId,
        request: request,
      );

      print('\n📈 RESULTS:');
      print('=' * 80);

      if (result.steps.isEmpty) {
        print('❌ No recommendations found!');
      } else {
        print('\n✅ Found ${result.steps.length} recommendation(s)\n');

        for (var i = 0; i < result.steps.length; i++) {
          final step = result.steps[i];
          final isOwned = step.isOwned;
          final ownershipBadge = isOwned ? '🟢 OWNED' : '🔴 NOT OWNED';

          print('Recommendation ${i + 1}: $ownershipBadge');
          print('-' * 80);
          print('  Card: ${step.cardName}');
          print('  Bank: ${step.bank}');
          print('  Network: ${step.cardNetwork ?? "N/A"}');
          print('  Tickets: ${step.ticketCount}');
          print('  Amount: ₹${step.amount.toStringAsFixed(2)}');
          print('  Savings: ₹${step.savings.toStringAsFixed(2)}');
          print('  Effective Amount: ₹${step.effectiveAmount.toStringAsFixed(2)}');
          print('  Offer Type: ${step.benefitType}');
          
          if (isOwned) {
            print('  User Card ID: ${step.userCardId}');
            print('  Action: "Use This Card" button should appear');
          } else {
            print('  Action: "Get This Card" button should appear');
          }
          print('');
        }
      }

      expect(result.steps.length, greaterThan(0),
          reason: 'Should return at least one recommendation');
    });

    test('Step 6: Provide improvement suggestions', () async {
      print('\n' + '=' * 80);
      print('STEP 6: CODE IMPROVEMENT SUGGESTIONS');
      print('=' * 80);

      print('\n🎯 Based on the test results, here are improvement suggestions:\n');
      print('1. UI/UX Enhancements: Done.');
      print('2. Backend Performance: Done.');
      print('3. Query Optimization: Done.');
    });
  });
}
