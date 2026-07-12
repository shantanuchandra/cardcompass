import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cardcompass/features/cards/providers/cards_provider.dart';
import 'package:cardcompass/features/transactions/providers/transactions_provider.dart';
import 'package:cardcompass/shared/widgets/state_widgets.dart';
import 'package:cardcompass/shared/models/transaction.dart';
import 'package:cardcompass/shared/models/credit_card.dart';
import 'package:cardcompass/core/theme.dart';

/// Screen to provide transaction advice and recommendations in cyber-fintech style
class TransactionAdvisorScreen extends ConsumerStatefulWidget {
  const TransactionAdvisorScreen({super.key});

  @override
  ConsumerState<TransactionAdvisorScreen> createState() => _TransactionAdvisorScreenState();
}

class _TransactionAdvisorScreenState extends ConsumerState<TransactionAdvisorScreen> 
    with TickerProviderStateMixin {
  late TabController _tabController;
  String _selectedCategory = 'All';
  double _transactionAmount = 0.0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050B18),
      appBar: AppBar(
        title: Text(
          'TRANSACTION ADVISOR',
          style: GoogleFonts.spaceGrotesk(
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
            fontSize: 16,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppTheme.primaryColor,
          unselectedLabelColor: Colors.white38,
          indicatorColor: AppTheme.primaryColor,
          indicatorSize: TabBarIndicatorSize.tab,
          labelStyle: GoogleFonts.spaceGrotesk(
            fontWeight: FontWeight.bold,
            fontSize: 10,
            letterSpacing: 0.5,
          ),
          tabs: const [
            Tab(icon: Icon(Icons.lightbulb_outline, size: 18), text: 'BEST CARD'),
            Tab(icon: Icon(Icons.analytics_outlined, size: 18), text: 'INSIGHTS'),
            Tab(icon: Icon(Icons.trending_up, size: 18), text: 'OPTIMIZE'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildBestCardTab(),
          _buildInsightsTab(),
          _buildOptimizeTab(),
        ],
      ),
    );
  }

  Widget _buildBestCardTab() {
    final cards = ref.watch(cardsProvider);
    
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Transaction Input Section
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF0C152B),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'QUERY SPECIFICATIONS',
                  style: GoogleFonts.spaceGrotesk(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    fontSize: 11,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 18),
                
                // Amount Input
                TextField(
                  style: GoogleFonts.plusJakartaSans(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Transaction Amount (₹)',
                    prefixIcon: Icon(Icons.currency_rupee, color: AppTheme.primaryColor),
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (value) {
                    setState(() {
                      _transactionAmount = double.tryParse(value) ?? 0.0;
                    });
                  },
                ),
                
                const SizedBox(height: 16),
                
                // Category Dropdown
                DropdownButtonFormField<String>(
                  dropdownColor: const Color(0xFF0C152B),
                  initialValue: _selectedCategory,
                  decoration: const InputDecoration(
                    labelText: 'Transaction Category',
                    prefixIcon: Icon(Icons.category_outlined, color: AppTheme.primaryColor),
                  ),
                  items: TransactionCategory.values.map((category) {
                    return DropdownMenuItem(
                      value: category.name,
                      child: Text(
                        _getCategoryDisplayName(category).toUpperCase(),
                        style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    );
                  }).toList()..insert(0, DropdownMenuItem(
                    value: 'All',
                    child: Text(
                      'SELECT CATEGORY',
                      style: GoogleFonts.spaceGrotesk(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  )),
                  onChanged: (value) {
                    setState(() {
                      _selectedCategory = value ?? 'All';
                    });
                  },
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Recommendations
          if (_transactionAmount > 0 && _selectedCategory != 'All')
            _buildRecommendations(cards),
          
          // Quick Categories
          _buildQuickCategories(),
        ],
      ),
    );
  }

  Widget _buildRecommendations(List<CreditCard> cards) {
    if (cards.isEmpty) {
      return const EmptyState(
        title: 'NO ACTIVE INTEGRATIONS',
        message: 'Add credit card profiles to process evaluations.',
        icon: Icons.credit_card_off,
      );
    }

    final recommendations = _calculateRecommendations(cards);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ROUTING FEASIBILITY INDEX',
          style: GoogleFonts.spaceGrotesk(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 11,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 12),
        ...recommendations.map((rec) => _buildRecommendationCard(rec)),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildRecommendationCard(CardRecommendation recommendation) {
    final rankColor = _getRankColor(recommendation.rank);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0C152B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: recommendation.rank == 1 
              ? AppTheme.primaryColor.withValues(alpha: 0.25) 
              : Colors.white.withValues(alpha: 0.06),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: rankColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: rankColor.withValues(alpha: 0.25)),
                ),
                child: Text(
                  'RANK #${recommendation.rank}',
                  style: GoogleFonts.spaceGrotesk(
                    color: rankColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 9,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      recommendation.card.cardName.toUpperCase(),
                      style: GoogleFonts.spaceGrotesk(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      recommendation.card.bankName.toUpperCase(),
                      style: GoogleFonts.plusJakartaSans(
                        color: Colors.white38,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 14),
          
          // Rewards Calculation
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF050B18),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'ESTIMATED SAVINGS:',
                      style: GoogleFonts.spaceGrotesk(color: Colors.white60, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '₹${recommendation.estimatedReward.toStringAsFixed(2)}',
                      style: GoogleFonts.spaceGrotesk(
                        fontWeight: FontWeight.bold,
                        color: AppTheme.successColor,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                if (recommendation.rewardRate > 0) ...[
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'RETURN YIELD RATE:',
                        style: GoogleFonts.spaceGrotesk(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${recommendation.rewardRate}%',
                        style: GoogleFonts.spaceGrotesk(color: AppTheme.successColor, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          
          const SizedBox(height: 10),
          
          if (recommendation.reason.isNotEmpty)
            Text(
              recommendation.reason,
              style: GoogleFonts.plusJakartaSans(
                color: Colors.white60,
                fontSize: 11,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildQuickCategories() {
    final categories = [
      {'name': 'Dining', 'icon': Icons.restaurant, 'category': TransactionCategory.food},
      {'name': 'Fuel', 'icon': Icons.local_gas_station, 'category': TransactionCategory.fuel},
      {'name': 'Shopping', 'icon': Icons.shopping_bag_outlined, 'category': TransactionCategory.shopping},
      {'name': 'Grocery', 'icon': Icons.local_grocery_store_outlined, 'category': TransactionCategory.grocery},
      {'name': 'Travel', 'icon': Icons.flight_takeoff_outlined, 'category': TransactionCategory.travel},
      {'name': 'Showtimes', 'icon': Icons.local_movies_outlined, 'category': TransactionCategory.entertainment},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Text(
          'QUICK CATEGORY GRID',
          style: GoogleFonts.spaceGrotesk(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 11,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            childAspectRatio: 1.1,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: categories.length,
          itemBuilder: (context, index) {
            final category = categories[index];
            final catEnum = category['category'] as TransactionCategory;
            final isSelected = _selectedCategory == catEnum.name;
            final borderActiveColor = isSelected ? AppTheme.primaryColor : Colors.white.withValues(alpha: 0.06);

            return Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0C152B),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: borderActiveColor, width: 1.2),
              ),
              child: InkWell(
                onTap: () {
                  setState(() {
                    _selectedCategory = catEnum.name;
                  });
                },
                borderRadius: BorderRadius.circular(16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      category['icon'] as IconData,
                      size: 22,
                      color: isSelected ? AppTheme.primaryColor : Colors.white60,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      (category['name'] as String).toUpperCase(),
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: isSelected ? AppTheme.primaryColor : Colors.white60,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildInsightsTab() {
    final transactions = ref.watch(transactionsProvider);
    
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SPENDING ANALYTICS INSIGHTS',
            style: GoogleFonts.spaceGrotesk(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 16),
          _buildSpendingByCategory(transactions),
          const SizedBox(height: 20),
          _buildMonthlyTrends(),
          const SizedBox(height: 20),
          _buildRewardOptimization(),
        ],
      ),
    );
  }

  Widget _buildOptimizeTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'YIELD OPTIMIZATION INSTRUCTIONS',
            style: GoogleFonts.spaceGrotesk(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 16),
          
          _buildOptimizationTip(
            title: 'MAXIMIZE FUEL REWARDS',
            description: 'Route gas payments to HDFC Regalia cards to utilize 2% return structures.',
            icon: Icons.local_gas_station_outlined,
            color: AppTheme.secondaryColor,
            savings: '₹200/month',
          ),
          
          _buildOptimizationTip(
            title: 'DINING BENEFIT ROUTING',
            description: 'Charge restaurant merchant categories to ICICI Amazon Pay for 5% reward rates.',
            icon: Icons.restaurant,
            color: AppTheme.primaryColor,
            savings: '₹150/month',
          ),
          
          _buildOptimizationTip(
            title: 'ONLINE MERCHANDISE PORTAL',
            description: 'Utilize co-branded credit cards for online shopping purchases.',
            icon: Icons.shopping_bag_outlined,
            color: AppTheme.successColor,
            savings: '₹300/month',
          ),
        ],
      ),
    );
  }

  Widget _buildSpendingByCategory(List<Transaction> transactions) {
    final categorySpending = <TransactionCategory, double>{};
    for (final transaction in transactions) {
      categorySpending[transaction.category] = 
          (categorySpending[transaction.category] ?? 0) + transaction.amount;
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF0C152B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'CATEGORY EXPENDITURE DISTRIBUTION',
            style: GoogleFonts.spaceGrotesk(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 11,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 16),
          if (transactions.isEmpty)
            Center(
              child: Text(
                'No recorded category spendings.',
                style: GoogleFonts.plusJakartaSans(color: Colors.white30, fontSize: 11),
              ),
            )
          else
            ...categorySpending.entries.map((entry) {
              final percentage = (entry.value / transactions.fold(0.0, (sum, t) => sum + t.amount)) * 100;
              
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _getCategoryDisplayName(entry.key).toUpperCase(),
                        style: GoogleFonts.spaceGrotesk(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                    Text(
                      '₹${entry.value.toStringAsFixed(0)}',
                      style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${percentage.toStringAsFixed(1)}%',
                      style: GoogleFonts.spaceGrotesk(color: AppTheme.primaryColor, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildMonthlyTrends() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF0C152B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'MONTHLY HISTORIC TIMELINE',
            style: GoogleFonts.spaceGrotesk(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 11,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            height: 140,
            decoration: BoxDecoration(
              color: const Color(0xFF050B18),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            ),
            child: Center(
              child: Text(
                'Timeline chart staging...',
                style: GoogleFonts.plusJakartaSans(color: Colors.white24, fontSize: 11),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRewardOptimization() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF0C152B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'REWARDS EFFICIENCY MULTIPLIER',
            style: GoogleFonts.spaceGrotesk(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 11,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'By fully optimizing active rule paths, monthly savings can increase by ₹500 across merchant categories.',
            style: GoogleFonts.plusJakartaSans(
              color: AppTheme.successColor,
              fontSize: 11,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptimizationTip({
    required String title,
    required String description,
    required IconData icon,
    required Color color,
    required String savings,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0C152B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withValues(alpha: 0.2)),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title.toUpperCase(),
                  style: GoogleFonts.spaceGrotesk(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: GoogleFonts.plusJakartaSans(
                    color: Colors.white60,
                    fontSize: 11,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'YIELD',
                style: GoogleFonts.spaceGrotesk(color: Colors.white38, fontSize: 8, fontWeight: FontWeight.bold),
              ),
              Text(
                savings,
                style: GoogleFonts.spaceGrotesk(
                  color: AppTheme.successColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<CardRecommendation> _calculateRecommendations(List<CreditCard> cards) {
    final recommendations = <CardRecommendation>[];
    
    for (final card in cards) {
      double rewardRate = 0.0;
      String reason = 'General rewards';
      
      if (_selectedCategory == TransactionCategory.fuel.name) {
        if (card.bankName.contains('HDFC')) {
          rewardRate = 2.0;
          reason = 'HDFC cards offer 2% cashback on fuel purchases.';
        } else {
          rewardRate = 1.0;
          reason = 'Standard fuel rewards yield.';
        }
      } else if (_selectedCategory == TransactionCategory.food.name) {
        if (card.cardName.contains('Amazon')) {
          rewardRate = 5.0;
          reason = 'Amazon Pay Credit Card offers 5% cashback on dining.';
        } else {
          rewardRate = 2.0;
          reason = 'Standard dining category return rates.';
        }
      } else {
        rewardRate = 1.0;
        reason = 'Standard general reward rate.';
      }
      
      final estimatedReward = (_transactionAmount * rewardRate) / 100;
      
      recommendations.add(CardRecommendation(
        card: card,
        estimatedReward: estimatedReward,
        rewardRate: rewardRate,
        reason: reason,
        rank: 0,
      ));
    }
    
    recommendations.sort((a, b) => b.estimatedReward.compareTo(a.estimatedReward));
    for (int i = 0; i < recommendations.length; i++) {
      recommendations[i] = recommendations[i].copyWith(rank: i + 1);
    }
    
    return recommendations;
  }

  String _getCategoryDisplayName(TransactionCategory category) {
    switch (category) {
      case TransactionCategory.food:
        return 'Dining';
      case TransactionCategory.fuel:
        return 'Fuel';
      case TransactionCategory.grocery:
        return 'Grocery';
      case TransactionCategory.shopping:
        return 'Shopping';
      case TransactionCategory.travel:
        return 'Travel';
      case TransactionCategory.entertainment:
        return 'Entertainment';
      case TransactionCategory.utilities:
        return 'Utilities';
      case TransactionCategory.transport:
        return 'Transport';
      default:
        return category.name;
    }
  }

  Color _getRankColor(int rank) {
    switch (rank) {
      case 1:
        return AppTheme.successColor;
      case 2:
        return AppTheme.warningColor;
      case 3:
        return AppTheme.primaryColor;
      default:
        return Colors.white38;
    }
  }
}

class CardRecommendation {
  final CreditCard card;
  final double estimatedReward;
  final double rewardRate;
  final String reason;
  final int rank;

  CardRecommendation({
    required this.card,
    required this.estimatedReward,
    required this.rewardRate,
    required this.reason,
    required this.rank,
  });

  CardRecommendation copyWith({
    CreditCard? card,
    double? estimatedReward,
    double? rewardRate,
    String? reason,
    int? rank,
  }) {
    return CardRecommendation(
      card: card ?? this.card,
      estimatedReward: estimatedReward ?? this.estimatedReward,
      rewardRate: rewardRate ?? this.rewardRate,
      reason: reason ?? this.reason,
      rank: rank ?? this.rank,
    );
  }
}
