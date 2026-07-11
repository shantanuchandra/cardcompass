// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'dashboard_viewmodel.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(DashboardViewModel)
final dashboardViewModelProvider = DashboardViewModelProvider._();

final class DashboardViewModelProvider
    extends $NotifierProvider<DashboardViewModel, DashboardViewState> {
  DashboardViewModelProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'dashboardViewModelProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$dashboardViewModelHash();

  @$internal
  @override
  DashboardViewModel create() => DashboardViewModel();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DashboardViewState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DashboardViewState>(value),
    );
  }
}

String _$dashboardViewModelHash() =>
    r'8831dc90004df52feb928b858b4df134c56ce9d7';

abstract class _$DashboardViewModel extends $Notifier<DashboardViewState> {
  DashboardViewState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<DashboardViewState, DashboardViewState>;
    final element = ref.element as $ClassProviderElement<
        AnyNotifier<DashboardViewState, DashboardViewState>,
        DashboardViewState,
        Object?,
        Object?>;
    return element.handleCreate(ref, build);
  }
}
