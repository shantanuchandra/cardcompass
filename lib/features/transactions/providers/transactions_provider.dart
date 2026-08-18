import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/repository_providers.dart';
import '../../../core/providers/supabase_provider.dart';
import '../../../core/services/bank_market.dart';
import '../../../core/services/card_normalizer_service.dart';
import '../../../core/services/retail_transaction_aggregation.dart';
import '../../../core/services/reporting_time.dart';
import '../../../shared/models/transaction.dart';
import '../../../shared/models/user_card.dart';

enum TxnGrouping { flat, byCard, byCategory, byDate }

class TxnFilter {
  final String? cardId;
  final DateTime? from;
  final DateTime? to;
  final String? category;

  const TxnFilter({this.cardId, this.from, this.to, this.category});

  TxnFilter copyWith({
    Object? cardId = _sentinel,
    Object? from = _sentinel,
    Object? to = _sentinel,
    Object? category = _sentinel,
  }) {
    return TxnFilter(
      cardId: cardId == _sentinel ? this.cardId : cardId as String?,
      from: from == _sentinel ? this.from : from as DateTime?,
      to: to == _sentinel ? this.to : to as DateTime?,
      category: category == _sentinel ? this.category : category as String?,
    );
  }

  static const _sentinel = Object();

  String get label {
    final parts = <String>[];
    if (from != null && to != null) {
      parts.add('${_mon(from!)} – ${_mon(to!)}');
    } else if (from != null) {
      parts.add('From ${_mon(from!)}');
    }
    if (category != null) parts.add(category!);
    return parts.isEmpty ? 'All time' : parts.join(' · ');
  }

  static String _mon(DateTime d) => '${d.day} ${_months[d.month - 1]}';
  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
}

class TrendPoint {
  final DateTime date;
  final double total;
  const TrendPoint(this.date, this.total);
}

class SpendTrend {
  final List<TrendPoint> points;
  final double dailyAverage;
  final String? peakLabel;
  final double? percentVsPrior;

  const SpendTrend({
    required this.points,
    required this.dailyAverage,
    this.peakLabel,
    this.percentVsPrior,
  });
}

sealed class TxnLedgerItem {
  const TxnLedgerItem();
}

final class TxnLedgerGroupHeader extends TxnLedgerItem {
  const TxnLedgerGroupHeader({required this.label, required this.total});

  final String label;
  final double total;
}

final class TxnLedgerTransaction extends TxnLedgerItem {
  const TxnLedgerTransaction(this.transaction);

  final Transaction transaction;
}

class TxnsState {
  static final Expando<_TxnsProjection> _projectionCache =
      Expando<_TxnsProjection>('TxnsState projection');

  final List<Transaction> all;
  final List<UserCard> cards;
  final TxnFilter filter;
  final TxnGrouping grouping;
  final DateTime? reportingCutoff;

  TxnsState({
    List<Transaction> all = const [],
    List<UserCard> cards = const [],
    this.filter = const TxnFilter(),
    this.grouping = TxnGrouping.flat,
    this.reportingCutoff,
  }) : all = List.unmodifiable(all),
       cards = List.unmodifiable(cards);

  TxnsState copyWith({
    List<Transaction>? all,
    List<UserCard>? cards,
    TxnFilter? filter,
    TxnGrouping? grouping,
    DateTime? reportingCutoff,
  }) => TxnsState(
    all: all ?? this.all,
    cards: cards ?? this.cards,
    filter: filter ?? this.filter,
    grouping: grouping ?? this.grouping,
    reportingCutoff: reportingCutoff ?? this.reportingCutoff,
  );

  _TxnsProjection get _projection {
    final cached = _projectionCache[this];
    if (cached != null) return cached;
    final projection = _buildProjection();
    _projectionCache[this] = projection;
    return projection;
  }

  List<Transaction> get filtered => _projection.rawRows;

  List<TxnLedgerItem> get ledgerItems => _projection.ledgerItems;

  int? ledgerIndexForTransactionId(String transactionId) =>
      _projection.ledgerIndexes[transactionId];

  RetailTransactionAggregate get _aggregate => _projection.aggregate;

  double get totalSpend => _aggregate.totalSpend;
  double get totalRewards => _aggregate.totalRewards;

  double canonicalSubtotal(Iterable<Transaction> rows) {
    final purchaseIdentities = _projection.purchaseIdentities;
    return rows.fold(
      0.0,
      (sum, transaction) =>
          sum +
          (purchaseIdentities.contains(transaction) ? transaction.amount : 0),
    );
  }

