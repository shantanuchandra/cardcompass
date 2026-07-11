// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'benefits_viewmodel.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(supabaseBenefitsRepository)
final supabaseBenefitsRepositoryProvider =
    SupabaseBenefitsRepositoryProvider._();

final class SupabaseBenefitsRepositoryProvider extends $FunctionalProvider<
    SupabaseBenefitsRepository,
    SupabaseBenefitsRepository,
    SupabaseBenefitsRepository> with $Provider<SupabaseBenefitsRepository> {
  SupabaseBenefitsRepositoryProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'supabaseBenefitsRepositoryProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$supabaseBenefitsRepositoryHash();

  @$internal
  @override
  $ProviderElement<SupabaseBenefitsRepository> $createElement(
          $ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  SupabaseBenefitsRepository create(Ref ref) {
    return supabaseBenefitsRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SupabaseBenefitsRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SupabaseBenefitsRepository>(value),
    );
  }
}

String _$supabaseBenefitsRepositoryHash() =>
    r'f42fc3479ad78b4aadc627a728ef062051f960cc';

@ProviderFor(supabaseBenefitTrackingRepository)
final supabaseBenefitTrackingRepositoryProvider =
    SupabaseBenefitTrackingRepositoryProvider._();

final class SupabaseBenefitTrackingRepositoryProvider
    extends $FunctionalProvider<SupabaseBenefitTrackingRepository,
        SupabaseBenefitTrackingRepository, SupabaseBenefitTrackingRepository>
    with $Provider<SupabaseBenefitTrackingRepository> {
  SupabaseBenefitTrackingRepositoryProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'supabaseBenefitTrackingRepositoryProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() =>
      _$supabaseBenefitTrackingRepositoryHash();

  @$internal
  @override
  $ProviderElement<SupabaseBenefitTrackingRepository> $createElement(
          $ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  SupabaseBenefitTrackingRepository create(Ref ref) {
    return supabaseBenefitTrackingRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SupabaseBenefitTrackingRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride:
          $SyncValueProvider<SupabaseBenefitTrackingRepository>(value),
    );
  }
}

String _$supabaseBenefitTrackingRepositoryHash() =>
    r'106e931dff8e0679ea7fd9b03958e9eeebba5515';

@ProviderFor(BenefitsViewModel)
final benefitsViewModelProvider = BenefitsViewModelProvider._();

final class BenefitsViewModelProvider
    extends $NotifierProvider<BenefitsViewModel, BenefitsViewState> {
  BenefitsViewModelProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'benefitsViewModelProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$benefitsViewModelHash();

  @$internal
  @override
  BenefitsViewModel create() => BenefitsViewModel();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BenefitsViewState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BenefitsViewState>(value),
    );
  }
}

String _$benefitsViewModelHash() => r'e0a733ab1916730293c26e93b7190caa626ed4cc';

abstract class _$BenefitsViewModel extends $Notifier<BenefitsViewState> {
  BenefitsViewState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<BenefitsViewState, BenefitsViewState>;
    final element = ref.element as $ClassProviderElement<
        AnyNotifier<BenefitsViewState, BenefitsViewState>,
        BenefitsViewState,
        Object?,
        Object?>;
    return element.handleCreate(ref, build);
  }
}
