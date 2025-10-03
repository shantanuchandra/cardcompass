import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/models/movie_ticket_request.dart';
import '../domain/models/movie_recommendation.dart';
import '../domain/models/transaction_step.dart';
import '../domain/models/movie_benefit_config.dart';
import '../debug/card_catalog_debug.dart';

/// Core service for movie ticket rule engine optimization
/// Updated to use statement cycle-based milestone tracking instead of weekly tracking
class MovieRuleEngineService {
  final SupabaseClient _supabase = Supabase.instance.client;
  
  static const String _benefitCategory = 'entertainment';
  static const List<String> _supportedPlatforms = [
    'BookMyShow', 'PVR', 'INOX', 'Cinepolis', 'Moviemax'
  ];

  /// Generate optimized movie ticket purchase recommendations
  Future<MovieRecommendation> optimizeMovieTicketPurchase({
    required String userId,
    required MovieTicketRequest request,
  }) async {
    try {
      print('DEBUG: Starting movie ticket optimization for userId: $userId');
      
      // 1. Get user's active cards with movie benefits
      print('DEBUG: Fetching user movie benefits');
      final cardBenefits = await _getUserMovieBenefits(userId);
      
      print('DEBUG: Found ${cardBenefits.length} cards with movie benefits');
      
      if (cardBenefits.isEmpty) {
        print('DEBUG: No cards with movie benefits found, returning empty recommendation');
        return MovieRecommendation.empty(
          totalAmount: request.totalAmount,
          tickets: request.numberOfTickets,
        );
      }

      // 2. Update statement cycle milestone cache
      print('DEBUG: Updating statement cycle milestones');
      await _updateStatementCycleMilestones(userId);
      print('DEBUG: Statement cycle milestones updated');

      // 3. Evaluate all benefit scenarios
      print('DEBUG: Evaluating all benefit scenarios');
      final scenarios = await _evaluateAllScenarios(
        request: request,
        cardBenefits: cardBenefits,
        userId: userId,
      );
      print('DEBUG: Found ${scenarios.length} benefit scenarios');

      // 4. Optimize transaction splitting
      print('DEBUG: Optimizing transaction splitting, found ${scenarios.length} scenarios');
      final optimizedSteps = _optimizeTransactionSplitting(
        scenarios: scenarios,
        request: request,
      );

      // 5. Generate final recommendation
      print('DEBUG: Generating final recommendation with ${optimizedSteps.length} steps');
      return _generateRecommendation(
        steps: optimizedSteps,
        request: request,
      );

    } catch (e, stackTrace) {
      print('ERROR in movie optimization: $e');
      print('ERROR stack trace: $stackTrace');
      return MovieRecommendation.empty(
        totalAmount: request.totalAmount,
        tickets: request.numberOfTickets,
      );
    }
  }