  String? get topCategory {
    final map = _aggregate.categoryTotals;
    if (map.isEmpty) return null;
    return map.entries.reduce((a, b) => a.value > b.value ? a : b).key;
  }

  /// Whether [txn] is a foreign-currency charge relative to its card's
  /// issuing bank's market currency. Resolves the card's bank name once
  /// per lookup (cards list is small — far fewer cards than transactions)
  /// rather than joining bank name into every transaction row at the
  /// database level. Returns false if the card can't be found or its
  /// bank's market currency can't be resolved (currencyForBank returns
  /// null for an unrecognized bank) — a transaction is only flagged
  /// international when there's a concrete, resolved market to compare
  /// against.
  bool isTransactionInternational(Transaction txn) {
    final card = cards.where((c) => c.id == txn.userCardId).firstOrNull;
    if (card?.bank == null) return false;
    final normalizedBank = CardNormalizerService.normalizeBankName(card!.bank!);
    final marketCurrency = currencyForBank(normalizedBank);
    if (marketCurrency == null) return false;
    return txn.isInternational(marketCurrency);
  }

  Map<String, List<Transaction>> get grouped => _projection.grouped;

  Map<String, List<Transaction>> _groupTransactions(
    List<Transaction> transactions,
  ) {
    final groups = <String, List<Transaction>>{};
    switch (grouping) {
      case TxnGrouping.flat:
        groups['All'] = transactions;
      case TxnGrouping.byCard:
        for (final transaction in transactions) {
          (groups[transaction.userCardId] ??= []).add(transaction);
        }
      case TxnGrouping.byCategory:
        for (final transaction in transactions) {
          (groups[transaction.category ?? 'Other'] ??= []).add(transaction);
        }
      case TxnGrouping.byDate:
        for (final transaction in transactions) {
          final d = toReportingLocalTime(transaction.transactionDate);
          final key = '${d.day} ${_TxnsState._months[d.month - 1]} ${d.year}';
          (groups[key] ??= []).add(transaction);
        }
    }

    return Map.unmodifiable(
      groups.map(
        (key, rows) => MapEntry(
          key,
          identical(rows, transactions)
              ? rows
              : List<Transaction>.unmodifiable(rows),
        ),
      ),
    );
  }

  SpendTrend get spendTrend {
    final aggregate = _aggregate;
    if (aggregate.purchases.isEmpty) {
      return const SpendTrend(points: [], dailyAverage: 0);
    }

    final days = aggregate.localDayTotals.keys.toList()..sort();
    final points = days
        .map((day) => TrendPoint(day, aggregate.localDayTotals[day]!))
        .toList();

    final total = points.fold(0.0, (s, p) => s + p.total);
    final avg = points.isEmpty ? 0.0 : total / points.length;

    TrendPoint? peak;
    for (final p in points) {
      if (peak == null || p.total > peak.total) peak = p;
    }
    String? peakLabel;
    if (peak != null) {
      final d = peak.date;
      peakLabel = '${d.day} ${_TxnsState._months[d.month - 1]}';
    }

    double? percentVsPrior;
    final priorTotal = _projection.priorTotal;
    if (filter.from != null && filter.to != null) {
      if (priorTotal != null && priorTotal > 0) {
        percentVsPrior = (total - priorTotal) / priorTotal * 100;
      }
    }

    return SpendTrend(
      points: points,
      dailyAverage: avg,
      peakLabel: peakLabel,
      percentVsPrior: percentVsPrior,
    );
  }

