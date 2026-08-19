import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/supabase_provider.dart';

enum AuthStatus { loading, authenticated, unauthenticated }

class InactiveAccountException implements Exception {
  const InactiveAccountException();

  @override
  String toString() => 'This account is inactive.';
}

abstract interface class UserAccessProfileReader {
  Future<bool> isActive(String userId);
}

abstract interface class AuthSessionAccess {
  String? get currentUserId;
  Future<void> signOut();
}

class _SupabaseUserAccessProfileReader implements UserAccessProfileReader {
  const _SupabaseUserAccessProfileReader(this._client);
  final SupabaseClient _client;

  @override
  Future<bool> isActive(String userId) async {
    final value = await _client.rpc('current_user_is_active');
    if (value is! bool) {
      throw StateError('The current account profile is unavailable.');
    }
    return value;
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
    final isActive = await ref
        .read(userAccessProfileReaderProvider)
        .isActive(userId);
    if (!isActive) {
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
