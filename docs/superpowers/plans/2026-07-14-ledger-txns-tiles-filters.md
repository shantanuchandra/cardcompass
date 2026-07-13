# Ledger Txns Tiles, Filters, and Grouped Views Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the Ledger Txns page from a flat, category-only-filtered list into a filterable (card + date + category) page with summary tiles (spend, rewards, top category, per-card, card benefits) and a grouping toggle (flat/card/category/date), so users can see where their money went, by which card, and how that ties to card benefits.

**Architecture:** Rewire `TransactionsScreen` off its local `_categoryFilter` state and onto the existing (currently unused) `TransactionsViewModelController`, which already has card/date/category filter state and `applyFilters()`/`getTransactionSummary()`. Add pure-Dart helper methods on the viewmodel for per-card summaries and date/category grouping (unit-testable), then build the screen's UI (filter bar, tile row, grouped list) on top of that state. No new backend calls — `loadTransactions` already fetches the full transaction + card list once; all filtering/grouping is client-side.

**Tech Stack:** Flutter, Riverpod (`@riverpod` code-gen), Hive/Supabase-backed models already in place, `google_fonts`, `flutter_animate`. Test with `flutter test` (pure-Dart unit tests only — this codebase has no widget-test precedent, so UI is verified via manual run per the `verify` skill instead of widget tests).

---

## File Structure

- **Modify:** `lib/features/transactions/viewmodels/transactions_viewmodel.dart` — add `getPerCardSummary()`, `getGroupedTransactions(TransactionGrouping)` methods and a `TransactionGrouping` enum. This is where all new filtering/grouping/summary math lives, so it stays unit-testable independent of widgets.
- **Modify:** `lib/features/transactions/presentation/screens/transactions_screen.dart` — full rebuild of `build()` to read from `TransactionsViewModelController` instead of local state; add filter bar, tile row, grouping toggle, grouped list rendering, card badge per row.
- **Create:** `test/transactions_viewmodel_test.dart` — unit tests for filtering, per-card summary, and grouping logic.

No other files change. The benefits card-summary widget is *replicated* (small, page-specific `_buildCardBenefitsTile` in the screen file) rather than extracted into a shared widget — it's a 15-line presentational block, not worth a cross-feature abstraction (YAGNI).

---

## Task 1: Add `TransactionGrouping` enum and per-card summary to the viewmodel

**Files:**
- Modify: `lib/features/transactions/viewmodels/transactions_viewmodel.dart`
- Test: `test/transactions_viewmodel_test.dart`

- [ ] **Step 1: Write the failing test for per-card summary**

Create `test/transactions_viewmodel_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:cardcompass/features/transactions/viewmodels/transactions_viewmodel.dart';
import 'package:cardcompass/shared/models/transaction.dart';

Transaction _tx({
  required String id,
  required String userCardId,
  required double amount,
  TransactionType type = TransactionType.debit,
  TransactionCategory category = TransactionCategory.food,
  double? rewardEarned,
  DateTime? date,
}) {
  return Transaction(
    id: id,
    userId: 'u1',
    userCardId: userCardId,
    amount: amount,
    description: 'test',
    category: category,
    type: type,
    transactionDate: date ?? DateTime(2026, 7, 10),
    rewardEarned: rewardEarned,
    createdAt: DateTime(2026, 7, 10),
  );
}

void main() {
  group('TransactionsViewState.perCardSummary', () {
    test('sums spend and rewards per card from filteredTransactions', () {
      final state = const TransactionsViewState().copyWith(
        filteredTransactions: [
          _tx(id: '1', userCardId: 'cardA', amount: 100, rewardEarned: 5),
          _tx(id: '2', userCardId: 'cardA', amount: 50, rewardEarned: 2),
          _tx(id: '3', userCardId: 'cardB', amount: 200),
          _tx(id: '4', userCardId: 'cardA', amount: 30, type: TransactionType.credit),
        ],
      );

      final summary = state.perCardSummary();

      expect(summary['cardA']!.totalSpend, 150);
      expect(summary['cardA']!.totalRewards, 7);
      expect(summary['cardB']!.totalSpend, 200);
      expect(summary['cardB']!.totalRewards, 0);
      expect(summary.containsKey('cardA'), isTrue);
    });

    test('excludes transactions with null userCardId', () {
      final state = const TransactionsViewState().copyWith(
        filteredTransactions: [
          _tx(id: '1', userCardId: '', amount: 100),
        ],
      );
      final summary = state.perCardSummary();
      expect(summary.isEmpty, isTrue);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/transactions_viewmodel_test.dart`
