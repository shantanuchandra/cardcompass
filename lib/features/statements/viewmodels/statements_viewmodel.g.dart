// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'statements_viewmodel.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(StatementsViewModelController)
final statementsViewModelControllerProvider =
    StatementsViewModelControllerProvider._();

final class StatementsViewModelControllerProvider extends $NotifierProvider<
    StatementsViewModelController, StatementsViewState> {
  StatementsViewModelControllerProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'statementsViewModelControllerProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$statementsViewModelControllerHash();

  @$internal
  @override
  StatementsViewModelController create() => StatementsViewModelController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(StatementsViewState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<StatementsViewState>(value),
    );
  }
}

String _$statementsViewModelControllerHash() =>
    r'3bf1963760277094d1a74f52ef83ad1d7b918ec4';

abstract class _$StatementsViewModelController
    extends $Notifier<StatementsViewState> {
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
