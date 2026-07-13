import 'package:supabase_flutter/supabase_flutter.dart';
import 'gemini_transaction_parser.dart';
import 'card_normalizer_service.dart';
import 'enhanced_web_scraper.dart';
import 'parsing_logger.dart';
import 'benefit_extraction_validator.dart';
import 'benefit_staging_policy.dart';
import 'benefit_deduplication_service.dart';
import 'benefit_category_normalizer.dart';

/// Advanced benefit calculation service with tier-based rewards
class AdvancedBenefitCalculationService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Calculate the best card for a specific transaction
  Future<Map<String, dynamic>> calculateBestCard({
    required String userId,
    required double amount,
    required String merchantName,
    required String category,
    String? mccCode,
  }) async {
    try {
      // Get user's cards
      // Fetch user cards joined to card_catalog for benefits
      final userCardsResponse = await _supabase.from('user_cards').select('''
            *,
            card:card_catalog!inner(*)
          ''').eq('user_id', userId).eq('is_active', true);

      if (userCardsResponse.isEmpty) {
        return {
          'bestCard': null,
          'maxReward': 0.0,
          'recommendations': <Map<String, dynamic>>[],
        };
      }

      List<Map<String, dynamic>> cardRecommendations = [];

      for (final userCard in userCardsResponse) {
        final card = userCard['card'];

        // Read card relationships from the mapping table only.
        final cardBenefitsResponse =
            await _supabase.from('card_benefit_mapping').select('''
              *,
              benefit:benefits!inner(*)
            ''').eq('card_id', card['id']).eq('benefit.is_active', true);

        final cardBenefits = cardBenefitsResponse;
        double totalReward = 0.0;
        List<Map<String, dynamic>> applicableBenefits = [];

        for (final cardBenefit in cardBenefits) {
          final benefit = Map<String, dynamic>.from(cardBenefit['benefit']);
          final configuration = benefit['value_config'] is Map
              ? Map<String, dynamic>.from(benefit['value_config'])
              : <String, dynamic>{};

          // Check if benefit applies to this category
          final mappedCategories =
              (cardBenefit['category_codes'] as List? ?? const [])
                  .whereType<String>()
                  .toList();
          final spendingCategories = mappedCategories.isNotEmpty
              ? mappedCategories
              : configuration['spending_categories'] as List<dynamic>? ??
                  [benefit['benefit_category']];
          bool categoryMatches = false;

          if (spendingCategories.isEmpty) {
            categoryMatches = true; // Applies to all categories
          } else {
            categoryMatches = spendingCategories.any((cat) =>
                cat.toString().toLowerCase() == category.toLowerCase() ||
                cat.toString().toLowerCase() == 'all');
          }

          if (!categoryMatches) continue;

          // Check exclusions and thresholds from canonical JSONB configuration.
          {
            final excludedCategories =
                configuration['excluded_categories'] as List<dynamic>?;
            if (excludedCategories != null &&
                excludedCategories.any((cat) =>
                    cat.toString().toLowerCase() == category.toLowerCase())) {
              continue;
            }

            final excludedMerchants =
                configuration['excluded_merchants'] as List<dynamic>?;
            if (excludedMerchants != null &&
                excludedMerchants.any((m) => merchantName
                    .toLowerCase()
                    .contains(m.toString().toLowerCase()))) {
              continue;
            }

            final minSpend = configuration['min_spend_threshold'];
            if (minSpend != null) {
              final minSpendVal = minSpend is num
                  ? minSpend.toDouble()
                  : double.tryParse(minSpend.toString());
              if (minSpendVal != null && amount < minSpendVal) {
                continue;
              }
            }
          }

          final calculationMethod =
              configuration['rate_type']?.toString() ?? 'percentage';
          final rawRate = configuration['rate'] ?? configuration['value'] ?? 0;
          final rate = rawRate is num ? rawRate.toDouble() : 0.0;
          double reward =
              _calculateSimpleReward(amount, rate, calculationMethod);

          // Apply monthly/annual caps and max cap limits
          final monthlyCap = (configuration['monthly_cap'] as num?)?.toDouble();
          final annualCap = (configuration['annual_cap'] as num?)?.toDouble();
          final maxCapLimit = configuration['max_cap_limit'];

          if (maxCapLimit != null) {
            final maxCapLimitVal = maxCapLimit is num
                ? maxCapLimit.toDouble()
                : double.tryParse(maxCapLimit.toString());
            if (maxCapLimitVal != null && reward > maxCapLimitVal) {
              reward = maxCapLimitVal;
            }
          }
          if (monthlyCap != null && reward > monthlyCap) {
            reward = monthlyCap;
          }
          if (annualCap != null && reward > annualCap) {
            reward = annualCap;
          }

          totalReward += reward;
          applicableBenefits.add({
            'benefit_name': benefit['title'],
            'category': spendingCategories.join(', '),
            'reward': reward,
            'calculation_method': calculationMethod,
            'description': benefit['description'],
          });
        }

        cardRecommendations.add({
          'card': card,
          'user_card': userCard,
          'total_reward': totalReward,
          'applicable_benefits': applicableBenefits,
          'reward_percentage': totalReward / amount * 100,
        });
      }

      // Sort by reward amount (descending)
      cardRecommendations
          .sort((a, b) => b['total_reward'].compareTo(a['total_reward']));

      return {
        'bestCard':
            cardRecommendations.isNotEmpty ? cardRecommendations.first : null,
        'maxReward': cardRecommendations.isNotEmpty
            ? cardRecommendations.first['total_reward']
            : 0.0,
        'recommendations': cardRecommendations,
      };
    } catch (e) {
      print('Error calculating best card: $e');
      return {
        'bestCard': null,
        'maxReward': 0.0,
        'recommendations': <Map<String, dynamic>>[],
        'error': e.toString(),
      };
    }
  }

  /// Calculate tier-based reward
  double _calculateTierBasedReward(
      double amount, List<dynamic> tiers, String calculationMethod) {
    // Sort tiers by minimum value
    final sortedTiers = List<Map<String, dynamic>>.from(tiers)
      ..sort((a, b) => a['tier_min_value'].compareTo(b['tier_min_value']));

    for (final tier in sortedTiers.reversed) {
      final minValue = tier['tier_min_value']?.toDouble() ?? 0.0;
      final maxValue = tier['tier_max_value']?.toDouble();

      if (amount >= minValue && (maxValue == null || amount <= maxValue)) {
        final tierBenefitValue = tier['tier_benefit_value']?.toDouble() ?? 0.0;
        return _calculateSimpleReward(
            amount, tierBenefitValue, calculationMethod);
      }
    }

    return 0.0;
  }

  /// Calculate simple reward based on calculation method
  double _calculateSimpleReward(
      double amount, double value, String calculationMethod) {
    switch (calculationMethod.toLowerCase()) {
      case 'percentage':
        return amount * (value / 100);
      case 'fixed':
        return value;
      case 'points':
        return amount * value; // Points earned
      case 'boolean':
        return value > 0 ? 1.0 : 0.0; // Benefit available or not
      default:
        return amount * (value / 100); // Default to percentage
    }
  }

  /// Get spending optimization suggestions
  Future<List<Map<String, dynamic>>> getSpendingOptimizations(
      String userId) async {
    try {
      // Get user's recent transactions
      final transactionsResponse = await _supabase
          .from('transactions')
          .select('*')
          .eq('user_id', userId)
          .gte(
              'transaction_date',
              DateTime.now()
                  .subtract(const Duration(days: 30))
                  .toIso8601String())
          .order('transaction_date', ascending: false);

      List<Map<String, dynamic>> optimizations = [];

      for (final transaction in transactionsResponse) {
        final amount = transaction['amount']?.toDouble() ?? 0.0;
        final category = transaction['category'] ?? 'general';
        final merchantName = transaction['merchant_name'] ?? '';

        // Calculate what the best card would have been
        final recommendation = await calculateBestCard(
          userId: userId,
          amount: amount,
          merchantName: merchantName,
          category: category,
        );

        final bestCard = recommendation['bestCard'];
        final maxReward = recommendation['maxReward'] ?? 0.0;
        final actualReward = transaction['reward_earned']?.toDouble() ?? 0.0;
        final potentialSavings = maxReward - actualReward;

        if (potentialSavings > 0.1) {
          // Only show if savings > 10 paise
          optimizations.add({
            'transaction': transaction,
            'best_card': bestCard,
            'potential_savings': potentialSavings,
            'actual_reward': actualReward,
            'optimal_reward': maxReward,
            'improvement_percentage': actualReward > 0
                ? (potentialSavings / actualReward * 100)
                : 0.0,
          });
        }
      }

      // Sort by potential savings (descending)
      optimizations.sort(
          (a, b) => b['potential_savings'].compareTo(a['potential_savings']));

      return optimizations.take(10).toList(); // Return top 10 optimizations
    } catch (e) {
      print('Error getting spending optimizations: $e');
      return [];
    }
  }

  /// Get monthly reward summary with breakdown
  Future<Map<String, dynamic>> getMonthlyRewardSummary(String userId) async {
    try {
      final now = DateTime.now();
      final startOfMonth = DateTime(now.year, now.month, 1);

      final transactionsResponse = await _supabase
          .from('transactions')
          .select('*')
          .eq('user_id', userId)
          .gte('transaction_date', startOfMonth.toIso8601String())
          .order('transaction_date', ascending: false);

      double totalRewardsEarned = 0.0;
      double totalPotentialRewards = 0.0;
      double totalSpending = 0.0;
      Map<String, double> categoryBreakdown = {};
      Map<String, double> cardBreakdown = {};

      for (final transaction in transactionsResponse) {
        final amount = transaction['amount']?.toDouble() ?? 0.0;
        final category = transaction['category'] ?? 'general';
        final merchantName = transaction['merchant_name'] ?? '';
        final actualReward = transaction['reward_earned']?.toDouble() ?? 0.0;
        final cardId = transaction['card_id'] ?? '';

        totalSpending += amount;
        totalRewardsEarned += actualReward;

        // Calculate category breakdown
        categoryBreakdown[category] =
            (categoryBreakdown[category] ?? 0.0) + actualReward;

        // Calculate card breakdown
        if (cardId.isNotEmpty) {
          cardBreakdown[cardId] = (cardBreakdown[cardId] ?? 0.0) + actualReward;
        }

        // Calculate optimal reward
        final recommendation = await calculateBestCard(
          userId: userId,
          amount: amount,
          merchantName: merchantName,
          category: category,
        );
        final optimalReward = recommendation['maxReward'] ?? 0.0;
        totalPotentialRewards += optimalReward;
      }

      final optimizationScore = totalPotentialRewards > 0
          ? (totalRewardsEarned / totalPotentialRewards * 100)
          : 0.0;

      return {
        'total_spending': totalSpending,
        'total_rewards_earned': totalRewardsEarned,
        'total_potential_rewards': totalPotentialRewards,
        'missed_rewards': totalPotentialRewards - totalRewardsEarned,
        'optimization_score': optimizationScore,
        'reward_rate': totalSpending > 0
            ? (totalRewardsEarned / totalSpending * 100)
            : 0.0,
        'category_breakdown': categoryBreakdown,
        'card_breakdown': cardBreakdown,
        'transactions_count': transactionsResponse.length,
      };
    } catch (e) {
      print('Error getting monthly reward summary: $e');
      return {};
    }
  }

  /// Get personalized card recommendations based on spending patterns
  Future<List<Map<String, dynamic>>> getPersonalizedCardRecommendations(
      String userId) async {
    try {
      // Analyze spending patterns
      final spendingPatterns = await _analyzeSpendingPatterns(userId);

      // Get all available cards
      final availableCardsResponse = await _supabase
          .from('card_catalog')
          .select('*')
          .eq('is_discontinued', false);

      List<Map<String, dynamic>> recommendations = [];

      for (final card in availableCardsResponse) {
        double projectedMonthlyReward = 0.0;
        List<String> matchingCategories = [];

        // Read canonical benefits through their card mapping.
        final cardBenefitsResponse =
            await _supabase.from('card_benefit_mapping').select('''
            *,
            benefit:benefits!inner(*)
          ''').eq('card_id', card['id']).eq('benefit.is_active', true);

        final cardBenefits = cardBenefitsResponse;

        for (final entry in spendingPatterns.entries) {
          final category = entry.key;
          final monthlySpending = entry.value;

          // Find best benefit for this category
          double bestRewardRate = 0.0;
          String bestBenefitName = '';

          for (final cardBenefit in cardBenefits) {
            final benefit = Map<String, dynamic>.from(cardBenefit['benefit']);
            final configuration = benefit['value_config'] is Map
                ? Map<String, dynamic>.from(benefit['value_config'])
                : <String, dynamic>{};
            final spendingCategories =
                configuration['spending_categories'] as List<dynamic>? ??
                    [benefit['benefit_category']];

            bool categoryMatches = false;
            if (spendingCategories.isEmpty) {
              categoryMatches = true;
            } else {
              categoryMatches = spendingCategories.any((cat) =>
                  cat.toString().toLowerCase() == category.toLowerCase() ||
                  cat.toString().toLowerCase() == 'all');
            }

            if (categoryMatches) {
              {
                final excludedCategories =
                    configuration['excluded_categories'] as List<dynamic>?;
                if (excludedCategories != null &&
                    excludedCategories.any((cat) =>
                        cat.toString().toLowerCase() ==
                        category.toLowerCase())) {
                  continue;
                }

                final minSpend = configuration['min_spend_threshold'];
                if (minSpend != null) {
                  final minSpendVal = minSpend is num
                      ? minSpend.toDouble()
                      : double.tryParse(minSpend.toString());
                  if (minSpendVal != null && monthlySpending < minSpendVal) {
                    continue;
                  }
                }
              }

              final calculationMethod =
                  configuration['rate_type']?.toString() ?? 'percentage';
              final rawRate =
                  configuration['rate'] ?? configuration['value'] ?? 0;
              final rate = rawRate is num ? rawRate.toDouble() : 0.0;
              double rewardRate = _calculateSimpleReward(
                  monthlySpending, rate, calculationMethod);

              final monthlyCap =
                  (configuration['monthly_cap'] as num?)?.toDouble();
              final maxCapLimit = configuration['max_cap_limit'];

              if (maxCapLimit != null) {
                final maxCapLimitVal = maxCapLimit is num
                    ? maxCapLimit.toDouble()
                    : double.tryParse(maxCapLimit.toString());
                if (maxCapLimitVal != null && rewardRate > maxCapLimitVal) {
                  rewardRate = maxCapLimitVal;
                }
              }
              if (monthlyCap != null && rewardRate > monthlyCap) {
                rewardRate = monthlyCap;
              }

              if (rewardRate > bestRewardRate) {
                bestRewardRate = rewardRate;
                bestBenefitName = benefit['title']?.toString() ?? 'Benefit';
              }
            }
          }

          if (bestRewardRate > 0) {
            projectedMonthlyReward += bestRewardRate;
            matchingCategories.add('$category: ${bestBenefitName}');
          }
        }

        if (projectedMonthlyReward > 0) {
          recommendations.add({
            'card': card,
            'projected_monthly_reward': projectedMonthlyReward,
            'matching_categories': matchingCategories,
            'annual_fee': card['annual_fee'] ?? 0.0,
            'net_annual_benefit':
                (projectedMonthlyReward * 12) - (card['annual_fee'] ?? 0.0),
            'recommendation_score':
                _calculateRecommendationScore(card, projectedMonthlyReward),
          });
        }
      }

      // Sort by recommendation score
      recommendations.sort((a, b) =>
          b['recommendation_score'].compareTo(a['recommendation_score']));

      return recommendations.take(5).toList(); // Return top 5 recommendations
    } catch (e) {
      print('Error getting personalized recommendations: $e');
      return [];
    }
  }

  /// Analyze user's spending patterns
  Future<Map<String, double>> _analyzeSpendingPatterns(String userId) async {
    final threeMonthsAgo = DateTime.now().subtract(const Duration(days: 90));

    final transactionsResponse = await _supabase
        .from('transactions')
        .select('category, amount')
        .eq('user_id', userId)
        .gte('transaction_date', threeMonthsAgo.toIso8601String());

    Map<String, double> categorySpending = {};

    for (final transaction in transactionsResponse) {
      final category = transaction['category'] ?? 'general';
      final amount = transaction['amount']?.toDouble() ?? 0.0;

      categorySpending[category] = (categorySpending[category] ?? 0.0) + amount;
    }

    // Convert to monthly averages
    Map<String, double> monthlyAverages = {};
    for (final entry in categorySpending.entries) {
      monthlyAverages[entry.key] = entry.value / 3; // 3 months average
    }

    return monthlyAverages;
  }

  /// Calculate recommendation score for a card
  double _calculateRecommendationScore(
      Map<String, dynamic> card, double projectedReward) {
    final annualFee = card['annual_fee']?.toDouble() ?? 0.0;
    final netBenefit = (projectedReward * 12) - annualFee;

    // Score based on net benefit, with bonus for premium features
    double score = netBenefit;

    final features = card['features'] as Map<String, dynamic>?;
    if (features != null) {
      if (features['airport_lounge'] == true) score += 500;
      if (features['travel_benefits'] == true) score += 300;
      if (features['cashback'] == true) score += 200;
    }

    return score;
  }

  /// NEW: AI-powered benefit extraction and update
  ///
  /// This method leverages existing Gemini integration to extract real benefit data
  /// from bank websites and update the database with confidence scoring.
  Future<Map<String, dynamic>> extractAndUpdateBenefits({
    required String cardId,
    required String cardName,
    required String bankName,
    String? customUrl,
  }) async {
    try {
      ParsingLogger.summary(
          '🤖 EXTRACTING BENEFITS: Starting extraction for $bankName $cardName');

      // 1. Normalize card and bank names using existing service
      final normalizedBank = CardNormalizerService.normalizeBankName(bankName);
      final normalizedCard =
          CardNormalizerService.normalizeCardName(cardName, normalizedBank);

      // 2. Fetch card web content
      String htmlContent = '';
      String sourceUrl = customUrl ?? '';

      if (customUrl != null && customUrl.isNotEmpty) {
        ParsingLogger.summary('🌐 FETCHING: Scraping custom URL: $customUrl');
        final scrapedContent = await EnhancedWebScraper.scrapeUrl(customUrl);
        if (scrapedContent.isSuccess) {
          htmlContent = scrapedContent.benefitContent.isNotEmpty
              ? scrapedContent.benefitContent
              : scrapedContent.html;
          ParsingLogger.summary(
              '✅ FETCHED: Successfully scraped ${htmlContent.length} chars from $customUrl');
        } else {
          ParsingLogger.error(
              'SCRAPING FAILED for custom URL: ${scrapedContent.error}');
        }
      } else {
        htmlContent =
            await _fetchCardWebContent(normalizedCard, normalizedBank);
      }

      if (htmlContent.isEmpty) {
        return {
          'success': false,
          'error': 'Could not fetch card content from website',
          'card_id': cardId,
        };
      }

      if (sourceUrl.isEmpty) {
        return {
          'success': false,
          'error':
              'Extraction requires a persisted official card product URL for source validation.',
          'card_id': cardId,
        };
      }
      final sourceValidation = EnhancedWebScraper.validateCardSource(
        url: sourceUrl,
        content: htmlContent,
        bankName: normalizedBank,
        cardName: normalizedCard,
      );
      if (!sourceValidation.isValid) {
        return {
          'success': false,
          'error': 'Source page failed card identity validation.',
          'card_id': cardId,
          'validation_reasons': sourceValidation.reasons
              .map((reason) => reason.toJson())
              .toList(),
        };
      }

      // 3. Use existing Gemini AI integration to extract benefits
      final extractionResult =
          await GeminiTransactionParser.extractCardBenefits(
        cardName: normalizedCard,
        bankName: normalizedBank,
        htmlContent: htmlContent,
      );

      if (!extractionResult['success']) {
        return {
          'success': false,
          'error': 'AI extraction failed: ${extractionResult['error']}',
          'card_id': cardId,
        };
      }

      final extractedData =
          Map<String, dynamic>.from(extractionResult['data'] as Map);
      final validation = BenefitExtractionValidator.validate(
        extractedData: extractedData,
        evidenceText: htmlContent,
        cardName: normalizedCard,
        bankName: normalizedBank,
        sourceUrl: sourceUrl,
      );

      // 4. Save to staging table for review before committing
      String? stagingId;
      try {
        final effectiveSource =
            sourceUrl.isNotEmpty ? sourceUrl : 'Official Bank Website';
        ParsingLogger.summary(
            '💾 STAGING: Saving ${validation.accepted ? "validated" : "rejected"} extraction...');
        final payload = BenefitStagingPolicy.buildInsertPayload(
          cardId: cardId,
          sourceUrl: effectiveSource,
          sourceEvidence: htmlContent,
          validation: validation,
        );
        final insertResult = await _supabase
            .from('card_benefits_staging')
            .insert(payload)
            .select('id')
            .single();
        stagingId = insertResult['id'] as String;
        ParsingLogger.summary(
            '${validation.accepted ? "✅" : "⛔"} STAGING: Saved ${payload['status']} record ID: $stagingId');

        return {
          'success': validation.accepted,
          'card_id': cardId,
          'staging_id': stagingId,
          'status': payload['status'],
          'extracted_data': validation.normalizedData,
          'confidence_score': validation.confidence,
          'validation_reasons':
              validation.reasons.map((reason) => reason.toJson()).toList(),
          'source_url': effectiveSource,
          if (!validation.accepted)
            'error': 'Extraction rejected by source-grounding validation',
        };
      } catch (e) {
        ParsingLogger.error(
            'STAGING FAILED: Refusing unsafe direct application: $e');
        return {
          'success': false,
          'card_id': cardId,
          'error': 'Could not persist validated staging result: $e',
        };
      }
    } catch (e) {
      ParsingLogger.error('BENEFIT EXTRACTION ERROR: $e');
      return {
        'success': false,
        'error': e.toString(),
        'card_id': cardId,
      };
    }
  }

  /// Records an explicit discard without changing active card mappings.
  Future<void> rejectStagedReview(
    String stagingId, {
    required Map<String, dynamic> reviewDecisions,
  }) async {
    await _supabase.from('card_benefits_staging').update({
      'status': 'rejected',
      'benefit_decisions': reviewDecisions['items'],
      'reviewed_at': DateTime.now().toUtc().toIso8601String(),
      'reviewed_by': _supabase.auth.currentUser?.id,
      'rejected_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', stagingId);
  }

  /// Applies only the reviewer's accepted candidates. The canonical benefit is
  /// deduplicated in [benefits]; the selected card is related through
  /// [card_benefit_mapping]. [card_benefits] is deliberately not written.
  Future<Map<String, dynamic>> applyApprovedBenefits(
    String stagingId, {
    required Map<String, dynamic> reviewDecisions,
  }) async {
    try {
      ParsingLogger.summary(
          '💾 APPLYING APPROVED BENEFITS: Staging ID = $stagingId');

      final stagingRecord = await _supabase
          .from('card_benefits_staging')
          .select('*')
          .eq('id', stagingId)
          .single();

      if (!BenefitStagingPolicy.canApprove(stagingRecord)) {
        return {
          'success': false,
          'error': 'Staging record is rejected, obsolete, or lacks evidence.',
        };
      }

      final decisions = reviewDecisions['items'];
      if (decisions is! List) {
        return {
          'success': false,
          'error': 'Benefit review decisions are required before approval.',
        };
      }
      final unresolved = decisions.any((item) =>
          item is Map && item['decision']?.toString() == 'unresolved');
      if (unresolved) {
        return {
          'success': false,
          'error': 'Resolve every candidate before applying the review.',
        };
      }

      final cardId = stagingRecord['card_id'] as String;
      final sourceUrl = stagingRecord['source_url'] as String;
      final aiData = stagingRecord['extracted_data'] as Map<String, dynamic>;
      final sourceEvidence = stagingRecord['source_evidence'] as Map;
      final card = await _supabase
          .from('card_catalog')
          .select('card_name, bank')
          .eq('id', cardId)
          .single();
      final validation = BenefitExtractionValidator.validate(
        extractedData: aiData,
        evidenceText: sourceEvidence['text']?.toString() ?? '',
        cardName: card['card_name'] as String,
        bankName: card['bank'] as String,
        sourceUrl: sourceUrl,
      );
      if (!validation.accepted) {
        await _supabase.from('card_benefits_staging').update({
          'status': 'rejected',
          'benefit_decisions': decisions,
          'reviewed_at': DateTime.now().toUtc().toIso8601String(),
          'reviewed_by': _supabase.auth.currentUser?.id,
          'calculated_confidence': validation.confidence,
          'validation_reasons':
              validation.reasons.map((reason) => reason.toJson()).toList(),
          'validation_warnings':
              validation.warnings.map((warning) => warning.toJson()).toList(),
          'rejected_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', stagingId);
        return {
          'success': false,
          'error': 'Staging record failed approval-time validation.',
          'validation_reasons':
              validation.reasons.map((reason) => reason.toJson()).toList(),
        };
      }
      final accepted = decisions
          .whereType<Map>()
          .where(
            (item) => item['decision']?.toString() == 'accepted',
          )
          .map((item) => Map<String, dynamic>.from(item))
          .toList();

      // Rejecting every candidate leaves currently active mappings untouched.
      if (accepted.isEmpty) {
        await _supabase.from('card_benefits_staging').update({
          'status': 'rejected',
          'benefit_decisions': decisions,
          'reviewed_at': DateTime.now().toUtc().toIso8601String(),
          'reviewed_by': _supabase.auth.currentUser?.id,
          'rejected_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', stagingId);
        return {'success': true, 'card_id': cardId, 'benefits_mapped': 0};
      }

      final mappedCount = await _replaceCardBenefitMappings(
        cardId: cardId,
        acceptedCandidates: accepted,
        sourceUrl: sourceUrl,
      );

      await _supabase.from('card_benefits_staging').update({
        'status': 'approved',
        'benefit_decisions': decisions,
        'reviewed_at': DateTime.now().toUtc().toIso8601String(),
        'reviewed_by': _supabase.auth.currentUser?.id,
      }).eq('id', stagingId);

      ParsingLogger.summary(
          '✅ APPLIED: Successfully synced approved benefits to card');
      return {
        'success': true,
        'card_id': cardId,
        'benefits_mapped': mappedCount,
        'confidence_score': validation.confidence,
      };
    } catch (e) {
      ParsingLogger.error('❌ APPLY FAILED: $e');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// Fetch card web content using enhanced web scraper
  ///
  /// This method uses the new EnhancedWebScraper service for robust
  /// web content extraction with multiple fallback strategies.
  Future<String> _fetchCardWebContent(String cardName, String bankName) async {
    try {
      ParsingLogger.summary(
          '🌐 FETCHING: Starting web scraping for $bankName $cardName');

      // Use the enhanced web scraper with multiple strategies
      final scrapedContent = await EnhancedWebScraper.scrapeCardPage(
        bankName: bankName,
        cardName: cardName,
      );

      if (scrapedContent.isSuccess) {
        ParsingLogger.summary(
            '✅ FETCHED: Successfully scraped ${scrapedContent.html.length} chars from ${scrapedContent.url}');

        // Extract benefit-specific content
        final benefitContent = scrapedContent.benefitContent;

        if (EnhancedWebScraper.isValidBenefitContent(benefitContent)) {
          ParsingLogger.summary(
              '✅ BENEFIT CONTENT: Found ${benefitContent.length} chars of benefit information');
          return benefitContent;
        } else {
          ParsingLogger.warning(
              'BENEFIT CONTENT: No valid benefit content found, using full HTML');
          return scrapedContent.html;
        }
      } else {
        ParsingLogger.error('SCRAPING FAILED: ${scrapedContent.error}');
        return '';
      }
    } catch (e) {
      ParsingLogger.error('SCRAPING ERROR: $e');
      // Fallback to simple HTTP if enhanced scraper fails
      return await _fallbackSimpleHttp(cardName, bankName);
    }
  }

  /// Fallback method using EnhancedWebScraper (handles CORS proxy on web)
  Future<String> _fallbackSimpleHttp(String cardName, String bankName) async {
    try {
      ParsingLogger.summary(
          '🔄 FALLBACK: Using EnhancedWebScraper for $bankName $cardName');

      // Generate potential URLs based on bank and card name
      final urls = _generateCardUrls(cardName, bankName);

      for (final url in urls) {
        try {
          ParsingLogger.summary('🌐 FALLBACK: Trying $url');

          final scraped = await EnhancedWebScraper.scrapeUrl(url);

          if (scraped.isSuccess && scraped.html.isNotEmpty) {
            ParsingLogger.summary(
                '✅ FALLBACK: Successfully retrieved content (${scraped.html.length} chars)');
            return scraped.html;
          }
        } catch (e) {
          ParsingLogger.warning('FALLBACK ERROR: $url - $e');
          continue; // Try next URL
        }
      }

      ParsingLogger.error('FALLBACK FAILED: No URLs returned valid content');
      return '';
    } catch (e) {
      ParsingLogger.error('FALLBACK ERROR: $e');
      return '';
    }
  }

  /// Generate potential URLs for card information
  List<String> _generateCardUrls(String cardName, String bankName) {
    final bank = bankName.toLowerCase();
    final card = cardName.toLowerCase().replaceAll(' ', '-');

    List<String> urls = [];

    // Bank-specific URL patterns
    if (bank.contains('hdfc')) {
      urls.addAll([
        'https://www.hdfcbank.com/personal/pay/cards/credit-cards/$card',
        'https://www.hdfcbank.com/personal/pay/cards/credit-cards',
        'https://www.hdfcbank.com/personal/pay/cards/credit-cards/super-premium-cards/$card',
      ]);
    } else if (bank.contains('icici')) {
      urls.addAll([
        'https://www.icicibank.com/personal-banking/cards/credit-card/$card',
        'https://www.icicibank.com/personal-banking/cards/credit-card',
        'https://www.icicibank.com/credit-card/$card',
      ]);
    } else if (bank.contains('sbi')) {
      urls.addAll([
        'https://www.sbicard.com/en/personal/credit-cards/$card.page',
        'https://www.sbicard.com/en/personal/credit-cards',
        'https://www.sbicard.com/personal/credit-cards/$card',
      ]);
    } else if (bank.contains('axis')) {
      urls.addAll([
        'https://www.axisbank.com/personal/cards/credit-cards/$card',
        'https://www.axisbank.com/personal/cards/credit-cards',
      ]);
    }

    // Generic fallback URLs
    urls.addAll([
      'https://www.google.com/search?q=$bankName+$cardName+credit+card+benefits',
    ]);

    return urls;
  }

  Future<int> _replaceCardBenefitMappings({
    required String cardId,
    required List<Map<String, dynamic>> acceptedCandidates,
    required String sourceUrl,
  }) async {
    final categoryCodesByBenefit = <String, Set<String>>{};
    for (final candidate in acceptedCandidates) {
      final source = candidate['source'];
      if (source is! Map) continue;
      final normalizedSource = Map<String, dynamic>.from(source);
      final benefitId = await _findOrCreateCanonicalBenefit(
        source: normalizedSource,
        sourceUrl: sourceUrl,
      );
      categoryCodesByBenefit
          .putIfAbsent(benefitId, () => <String>{})
          .addAll(BenefitCategoryNormalizer.idsFor(normalizedSource));
    }

    // A fully reviewed candidate set is the desired state for this one card.
    await _supabase.from('card_benefit_mapping').delete().eq('card_id', cardId);
    final mappings = categoryCodesByBenefit.entries.toList();
    for (var index = 0; index < mappings.length; index++) {
      final mapping = mappings[index];
      await _supabase.from('card_benefit_mapping').upsert({
        'card_id': cardId,
        'benefit_id': mapping.key,
        'category_codes': mapping.value.toList()..sort(),
        'display_priority': index + 1,
        'is_primary': index == 0,
      }, onConflict: 'card_id,benefit_id');
    }
    return mappings.length;
  }

  Future<String> _findOrCreateCanonicalBenefit({
    required Map<String, dynamic> source,
    required String sourceUrl,
  }) async {
    final title = source['description']?.toString().trim();
    if (title == null || title.isEmpty) {
      throw ArgumentError('An accepted benefit needs a description.');
    }
    final categoryIds = BenefitCategoryNormalizer.idsFor(source);
    final category = categoryIds.first.toLowerCase();
    final type = (source['rate_type'] ?? source['type'] ?? 'general')
        .toString()
        .toLowerCase();
    final dedupeKey = BenefitDeduplicationService.keyFor(
      category: category,
      type: type,
      title: title,
    );
    final existing = await _supabase
        .from('benefits')
        .select('benefit_id')
        .eq('dedupe_key', dedupeKey)
        .maybeSingle();
    if (existing != null) return existing['benefit_id'] as String;

    try {
      final created = await _supabase
          .from('benefits')
          .insert({
            'title': title,
            'description': source['conditions']?.toString(),
            'benefit_category': category,
            'benefit_type': type,
            'value_config': source,
            'source_url': sourceUrl,
            'dedupe_key': dedupeKey,
            'is_active': true,
          })
          .select('benefit_id')
          .single();
      return created['benefit_id'] as String;
    } catch (_) {
      // The unique index resolves concurrent approval attempts. Re-read the
      // winner instead of creating a second canonical benefit.
      final winner = await _supabase
          .from('benefits')
          .select('benefit_id')
          .eq('dedupe_key', dedupeKey)
          .single();
      return winner['benefit_id'] as String;
    }
  }

  /// Classify URLs using AI for better credit card page detection
  Future<String> classifyUrlsWithAI(String prompt) async {
    try {
      // For now, use a simple pattern-based classification as fallback
      // This can be enhanced with proper AI integration later

      final lines = prompt.split('\n');
      final classifications = <String>[];

      for (final line in lines) {
        if (line.trim().isEmpty || !line.contains('http')) continue;

        final url = line.trim();
        String classification = 'OTHER';

        // Simple pattern matching for classification
        if (url.contains('credit-card') &&
            (url.endsWith('.html') || url.split('/').length > 5)) {
          classification = 'PRODUCT';
        } else if (url.contains('credit-card') ||
            url.contains('cards/credit')) {
          classification = 'CATEGORY';
        }

        classifications.add(classification);
      }

      return classifications.join('\n');
    } catch (e) {
      print('AI URL classification failed: $e');
      return 'OTHER\nOTHER\nOTHER'; // Safe fallback
    }
  }
}
