import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
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
      backgroundColor: const Color(0xFF050B18),
      appBar: AppBar(
        title: Text(
          _card!.cardName.toUpperCase(),
          style: GoogleFonts.spaceGrotesk(
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0,
            fontSize: 16,
          ),
        ),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit, color: AppTheme.primaryColor),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (context) => const AddCardScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.white70),
            onPressed: () => _showCardOptions(),
          ),
        ],
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
            Tab(icon: Icon(Icons.info_outline, size: 18), text: 'OVERVIEW'),
            Tab(icon: Icon(Icons.list_alt, size: 18), text: 'TXNS'),
            Tab(icon: Icon(Icons.bolt, size: 18), text: 'BENEFITS'),
            Tab(icon: Icon(Icons.analytics_outlined, size: 18), text: 'CHARTS'),
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
        title: 'No Benefits Configured',
        message: 'No benefits rules detected for this card variant',
        icon: Icons.star_border,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      itemCount: _benefits.length,
      itemBuilder: (context, index) {
        final benefit = _benefits[index];
        final rate = benefit['reward_rate']?.toString() ?? 'N/A';
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF0C152B),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.06),
              width: 1,
            ),
          ),
          child: ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.2), width: 1),
              ),
              child: Icon(
                benefit['icon'],
                color: AppTheme.primaryColor,
                size: 18,
              ),
            ),
            title: Text(
              benefit['category'].toString().toUpperCase(),
              style: GoogleFonts.spaceGrotesk(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
                letterSpacing: 0.5,
              ),
            ),
            subtitle: Text(
              benefit['description'],
              style: GoogleFonts.plusJakartaSans(
                color: Colors.white60,
                fontSize: 11,
              ),
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.successColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.successColor.withValues(alpha: 0.3), width: 1),
              ),
              child: Text(
                rate,
                style: GoogleFonts.spaceGrotesk(
                  color: AppTheme.successColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
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
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 80),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SPENDING ANALYTICS',
            style: GoogleFonts.spaceGrotesk(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 16),

          // Monthly spending card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF0C152B),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppTheme.primaryColor.withValues(alpha: 0.2),
                width: 1,
              ),
              boxShadow: AppTheme.neonGlow(color: AppTheme.primaryColor, opacity: 0.1, blurRadius: 10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CURRENT BILLING CYCLE',
                  style: GoogleFonts.spaceGrotesk(
                    color: Colors.white70,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '₹${_calculateMonthlySpending().toStringAsFixed(0)}',
                  style: GoogleFonts.spaceGrotesk(
                    color: AppTheme.primaryColor,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Category breakdown
          Text(
            'SPENDING BY CATEGORY',
            style: GoogleFonts.spaceGrotesk(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 12,
              letterSpacing: 1.0,
            ),
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0C152B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withValues(alpha: 0.25),
          width: 1.5,
        ),
        boxShadow: AppTheme.neonGlow(color: color, opacity: 0.12, blurRadius: 10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  style: GoogleFonts.spaceGrotesk(
                    color: Colors.white70,
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.spaceGrotesk(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
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
      final categoryColor = _getCategoryColor(entry.key);
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF0C152B),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.06),
            width: 1,
          ),
        ),
        child: ListTile(
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: categoryColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _getCategoryIcon(entry.key),
              color: categoryColor,
              size: 18,
            ),
          ),
          title: Text(
            entry.key.toUpperCase(),
            style: GoogleFonts.spaceGrotesk(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 12,
              letterSpacing: 0.5,
            ),
          ),
          trailing: Text(
            '₹${entry.value.toStringAsFixed(0)}',
            style: GoogleFonts.spaceGrotesk(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
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
              onPressed: () async {
                Navigator.pop(context);
                final authState = ref.read(authStateProvider);
                if (authState.user != null && _card != null) {
                  await ref.read(cardsProvider.notifier).removeUserCard(
                    userId: authState.user!.id,
                    cardId: _card!.id,
                  );
                }
                if (mounted) {
                  Navigator.pop(context); // Go back to cards list
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Card removed')),
                  );
                }
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