  /// Get user's cards that have movie benefits
  Future<List<Map<String, dynamic>>> _getUserMovieBenefits(String userId) async {
    try {
      print('DEBUG: Starting _getUserMovieBenefits for userId: $userId');
      CardCatalogDebug.logQuery('Fetching user movie benefits', method: '_getUserMovieBenefits');
      
      // Fetch user's active cards
      print('DEBUG: Querying user_cards for active cards');
      final response = await _supabase
          .from('user_cards')
          .select('''
            id,
            catalog_card_id,
            card:card_catalog(
              id,
              card_name,
              network,
              bank
            )
          ''')
          .eq('user_id', userId)
          .eq('is_active', true);
      
      print('DEBUG: Found ${response.length} active user cards');
      
      List<Map<String, dynamic>> cardBenefits = [];

      // For each active card, get movie benefits
      for (final userCard in response) {
        print('DEBUG: Processing user card: ${userCard['id']} - ${userCard['card']['card_name']}');
        
        try {
          print('DEBUG: Querying card_benefits for catalog_card_id: ${userCard['card']['id']}');
          final cardBenefitsResponse = await _supabase
              .from('card_benefits')
              .select('''
                *,
                benefit:benefits!inner(*)
              ''')
              .eq('card_id', userCard['card']['id'])
              .contains('spending_categories', [_benefitCategory]);
          
          print('DEBUG: Found ${cardBenefitsResponse.length} benefits for this card');
          
          for (final benefit in cardBenefitsResponse) {
            // Parse JSON configuration
            MovieBenefitConfig? config;
            if (benefit['json_configuration'] != null) {
              try {
                Map<String, dynamic> configJson;
                
                // Check if json_configuration is already a Map or a String that needs to be parsed
                if (benefit['json_configuration'] is String) {
                  print('DEBUG: Parsing json_configuration string for benefit ID: ${benefit['id']}');
                  configJson = jsonDecode(benefit['json_configuration']);
                } else if (benefit['json_configuration'] is Map) {
                  print('DEBUG: json_configuration is already a Map for benefit ID: ${benefit['id']}');
                  configJson = Map<String, dynamic>.from(benefit['json_configuration']);
                } else {
                  print('DEBUG: Unexpected json_configuration type: ${benefit['json_configuration'].runtimeType}');
                  continue;
                }
                
                // Validate the configuration schema
                if (!CardCatalogDebug.validateBenefitConfigSchema(configJson, benefitId: benefit['id']?.toString())) {
                  print('DEBUG: Invalid benefit config schema for benefit ID: ${benefit['id']}');
                  continue;
                }
                
                config = MovieBenefitConfig.fromJson(configJson);
                print('DEBUG: Successfully parsed benefit config for benefit ID: ${benefit['id']}');
                print('DEBUG: Config offerType: ${config.offerType}');
                print('DEBUG: Config valid days: ${config.validDayOfWeek}');
                print('DEBUG: Config partners: ${config.partnerFilter}');
              } catch (e, stackTrace) {
                print('DEBUG: Error parsing benefit config: $e');
                print('DEBUG: Error stacktrace: $stackTrace');
                print('DEBUG: json_configuration type: ${benefit['json_configuration'].runtimeType}');
                print('DEBUG: json_configuration value: ${benefit['json_configuration']}');
                continue;
              }
            }

            cardBenefits.add({
              'user_card_id': userCard['id'],
              'card_id': userCard['card']['id'],
              'card_name': userCard['card']['card_name'],
              'card_network': userCard['card']['network'],
              'bank': userCard['card']['bank'],
              'priority_score': benefit['priority_score'] ?? 1,
              'benefit': benefit,
              'config': config,
              'efficiency_threshold': benefit['efficiency_threshold'],
            });
          }
        } catch (e) {
          print('DEBUG: Error processing card benefits for card ${userCard['card']['id']}: $e');
        }
      }

      print('DEBUG: Completed _getUserMovieBenefits, found ${cardBenefits.length} total benefits');
      return cardBenefits;
    } catch (e, stackTrace) {
      print('ERROR in _getUserMovieBenefits: $e');
      print('ERROR stack trace: $stackTrace');
      CardCatalogDebug.logException(e, 
        method: '_getUserMovieBenefits', 
        query: 'user_cards join card_catalog'
      );
      return [];
    }
  }

  /// Get the latest statement cycle dates for a user's card
  Future<Map<String, dynamic>?> _getLatestStatementCycle({
    required String userId,
    required String cardId,
  }) async {
    try {
      // Get the user_card_id first
      final userCardResponse = await _supabase
          .from('user_cards')
          .select('id')
          .eq('user_id', userId)
          .eq('catalog_card_id', cardId)
          .eq('is_active', true)
          .limit(1);
      
      if (userCardResponse.isEmpty) return null;
      final userCardId = userCardResponse[0]['id'];
      
      // Find the latest statement for this card
      final statementsResponse = await _supabase
          .from('statements')
          .select('id, statement_date, due_date')
          .eq('user_card_id', userCardId)
          .order('statement_date', ascending: false)
          .limit(1);
      
      if (statementsResponse.isEmpty) {
        // If no statement exists, use a default 30-day cycle from today
        final now = DateTime.now();
        final cyclePeriodEnd = now;
        final cyclePeriodStart = now.subtract(const Duration(days: 30));
        
        return {
          'statement_start_date': cyclePeriodStart.toIso8601String(),
          'statement_end_date': cyclePeriodEnd.toIso8601String(),
          'user_card_id': userCardId,
        };
      }
      
      final statement = statementsResponse[0];
      final statementDate = DateTime.parse(statement['statement_date']);
      
      // The end date is the current statement date
      final cyclePeriodEnd = statementDate;
      
      // Find the previous statement to get the start date
      final prevStatementsResponse = await _supabase
          .from('statements')
          .select('statement_date')
          .eq('user_card_id', userCardId)
          .lt('statement_date', statementDate.toIso8601String())
          .order('statement_date', ascending: false)
          .limit(1);
      
      DateTime cyclePeriodStart;
      if (prevStatementsResponse.isEmpty) {
        // If no previous statement, estimate the start date as 30 days before the end date
        cyclePeriodStart = cyclePeriodEnd.subtract(const Duration(days: 30));
      } else {
        cyclePeriodStart = DateTime.parse(prevStatementsResponse[0]['statement_date']);
      }
      
      return {
        'statement_start_date': cyclePeriodStart.toIso8601String(),
        'statement_end_date': cyclePeriodEnd.toIso8601String(),
        'user_card_id': userCardId,
      };
    } catch (e) {
      print('Error getting statement cycle: $e');
      return null;
    }
  }

