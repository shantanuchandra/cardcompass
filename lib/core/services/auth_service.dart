import 'package:cardcompass/shared/models/user.dart';

/// Service interface for authentication operations
abstract class AuthService {
  /// Get current authenticated user
  User? get currentUser;

  Future<User?> getCurrentUser();
  /// Sign in with Google
  Future<User?> signInWithGoogle();

  /// Sign in with email and password
  Future<User?> signInWithEmail(String email, String password);

  /// Sign up with email and password
  Future<User?> signUpWithEmail(String email, String password, String fullName);

  /// Sign in as guest
  Future<User?> signInAsGuest();

  /// Sign out current user
  Future<void> signOut();

  /// Check if user is authenticated
  bool isAuthenticated();
  /// Update user profile
  Future<User?> updateUserProfile({
    required String userId,
    String? name,
    String? email,
    String? photoUrl,
    String? fullName,
    String? phoneNumber,
    DateTime? dateOfBirth,
    double? annualIncome,
    int? creditScore,
    String? occupation,
    String? city,
  });

  /// Delete user account
  Future<void> deleteAccount(String userId);

  /// Get user preferences
  Future<Map<String, dynamic>> getUserPreferences(String userId);

  /// Update user preferences
  Future<void> updateUserPreferences({
    required String userId,
    required Map<String, dynamic> preferences,
  });

  /// Stream of authentication state changes
  Stream<User?> get authStateChanges;
}
