import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../shared/models/user.dart';

part 'auth_provider.g.dart';

/// SharedPreferences key used to persist the Google OAuth provider token on web.
/// The token is only available from the Supabase session immediately after the
/// OAuth redirect, so we cache it for use by the Gmail sync flow.
const String _kGoogleProviderTokenKey = 'google_provider_token';

@riverpod
AuthService authService(Ref ref) => AuthService();

@riverpod
class AuthNotifier extends _$AuthNotifier {
  late final AuthService _authService;

  @override
  AuthState build() {
    _authService = ref.watch(authServiceProvider);
    Future.microtask(() => _checkAuthState());
    return const AuthState.initial();
  }

  Future<void> _checkAuthState() async {
    print('🔑 AuthNotifier: _checkAuthState started');
    // Guard: provider may have already been rebuilt by the time we start
    if (!ref.mounted) return;
    state = const AuthState.loading();
    try {
      print('🔑 AuthNotifier: Fetching current user...');
      final user = await _authService.getCurrentUser()
          .timeout(const Duration(seconds: 6), onTimeout: () {
        print('🔑 AuthNotifier: getCurrentUser timed out, treating as unauthenticated');
        return null;
      });
      print('🔑 AuthNotifier: Current user: $user');
      // Guard: provider may have been rebuilt while waiting for the auth check
      if (!ref.mounted) return;
      if (user != null) {
        state = AuthState.authenticated(user);
      } else {
        state = const AuthState.unauthenticated();
      }
    } catch (e, stack) {
      print('🔑 AuthNotifier: Error in _checkAuthState: $e\n$stack');
      if (!ref.mounted) return;
      // Treat errors as unauthenticated so the user can still reach the login screen
      state = const AuthState.unauthenticated();
    }
  }

  Future<void> signInWithGoogle() async {
    if (!ref.mounted) return;
    state = const AuthState.loading();
    try {
      final user = await _authService.signInWithGoogle();
      if (!ref.mounted) return;
      if (user != null) {
        state = AuthState.authenticated(user);
      } else {
        state = const AuthState.unauthenticated();
      }
    } catch (e) {
      if (!ref.mounted) return;
      state = AuthState.error(e.toString());
    }
  }

  Future<void> signInAsGuest() async {
    // For demo purposes, create a guest user
    final guestUser = User(
      id: 'guest',
      email: 'guest@cardcompass.com',
      name: 'Guest User',
      createdAt: DateTime.now(),
      lastLoginAt: DateTime.now(),
    );
    if (!ref.mounted) return;
    state = AuthState.authenticated(guestUser);
  }

  Future<void> signOut() async {
    final isGuest = state.user?.id == 'guest';
    if (isGuest) {
      if (!ref.mounted) return;
      state = const AuthState.unauthenticated();
      return;
    }
    try {
      await _authService.signOut();
      if (!ref.mounted) return;
      state = const AuthState.unauthenticated();
    } catch (e) {
      if (!ref.mounted) return;
      state = AuthState.error(e.toString());
    }
  }

  Future<void> refreshAuthState() async {
    await _checkAuthState();
  }
}


// Alias to maintain compatibility with legacy code
final authStateProvider = authProvider;

class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<User?> signInWithGoogle() async {
    try {
      // Use Supabase OAuth for Google Sign-In
      final String? webRedirect = kIsWeb
          ? Uri.base.origin // preserve scheme+host+port, e.g., http://localhost:54321
          : null;

      final bool success = await _supabase.auth.signInWithOAuth(
        OAuthProvider.google,
        // Include Gmail scopes so the provider token can be reused for Gmail API
        // without a separate Google Sign-In flow on web
        scopes: [
          'email',
          'profile',
          'https://www.googleapis.com/auth/gmail.readonly',
          'https://www.googleapis.com/auth/gmail.modify',
          'https://www.googleapis.com/auth/user.birthday.read',
        ].join(' '),
        // For web: explicitly set redirectTo so Supabase returns to the same origin
        redirectTo: webRedirect ?? 'io.supabase.cardcompass://login-callback/',
      );

      if (success) {
        // For web, the OAuth flow will redirect to the callback URL
        // Check for current user after redirect
        final currentUser = _supabase.auth.currentUser;
        if (currentUser != null) {
          return User(
            id: currentUser.id,
            email: currentUser.email!,
            name: currentUser.userMetadata?['full_name'],
            profileImage: currentUser.userMetadata?['avatar_url'],
            createdAt: DateTime.parse(currentUser.createdAt),
            lastLoginAt: DateTime.now(),
          );
        }
      }
      
      // For web, return null as the auth state will be handled by the redirect
      return null;
    } catch (e) {
      throw AuthException('Failed to sign in with Google: $e');
    }
  }

  Future<void> signOut() async {
    await _supabase.auth.signOut();
    // Clear cached provider token so a new login gets fresh scopes
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kGoogleProviderTokenKey);
    }
  }

  Future<User?> getCurrentUser() async {
    print('🔑 AuthService: getCurrentUser started');
    try {
      final session = _supabase.auth.currentSession;
      print('🔑 AuthService: session: $session');
      if (session?.user != null) {
        // Persist the Google provider token whenever it's available.
        // On web, providerToken is only set right after the OAuth redirect;
        // caching it lets the Gmail sync flow use it on subsequent page loads.
        if (kIsWeb && session?.providerToken != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_kGoogleProviderTokenKey, session!.providerToken!);
          print('🔑 AuthService: Cached Google provider token to SharedPreferences');
        }
        return User(
          id: session!.user.id,
          email: session.user.email!,
          name: session.user.userMetadata?['full_name'],
          profileImage: session.user.userMetadata?['avatar_url'],
          createdAt: DateTime.parse(session.user.createdAt),
          lastLoginAt: DateTime.now(),
        );
      }
      return null;
    } catch (e) {
      print('🔑 AuthService: error getting current user: $e');
      rethrow;
    }
  }
}

class AuthState {
  const AuthState();

  const factory AuthState.initial() = _Initial;
  const factory AuthState.loading() = _Loading;
  const factory AuthState.authenticated(User user) = _Authenticated;
  const factory AuthState.unauthenticated() = _Unauthenticated;
  const factory AuthState.error(String message) = _Error;

  bool get isLoading => this is _Loading;
  bool get isAuthenticated => this is _Authenticated;
  bool get isUnauthenticated => this is _Unauthenticated;
  bool get hasError => this is _Error;

  User? get user => this is _Authenticated ? (this as _Authenticated).user : null;
  String? get error => this is _Error ? (this as _Error).message : null;
}

class _Initial extends AuthState {
  const _Initial();
}

class _Loading extends AuthState {
  const _Loading();
}

class _Authenticated extends AuthState {
  @override
  final User user;
  const _Authenticated(this.user);
}

class _Unauthenticated extends AuthState {
  const _Unauthenticated();
}

class _Error extends AuthState {
  final String message;
  const _Error(this.message);
}

class AuthException implements Exception {
  final String message;
  AuthException(this.message);

  @override
  String toString() => 'AuthException: $message';
}
