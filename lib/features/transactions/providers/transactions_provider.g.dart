// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'transactions_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(TransactionsNotifier)
final transactionsProvider = TransactionsNotifierProvider._();

final class TransactionsNotifierProvider
    extends $NotifierProvider<TransactionsNotifier, List<Transaction>> {
  TransactionsNotifierProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'transactionsProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$transactionsNotifierHash();

  @$internal
  @override
  TransactionsNotifier create() => TransactionsNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<Transaction> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<Transaction>>(value),
    );
  }
}

String _$transactionsNotifierHash() =>
    r'57fec2e2a1c9e36e619be3469a28a6507fdb5aab';

abstract class _$TransactionsNotifier extends $Notifier<List<Transaction>> {
  List<Transaction> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<List<Transaction>, List<Transaction>>;
    final element = ref.element as $ClassProviderElement<
        AnyNotifier<List<Transaction>, List<Transaction>>,
        List<Transaction>,
        Object?,
        Object?>;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(recentTransactions)
final recentTransactionsProvider = RecentTransactionsProvider._();

final class RecentTransactionsProvider extends $FunctionalProvider<
    List<Transaction>,
    List<Transaction>,
    List<Transaction>> with $Provider<List<Transaction>> {
  RecentTransactionsProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'recentTransactionsProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$recentTransactionsHash();

  @$internal
  @override
  $ProviderElement<List<Transaction>> $createElement(
          $ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  List<Transaction> create(Ref ref) {
    return recentTransactions(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<Transaction> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<Transaction>>(value),
    );
  }
}

String _$recentTransactionsHash() =>
    r'e56298640add6a24bd906af2b5e1599f473280d9';

@ProviderFor(monthlySpending)
final monthlySpendingProvider = MonthlySpendingProvider._();

final class MonthlySpendingProvider
    extends $FunctionalProvider<double, double, double> with $Provider<double> {
  MonthlySpendingProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'monthlySpendingProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$monthlySpendingHash();

  @$internal
  @override
  $ProviderElement<double> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  double create(Ref ref) {
    return monthlySpending(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(double value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<double>(value),
    );
  }
}

String _$monthlySpendingHash() => r'b336980b207f2f2658da58a80fa256dd92177d39';

@ProviderFor(monthlyRewards)
final monthlyRewardsProvider = MonthlyRewardsProvider._();

final class MonthlyRewardsProvider
    extends $FunctionalProvider<double, double, double> with $Provider<double> {
  MonthlyRewardsProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'monthlyRewardsProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$monthlyRewardsHash();

  @$internal
  @override
  $ProviderElement<double> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  double create(Ref ref) {
    return monthlyRewards(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(double value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<double>(value),
    );
  }
}

String _$monthlyRewardsHash() => r'71c115f87e70da90550c429f91cb8ff17f511714';

@ProviderFor(transactionsByCategory)
final transactionsByCategoryProvider = TransactionsByCategoryProvider._();

final class TransactionsByCategoryProvider extends $FunctionalProvider<
        Map<TransactionCategory, double>,
        Map<TransactionCategory, double>,
        Map<TransactionCategory, double>>
    with $Provider<Map<TransactionCategory, double>> {
  TransactionsByCategoryProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'transactionsByCategoryProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$transactionsByCategoryHash();

  @$internal
  @override
  $ProviderElement<Map<TransactionCategory, double>> $createElement(
          $ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  Map<TransactionCategory, double> create(Ref ref) {
    return transactionsByCategory(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Map<TransactionCategory, double> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride:
          $SyncValueProvider<Map<TransactionCategory, double>>(value),
    );
  }
}

String _$transactionsByCategoryHash() =>
    r'e0a68d76f993db7c80579cf6a9f6048836349351';

@ProviderFor(userTransactionsForAnalytics)
final userTransactionsForAnalyticsProvider =
    UserTransactionsForAnalyticsFamily._();

final class UserTransactionsForAnalyticsProvider extends $FunctionalProvider<
    List<Transaction>,
    List<Transaction>,
    List<Transaction>> with $Provider<List<Transaction>> {
  UserTransactionsForAnalyticsProvider._(
      {required UserTransactionsForAnalyticsFamily super.from,
      required String? super.argument})
      : super(
          retry: null,
          name: r'userTransactionsForAnalyticsProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$userTransactionsForAnalyticsHash();

  @override
  String toString() {
    return r'userTransactionsForAnalyticsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<List<Transaction>> $createElement(
          $ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  List<Transaction> create(Ref ref) {
    final argument = this.argument as String?;
    return userTransactionsForAnalytics(
      ref,
      argument,
    );
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<Transaction> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<Transaction>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is UserTransactionsForAnalyticsProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$userTransactionsForAnalyticsHash() =>
    r'2eda91711ff32dcbc6597812c14b1bb83496bf3a';

final class UserTransactionsForAnalyticsFamily extends $Family
    with $FunctionalFamilyOverride<List<Transaction>, String?> {
  UserTransactionsForAnalyticsFamily._()
      : super(
          retry: null,
          name: r'userTransactionsForAnalyticsProvider',
          dependencies: null,
          $allTransitiveDependencies: null,
          isAutoDispose: true,
        );

  UserTransactionsForAnalyticsProvider call(
    String? userId,
  ) =>
      UserTransactionsForAnalyticsProvider._(argument: userId, from: this);

  @override
  String toString() => r'userTransactionsForAnalyticsProvider';
}
