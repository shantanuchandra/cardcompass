import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/repository_providers.dart';
import '../../../core/providers/supabase_provider.dart';
import '../../../core/services/bank_market.dart';
import '../../../core/services/card_normalizer_service.dart';
import '../../../core/services/retail_transaction_aggregation.dart';
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

class TxnsState {
  final List<Transaction> all;
  final List<UserCard> cards;
  final TxnFilter filter;
  final TxnGrouping grouping;
  final DateTime? reportingCutoff;

  const TxnsState({
    this.all = const [],
    this.cards = const [],
    this.filter = const TxnFilter(),
    this.grouping = TxnGrouping.flat,
    this.reportingCutoff,
  });

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

  List<Transaction> get filtered {
    var txns = all;
    if (reportingCutoff != null) {
      txns = txns
          .where((t) => !t.transactionDate.isAfter(reportingCutoff!))
          .toList();
    }
    if (filter.cardId != null) {
      txns = txns.where((t) => t.userCardId == filter.cardId).toList();
    }
    if (filter.from != null) {
      txns = txns
          .where((t) => !t.transactionDate.isBefore(filter.from!))
          .toList();
    }
    if (filter.to != null) {
      final endExclusive = _nextCalendarDay(filter.to!);
      txns = txns
          .where((t) => t.transactionDate.isBefore(endExclusive))
          .toList();
    }
    if (filter.category != null) {
      txns = txns
          .where(
            (t) => t.category?.toLowerCase() == filter.category!.toLowerCase(),
          )
          .toList();
    }
    return txns;
  }

  RetailTransactionAggregate get _aggregate =>
      aggregateRetailTransactions(filtered);

  double get totalSpend => _aggregate.totalSpend;
  double get totalRewards => _aggregate.totalRewards;

  double canonicalSubtotal(Iterable<Transaction> rows) {
    final groupRows = rows.toSet();
    return _aggregate.purchases
        .where(groupRows.contains)
        .fold(0.0, (sum, transaction) => sum + transaction.amount);
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

  Map<String, List<Transaction>> get grouped {
    final txns = filtered;
    switch (grouping) {
      case TxnGrouping.flat:
        return {'All': txns};
      case TxnGrouping.byCard:
        final m = <String, List<Transaction>>{};
        for (final t in txns) {
          (m[t.userCardId] ??= []).add(t);
        }
        return m;
      case TxnGrouping.byCategory:
        final m = <String, List<Transaction>>{};
        for (final t in txns) {
          (m[t.category ?? 'Other'] ??= []).add(t);
        }
        return m;
      case TxnGrouping.byDate:
        final m = <String, List<Transaction>>{};
        for (final t in txns) {
          final d = t.transactionDate.toLocal();
          final key = '${d.day} ${_TxnsState._months[d.month - 1]} ${d.year}';
          (m[key] ??= []).add(t);
        }
        return m;
    }
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

    // prior period comparison
    double? percentVsPrior;
    if (filter.from != null && filter.to != null) {
      final currentEndExclusive = _nextCalendarDay(filter.to!);
      final duration = currentEndExclusive.difference(filter.from!);
      final priorFrom = filter.from!.subtract(duration);
      final priorThrough = filter.from!.subtract(
        const Duration(microseconds: 1),
      );
      final priorTotal = aggregateRetailTransactions(
        _filteredWithoutDateRange,
        fromInclusive: priorFrom,
        throughInclusive: priorThrough,
      ).totalSpend;
      if (priorTotal > 0) {
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

  List<Transaction> get _filteredWithoutDateRange {
    return all.where((transaction) {
      if (reportingCutoff != null &&
          transaction.transactionDate.isAfter(reportingCutoff!)) {
        return false;
      }
      if (filter.cardId != null && transaction.userCardId != filter.cardId) {
        return false;
      }
      if (filter.category != null &&
          transaction.category?.toLowerCase() !=
              filter.category!.toLowerCase()) {
        return false;
      }
      return true;
    }).toList();
  }

  static DateTime _nextCalendarDay(DateTime date) {
    return date.isUtc
        ? DateTime.utc(date.year, date.month, date.day + 1)
        : DateTime(date.year, date.month, date.day + 1);
  }
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
    if (user == null) return const TxnsState();

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
