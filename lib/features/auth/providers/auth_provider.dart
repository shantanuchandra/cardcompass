import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/supabase_provider.dart';
import '../../../core/env/env.dart';

enum AuthStatus { loading, authenticated, unauthenticated }

class AuthNotifier extends AsyncNotifier<AuthStatus> {
  @override
  Future<AuthStatus> build() async {
    ref.watch(authStateProvider);
    final user = ref.read(supabaseClientProvider).auth.currentUser;
    return user != null ? AuthStatus.authenticated : AuthStatus.unauthenticated;
  }

  Future<void> signInWithGoogle() async {
    state = const AsyncValue.loading();
    try {
      final googleSignIn = GoogleSignIn(
        clientId: Env.googleClientId,
        scopes: const [
          'email',
          'profile',
          'https://www.googleapis.com/auth/gmail.readonly',
        ],
      );
      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        state = const AsyncValue.data(AuthStatus.unauthenticated);
        return;
      }
      final googleAuth = await googleUser.authentication;
      await ref.read(supabaseClientProvider).auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: googleAuth.idToken!,
        accessToken: googleAuth.accessToken,
      );
      state = const AsyncValue.data(AuthStatus.authenticated);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> signOut() async {
    await GoogleSignIn().signOut();
    await ref.read(supabaseClientProvider).auth.signOut();
    state = const AsyncValue.data(AuthStatus.unauthenticated);
  }
}

final authNotifierProvider = AsyncNotifierProvider<AuthNotifier, AuthStatus>(AuthNotifier.new);
