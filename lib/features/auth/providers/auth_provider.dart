import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import 'package:flutter/foundation.dart';
import '../../../shared/models/user.dart';

part 'auth_provider.g.dart';

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
    state = const AuthState.loading();
    try {
      final user = await _authService.getCurrentUser();
      if (user != null) {
        state = AuthState.authenticated(user);
      } else {
        state = const AuthState.unauthenticated();
      }
    } catch (e) {
      state = AuthState.error(e.toString());
    }
  }

  Future<void> signInWithGoogle() async {
    state = const AuthState.loading();
    try {
      final user = await _authService.signInWithGoogle();
      if (user != null) {
        state = AuthState.authenticated(user);
      } else {
        state = const AuthState.unauthenticated();
      }
    } catch (e) {
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
    state = AuthState.authenticated(guestUser);
  }

  Future<void> signOut() async {
    final isGuest = state.user?.id == 'guest';
    if (isGuest) {
      state = const AuthState.unauthenticated();
      return;
    }
    try {
      await _authService.signOut();
      state = const AuthState.unauthenticated();
    } catch (e) {
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
        // For web: explicitly set redirectTo so Supabase returns to the same origin (localhost/dev or prod)
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
  }

  Future<User?> getCurrentUser() async {
    final session = _supabase.auth.currentSession;
    if (session?.user != null) {
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
