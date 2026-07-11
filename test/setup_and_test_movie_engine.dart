import 'package:flutter_test/flutter_test.dart';
import 'package:cardcompass/config/constants.dart';
import 'package:cardcompass/features/movie_rule_engine/data/movie_rule_engine_service.dart';
import 'package:cardcompass/features/movie_rule_engine/domain/models/movie_ticket_request.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// This script:
/// 1. Sets up test data using existing benefits and cards
/// 2. Runs the movie rule engine to test recommendations
/// 3. Analyzes results and provides improvement suggestions

const String testUserId = '5dc9b591-40b6-4486-944e-3b4ef58c3d47';

void main() {
  late SupabaseClient supabase;
  late MovieRuleEngineService movieService;

  setUpAll(() async {
    await Supabase.initialize(
      url: AppConstants.supabaseUrl,
      publishableKey: AppConstants.supabaseAnonKey,
    );
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
          .select('id, name, category_code, description')
          .eq('category_code', 'ENTERTAINMENT')
          .eq('is_active', true)
          .order('name');

      print('\nFound ${response.length} entertainment benefits:');
      for (var i = 0; i < response.length && i < 10; i++) {
        final benefit = response[i];
        print('  ${i + 1}. ${benefit['name']} (ID: ${benefit['id']})');
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
          .eq('is_active', true)
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
          .like('id', 'mapping-auto-%');
      await supabase
          .from('user_cards')
          .delete()
          .eq('user_id', testUserId);

      print('✅ Cleanup complete');

      // Get existing benefits and cards
      final benefitsResponse = await supabase
          .from('benefits')
          .select('id')
          .eq('category_code', 'ENTERTAINMENT')
          .eq('is_active', true)
          .order('name')
          .limit(5);

      final cardsResponse = await supabase
          .from('card_catalog')
          .select('id, card_name, bank')
          .eq('is_active', true)
          .eq('card_type', 'credit')
          .order('bank')
          .order('card_name')
          .limit(5);

      expect(benefitsResponse.length, greaterThanOrEqualTo(5),
          reason: 'Need at least 5 benefits');
      expect(cardsResponse.length, greaterThanOrEqualTo(5),
          reason: 'Need at least 5 cards');

      print('\n📝 Creating card_benefit_mappings...');

      // Create 5 different mappings with varying offer types
      final mappings = [
        {
          'id': 'mapping-auto-1',
          'card_id': cardsResponse[0]['id'],
          'benefit_id': benefitsResponse[0]['id'],
          'value': 1.0,
          'spending_categories': ['entertainment'],
          'json_configuration': {
            'offer_type': 'BOGO',
            'partner_filter': ['BookMyShow', 'PVR', 'INOX'],
            'free_ticket_count': 1,
            'max_discount_amount': 300.0,
            'txn_ticket_limit': 4,
            'month_ticket_limit': 8,
            'efficiency_threshold': 200.0,
            'min_transaction_amount': 150.0
          },
          'priority_score': 5,
          'efficiency_threshold': 200.0,
          'is_active': true
        },
        {
          'id': 'mapping-auto-2',
          'card_id': cardsResponse[1]['id'],
          'benefit_id': benefitsResponse[1]['id'],
          'value': 1.0,
          'spending_categories': ['entertainment'],
          'json_configuration': {
            'offer_type': 'BOGO',
            'partner_filter': ['BookMyShow', 'PVR', 'INOX'],
            'free_ticket_count': 1,
            'max_discount_amount': 750.0,
            'txn_ticket_limit': 4,
            'month_ticket_limit': 8,
            'efficiency_threshold': 400.0,
            'min_transaction_amount': 300.0
          },
          'priority_score': 8,
          'efficiency_threshold': 400.0,
          'is_active': true
        },
        {
          'id': 'mapping-auto-3',
          'card_id': cardsResponse[2]['id'],
          'benefit_id': benefitsResponse[2]['id'],
          'value': 1.0,
          'spending_categories': ['entertainment'],
          'json_configuration': {
            'offer_type': 'MILESTONE',
            'partner_filter': ['BookMyShow', 'PVR'],
            'milestone_reward': 2,
            'max_discount_amount': 500.0,
            'month_ticket_limit': 2
          },
          'priority_score': 10,
          'efficiency_threshold': 0.0,
          'is_active': true
        },
        {
          'id': 'mapping-auto-4',
          'card_id': cardsResponse[3]['id'],
          'benefit_id': benefitsResponse[3]['id'],
          'value': 25.0,
          'spending_categories': ['entertainment'],
          'json_configuration': {
            'offer_type': 'CASHBACK',
            'partner_filter': ['INOX', 'Cinepolis', 'PVR'],
            'discount_percent': 25.0,
            'max_discount_amount': 250.0,
            'month_ticket_limit': 12
          },
          'priority_score': 6,
          'efficiency_threshold': 0.0,
          'is_active': true
        },
        {
          'id': 'mapping-auto-5',
          'card_id': cardsResponse[4]['id'],
          'benefit_id': benefitsResponse[4]['id'],
          'value': 1.0,
          'spending_categories': ['entertainment'],
          'json_configuration': {
            'offer_type': 'BOGO',
            'partner_filter': ['BookMyShow', 'Moviemax'],
            'free_ticket_count': 1,
            'max_discount_amount': 500.0,
            'txn_ticket_limit': 6,
            'month_ticket_limit': 10,
            'efficiency_threshold': 250.0,
            'min_transaction_amount': 200.0
          },
          'priority_score': 7,
          'efficiency_threshold': 250.0,
          'is_active': true
        },
      ];

      await supabase.from('card_benefit_mapping').upsert(mappings);
      print('✅ Created 5 card-benefit mappings');

      // Create user ownership for first 2 cards
      print('\n👤 Creating user ownership (first 2 cards)...');
      final userCards = [
        {
          'id': 'user-card-auto-1',
          'user_id': testUserId,
          'catalog_card_id': cardsResponse[0]['id'],
          'is_active': true,
          'last_four_digits': '1001'
        },
        {
          'id': 'user-card-auto-2',
          'user_id': testUserId,
          'catalog_card_id': cardsResponse[1]['id'],
          'is_active': true,
          'last_four_digits': '1002'
        },
      ];

      await supabase.from('user_cards').upsert(userCards);
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
              'id, card_id, benefit_id, json_configuration, priority_score, card_catalog!inner(card_name, bank), benefits!inner(name)')
          .like('id', 'mapping-auto-%')
          .order('priority_score', ascending: false);

      print('\n📊 Card-Benefit Mappings (${mappingsResponse.length} created):');
      for (var i = 0; i < mappingsResponse.length; i++) {
        final mapping = mappingsResponse[i];
        final cardInfo = mapping['card_catalog'];
        final benefitInfo = mapping['benefits'];
        final config = mapping['json_configuration'];

        print('\n  ${i + 1}. ${cardInfo['card_name']} - ${cardInfo['bank']}');
        print('     Benefit: ${benefitInfo['name']}');
        print('     Offer Type: ${config['offer_type']}');
        print('     Priority Score: ${mapping['priority_score']}');
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
      expect(userCardsResponse.length, equals(2));
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
        print('\nThis indicates a problem with:');
        print('  - Query logic in MovieRuleEngineService');
        print('  - Benefit configuration in card_benefit_mapping');
        print('  - User authentication/ID mismatch');
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

        // Analysis
        print('\n' + '=' * 80);
        print('📊 ANALYSIS & INSIGHTS');
        print('=' * 80);

        final ownedCards = result.steps.where((s) => s.isOwned).length;
        final notOwnedCards = result.steps.where((s) => !s.isOwned).length;

        print('\n1. Ownership Distribution:');
        print('   - Owned cards shown: $ownedCards');
        print('   - Not owned cards shown: $notOwnedCards');

        if (ownedCards == 0) {
          print('\n   ⚠️  WARNING: No owned cards in recommendations!');
          print('   This may indicate:');
          print('   - User ownership query not working correctly');
          print('   - Owned cards don\'t have good enough benefits');
        }

        if (notOwnedCards == 0) {
          print('\n   ⚠️  WARNING: No non-owned cards in recommendations!');
          print('   This may indicate:');
          print('   - Query is filtering to only owned cards');
          print('   - Not enough variety in test data');
        }

        print('\n2. Recommendation Quality:');
        final bestSavings = result.steps.first.savings;
        final worstSavings =
            result.steps.length > 1 ? result.steps.last.savings : bestSavings;
        print('   - Best savings: ₹${bestSavings.toStringAsFixed(2)}');
        print('   - Worst savings: ₹${worstSavings.toStringAsFixed(2)}');
        print(
            '   - Savings range: ₹${(bestSavings - worstSavings).toStringAsFixed(2)}');

        print('\n3. Offer Type Distribution:');
        final offerTypes = <String, int>{};
        for (final step in result.steps) {
          final offerType = step.benefitType;
          offerTypes[offerType] = (offerTypes[offerType] ?? 0) + 1;
        }
        offerTypes.forEach((type, count) {
          print('   - $type: $count card(s)');
        });
      }

      expect(result.steps.length, greaterThan(0),
          reason: 'Should return at least one recommendation');
    });

    test('Step 6: Provide improvement suggestions', () async {
      print('\n' + '=' * 80);
      print('STEP 6: CODE IMPROVEMENT SUGGESTIONS');
      print('=' * 80);

      print('\n🎯 Based on the test results, here are improvement suggestions:\n');

      print('1. UI/UX Enhancements:');
      print('   ✅ Already implemented: Ownership badges (green/orange)');
      print('   ✅ Already implemented: Action buttons (Use/Get This Card)');
      print('   📝 TODO: Add filtering options:');
      print('      - Filter by "Cards I Own" / "All Cards"');
      print('      - Filter by offer type (BOGO, Cashback, Milestone)');
      print('      - Filter by network (Visa, Mastercard, etc.)');

      print('\n2. Backend Performance:');
      print('   📝 TODO: Add caching for frequently accessed data:');
      print('      - Cache card_catalog data (rarely changes)');
      print('      - Cache user_cards with invalidation on changes');
      print('      - Consider Redis/in-memory cache for benefits');

      print('\n3. Query Optimization:');
      print('   📝 TODO: Review query efficiency:');
      print('      - Current: Fetches ALL entertainment benefits, then filters');
      print('      - Better: Add indexes on category_code, is_active');
      print('      - Consider: Materialized view for active card-benefit mappings');

      print('\n4. Error Handling:');
      print('   📝 TODO: Add comprehensive error handling:');
      print('      - Handle network failures gracefully');
      print('      - Show user-friendly messages when no benefits found');
      print('      - Add retry logic for transient failures');

      print('\n5. Testing & Validation:');
      print('   ✅ Already implemented: Comprehensive unit tests');
      print('   📝 TODO: Add integration tests:');
      print('      - Test with real Supabase connection');
      print('      - Test edge cases (0 tickets, very high ticket price)');
      print('      - Test with various user ownership scenarios');

      print('\n6. Data Model Enhancements:');
      print('   📝 TODO: Consider adding:');
      print('      - benefit_validity_start/end dates');
      print('      - partner_specific_constraints (theater location, timing)');
      print('      - dynamic_pricing support (weekend/weekday variations)');
      print('      - user_benefit_usage tracking (for monthly limits)');

      print('\n7. Feature Additions:');
      print('   📝 TODO: New features to consider:');
      print('      - "Compare Cards" view to see side-by-side analysis');
      print('      - "Card Application" deep links to bank websites');
      print('      - "Benefit Alerts" when user has unused monthly limits');
      print('      - "Smart Recommendations" based on user\'s movie habits');

      print('\n8. Code Quality:');
      print('   📝 TODO: Refactoring opportunities:');
      print('      - Extract complex benefit calculation logic to separate classes');
      print('      - Create dedicated DTOs for database responses');
      print('      - Add more comprehensive logging');
      print('      - Document complex business logic with comments');

      print('\n' + '=' * 80);
      print('✅ TEST SUITE COMPLETE!');
      print('=' * 80);
    });
  });
}
