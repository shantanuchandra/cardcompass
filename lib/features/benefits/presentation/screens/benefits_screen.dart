import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cardcompass/features/auth/providers/auth_provider.dart';
import 'package:cardcompass/features/benefits/viewmodels/benefits_viewmodel.dart';
import 'package:cardcompass/shared/models/credit_card.dart';
import 'package:cardcompass/shared/widgets/state_widgets.dart';

/// Screen to manage and view credit card benefits
class BenefitsScreen extends ConsumerStatefulWidget {
  const BenefitsScreen({super.key});

  @override
  ConsumerState<BenefitsScreen> createState() => _BenefitsScreenState();
}

class _BenefitsScreenState extends ConsumerState<BenefitsScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    // Delay loading benefits until after the widget tree is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadBenefits();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
  
  void _loadBenefits() {
    final user = ref.read(authStateProvider).user;
    if (user != null) {
      ref.read(benefitsViewModelProvider.notifier).loadBenefitsData(user.id);
    }
  }@override
  Widget build(BuildContext context) {
    final benefitsState = ref.watch(benefitsViewModelProvider);

    if (benefitsState.isLoading) {
      return const Scaffold(
        body: LoadingState(message: 'Loading benefits...'),
      );
    }

    if (benefitsState.error != null) {
      return Scaffold(
        body: ErrorState(
          error: benefitsState.error!,
          onRetry: _loadBenefits,
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Benefits Manager'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.card_giftcard), text: 'Active'),
            Tab(icon: Icon(Icons.trending_up), text: 'Usage'),
            Tab(icon: Icon(Icons.compare_arrows), text: 'Compare'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,        children: [
          _buildActiveBenefitsTab(benefitsState),
          _buildUsageTab(benefitsState),
          _buildCompareTab(benefitsState.userCards),
        ],
      ),
    );
  }
  /// Build active benefits tab
  Widget _buildActiveBenefitsTab(BenefitsViewState state) {
    if (state.userCards.isEmpty) {
      return const EmptyState(
        title: 'No Cards Found',
        message: 'Add credit cards to view their benefits',
        icon: Icons.credit_card_off,
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary card
          _buildBenefitsSummaryCard(state.userCards),
          
          const SizedBox(height: 16),
          
          // Card selector
          _buildCardSelector(state.userCards),
          
          const SizedBox(height: 16),
          
          // Benefits list
          _buildBenefitsList(state.userCards),
        ],
      ),
    );
  }

  /// Build benefits summary card
  Widget _buildBenefitsSummaryCard(List<CreditCard> userCards) {    final totalBenefits = userCards.fold<int>(0, (sum, card) => sum + card.benefits.length);
    final activeBenefits = userCards.fold<int>(0, (sum, card) => 
      sum + card.benefits.where((b) => b.isActive).length);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(        gradient: LinearGradient(
          colors: [
            Theme.of(context).primaryColor,
            Theme.of(context).primaryColor.withValues(alpha: 0.8),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).primaryColor.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.card_giftcard,
                color: Colors.white,
                size: 28,
              ),
              const SizedBox(width: 12),
              Text(
                'Benefits Overview',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _buildSummaryItem(
                  'Total Benefits',
                  totalBenefits.toString(),
                  Icons.inventory,
                ),
              ),
              Expanded(
                child: _buildSummaryItem(
                  'Active Benefits',
                  activeBenefits.toString(),
                  Icons.check_circle,
                ),
              ),
              Expanded(
                child: _buildSummaryItem(
                  'Cards',
                  userCards.length.toString(),
                  Icons.credit_card,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Build summary item widget
  Widget _buildSummaryItem(String label, String value, IconData icon) {
    return Column(
      children: [        Icon(
          icon,
          color: Colors.white.withValues(alpha: 0.8),
          size: 24,
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.8),
            fontSize: 12,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
  /// Build card selector dropdown
  Widget _buildCardSelector(List<CreditCard> userCards) {
    final benefitsState = ref.watch(benefitsViewModelProvider);
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButton<String>(
        value: benefitsState.selectedCardId.isEmpty ? null : benefitsState.selectedCardId,
        hint: const Text('Select a card to view benefits'),
        isExpanded: true,
        underline: const SizedBox(),
        items: [
          const DropdownMenuItem<String>(
            value: '',
            child: Text('All Cards'),
          ),
          ...userCards.map((card) {
            return DropdownMenuItem<String>(
              value: card.id,
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 20,
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Center(
                      child: Text(
                        card.network.name.substring(0, 1).toUpperCase(),
                        style: TextStyle(
                          color: Theme.of(context).primaryColor,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          card.cardName,
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        Text(
                          card.bankName,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],        onChanged: (value) {
          ref.read(benefitsViewModelProvider.notifier).setSelectedCard(value ?? '');
        },
      ),
    );
  }
  /// Build benefits list
  Widget _buildBenefitsList(List<CreditCard> userCards) {
    final benefitsViewModel = ref.read(benefitsViewModelProvider.notifier);
    final selectedCards = benefitsViewModel.getSelectedCards();

    if (selectedCards.isEmpty) {
      return const EmptyState(
        title: 'No Benefits Found',
        message: 'Selected card has no benefits configured',
        icon: Icons.card_membership,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Benefits Details',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        ...selectedCards.map((card) => _buildCardBenefits(card)),
      ],
    );
  }
  /// Build benefits for a specific card
  Widget _buildCardBenefits(CreditCard card) {
    final benefitsViewModel = ref.read(benefitsViewModelProvider.notifier);
    final realBenefits = benefitsViewModel.getCardBenefits(card.id);
    
    if (realBenefits.isEmpty) {
      return Card(
        margin: const EdgeInsets.only(bottom: 16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Card header
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 24,
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Center(
                      child: Text(
                        card.network.name.substring(0, 1).toUpperCase(),
                        style: TextStyle(
                          color: Theme.of(context).primaryColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          card.cardName,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          card.bankName,
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 16),
              
              // No benefits message
              const Center(
                child: Text(
                  'No benefits configured for this card',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ],
          ),
        ),
      );
    }
    
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Card header
            Row(
              children: [
                Container(
                  width: 40,
                  height: 24,
                  decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Center(
                    child: Text(
                      card.network.name.substring(0, 1).toUpperCase(),
                      style: TextStyle(
                        color: Theme.of(context).primaryColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        card.cardName,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        card.bankName,
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Real benefits list
            ...realBenefits.map((benefit) => _buildRealBenefitItem(benefit)),
          ],
        ),
      ),
    );
  }

  /// Build real benefit item from CardBenefit
  Widget _buildRealBenefitItem(dynamic benefit) {
    // Handle both CardBenefit objects and Map<String, dynamic>
    final isActive = benefit is Map ? (benefit['isActive'] ?? true) : true;
    final category = benefit is Map ? (benefit['category'] ?? 'General') : 'General';
    final description = benefit is Map ? (benefit['description'] ?? 'No description') : 'No description';
    final value = benefit is Map ? (benefit['value'] ?? 'N/A') : 'N/A';
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isActive 
            ? Colors.green.withValues(alpha: 0.1) 
            : Colors.grey.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isActive 
              ? Colors.green.withValues(alpha: 0.2) 
              : Colors.grey.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isActive ? Icons.check_circle : Icons.pause_circle_outline,
            color: isActive ? Colors.green : Colors.grey,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        category,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: isActive ? Colors.green.shade700 : Colors.grey.shade700,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: isActive 
                            ? Colors.green.withValues(alpha: 0.2) 
                            : Colors.grey.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        value.toString(),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isActive ? Colors.green.shade800 : Colors.grey.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  /// Build usage tracking tab
  Widget _buildUsageTab(BenefitsViewState state) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Benefit Usage Tracking',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          
          // Month selector
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Select Period',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            ref.read(benefitsViewModelProvider.notifier).setSelectedPeriod('current_month');
                          },
                          child: const Text('This Month'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            ref.read(benefitsViewModelProvider.notifier).setSelectedPeriod('previous_month');
                          },
                          child: const Text('Previous Month'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          _buildUsageMetrics(state),
          const SizedBox(height: 16),
          _buildUsageHistory(state),
        ],
      ),
    );
  }

  /// Build benefits comparison tab
  Widget _buildCompareTab(List<CreditCard> userCards) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Benefits Comparison',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          _buildComparisonTable(userCards),
        ],
      ),
    );
  }
  /// Build usage metrics widget
  Widget _buildUsageMetrics(BenefitsViewState state) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This Month',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                ...state.metrics.map((metric) => Expanded(
                  child: _buildMetricItem(
                    metric.label, 
                    metric.value, 
                    _getIconFromString(metric.icon), 
                    _getColorFromString(metric.color),
                  ),
                )),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Build metric item
  Widget _buildMetricItem(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
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
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }
  /// Build usage history widget
  Widget _buildUsageHistory(BenefitsViewState state) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Recent Usage',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            if (state.recentUsage.isEmpty)
              const Text('No recent benefit usage found')
            else
              ...state.recentUsage.map((usage) => _buildUsageItem(
                usage.benefitName,
                '₹${usage.amountSaved.toStringAsFixed(0)} saved',
                _formatDate(usage.usageDate),
                Colors.green,
              )),
          ],
        ),
      ),
    );
  }

  /// Build usage item
  Widget _buildUsageItem(String benefit, String saving, String date, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  benefit,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                Text(
                  saving,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Text(
            date,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
  /// Build comparison table
  Widget _buildComparisonTable(List<CreditCard> userCards) {
    if (userCards.isEmpty) {
      return const EmptyState(
        title: 'No Cards to Compare',
        message: 'Add multiple cards to compare their benefits',
        icon: Icons.compare_arrows,
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Feature Comparison',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: [
                  const DataColumn(label: Text('Feature')),
                  ...userCards.take(3).map((card) => DataColumn(
                    label: Text(
                      card.cardName,
                      style: const TextStyle(fontSize: 12),
                    ),
                  )),
                ],
                rows: _buildComparisonRows(userCards),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build comparison rows based on actual user cards
  List<DataRow> _buildComparisonRows(List<CreditCard> userCards) {
    // TODO: Implement real comparison logic using userCards and actual benefit data
    return [];
  }


  /// Helper method to get icon from string
  IconData _getIconFromString(String iconName) {
    switch (iconName) {
      case 'check_circle':
        return Icons.check_circle;
      case 'savings':
        return Icons.savings;
      case 'card_giftcard':
        return Icons.card_giftcard;
      case 'warning':
        return Icons.warning;
      default:
        return Icons.info;
    }
  }

  /// Helper method to get color from string
  Color _getColorFromString(String colorName) {
    switch (colorName) {
      case 'green':
        return Colors.green;
      case 'blue':
        return Colors.blue;
      case 'orange':
        return Colors.orange;
      case 'red':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  /// Helper method to format date
  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date).inDays;
    
    if (difference == 0) {
      return 'Today';
    } else if (difference == 1) {
      return 'Yesterday';
    } else {
      return '$difference days ago';
    }
  }
}
