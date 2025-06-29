import 'package:flutter/foundation.dart';
import 'package:cardcompass/core/services/user_profile_service.dart';

/// Implementation of user profile service using Supabase
class UserProfileServiceImpl implements UserProfileService {
  // In a real implementation, this would use Supabase client
  // For now, we'll use local storage and mock data with some persistence

  final Map<String, UserProfile> _profileCache = {};

  @override
  Future<UserProfile> getUserProfile(String userId) async {
    try {
      // Check cache first
      if (_profileCache.containsKey(userId)) {
        return _profileCache[userId]!;
      }

      // In production, this would fetch from Supabase
      // For now, return a profile with some default values but allow for updates
      final profile = UserProfile(
        userId: userId,
        name: null, // To be filled by user
        email: null, // To be filled by user
        annualIncome: null, // To be filled by user
        creditScore: null, // To be filled by user
        financialGoals: [],
        occupation: null,
        city: null,
        dateOfBirth: null,
        phoneNumber: null,
        preferences: {},
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      _profileCache[userId] = profile;
      return profile;
    } catch (error) {
      debugPrint('Error fetching user profile: $error');
      rethrow;
    }
  }

  @override
  Future<void> updateUserProfile(String userId, UserProfile profile) async {
    try {
      // Update cache
      _profileCache[userId] = profile.copyWith(updatedAt: DateTime.now());
      
      // In production, this would update Supabase
      debugPrint('User profile updated for $userId');
    } catch (error) {
      debugPrint('Error updating user profile: $error');
      rethrow;
    }
  }

  @override
  Future<double?> getUserIncome(String userId) async {
    try {
      final profile = await getUserProfile(userId);
      return profile.annualIncome;
    } catch (error) {
      debugPrint('Error fetching user income: $error');
      return null;
    }
  }

  @override
  Future<void> updateUserIncome(String userId, double income) async {
    try {
      final profile = await getUserProfile(userId);
      final updatedProfile = profile.copyWith(
        annualIncome: income,
        updatedAt: DateTime.now(),
      );
      await updateUserProfile(userId, updatedProfile);
    } catch (error) {
      debugPrint('Error updating user income: $error');
      rethrow;
    }
  }

  @override
  Future<int?> getUserCreditScore(String userId) async {
    try {
      final profile = await getUserProfile(userId);
      return profile.creditScore;
    } catch (error) {
      debugPrint('Error fetching user credit score: $error');
      return null;
    }
  }

  @override
  Future<void> updateUserCreditScore(String userId, int creditScore) async {
    try {
      final profile = await getUserProfile(userId);
      final updatedProfile = profile.copyWith(
        creditScore: creditScore,
        updatedAt: DateTime.now(),
      );
      await updateUserProfile(userId, updatedProfile);
    } catch (error) {
      debugPrint('Error updating user credit score: $error');
      rethrow;
    }
  }

  @override
  Future<List<String>> getUserFinancialGoals(String userId) async {
    try {
      final profile = await getUserProfile(userId);
      return profile.financialGoals;
    } catch (error) {
      debugPrint('Error fetching user financial goals: $error');
      return [];
    }
  }

  @override
  Future<void> updateUserFinancialGoals(String userId, List<String> goals) async {
    try {
      final profile = await getUserProfile(userId);
      final updatedProfile = profile.copyWith(
        financialGoals: goals,
        updatedAt: DateTime.now(),
      );
      await updateUserProfile(userId, updatedProfile);
    } catch (error) {
      debugPrint('Error updating user financial goals: $error');
      rethrow;
    }
  }

  /// Initialize profile with basic information from auth
  Future<void> initializeProfile(String userId, {
    String? name,
    String? email,
  }) async {
    try {
      final existingProfile = await getUserProfile(userId);
      
      // Only update if the profile doesn't have this information
      if (existingProfile.name == null || existingProfile.email == null) {
        final updatedProfile = existingProfile.copyWith(
          name: name ?? existingProfile.name,
          email: email ?? existingProfile.email,
          updatedAt: DateTime.now(),
        );
        await updateUserProfile(userId, updatedProfile);
      }
    } catch (error) {
      debugPrint('Error initializing user profile: $error');
    }
  }

  /// Get profile data optimized for AI analysis
  Future<Map<String, dynamic>> getAIOptimizedProfile(String userId) async {
    try {
      final profile = await getUserProfile(userId);
      return profile.toAIFormat();
    } catch (error) {
      debugPrint('Error getting AI optimized profile: $error');
      // Return safe defaults for AI
      return {
        'userId': userId,
        'annualIncome': 800000, // Default income
        'creditScore': 750, // Default credit score
        'age': 30,
        'city': 'Mumbai',
        'occupation': 'Professional',
        'financialGoals': ['savings', 'rewards'],
        'profileCompleteness': 0.3,
        'hasValidIncome': false,
        'hasValidCreditScore': false,
      };
    }
  }

  /// Check if user needs to complete profile for better AI recommendations
  Future<bool> needsProfileCompletion(String userId) async {
    try {
      final profile = await getUserProfile(userId);
      return !profile.isCompleteForAI;
    } catch (error) {
      return true; // Assume needs completion if error
    }
  }

  /// Get suggestions for profile completion
  Future<List<String>> getProfileCompletionSuggestions(String userId) async {
    try {
      final profile = await getUserProfile(userId);
      final suggestions = <String>[];

      if (profile.annualIncome == null) {
        suggestions.add('Add your annual income for better card recommendations');
      }
      if (profile.creditScore == null) {
        suggestions.add('Add your credit score for personalized suggestions');
      }
      if (profile.dateOfBirth == null) {
        suggestions.add('Add your date of birth for age-appropriate recommendations');
      }
      if (profile.city == null) {
        suggestions.add('Add your city for location-specific offers');
      }
      if (profile.occupation == null) {
        suggestions.add('Add your occupation for professional card recommendations');
      }
      if (profile.financialGoals.isEmpty) {
        suggestions.add('Set your financial goals for targeted advice');
      }

      return suggestions;
    } catch (error) {
      return ['Complete your profile for better AI recommendations'];
    }
  }
}
