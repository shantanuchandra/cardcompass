import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/models/movie_ticket_request.dart';
import '../domain/models/movie_recommendation.dart';
import '../domain/models/transaction_step.dart';
import '../domain/models/movie_benefit_config.dart';

/// Core service for movie ticket rule engine optimization
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
      // 1. Get user's active cards with movie benefits
      final cardBenefits = await _getUserMovieBenefits(userId);
      
      if (cardBenefits.isEmpty) {
        return MovieRecommendation.empty(
          totalAmount: request.totalAmount,
          tickets: request.numberOfTickets,
        );
      }

      // 2. Update weekly milestone cache
      await _updateWeeklyMilestoneCache(userId);

      // 3. Evaluate all benefit scenarios
      final scenarios = await _evaluateAllScenarios(
        request: request,
        cardBenefits: cardBenefits,
        userId: userId,
      );

      // 4. Optimize transaction splitting
      final optimizedSteps = _optimizeTransactionSplitting(
        scenarios: scenarios,
        request: request,
      );

      // 5. Generate final recommendation
      return _generateRecommendation(
        steps: optimizedSteps,
        request: request,
      );

    } catch (e) {
      print('Error in movie optimization: $e');
      return MovieRecommendation.empty(
        totalAmount: request.totalAmount,
        tickets: request.numberOfTickets,
      );
    }
  }

  /// Get user's cards that have movie benefits
  Future<List<Map<String, dynamic>>> _getUserMovieBenefits(String userId) async {
    final response = await _supabase
        .from('user_cards')
        .select('''
          id,
          card_id,
          card:card_catalog!inner(
            id,
            card_name,
            card_network,
            priority_score
          )
        ''')
        .eq('user_id', userId)
        .eq('is_active', true);

    List<Map<String, dynamic>> cardBenefits = [];

    for (final userCard in response) {
      final cardBenefitsResponse = await _supabase
          .from('card_benefits')
          .select('''
            *,
            benefit:benefits!inner(*)
          ''')
          .eq('card_id', userCard['card']['id'])
          .contains('spending_categories', [_benefitCategory]);

      for (final benefit in cardBenefitsResponse) {
        // Parse JSON configuration
        MovieBenefitConfig? config;
        if (benefit['json_configuration'] != null) {
          try {
            final configJson = jsonDecode(benefit['json_configuration']);
            config = MovieBenefitConfig.fromJson(configJson);
          } catch (e) {
            print('Error parsing benefit config: $e');
            continue;
          }
        }

        cardBenefits.add({
          'user_card_id': userCard['id'],
          'card_id': userCard['card']['id'],
          'card_name': userCard['card']['card_name'],
          'card_network': userCard['card']['card_network'],
          'priority_score': userCard['card']['priority_score'] ?? 1,
          'benefit': benefit,
          'config': config,
          'efficiency_threshold': benefit['efficiency_threshold'],
        });
      }
    }

    return cardBenefits;
  }

  /// Update weekly milestone cache for user's cards
  Future<void> _updateWeeklyMilestoneCache(String userId) async {
    final now = DateTime.now();
    final weekStart = _getWeekStart(now);

    // Get spending for current week
    final spendingResponse = await _supabase
        .from('transactions')
        .select('card_id, amount')
        .eq('user_id', userId)
        .eq('category', _benefitCategory)
        .gte('transaction_date', weekStart.toIso8601String())
        .lte('transaction_date', now.toIso8601String());

    // Group by card and update cache
    final cardSpending = <int, double>{};
    for (final transaction in spendingResponse) {
      final cardId = transaction['card_id'] as int;
      final amount = (transaction['amount'] ?? 0.0).toDouble();
      cardSpending[cardId] = (cardSpending[cardId] ?? 0.0) + amount;
    }

    // Update cache for each card
    for (final entry in cardSpending.entries) {
      await _supabase
          .from('weekly_milestone_cache')
          .upsert({
            'user_id': userId,
            'card_id': entry.key,
            'benefit_category': _benefitCategory,
            'week_start_date': weekStart.toIso8601String(),
            'total_spending': entry.value,
            'last_updated': now.toIso8601String(),
          });
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

  /// Get monthly usage for a card
  Future<int> _getMonthlyUsage({
    required String userId,
    required int cardId,
  }) async {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);

    final response = await _supabase
        .from('transactions')
        .select('amount')
        .eq('user_id', userId)
        .eq('card_id', cardId)
        .eq('category', _benefitCategory)
        .gte('transaction_date', monthStart.toIso8601String())
        .lte('transaction_date', now.toIso8601String());

    return response.length; // Assuming each transaction is for tickets
  }

  /// Get start of week (Monday)
  DateTime _getWeekStart(DateTime date) {
    final daysFromMonday = date.weekday - 1;
    return DateTime(date.year, date.month, date.day - daysFromMonday);
  }
}
