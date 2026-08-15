import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/supabase_provider.dart';

enum AuthStatus { loading, authenticated, unauthenticated }

/// Supabase must redirect back to the deployed Flutter base, not the public
/// landing root. The origin itself remains subject to Supabase's redirect URL
/// allow-list in every environment.
Uri oauthRedirectUri(Uri current) {
  final production =
      current.scheme == 'https' && current.host == 'cardcompass.in';
  final local =
      (current.scheme == 'http' || current.scheme == 'https') &&
      (current.host == '127.0.0.1' || current.host == 'localhost');
  if (!production && !local) {
    throw StateError('OAuth redirect origin is not allow-listed.');
  }
  return Uri(
    scheme: current.scheme,
    host: current.host,
    port: current.hasPort ? current.port : null,
    path: '/app/',
  );
}

class AuthNotifier extends AsyncNotifier<AuthStatus> {
  @override
  Future<AuthStatus> build() async {
    ref.watch(authStateProvider);
    final user = ref.read(supabaseClientProvider).auth.currentUser;
    return user != null ? AuthStatus.authenticated : AuthStatus.unauthenticated;
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
    await ref.read(supabaseClientProvider).auth.signOut();
    state = const AsyncValue.data(AuthStatus.unauthenticated);
  }
}

final authNotifierProvider = AsyncNotifierProvider<AuthNotifier, AuthStatus>(
  AuthNotifier.new,
);
