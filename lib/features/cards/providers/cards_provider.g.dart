// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cards_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(CardsNotifier)
final cardsProvider = CardsNotifierProvider._();

final class CardsNotifierProvider
    extends $NotifierProvider<CardsNotifier, List<CreditCard>> {
  CardsNotifierProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'cardsProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$cardsNotifierHash();

  @$internal
  @override
  CardsNotifier create() => CardsNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<CreditCard> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<CreditCard>>(value),
    );
  }
}

String _$cardsNotifierHash() => r'664faa2271b99653ed6bb09505c549280b29381c';

abstract class _$CardsNotifier extends $Notifier<List<CreditCard>> {
  List<CreditCard> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<List<CreditCard>, List<CreditCard>>;
    final element = ref.element as $ClassProviderElement<
        AnyNotifier<List<CreditCard>, List<CreditCard>>,
        List<CreditCard>,
        Object?,
        Object?>;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(activeCards)
final activeCardsProvider = ActiveCardsProvider._();

final class ActiveCardsProvider extends $FunctionalProvider<List<CreditCard>,
    List<CreditCard>, List<CreditCard>> with $Provider<List<CreditCard>> {
  ActiveCardsProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'activeCardsProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$activeCardsHash();

  @$internal
  @override
  $ProviderElement<List<CreditCard>> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  List<CreditCard> create(Ref ref) {
    return activeCards(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<CreditCard> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<CreditCard>>(value),
    );
  }
}

String _$activeCardsHash() => r'd044f37db8b1908f756ca8c6ebe306d5e316c987';

@ProviderFor(totalCreditLimit)
final totalCreditLimitProvider = TotalCreditLimitProvider._();

final class TotalCreditLimitProvider
    extends $FunctionalProvider<double, double, double> with $Provider<double> {
  TotalCreditLimitProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'totalCreditLimitProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$totalCreditLimitHash();

  @$internal
  @override
  $ProviderElement<double> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  double create(Ref ref) {
    return totalCreditLimit(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(double value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<double>(value),
    );
  }
}

String _$totalCreditLimitHash() => r'714bd6908873c3f69a54bfa40fa066fbe76b0e70';

@ProviderFor(cardsCount)
final cardsCountProvider = CardsCountProvider._();

final class CardsCountProvider extends $FunctionalProvider<int, int, int>
    with $Provider<int> {
  CardsCountProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'cardsCountProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$cardsCountHash();

  @$internal
  @override
  $ProviderElement<int> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  int create(Ref ref) {
    return cardsCount(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(int value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<int>(value),
    );
  }
}

String _$cardsCountHash() => r'7a70296cb8a31ed716358849e36545c2be3a8f5d';

@ProviderFor(userCardsForAnalytics)
final userCardsForAnalyticsProvider = UserCardsForAnalyticsFamily._();

final class UserCardsForAnalyticsProvider extends $FunctionalProvider<
    List<CreditCard>,
    List<CreditCard>,
    List<CreditCard>> with $Provider<List<CreditCard>> {
  UserCardsForAnalyticsProvider._(
      {required UserCardsForAnalyticsFamily super.from,
      required String? super.argument})
      : super(
          retry: null,
          name: r'userCardsForAnalyticsProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$userCardsForAnalyticsHash();

  @override
  String toString() {
    return r'userCardsForAnalyticsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<List<CreditCard>> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  List<CreditCard> create(Ref ref) {
    final argument = this.argument as String?;
    return userCardsForAnalytics(
      ref,
      argument,
    );
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<CreditCard> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<CreditCard>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is UserCardsForAnalyticsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$userCardsForAnalyticsHash() =>
    r'69dd85a9c4fdf8839172df1e81e86b97b9a96870';

final class UserCardsForAnalyticsFamily extends $Family
    with $FunctionalFamilyOverride<List<CreditCard>, String?> {
  UserCardsForAnalyticsFamily._()
      : super(
          retry: null,
          name: r'userCardsForAnalyticsProvider',
          dependencies: null,
          $allTransitiveDependencies: null,
          isAutoDispose: true,
        );

  UserCardsForAnalyticsProvider call(
    String? userId,
  ) =>
      UserCardsForAnalyticsProvider._(argument: userId, from: this);

  @override
  String toString() => r'userCardsForAnalyticsProvider';
}

/// Async provider that fetches the sum of available_credit from the most recent
/// statement per user card. Falls back to 0 if no statements are found.

@ProviderFor(availableCredit)
final availableCreditProvider = AvailableCreditProvider._();

/// Async provider that fetches the sum of available_credit from the most recent
/// statement per user card. Falls back to 0 if no statements are found.

final class AvailableCreditProvider
    extends $FunctionalProvider<AsyncValue<double>, double, FutureOr<double>>
    with $FutureModifier<double>, $FutureProvider<double> {
  /// Async provider that fetches the sum of available_credit from the most recent
  /// statement per user card. Falls back to 0 if no statements are found.
  AvailableCreditProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'availableCreditProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$availableCreditHash();

  @$internal
  @override
  $FutureProviderElement<double> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<double> create(Ref ref) {
    return availableCredit(ref);
  }
}

String _$availableCreditHash() => r'36371c029817bd9fba29f944401a64043f060761';

/// Async provider that fetches total rewards_earned from the most recent
/// statement per user card (statement-level rewards, as opposed to per-tx rewards).

@ProviderFor(statementRewardsTotal)
final statementRewardsTotalProvider = StatementRewardsTotalProvider._();

/// Async provider that fetches total rewards_earned from the most recent
/// statement per user card (statement-level rewards, as opposed to per-tx rewards).

final class StatementRewardsTotalProvider
    extends $FunctionalProvider<AsyncValue<double>, double, FutureOr<double>>
    with $FutureModifier<double>, $FutureProvider<double> {
  /// Async provider that fetches total rewards_earned from the most recent
  /// statement per user card (statement-level rewards, as opposed to per-tx rewards).
  StatementRewardsTotalProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'statementRewardsTotalProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$statementRewardsTotalHash();

  @$internal
  @override
  $FutureProviderElement<double> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<double> create(Ref ref) {
    return statementRewardsTotal(ref);
  }
}

String _$statementRewardsTotalHash() =>
    r'3f826d3e57002b9e1806819ee7cbc4a599fe0157';
