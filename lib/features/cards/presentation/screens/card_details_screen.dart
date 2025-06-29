import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cardcompass/shared/models/credit_card.dart';
import 'package:cardcompass/shared/models/transaction.dart';
import 'package:cardcompass/shared/widgets/credit_card_widget.dart';
import 'package:cardcompass/shared/widgets/state_widgets.dart';
import 'package:cardcompass/features/cards/providers/cards_provider.dart';
import 'package:cardcompass/features/transactions/providers/transactions_provider.dart';

/// Screen for displaying detailed information about a specific credit card
class CardDetailsScreen extends ConsumerStatefulWidget {
  final String cardId;

  const CardDetailsScreen({
    super.key,
    required this.cardId,
  });

  @override
  ConsumerState<CardDetailsScreen> createState() => _CardDetailsScreenState();
}

class _CardDetailsScreenState extends ConsumerState<CardDetailsScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  CreditCard? _card;
  List<Transaction> _transactions = [];
  List<Map<String, dynamic>> _benefits = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadCardDetails();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
  Future<void> _loadCardDetails() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Load card details
      final cards = ref.read(cardsProvider);
      _card = cards.firstWhere(
        (card) => card.id == widget.cardId,
        orElse: () => cards.first, // Fallback to first card if not found
      );      // Load transactions for this card
      final transactions = ref.read(transactionsProvider);
      _transactions = transactions
          .where((t) => t.userCardId == widget.cardId)
          .toList();

      // Mock benefits data
      _benefits = [
        {
          'category': 'Dining',
          'reward_rate': '5%',
          'description': 'Earn 5% cashback on dining expenses',
          'icon': Icons.restaurant,
        },
        {
          'category': 'Online Shopping',
          'reward_rate': '3%',
          'description': 'Get 3% rewards on online purchases',
          'icon': Icons.shopping_cart,
        },
        {
          'category': 'Groceries',
          'reward_rate': '2%',
          'description': '2% cashback on grocery shopping',
          'icon': Icons.local_grocery_store,
        },
        {
          'category': 'Fuel',
          'reward_rate': '1%',
          'description': 'Earn 1% on fuel purchases',
          'icon': Icons.local_gas_station,
        },
      ];
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load card details: $e')),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _card == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Card Details'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_card!.cardName),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () {
              // TODO: Navigate to edit card screen
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Edit card coming soon')),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () => _showCardOptions(),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.info), text: 'Overview'),
            Tab(icon: Icon(Icons.list), text: 'Transactions'),
            Tab(icon: Icon(Icons.star), text: 'Benefits'),
            Tab(icon: Icon(Icons.analytics), text: 'Analytics'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildOverviewTab(),
          _buildTransactionsTab(),
          _buildBenefitsTab(),
          _buildAnalyticsTab(),
        ],
      ),
    );
  }

  Widget _buildOverviewTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [          // Card Display
          CreditCardWidget(
            cardName: _card!.cardName,
            bankName: _card!.bankName,
            lastFourDigits: _card!.cardNumber ?? '****',
            expiryDate: _card!.expiryDate?.toString().substring(0, 7) ?? 'MM/YY',
            cardType: _card!.type.name,
            gradientColors: [_card!.networkColor, _card!.networkColor.withValues(alpha: 0.7)],
          ),
          const SizedBox(height: 24),          // Quick Stats
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  'Current Balance',
                  '₹25,000', // Mock data - no currentBalance in model
                  Icons.account_balance_wallet,
                  Colors.red,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildStatCard(
                  'Available Limit',
                  '₹${((_card!.creditLimit ?? 100000) - 25000).toStringAsFixed(0)}',
                  Icons.trending_up,
                  Colors.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  'Credit Limit',
                  '₹${(_card!.creditLimit ?? 100000).toStringAsFixed(0)}',
                  Icons.credit_card,
                  Colors.blue,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildStatCard(
                  'Utilization',
                  '${((25000 / (_card!.creditLimit ?? 100000)) * 100).toStringAsFixed(1)}%',
                  Icons.pie_chart,
                  Colors.orange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Card Details
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Card Information',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 16),                  _buildDetailRow('Bank', _card!.bankName),
                  _buildDetailRow('Card Type', _card!.type.name),
                  _buildDetailRow('Network', _card!.network.name),
                  _buildDetailRow('Annual Fee', '₹${_card!.annualFee ?? 0}'),
                  _buildDetailRow('Issued Date', _formatDate(_card!.issuedDate.toString())),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionsTab() {
    if (_transactions.isEmpty) {
      return const EmptyState(
        title: 'No Transactions',
        message: 'No transactions found for this card',
        icon: Icons.receipt_long,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _transactions.length,
      itemBuilder: (context, index) {
        final transaction = _transactions[index];        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: _getCategoryColor(transaction.category),
              child: Icon(
                _getCategoryIcon(transaction.category),
                color: Colors.white,
              ),
            ),
            title: Text(transaction.description),
            subtitle: Text(
              '${transaction.categoryString} • ${_formatDate(transaction.transactionDate.toString())}',
            ),
            trailing: Text(
              '₹${transaction.amount.toStringAsFixed(2)}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: transaction.amount > 0 ? Colors.red : Colors.green,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBenefitsTab() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _benefits.length,
      itemBuilder: (context, index) {
        final benefit = _benefits[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).primaryColor,
              child: Icon(
                benefit['icon'],
                color: Colors.white,
              ),
            ),
            title: Text(benefit['category']),
            subtitle: Text(benefit['description']),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                benefit['reward_rate'],
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAnalyticsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Spending Analytics',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),

          // Monthly spending
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'This Month',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '₹${_calculateMonthlySpending().toStringAsFixed(0)}',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: Theme.of(context).primaryColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Category breakdown
          Text(
            'Spending by Category',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          ..._buildCategoryBreakdown(),

          const SizedBox(height: 24),

          // Usage tips
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Optimization Tips',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  _buildTip('Use this card for dining to maximize 5% cashback'),
                  _buildTip('Consider paying down balance to improve utilization ratio'),
                  _buildTip('Set up auto-pay to avoid late fees'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
  List<Widget> _buildCategoryBreakdown() {
    final categoryTotals = <String, double>{};
    for (final transaction in _transactions) {
      final category = transaction.categoryString;
      final amount = transaction.amount;
      categoryTotals[category] = (categoryTotals[category] ?? 0) + amount;
    }

    return categoryTotals.entries.map((entry) {
      return Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          leading: Icon(
            _getCategoryIcon(entry.key),
            color: _getCategoryColor(entry.key),
          ),
          title: Text(entry.key),
          trailing: Text(
            '₹${entry.value.toStringAsFixed(0)}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      );
    }).toList();
  }

  Widget _buildTip(String tip) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lightbulb, size: 16, color: Colors.amber),
          const SizedBox(width: 8),
          Expanded(child: Text(tip)),
        ],
      ),
    );
  }  Color _getCategoryColor(dynamic category) {
    final categoryStr = category is TransactionCategory ? category.name : category?.toString().toLowerCase();
    switch (categoryStr) {
      case 'food':
      case 'dining':
        return Colors.orange;
      case 'shopping':
        return Colors.purple;
      case 'grocery':
      case 'groceries':
        return Colors.green;
      case 'fuel':
        return Colors.red;
      case 'entertainment':
        return Colors.pink;
      case 'travel':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  IconData _getCategoryIcon(dynamic category) {
    final categoryStr = category is TransactionCategory ? category.name : category?.toString().toLowerCase();
    switch (categoryStr) {
      case 'food':
      case 'dining':
        return Icons.restaurant;
      case 'shopping':
        return Icons.shopping_cart;
      case 'grocery':
      case 'groceries':
        return Icons.local_grocery_store;
      case 'fuel':
        return Icons.local_gas_station;
      case 'entertainment':
        return Icons.movie;
      case 'travel':
        return Icons.flight;
      default:
        return Icons.category;
    }
  }
  double _calculateMonthlySpending() {
    final now = DateTime.now();
    final thisMonth = DateTime(now.year, now.month, 1);
    return _transactions
        .where((t) {
          return t.transactionDate.isAfter(thisMonth);
        })
        .map((t) => t.amount)
        .fold(0.0, (sum, amount) => sum + amount);
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return 'Unknown';
    try {
      final date = DateTime.parse(dateStr);
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return 'Unknown';
    }
  }

  void _showCardOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('Edit Card'),
                onTap: () {
                  Navigator.pop(context);
                  // TODO: Navigate to edit card
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Edit card coming soon')),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.block),
                title: const Text('Freeze Card'),
                onTap: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Card freeze coming soon')),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('Remove Card', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  _showDeleteConfirmation();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showDeleteConfirmation() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Remove Card'),
          content: const Text(
            'Are you sure you want to remove this card? This action cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context); // Go back to cards list
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Card removal coming soon')),
                );
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Remove'),
            ),
          ],
        );
      },
    );
  }
}
