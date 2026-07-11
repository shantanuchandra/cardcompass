import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cardcompass/core/theme.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:cardcompass/core/services/enhanced_analytics_service.dart';
import 'package:cardcompass/shared/models/credit_card.dart';
import 'package:cardcompass/shared/models/transaction.dart';

/// Enhanced financial insights widget showing comprehensive analytics
class FinancialInsightsWidget extends ConsumerStatefulWidget {
  final String userId;
  final List<Transaction> transactions;
  final List<CreditCard> creditCards;
  
  const FinancialInsightsWidget({
    super.key,
    required this.userId,
    required this.transactions,
    required this.creditCards,
  });
  
  @override
  ConsumerState<FinancialInsightsWidget> createState() => _FinancialInsightsWidgetState();
}

class _FinancialInsightsWidgetState extends ConsumerState<FinancialInsightsWidget> {
  final EnhancedAnalyticsService _analyticsService = EnhancedAnalyticsService();
  FinancialInsights? _insights;
  bool _isLoading = true;
  String? _error;
  int _touchedIndex = -1;
  
  @override
  void initState() {
    super.initState();
    _loadInsights();
  }
  
  Future<void> _loadInsights() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });
        // Guard: if no transactions and no credit cards, skip analytics
      if (widget.transactions.isEmpty && widget.creditCards.isEmpty) {
        setState(() {
          _insights = null;
          _isLoading = false;
        });
        return;      }
      
      final insights = await _analyticsService.generateComprehensiveInsights(
        userId: widget.userId,
        transactions: widget.transactions,
        creditCards: widget.creditCards,
      );
      
      setState(() {
        _insights = insights;
        _isLoading = false;
      });
    } catch (error) {
      final msg = error.toString();
      if (msg.contains('Bad state: No element')) {
        // No data found, treat as empty insights
        setState(() {
          _insights = null;
          _isLoading = false;
          _error = null;
        });
      } else {
        setState(() {
          _error = msg;
          _isLoading = false;
        });
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }
    
    if (_error != null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Icon(Icons.error, color: Colors.red, size: 48),
              const SizedBox(height: 8),
              Text('Error loading insights: $_error'),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _loadInsights,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    
    if (_insights == null) {
      // No insights available
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Icon(Icons.info_outline, size: 48),
              const SizedBox(height: 8),
              const Text('No financial insights available'),
            ],
          ),
        ),
      );
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Financial Health Score
        _buildFinancialHealthCard(),
        
        const SizedBox(height: 16),
        
        // Spending Trends
        _buildSpendingTrendsCard(),
        
        const SizedBox(height: 16),
        
        // Category Insights
        _buildCategoryInsightsCard(),
        
        const SizedBox(height: 16),
        
        // Savings Opportunities
        _buildSavingsOpportunitiesCard(),
        
        const SizedBox(height: 16),
        
        // Reward Optimization
        _buildRewardOptimizationCard(),
        
        const SizedBox(height: 16),
        
        // Predictive Insights
        _buildPredictiveInsightsCard(),
      ],
    );
  }
  
  Widget _buildFinancialHealthCard() {
    final healthScore = _insights!.financialHealthScore;
    final themeColor = _getHealthScoreColor(healthScore.overallScore);
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0C152B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: themeColor.withValues(alpha: 0.25),
          width: 1.5,
        ),
        boxShadow: AppTheme.neonGlow(color: themeColor, opacity: 0.12, blurRadius: 12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.health_and_safety_outlined,
                color: themeColor,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'FINANCIAL HEALTH PROFILE',
                style: GoogleFonts.spaceGrotesk(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          
          // Overall Score with a beautiful circular indicator
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${healthScore.overallScore.toStringAsFixed(0)}/100',
                      style: GoogleFonts.spaceGrotesk(
                        color: themeColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 32,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _getHealthScoreDescription(healthScore.overallScore).toUpperCase(),
                      style: GoogleFonts.spaceGrotesk(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 50,
                height: 50,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: healthScore.overallScore / 100,
                      backgroundColor: Colors.white.withValues(alpha: 0.05),
                      valueColor: AlwaysStoppedAnimation<Color>(themeColor),
                      strokeWidth: 4.5,
                    ),
                    Text(
                      '${healthScore.overallScore.toStringAsFixed(0)}%',
                      style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 20),
          
          // Detailed Scores
          _buildScoreBreakdown(healthScore),
          
          if (healthScore.insights.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Divider(color: Color(0xFF1E293B)),
            const SizedBox(height: 8),
            Text(
              'KEY OBSERVATIONS',
              style: GoogleFonts.spaceGrotesk(
                color: Colors.white70,
                fontWeight: FontWeight.bold,
                fontSize: 10,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 8),
            ...healthScore.insights.map((insight) => 
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.bolt, size: 14, color: themeColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        insight,
                        style: GoogleFonts.plusJakartaSans(color: Colors.white60, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
  
  Widget _buildScoreBreakdown(FinancialHealthScore healthScore) {
    return Column(
      children: [
        _buildScoreItem('Credit Utilization', healthScore.creditUtilizationScore),
        _buildScoreItem('Spending Consistency', healthScore.spendingConsistencyScore),
        _buildScoreItem('Category Balance', healthScore.categoryBalanceScore),
        _buildScoreItem('Emergency Fund', healthScore.emergencyFundScore),
      ],
    );
  }

  Widget _buildScoreItem(String label, double score) {
    final scoreColor = _getHealthScoreColor(score);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label.toUpperCase(),
              style: GoogleFonts.spaceGrotesk(
                color: Colors.white70,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: score / 100,
                backgroundColor: Colors.white.withValues(alpha: 0.05),
                valueColor: AlwaysStoppedAnimation<Color>(scoreColor),
                minHeight: 5,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${score.toStringAsFixed(0)}',
            style: GoogleFonts.spaceGrotesk(
              color: scoreColor,
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildSpendingTrendsCard() {
    final trends = _insights!.spendingTrends;
    
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _getTrendIcon(trends.trendDirection),
                  color: _getTrendColor(trends.trendDirection),
                ),
                const SizedBox(width: 8),
                Text(
                  'Spending Trends',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            Row(
              children: [
                Expanded(
                  child: _buildTrendMetric(
                    'Average Monthly',
                    '₹${trends.averageMonthlySpending.toStringAsFixed(0)}',
                    Icons.trending_up,
                  ),
                ),
                Expanded(
                  child: _buildTrendMetric(
                    'Trend',
                    trends.trendDirection.toUpperCase(),
                    _getTrendIcon(trends.trendDirection),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            Text(
              'Volatility: ${(trends.spendingVolatility * 100).toStringAsFixed(1)}%',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            
            if (trends.spendingVolatility > 0.3)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning, color: Colors.orange, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'High spending volatility detected. Consider budgeting for consistency.',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: Colors.grey[800]),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildTrendMetric(String label, String value, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16),
            const SizedBox(width: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
  
  Color _getCategoryNeonColor(TransactionCategory category) {
    switch (category) {
      case TransactionCategory.food:
        return AppTheme.primaryColor;
      case TransactionCategory.fuel:
        return AppTheme.warningColor;
      case TransactionCategory.grocery:
        return AppTheme.successColor;
      case TransactionCategory.entertainment:
        return AppTheme.accentColor;
      case TransactionCategory.travel:
        return AppTheme.secondaryColor;
      case TransactionCategory.shopping:
        return const Color(0xFFF472B6);
      case TransactionCategory.utilities:
        return const Color(0xFFFBBF24);
      case TransactionCategory.insurance:
        return const Color(0xFF60A5FA);
      case TransactionCategory.medical:
        return const Color(0xFFF87171);
      case TransactionCategory.education:
        return const Color(0xFF34D399);
      case TransactionCategory.investment:
        return AppTheme.rewardGold;
      case TransactionCategory.transport:
        return const Color(0xFFA78BFA);
      case TransactionCategory.rental:
        return const Color(0xFFFB923C);
      case TransactionCategory.subscription:
        return const Color(0xFF2DD4BF);
      case TransactionCategory.gift:
        return const Color(0xFFE879F9);
      case TransactionCategory.other:
      default:
        return Colors.grey;
    }
  }

  Widget _buildCategoryInsightsCard() {
    final categoryInsights = _insights!.categoryInsights;
    final topInsights = categoryInsights.insights.take(5).toList();
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0C152B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppTheme.primaryColor.withValues(alpha: 0.25),
          width: 1.5,
        ),
        boxShadow: AppTheme.neonGlow(color: AppTheme.primaryColor, opacity: 0.12, blurRadius: 12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.pie_chart_outline,
                color: AppTheme.primaryColor,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'CATEGORY BREAKDOWN',
                style: GoogleFonts.spaceGrotesk(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          
          if (topInsights.isEmpty)
            Center(
              child: Text(
                'No category data available',
                style: GoogleFonts.spaceGrotesk(color: Colors.white60),
              ),
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Pie Chart
                SizedBox(
                  height: 160,
                  width: 160,
                  child: PieChart(
                    PieChartData(
                      pieTouchData: PieTouchData(
                        touchCallback: (FlTouchEvent event, pieTouchResponse) {
                          setState(() {
                            if (!event.isInterestedForInteractions ||
                                pieTouchResponse == null ||
                                pieTouchResponse.touchedSection == null) {
                              _touchedIndex = -1;
                              return;
                            }
                            _touchedIndex = pieTouchResponse.touchedSection!.touchedSectionIndex;
                          });
                        },
                      ),
                      borderData: FlBorderData(show: false),
                      sectionsSpace: 3,
                      centerSpaceRadius: 35,
                      sections: topInsights.asMap().entries.map((entry) {
                        final index = entry.key;
                        final insight = entry.value;
                        final isTouched = index == _touchedIndex;
                        final color = _getCategoryNeonColor(insight.category);
                        final radius = isTouched ? 55.0 : 45.0;
                        
                        return PieChartSectionData(
                          color: color,
                          value: insight.totalSpent,
                          title: '${insight.percentage.toStringAsFixed(0)}%',
                          radius: radius,
                          titleStyle: GoogleFonts.spaceGrotesk(
                            fontSize: isTouched ? 14 : 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          badgeWidget: isTouched
                              ? Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0C152B),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: color, width: 1),
                                  ),
                                  child: Text(
                                    insight.category.name.toUpperCase(),
                                    style: GoogleFonts.spaceGrotesk(
                                      color: color,
                                      fontSize: 8,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                )
                              : null,
                          badgePositionPercentageOffset: 1.1,
                        );
                      }).toList(),
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                // Legend list
                Expanded(
                  child: Column(
                    children: topInsights.asMap().entries.map((entry) {
                      final index = entry.key;
                      final insight = entry.value;
                      final isTouched = index == _touchedIndex;
                      final color = _getCategoryNeonColor(insight.category);
                      
                      return MouseRegion(
                        onEnter: (_) => setState(() => _touchedIndex = index),
                        onExit: (_) => setState(() => _touchedIndex = -1),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          decoration: BoxDecoration(
                            color: isTouched
                                ? color.withValues(alpha: 0.1)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isTouched
                                  ? color.withValues(alpha: 0.3)
                                  : Colors.transparent,
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: color,
                                  boxShadow: AppTheme.neonGlow(color: color, opacity: 0.4, blurRadius: 4),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  insight.category.name.toUpperCase(),
                                  style: GoogleFonts.spaceGrotesk(
                                    color: isTouched ? Colors.white : Colors.white70,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '₹${insight.totalSpent.toStringAsFixed(0)}',
                                    style: GoogleFonts.spaceGrotesk(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    '${insight.percentage.toStringAsFixed(1)}%',
                                    style: GoogleFonts.spaceGrotesk(
                                      color: Colors.white38,
                                      fontSize: 9,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          
          if (categoryInsights.unusualSpendingCategories.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                border: Border.all(color: Colors.red.withValues(alpha: 0.3), width: 1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'UNUSUAL SPENDING DETECTED',
                          style: GoogleFonts.spaceGrotesk(
                            fontWeight: FontWeight.bold,
                            color: Colors.red,
                            fontSize: 11,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'High spending patterns in: ${categoryInsights.unusualSpendingCategories.map((c) => c.name.toUpperCase()).join(", ")}',
                          style: GoogleFonts.spaceGrotesk(
                            color: Colors.white70,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  
  Widget _buildSavingsOpportunitiesCard() {
    final opportunities = _insights!.savingsOpportunities;
    
    if (opportunities.isEmpty) {
      return Card(
        elevation: 4,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 48),
              const SizedBox(height: 8),
              Text(
                'Great job!',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Text('No major savings opportunities detected.'),
            ],
          ),
        ),
      );
    }
    
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.savings, color: Colors.green),
                const SizedBox(width: 8),
                Text(
                  'Savings Opportunities',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            ...opportunities.map((opportunity) => _buildSavingsOpportunityItem(opportunity)),
            
            const SizedBox(height: 12),            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green[50],
                border: Border.all(color: Colors.green[300]!),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Total Potential Savings: ₹${opportunities.fold(0.0, (sum, opp) => sum + opp.potentialSavings).toStringAsFixed(0)} per year',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.green[800],
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildSavingsOpportunityItem(SavingsOpportunity opportunity) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _getSavingsIcon(opportunity.type),
                  color: _getSavingsPriorityColor(opportunity.priority),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    opportunity.title,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Text(
                  '₹${opportunity.potentialSavings.toStringAsFixed(0)}',
                  style: TextStyle(
                    color: Colors.green[700],
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(opportunity.description),
          ],
        ),
      ),
    );
  }
  
  Widget _buildRewardOptimizationCard() {
    final rewardOpt = _insights!.rewardOptimization;
    
    if (rewardOpt.optimizations.isEmpty) {
      return const SizedBox.shrink();
    }
    
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.stars, color: Colors.amber),
                const SizedBox(width: 8),
                Text(
                  'Reward Optimization',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber[50],
                border: Border.all(color: Colors.amber[300]!),
                borderRadius: BorderRadius.circular(8),
              ),              child: Text(
                'Potential Additional Rewards: ₹${rewardOpt.totalAdditionalRewards.toStringAsFixed(0)} per year',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.amber[800],
                ),
                textAlign: TextAlign.center,
              ),
            ),
            
            const SizedBox(height: 12),
            
            ...rewardOpt.topOpportunities.map((opt) => _buildRewardOptimizationItem(opt)),
          ],
        ),
      ),
    );
  }
  
  Widget _buildRewardOptimizationItem(RewardOptimization optimization) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  optimization.category.name.toUpperCase(),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  optimization.recommendedCard,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Expanded(
            flex: 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '+₹${optimization.additionalRewards.toStringAsFixed(0)}',
                  style: TextStyle(
                    color: Colors.green[700],
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '${optimization.optimizedRewardRate}% vs ${optimization.currentRewardRate}%',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildPredictiveInsightsCard() {
    final predictiveInsights = _insights!.predictiveInsights;
    
    if (predictiveInsights.isEmpty) {
      return const SizedBox.shrink();
    }
    
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.psychology, color: Colors.purple),
                const SizedBox(width: 8),
                Text(
                  'AI Predictions',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            ...predictiveInsights.map((insight) => _buildPredictiveInsightItem(insight)),
          ],
        ),
      ),
    );
  }
    Widget _buildPredictiveInsightItem(PredictiveInsight insight) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey[100], // Changed to lighter background for better contrast
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.purple[300]!),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    insight.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.black87, // Dark text for readability
                      fontSize: 16,
                    ),
                  ),
                ),
                Text(
                  '${(insight.confidence * 100).toStringAsFixed(0)}% confidence',
                  style: TextStyle(
                    color: Colors.purple[600],
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              insight.description,
              style: const TextStyle(
                color: Colors.black87, // Dark text for readability
                fontSize: 14,
              ),
            ),            if (insight.actionable && insight.recommendation.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.lightbulb, size: 16, color: Colors.blue),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        insight.recommendation,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black87, // Dark text for readability
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
  
  // Helper methods for styling
  Color _getHealthScoreColor(double score) {
    if (score >= 80) return Colors.green;
    if (score >= 60) return Colors.orange;
    return Colors.red;
  }
  
  String _getHealthScoreDescription(double score) {
    if (score >= 80) return 'Excellent';
    if (score >= 60) return 'Good';
    if (score >= 40) return 'Fair';
    return 'Needs Improvement';
  }
  
  IconData _getTrendIcon(String trend) {
    switch (trend) {
      case 'increasing':
        return Icons.trending_up;
      case 'decreasing':
        return Icons.trending_down;
      default:
        return Icons.trending_flat;
    }
  }
  
  Color _getTrendColor(String trend) {
    switch (trend) {
      case 'increasing':
        return Colors.red;
      case 'decreasing':
        return Colors.green;
      default:
        return Colors.blue;
    }
  }
  
  IconData _getSavingsIcon(SavingsOpportunityType type) {
    switch (type) {
      case SavingsOpportunityType.subscriptions:
        return Icons.subscriptions;
      case SavingsOpportunityType.lifestyle:
        return Icons.restaurant;
      case SavingsOpportunityType.transportation:
        return Icons.directions_car;
      case SavingsOpportunityType.utilities:
        return Icons.electrical_services;
      case SavingsOpportunityType.insurance:
        return Icons.security;
    }
  }
  
  Color _getSavingsPriorityColor(SavingsPriority priority) {
    switch (priority) {
      case SavingsPriority.high:
        return Colors.red;
      case SavingsPriority.medium:
        return Colors.orange;
      case SavingsPriority.low:
        return Colors.green;
    }
  }
}
