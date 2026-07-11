// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'auth_viewmodel.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(AuthViewModelController)
final authViewModelControllerProvider = AuthViewModelControllerProvider._();

final class AuthViewModelControllerProvider
    extends $NotifierProvider<AuthViewModelController, AuthState> {
  AuthViewModelControllerProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'authViewModelControllerProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$authViewModelControllerHash();

  @$internal
  @override
  AuthViewModelController create() => AuthViewModelController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AuthState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AuthState>(value),
    );
  }
}

String _$authViewModelControllerHash() =>
    r'e6f4b82c71db9145398320d2e450634f72a9d7ba';

abstract class _$AuthViewModelController extends $Notifier<AuthState> {
  AuthState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AuthState, AuthState>;
    final element = ref.element as $ClassProviderElement<
        AnyNotifier<AuthState, AuthState>, AuthState, Object?, Object?>;
    return element.handleCreate(ref, build);
  }
}
