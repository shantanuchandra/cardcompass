// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'transaction_advisor_viewmodel.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(TransactionAdvisorViewModel)
final transactionAdvisorViewModelProvider =
    TransactionAdvisorViewModelProvider._();

final class TransactionAdvisorViewModelProvider extends $NotifierProvider<
    TransactionAdvisorViewModel, TransactionAdvisorViewState> {
  TransactionAdvisorViewModelProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'transactionAdvisorViewModelProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$transactionAdvisorViewModelHash();

  @$internal
  @override
  TransactionAdvisorViewModel create() => TransactionAdvisorViewModel();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TransactionAdvisorViewState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TransactionAdvisorViewState>(value),
    );
  }
}

String _$transactionAdvisorViewModelHash() =>
    r'ba0923e216fed6dd688fdd9bba1d90693cb8bd33';

abstract class _$TransactionAdvisorViewModel
    extends $Notifier<TransactionAdvisorViewState> {
  TransactionAdvisorViewState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref
        as $Ref<TransactionAdvisorViewState, TransactionAdvisorViewState>;
    final element = ref.element as $ClassProviderElement<
        AnyNotifier<TransactionAdvisorViewState, TransactionAdvisorViewState>,
        TransactionAdvisorViewState,
        Object?,
        Object?>;
    return element.handleCreate(ref, build);
  }
}