Expected: FAIL — compile error, `perCardSummary` and `CardSpendSummary` undefined.

- [ ] **Step 3: Implement `CardSpendSummary` and `perCardSummary()` on `TransactionsViewState`**

In `lib/features/transactions/viewmodels/transactions_viewmodel.dart`, add near the top (after imports, before `TransactionsViewState`):

```dart
/// Aggregated spend/reward totals for one card within the current filter.
class CardSpendSummary {
  final String cardId;
  final double totalSpend;
  final double totalRewards;

  const CardSpendSummary({
    required this.cardId,
    required this.totalSpend,
    required this.totalRewards,
  });
}
```

Add this method inside `TransactionsViewState` (after the `copyWith` method, before the closing brace):

```dart
  /// Per-card spend + reward totals, computed from [filteredTransactions].
  /// Transactions with a null/empty userCardId are excluded.
  Map<String, CardSpendSummary> perCardSummary() {
    final spendByCard = <String, double>{};
    final rewardsByCard = <String, double>{};

    for (final t in filteredTransactions) {
      final cardId = t.userCardId;
      if (cardId == null || cardId.isEmpty) continue;

      if (t.type == TransactionType.debit) {
        spendByCard[cardId] = (spendByCard[cardId] ?? 0) + t.amount.abs();
      } else {
        spendByCard.putIfAbsent(cardId, () => 0);
      }
      rewardsByCard[cardId] = (rewardsByCard[cardId] ?? 0) + (t.rewardEarned ?? 0);
    }

    return {
      for (final cardId in spendByCard.keys)
        cardId: CardSpendSummary(
          cardId: cardId,
          totalSpend: spendByCard[cardId] ?? 0,
          totalRewards: rewardsByCard[cardId] ?? 0,
        ),
    };
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/transactions_viewmodel_test.dart`
Expected: PASS (2 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/features/transactions/viewmodels/transactions_viewmodel.dart test/transactions_viewmodel_test.dart
git commit -m "feat: add per-card spend/reward summary to transactions viewmodel"
```

---

## Task 2: Add `TransactionGrouping` enum and grouped-transactions method

**Files:**
- Modify: `lib/features/transactions/viewmodels/transactions_viewmodel.dart`
- Test: `test/transactions_viewmodel_test.dart`

- [ ] **Step 1: Write the failing test for grouping**

Append to `test/transactions_viewmodel_test.dart` (inside `main()`, after the existing `group`):

```dart
  group('TransactionsViewState.groupedTransactions', () {
    test('flat grouping returns a single group with all filtered transactions, newest first', () {
      final state = const TransactionsViewState().copyWith(
        filteredTransactions: [
          _tx(id: '1', userCardId: 'cardA', amount: 10, date: DateTime(2026, 7, 1)),
          _tx(id: '2', userCardId: 'cardA', amount: 20, date: DateTime(2026, 7, 10)),
        ],
      );

      final groups = state.groupedTransactions(TransactionGrouping.flat);

      expect(groups.length, 1);
      expect(groups.first.key, 'All Transactions');
      expect(groups.first.transactions.map((t) => t.id).toList(), ['2', '1']);
    });

    test('byCard grouping buckets by userCardId with per-group subtotal', () {
      final state = const TransactionsViewState().copyWith(
        filteredTransactions: [
          _tx(id: '1', userCardId: 'cardA', amount: 10),
          _tx(id: '2', userCardId: 'cardB', amount: 20),
          _tx(id: '3', userCardId: 'cardA', amount: 5),
        ],
      );

      final groups = state.groupedTransactions(TransactionGrouping.byCard);
      final byKey = {for (final g in groups) g.key: g};

      expect(byKey.keys.toSet(), {'cardA', 'cardB'});
      expect(byKey['cardA']!.transactions.length, 2);
      expect(byKey['cardA']!.subtotal, 15);
      expect(byKey['cardB']!.subtotal, 20);
    });

    test('byCategory grouping buckets by category name', () {
      final state = const TransactionsViewState().copyWith(
        filteredTransactions: [
          _tx(id: '1', userCardId: 'cardA', amount: 10, category: TransactionCategory.food),
          _tx(id: '2', userCardId: 'cardA', amount: 20, category: TransactionCategory.fuel),
        ],
      );

      final groups = state.groupedTransactions(TransactionGrouping.byCategory);
      final keys = groups.map((g) => g.key).toSet();

      expect(keys, {'food', 'fuel'});
    });

    test('byDate grouping buckets by year-month', () {
      final state = const TransactionsViewState().copyWith(
        filteredTransactions: [
          _tx(id: '1', userCardId: 'cardA', amount: 10, date: DateTime(2026, 6, 15)),
          _tx(id: '2', userCardId: 'cardA', amount: 20, date: DateTime(2026, 7, 1)),
        ],
      );

      final groups = state.groupedTransactions(TransactionGrouping.byDate);
      final keys = groups.map((g) => g.key).toSet();

      expect(keys, {'2026-06', '2026-07'});
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/transactions_viewmodel_test.dart`
Expected: FAIL — `TransactionGrouping`, `groupedTransactions` undefined.

- [ ] **Step 3: Implement `TransactionGrouping`, `TransactionGroup`, and `groupedTransactions()`**

Add after the `CardSpendSummary` class in `lib/features/transactions/viewmodels/transactions_viewmodel.dart`:

```dart
/// How the transaction list should be sectioned in the UI.
enum TransactionGrouping { flat, byCard, byCategory, byDate }

/// One section of grouped transactions with a display key and subtotal.
class TransactionGroup {
  final String key;
  final List<Transaction> transactions;
  final double subtotal;

  const TransactionGroup({
    required this.key,
    required this.transactions,
    required this.subtotal,
  });
}

double _debitTotal(List<Transaction> transactions) {
  return transactions
      .where((t) => t.type == TransactionType.debit)
      .fold<double>(0, (sum, t) => sum + t.amount.abs());
}

List<Transaction> _sortedNewestFirst(List<Transaction> transactions) {
  final sorted = List<Transaction>.from(transactions);
  sorted.sort((a, b) => b.transactionDate.compareTo(a.transactionDate));
  return sorted;
}
```

Add this method inside `TransactionsViewState` (after `perCardSummary()`):

```dart
  /// Sections [filteredTransactions] per [grouping], each section newest-first,
  /// sections ordered by first-seen key.
  List<TransactionGroup> groupedTransactions(TransactionGrouping grouping) {
    if (grouping == TransactionGrouping.flat) {
      final sorted = _sortedNewestFirst(filteredTransactions);
      return [
        TransactionGroup(
          key: 'All Transactions',
          transactions: sorted,
          subtotal: _debitTotal(sorted),
        ),
      ];
    }

    String keyFor(Transaction t) {
      switch (grouping) {
        case TransactionGrouping.byCard:
          return (t.userCardId == null || t.userCardId!.isEmpty) ? 'Unknown Card' : t.userCardId!;
        case TransactionGrouping.byCategory:
          return t.categoryString;
        case TransactionGrouping.byDate:
          return '${t.transactionDate.year}-${t.transactionDate.month.toString().padLeft(2, '0')}';
        case TransactionGrouping.flat:
          return 'All Transactions';
      }
    }

    final buckets = <String, List<Transaction>>{};
    for (final t in filteredTransactions) {
      buckets.putIfAbsent(keyFor(t), () => []).add(t);
    }

    return buckets.entries.map((entry) {
      final sorted = _sortedNewestFirst(entry.value);
      return TransactionGroup(
        key: entry.key,
        transactions: sorted,
        subtotal: _debitTotal(sorted),
      );
    }).toList();
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/transactions_viewmodel_test.dart`
Expected: PASS (6 tests total)

- [ ] **Step 5: Commit**

```bash
git add lib/features/transactions/viewmodels/transactions_viewmodel.dart test/transactions_viewmodel_test.dart
git commit -m "feat: add transaction grouping (flat/card/category/date) to viewmodel"
```

---

## Task 3: Wire `TransactionsScreen` onto `TransactionsViewModelController` and add the filter bar

**Files:**
- Modify: `lib/features/transactions/presentation/screens/transactions_screen.dart`

- [ ] **Step 1: Replace state source and load call**

In `lib/features/transactions/presentation/screens/transactions_screen.dart`, replace the whole file with the version below. This step covers filter-bar wiring; tiles and grouped list are added in Tasks 4-5 within the same file, so the full file is given here and refined in place in subsequent tasks (each task's diff is additive on top of this).

```dart
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
                title: const Text('All Time', style: TextStyle(color: Colors.white)),
                onTap: () {
                  notifier.setDateRange(null);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: const Text('This Month', style: TextStyle(color: Colors.white)),
                onTap: () {
                  notifier.setDateRange(DateRange(start: DateTime(now.year, now.month, 1), end: now));
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: const Text('Last Month', style: TextStyle(color: Colors.white)),
                onTap: () {
                  final lastMonth = DateTime(now.year, now.month - 1, 1);
                  final endOfLastMonth = DateTime(now.year, now.month, 1).subtract(const Duration(days: 1));
                  notifier.setDateRange(DateRange(start: lastMonth, end: endOfLastMonth));
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: const Text('Last 3 Months', style: TextStyle(color: Colors.white)),
                onTap: () {
                  notifier.setDateRange(DateRange(start: DateTime(now.year, now.month - 3, now.day), end: now));
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: const Text('Custom Range', style: TextStyle(color: Colors.white)),
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
```

- [ ] **Step 2: Run static analysis to confirm the file compiles**

Run: `flutter analyze lib/features/transactions/presentation/screens/transactions_screen.dart`
Expected: No errors (warnings about unused `_grouping`/`CreditCard` import are acceptable at this intermediate step and resolved by Task 5).

- [ ] **Step 3: Commit**

```bash
git add lib/features/transactions/presentation/screens/transactions_screen.dart
git commit -m "feat: wire ledger txns screen onto shared viewmodel with card/date/category filter bar"
```

---

## Task 4: Add the summary tile row (Total Spend, Rewards Earned, Top Category, per-card, Card Benefits)

**Files:**
- Modify: `lib/features/transactions/presentation/screens/transactions_screen.dart`
- Modify: `lib/features/transactions/viewmodels/transactions_viewmodel.dart` (only if a helper is missing — none expected; `getTransactionSummary()` and `perCardSummary()` already exist)

- [ ] **Step 1: Add imports for benefits viewmodel**

In `lib/features/transactions/presentation/screens/transactions_screen.dart`, add to the imports:

```dart
import '../../../benefits/viewmodels/benefits_viewmodel.dart';
import '../../../../shared/models/benefit.dart';
```

- [ ] **Step 2: Insert the tile row into `build()`**

In the `ListView`'s `children` list built in Task 3, insert `_buildTileRow(state)` right after `_buildFilterBar(state, notifier)`:

```dart
                    children: [
                      _buildFilterBar(state, notifier),
                      const SizedBox(height: AppSpacing.md),
                      _buildTileRow(state),
                      const SizedBox(height: AppSpacing.md),
                      if (state.filteredTransactions.isEmpty)
                        _buildNoResultsState(notifier)
                      else
                        ..._buildTransactionSections(state),
                    ],
```

- [ ] **Step 3: Implement `_buildTileRow` and its sub-widgets**

Add these methods to `_TransactionsScreenState`:

```dart
  Widget _buildTileRow(TransactionsViewState state) {
    final summary = state.getTransactionSummary();
    final perCard = state.perCardSummary();
    final cardsToShow = state.selectedCardId.isEmpty
        ? state.userCards
        : state.userCards.where((c) => c.id == state.selectedCardId).toList();

    return SizedBox(
      height: 108,
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

  Widget _statTile(String label, String value, IconData icon, Color color, {String? subtitle}) {
    return Container(
      width: 150,
      margin: const EdgeInsets.only(right: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: const Color(0xFF0C152B),
        borderRadius: BorderRadius.circular(AppBorderRadius.xl),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: AppSpacing.sm),
          Text(value, style: GoogleFonts.spaceGrotesk(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16), overflow: TextOverflow.ellipsis),
          if (subtitle != null)
            Text(subtitle, style: GoogleFonts.spaceGrotesk(color: Colors.white54, fontSize: 11)),
          const SizedBox(height: 2),
          Text(label, style: GoogleFonts.spaceGrotesk(color: Colors.white38, fontSize: 10, letterSpacing: 0.5)),
        ],
      ),
    );
  }

  Widget _cardTile(CreditCard card, CardSpendSummary? summary) {
    return Container(
      width: 160,
      margin: const EdgeInsets.only(right: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: const Color(0xFF0C152B),
        borderRadius: BorderRadius.circular(AppBorderRadius.xl),
        border: Border.all(color: card.networkColor.withValues(alpha: 0.4), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.credit_card, color: card.networkColor, size: 18),
          const SizedBox(height: AppSpacing.sm),
          Text('₹${(summary?.totalSpend ?? 0).toStringAsFixed(0)}', style: GoogleFonts.spaceGrotesk(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          Text('+₹${(summary?.totalRewards ?? 0).toStringAsFixed(0)} rewards', style: GoogleFonts.spaceGrotesk(color: AppTheme.rewardGold, fontSize: 11)),
          const SizedBox(height: 2),
          Text(card.cardName.toUpperCase(), style: GoogleFonts.spaceGrotesk(color: Colors.white38, fontSize: 10, letterSpacing: 0.5), overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Widget _cardBenefitsTile(String cardId) {
    return Consumer(
      builder: (context, ref, _) {
        final benefitsState = ref.watch(benefitsViewModelProvider);
        final cardBenefits = benefitsState.userCardBenefits.where((cb) => cb.cardId == cardId).toList();
        final activeCount = cardBenefits.where((cb) => cb.isActive).length;

        return Container(
          width: 160,
          margin: const EdgeInsets.only(right: AppSpacing.sm),
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: const Color(0xFF0C152B),
            borderRadius: BorderRadius.circular(AppBorderRadius.xl),
            border: Border.all(color: AppTheme.successColor.withValues(alpha: 0.25), width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.verified_outlined, color: AppTheme.successColor, size: 18),
              const SizedBox(height: AppSpacing.sm),
              Text('${cardBenefits.length} available', style: GoogleFonts.spaceGrotesk(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
              Text('$activeCount active', style: GoogleFonts.spaceGrotesk(color: Colors.white54, fontSize: 11)),
              const SizedBox(height: 2),
              Text('CARD BENEFITS', style: GoogleFonts.spaceGrotesk(color: Colors.white38, fontSize: 10, letterSpacing: 0.5)),
            ],
          ),
        );
      },
    );
  }
```

Note: `benefitsViewModelProvider` state is populated by `benefits_screen.dart`'s own `loadBenefitsData` call when that screen has been visited; this tile reads whatever is already loaded and does not trigger its own load, to avoid duplicating data-fetch responsibility across features. If the user hasn't opened Benefits yet in the session, the tile shows 0/0, which is acceptable for this iteration (documented limitation, not a bug — no cross-feature preloading is introduced here per YAGNI).

- [ ] **Step 4: Run static analysis**

Run: `flutter analyze lib/features/transactions/presentation/screens/transactions_screen.dart`
Expected: No errors.

- [ ] **Step 5: Commit**

```bash
git add lib/features/transactions/presentation/screens/transactions_screen.dart
git commit -m "feat: add spend/reward/category/card/benefits summary tiles to ledger txns page"
```

---

## Task 5: Add grouping toggle and render grouped transaction sections with card badges

**Files:**
- Modify: `lib/features/transactions/presentation/screens/transactions_screen.dart`

- [ ] **Step 1: Replace the `_buildTransactionSections` stub with the real implementation**

Replace:

```dart
  List<Widget> _buildTransactionSections(TransactionsViewState state) {
    return [const SizedBox.shrink()]; // replaced in Task 5
  }
```

with:

```dart
  List<Widget> _buildTransactionSections(TransactionsViewState state) {
    final groups = state.groupedTransactions(_grouping);
    final cardsById = {for (final c in state.userCards) c.id: c};

    return [
      _buildGroupingToggle(),
      const SizedBox(height: AppSpacing.md),
      for (final group in groups) ...[
        if (_grouping != TransactionGrouping.flat) _buildGroupHeader(group, state.selectedCardId, cardsById),
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

  Widget _buildGroupHeader(TransactionGroup group, String selectedCardId, Map<String, CreditCard> cardsById) {
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
    final categoryColor = _getCategoryColor(t.categoryString);
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
    if (difference == 0) return 'Today';
    if (difference == 1) return 'Yesterday';
    if (difference < 7) return '$difference days ago';
    return '${date.day}/${date.month}/${date.year}';
  }
```

- [ ] **Step 2: Run static analysis on the full file**

Run: `flutter analyze lib/features/transactions/presentation/screens/transactions_screen.dart`
Expected: No errors, no unused-import/unused-field warnings.

- [ ] **Step 3: Run the full test suite to confirm no regressions**

Run: `flutter test`
Expected: All tests pass, including the 6 new tests from Tasks 1-2.

- [ ] **Step 4: Commit**

```bash
git add lib/features/transactions/presentation/screens/transactions_screen.dart
git commit -m "feat: add grouping toggle and per-transaction card badge to ledger txns list"
```

---

## Task 6: Manual verification in a running app

**Files:** none (verification only)

- [ ] **Step 1: Launch the app**

Use the `run` skill (or `flutter run`) to launch the app on an available device/emulator, and navigate to the Ledger Txns tab.

- [ ] **Step 2: Verify the golden path**

Confirm: tile row renders (Total Spend, Rewards Earned, Top Category, per-card tiles); filter bar shows card chips, date control, category chips; selecting a card filters both tiles and list; selecting "This Month" narrows the list; grouping toggle switches between Flat/By Card/By Category/By Date with correct section headers and subtotals; each transaction row shows its card badge.

- [ ] **Step 3: Verify edge cases**

Confirm: a user with zero cards/transactions still sees the original "No transactions yet" empty state; applying filters that match nothing shows the new "No matching transactions" state with a working "Clear filters" button; selecting "All Cards" after a specific card was selected collapses the Card Benefits tile away (it's card-specific only).

- [ ] **Step 4: Report results**

Note any visual issues found and fix them in the relevant task's file before considering the plan complete. This step produces no commit by itself — any fix gets its own commit.
