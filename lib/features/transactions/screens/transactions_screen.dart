import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/transactions_provider.dart';
import '../widgets/spend_trend_panel.dart';
import '../../../shared/models/transaction.dart';
import '../../../shared/models/user_card.dart';

final _fmt = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
final _fmtCompact = NumberFormat.compactCurrency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

class TransactionsScreen extends ConsumerWidget {
  const TransactionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(txnsNotifierProvider);

    return Scaffold(
      backgroundColor: AppColors.surfaceVoid,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceVoid,
        title: Text('Ledger',
            style: GoogleFonts.spaceGrotesk(fontSize: 20, fontWeight: FontWeight.w700)),
        actions: [
          async.whenOrNull(data: (s) => IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 20, color: AppColors.textMuted),
            onPressed: () => ref.read(txnsNotifierProvider.notifier).refresh(),
          )) ?? const SizedBox(),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.neonCyan)),
        error: (e, _) => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off_rounded, size: 48, color: AppColors.textMuted),
            const SizedBox(height: AppSpacing.md),
            Text('Couldn\'t load ledger', style: GoogleFonts.spaceGrotesk(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(height: AppSpacing.xs),
            Text('$e', style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted), textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(
              onPressed: () => ref.read(txnsNotifierProvider.notifier).refresh(),
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Retry'),
              style: FilledButton.styleFrom(backgroundColor: AppColors.neonCyan, foregroundColor: AppColors.surfaceVoid),
            ),
          ]),
        ),
        data: (state) => _LedgerBody(state: state),
      ),
    );
  }
}

class _LedgerBody extends ConsumerStatefulWidget {
  final TxnsState state;
  const _LedgerBody({required this.state});

  @override
  ConsumerState<_LedgerBody> createState() => _LedgerBodyState();
}

class _LedgerBodyState extends ConsumerState<_LedgerBody> {
  bool _showFilters = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final filtered = s.filtered;
    final grouped = s.grouped;
    final trend = s.spendTrend;

    return RefreshIndicator(
      color: AppColors.neonCyan,
      backgroundColor: AppColors.surface1,
      onRefresh: () => ref.read(txnsNotifierProvider.notifier).refresh(),
      child: CustomScrollView(
        slivers: [
          // ── Summary KPI tiles ──────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
              child: Row(
                children: [
                  _KpiTile(label: 'Spent', value: _fmtCompact.format(s.totalSpend), color: AppColors.textPrimary),
                  const SizedBox(width: AppSpacing.sm),
                  _KpiTile(label: 'Rewards', value: _fmtCompact.format(s.totalRewards), color: AppColors.success),
                  const SizedBox(width: AppSpacing.sm),
                  _KpiTile(
                    label: 'Top',
                    value: s.topCategory ?? '—',
                    color: AppColors.violet,
                    capitalize: true,
                  ),
                ],
              ),
            ),
          ),

          // ── Filter bar ────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
              child: Row(
                children: [
                  _FilterPill(
                    label: s.filter.label,
                    active: s.filter.from != null || s.filter.to != null || s.filter.category != null || s.filter.cardId != null,
                    onTap: () => setState(() => _showFilters = !_showFilters),
                    icon: Icons.tune_rounded,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  _GroupingPill(
                    grouping: s.grouping,
                    onChanged: (g) => ref.read(txnsNotifierProvider.notifier).setGrouping(g),
                  ),
                  const Spacer(),
                  Text('${filtered.length} txns',
                      style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted)),
                ],
              ),
            ),
          ),

          if (_showFilters)
            SliverToBoxAdapter(
              child: _FilterPanel(
                state: s,
                onChanged: (f) => ref.read(txnsNotifierProvider.notifier).setFilter(f),
              ),
            ),

          // ── Spend trend chart ─────────────────────────────────────────
          if (trend.points.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
                child: SpendTrendPanel(trend: trend, caption: s.filter.label),
              ),
            ),

          // ── Transaction list ──────────────────────────────────────────
          if (filtered.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.receipt_long_outlined, size: 48, color: AppColors.textMuted),
                  const SizedBox(height: AppSpacing.md),
                  Text('No transactions', style: GoogleFonts.spaceGrotesk(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  const SizedBox(height: AppSpacing.xs),
                  Text('Try adjusting your filters', style: GoogleFonts.inter(fontSize: 13, color: AppColors.textMuted)),
                ]),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.lg),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final entries = grouped.entries.toList();
                    int cursor = 0;
                    for (final entry in entries) {
                      // Group header (only if not flat)
                      if (s.grouping != TxnGrouping.flat) {
                        if (index == cursor) return _GroupHeader(label: entry.key, txns: entry.value, cards: s.cards);
                        cursor++;
                      }
                      for (final txn in entry.value) {
                        if (index == cursor) return _TxnRow(txn: txn);
                        cursor++;
                      }
                    }
                    return null;
                  },
                  childCount: s.grouping == TxnGrouping.flat
                      ? filtered.length
                      : grouped.entries.fold<int>(0, (sum, e) => sum + 1 + e.value.length),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Filter panel ─────────────────────────────────────────────────────────────

