import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../../transactions/providers/transactions_provider.dart';
import '../../../../shared/models/transaction.dart';

class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  TransactionCategory? _categoryFilter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  void _load() {
    final user = ref.read(authStateProvider).user;
    if (user == null) return;
    ref.read(transactionsProvider.notifier).loadUserTransactions(user.id);
  }

  @override
  Widget build(BuildContext context) {
    final allTransactions = ref.watch(transactionsProvider);
    final transactions = _categoryFilter == null
        ? allTransactions
        : allTransactions.where((t) => t.category == _categoryFilter).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF050B18),
      appBar: AppBar(
        title: Text(
          'TRANSACTIONS',
          style: GoogleFonts.spaceGrotesk(
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
            fontSize: 18,
          ),
        ),
        actions: [
          IconButton(
            onPressed: () => _showFilterSheet(context),
            icon: Icon(
              _categoryFilter == null ? Icons.filter_list : Icons.filter_alt,
              color: AppTheme.primaryColor,
            ),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: allTransactions.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.receipt_long_outlined, size: 64, color: Colors.white24),
                        const SizedBox(height: 16),
                        Text(
                          'No transactions yet',
                          style: GoogleFonts.spaceGrotesk(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Transactions from your statements will show up here.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.plusJakartaSans(
                            color: Colors.white38,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () async => _load(),
                  color: AppTheme.primaryColor,
                  backgroundColor: const Color(0xFF0C152B),
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                    itemCount: transactions.length,
                    itemBuilder: (context, index) {
                      final t = transactions[index];
                      final isCredit = t.type == TransactionType.credit || t.type == TransactionType.refund;
                      final categoryColor = _getCategoryColor(t.categoryString);
                      
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0C152B),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.06),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            // category icon in neon ring
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: categoryColor.withValues(alpha: 0.12),
                                shape: BoxShape.circle,
                                border: Border.all(color: categoryColor.withValues(alpha: 0.3), width: 1),
                              ),
                              child: Icon(
                                _categoryIcon(t.category),
                                color: categoryColor,
                                size: 16,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    t.merchantName ?? t.description,
                                    style: GoogleFonts.plusJakartaSans(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${_formatDate(t.transactionDate)} · ${t.categoryString.toUpperCase()}',
                                    style: GoogleFonts.spaceGrotesk(
                                      color: Colors.white38,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '${isCredit ? '+' : '-'}₹${t.amount.toStringAsFixed(0)}',
                                  style: GoogleFonts.spaceGrotesk(
                                    color: isCredit ? AppTheme.successColor : Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                                if (t.rewardEarned != null && t.rewardEarned! > 0) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    '+₹${t.rewardEarned!.toStringAsFixed(0)}',
                                    style: GoogleFonts.spaceGrotesk(
                                      color: AppTheme.rewardGold,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
        ),
      ),
    );
  }

  void _showFilterSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0C152B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    'FILTER BY CATEGORY',
                    style: GoogleFonts.spaceGrotesk(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
                const Divider(color: Color(0xFF1E293B)),
                ListTile(
                  title: Text(
                    'ALL CATEGORIES',
                    style: GoogleFonts.spaceGrotesk(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  trailing: _categoryFilter == null ? const Icon(Icons.check, color: AppTheme.primaryColor) : null,
                  onTap: () {
                    setState(() => _categoryFilter = null);
                    Navigator.pop(context);
                  },
                ),
                ...TransactionCategory.values.map((category) {
                  return ListTile(
                    title: Text(
                      category.name.toUpperCase(),
                      style: GoogleFonts.spaceGrotesk(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    trailing: _categoryFilter == category ? const Icon(Icons.check, color: AppTheme.primaryColor) : null,
                    onTap: () {
                      setState(() => _categoryFilter = category);
                      Navigator.pop(context);
                    },
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  IconData _categoryIcon(TransactionCategory category) {
    switch (category) {
      case TransactionCategory.food:
        return Icons.restaurant;
      case TransactionCategory.fuel:
        return Icons.local_gas_station;
      case TransactionCategory.grocery:
        return Icons.shopping_basket;
      case TransactionCategory.entertainment:
        return Icons.movie;
      case TransactionCategory.travel:
        return Icons.flight;
      case TransactionCategory.shopping:
        return Icons.shopping_bag;
      default:
        return Icons.payment;
    }
  }

  Color _getCategoryColor(String? category) {
    switch (category?.toLowerCase()) {
      case 'food':
        return Colors.orange;
      case 'shopping':
        return AppTheme.primaryColor;
      case 'fuel':
        return AppTheme.errorColor;
      case 'entertainment':
        return Colors.purpleAccent;
      case 'travel':
        return Colors.green;
      case 'grocery':
      case 'groceries':
        return Colors.tealAccent;
      default:
        return Colors.grey;
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date).inDays;

    if (difference == 0) {
      return 'Today';
    } else if (difference == 1) {
      return 'Yesterday';
    } else if (difference < 7) {
      return '$difference days ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }
}
