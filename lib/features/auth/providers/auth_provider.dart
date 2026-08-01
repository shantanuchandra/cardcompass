import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/supabase_provider.dart';

enum AuthStatus { loading, authenticated, unauthenticated }

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
      await ref.read(supabaseClientProvider).auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: Uri.base.origin,
        scopes: 'email profile https://www.googleapis.com/auth/gmail.readonly',
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

final authNotifierProvider = AsyncNotifierProvider<AuthNotifier, AuthStatus>(AuthNotifier.new);
