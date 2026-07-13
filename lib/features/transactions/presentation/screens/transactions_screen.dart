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
    return [const SizedBox.shrink()]; // replaced in Task 5
  }
}
