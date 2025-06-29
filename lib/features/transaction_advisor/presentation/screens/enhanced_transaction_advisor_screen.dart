import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cardcompass/features/auth/providers/auth_provider.dart';
import 'package:cardcompass/core/services/advanced_benefit_calculation_service.dart';
import 'package:cardcompass/shared/widgets/state_widgets.dart';
import 'package:intl/intl.dart';

/// Enhanced transaction advisor with advanced benefit calculations
class EnhancedTransactionAdvisorScreen extends ConsumerStatefulWidget {
  const EnhancedTransactionAdvisorScreen({super.key});

  @override
  ConsumerState<EnhancedTransactionAdvisorScreen> createState() => 
      _EnhancedTransactionAdvisorScreenState();
}

class _EnhancedTransactionAdvisorScreenState 
    extends ConsumerState<EnhancedTransactionAdvisorScreen> 
    with TickerProviderStateMixin {
  
  late TabController _tabController;
  final AdvancedBenefitCalculationService _benefitService = 
      AdvancedBenefitCalculationService();
  
  // Form controllers
  final _amountController = TextEditingController();
  final _merchantController = TextEditingController();
  
  // State variables
  String _selectedCategory = 'dining';
  bool _isCalculating = false;
  Map<String, dynamic>? _recommendation;
  List<Map<String, dynamic>> _optimizations = [];
  Map<String, dynamic>? _rewardSummary;
  List<Map<String, dynamic>> _personalizedRecommendations = [];
  bool _isLoadingOptimizations = false;
  bool _isLoadingSummary = false;
  bool _isLoadingRecommendations = false;

  final List<String> _categories = [
    'dining',
    'fuel',
    'groceries',
    'shopping',
    'travel',
    'utilities',
    'entertainment',
    'healthcare',
    'education',
    'other',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadInitialData();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _amountController.dispose();
    _merchantController.dispose();
    super.dispose();
  }

  void _loadInitialData() {
    _loadOptimizations();
    _loadRewardSummary();
    _loadPersonalizedRecommendations();
  }

  Future<void> _calculateBestCard() async {
    if (_amountController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter an amount')),
      );
      return;
    }

    final user = ref.read(authStateProvider).user;
    if (user == null) return;

    setState(() {
      _isCalculating = true;
      _recommendation = null;
    });

    try {
      final amount = double.parse(_amountController.text);
      final merchant = _merchantController.text.trim();
      
      final result = await _benefitService.calculateBestCard(
        userId: user.id,
        amount: amount,
        merchantName: merchant.isEmpty ? 'General Merchant' : merchant,
        category: _selectedCategory,
      );

      setState(() {
        _recommendation = result;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    } finally {
      setState(() {
        _isCalculating = false;
      });
    }
  }

  Future<void> _loadOptimizations() async {
    final user = ref.read(authStateProvider).user;
    if (user == null) return;

    setState(() {
      _isLoadingOptimizations = true;
    });

    try {
      final optimizations = await _benefitService.getSpendingOptimizations(user.id);
      setState(() {
        _optimizations = optimizations;
      });
    } catch (e) {
      print('Error loading optimizations: $e');
    } finally {
      setState(() {
        _isLoadingOptimizations = false;
      });
    }
  }

  Future<void> _loadRewardSummary() async {
    final user = ref.read(authStateProvider).user;
    if (user == null) return;

    setState(() {
      _isLoadingSummary = true;
    });

    try {
      final summary = await _benefitService.getMonthlyRewardSummary(user.id);
      setState(() {
        _rewardSummary = summary;
      });
    } catch (e) {
      print('Error loading reward summary: $e');
    } finally {
      setState(() {
        _isLoadingSummary = false;
      });
    }
  }

  Future<void> _loadPersonalizedRecommendations() async {
    final user = ref.read(authStateProvider).user;
    if (user == null) return;

    setState(() {
      _isLoadingRecommendations = true;
    });

    try {
      final recommendations = await _benefitService.getPersonalizedCardRecommendations(user.id);
      setState(() {
        _personalizedRecommendations = recommendations;
      });
    } catch (e) {
      print('Error loading personalized recommendations: $e');
    } finally {
      setState(() {
        _isLoadingRecommendations = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Card Advisor'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(icon: Icon(Icons.calculate), text: 'Calculator'),
            Tab(icon: Icon(Icons.trending_up), text: 'Optimize'),
            Tab(icon: Icon(Icons.analytics), text: 'Summary'),
            Tab(icon: Icon(Icons.recommend), text: 'Recommendations'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildCalculatorTab(),
          _buildOptimizationsTab(),
          _buildSummaryTab(),
          _buildRecommendationsTab(),
        ],
      ),
    );
  }

  Widget _buildCalculatorTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Transaction Details',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _amountController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Amount (₹)',
                      prefixIcon: Icon(Icons.currency_rupee),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _merchantController,
                    decoration: const InputDecoration(
                      labelText: 'Merchant (Optional)',
                      prefixIcon: Icon(Icons.store),
                      border: OutlineInputBorder(),
                      hintText: 'e.g., Amazon, Swiggy, BPCL',
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _selectedCategory,
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      prefixIcon: Icon(Icons.category),
                      border: OutlineInputBorder(),
                    ),
                    items: _categories.map((category) {
                      return DropdownMenuItem(
                        value: category,
                        child: Text(category.toUpperCase()),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedCategory = value!;
                      });
                    },
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isCalculating ? null : _calculateBestCard,
                      icon: _isCalculating 
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.calculate),
                      label: Text(_isCalculating ? 'Calculating...' : 'Find Best Card'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          if (_recommendation != null) ...[
            const SizedBox(height: 16),
            _buildRecommendationResult(),
          ],
        ],
      ),
    );
  }

  Widget _buildRecommendationResult() {
    final bestCard = _recommendation!['bestCard'];
    final recommendations = _recommendation!['recommendations'] as List<dynamic>;

    if (bestCard == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(
                Icons.info_outline,
                size: 48,
                color: Colors.grey[400],
              ),
              const SizedBox(height: 8),
              Text(
                'No Cards Found',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                'You don\'t have any cards that offer rewards for this transaction.',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Best card recommendation
        Card(
          color: Colors.green.shade50,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.star, color: Colors.green.shade700),
                    const SizedBox(width: 8),
                    Text(
                      'Best Card',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  bestCard['card']['card_name'],
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  bestCard['card']['bank_name'],
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Reward: ₹${bestCard['total_reward'].toStringAsFixed(2)}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade700,
                      ),
                    ),
                    Text(
                      '${bestCard['reward_percentage'].toStringAsFixed(2)}%',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Divider(),
                const Text(
                  'Applicable Benefits:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                ...bestCard['applicable_benefits'].map<Widget>((benefit) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle, 
                             size: 16, 
                             color: Colors.green.shade600),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${benefit['benefit_name']}: ₹${benefit['reward'].toStringAsFixed(2)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ],
            ),
          ),
        ),

        // All card recommendations
        if (recommendations.length > 1) ...[
          const SizedBox(height: 16),
          Text(
            'All Your Cards',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          ...recommendations.map<Widget>((recommendation) {
            final isFirst = recommendation == recommendations.first;
            return Card(
              color: isFirst ? Colors.green.shade50 : null,
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: isFirst ? Colors.green : Colors.grey,
                  child: Icon(
                    isFirst ? Icons.star : Icons.credit_card,
                    color: Colors.white,
                  ),
                ),
                title: Text(recommendation['card']['card_name']),
                subtitle: Text(recommendation['card']['bank_name']),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '₹${recommendation['total_reward'].toStringAsFixed(2)}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isFirst ? Colors.green.shade700 : null,
                      ),
                    ),
                    Text(
                      '${recommendation['reward_percentage'].toStringAsFixed(2)}%',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ],
      ],
    );
  }

  Widget _buildOptimizationsTab() {
    if (_isLoadingOptimizations) {
      return const LoadingState(message: 'Analyzing your spending...');
    }

    if (_optimizations.isEmpty) {
      return const EmptyState(
        icon: Icons.trending_up,
        title: 'No Optimizations Found',
        message: 'Your card usage is already optimized! Keep up the good work.',
      );
    }

    return RefreshIndicator(
      onRefresh: _loadOptimizations,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _optimizations.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            final totalMissedRewards = _optimizations.fold<double>(
              0.0, 
              (sum, opt) => sum + opt['potential_savings']
            );
            
            return Card(
              color: Colors.orange.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Icon(
                      Icons.insights,
                      size: 48,
                      color: Colors.orange.shade700,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Optimization Opportunities',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'You could have earned ₹${totalMissedRewards.toStringAsFixed(2)} more this month!',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.orange.shade700,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          final optimization = _optimizations[index - 1];
          final transaction = optimization['transaction'];
          final bestCard = optimization['best_card'];
          
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          transaction['merchant_name'] ?? 'Unknown Merchant',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8, 
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '₹${optimization['potential_savings'].toStringAsFixed(2)} missed',
                          style: TextStyle(
                            color: Colors.red.shade700,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Amount: ₹${transaction['amount']}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  Text(
                    'Date: ${DateFormat('MMM dd, yyyy').format(DateTime.parse(transaction['transaction_date']))}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  const Divider(),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.lightbulb_outline, 
                           size: 16, 
                           color: Colors.orange.shade600),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Best card: ${bestCard['card']['card_name']}',
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            color: Colors.orange.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    'Would have earned: ₹${optimization['optimal_reward'].toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSummaryTab() {
    if (_isLoadingSummary) {
      return const LoadingState(message: 'Loading reward summary...');
    }

    if (_rewardSummary == null || _rewardSummary!.isEmpty) {
      return const EmptyState(
        icon: Icons.analytics,
        title: 'No Data Available',
        message: 'Start making transactions to see your reward summary.',
      );
    }

    final summary = _rewardSummary!;
    
    return RefreshIndicator(
      onRefresh: _loadRewardSummary,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Overall summary card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'This Month\'s Summary',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _buildSummaryItem(
                            'Total Spending',
                            '₹${summary['total_spending']?.toStringAsFixed(0) ?? '0'}',
                            Icons.account_balance_wallet,
                            Colors.blue,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildSummaryItem(
                            'Rewards Earned',
                            '₹${summary['total_rewards_earned']?.toStringAsFixed(2) ?? '0'}',
                            Icons.stars,
                            Colors.green,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _buildSummaryItem(
                            'Missed Rewards',
                            '₹${summary['missed_rewards']?.toStringAsFixed(2) ?? '0'}',
                            Icons.warning,
                            Colors.orange,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildSummaryItem(
                            'Optimization Score',
                            '${summary['optimization_score']?.toStringAsFixed(1) ?? '0'}%',
                            Icons.score,
                            Colors.purple,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Category breakdown
            if (summary['category_breakdown'] != null) ...[
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Rewards by Category',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ...(summary['category_breakdown'] as Map<String, dynamic>)
                          .entries
                          .map((entry) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                entry.key.toUpperCase(),
                                style: const TextStyle(fontWeight: FontWeight.w500),
                              ),
                              Text(
                                '₹${entry.value.toStringAsFixed(2)}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green.shade700,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryItem(String title, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 32),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          title,
          style: Theme.of(context).textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildRecommendationsTab() {
    if (_isLoadingRecommendations) {
      return const LoadingState(message: 'Finding personalized recommendations...');
    }

    if (_personalizedRecommendations.isEmpty) {
      return const EmptyState(
        icon: Icons.recommend,
        title: 'No Recommendations Available',
        message: 'We need more transaction data to provide personalized card recommendations.',
      );
    }

    return RefreshIndicator(
      onRefresh: _loadPersonalizedRecommendations,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _personalizedRecommendations.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Card(
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Icon(
                      Icons.recommend,
                      size: 48,
                      color: Colors.blue.shade700,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Personalized Card Recommendations',
                      style: Theme.of(context).textTheme.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Based on your spending patterns',
                      style: Theme.of(context).textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }

          final recommendation = _personalizedRecommendations[index - 1];
          final card = recommendation['card'];
          
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              card['card_name'],
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              card['bank_name'],
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12, 
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.shade100,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          '₹${recommendation['projected_monthly_reward'].toStringAsFixed(0)}/month',
                          style: TextStyle(
                            color: Colors.green.shade700,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Annual Fee: ₹${card['annual_fee']?.toStringAsFixed(0) ?? '0'}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    'Net Annual Benefit: ₹${recommendation['net_annual_benefit'].toStringAsFixed(0)}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: recommendation['net_annual_benefit'] > 0 
                          ? Colors.green.shade700 
                          : Colors.red.shade700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Matching Benefits:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  ...recommendation['matching_categories'].take(3).map<Widget>((category) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        children: [
                          Icon(Icons.check, size: 14, color: Colors.green.shade600),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              category,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
