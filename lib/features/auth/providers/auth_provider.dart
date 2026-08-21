import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/supabase_provider.dart';

enum AuthStatus { loading, authenticated, unauthenticated }

/// Riverpod preserves the previous value while an async dependency refreshes,
/// which makes `isLoading` true even though an authorization decision is
/// already available. Only the initial value-less load should block routing or
/// disable sign-in controls.
bool authStatusIsPending(AsyncValue<AuthStatus> auth) =>
    auth.isLoading && !auth.hasValue;

class InactiveAccountException implements Exception {
  const InactiveAccountException();

  @override
  String toString() => 'This account is inactive.';
}

class MissingAccessProfileException implements Exception {
  const MissingAccessProfileException();
}

class AuthIdentityChangedException implements Exception {
  const AuthIdentityChangedException();
}

enum UserAccessProfileState { active, inactive, missing }

abstract interface class UserAccessProfileReader {
  Future<UserAccessProfileState> read(String userId);
}

abstract interface class AuthSessionAccess {
  String? get currentUserId;
  Future<void> signOut();
}

class _SupabaseUserAccessProfileReader implements UserAccessProfileReader {
  const _SupabaseUserAccessProfileReader(this._client);
  final SupabaseClient _client;

  @override
  Future<UserAccessProfileState> read(String userId) async {
    if (_client.auth.currentUser?.id != userId) {
      throw const AuthIdentityChangedException();
    }
    final response = await _client.rpc('current_user_access_profile_state');
    return switch (response) {
      'active' => UserAccessProfileState.active,
      'inactive' => UserAccessProfileState.inactive,
      'missing' => UserAccessProfileState.missing,
      _ => throw StateError('The current account profile is unavailable.'),
    };
  }
}

class _SupabaseAuthSessionAccess implements AuthSessionAccess {
  const _SupabaseAuthSessionAccess(this._client);
  final SupabaseClient _client;

  @override
  String? get currentUserId => _client.auth.currentUser?.id;

  @override
  Future<void> signOut() => _client.auth.signOut();
}

final authSessionAccessProvider = Provider<AuthSessionAccess>((ref) {
  ref.watch(authStateProvider);
  return _SupabaseAuthSessionAccess(ref.watch(supabaseClientProvider));
});

final userAccessProfileReaderProvider = Provider<UserAccessProfileReader>(
  (ref) => _SupabaseUserAccessProfileReader(ref.watch(supabaseClientProvider)),
);

/// Supabase must redirect back to the deployed Flutter base, not the public
/// landing root. The origin itself remains subject to Supabase's redirect URL
/// allow-list in every environment.
Uri oauthRedirectUri(Uri current) {
  final production =
      current.scheme == 'https' &&
      (current.host == 'cardcompass.in' ||
          current.host == 'www.cardcompass.in');
  final local =
      (current.scheme == 'http' || current.scheme == 'https') &&
      (current.host == '127.0.0.1' || current.host == 'localhost');
  if (!production && !local) {
    throw StateError('OAuth redirect origin is not allow-listed.');
  }
  return Uri(
    scheme: current.scheme,
    // PKCE stores its verifier per browser origin. Keep a trusted production
    // host unchanged so the callback can read the verifier created at sign-in.
    host: current.host,
    port: current.hasPort ? current.port : null,
    path: '/app/',
  );
}

class AuthNotifier extends AsyncNotifier<AuthStatus> {
  @override
  Future<AuthStatus> build() async {
    final session = ref.watch(authSessionAccessProvider);
    final userId = session.currentUserId;
    if (userId == null) return AuthStatus.unauthenticated;
    final profile = await ref
        .read(userAccessProfileReaderProvider)
        .read(userId);
    if (session.currentUserId != userId) {
      throw const AuthIdentityChangedException();
    }
    if (profile == UserAccessProfileState.missing) {
      throw const MissingAccessProfileException();
    }
    if (profile == UserAccessProfileState.inactive) {
      if (session.currentUserId != userId) {
        throw const AuthIdentityChangedException();
      }
      await session.signOut();
      throw const InactiveAccountException();
    }
    return AuthStatus.authenticated;
  }

  // Uses Supabase's own redirect-based OAuth rather than the google_sign_in
  // package. google_sign_in_web's popup flow (GIS-based) does not reliably
  // return an ID token on web, which signInWithIdToken requires. Gmail scope
  // is requested upfront since it's needed later for statement import.
  Future<void> signInWithGoogle() async {
    state = const AsyncValue.loading();
    try {
      await ref
          .read(supabaseClientProvider)
          .auth
          .signInWithOAuth(
            OAuthProvider.google,
            redirectTo: oauthRedirectUri(Uri.base).toString(),
            scopes:
                'email profile https://www.googleapis.com/auth/gmail.readonly '
                'https://www.googleapis.com/auth/user.birthday.read',
            queryParams: const {'access_type': 'offline', 'prompt': 'consent'},
          );
      // Auth state resolves via the onAuthStateChange stream after Supabase
      // redirects back with the session; authStateProvider triggers a rebuild.
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> signOut() async {
    await ref.read(authSessionAccessProvider).signOut();
    state = const AsyncValue.data(AuthStatus.unauthenticated);
  }
}

final authNotifierProvider = AsyncNotifierProvider<AuthNotifier, AuthStatus>(
  AuthNotifier.new,
);
