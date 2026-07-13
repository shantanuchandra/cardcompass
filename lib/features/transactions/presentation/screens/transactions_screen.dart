import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme.dart';
import '../../../../shared/widgets/app_scaffold.dart';
import '../../../../shared/widgets/state_widgets.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../../../shared/models/transaction.dart';
import '../../../../shared/models/credit_card.dart';
import '../../viewmodels/transactions_viewmodel.dart';
import '../../../benefits/viewmodels/benefits_viewmodel.dart';

class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  TransactionGrouping _grouping = TransactionGrouping.flat;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  void _load() {
    final user = ref.read(authStateProvider).user;
    if (user == null) return;
    ref.read(transactionsViewModelProvider.notifier).loadTransactions(user.id);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(transactionsViewModelProvider);
    final notifier = ref.read(transactionsViewModelProvider.notifier);

    return CardCompassScaffold(
      title: 'Transactions',
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: state.transactions.isEmpty
              ? const EmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'No transactions yet',
                  message: 'Transactions from your statements will show up here.',
                )
              : RefreshIndicator(
                  onRefresh: () async => _load(),
                  color: AppTheme.primaryColor,
                  backgroundColor: const Color(0xFF0C152B),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      AppSpacing.sm + 4,
                      AppSpacing.md,
                      80,
                    ),
                    children: [
                      _buildFilterBar(state, notifier),
                      const SizedBox(height: AppSpacing.md),
                      _buildTileRow(state, notifier),
                      const SizedBox(height: AppSpacing.md),
                      if (state.filteredTransactions.isEmpty)
                        _buildNoResultsState(notifier)
                      else
                        ..._buildTransactionSections(state),
                    ],
                  ),
                ).animate().fadeIn(duration: 250.ms, curve: Curves.easeOut).slideY(
                    begin: 0.05,
                    end: 0,
                    duration: 250.ms,
                    curve: Curves.easeOut,
                  ),
        ),
      ),
    );
  }

  Widget _buildNoResultsState(TransactionsViewModelController notifier) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
      child: EmptyState(
        icon: Icons.filter_alt_off_outlined,
        title: 'No matching transactions',
        message: 'Try widening your filters.',
        buttonText: 'Clear filters',
        onButtonPressed: notifier.clearFilters,
      ),
    );
  }

  Widget _buildFilterBar(TransactionsViewState state, TransactionsViewModelController notifier) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCardFilterRow(state, notifier),
        const SizedBox(height: AppSpacing.sm),
        _buildDateRangeControl(state, notifier),
        const SizedBox(height: AppSpacing.sm),
        _buildCategoryFilterRow(state, notifier),
      ],
    );
  }

  Widget _buildCardFilterRow(TransactionsViewState state, TransactionsViewModelController notifier) {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _filterChip(
            label: 'All Cards',
            selected: state.selectedCardId.isEmpty,
            onTap: () => notifier.setSelectedCard(''),
          ),
          for (final card in state.userCards)
            Padding(
              padding: const EdgeInsets.only(left: AppSpacing.sm),
              child: _filterChip(
                label: '${card.cardName} •••${card.cardNumberLast4 ?? ''}',
                selected: state.selectedCardId == card.id,
                onTap: () => notifier.setSelectedCard(card.id),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCategoryFilterRow(TransactionsViewState state, TransactionsViewModelController notifier) {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _filterChip(
            label: 'All Categories',
            selected: state.selectedCategory == 'All',
            onTap: () => notifier.setSelectedCategory('All'),
          ),
          for (final category in TransactionCategory.values)
            Padding(
              padding: const EdgeInsets.only(left: AppSpacing.sm),
              child: _filterChip(
                label: category.name.toUpperCase(),
                selected: state.selectedCategory == category.name,
                onTap: () => notifier.setSelectedCategory(category.name),
              ),
            ),
        ],
      ),
    );
  }

  Widget _filterChip({required String label, required bool selected, required VoidCallback onTap}) {
    return ChoiceChip(
      label: Text(
        label,
        style: GoogleFonts.spaceGrotesk(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: selected ? Colors.black : Colors.white70,
        ),
      ),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: AppTheme.primaryColor,
      backgroundColor: const Color(0xFF0C152B),
      side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
    );
  }

  Widget _buildDateRangeControl(TransactionsViewState state, TransactionsViewModelController notifier) {
    final label = state.dateRange == null
        ? 'All Time'
        : '${_shortDate(state.dateRange!.start)} - ${_shortDate(state.dateRange!.end)}';

    return InkWell(
      onTap: () => _showDateRangeSheet(context, notifier),
      borderRadius: BorderRadius.circular(AppBorderRadius.md),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: const Color(0xFF0C152B),
          borderRadius: BorderRadius.circular(AppBorderRadius.md),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.calendar_today_outlined, color: AppTheme.primaryColor, size: 14),
            const SizedBox(width: AppSpacing.sm),
            Text(
              label,
              style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  String _shortDate(DateTime date) => '${date.day}/${date.month}/${date.year}';

  void _showDateRangeSheet(BuildContext context, TransactionsViewModelController notifier) {
    final now = DateTime.now();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0C152B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Text(
                  'FILTER BY DATE',
                  style: GoogleFonts.spaceGrotesk(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 1.0),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                title: Text('All Time', style: GoogleFonts.spaceGrotesk(color: Colors.white)),
                onTap: () {
                  notifier.setDateRange(null);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: Text('This Month', style: GoogleFonts.spaceGrotesk(color: Colors.white)),
                onTap: () {
                  notifier.setDateRange(DateRange(start: DateTime(now.year, now.month, 1), end: now));
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: Text('Last Month', style: GoogleFonts.spaceGrotesk(color: Colors.white)),
                onTap: () {
                  final lastMonth = DateTime(now.year, now.month - 1, 1);
                  final endOfLastMonth = DateTime(now.year, now.month, 1).subtract(const Duration(days: 1));
                  notifier.setDateRange(DateRange(start: lastMonth, end: endOfLastMonth));
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: Text('Last 3 Months', style: GoogleFonts.spaceGrotesk(color: Colors.white)),
                onTap: () {
                  notifier.setDateRange(DateRange(start: DateTime(now.year, now.month - 3, now.day), end: now));
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: Text('Custom Range', style: GoogleFonts.spaceGrotesk(color: Colors.white)),
                onTap: () async {
                  Navigator.pop(context);
                  final picked = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2020),
                    lastDate: now,
                  );
                  if (picked != null) {
                    notifier.setDateRange(DateRange(start: picked.start, end: picked.end));
                  }
                },
              ),
              const SizedBox(height: AppSpacing.md),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _buildTransactionSections(TransactionsViewState state) {
    final groups = state.groupedTransactions(_grouping);
    final cardsById = {for (final c in state.userCards) c.id: c};

    return [
      _buildGroupingToggle(),
      const SizedBox(height: AppSpacing.md),
      for (final group in groups) ...[
        if (_grouping != TransactionGrouping.flat) _buildGroupHeader(group, cardsById),
        for (final t in group.transactions) _buildTransactionRow(t, cardsById),
        const SizedBox(height: AppSpacing.sm),
      ],
    ];
  }

  Widget _buildGroupingToggle() {
    const options = {
      TransactionGrouping.flat: 'Flat',
      TransactionGrouping.byCard: 'By Card',
      TransactionGrouping.byCategory: 'By Category',
      TransactionGrouping.byDate: 'By Date',
    };

    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: options.entries.map((entry) {
          final selected = _grouping == entry.key;
          return Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: ChoiceChip(
              label: Text(entry.value, style: GoogleFonts.spaceGrotesk(fontSize: 11, fontWeight: FontWeight.w600, color: selected ? Colors.black : Colors.white70)),
              selected: selected,
              onSelected: (_) => setState(() => _grouping = entry.key),
              selectedColor: AppTheme.primaryColor,
              backgroundColor: const Color(0xFF0C152B),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildGroupHeader(TransactionGroup group, Map<String, CreditCard> cardsById) {
    String title = group.key;
    if (_grouping == TransactionGrouping.byCard) {
      title = cardsById[group.key]?.cardName ?? 'Unknown Card';
    } else if (_grouping == TransactionGrouping.byCategory) {
      title = group.key.toUpperCase();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: GoogleFonts.spaceGrotesk(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.5)),
          Text('₹${group.subtotal.toStringAsFixed(0)}', style: GoogleFonts.spaceGrotesk(color: AppTheme.primaryColor, fontWeight: FontWeight.bold, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildTransactionRow(Transaction t, Map<String, CreditCard> cardsById) {
    final isCredit = t.type == TransactionType.credit || t.type == TransactionType.refund;
    final categoryColor = _getCategoryColor(t.category);
    final card = cardsById[t.userCardId];

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm + 4),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: const Color(0xFF0C152B),
        borderRadius: BorderRadius.circular(AppBorderRadius.xl),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06), width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: categoryColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(color: categoryColor.withValues(alpha: 0.3), width: 1),
            ),
            child: Icon(_categoryIcon(t.category), color: categoryColor, size: 16),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.merchantName ?? t.description,
                  style: AppTextStyles.body2.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  children: [
                    Text(
                      '${_formatDate(t.transactionDate)} · ${t.categoryString.toUpperCase()}',
                      style: GoogleFonts.spaceGrotesk(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 0.5),
                    ),
                    if (card != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: card.networkColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(AppBorderRadius.sm),
                        ),
                        child: Text(
                          '${card.cardName} •${card.cardNumberLast4 ?? ''}',
                          style: GoogleFonts.spaceGrotesk(color: card.networkColor, fontSize: 9, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${isCredit ? '+' : '-'}₹${t.amount.toStringAsFixed(0)}',
                style: GoogleFonts.spaceGrotesk(color: isCredit ? AppTheme.successColor : Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
              ),
              if (t.rewardEarned != null && t.rewardEarned! > 0) ...[
                const SizedBox(height: 2),
                Text(
                  '+₹${t.rewardEarned!.toStringAsFixed(0)}',
                  style: GoogleFonts.spaceGrotesk(color: AppTheme.rewardGold, fontWeight: FontWeight.bold, fontSize: 11),
                ),
              ],
            ],
          ),
        ],
      ),
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

  Color _getCategoryColor(TransactionCategory category) {
    switch (category) {
      case TransactionCategory.food:
        return Colors.orange;
      case TransactionCategory.shopping:
        return AppTheme.primaryColor;
      case TransactionCategory.fuel:
        return AppTheme.errorColor;
      case TransactionCategory.entertainment:
        return Colors.purpleAccent;
      case TransactionCategory.travel:
        return Colors.green;
      case TransactionCategory.grocery:
        return Colors.tealAccent;
      default:
        return Colors.grey;
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date).inDays;
    if (difference == 0) return 'Today';
    if (difference == 1) return 'Yesterday';
    if (difference < 7) return '$difference days ago';
    return '${date.day}/${date.month}/${date.year}';
  }

  Widget _buildTileRow(TransactionsViewState state, TransactionsViewModelController notifier) {
    final summary = notifier.getTransactionSummary();
    final perCard = state.perCardSummary();
    final cardsToShow = state.selectedCardId.isEmpty
        ? state.userCards
        : state.userCards.where((c) => c.id == state.selectedCardId).toList();

    return SizedBox(
      height: 124,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _statTile('TOTAL SPEND', '₹${(summary['totalAmount'] as double).toStringAsFixed(0)}', Icons.account_balance_wallet_outlined, AppTheme.primaryColor),
          _statTile('REWARDS EARNED', '₹${_totalRewards(state).toStringAsFixed(0)}', Icons.stars_outlined, AppTheme.rewardGold),
          _statTile('TOP CATEGORY', '${summary['topCategory']}', Icons.pie_chart_outline, AppTheme.accentColor,
              subtitle: '₹${(summary['topCategoryAmount'] as double).toStringAsFixed(0)}'),
          for (final card in cardsToShow)
            _cardTile(card, perCard[card.id]),
          if (state.selectedCardId.isNotEmpty && cardsToShow.isNotEmpty)
            _cardBenefitsTile(cardsToShow.first.id),
        ],
      ),
    );
  }

  double _totalRewards(TransactionsViewState state) {
    return state.filteredTransactions.fold<double>(0, (sum, t) => sum + (t.rewardEarned ?? 0));
  }

  Widget _tileShell({
    required Color borderColor,
    required List<Widget> children,
    double width = 150,
  }) {
    return Container(
      width: width,
      margin: const EdgeInsets.only(right: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: const Color(0xFF0C152B),
        borderRadius: BorderRadius.circular(AppBorderRadius.xl),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: children,
      ),
    );
  }

  Widget _statTile(String label, String value, IconData icon, Color color, {String? subtitle}) {
    return _tileShell(
      borderColor: color.withValues(alpha: 0.25),
      width: 150,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(height: AppSpacing.sm),
        Text(value, style: GoogleFonts.spaceGrotesk(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16), overflow: TextOverflow.ellipsis),
        if (subtitle != null)
          Text(subtitle, style: GoogleFonts.spaceGrotesk(color: Colors.white54, fontSize: 11)),
        const SizedBox(height: 2),
        Text(label, style: GoogleFonts.spaceGrotesk(color: Colors.white38, fontSize: 10, letterSpacing: 0.5)),
      ],
    );
  }

  Widget _cardTile(CreditCard card, CardSpendSummary? summary) {
    return _tileShell(
      borderColor: card.networkColor.withValues(alpha: 0.4),
      width: 160,
      children: [
        Icon(Icons.credit_card, color: card.networkColor, size: 18),
        const SizedBox(height: AppSpacing.sm),
        Text('₹${(summary?.totalSpend ?? 0).toStringAsFixed(0)}', style: GoogleFonts.spaceGrotesk(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
        Text('+₹${(summary?.totalRewards ?? 0).toStringAsFixed(0)} rewards', style: GoogleFonts.spaceGrotesk(color: AppTheme.rewardGold, fontSize: 11)),
        const SizedBox(height: 2),
        Text(card.cardName.toUpperCase(), style: GoogleFonts.spaceGrotesk(color: Colors.white38, fontSize: 10, letterSpacing: 0.5), overflow: TextOverflow.ellipsis),
      ],
    );
  }

  Widget _cardBenefitsTile(String cardId) {
    final benefitsState = ref.watch(benefitsViewModelProvider);
    final cardBenefits = benefitsState.userCardBenefits.where((cb) => cb.cardId == cardId).toList();
    final activeCount = cardBenefits.where((cb) => cb.isActive).length;

    return _tileShell(
      borderColor: AppTheme.successColor.withValues(alpha: 0.25),
      width: 160,
      children: [
        const Icon(Icons.verified_outlined, color: AppTheme.successColor, size: 18),
        const SizedBox(height: AppSpacing.sm),
        Text('${cardBenefits.length} available', style: GoogleFonts.spaceGrotesk(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
        Text('$activeCount active', style: GoogleFonts.spaceGrotesk(color: Colors.white54, fontSize: 11)),
        const SizedBox(height: 2),
        Text('CARD BENEFITS', style: GoogleFonts.spaceGrotesk(color: Colors.white38, fontSize: 10, letterSpacing: 0.5)),
      ],
    );
  }
}
