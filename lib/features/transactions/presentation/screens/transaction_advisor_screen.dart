import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cardcompass/features/cards/providers/cards_provider.dart';
import 'package:cardcompass/features/transactions/providers/transactions_provider.dart';
import 'package:cardcompass/shared/widgets/state_widgets.dart';
import 'package:cardcompass/shared/models/transaction.dart';
import 'package:cardcompass/shared/models/credit_card.dart';

/// Screen to provide transaction advice and recommendations
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
      appBar: AppBar(
        title: const Text('Transaction Advisor'),
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.lightbulb_outline), text: 'Best Card'),
            Tab(icon: Icon(Icons.analytics_outlined), text: 'Insights'),
            Tab(icon: Icon(Icons.trending_up), text: 'Optimize'),
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
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Transaction Input Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Get Card Recommendation',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  
                  // Amount Input
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'Transaction Amount (₹)',
                      prefixIcon: Icon(Icons.currency_rupee),
                      border: OutlineInputBorder(),
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
                    initialValue: _selectedCategory,
                    decoration: const InputDecoration(
                      labelText: 'Transaction Category',
                      prefixIcon: Icon(Icons.category),
                      border: OutlineInputBorder(),
                    ),
                    items: TransactionCategory.values.map((category) {
                      return DropdownMenuItem(
                        value: category.name,
                        child: Text(_getCategoryDisplayName(category)),
                      );
                    }).toList()..insert(0, const DropdownMenuItem(
                      value: 'All',
                      child: Text('Select Category'),
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
          ),
          
          const SizedBox(height: 16),
          
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
        title: 'No Cards Available',
        message: 'Add credit cards to get recommendations',
        icon: Icons.credit_card_off,
      );
    }

    // Calculate recommendations based on benefits
    final recommendations = _calculateRecommendations(cards);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recommended Cards',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        
        ...recommendations.map((rec) => _buildRecommendationCard(rec)),
      ],
    );
  }

  Widget _buildRecommendationCard(CardRecommendation recommendation) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getRankColor(recommendation.rank),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '#${recommendation.rank}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        recommendation.card.cardName,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        recommendation.card.bankName,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            // Rewards Calculation
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Estimated Rewards:'),
                      Text(
                        '₹${recommendation.estimatedReward.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                  if (recommendation.rewardRate > 0) ...[
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Reward Rate:'),
                        Text('${recommendation.rewardRate}%'),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            
            const SizedBox(height: 8),
            
            // Reason
            if (recommendation.reason.isNotEmpty)
              Text(
                recommendation.reason,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey[600],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickCategories() {
    final categories = [
      {'name': 'Dining', 'icon': Icons.restaurant, 'category': TransactionCategory.food},
      {'name': 'Fuel', 'icon': Icons.local_gas_station, 'category': TransactionCategory.fuel},
      {'name': 'Shopping', 'icon': Icons.shopping_bag, 'category': TransactionCategory.shopping},
      {'name': 'Grocery', 'icon': Icons.local_grocery_store, 'category': TransactionCategory.grocery},
      {'name': 'Travel', 'icon': Icons.flight, 'category': TransactionCategory.travel},
      {'name': 'Entertainment', 'icon': Icons.movie, 'category': TransactionCategory.entertainment},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Text(
          'Quick Category Selection',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            childAspectRatio: 1.2,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: categories.length,
          itemBuilder: (context, index) {
            final category = categories[index];
            return Card(
              child: InkWell(
                onTap: () {
                  setState(() {
                    _selectedCategory = (category['category'] as TransactionCategory).name;
                  });
                },
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      category['icon'] as IconData,
                      size: 32,
                      color: _selectedCategory == (category['category'] as TransactionCategory).name
                          ? Theme.of(context).primaryColor
                          : Colors.grey[600],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      category['name'] as String,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _selectedCategory == (category['category'] as TransactionCategory).name
                            ? Theme.of(context).primaryColor
                            : Colors.grey[600],
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
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Spending Insights',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          
          // Spending by Category
          _buildSpendingByCategory(transactions),
          
          const SizedBox(height: 24),
          
          // Monthly Trends
          _buildMonthlyTrends(),
          
          const SizedBox(height: 24),
          
          // Reward Optimization
          _buildRewardOptimization(),
        ],
      ),
    );
  }

  Widget _buildOptimizeTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Optimization Tips',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          
          _buildOptimizationTip(
            title: 'Maximize Fuel Rewards',
            description: 'Use your HDFC Regalia for fuel purchases to get 2% cashback',
            icon: Icons.local_gas_station,
            color: Colors.orange,
            savings: '₹200/month',
          ),
          
          _buildOptimizationTip(
            title: 'Dining Benefits',
            description: 'Use ICICI Amazon Pay for restaurant bills to earn 5% rewards',
            icon: Icons.restaurant,
            color: Colors.red,
            savings: '₹150/month',
          ),
          
          _buildOptimizationTip(
            title: 'Online Shopping',
            description: 'Use Amazon Pay Credit Card for online purchases',
            icon: Icons.shopping_cart,
            color: Colors.blue,
            savings: '₹300/month',
          ),
        ],
      ),
    );
  }

  Widget _buildSpendingByCategory(List<Transaction> transactions) {
    // Group transactions by category
    final categorySpending = <TransactionCategory, double>{};
    for (final transaction in transactions) {
      categorySpending[transaction.category] = 
          (categorySpending[transaction.category] ?? 0) + transaction.amount;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Spending by Category',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            ...categorySpending.entries.map((entry) {
              final percentage = transactions.isEmpty 
                  ? 0.0 
                  : (entry.value / transactions.fold(0.0, (sum, t) => sum + t.amount)) * 100;
              
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(_getCategoryDisplayName(entry.key)),
                    ),
                    Text('₹${entry.value.toStringAsFixed(0)}'),
                    const SizedBox(width: 8),
                    Text('${percentage.toStringAsFixed(1)}%'),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthlyTrends() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Monthly Spending Trend',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            // Placeholder for chart
            Container(
              height: 200,
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Center(
                child: Text('Chart coming soon'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRewardOptimization() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Reward Optimization',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Text(
              'You could earn ₹500 more per month by optimizing your card usage!',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
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
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            Column(
              children: [
                Text(
                  'Save',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  savings,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<CardRecommendation> _calculateRecommendations(List<CreditCard> cards) {
    final recommendations = <CardRecommendation>[];
    
    for (final card in cards) {
      double rewardRate = 0.0;
      String reason = 'General rewards';
      
      // Calculate reward rate based on category and card benefits
      if (_selectedCategory == TransactionCategory.fuel.name) {
        if (card.bankName.contains('HDFC')) {
          rewardRate = 2.0;
          reason = 'HDFC cards offer 2% cashback on fuel';
        } else {
          rewardRate = 1.0;
          reason = 'Standard fuel rewards';
        }
      } else if (_selectedCategory == TransactionCategory.food.name) {
        if (card.cardName.contains('Amazon')) {
          rewardRate = 5.0;
          reason = 'Amazon Pay offers 5% cashback on dining';
        } else {
          rewardRate = 2.0;
          reason = 'Standard dining rewards';
        }
      } else {
        rewardRate = 1.0;
        reason = 'Standard reward rate';
      }
      
      final estimatedReward = (_transactionAmount * rewardRate) / 100;
      
      recommendations.add(CardRecommendation(
        card: card,
        estimatedReward: estimatedReward,
        rewardRate: rewardRate,
        reason: reason,
        rank: 0, // Will be set after sorting
      ));
    }
    
    // Sort by estimated reward and assign ranks
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
        return category.name.toUpperCase();
    }
  }

  Color _getRankColor(int rank) {
    switch (rank) {
      case 1:
        return Colors.green;
      case 2:
        return Colors.orange;
      case 3:
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }
}

/// Card recommendation model
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
