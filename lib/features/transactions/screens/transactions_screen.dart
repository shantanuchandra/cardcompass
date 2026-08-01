import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/repository_providers.dart';
import '../../../core/providers/supabase_provider.dart';
import '../../../shared/models/transaction.dart';

final _transactionsProvider = FutureProvider<List<Transaction>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return [];
  return ref.read(transactionsRepositoryProvider).getTransactions(userId: user.id, limit: 100);
});

final _fmt = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

class TransactionsScreen extends ConsumerWidget {
  const TransactionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txnsAsync = ref.watch(_transactionsProvider);

    return Scaffold(
      backgroundColor: AppColors.surfaceVoid,
      appBar: AppBar(
        title: Text('Ledger',
            style: GoogleFonts.spaceGrotesk(fontSize: 20, fontWeight: FontWeight.w700)),
      ),
      body: txnsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.neonCyan)),
        error: (e, _) => Center(child: Text('Error: $e', style: GoogleFonts.inter(color: AppColors.error))),
        data: (txns) {
          if (txns.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.receipt_long_outlined, size: 56, color: AppColors.textMuted),
                  const SizedBox(height: AppSpacing.md),
                  Text('No transactions yet',
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  const SizedBox(height: AppSpacing.sm),
                  Text('Sync your Gmail to import\ncredit card statements.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(fontSize: 14, color: AppColors.textSecondary, height: 1.5)),
                ],
              ),
            );
          }
          return RefreshIndicator(
            color: AppColors.neonCyan,
            backgroundColor: AppColors.surface1,
            onRefresh: () => ref.refresh(_transactionsProvider.future),
            child: ListView.builder(
              padding: const EdgeInsets.all(AppSpacing.md),
              itemCount: txns.length,
              itemBuilder: (_, i) => _TxnRow(txn: txns[i]),
            ),
          );
        },
      ),
    );
  }
}

class _TxnRow extends StatelessWidget {
  final Transaction txn;
  const _TxnRow({required this.txn});

  @override
  Widget build(BuildContext context) {
    final isDebit = txn.isDebit;
    final amount = isDebit ? '-${_fmt.format(txn.amount)}' : '+${_fmt.format(txn.amount)}';
    final color = isDebit ? AppColors.textPrimary : AppColors.success;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs + 2),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.textMuted.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: _categoryColor(txn.category).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(_categoryIcon(txn.category), size: 18, color: _categoryColor(txn.category)),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(txn.merchantName ?? txn.description,
                    style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
                    overflow: TextOverflow.ellipsis),
                Text(DateFormat('d MMM · hh:mm a').format(txn.transactionDate.toLocal()),
                    style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted)),
              ],
            ),
          ),
          Text(amount,
              style: GoogleFonts.spaceGrotesk(fontSize: 14, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }

  static Color _categoryColor(String? cat) {
    switch (cat?.toLowerCase()) {
      case 'dining': return AppColors.warning;
      case 'travel': return const Color(0xFF38BDF8);
      case 'shopping': return AppColors.violet;
      case 'fuel': return const Color(0xFFF97316);
      case 'entertainment': return const Color(0xFFEC4899);
      case 'groceries': return AppColors.success;
      default: return AppColors.textSecondary;
    }
  }

  static IconData _categoryIcon(String? cat) {
    switch (cat?.toLowerCase()) {
      case 'dining': return Icons.restaurant_rounded;
      case 'travel': return Icons.flight_rounded;
      case 'shopping': return Icons.shopping_bag_rounded;
      case 'fuel': return Icons.local_gas_station_rounded;
      case 'entertainment': return Icons.theaters_rounded;
      case 'groceries': return Icons.local_grocery_store_rounded;
      default: return Icons.receipt_rounded;
    }
  }
}