class _FilterPanel extends StatelessWidget {
  final TxnsState state;
  final ValueChanged<TxnFilter> onChanged;
  const _FilterPanel({required this.state, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cats = state.all.map((t) => t.category).whereType<String>().toSet().toList()..sort();
    final now = DateTime.now();

    return Container(
      margin: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.textMuted.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Date presets
          Text('Date range', style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w500)),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            children: [
              _DateChip(label: 'This month', active: _isThisMonth(state.filter, now),
                onTap: () => onChanged(state.filter.copyWith(from: DateTime(now.year, now.month, 1), to: null))),
              _DateChip(label: 'Last month', active: _isLastMonth(state.filter, now),
                onTap: () => onChanged(state.filter.copyWith(from: DateTime(now.year, now.month - 1, 1), to: DateTime(now.year, now.month, 0)))),
              _DateChip(label: 'Last 3M', active: _isLast3M(state.filter, now),
                onTap: () => onChanged(state.filter.copyWith(from: now.subtract(const Duration(days: 90)), to: null))),
              _DateChip(label: 'All time', active: state.filter.from == null && state.filter.to == null,
                onTap: () => onChanged(state.filter.copyWith(from: null, to: null))),
            ],
          ),
          // Card filter
          if (state.cards.length > 1) ...[
            const SizedBox(height: AppSpacing.sm),
            Text('Card', style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w500)),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.xs,
              children: [
                _DateChip(label: 'All cards', active: state.filter.cardId == null,
                  onTap: () => onChanged(state.filter.copyWith(cardId: null))),
                ...state.cards.map((c) => _DateChip(
                  label: c.displayName,
                  active: state.filter.cardId == c.id,
                  onTap: () => onChanged(state.filter.copyWith(cardId: c.id)),
                )),
              ],
            ),
          ],
          // Category filter
          if (cats.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text('Category', style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w500)),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.xs,
              children: [
                _DateChip(label: 'All', active: state.filter.category == null,
                  onTap: () => onChanged(state.filter.copyWith(category: null))),
                ...cats.map((c) => _DateChip(
                  label: c[0].toUpperCase() + c.substring(1),
                  active: state.filter.category == c,
                  onTap: () => onChanged(state.filter.copyWith(category: c)),
                )),
              ],
            ),
          ],
        ],
      ),
    );
  }

  bool _isThisMonth(TxnFilter f, DateTime now) =>
      f.from?.year == now.year && f.from?.month == now.month && f.to == null && f.from?.day == 1;
  bool _isLastMonth(TxnFilter f, DateTime now) {
    final lm = DateTime(now.year, now.month - 1, 1);
    return f.from?.year == lm.year && f.from?.month == lm.month;
  }
  bool _isLast3M(TxnFilter f, DateTime now) {
    if (f.from == null) return false;
    final diff = now.difference(f.from!).inDays;
    return diff >= 88 && diff <= 92 && f.to == null;
  }
}

// ── Rows & sub-widgets ───────────────────────────────────────────────────────

class _GroupHeader extends StatelessWidget {
  final String label;
  final List<Transaction> txns;
  final List<UserCard> cards;
  const _GroupHeader({required this.label, required this.txns, required this.cards});

