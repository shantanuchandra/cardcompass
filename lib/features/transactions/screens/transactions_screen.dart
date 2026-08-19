import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/brand_components.dart';
import '../../../core/theme/brand_tokens.dart';
import '../providers/transactions_provider.dart';
import '../widgets/spend_trend_panel.dart';
import '../../../shared/models/transaction.dart';
import '../../../shared/models/user_card.dart';
import '../../feedback/contextual_feedback_button.dart';
import '../../feedback/feedback_models.dart';

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
final _fmtPoints = NumberFormat.decimalPattern('en_IN');

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
          'Transactions',
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
        loading: () => const BrandLoadingSkeleton(
          key: Key('transactions-loading'),
          semanticLabel: 'Loading transactions',
          minHeight: 280,
        ),
        error: (_, _) => BrandStateView(
          title: 'Could not load your transactions.',
          message: 'Check your connection and try again.',
          icon: Icons.cloud_off_rounded,
          actionLabel: 'Try again',
          onAction: () => ref.read(txnsNotifierProvider.notifier).refresh(),
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
  int _activeFilterCount(TxnFilter filter) =>
      (filter.from != null || filter.to != null ? 1 : 0) +
      (filter.cardId != null ? 1 : 0) +
      (filter.category != null ? 1 : 0);

  void _openFilters(BuildContext context, TxnsState state) {
    void onChanged(TxnFilter filter) {
      ref.read(txnsNotifierProvider.notifier).setFilter(filter);
      Navigator.of(context).pop();
    }

    final panel = _FilterPanel(state: state, onChanged: onChanged);
    if (MediaQuery.sizeOf(context).width < 600) {
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: BrandColors.paper,
        builder: (context) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: BrandSpacing.lg),
            child: panel,
          ),
        ),
      );
      return;
    }
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: BrandColors.paper,
        title: const Text('Filters'),
        content: SingleChildScrollView(child: panel),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final filtered = s.filtered;
    final ledgerItems = s.ledgerItems;
    final trend = s.spendTrend;

    return BrandContentFrame(
      mode: BrandContentMode.fullWidthData,
      child: RefreshIndicator(
        color: BrandColors.focusDark,
        backgroundColor: BrandColors.paper,
        onRefresh: () => ref.read(txnsNotifierProvider.notifier).refresh(),
        child: CustomScrollView(
          slivers: [
            // ── Summary ───────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  BrandSpacing.md,
                  BrandSpacing.sm,
                  BrandSpacing.md,
                  0,
                ),
                child: BrandSurface(
                  tone: BrandSurfaceTone.ledger,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final stack =
                          constraints.maxWidth < 600 ||
                          MediaQuery.textScalerOf(context).scale(14) >= 21;
                      final primary = BrandMetric(
                        label: 'Total spend',
                        value: _fmtCompact.format(s.totalSpend),
                        supportingText: '${filtered.length} transactions',
                      );
                      final support = _SupportingMetrics(
                        rewards: '${_fmtPoints.format(s.totalRewards)} pts',
                        topCategory: s.topCategory ?? '—',
                      );
                      return stack
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                primary,
                                const SizedBox(height: BrandSpacing.md),
                                support,
                              ],
                            )
                          : Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: primary),
                                const SizedBox(width: BrandSpacing.xl),
                                support,
                              ],
                            );
                    },
                  ),
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
                child: Wrap(
                  runSpacing: BrandSpacing.xs,
                  spacing: BrandSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _FilterPill(
                      controlKey: const Key('transactions-filters'),
                      label: 'Filters',
                      summary: _activeFilterCount(s.filter) == 0
                          ? 'All time'
                          : '${_activeFilterCount(s.filter)} active',
                      active: _activeFilterCount(s.filter) > 0,
                      onTap: () => _openFilters(context, s),
                      icon: Icons.tune_rounded,
                    ),
                    _GroupingPill(
                      controlKey: const Key('transactions-grouping'),
                      grouping: s.grouping,
                      onChanged: (g) => ref
                          .read(txnsNotifierProvider.notifier)
                          .setGrouping(g),
                    ),
                    _CountPill(count: filtered.length),
                  ],
                ),
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
                child: BrandStateView(
                  title: s.all.isEmpty
                      ? 'No transactions yet'
                      : 'No matches for these filters',
                  message: s.all.isEmpty
                      ? 'Refresh after your next statement sync to check again.'
                      : 'Clear the active filters to return to all transactions.',
                  icon: Icons.receipt_long_outlined,
                  actionLabel: s.all.isEmpty ? 'Check again' : 'Clear filters',
                  onAction: s.all.isEmpty
                      ? () => ref.read(txnsNotifierProvider.notifier).refresh()
                      : () => ref
                            .read(txnsNotifierProvider.notifier)
                            .setFilter(const TxnFilter()),
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
                      final item = ledgerItems[index];
                      if (item is TxnLedgerGroupHeader) {
                        return _GroupHeader(
                          label: item.label,
                          total: item.total,
                          cards: s.cards,
                        );
                      }
                      final txn = (item as TxnLedgerTransaction).transaction;
                      return _TxnRow(
                        key: ValueKey(txn.id),
                        txn: txn,
                        isInternational: s.isTransactionInternational(txn),
                        cardName: s.cards
                            .where((card) => card.id == txn.userCardId)
                            .firstOrNull
                            ?.displayName,
                      );
                    },
                    findChildIndexCallback: (key) => key is ValueKey<String>
                        ? s.ledgerIndexForTransactionId(key.value)
                        : null,
                    childCount: ledgerItems.length,
                  ),
                ),
              ),
          ],
        ),
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
    final now = state.reportingCutoff ?? DateTime.now();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: BrandSpacing.md),
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
              fontSize: 12,
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
                fontSize: 12,
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
                fontSize: 12,
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
  final double total;
  final List<UserCard> cards;
  const _GroupHeader({
    required this.label,
    required this.total,
    required this.cards,
  });

  @override
  Widget build(BuildContext context) {
    String displayLabel = label;
    // Resolve card ID to display name
    if (cards.any((c) => c.id == label)) {
      displayLabel = cards.firstWhere((c) => c.id == label).displayName;
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        0,
        BrandSpacing.md,
        0,
        BrandSpacing.xs,
      ),
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

class _TxnRow extends StatefulWidget {
  const _TxnRow({
    super.key,
    required this.txn,
    this.isInternational = false,
    this.cardName,
  });

  final Transaction txn;
  final bool isInternational;
  final String? cardName;

  @override
  State<_TxnRow> createState() => _TxnRowState();
}

class _TxnRowState extends State<_TxnRow> {
  bool _showDetails = false;

  @override
  Widget build(BuildContext context) {
    final txn = widget.txn;
    final amount = txn.isDebit
        ? '-${_fmt.format(txn.amount)}'
        : '+${_fmt.format(txn.amount)}';
    final amountColor = txn.isDebit ? BrandColors.ink : BrandColors.successInk;
    final hasDetails =
        widget.isInternational ||
        (txn.rewardEarned != null && txn.rewardEarned! > 0);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(BrandSpacing.md),
      decoration: BoxDecoration(
        color: BrandColors.paper,
        borderRadius: BorderRadius.circular(BrandRadius.card),
        border: Border.all(color: BrandColors.mutedInk.withValues(alpha: .07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final stackAmount =
                  constraints.maxWidth < 420 ||
                  MediaQuery.textScalerOf(context).scale(14) >= 21;
              final merchant = Text(
                txn.merchantName ?? txn.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: BrandColors.ink,
                ),
              );
              final amountText = Text(
                amount,
                style: TextStyle(
                  fontFamily: 'IBM Plex Mono',
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: amountColor,
                ),
              );
              return stackAmount
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        merchant,
                        const SizedBox(height: 2),
                        amountText,
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: merchant),
                        const SizedBox(width: BrandSpacing.sm),
                        amountText,
                      ],
                    );
            },
          ),
          const SizedBox(height: BrandSpacing.xs),
          Text(
            DateFormat('d MMM · h:mm a').format(txn.transactionDate.toLocal()),
            style: const TextStyle(
              fontFamily: 'Manrope',
              fontSize: 12,
              color: BrandColors.mutedInk,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            widget.cardName ?? 'Unlinked card',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'Manrope',
              fontSize: 12,
              color: BrandColors.mutedInk,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            txn.category ?? 'Other',
            style: const TextStyle(
              fontFamily: 'Manrope',
              fontSize: 12,
              color: BrandColors.mutedInk,
            ),
          ),
          if (hasDetails) ...[
            const SizedBox(height: BrandSpacing.xs),
            TextButton.icon(
              onPressed: () => setState(() => _showDetails = !_showDetails),
              icon: Icon(
                _showDetails
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
                size: 18,
              ),
              label: Text(_showDetails ? 'Hide details' : 'Details'),
            ),
          ],
          if (_showDetails) ...[
            if (widget.isInternational)
              const Text(
                'International transaction',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 12,
                  color: BrandColors.mutedInk,
                ),
              ),
            if (txn.rewardEarned != null && txn.rewardEarned! > 0)
              Text(
                '+${_fmtPoints.format(txn.rewardEarned)} pts',
                style: const TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 12,
                  color: BrandColors.successInk,
                ),
              ),
          ],
          ContextualFeedbackButton(
            target: TransactionFeedbackTarget(txn.id),
            preview:
                '${(txn.merchantName ?? txn.description).characters.take(80).toString()} · $amount',
          ),
        ],
      ),
    );
  }
}

