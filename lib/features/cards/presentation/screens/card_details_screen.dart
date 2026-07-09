import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cardcompass/core/theme.dart';
import 'package:cardcompass/core/mock/mock_data.dart';
import 'package:cardcompass/core/providers/service_providers.dart';
import 'package:cardcompass/shared/models/credit_card.dart';
import 'package:cardcompass/shared/models/transaction.dart';
import 'package:cardcompass/shared/widgets/credit_card_widget.dart';
import 'package:cardcompass/shared/widgets/state_widgets.dart';
import 'package:cardcompass/features/auth/providers/auth_provider.dart';
import 'package:cardcompass/features/cards/providers/cards_provider.dart';
import 'package:cardcompass/features/transactions/providers/transactions_provider.dart';
import 'package:cardcompass/features/cards/presentation/screens/add_card_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  Map<String, dynamic>? _latestStatement;
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
      var cards = ref.read(cardsProvider);
      if (cards.isEmpty) {
        final authState = ref.read(authStateProvider);
        if (authState.user != null) {
          await ref.read(cardsProvider.notifier).loadUserCards(authState.user!.id);
          await ref.read(transactionsProvider.notifier).loadUserTransactions(authState.user!.id);
        }
        cards = ref.read(cardsProvider);
      }

      if (cards.isEmpty) {
        _card = null;
        _transactions = [];
        return;
      }

      final matches = cards.where((card) => card.id == widget.cardId);
      _card = matches.isEmpty ? cards.first : matches.first;

      final transactions = ref.read(transactionsProvider);
      _transactions = transactions
          .where((t) => t.userCardId == _card!.id)
          .toList();

      // Load latest statement for this card
      await _fetchLatestStatement();

      // Load benefits data (mock in guest mode, Supabase otherwise)
      await _fetchCardBenefits();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load card details: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Card Details')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_card == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Card Details')),
        body: Center(
          child: Text(
            'This card could not be found.',
            style: AppTextStyles.body1,
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_card!.cardName),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (context) => const AddCardScreen()),
            ),
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
                  'Outstanding Amount',
                  _latestStatement != null 
                      ? '₹${(_latestStatement!['outstanding_amount'] ?? 0).toStringAsFixed(0)}'
                      : '₹0',
                  Icons.account_balance_wallet,
                  Colors.red,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildStatCard(
                  'Available Limit',
                  _latestStatement != null && _card!.creditLimit != null
                      ? '₹${((_card!.creditLimit! - (_latestStatement!['outstanding_amount'] ?? 0))).toStringAsFixed(0)}'
                      : '₹${(_card!.creditLimit ?? 100000).toStringAsFixed(0)}',
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
                  'Due Date',
                  _latestStatement != null 
                      ? _formatDate(_latestStatement!['due_date']?.toString() ?? '')
                      : 'N/A',
                  Icons.schedule,
                  Colors.orange,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildStatCard(
                  'Minimum Due',
                  _latestStatement != null 
                      ? '₹${(_latestStatement!['minimum_amount_due'] ?? 0).toStringAsFixed(0)}'
                      : '₹0',
                  Icons.payment,
                  Colors.purple,
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
                  _latestStatement != null && _card!.creditLimit != null
                      ? '${(((_latestStatement!['outstanding_amount'] ?? 0) / _card!.creditLimit!) * 100).toStringAsFixed(1)}%'
                      : '0%',
                  Icons.pie_chart,
                  Colors.teal,
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
                  if (_latestStatement != null) ...[
                    const Divider(),
                    Text(
                      'Statement Information',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildDetailRow('Statement Date', _formatDate(_latestStatement!['statement_date']?.toString() ?? '')),
                    _buildDetailRow('Due Date', _formatDate(_latestStatement!['due_date']?.toString() ?? '')),
                    _buildDetailRow('Outstanding Amount', '₹${(_latestStatement!['outstanding_amount'] ?? 0).toStringAsFixed(2)}'),
                    _buildDetailRow('Minimum Due', '₹${(_latestStatement!['minimum_amount_due'] ?? 0).toStringAsFixed(2)}'),
                    _buildDetailRow('Previous Balance', '₹${(_latestStatement!['previous_balance'] ?? 0).toStringAsFixed(2)}'),
                  ],
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
    if (_benefits.isEmpty) {
      return const EmptyState(
        title: 'No Benefits',
        message: 'No benefits configured for this card',
        icon: Icons.star_border,
      );
    }

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
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (context) => const AddCardScreen()),
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

  /// Fetch the latest statement for this card — mock data in guest mode,
  /// Supabase otherwise.
  Future<void> _fetchLatestStatement() async {
    final isGuest = ref.read(isGuestModeProvider);
    if (isGuest) {
      final statements = MockData.statements().where((s) => s.userCardId == _card!.id).toList()
        ..sort((a, b) => b.statementDate.compareTo(a.statementDate));
      if (statements.isNotEmpty) {
        final latest = statements.first;
        _latestStatement = {
          'outstanding_amount': latest.totalAmount,
          'due_date': latest.dueDate.toIso8601String(),
          'minimum_amount_due': latest.minimumPayment,
          'statement_date': latest.statementDate.toIso8601String(),
          'previous_balance': latest.closingBalance,
        };
      }
      return;
    }

    try {
      final response = await Supabase.instance.client
          .from('statements')
          .select('*')
          .eq('user_card_id', widget.cardId)
          .order('statement_date', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response != null) {
        _latestStatement = response;
      }
    } catch (e) {
      print('Error fetching latest statement: $e');
    }
  }

  /// Fetch card benefits — mock data in guest mode, Supabase otherwise.
  Future<void> _fetchCardBenefits() async {
    final isGuest = ref.read(isGuestModeProvider);
    if (isGuest) {
      final mockBenefits = MockData.cardBenefits(_card!.id);
      _benefits = mockBenefits.map((benefit) => {
        'category': benefit['category'] ?? 'General',
        'reward_rate': benefit['name']?.toString() ?? 'N/A',
        'description': benefit['description'] ?? 'No description',
        'icon': _getIconFromCategory(benefit['category'] ?? 'General'),
      }).toList();
      return;
    }

    try {
      final response = await Supabase.instance.client
          .from('card_benefits')
          .select('*')
          .eq('card_id', widget.cardId);

      if (response.isNotEmpty) {
        _benefits = response.map((benefit) => {
          'category': benefit['category'] ?? 'General',
          'reward_rate': benefit['value']?.toString() ?? 'N/A',
          'description': benefit['description'] ?? 'No description',
          'icon': _getIconFromCategory(benefit['category'] ?? 'General'),
        }).toList();
      } else {
        _benefits = []; // No benefits found
      }
    } catch (e) {
      print('Error fetching card benefits: $e');
      _benefits = []; // Fallback to empty list
    }
  }

  /// Get icon based on category
  IconData _getIconFromCategory(String category) {
    switch (category.toLowerCase()) {
      case 'dining':
      case 'restaurants':
        return Icons.restaurant;
      case 'online shopping':
      case 'shopping':
        return Icons.shopping_cart;
      case 'groceries':
        return Icons.local_grocery_store;
      case 'fuel':
      case 'gas':
        return Icons.local_gas_station;
      case 'travel':
        return Icons.flight;
      case 'entertainment':
        return Icons.movie;
      default:
        return Icons.star;
    }
  }
}
