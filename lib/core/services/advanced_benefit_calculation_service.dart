import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'gemini_transaction_parser.dart';
import 'card_normalizer_service.dart';
import 'enhanced_web_scraper.dart';
import 'parsing_logger.dart';

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
      final userCardsResponse = await _supabase
          .from('user_cards')
          .select('''
            *,
            card:card_catalog!inner(*)
          ''')
          .eq('user_id', userId)
          .eq('is_active', true);

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
        
        // Get card benefits separately to avoid join issues
        final cardBenefitsResponse = await _supabase
            .from('card_benefits')
            .select('''
              *,
              benefit:benefits!inner(*),
              benefit_tiers(*),
              benefit_configurations(*)
            ''')
            .eq('card_id', card['id']);

        final cardBenefits = cardBenefitsResponse;
        double totalReward = 0.0;
        List<Map<String, dynamic>> applicableBenefits = [];

        for (final cardBenefit in cardBenefits) {
          final benefit = cardBenefit['benefit'];
          final benefitTiers = cardBenefit['benefit_tiers'] as List<dynamic>?;
          final benefitConfigs = cardBenefit['benefit_configurations'] as List<dynamic>?;

          // Check if benefit applies to this category
          final spendingCategories = cardBenefit['spending_categories'] as List<dynamic>?;
          bool categoryMatches = false;

          if (spendingCategories == null || spendingCategories.isEmpty) {
            categoryMatches = true; // Applies to all categories
          } else {
            categoryMatches = spendingCategories.any((cat) => 
              cat.toString().toLowerCase() == category.toLowerCase() ||
              cat.toString().toLowerCase() == 'all'
            );
          }

          if (!categoryMatches) continue;

          // Check merchant-specific benefits
          bool merchantMatches = true;
          if (benefitConfigs != null) {
            final merchantConfig = benefitConfigs.firstWhere(
              (config) => config['config_key'] == 'merchant_name',
              orElse: () => null,
            );
            if (merchantConfig != null) {
              merchantMatches = merchantConfig['config_value']
                  .toString()
                  .toLowerCase()
                  .contains(merchantName.toLowerCase());
            }
          }

          if (!merchantMatches) continue;

          // Check exclusions and thresholds from JSONB configuration
          final configuration = cardBenefit['configuration'] as Map<String, dynamic>?;
          if (configuration != null) {
            final excludedCategories = configuration['excluded_categories'] as List<dynamic>?;
            if (excludedCategories != null && excludedCategories.any((cat) => cat.toString().toLowerCase() == category.toLowerCase())) {
              continue; 
            }
            
            final excludedMerchants = configuration['excluded_merchants'] as List<dynamic>?;
            if (excludedMerchants != null && excludedMerchants.any((m) => merchantName.toLowerCase().contains(m.toString().toLowerCase()))) {
              continue; 
            }
            
            final minSpend = configuration['min_spend_threshold'];
            if (minSpend != null) {
              final minSpendVal = minSpend is num ? minSpend.toDouble() : double.tryParse(minSpend.toString());
              if (minSpendVal != null && amount < minSpendVal) {
                continue; 
              }
            }
          }

          // Calculate reward based on benefit type and tiers
          double reward = 0.0;
          String calculationMethod = benefit['calculation_method'] ?? 'percentage';

          if (benefitTiers != null && benefitTiers.isNotEmpty) {
            reward = _calculateTierBasedReward(amount, benefitTiers, calculationMethod);
          } else {
            double defaultValue = (cardBenefit['value'] ?? benefit['default_value'] ?? 0.0).toDouble();
            reward = _calculateSimpleReward(amount, defaultValue, calculationMethod);
          }

          // Apply monthly/annual caps and max cap limits
          final monthlyCap = cardBenefit['monthly_cap']?.toDouble();
          final annualCap = cardBenefit['annual_cap']?.toDouble();
          final maxCapLimit = configuration?['max_cap_limit'];
          
          if (maxCapLimit != null) {
            final maxCapLimitVal = maxCapLimit is num ? maxCapLimit.toDouble() : double.tryParse(maxCapLimit.toString());
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
            'benefit_name': benefit['name'],
            'category': benefit['category_code'],
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
      cardRecommendations.sort((a, b) => 
        b['total_reward'].compareTo(a['total_reward'])
      );

      return {
        'bestCard': cardRecommendations.isNotEmpty ? cardRecommendations.first : null,
        'maxReward': cardRecommendations.isNotEmpty ? cardRecommendations.first['total_reward'] : 0.0,
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
    double amount, 
    List<dynamic> tiers, 
    String calculationMethod
  ) {
    // Sort tiers by minimum value
    final sortedTiers = List<Map<String, dynamic>>.from(tiers)
      ..sort((a, b) => a['tier_min_value'].compareTo(b['tier_min_value']));

    for (final tier in sortedTiers.reversed) {
      final minValue = tier['tier_min_value']?.toDouble() ?? 0.0;
      final maxValue = tier['tier_max_value']?.toDouble();
      
      if (amount >= minValue && (maxValue == null || amount <= maxValue)) {
        final tierBenefitValue = tier['tier_benefit_value']?.toDouble() ?? 0.0;
        return _calculateSimpleReward(amount, tierBenefitValue, calculationMethod);
      }
    }

    return 0.0;
  }

  /// Calculate simple reward based on calculation method
  double _calculateSimpleReward(double amount, double value, String calculationMethod) {
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
  Future<List<Map<String, dynamic>>> getSpendingOptimizations(String userId) async {
    try {
      // Get user's recent transactions
      final transactionsResponse = await _supabase
          .from('transactions')
          .select('*')
          .eq('user_id', userId)
          .gte('transaction_date', DateTime.now().subtract(const Duration(days: 30)).toIso8601String())
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

        if (potentialSavings > 0.1) { // Only show if savings > 10 paise
          optimizations.add({
            'transaction': transaction,
            'best_card': bestCard,
            'potential_savings': potentialSavings,
            'actual_reward': actualReward,
            'optimal_reward': maxReward,
            'improvement_percentage': actualReward > 0 ? (potentialSavings / actualReward * 100) : 0.0,
          });
        }
      }

      // Sort by potential savings (descending)
      optimizations.sort((a, b) => 
        b['potential_savings'].compareTo(a['potential_savings'])
      );

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
        categoryBreakdown[category] = (categoryBreakdown[category] ?? 0.0) + actualReward;

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
        'reward_rate': totalSpending > 0 ? (totalRewardsEarned / totalSpending * 100) : 0.0,
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
  Future<List<Map<String, dynamic>>> getPersonalizedCardRecommendations(String userId) async {
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

        // Fetch card benefits separately
        final cardBenefitsResponse = await _supabase
          .from('card_benefits')
          .select('''
            *,
            benefit:benefits!inner(*),
            benefit_tiers(*),
            benefit_configurations(*)
          ''')
          .eq('card_id', card['id']);
        
        final cardBenefits = cardBenefitsResponse;

        for (final entry in spendingPatterns.entries) {
          final category = entry.key;
          final monthlySpending = entry.value;

          // Find best benefit for this category
          double bestRewardRate = 0.0;
          String bestBenefitName = '';

          for (final cardBenefit in cardBenefits) {
            final benefit = cardBenefit['benefit'];
            final spendingCategories = cardBenefit['spending_categories'] as List<dynamic>?;
            
            bool categoryMatches = false;
            if (spendingCategories == null || spendingCategories.isEmpty) {
              categoryMatches = true;
            } else {
              categoryMatches = spendingCategories.any((cat) => 
                cat.toString().toLowerCase() == category.toLowerCase() ||
                cat.toString().toLowerCase() == 'all'
              );
            }

            if (categoryMatches) {
              final configuration = cardBenefit['configuration'] as Map<String, dynamic>?;
              if (configuration != null) {
                final excludedCategories = configuration['excluded_categories'] as List<dynamic>?;
                if (excludedCategories != null && excludedCategories.any((cat) => cat.toString().toLowerCase() == category.toLowerCase())) {
                  continue; 
                }
                
                final minSpend = configuration['min_spend_threshold'];
                if (minSpend != null) {
                  final minSpendVal = minSpend is num ? minSpend.toDouble() : double.tryParse(minSpend.toString());
                  if (minSpendVal != null && monthlySpending < minSpendVal) {
                    continue; 
                  }
                }
              }

              final benefitTiers = cardBenefit['benefit_tiers'] as List<dynamic>?;
              String calculationMethod = benefit['calculation_method'] ?? 'percentage';
              double rewardRate = 0.0;

              if (benefitTiers != null && benefitTiers.isNotEmpty) {
                rewardRate = _calculateTierBasedReward(monthlySpending, benefitTiers, calculationMethod);
              } else {
                double defaultValue = (cardBenefit['value'] ?? benefit['default_value'] ?? 0.0).toDouble();
                rewardRate = _calculateSimpleReward(monthlySpending, defaultValue, calculationMethod);
              }

              final monthlyCap = cardBenefit['monthly_cap']?.toDouble();
              final maxCapLimit = configuration?['max_cap_limit'];
              
              if (maxCapLimit != null) {
                final maxCapLimitVal = maxCapLimit is num ? maxCapLimit.toDouble() : double.tryParse(maxCapLimit.toString());
                if (maxCapLimitVal != null && rewardRate > maxCapLimitVal) {
                  rewardRate = maxCapLimitVal;
                }
              }
              if (monthlyCap != null && rewardRate > monthlyCap) {
                rewardRate = monthlyCap;
              }

              if (rewardRate > bestRewardRate) {
                bestRewardRate = rewardRate;
                bestBenefitName = benefit['name'];
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
            'net_annual_benefit': (projectedMonthlyReward * 12) - (card['annual_fee'] ?? 0.0),
            'recommendation_score': _calculateRecommendationScore(card, projectedMonthlyReward),
          });
        }
      }

      // Sort by recommendation score
      recommendations.sort((a, b) => 
        b['recommendation_score'].compareTo(a['recommendation_score'])
      );

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
  double _calculateRecommendationScore(Map<String, dynamic> card, double projectedReward) {
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
      ParsingLogger.summary('🤖 EXTRACTING BENEFITS: Starting extraction for $bankName $cardName');
      
      // 1. Normalize card and bank names using existing service
      final normalizedBank = CardNormalizerService.normalizeBankName(bankName);
      final normalizedCard = CardNormalizerService.normalizeCardName(cardName, normalizedBank);
      
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
          ParsingLogger.summary('✅ FETCHED: Successfully scraped ${htmlContent.length} chars from $customUrl');
        } else {
          ParsingLogger.error('SCRAPING FAILED for custom URL: ${scrapedContent.error}');
        }
      } else {
        htmlContent = await _fetchCardWebContent(normalizedCard, normalizedBank);
      }
      
      if (htmlContent.isEmpty) {
        return {
          'success': false,
          'error': 'Could not fetch card content from website',
          'card_id': cardId,
        };
      }
      
      // 3. Use existing Gemini AI integration to extract benefits
      final extractionResult = await GeminiTransactionParser.extractCardBenefits(
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
      
      // 4. Save to staging table for review before committing
      String? stagingId;
      try {
        ParsingLogger.summary('💾 STAGING: Saving extracted benefits to review staging table...');
        final insertResult = await _supabase.from('card_benefits_staging').insert({
          'card_id': cardId,
          'source_url': sourceUrl.isNotEmpty ? sourceUrl : 'Official Bank Website',
          'extracted_data': extractionResult['data'],
          'status': 'pending',
        }).select('id').single();
        stagingId = insertResult['id'] as String;
        ParsingLogger.summary('✅ STAGING: Successfully saved staging record ID: $stagingId');
        
        return {
          'success': true,
          'card_id': cardId,
          'staging_id': stagingId,
          'extracted_data': extractionResult['data'],
          'source_url': sourceUrl.isNotEmpty ? sourceUrl : 'Official Bank Website',
        };
      } catch (e) {
        ParsingLogger.warning('⚠️ Staging table not found, falling back to direct database insertion. (Apply supabase/migrations/20260712030000_card_benefits_staging.sql in Supabase dashboard to enable staging). Error: $e');
        
        final updateResult = await _updateCardBenefitsFromAI(
          cardId, 
          extractionResult['data'],
          sourceUrl.isNotEmpty ? sourceUrl : 'Official Bank Website',
        );
        
        return {
          'success': true,
          'card_id': cardId,
          'direct_applied': true,
          'benefits_extracted': updateResult['benefits_count'],
          'confidence_score': updateResult['avg_confidence'],
          'source_url': sourceUrl.isNotEmpty ? sourceUrl : 'Official Bank Website',
          'extracted_at': DateTime.now().toIso8601String(),
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

  /// Apply approved card benefits and update catalog metadata
  Future<Map<String, dynamic>> applyApprovedBenefits(String stagingId) async {
    try {
      ParsingLogger.summary('💾 APPLYING APPROVED BENEFITS: Staging ID = $stagingId');
      
      final stagingRecord = await _supabase
          .from('card_benefits_staging')
          .select('*')
          .eq('id', stagingId)
          .single();
      
      final cardId = stagingRecord['card_id'] as String;
      final sourceUrl = stagingRecord['source_url'] as String;
      final aiData = stagingRecord['extracted_data'] as Map<String, dynamic>;
      
      // Update catalog fees & waivers
      final annualFee = aiData['annual_fee'] as Map<String, dynamic>?;
      if (annualFee != null) {
        final firstYear = annualFee['first_year'] != null ? (annualFee['first_year'] as num).toDouble() : 0.0;
        final renewal = annualFee['renewal'] != null ? (annualFee['renewal'] as num).toDouble() : firstYear;
        final waiver = annualFee['waiver_conditions'] as String? ?? '';
        
        ParsingLogger.summary('💳 CATALOG METADATA: Updating fees (Annual: ₹$renewal, Joining: ₹$firstYear)');
        await _supabase.from('card_catalog').update({
          'annual_fee': renewal,
          'joining_fee': firstYear,
          'rewards_summary': waiver,
        }).eq('id', cardId);
      }
      
      final updateResult = await _updateCardBenefitsFromAI(cardId, aiData, sourceUrl);
      
      await _supabase.from('card_benefits_staging').update({
        'status': 'approved',
      }).eq('id', stagingId);
      
      ParsingLogger.summary('✅ APPLIED: Successfully synced approved benefits to card');
      return {
        'success': true,
        'card_id': cardId,
        'benefits_extracted': updateResult['benefits_count'],
        'confidence_score': updateResult['avg_confidence'],
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
      ParsingLogger.summary('🌐 FETCHING: Starting web scraping for $bankName $cardName');
      
      // Use the enhanced web scraper with multiple strategies
      final scrapedContent = await EnhancedWebScraper.scrapeCardPage(
        bankName: bankName,
        cardName: cardName,
      );
      
      if (scrapedContent.isSuccess) {
        ParsingLogger.summary('✅ FETCHED: Successfully scraped ${scrapedContent.html.length} chars from ${scrapedContent.url}');
        
        // Extract benefit-specific content
        final benefitContent = scrapedContent.benefitContent;
        
        if (EnhancedWebScraper.isValidBenefitContent(benefitContent)) {
          ParsingLogger.summary('✅ BENEFIT CONTENT: Found ${benefitContent.length} chars of benefit information');
          return benefitContent;
        } else {
          ParsingLogger.warning('BENEFIT CONTENT: No valid benefit content found, using full HTML');
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

  /// Fallback method using simple HTTP requests
  Future<String> _fallbackSimpleHttp(String cardName, String bankName) async {
    try {
      ParsingLogger.summary('🔄 FALLBACK: Using simple HTTP for $bankName $cardName');
      
      // Generate potential URLs based on bank and card name
      final urls = _generateCardUrls(cardName, bankName);
      
      for (final url in urls) {
        try {
          ParsingLogger.summary('🌐 FALLBACK: Trying $url');
          
          final response = await http.get(
            Uri.parse(url),
            headers: {
              'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
              'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
              'Accept-Language': 'en-US,en;q=0.5',
            },
          ).timeout(const Duration(seconds: 10));
          
          if (response.statusCode == 200 && response.body.isNotEmpty) {
            ParsingLogger.summary('✅ FALLBACK: Successfully retrieved content (${response.body.length} chars)');
            return response.body;
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
  
  /// Update card benefits in database using AI-extracted data
  /// 
  /// This method reuses existing database patterns to store AI-extracted benefits
  /// with proper confidence scoring and source tracking.
  Future<Map<String, dynamic>> _updateCardBenefitsFromAI(
    String cardId, 
    Map<String, dynamic> aiData,
    String sourceUrl,
  ) async {
    try {
      int benefitsCount = 0;
      double totalConfidence = 0.0;
      
      // Get existing benefits to avoid duplicates
      final existingBenefits = await _supabase
          .from('card_benefits')
          .select('*')
          .eq('card_id', cardId)
          .eq('ai_extracted', true);
      
      // Clear existing AI-extracted benefits for this card
      if (existingBenefits.isNotEmpty) {
        await _supabase
            .from('card_benefits')
            .delete()
            .eq('card_id', cardId)
            .eq('ai_extracted', true);
      }
      
      final validCategories = [
        'DINING',
        'TRAVEL',
        'FUEL',
        'SHOPPING',
        'GROCERY',
        'ENTERTAINMENT',
        'UTILITIES',
        'HEALTHCARE',
        'GENERAL'
      ];

      // Process cashback benefits
      if (aiData['cashback_benefits'] is List) {
        final cashbackBenefits = aiData['cashback_benefits'] as List;
        
        for (final benefit in cashbackBenefits) {
          if (benefit is Map<String, dynamic>) {
            final category = (benefit['category'] as String? ?? 'GENERAL').toUpperCase();
            final categoryCode = validCategories.contains(category) ? category : 'GENERAL';
            
            await _insertAIBenefit(cardId, benefit, categoryCode, sourceUrl);
            benefitsCount++;
            totalConfidence += (benefit['confidence'] ?? 0.8);
          }
        }
      }
      
      // Process reward points
      if (aiData['reward_points'] is Map) {
        final rewardData = aiData['reward_points'] as Map<String, dynamic>;
        
        await _insertAIBenefit(cardId, {
          'category': 'GENERAL',
          'rate': rewardData['base_rate'] ?? 1.0,
          'description': 'Base reward points',
          'rate_type': 'points',
        }, 'GENERAL', sourceUrl);
        
        benefitsCount++;
        totalConfidence += 0.8;
      }
      
      // Process special benefits
      if (aiData['special_benefits'] is List) {
        final specialBenefits = aiData['special_benefits'] as List;
        
        for (final benefit in specialBenefits) {
          if (benefit is Map<String, dynamic>) {
            final type = (benefit['type'] as String? ?? 'GENERAL').toUpperCase();
            final categoryCode = validCategories.contains(type) ? type : 'GENERAL';
            
            await _insertAIBenefit(cardId, benefit, categoryCode, sourceUrl);
            benefitsCount++;
            totalConfidence += 0.7;
          }
        }
      }
      
      final avgConfidence = benefitsCount > 0 ? totalConfidence / benefitsCount : 0.0;
      
      return {
        'benefits_count': benefitsCount,
        'avg_confidence': avgConfidence,
        'source_url': sourceUrl,
      };
      
    } catch (e) {
      ParsingLogger.error('DATABASE UPDATE ERROR: $e');
      return {
        'benefits_count': 0,
        'avg_confidence': 0.0,
        'error': e.toString(),
      };
    }
  }
  
  /// Insert AI-extracted benefit into database
  Future<void> _insertAIBenefit(
    String cardId,
    Map<String, dynamic> benefitData,
    String categoryCode,
    String sourceUrl,
  ) async {
    try {
      // Find or create benefit in benefits table
      final benefitResponse = await _supabase
          .from('benefits')
          .select('id')
          .eq('category_code', categoryCode)
          .eq('name', benefitData['description'] ?? 'AI Extracted Benefit')
          .maybeSingle();
      
      String benefitId;
      
      if (benefitResponse == null) {
        // Create new benefit
        final newBenefit = await _supabase
            .from('benefits')
            .insert({
              'category_code': categoryCode,
              'name': benefitData['description'] ?? 'AI Extracted Benefit',
              'calculation_method': benefitData['rate_type'] ?? 'percentage',
              'default_value': benefitData['rate'] ?? 1.0,
              'is_active': true,
            })
            .select('id')
            .single();
        
        benefitId = newBenefit['id'];
      } else {
        benefitId = benefitResponse['id'];
      }
      
      // Insert card benefit with AI tracking
      await _supabase.from('card_benefits').insert({
        'card_id': cardId,
        'benefit_id': benefitId,
        'value': benefitData['rate'] ?? 1.0,
        'spending_categories': benefitData['merchants'] ?? [],
        'monthly_cap': benefitData['monthly_cap'],
        'annual_cap': benefitData['annual_cap'],
        'configuration': {
          'ai_extracted_data': benefitData,
          'conditions': benefitData['conditions'],
          // NEW: structured calculation limits
          'min_spend_threshold': benefitData['min_spend_threshold'],
          'max_cap_limit': benefitData['max_cap_limit'],
          'excluded_categories': benefitData['excluded_categories'],
          'excluded_merchants': benefitData['excluded_merchants'],
          'is_accelerated': benefitData['is_accelerated'] ?? false,
        },
        // NEW: AI tracking fields
        'ai_extracted': true,
        'extraction_confidence': benefitData['confidence'] ?? 0.8,
        'source_url': sourceUrl,
        'last_scraped_at': DateTime.now().toIso8601String(),
        'is_active': true,
      });
      
    } catch (e) {
      ParsingLogger.error('INSERT BENEFIT ERROR: $e');
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
        if (url.contains('credit-card') && (url.endsWith('.html') || url.split('/').length > 5)) {
          classification = 'PRODUCT';
        } else if (url.contains('credit-card') || url.contains('cards/credit')) {
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