  /// Update statement cycle milestone cache for user's cards
  Future<void> _updateStatementCycleMilestones(String userId) async {
    try {
      final now = DateTime.now();

      // Get all active user cards
      final userCardsResponse = await _supabase
          .from('user_cards')
          .select('id, catalog_card_id, card:card_catalog(id, card_name)')
          .eq('user_id', userId)
          .eq('is_active', true);
      
      for (final userCard in userCardsResponse) {
        final cardId = userCard['catalog_card_id'] as String;
        final userCardId = userCard['id'] as String;
        
        // Get the current statement cycle for this card
        final statementCycle = await _getLatestStatementCycle(
          userId: userId,
          cardId: cardId,
        );
        
        if (statementCycle == null) continue;
        
        final cyclePeriodStart = DateTime.parse(statementCycle['statement_start_date']);
        final cyclePeriodEnd = DateTime.parse(statementCycle['statement_end_date']);
        
        // Get total spending for this statement cycle
        final spendingResponse = await _supabase
            .from('transactions')
            .select('amount')
            .eq('user_card_id', userCardId)
            .eq('category', _benefitCategory)
            .gte('transaction_date', cyclePeriodStart.toIso8601String())
            .lte('transaction_date', cyclePeriodEnd.toIso8601String());
        
        double totalSpending = 0;
        for (final transaction in spendingResponse) {
          final amount = (transaction['amount'] ?? 0.0).toDouble();
          totalSpending += amount;
        }
        
        // Update the statement milestone cache
        await _supabase
            .from('statement_milestone_cache')
            .upsert({
              'user_id': userId,
              'card_id': cardId,
              'user_card_id': userCardId,
              'benefit_category': _benefitCategory,
              'statement_start_date': cyclePeriodStart.toIso8601String(),
              'statement_end_date': cyclePeriodEnd.toIso8601String(),
              'total_spending': totalSpending,
              'last_updated': now.toIso8601String(),
            });
      }
    } catch (e) {
      print('Error updating statement milestone cache: $e');
    }
  }

  /// Evaluate all possible benefit scenarios
  Future<List<Map<String, dynamic>>> _evaluateAllScenarios({
    required MovieTicketRequest request,
    required List<Map<String, dynamic>> cardBenefits,
    required String userId,
  }) async {
    List<Map<String, dynamic>> scenarios = [];

    for (final cardBenefit in cardBenefits) {
      final config = cardBenefit['config'] as MovieBenefitConfig?;
      if (config == null || !config.isValid) continue;

      // Check efficiency threshold
      if (!config.isEfficient(request.pricePerTicket)) {
        continue;
      }

      // Check minimum amount
      if (!config.meetsMinimumAmount(request.totalAmount)) {
        continue;
      }

      // Check day of week
      if (!config.validForDay(DateTime.now())) {
        continue;
      }

      // Evaluate for each supported platform (or user preference)
      final platforms = request.preferredPlatform != null 
          ? [request.preferredPlatform!]
          : _supportedPlatforms;

      for (final platform in platforms) {
        if (!config.appliesToPlatform(platform)) continue;

        final scenario = await _calculateBenefitScenario(
          request: request,
          cardBenefit: cardBenefit,
          config: config,
          platform: platform,
          userId: userId,
        );

        if (scenario != null) {
          scenarios.add(scenario);
        }
      }
    }

    // Sort by efficiency (savings per ticket)
    scenarios.sort((a, b) {
      final efficiencyA = (a['savings'] as double) / (a['tickets'] as int);
      final efficiencyB = (b['savings'] as double) / (b['tickets'] as int);
      return efficiencyB.compareTo(efficiencyA);
    });

    return scenarios;
  }

