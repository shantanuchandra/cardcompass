import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:cardcompass/shared/models/user.dart';
import 'package:cardcompass/core/services/auth_service.dart';
import 'package:cardcompass/core/services/storage_service.dart';

// AuthState represents the current authentication state
class AuthState {
  final User? user;
  final bool isLoading;
  final String? error;
  final bool isAuthenticated;

  const AuthState({
    this.user,
    this.isLoading = false,
    this.error,
    this.isAuthenticated = false,
  });

  AuthState copyWith({
    User? user,
    bool? isLoading,
    String? error,
    bool? isAuthenticated,
  }) {
    return AuthState(
      user: user ?? this.user,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
    );
  }
}

// AuthViewModel manages authentication state and operations
class AuthViewModel extends StateNotifier<AuthState> {
  final AuthService _authService;
  final StorageService _storageService;

  AuthViewModel(this._authService, this._storageService) : super(const AuthState()) {
    _initializeAuth();
  }

  // Initialize authentication state
  Future<void> _initializeAuth() async {
    state = state.copyWith(isLoading: true);
    
    try {
      // Check if user is already logged in
      final user = await _authService.getCurrentUser();
      if (user != null) {
        state = state.copyWith(
          user: user,
          isAuthenticated: true,
          isLoading: false,
        );
      } else {
        state = state.copyWith(isLoading: false);
      }
    } catch (error) {
      state = state.copyWith(
        error: error.toString(),
        isLoading: false,
      );
    }
  }

  // Sign in with Google
  Future<bool> signInWithGoogle() async {
    state = state.copyWith(isLoading: true, error: null);
    
    try {
      final user = await _authService.signInWithGoogle();
      if (user != null) {
        await _storageService.saveUser(user);
        state = state.copyWith(
          user: user,
          isAuthenticated: true,
          isLoading: false,
        );
        return true;
      } else {
        state = state.copyWith(
          error: 'Failed to sign in with Google',
          isLoading: false,
        );
        return false;
      }
    } catch (error) {
      state = state.copyWith(
        error: error.toString(),
        isLoading: false,
      );
      return false;
    }
  }

  // Sign in with email and password
  Future<bool> signInWithEmail(String email, String password) async {
    state = state.copyWith(isLoading: true, error: null);
    
    try {
      final user = await _authService.signInWithEmail(email, password);
      if (user != null) {
        await _storageService.saveUser(user);
        state = state.copyWith(
          user: user,
          isAuthenticated: true,
          isLoading: false,
        );
        return true;
      } else {
        state = state.copyWith(
          error: 'Invalid email or password',
          isLoading: false,
        );
        return false;
      }
    } catch (error) {
      state = state.copyWith(
        error: error.toString(),
        isLoading: false,
      );
      return false;
    }
  }

  // Sign up with email and password
  Future<bool> signUpWithEmail(String email, String password, String fullName) async {
    state = state.copyWith(isLoading: true, error: null);
    
    try {
      final user = await _authService.signUpWithEmail(email, password, fullName);
      if (user != null) {
        await _storageService.saveUser(user);
        state = state.copyWith(
          user: user,
          isAuthenticated: true,
          isLoading: false,
        );
        return true;
      } else {
        state = state.copyWith(
          error: 'Failed to create account',
          isLoading: false,
        );
        return false;
      }
    } catch (error) {
      state = state.copyWith(
        error: error.toString(),
        isLoading: false,
      );
      return false;
    }
  }

  // Sign out
  Future<void> signOut() async {
    state = state.copyWith(isLoading: true);
    
    try {
      await _authService.signOut();
      await _storageService.clearUser();
      state = const AuthState();
    } catch (error) {
      state = state.copyWith(
        error: error.toString(),
        isLoading: false,
      );
    }
  }

  // Update user profile
  Future<bool> updateProfile({
    String? fullName,
    String? phoneNumber,
    DateTime? dateOfBirth,
    double? annualIncome,
    int? creditScore,
    String? occupation,
    String? city,
  }) async {
    if (state.user == null) return false;
    
    state = state.copyWith(isLoading: true, error: null);
    
    try {
      final updatedUser = await _authService.updateUserProfile(
        userId: state.user!.id,
        fullName: fullName,
        phoneNumber: phoneNumber,
        dateOfBirth: dateOfBirth,
        annualIncome: annualIncome,
        creditScore: creditScore,
        occupation: occupation,
        city: city,
      );
      
      if (updatedUser != null) {
        await _storageService.saveUser(updatedUser);
        state = state.copyWith(
          user: updatedUser,
          isLoading: false,
        );
        return true;
      } else {
        state = state.copyWith(
          error: 'Failed to update profile',
          isLoading: false,
        );
        return false;
      }
    } catch (error) {
      state = state.copyWith(
        error: error.toString(),
        isLoading: false,
      );
      return false;
    }
  }

  // Clear error
  void clearError() {
    state = state.copyWith(error: null);
  }

  // Check if user profile is complete
  bool get isProfileComplete {
    final user = state.user;
    if (user == null) return false;
    
    return user.fullName != null &&
           user.phoneNumber != null &&
           user.dateOfBirth != null &&
           user.annualIncome != null &&
           user.occupation != null &&
           user.city != null;
  }

  // Get user display name
  String get userDisplayName {
    final user = state.user;
    if (user?.fullName != null && user!.fullName!.isNotEmpty) {
      return user.fullName!;
    }
    return user?.email ?? 'User';
  }
}

// Provider for AuthViewModel
final authViewModelProvider = StateNotifierProvider<AuthViewModel, AuthState>((ref) {
  final authService = ref.watch(authServiceProvider);
  final storageService = ref.watch(storageServiceProvider);
  return AuthViewModel(authService, storageService);
});

// Provider for AuthService (to be defined in services)
final authServiceProvider = Provider<AuthService>((ref) {
  throw UnimplementedError('AuthService provider not implemented');
});

// Provider for StorageService (to be defined in services)
final storageServiceProvider = Provider<StorageService>((ref) {
  throw UnimplementedError('StorageService provider not implemented');
});
