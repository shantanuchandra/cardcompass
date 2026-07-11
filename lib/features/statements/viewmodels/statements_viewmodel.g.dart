// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'statements_viewmodel.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(StatementsViewModel)
final statementsViewModelProvider = StatementsViewModelProvider._();

final class StatementsViewModelProvider
    extends $NotifierProvider<StatementsViewModel, StatementsViewState> {
  StatementsViewModelProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'statementsViewModelProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$statementsViewModelHash();

  @$internal
  @override
  StatementsViewModel create() => StatementsViewModel();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(StatementsViewState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<StatementsViewState>(value),
    );
  }
}

String _$statementsViewModelHash() =>
    r'd0db9c8d440611b4b477b1036618ad4b0a35fdeb';

abstract class _$StatementsViewModel extends $Notifier<StatementsViewState> {
  StatementsViewState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<StatementsViewState, StatementsViewState>;
    final element = ref.element as $ClassProviderElement<
        AnyNotifier<StatementsViewState, StatementsViewState>,
        StatementsViewState,
        Object?,
        Object?>;
    return element.handleCreate(ref, build);
  }
}
