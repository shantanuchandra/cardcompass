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

  /// Get all card-benefit combinations for display (no optimization, just listing)
  Future<List<Map<String, dynamic>>> getAllMovieCardBenefits({
    required String userId,
  }) async {
    try {
      print('DEBUG: Fetching all movie card-benefit combinations');
      
      // Get all cards with benefits
      final cardBenefits = await _getUserMovieBenefits(userId);
      
      // Return structured data with all details
      return cardBenefits.map((cb) {
        final benefit = cb['benefit'] as Map<String, dynamic>;
        final config = cb['config'] as MovieBenefitConfig?;
        
        // Extract platform from value_config
        String? platform;
        if (benefit['value_config'] != null) {
          final valueConfig = benefit['value_config'] is String
              ? jsonDecode(benefit['value_config'])
              : benefit['value_config'];
          platform = valueConfig['platform'];
        }
        
        // Format benefit details
        String benefitDescription = '';
        if (config != null) {
          switch (config.offerType) {
            case 'PERCENT_DISCOUNT':
              benefitDescription = '${config.discountPercent?.toStringAsFixed(0)}% off';
              if (config.maxDiscountAmount != null) {
                benefitDescription += ' (max ₹${config.maxDiscountAmount?.toStringAsFixed(0)})';
              }
              break;
            case 'BOGO':
              benefitDescription = 'Buy ${(config.freeTicketCount ?? 1) + 1} Get ${config.freeTicketCount ?? 1} Free';
              break;
            case 'CASHBACK':
              benefitDescription = '${config.discountPercent?.toStringAsFixed(1)}% cashback';
              break;
            case 'MILESTONE':
              benefitDescription = 'Milestone reward';
              break;
            default:
              benefitDescription = benefit['title'] ?? 'Entertainment benefit';
          }
        } else {
          benefitDescription = benefit['title'] ?? 'Entertainment benefit';
        }
        
        return {
          'card_id': cb['card_id'],
          'card_name': cb['card_name'],
          'card_network': cb['card_network'],
          'bank': cb['bank'],
          'benefit_title': benefit['title'],
          'benefit_description': benefitDescription,
          'platform': platform ?? 'All platforms',
          'is_owned': cb['is_owned'],
          'user_card_id': cb['user_card_id'],
          'priority_score': cb['priority_score'],
          'config': config,
        };
      }).toList();
    } catch (e, stackTrace) {
      print('ERROR in getAllMovieCardBenefits: $e');
      print('Stack trace: $stackTrace');
      return [];
    }
  }

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

      // 3. Find single best benefit (optimized for single recommendation)
      print('DEBUG: Finding best benefit using smart ranking');
      final bestScenario = await _findBestBenefit(
        request: request,
        cardBenefits: cardBenefits,
        userId: userId,
      );
      
      if (bestScenario == null) {
        print('DEBUG: No valid benefit scenarios found');
        return MovieRecommendation.empty(
          totalAmount: request.totalAmount,
          tickets: request.numberOfTickets,
        );
      }
      
      print('DEBUG: Best card: ${bestScenario['card_name']} on ${bestScenario['platform']} (saves ₹${bestScenario['savings']})');

      // 4. Generate single-step recommendation
      print('DEBUG: Generating recommendation with best benefit');
      return _generateSingleRecommendation(
        scenario: bestScenario,
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

  /// Get ALL cards with movie benefits (not just user-owned cards)
  /// Returns both owned and non-owned cards with benefits
  Future<List<Map<String, dynamic>>> _getUserMovieBenefits(String userId) async {
    try {
      print('DEBUG: Starting _getUserMovieBenefits for userId: $userId');
      CardCatalogDebug.logQuery('Fetching ALL movie benefits from new schema', method: '_getUserMovieBenefits');
      
      // Step 1: Get user's active cards for ownership checking
      print('DEBUG: Querying user_cards for ownership info');
      final userCardsResponse = await _supabase
          .from('user_cards')
          .select('id, catalog_card_id')
          .eq('user_id', userId)
          .eq('is_active', true);
      
      final ownedCardIds = userCardsResponse.map((uc) => uc['catalog_card_id'].toString()).toSet();
      print('DEBUG: User owns ${ownedCardIds.length} cards: $ownedCardIds');
      
      // Step 2: Query actual schema - simpler approach to avoid PostgREST join issues
      // First, get entertainment benefits
      print('DEBUG: Querying entertainment benefits');
      final benefitsResponse = await _supabase
          .from('benefits')
          .select('benefit_id, title, description, benefit_category, benefit_type, value_config')
          .eq('benefit_category', 'entertainment')
          .eq('is_active', true);
      
      if (benefitsResponse.isEmpty) {
        print('DEBUG: No entertainment benefits found');
        return [];
      }
      
      print('DEBUG: Found ${benefitsResponse.length} entertainment benefits');
      final benefitIds = benefitsResponse.map((b) => b['benefit_id'].toString()).toList();
      
      // Step 3: Get card-benefit mappings for these benefits
      print('DEBUG: Querying card_benefit_mapping for entertainment benefits');
      final mappingsResponse = await _supabase
          .from('card_benefit_mapping')
          .select('mapping_id, card_id, benefit_id, display_priority, is_primary')
          .inFilter('benefit_id', benefitIds)
          .eq('is_primary', true);
      
      if (mappingsResponse.isEmpty) {
        print('DEBUG: No card mappings found for entertainment benefits');
        return [];
      }
      
      print('DEBUG: Found ${mappingsResponse.length} card-benefit mappings');
      final cardIds = mappingsResponse.map((m) => m['card_id'].toString()).toSet().toList();
      
      // Step 4: Get card details
      print('DEBUG: Querying card_catalog for mapped cards');
      final cardsResponse = await _supabase
          .from('card_catalog')
          .select('id, card_name, network, bank')
          .inFilter('id', cardIds);
      
      print('DEBUG: Found ${cardsResponse.length} cards with entertainment benefits');
      
      
      // Step 5: Create lookup maps for efficient processing
      final benefitMap = {for (var b in benefitsResponse) b['benefit_id'].toString(): b};
      final cardMap = {for (var c in cardsResponse) c['id'].toString(): c};
      
      List<Map<String, dynamic>> cardBenefits = [];

      // Step 6: Process all mappings and combine data
      for (final mapping in mappingsResponse) {
        final benefitId = mapping['benefit_id'].toString();
        final cardId = mapping['card_id'].toString();
        
        final benefit = benefitMap[benefitId];
        final card = cardMap[cardId];
        
        if (benefit == null || card == null) {
          print('DEBUG: Skipping mapping - missing benefit or card data');
          continue;
        }
        
        print('DEBUG: Processing: ${card['card_name']} -> ${benefit['title']}');
        
        // Check if user owns this card
        final isOwned = ownedCardIds.contains(cardId);
        print('DEBUG: Card ${card['card_name']} is ${isOwned ? "OWNED" : "NOT OWNED"} by user');
        
        // Get user_card_id if owned
        String? userCardId;
        if (isOwned) {
            final uc = userCardsResponse.firstWhere(
              (uc) => uc['catalog_card_id'].toString() == card['id'].toString(),
              orElse: () => <String, dynamic>{},
            );
            userCardId = uc['id']?.toString();
          }
          
          // Parse benefit configuration from value_config
          MovieBenefitConfig? config;
          if (benefit['value_config'] != null) {
            try {
              Map<String, dynamic> configJson;
              
              // Check if value_config is already a Map or a String that needs to be parsed
              if (benefit['value_config'] is String) {
                print('DEBUG: Parsing value_config string for benefit ID: ${benefit['benefit_id']}');
                configJson = jsonDecode(benefit['value_config']);
              } else if (benefit['value_config'] is Map) {
                print('DEBUG: value_config is already a Map for benefit ID: ${benefit['benefit_id']}');
                configJson = Map<String, dynamic>.from(benefit['value_config']);
              } else {
                print('DEBUG: Unexpected value_config type: ${benefit['value_config'].runtimeType}');
                continue;
              }
              
              // Validate the configuration schema  
              if (!CardCatalogDebug.validateBenefitConfigSchema(configJson, benefitId: benefit['benefit_id']?.toString())) {
                print('DEBUG: Invalid benefit config schema for benefit ID: ${benefit['benefit_id']} - using defaults');
                // Create a default config instead of skipping
                config = null; // Will use default calculation later
              } else {
                config = MovieBenefitConfig.fromJson(configJson);
                print('DEBUG: Successfully parsed benefit config for benefit ID: ${benefit['benefit_id']}');
                print('DEBUG: Config offerType: ${config.offerType}');
                print('DEBUG: Config valid days: ${config.validDayOfWeek}');
                print('DEBUG: Config partners: ${config.partnerFilter}');
              }
            } catch (e, stackTrace) {
              print('DEBUG: Error parsing benefit config: $e');
              print('DEBUG: Error stacktrace: $stackTrace');
              print('DEBUG: value_config type: ${benefit['value_config'].runtimeType}');
              print('DEBUG: value_config value: ${benefit['value_config']}');
              continue;
            }
          }

        cardBenefits.add({
          'user_card_id': userCardId, // null if not owned
          'card_id': card['id'],
          'card_name': card['card_name'],
          'card_network': card['network'],
          'bank': card['bank'],
          'priority_score': mapping['display_priority'] ?? 1,
          'benefit': benefit,
          'mapping': mapping,
          'config': config,
          'efficiency_threshold': 0.0, // Not in current schema
          'is_owned': isOwned, // NEW: flag to indicate ownership
        });
      }

      print('DEBUG: Completed _getUserMovieBenefits, found ${cardBenefits.length} total benefits');
      print('DEBUG: Owned cards: ${cardBenefits.where((cb) => cb['is_owned'] == true).length}');
      print('DEBUG: Non-owned cards: ${cardBenefits.where((cb) => cb['is_owned'] == false).length}');
      return cardBenefits;
    } catch (e, stackTrace) {
      print('ERROR in _getUserMovieBenefits: $e');
      print('ERROR stack trace: $stackTrace');
      CardCatalogDebug.logException(e, 
        method: '_getUserMovieBenefits', 
        query: 'benefits join card_benefit_mapping join card_catalog'
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

  /// Find the single best benefit using comprehensive ranking
  /// Returns the top-ranked scenario or null if none found
  Future<Map<String, dynamic>?> _findBestBenefit({
    required MovieTicketRequest request,
    required List<Map<String, dynamic>> cardBenefits,
    required String userId,
  }) async {
    List<Map<String, dynamic>> rankedScenarios = [];

    // Determine platforms to evaluate
    final platforms = request.preferredPlatform != null 
        ? [request.preferredPlatform!]
        : _supportedPlatforms;

    print('DEBUG: Evaluating ${cardBenefits.length} cards across ${platforms.length} platform(s)');

    // Evaluate each card-platform combination
    for (final cardBenefit in cardBenefits) {
      final config = cardBenefit['config'] as MovieBenefitConfig?;
      final isOwned = cardBenefit['is_owned'] as bool;
      
      for (final platform in platforms) {
        // Quick filters before expensive calculation
        if (config != null) {
          if (!config.isEfficient(request.pricePerTicket)) continue;
          if (!config.meetsMinimumAmount(request.totalAmount)) continue;
          if (!config.validForDay(DateTime.now())) continue;
          if (!config.appliesToPlatform(platform)) continue;
        }

        final scenario = await _calculateBenefitScenario(
          request: request,
          cardBenefit: cardBenefit,
          config: config,
          platform: platform,
          userId: userId,
        );

        if (scenario != null && scenario['savings'] > 0) {
          // Calculate comprehensive ranking score
          final savingsPercent = ((scenario['savings'] as double) / request.totalAmount) * 100;
          final savingsPerTicket = (scenario['savings'] as double) / (scenario['tickets'] as int);
          final displayPriority = (cardBenefit['priority_score'] ?? 1) as int;
          
          // Bonus factors
          final ownershipBonus = isOwned ? 30.0 : 0.0;
          final platformBonus = (request.preferredPlatform == platform) ? 20.0 : 0.0;
          final priorityScore = (displayPriority / 10.0) * 10.0; // Normalize to 0-10 range
          
          // Comprehensive ranking: weighted sum
          final rankingScore = 
              (savingsPercent * 0.4) +         // 40% weight on savings percentage
              ownershipBonus +                  // 30 points if owned
              platformBonus +                   // 20 points for platform match
              priorityScore;                    // Up to 10 points from display priority
          
          scenario['ranking_score'] = rankingScore;
          scenario['savings_percent'] = savingsPercent;
          scenario['savings_per_ticket'] = savingsPerTicket;
          
          rankedScenarios.add(scenario);
          
          print('DEBUG: ${cardBenefit['card_name']} on $platform: '
                'saves ${savingsPercent.toStringAsFixed(1)}%, '
                'rank=${rankingScore.toStringAsFixed(1)}, '
                'owned=$isOwned');
        }
      }
    }

    if (rankedScenarios.isEmpty) {
      print('DEBUG: No valid scenarios found');
      return null;
    }

    // Sort by ranking score descending
    rankedScenarios.sort((a, b) => 
      (b['ranking_score'] as double).compareTo(a['ranking_score'] as double)
    );

    final winner = rankedScenarios.first;
    print('DEBUG: Winner: ${winner['card_name']} on ${winner['platform']} '
          '(rank=${winner['ranking_score']}, saves=₹${winner['savings']})');
    
    // Early exit check: if winner is significantly better (2x ranking score)
    if (rankedScenarios.length > 1) {
      final runnerUp = rankedScenarios[1];
      final winnerScore = winner['ranking_score'] as double;
      final runnerUpScore = runnerUp['ranking_score'] as double;
      
      if (winnerScore > runnerUpScore * 1.5) {
        print('DEBUG: Clear winner found (${winnerScore.toStringAsFixed(1)} vs ${runnerUpScore.toStringAsFixed(1)})');
      }
    }

    return winner;
  }

  /// Generate a single-step recommendation from the best scenario
  MovieRecommendation _generateSingleRecommendation({
    required Map<String, dynamic> scenario,
    required MovieTicketRequest request,
  }) {
    final step = TransactionStep(
      platform: scenario['platform'],
      cardName: scenario['card_name'],
      cardId: scenario['card_id'].toString(),
      ticketCount: scenario['tickets'],
      amount: scenario['amount'],
      savings: scenario['savings'],
      benefitType: scenario['benefit_type'],
      explanation: scenario['explanation'],
      benefitDetails: {
        'priority_score': scenario['priority_score'],
        'efficiency': scenario['savings_per_ticket'],
        'is_owned': scenario['is_owned'],
        'user_card_id': scenario['user_card_id'],
        'card_network': scenario['card_network'],
        'bank': scenario['bank'],
        'ranking_score': scenario['ranking_score'],
        'savings_percent': scenario['savings_percent'],
      },
    );

    final totalSavings = scenario['savings'] as double;
    final totalAmount = request.totalAmount;
    final finalAmount = totalAmount - totalSavings;
    final savingsPercent = (totalSavings / totalAmount * 100).toStringAsFixed(1);

    return MovieRecommendation(
      steps: [step],
      totalAmount: totalAmount,
      totalSavings: totalSavings,
      finalAmount: finalAmount,
      explanation: 'Optimized strategy saves ₹${totalSavings.toStringAsFixed(0)} '
          '($savingsPercent%) using your best card',
      calculatedAt: DateTime.now(),
      metadata: {
        'ranking_score': scenario['ranking_score'],
        'savings_percent': scenario['savings_percent'],
        'is_owned': scenario['is_owned'],
      },
    );
  }



  /// Calculate benefit for a specific scenario
  Future<Map<String, dynamic>?> _calculateBenefitScenario({
    required MovieTicketRequest request,
    required Map<String, dynamic> cardBenefit,
    required MovieBenefitConfig? config, // Made nullable
    required String platform,
    required String userId,
  }) async {
    try {
      print('DEBUG: Calculating benefit scenario for card: ${cardBenefit['card_name']}, platform: $platform');
      
      // If no config, create a basic scenario with 0 savings
      if (config == null) {
        print('DEBUG: No config available, creating basic scenario');
        return {
          'card_id': cardBenefit['card_id'],
          'user_card_id': cardBenefit['user_card_id'],
          'card_name': cardBenefit['card_name'],
          'card_network': cardBenefit['card_network'],
          'bank': cardBenefit['bank'],
          'savings': 0.0,
          'tickets': request.numberOfTickets,
          'platform': platform,
          'explanation': 'Entertainment benefit available - specific terms not configured',
          'benefit_type': 'UNKNOWN',
          'is_owned': cardBenefit['is_owned'] ?? false,
        };
      }
      
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
      'card_network': cardBenefit['card_network'],
      'bank': cardBenefit['bank'],
      'platform': platform,
      'tickets': applicableTickets,
      'amount': applicableTickets * request.pricePerTicket,
      'savings': savings,
      'benefit_type': offerType,
      'explanation': explanation,
      'priority_score': cardBenefit['priority_score'],
      'config': config,
      'is_owned': cardBenefit['is_owned'], // NEW: pass ownership info
      'user_card_id': cardBenefit['user_card_id'], // NEW: pass user_card_id if owned
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