  /// Calculate benefit for a specific scenario
  Future<Map<String, dynamic>?> _calculateBenefitScenario({
    required MovieTicketRequest request,
    required Map<String, dynamic> cardBenefit,
    required MovieBenefitConfig config,
    required String platform,
    required String userId,
  }) async {
    try {
      print('DEBUG: Calculating benefit scenario for card: ${cardBenefit['card_name']}, platform: $platform');
      final offerType = config.offerType;
    double savings = 0.0;
    int applicableTickets = request.numberOfTickets;
    String explanation = '';

    // Check transaction limits
    if (config.transactionTicketLimit != null) {
      applicableTickets = applicableTickets.clamp(0, config.transactionTicketLimit!);
    }

    // Check monthly usage limits
    final monthlyUsage = await _getMonthlyUsage(
      userId: userId,
      cardId: cardBenefit['card_id'],
    );

    if (config.monthlyTicketLimit != null) {
      final remainingMonthlyTickets = config.monthlyTicketLimit! - monthlyUsage;
      if (remainingMonthlyTickets <= 0) return null;
      applicableTickets = applicableTickets.clamp(0, remainingMonthlyTickets);
    }

    if (applicableTickets <= 0) return null;

    switch (offerType) {
      case 'BOGO':
        final freeTickets = config.freeTicketCount ?? 1;
        final bogoSets = applicableTickets ~/ (freeTickets + 1);
        savings = bogoSets * freeTickets * request.pricePerTicket;
        
        if (config.maxDiscountAmount != null) {
          savings = savings.clamp(0, config.maxDiscountAmount!);
        }
        
        explanation = 'BOGO: Get $freeTickets free ticket(s) for every ${freeTickets + 1} purchased';
        break;

      case 'PERCENT_DISCOUNT':
        final discountPercent = config.discountPercent ?? 0.0;
        savings = (applicableTickets * request.pricePerTicket * discountPercent / 100);
        
        if (config.maxDiscountAmount != null) {
          savings = savings.clamp(0, config.maxDiscountAmount!);
        }
        
        explanation = '${discountPercent.toStringAsFixed(0)}% discount (max ₹${config.maxDiscountAmount?.toStringAsFixed(0) ?? "unlimited"})';
        break;

      case 'CASHBACK':
        final cashbackPercent = config.discountPercent ?? 0.0;
        savings = (applicableTickets * request.pricePerTicket * cashbackPercent / 100);
        
        if (config.maxDiscountAmount != null) {
          savings = savings.clamp(0, config.maxDiscountAmount!);
        }
        
        explanation = '${cashbackPercent.toStringAsFixed(1)}% cashback (max ₹${config.maxDiscountAmount?.toStringAsFixed(0) ?? "unlimited"})';
        break;

      case 'MILESTONE':
        // Milestone rewards are handled separately
        final rewardTickets = config.milestoneReward ?? 0;
        if (rewardTickets > 0) {
          savings = rewardTickets * request.pricePerTicket;
          explanation = '$rewardTickets free milestone reward ticket(s)';
        }
        break;

      default:
        return null;
    }

    if (savings <= 0) return null;

    return {
      'card_id': cardBenefit['card_id'],
      'card_name': cardBenefit['card_name'],
      'platform': platform,
      'tickets': applicableTickets,
      'amount': applicableTickets * request.pricePerTicket,
      'savings': savings,
      'benefit_type': offerType,
      'explanation': explanation,
      'priority_score': cardBenefit['priority_score'],
      'config': config,
    };
    } catch (e) {
      print('ERROR in _calculateBenefitScenario: $e');
      print('ERROR for card: ${cardBenefit['card_name']}, platform: $platform');
      CardCatalogDebug.logException(e, 
        method: '_calculateBenefitScenario', 
        query: 'benefit calculation for ${cardBenefit['card_name']}'
      );
      return null;
    }
  }

  /// Optimize transaction splitting to maximize savings
  List<TransactionStep> _optimizeTransactionSplitting({
    required List<Map<String, dynamic>> scenarios,
    required MovieTicketRequest request,
  }) {
    List<TransactionStep> steps = [];
    int remainingTickets = request.numberOfTickets;

    // Take top 3 most efficient scenarios
    final topScenarios = scenarios.take(3).toList();

    for (final scenario in topScenarios) {
      if (remainingTickets <= 0) break;

      final ticketsForThisStep = (scenario['tickets'] as int).clamp(0, remainingTickets);
      if (ticketsForThisStep <= 0) continue;

      final step = TransactionStep(
        platform: scenario['platform'],
        cardName: scenario['card_name'],
        cardId: scenario['card_id'].toString(),
        ticketCount: ticketsForThisStep,
        amount: ticketsForThisStep * request.pricePerTicket,
        savings: (scenario['savings'] as double) * (ticketsForThisStep / scenario['tickets']),
        benefitType: scenario['benefit_type'],
        explanation: scenario['explanation'],
        benefitDetails: {
          'priority_score': scenario['priority_score'],
          'efficiency': (scenario['savings'] as double) / (scenario['tickets'] as int),
        },
      );

      steps.add(step);
      remainingTickets -= ticketsForThisStep;
    }

    return steps;
  }