  _TxnsProjection _buildProjection() {
    final currentRows = <Transaction>[];
    final priorRows = <Transaction>[];
    final currentEndExclusive = filter.to == null
        ? null
        : _nextCalendarDay(filter.to!);
    final hasPriorPeriod = filter.from != null && currentEndExclusive != null;
    final periodDuration = hasPriorPeriod
        ? currentEndExclusive.difference(filter.from!)
        : null;
    final priorFrom = periodDuration == null
        ? null
        : filter.from!.subtract(periodDuration);
    final priorThrough = hasPriorPeriod
        ? filter.from!.subtract(const Duration(microseconds: 1))
        : null;

    for (final transaction in all) {
      final date = transaction.transactionDate;
      if (reportingCutoff != null && date.isAfter(reportingCutoff!)) continue;
      if (filter.cardId != null && transaction.userCardId != filter.cardId) {
        continue;
      }

      final inCurrentPeriod =
          (filter.from == null || !date.isBefore(filter.from!)) &&
          (currentEndExclusive == null || date.isBefore(currentEndExclusive));
      if (inCurrentPeriod) currentRows.add(transaction);

      if (priorFrom != null &&
          priorThrough != null &&
          !date.isBefore(priorFrom) &&
          !date.isAfter(priorThrough)) {
        priorRows.add(transaction);
      }
    }

    final currentBeforeCategory = aggregateRetailTransactions(currentRows);
    final aggregate = _selectCategory(currentBeforeCategory);
    final category = filter.category?.toLowerCase();
    final rawRows = category == null
        ? currentRows
        : currentRows
              .where(
                (transaction) =>
                    transaction.category?.toLowerCase() == category,
              )
              .toList();

    double? priorTotal;
    if (hasPriorPeriod) {
      priorTotal = _selectCategory(
        aggregateRetailTransactions(priorRows),
      ).totalSpend;
    }

    final immutableRawRows = List<Transaction>.unmodifiable(rawRows);
    final purchaseIdentities = Set<Transaction>.unmodifiable(
      aggregate.purchases,
    );
    final grouped = _groupTransactions(immutableRawRows);
    final ledgerItems = <TxnLedgerItem>[];
    final ledgerIndexes = <String, int>{};
    for (final entry in grouped.entries) {
      if (grouping != TxnGrouping.flat) {
        final total = entry.value.fold<double>(
          0,
          (sum, transaction) =>
              sum +
              (purchaseIdentities.contains(transaction)
                  ? transaction.amount
                  : 0),
        );
        ledgerItems.add(TxnLedgerGroupHeader(label: entry.key, total: total));
      }
      for (final transaction in entry.value) {
        ledgerIndexes.putIfAbsent(transaction.id, () => ledgerItems.length);
        ledgerItems.add(TxnLedgerTransaction(transaction));
      }
    }

    return _TxnsProjection(
      rawRows: immutableRawRows,
      aggregate: aggregate,
      purchaseIdentities: purchaseIdentities,
      priorTotal: priorTotal,
      grouped: grouped,
      ledgerItems: List.unmodifiable(ledgerItems),
      ledgerIndexes: Map.unmodifiable(ledgerIndexes),
    );
  }

  RetailTransactionAggregate _selectCategory(
    RetailTransactionAggregate aggregate,
  ) {
    final category = filter.category?.toLowerCase();
    if (category == null) return aggregate;
    return aggregateRetailTransactions(
      aggregate.purchases.where(
        (transaction) => transaction.category?.toLowerCase() == category,
      ),
    );
  }

  static DateTime _nextCalendarDay(DateTime date) {
    return date.isUtc
        ? DateTime.utc(date.year, date.month, date.day + 1)
        : DateTime(date.year, date.month, date.day + 1);
  }
}

class _TxnsProjection {
  const _TxnsProjection({
    required this.rawRows,
    required this.aggregate,
    required this.purchaseIdentities,
    required this.priorTotal,
    required this.grouped,
    required this.ledgerItems,
    required this.ledgerIndexes,
  });

  final List<Transaction> rawRows;
  final RetailTransactionAggregate aggregate;
  final Set<Transaction> purchaseIdentities;
  final double? priorTotal;
  final Map<String, List<Transaction>> grouped;
  final List<TxnLedgerItem> ledgerItems;
  final Map<String, int> ledgerIndexes;
}

// ignore: library_private_types_in_public_api
class _TxnsState {
  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
}

class TxnsNotifier extends AsyncNotifier<TxnsState> {
  @override
  Future<TxnsState> build() async {
    final user = ref.watch(currentUserProvider);
    if (user == null) return TxnsState();

    final txnRepo = ref.read(transactionsRepositoryProvider);
    final cardsRepo = ref.read(cardsRepositoryProvider);
    final reportingCutoff = DateTime.now();

    final results = await Future.wait([
      txnRepo.getAllTransactions(userId: user.id),
      cardsRepo.getUserCards(user.id),
    ]);

    return TxnsState(
      all: results[0] as List<Transaction>,
      cards: results[1] as List<UserCard>,
      filter: _defaultThisMonthFilter(reportingCutoff),
      reportingCutoff: reportingCutoff,
    );
  }

  TxnFilter _defaultThisMonthFilter(DateTime reportingCutoff) {
    return TxnFilter(
      from: DateTime(reportingCutoff.year, reportingCutoff.month, 1),
    );
  }

  void setFilter(TxnFilter filter) {
    state = state.whenData((s) => s.copyWith(filter: filter));
  }

  void setGrouping(TxnGrouping g) {
    state = state.whenData((s) => s.copyWith(grouping: g));
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }
}

final txnsNotifierProvider = AsyncNotifierProvider<TxnsNotifier, TxnsState>(
  TxnsNotifier.new,
);
