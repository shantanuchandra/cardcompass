import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import 'package:supabase_flutter/supabase_flutter.dart' as supabase show User;
import 'package:flutter/foundation.dart';
import 'package:cardcompass/shared/models/user.dart';
import 'package:cardcompass/core/services/auth_service.dart';

/// Implementation of authentication service using Supabase
class AuthServiceImpl implements AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;

  @override
  User? get currentUser {
    final supabaseUser = _supabase.auth.currentUser;
    if (supabaseUser != null) {
      return _mapSupabaseUserToAppUser(supabaseUser);
    }
    return null;
  }

  @override
  Future<User?> getCurrentUser() async {
    try {
      final session = _supabase.auth.currentSession;
      if (session?.user != null) {
        return _mapSupabaseUserToAppUser(session!.user);
      }
      return null;
    } catch (error) {
      throw Exception('Failed to get current user: $error');
    }
  }  @override
  Future<User?> signInWithGoogle() async {
    try {
      // Use Supabase OAuth for Google Sign-In
      final bool success = await _supabase.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: kIsWeb ? null : 'io.supabase.cardcompass://login-callback/',
      );

      if (success) {
        // For web, the OAuth flow will redirect to the callback URL
        // Check for current user after redirect
        final currentUser = _supabase.auth.currentUser;
        if (currentUser != null) {
          final user = _mapSupabaseUserToAppUser(currentUser);
          
          // Create or update user profile in our database
          await _createOrUpdateUserProfile(user);
          
          return user;
        }
      }
      
      // For web, return null as the auth state will be handled by the redirect
      return null;
    } catch (error) {
      throw Exception('Failed to sign in with Google: $error');
    }
  }

  @override
  Future<User?> signInWithEmail(String email, String password) async {
    try {
      final AuthResponse response = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (response.user != null) {
        return _mapSupabaseUserToAppUser(response.user!);
      }
      return null;
    } catch (error) {
      throw Exception('Failed to sign in with email: $error');
    }
  }

  @override
  Future<User?> signUpWithEmail(String email, String password, String fullName) async {
    try {
      final AuthResponse response = await _supabase.auth.signUp(
        email: email,
        password: password,
        data: {'full_name': fullName},
      );

      if (response.user != null) {
        final user = _mapSupabaseUserToAppUser(response.user!);
        
        // Create user profile in our database
        await _createOrUpdateUserProfile(user);
        
        return user;
      }
      return null;
    } catch (error) {
      throw Exception('Failed to sign up with email: $error');
    }
  }

  @override
  Future<User?> signInAsGuest() async {
    try {
      // Create a guest user session
      final guestUser = User(
        id: 'guest_${DateTime.now().millisecondsSinceEpoch}',
        email: 'guest@cardcompass.app',
        fullName: 'Guest User',
        createdAt: DateTime.now(),
      );
      
      // Store guest session locally but don't save to Supabase
      return guestUser;
    } catch (error) {
      throw Exception('Failed to sign in as guest: $error');
    }
  }
  @override
  Future<void> signOut() async {
    try {
      await _supabase.auth.signOut();
    } catch (error) {
      throw Exception('Failed to sign out: $error');
    }
  }

  @override
  bool isAuthenticated() {
    return _supabase.auth.currentUser != null;
  }

  @override
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
  }) async {
    try {
      final updateData = <String, dynamic>{};
      
      if (fullName != null) updateData['full_name'] = fullName;
      if (photoUrl != null) updateData['avatar_url'] = photoUrl;
      if (phoneNumber != null) updateData['phone_number'] = phoneNumber;
      if (dateOfBirth != null) updateData['date_of_birth'] = dateOfBirth.toIso8601String();
      if (annualIncome != null) updateData['annual_income'] = annualIncome;
      if (creditScore != null) updateData['credit_score'] = creditScore;
      if (occupation != null) updateData['occupation'] = occupation;
      if (city != null) updateData['city'] = city;

      // Update in Supabase auth if needed
      if (email != null || updateData.isNotEmpty) {
        await _supabase.auth.updateUser(
          UserAttributes(
            email: email,
            data: updateData,
          ),
        );
      }

      // Update in our users table
      await _supabase.from('users').update({
        ...updateData,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', userId);

      // Return updated user
      return getCurrentUser();
    } catch (error) {
      throw Exception('Failed to update user profile: $error');
    }
  }

  @override
  Future<void> deleteAccount(String userId) async {
    try {
      // Delete user data from our tables
      await _supabase.from('transactions').delete().eq('user_id', userId);
      await _supabase.from('user_cards').delete().eq('user_id', userId);
      await _supabase.from('users').delete().eq('id', userId);
      
      // Note: Deleting from Supabase auth might require admin privileges
      // For now, just sign out
      await signOut();
    } catch (error) {
      throw Exception('Failed to delete account: $error');
    }
  }

  @override
  Future<Map<String, dynamic>> getUserPreferences(String userId) async {
    try {
      final response = await _supabase
          .from('users')
          .select('preferences')
          .eq('id', userId)
          .single();
      
      return Map<String, dynamic>.from(response['preferences'] ?? {});
    } catch (error) {
      throw Exception('Failed to get user preferences: $error');
    }
  }

  @override
  Future<void> updateUserPreferences({
    required String userId,
    required Map<String, dynamic> preferences,
  }) async {
    try {
      await _supabase.from('users').update({
        'preferences': preferences,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', userId);
    } catch (error) {
      throw Exception('Failed to update user preferences: $error');
    }
  }

  @override
  Stream<User?> get authStateChanges {
    return _supabase.auth.onAuthStateChange.map((state) {
      if (state.session?.user != null) {
        return _mapSupabaseUserToAppUser(state.session!.user);
      }
      return null;
    });
  }

  /// Helper method to map Supabase user to our app user model
  User _mapSupabaseUserToAppUser(supabase.User supabaseUser) {
    return User(
      id: supabaseUser.id,
      email: supabaseUser.email ?? '',
      fullName: supabaseUser.userMetadata?['full_name'] ?? 'User',
      profileImage: supabaseUser.userMetadata?['avatar_url'],
      phoneNumber: supabaseUser.userMetadata?['phone_number'],
      dateOfBirth: supabaseUser.userMetadata?['date_of_birth'] != null 
          ? DateTime.tryParse(supabaseUser.userMetadata!['date_of_birth']) 
          : null,
      annualIncome: supabaseUser.userMetadata?['annual_income']?.toDouble(),
      creditScore: supabaseUser.userMetadata?['credit_score']?.toInt(),
      occupation: supabaseUser.userMetadata?['occupation'],
      city: supabaseUser.userMetadata?['city'],
      preferences: Map<String, dynamic>.from(supabaseUser.userMetadata?['preferences'] ?? {}),
      createdAt: DateTime.tryParse(supabaseUser.createdAt) ?? DateTime.now(),
    );
  }

  /// Helper method to create or update user profile in our database
  Future<void> _createOrUpdateUserProfile(User user) async {
    try {
      await _supabase.from('users').upsert({
        'id': user.id,
        'email': user.email,
        'full_name': user.fullName,
        'profile_image': user.profileImage,
        'phone_number': user.phoneNumber,
        'date_of_birth': user.dateOfBirth?.toIso8601String(),
        'annual_income': user.annualIncome,
        'credit_score': user.creditScore,
        'occupation': user.occupation,
        'city': user.city,
        'preferences': user.preferences,
        'is_premium': user.isPremium,
        'created_at': user.createdAt.toIso8601String(),
        'last_login_at': DateTime.now().toIso8601String(),
      });
    } catch (error) {      // Log error but don't throw - auth can succeed even if profile creation fails
      // TODO: Replace with proper logging in production
      debugPrint('Warning: Failed to create/update user profile: $error');
    }
  }
}
