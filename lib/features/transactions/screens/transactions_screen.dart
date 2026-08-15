import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/brand_tokens.dart';
import '../../../core/theme/category_display.dart';
import '../providers/transactions_provider.dart';
import '../widgets/spend_trend_panel.dart';
import '../../../shared/models/transaction.dart';
import '../../../shared/models/user_card.dart';

final _fmt = NumberFormat.currency(
  locale: 'en_IN',
  symbol: '₹',
  decimalDigits: 0,
);
final _fmtCompact = NumberFormat.compactCurrency(
  locale: 'en_IN',
  symbol: '₹',
  decimalDigits: 0,
);

class TransactionsScreen extends ConsumerWidget {
  const TransactionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(txnsNotifierProvider);

    return Scaffold(
      backgroundColor: BrandColors.paper,
      appBar: AppBar(
        backgroundColor: BrandColors.paper,
        title: Text(
          'Ledger',
          style: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          async.whenOrNull(
                data: (s) => IconButton(
                  icon: const Icon(
                    Icons.refresh_rounded,
                    size: 20,
                    color: BrandColors.mutedInk,
                  ),
                  onPressed: () =>
                      ref.read(txnsNotifierProvider.notifier).refresh(),
                ),
              ) ??
              const SizedBox(),
        ],
      ),
      body: async.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: BrandColors.focusDark),
        ),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.cloud_off_rounded,
                size: 48,
                color: BrandColors.mutedInk,
              ),
              const SizedBox(height: BrandSpacing.md),
              Text(
                'Couldn\'t load ledger',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: BrandColors.ink,
                ),
              ),
              const SizedBox(height: BrandSpacing.xs),
              Text(
                '$e',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 12,
                  color: BrandColors.mutedInk,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: BrandSpacing.md),
              FilledButton.icon(
                onPressed: () =>
                    ref.read(txnsNotifierProvider.notifier).refresh(),
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Retry'),
                style: FilledButton.styleFrom(
                  backgroundColor: BrandColors.focusDark,
                  foregroundColor: BrandColors.paper,
                ),
              ),
            ],
          ),
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
      color: BrandColors.focusDark,
      backgroundColor: BrandColors.paper,
      onRefresh: () => ref.read(txnsNotifierProvider.notifier).refresh(),
      child: CustomScrollView(
        slivers: [
          // ── Summary KPI tiles ──────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                BrandSpacing.md,
                BrandSpacing.sm,
                BrandSpacing.md,
                0,
              ),
              child: Row(
                children: [
                  _KpiTile(
                    label: 'Spent',
                    value: _fmtCompact.format(s.totalSpend),
                    color: BrandColors.ink,
                  ),
                  const SizedBox(width: BrandSpacing.sm),
                  _KpiTile(
                    label: 'Rewards',
                    value: _fmtCompact.format(s.totalRewards),
                    color: BrandColors.successInk,
                  ),
                  const SizedBox(width: BrandSpacing.sm),
                  _KpiTile(
                    label: 'Top',
                    value: s.topCategory ?? '—',
                    color: BrandColors.reward,
                    capitalize: true,
                  ),
                ],
              ),
            ),
          ),

          // ── Filter bar ────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                BrandSpacing.md,
                BrandSpacing.sm,
                BrandSpacing.md,
                0,
              ),
              child: Row(
                children: [
                  _FilterPill(
                    label: s.filter.label,
                    active:
                        s.filter.from != null ||
                        s.filter.to != null ||
                        s.filter.category != null ||
                        s.filter.cardId != null,
                    onTap: () => setState(() => _showFilters = !_showFilters),
                    icon: Icons.tune_rounded,
                  ),
                  const SizedBox(width: BrandSpacing.xs),
                  _GroupingPill(
                    grouping: s.grouping,
                    onChanged: (g) =>
                        ref.read(txnsNotifierProvider.notifier).setGrouping(g),
                  ),
                  const Spacer(),
                  Text(
                    '${filtered.length} txns',
                    style: TextStyle(
                      fontFamily: 'Manrope',
                      fontSize: 11,
                      color: BrandColors.mutedInk,
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (_showFilters)
            SliverToBoxAdapter(
              child: _FilterPanel(
                state: s,
                onChanged: (f) =>
                    ref.read(txnsNotifierProvider.notifier).setFilter(f),
              ),
            ),

          // ── Spend trend chart ─────────────────────────────────────────
          if (trend.points.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  BrandSpacing.md,
                  BrandSpacing.sm,
                  BrandSpacing.md,
                  0,
                ),
                child: SpendTrendPanel(trend: trend, caption: s.filter.label),
              ),
            ),

          // ── Transaction list ──────────────────────────────────────────
          if (filtered.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.receipt_long_outlined,
                      size: 48,
                      color: BrandColors.mutedInk,
                    ),
                    const SizedBox(height: BrandSpacing.md),
                    Text(
                      'No transactions',
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: BrandColors.ink,
                      ),
                    ),
                    const SizedBox(height: BrandSpacing.xs),
                    Text(
                      'Try adjusting your filters',
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 13,
                        color: BrandColors.mutedInk,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                BrandSpacing.md,
                BrandSpacing.sm,
                BrandSpacing.md,
                BrandSpacing.lg,
              ),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final entries = grouped.entries.toList();
                    int cursor = 0;
                    for (final entry in entries) {
                      // Group header (only if not flat)
                      if (s.grouping != TxnGrouping.flat) {
                        if (index == cursor)
                          return _GroupHeader(
                            label: entry.key,
                            txns: entry.value,
                            cards: s.cards,
                          );
                        cursor++;
                      }
                      for (final txn in entry.value) {
                        if (index == cursor) {
                          return _TxnRow(
                            txn: txn,
                            isInternational: s.isTransactionInternational(txn),
                          );
                        }
                        cursor++;
                      }
                    }
                    return null;
                  },
                  childCount: s.grouping == TxnGrouping.flat
                      ? filtered.length
                      : grouped.entries.fold<int>(
                          0,
                          (sum, e) => sum + 1 + e.value.length,
                        ),
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
    final cats =
        state.all.map((t) => t.category).whereType<String>().toSet().toList()
          ..sort();
    final now = DateTime.now();

    return Container(
      margin: const EdgeInsets.fromLTRB(
        BrandSpacing.md,
        BrandSpacing.sm,
        BrandSpacing.md,
        0,
      ),
      padding: const EdgeInsets.all(BrandSpacing.md),
      decoration: BoxDecoration(
        color: BrandColors.paper,
        borderRadius: BorderRadius.circular(BrandRadius.card),
        border: Border.all(color: BrandColors.mutedInk.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Date presets
          Text(
            'Date range',
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 11,
              color: BrandColors.mutedInk,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: BrandSpacing.xs),
          Wrap(
            spacing: BrandSpacing.xs,
            children: [
              _DateChip(
                label: 'This month',
                active: _isThisMonth(state.filter, now),
                onTap: () => onChanged(
                  state.filter.copyWith(
                    from: DateTime(now.year, now.month, 1),
                    to: null,
                  ),
                ),
              ),
              _DateChip(
                label: 'Last month',
                active: _isLastMonth(state.filter, now),
                onTap: () => onChanged(
                  state.filter.copyWith(
                    from: DateTime(now.year, now.month - 1, 1),
                    to: DateTime(now.year, now.month, 0),
                  ),
                ),
              ),
              _DateChip(
                label: 'Last 3M',
                active: _isLast3M(state.filter, now),
                onTap: () => onChanged(
                  state.filter.copyWith(
                    from: now.subtract(const Duration(days: 90)),
                    to: null,
                  ),
                ),
              ),
              _DateChip(
                label: 'All time',
                active: state.filter.from == null && state.filter.to == null,
                onTap: () =>
                    onChanged(state.filter.copyWith(from: null, to: null)),
              ),
            ],
          ),
          // Card filter
          if (state.cards.length > 1) ...[
            const SizedBox(height: BrandSpacing.sm),
            Text(
              'Card',
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 11,
                color: BrandColors.mutedInk,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: BrandSpacing.xs),
            Wrap(
              spacing: BrandSpacing.xs,
              children: [
                _DateChip(
                  label: 'All cards',
                  active: state.filter.cardId == null,
                  onTap: () => onChanged(state.filter.copyWith(cardId: null)),
                ),
                ...state.cards.map(
                  (c) => _DateChip(
                    label: c.displayName,
                    active: state.filter.cardId == c.id,
                    onTap: () => onChanged(state.filter.copyWith(cardId: c.id)),
                  ),
                ),
              ],
            ),
          ],
          // Category filter
          if (cats.isNotEmpty) ...[
            const SizedBox(height: BrandSpacing.sm),
            Text(
              'Category',
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 11,
                color: BrandColors.mutedInk,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: BrandSpacing.xs),
            Wrap(
              spacing: BrandSpacing.xs,
              children: [
                _DateChip(
                  label: 'All',
                  active: state.filter.category == null,
                  onTap: () => onChanged(state.filter.copyWith(category: null)),
                ),
                ...cats.map(
                  (c) => _DateChip(
                    label: c[0].toUpperCase() + c.substring(1),
                    active: state.filter.category == c,
                    onTap: () => onChanged(state.filter.copyWith(category: c)),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  bool _isThisMonth(TxnFilter f, DateTime now) =>
      f.from?.year == now.year &&
      f.from?.month == now.month &&
      f.to == null &&
      f.from?.day == 1;
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
  const _GroupHeader({
    required this.label,
    required this.txns,
    required this.cards,
  });

  @override
  Widget build(BuildContext context) {
    final total = txns
        .where((t) => t.isDebit)
        .fold(0.0, (s, t) => s + t.amount);
    String displayLabel = label;
    // Resolve card ID to display name
    if (cards.any((c) => c.id == label)) {
      displayLabel = cards.firstWhere((c) => c.id == label).displayName;
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, BrandSpacing.md, 0, BrandSpacing.xs),
      child: Row(
        children: [
          Text(
            displayLabel,
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: BrandColors.mutedInk,
            ),
          ),
          const Spacer(),
          Text(
            _fmt.format(total),
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: BrandColors.mutedInk,
            ),
          ),
        ],
      ),
    );
  }
}

class _TxnRow extends StatelessWidget {
  final Transaction txn;
  final bool isInternational;
  const _TxnRow({required this.txn, this.isInternational = false});

  @override
  Widget build(BuildContext context) {
    final isDebit = txn.isDebit;
    final amountStr = isDebit
        ? '-${_fmt.format(txn.amount)}'
        : '+${_fmt.format(txn.amount)}';
    final amountColor = isDebit ? BrandColors.ink : BrandColors.successInk;
    final catColor = _categoryColor(txn.category);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(
        horizontal: BrandSpacing.md,
        vertical: 11,
      ),
      decoration: BoxDecoration(
        color: BrandColors.paper,
        borderRadius: BorderRadius.circular(BrandRadius.card),
        border: Border.all(color: BrandColors.mutedInk.withValues(alpha: 0.07)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: catColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(BrandRadius.control),
            ),
            child: Icon(_categoryIcon(txn.category), size: 17, color: catColor),
          ),
          const SizedBox(width: BrandSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        txn.merchantName ?? txn.description,
                        style: TextStyle(
                          fontFamily: 'Manrope',
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: BrandColors.ink,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isInternational)
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Icon(
                          Icons.public,
                          size: 12,
                          color: BrandColors.mutedInk,
                        ),
                      ),
                  ],
                ),
                Text(
                  DateFormat(
                    'd MMM · h:mm a',
                  ).format(txn.transactionDate.toLocal()),
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 11,
                    color: BrandColors.mutedInk,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                amountStr,
                style: TextStyle(
                  fontFamily: 'IBM Plex Mono',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: amountColor,
                ),
              ),
              if (txn.rewardEarned != null && txn.rewardEarned! > 0)
                Text(
                  '+${_fmt.format(txn.rewardEarned)} pts',
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 10,
                    color: BrandColors.successInk,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static Color _categoryColor(String? cat) => categoryColor(cat);

  static IconData _categoryIcon(String? cat) => categoryIcon(cat);
}

// ── Shared pill/chip widgets ─────────────────────────────────────────────────

class _KpiTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool capitalize;
  const _KpiTile({
    required this.label,
    required this.value,
    required this.color,
    this.capitalize = false,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: BrandSpacing.sm,
          vertical: BrandSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: BrandColors.ledger,
          borderRadius: BorderRadius.circular(BrandRadius.card),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 10,
                color: BrandColors.mutedInk,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              capitalize
                  ? (value.isNotEmpty
                        ? value[0].toUpperCase() + value.substring(1)
                        : value)
                  : value,
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: color,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  final IconData icon;
  const _FilterPill({
    required this.label,
    required this.active,
    required this.onTap,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? BrandColors.focusDark.withValues(alpha: 0.12)
              : BrandColors.paper,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active
                ? BrandColors.focusDark.withValues(alpha: 0.4)
                : BrandColors.mutedInk.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: active ? BrandColors.focusDark : BrandColors.mutedInk,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: active ? BrandColors.focusDark : BrandColors.mutedInk,
              ),
            ),
          ],
        ),
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
          color: BrandColors.paper,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: BrandColors.mutedInk.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.layers_rounded,
              size: 13,
              color: BrandColors.mutedInk,
            ),
            const SizedBox(width: 4),
            Text(
              labels[grouping]!,
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: BrandColors.mutedInk,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _DateChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: BrandSpacing.xs),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active
              ? BrandColors.focusDark.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: active
                ? BrandColors.focusDark.withValues(alpha: 0.5)
                : BrandColors.mutedInk.withValues(alpha: 0.2),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 11,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            color: active ? BrandColors.focusDark : BrandColors.mutedInk,
          ),
        ),
      ),
    );
  }
}
