import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
      appBar: AppBar(
        title: const Text('Transactions'),
        actions: [
          IconButton(
            onPressed: () => _showFilterSheet(context),
            icon: Icon(
              _categoryFilter == null ? Icons.filter_list : Icons.filter_alt,
            ),
          ),
        ],
      ),
      body: allTransactions.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.receipt_long, size: 64, color: Theme.of(context).colorScheme.outline),
                  const SizedBox(height: 16),
                  Text('No transactions yet', style: AppTextStyles.heading3),
                  const SizedBox(height: 8),
                  Text(
                    'Transactions from your cards will show up here',
                    style: AppTextStyles.body1.copyWith(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: () async => _load(),
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: transactions.length,
                itemBuilder: (context, index) {
                  final t = transactions[index];
                  final isCredit = t.type == TransactionType.credit || t.type == TransactionType.refund;
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                      child: Icon(_categoryIcon(t.category), color: Theme.of(context).colorScheme.primary),
                    ),
                    title: Text(t.merchantName ?? t.description),
                    subtitle: Text(
                      '${_formatDate(t.transactionDate)} · ${t.categoryString}',
                    ),
                    trailing: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${isCredit ? '+' : '-'}₹${t.amount.toStringAsFixed(0)}',
                          style: AppTextStyles.body1.copyWith(
                            color: isCredit ? AppTheme.successColor : null,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (t.rewardEarned != null && t.rewardEarned! > 0)
                          Text(
                            '+${t.rewardEarned!.toStringAsFixed(0)} pts',
                            style: AppTextStyles.caption.copyWith(color: AppTheme.accentColor),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
    );
  }

  void _showFilterSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('All categories'),
                trailing: _categoryFilter == null ? const Icon(Icons.check) : null,
                onTap: () {
                  setState(() => _categoryFilter = null);
                  Navigator.pop(context);
                },
              ),
              ...TransactionCategory.values.map((category) {
                return ListTile(
                  title: Text(category.name),
                  trailing: _categoryFilter == category ? const Icon(Icons.check) : null,
                  onTap: () {
                    setState(() => _categoryFilter = category);
                    Navigator.pop(context);
                  },
                );
              }),
            ],
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
      case TransactionCategory.utilities:
        return Icons.bolt;
      case TransactionCategory.insurance:
        return Icons.shield;
      case TransactionCategory.medical:
        return Icons.local_hospital;
      case TransactionCategory.education:
        return Icons.school;
      case TransactionCategory.investment:
        return Icons.trending_up;
      case TransactionCategory.transport:
        return Icons.directions_car;
      case TransactionCategory.rental:
        return Icons.home;
      case TransactionCategory.subscription:
        return Icons.subscriptions;
      case TransactionCategory.gift:
        return Icons.card_giftcard;
      case TransactionCategory.other:
        return Icons.receipt;
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return '$diff days ago';
    return '${date.day}/${date.month}/${date.year}';
  }
}
