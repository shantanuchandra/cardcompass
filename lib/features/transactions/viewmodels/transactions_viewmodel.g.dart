// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'transactions_viewmodel.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Transactions view model

@ProviderFor(TransactionsViewModelController)
final transactionsViewModelControllerProvider =
    TransactionsViewModelControllerProvider._();

/// Transactions view model
final class TransactionsViewModelControllerProvider extends $NotifierProvider<
    TransactionsViewModelController, TransactionsViewState> {
  /// Transactions view model
  TransactionsViewModelControllerProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'transactionsViewModelControllerProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$transactionsViewModelControllerHash();

  @$internal
  @override
  TransactionsViewModelController create() => TransactionsViewModelController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TransactionsViewState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TransactionsViewState>(value),
    );
  }
}

String _$transactionsViewModelControllerHash() =>
    r'0b0da62df1a10e09071f0f6c1bf5656f472144e5';

/// Transactions view model

abstract class _$TransactionsViewModelController
    extends $Notifier<TransactionsViewState> {
  TransactionsViewState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<TransactionsViewState, TransactionsViewState>;
    final element = ref.element as $ClassProviderElement<
        AnyNotifier<TransactionsViewState, TransactionsViewState>,
        TransactionsViewState,
        Object?,
        Object?>;
    return element.handleCreate(ref, build);
  }
}

/// Provider for transactions repository

@ProviderFor(transactionsRepository)
final transactionsRepositoryProvider = TransactionsRepositoryProvider._();

/// Provider for transactions repository

final class TransactionsRepositoryProvider extends $FunctionalProvider<
    TransactionsRepository,
    TransactionsRepository,
    TransactionsRepository> with $Provider<TransactionsRepository> {
  /// Provider for transactions repository
  TransactionsRepositoryProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'transactionsRepositoryProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$transactionsRepositoryHash();

  @$internal
  @override
  $ProviderElement<TransactionsRepository> $createElement(
          $ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  TransactionsRepository create(Ref ref) {
    return transactionsRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TransactionsRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TransactionsRepository>(value),
    );
  }
}

String _$transactionsRepositoryHash() =>
    r'f8dc23141c69c00849d9b3db3cabd39a173e25f9';