  /// Generate final recommendation
  MovieRecommendation _generateRecommendation({
    required List<TransactionStep> steps,
    required MovieTicketRequest request,
  }) {
    final totalSavings = steps.fold(0.0, (sum, step) => sum + step.savings);
    final totalAmount = request.totalAmount;
    final finalAmount = totalAmount - totalSavings;

    String explanation;
    if (steps.isEmpty) {
      explanation = 'No suitable movie benefits found. Consider using a general cashback card.';
    } else {
      final savingsPercent = (totalSavings / totalAmount * 100).toStringAsFixed(1);
      explanation = 'Optimized strategy saves ₹${totalSavings.toStringAsFixed(0)} '
          '($savingsPercent%) across ${steps.length} transaction(s)';
    }

    return MovieRecommendation(
      steps: steps,
      totalAmount: totalAmount,
      totalSavings: totalSavings,
      finalAmount: finalAmount,
      explanation: explanation,
      calculatedAt: DateTime.now(),
      metadata: {
        'request': request.toJson(),
        'optimization_version': '1.0',
      },
    );
  }

  /// Get statement cycle usage for a card
  Future<int> _getMonthlyUsage({
    required String userId,
    required String cardId,
  }) async {
    try {
      print('DEBUG: Getting monthly usage for userId: $userId, cardId: $cardId');
      print('DEBUG: Using user_card_id instead of card_id in transactions table query');
      // Get the current statement cycle for this card
      final statementCycle = await _getLatestStatementCycle(
        userId: userId,
        cardId: cardId,
      );
      
      if (statementCycle == null) return 0;
      
      final cyclePeriodStart = DateTime.parse(statementCycle['statement_start_date']);
      final cyclePeriodEnd = DateTime.parse(statementCycle['statement_end_date']);
      
      // Check if there's already a cached value in statement_milestone_cache
      final cacheResponse = await _supabase
          .from('statement_milestone_cache')
          .select('id')
          .eq('user_id', userId)
          .eq('card_id', cardId)
          .eq('benefit_category', _benefitCategory)
          .eq('statement_start_date', cyclePeriodStart.toIso8601String())
          .eq('statement_end_date', cyclePeriodEnd.toIso8601String())
          .limit(1);
      
      if (cacheResponse.isNotEmpty) {
        // If we have a cached entry, use the transactions count directly
        final userCardResponse = await _supabase
            .from('user_cards')
            .select('id')
            .eq('user_id', userId)
            .eq('catalog_card_id', cardId)
            .eq('is_active', true)
            .limit(1);
            
        if (userCardResponse.isEmpty) return 0;
        final userCardId = userCardResponse[0]['id'];
        
        final response = await _supabase
            .from('transactions')
            .select('amount')
            .eq('user_id', userId)
            .eq('user_card_id', userCardId)  // Fixed: using user_card_id instead of card_id
            .eq('category', _benefitCategory)
            .gte('transaction_date', cyclePeriodStart.toIso8601String())
            .lte('transaction_date', cyclePeriodEnd.toIso8601String());
        
        return response.length; // Assuming each transaction is for tickets
      } else {
        // If no cache entry exists, fallback to calendar month
        final now = DateTime.now();
        final monthStart = DateTime(now.year, now.month, 1);
        
        final userCardResponse = await _supabase
            .from('user_cards')
            .select('id')
            .eq('user_id', userId)
            .eq('catalog_card_id', cardId)
            .eq('is_active', true)
            .limit(1);
            
        if (userCardResponse.isEmpty) return 0;
        final userCardId = userCardResponse[0]['id'];
        
        final response = await _supabase
            .from('transactions')
            .select('amount')
            .eq('user_id', userId)
            .eq('user_card_id', userCardId)  // Fixed: using user_card_id instead of card_id
            .eq('category', _benefitCategory)
            .gte('transaction_date', monthStart.toIso8601String())
            .lte('transaction_date', now.toIso8601String());
        
        return response.length; // Assuming each transaction is for tickets
      }
    } catch (e) {
      print('Error getting monthly usage: $e');
      CardCatalogDebug.logException(e, 
        method: '_getMonthlyUsage',
        query: 'transactions with user_card_id'
      );
      return 0;
    }
  }

}