class _SupportingMetrics extends StatelessWidget {
  const _SupportingMetrics({required this.rewards, required this.topCategory});

  final String rewards;
  final String topCategory;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: BrandSpacing.lg,
    runSpacing: BrandSpacing.sm,
    children: [
      _SupportingMetric(label: 'Rewards earned', value: rewards),
      _SupportingMetric(label: 'Top category', value: topCategory),
    ],
  );
}

class _SupportingMetric extends StatelessWidget {
  const _SupportingMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        label,
        style: const TextStyle(
          fontFamily: 'Manrope',
          fontSize: 12,
          color: BrandColors.mutedInk,
        ),
      ),
      const SizedBox(height: 2),
      Text(
        value,
        style: const TextStyle(
          fontFamily: 'IBM Plex Mono',
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: BrandColors.ink,
        ),
      ),
    ],
  );
}

class _CountPill extends StatelessWidget {
  const _CountPill({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => Text(
    '$count txns',
    style: const TextStyle(
      fontFamily: 'Manrope',
      fontSize: 12,
      color: BrandColors.mutedInk,
    ),
  );
}

// ── Shared pill/chip widgets ─────────────────────────────────────────────────

class _FilterPill extends StatelessWidget {
  final Key? controlKey;
  final String label;
  final String summary;
  final bool active;
  final VoidCallback onTap;
  final IconData icon;
  const _FilterPill({
    this.controlKey,
    required this.label,
    required this.summary,
    required this.active,
    required this.onTap,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.textScalerOf(context).scale(14) >= 21;
    return Semantics(
      key: controlKey,
      button: true,
      selected: active,
      label: '$label, $summary',
      onTap: onTap,
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              constraints: const BoxConstraints(minHeight: 44),
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
              child: compact
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _FilterPillLabel(
                          label: label,
                          icon: icon,
                          active: active,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          summary,
                          style: TextStyle(
                            fontFamily: 'Manrope',
                            fontSize: 14,
                            color: active
                                ? BrandColors.focusDark
                                : BrandColors.mutedInk,
                          ),
                        ),
                      ],
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _FilterPillLabel(
                          label: label,
                          icon: icon,
                          active: active,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          summary,
                          style: TextStyle(
                            fontFamily: 'Manrope',
                            fontSize: 14,
                            color: active
                                ? BrandColors.focusDark
                                : BrandColors.mutedInk,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterPillLabel extends StatelessWidget {
  const _FilterPillLabel({
    required this.label,
    required this.icon,
    required this.active,
  });

  final String label;
  final IconData icon;
  final bool active;

  @override
  Widget build(BuildContext context) => Row(
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
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: active ? BrandColors.focusDark : BrandColors.mutedInk,
        ),
      ),
    ],
  );
}

class _GroupingPill extends StatelessWidget {
  final Key? controlKey;
  final TxnGrouping grouping;
  final ValueChanged<TxnGrouping> onChanged;
  const _GroupingPill({
    this.controlKey,
    required this.grouping,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    const labels = {
      TxnGrouping.flat: 'Flat',
      TxnGrouping.byCard: 'Card',
      TxnGrouping.byCategory: 'Category',
      TxnGrouping.byDate: 'Date',
    };
    final label = labels[grouping]!;
    return Semantics(
      key: controlKey,
      label: 'Group transactions by $label',
      button: true,
      onTap: () {
        final values = TxnGrouping.values;
        final next = values[(values.indexOf(grouping) + 1) % values.length];
        onChanged(next);
      },
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              final values = TxnGrouping.values;
              final next =
                  values[(values.indexOf(grouping) + 1) % values.length];
              onChanged(next);
            },
            borderRadius: BorderRadius.circular(20),
            child: Container(
              constraints: const BoxConstraints(minHeight: 44),
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
                    label,
                    style: TextStyle(
                      fontFamily: 'Manrope',
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: BrandColors.mutedInk,
                    ),
                  ),
                ],
              ),
            ),
          ),
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
    return Semantics(
      key: Key('date-filter-$label'),
      label: label,
      button: true,
      selected: active,
      onTap: onTap,
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              constraints: const BoxConstraints(minHeight: 44),
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
                  fontSize: 14,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  color: active ? BrandColors.focusDark : BrandColors.mutedInk,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