  @override
  Widget build(BuildContext context) {
    final total = txns.where((t) => t.isDebit).fold(0.0, (s, t) => s + t.amount);
    String displayLabel = label;
    // Resolve card ID to display name
    if (cards.any((c) => c.id == label)) {
      displayLabel = cards.firstWhere((c) => c.id == label).displayName;
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, AppSpacing.md, 0, AppSpacing.xs),
      child: Row(
        children: [
          Text(displayLabel,
              style: GoogleFonts.spaceGrotesk(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
          const Spacer(),
          Text(_fmt.format(total),
              style: GoogleFonts.spaceGrotesk(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
        ],
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
    final amountStr = isDebit ? '-${_fmt.format(txn.amount)}' : '+${_fmt.format(txn.amount)}';
    final amountColor = isDebit ? AppColors.textPrimary : AppColors.success;
    final catColor = _categoryColor(txn.category);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.textMuted.withValues(alpha: 0.07)),
      ),
      child: Row(
        children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              color: catColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(_categoryIcon(txn.category), size: 17, color: catColor),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                txn.merchantName ?? txn.description,
                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                DateFormat('d MMM · h:mm a').format(txn.transactionDate.toLocal()),
                style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted),
              ),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(amountStr,
                style: GoogleFonts.spaceGrotesk(fontSize: 13, fontWeight: FontWeight.w700, color: amountColor)),
            if (txn.rewardEarned != null && txn.rewardEarned! > 0)
              Text('+${_fmt.format(txn.rewardEarned)} pts',
                  style: GoogleFonts.inter(fontSize: 10, color: AppColors.success)),
          ]),
        ],
      ),
    );
  }

  static Color _categoryColor(String? cat) {
    switch (cat?.toLowerCase()) {
      case 'dining': case 'food': return AppColors.warning;
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
      case 'dining': case 'food': return Icons.restaurant_rounded;
      case 'travel': return Icons.flight_rounded;
      case 'shopping': return Icons.shopping_bag_rounded;
      case 'fuel': return Icons.local_gas_station_rounded;
      case 'entertainment': return Icons.theaters_rounded;
      case 'groceries': return Icons.local_grocery_store_rounded;
      default: return Icons.receipt_rounded;
    }
  }
}

// ── Shared pill/chip widgets ─────────────────────────────────────────────────

class _KpiTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool capitalize;
  const _KpiTile({required this.label, required this.value, required this.color, this.capitalize = false});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: GoogleFonts.inter(fontSize: 10, color: AppColors.textMuted)),
          const SizedBox(height: 2),
          Text(
            capitalize ? (value.isNotEmpty ? value[0].toUpperCase() + value.substring(1) : value) : value,
            style: GoogleFonts.spaceGrotesk(fontSize: 14, fontWeight: FontWeight.w700, color: color),
            overflow: TextOverflow.ellipsis,
          ),
        ]),
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  final IconData icon;
  const _FilterPill({required this.label, required this.active, required this.onTap, required this.icon});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? AppColors.neonCyan.withValues(alpha: 0.12) : AppColors.surface1,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: active ? AppColors.neonCyan.withValues(alpha: 0.4) : AppColors.textMuted.withValues(alpha: 0.2)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: active ? AppColors.neonCyan : AppColors.textMuted),
          const SizedBox(width: 4),
          Text(label, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500, color: active ? AppColors.neonCyan : AppColors.textSecondary)),
        ]),
      ),
    );
  }
}

class _GroupingPill extends StatelessWidget {
  final TxnGrouping grouping;
  final ValueChanged<TxnGrouping> onChanged;
  const _GroupingPill({required this.grouping, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const labels = {
      TxnGrouping.flat: 'Flat',
      TxnGrouping.byCard: 'Card',
      TxnGrouping.byCategory: 'Category',
      TxnGrouping.byDate: 'Date',
    };
    return GestureDetector(
      onTap: () {
        final values = TxnGrouping.values;
        final next = values[(values.indexOf(grouping) + 1) % values.length];
        onChanged(next);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.textMuted.withValues(alpha: 0.2)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.layers_rounded, size: 13, color: AppColors.textMuted),
          const SizedBox(width: 4),
          Text(labels[grouping]!, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
        ]),
      ),
    );
  }
}

class _DateChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _DateChip({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.xs),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active ? AppColors.neonCyan.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: active ? AppColors.neonCyan.withValues(alpha: 0.5) : AppColors.textMuted.withValues(alpha: 0.2)),
        ),
        child: Text(label,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              color: active ? AppColors.neonCyan : AppColors.textSecondary,
            )),
      ),
    );
  }
}
