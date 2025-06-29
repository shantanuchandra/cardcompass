import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cardcompass/shared/models/user.dart' as app_models;

/// Repository for user data operations with Supabase
class SupabaseUserRepository {
  final SupabaseClient _supabase = Supabase.instance.client;
  /// Get user by ID
  Future<app_models.User?> getUserById(String userId) async {
    try {
      final response = await _supabase
          .from('users')
          .select()
          .eq('id', userId)
          .maybeSingle();

      if (response == null) return null;      return app_models.User.fromJson({
        'id': response['id'],
        'email': response['email'] ?? '',
        'name': response['full_name'],
        'profileImage': response['avatar_url'],
        'createdAt': response['created_at'] ?? DateTime.now().toIso8601String(),
        'lastLoginAt': response['last_login_at'],
        'cardIds': <String>[], // Will be populated from separate query if needed
        'preferences': response['preferences'] ?? {},
        'isPremium': false, // Add this field to DB if needed
        'fullName': response['full_name'],
        'phoneNumber': response['phone'],
        'dateOfBirth': response['date_of_birth'],
        'annualIncome': response['annual_income']?.toDouble(),
        'creditScore': response['credit_score'],
        'occupation': response['occupation'],
        'city': response['city'],
      });
    } catch (error) {
      print('Error fetching user: $error');
      return null;
    }
  }
  /// Get user by email
  Future<app_models.User?> getUserByEmail(String email) async {
    try {
      final response = await _supabase
          .from('users')
          .select()
          .eq('email', email)
          .maybeSingle();

      if (response == null) return null;      return app_models.User.fromJson({
        'id': response['id'],
        'email': response['email'] ?? '',
        'name': response['full_name'],        'profileImage': response['avatar_url'],
        'createdAt': response['created_at'] ?? DateTime.now().toIso8601String(),
        'lastLoginAt': response['last_login_at'],
        'cardIds': <String>[],
        'preferences': response['preferences'] ?? {},
        'isPremium': false,
        'fullName': response['full_name'],
        'phoneNumber': response['phone'],
        'dateOfBirth': response['date_of_birth'],
        'annualIncome': response['annual_income']?.toDouble(),
        'creditScore': response['credit_score'],
        'occupation': response['occupation'],
        'city': response['city'],
      });
    } catch (error) {
      print('Error fetching user by email: $error');
      return null;
    }  }

  /// Create new user
  Future<app_models.User?> createUser({
    required String email,
    String? fullName,
    String? givenName,
    String? familyName,
    String? avatarUrl,
    String? phone,
    DateTime? dateOfBirth,
    Map<String, dynamic>? profileData,
    Map<String, dynamic>? preferences,
  }) async {    try {
      // Get the authenticated user's ID
      final authUser = _supabase.auth.currentUser;
      if (authUser == null) {
        print('Error: No authenticated user found');
        return null;
      }

      // Check if user already exists
      final existingUserResponse = await _supabase
          .from('users')
          .select()
          .eq('id', authUser.id)
          .maybeSingle();

      if (existingUserResponse != null) {
        print('User already exists, returning existing user');        return app_models.User.fromJson({
          'id': existingUserResponse['id'],
          'email': existingUserResponse['email'],
          'name': existingUserResponse['full_name'],
          'profileImage': existingUserResponse['avatar_url'],
          'createdAt': existingUserResponse['created_at'] ?? DateTime.now().toIso8601String(),
          'lastLoginAt': null,
          'cardIds': <String>[],
          'preferences': existingUserResponse['preferences'] ?? {},
          'isPremium': false,
          'fullName': existingUserResponse['full_name'],
          'phoneNumber': existingUserResponse['phone'],
          'dateOfBirth': existingUserResponse['date_of_birth'],
          'annualIncome': null,
          'creditScore': null,
          'occupation': null,
          'city': null,
        });
      }

      final response = await _supabase
          .from('users')
          .insert({
            'id': authUser.id, // Explicitly set the user ID to match auth.uid()
            'email': email,
            'full_name': fullName,
            'given_name': givenName,
            'family_name': familyName,
            'avatar_url': avatarUrl,
            'phone': phone,
            'date_of_birth': dateOfBirth?.toIso8601String(),
            'profile_data': profileData ?? {},
            'preferences': preferences ?? {},            
            'is_active': true,
          })
          .select()
          .single();      return app_models.User.fromJson({
        'id': response['id'],
        'email': response['email'],
        'name': response['full_name'],
        'profileImage': response['avatar_url'],
        'createdAt': response['created_at'] ?? DateTime.now().toIso8601String(),
        'lastLoginAt': null,
        'cardIds': <String>[],
        'preferences': response['preferences'] ?? {},
        'isPremium': false,
        'fullName': response['full_name'],
        'phoneNumber': response['phone'],
        'dateOfBirth': response['date_of_birth'],
        'annualIncome': null,
        'creditScore': null,
        'occupation': null,
        'city': null,
      });
    } catch (error) {
      print('Error creating user: $error');
      return null;
    }
  }
  /// Update user profile with Google API data
  Future<app_models.User?> updateUserWithGoogleProfile({
    required String userId,
    required Map<String, dynamic> googleProfile,
  }) async {
    try {
      // Extract data from Google profile
      final updateData = <String, dynamic>{
        'updated_at': DateTime.now().toIso8601String(),
      };

      // Update name fields
      if (googleProfile['displayName'] != null) {
        updateData['full_name'] = googleProfile['displayName'];
      }
      if (googleProfile['givenName'] != null) {
        updateData['given_name'] = googleProfile['givenName'];
      }
      if (googleProfile['familyName'] != null) {
        updateData['family_name'] = googleProfile['familyName'];
      }

      // Update birthday if available
      if (googleProfile['birthday'] != null) {
        final birthday = googleProfile['birthday'] as Map<String, dynamic>;
        if (birthday['year'] != null && birthday['month'] != null && birthday['day'] != null) {
          final dobString = '${birthday['year']}-${birthday['month'].toString().padLeft(2, '0')}-${birthday['day'].toString().padLeft(2, '0')}';
          updateData['date_of_birth'] = dobString;
        }
          // Store ALL Google profile data in profile_data for comprehensive access
        updateData['profile_data'] = {
          ...googleProfile, // Store complete Google profile
          'last_google_sync': DateTime.now().toIso8601String(),
        };
      }

      final response = await _supabase
          .from('users')
          .update(updateData)          .eq('id', userId)
          .select()
          .single();      return app_models.User.fromJson({
        'id': response['id'],
        'email': response['email'],
        'name': response['full_name'],
        'profileImage': response['avatar_url'],
        'createdAt': response['created_at'] ?? DateTime.now().toIso8601String(),
        'lastLoginAt': response['last_login_at'],
        'cardIds': <String>[],
        'preferences': response['preferences'] ?? {},
        'isPremium': false,
        'fullName': response['full_name'],
        'phoneNumber': response['phone'],
        'dateOfBirth': response['date_of_birth'],
        'annualIncome': response['annual_income']?.toDouble(),
        'creditScore': response['credit_score'],
        'occupation': response['occupation'],
        'city': response['city'],
      });
    } catch (error) {
      print('Error updating user with Google profile: $error');
      return null;
    }
  }

  /// Update user's last login time
  Future<void> updateLastLogin(String userId) async {
    try {
      await _supabase
          .from('users')
          .update({
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', userId);
    } catch (error) {
      print('Error updating last login: $error');
    }
  }

  /// Get user's birthday in password formats
  Future<Map<String, dynamic>?> getUserBirthdayFormats(String userId) async {
    try {
      final response = await _supabase
          .from('users')
          .select('date_of_birth, profile_data')
          .eq('id', userId)
          .maybeSingle();

      if (response == null) return null;

      final dateOfBirth = response['date_of_birth'];
      final profileData = response['profile_data'] as Map<String, dynamic>?;

      if (dateOfBirth != null) {
        final dob = DateTime.parse(dateOfBirth);
        final day = dob.day.toString().padLeft(2, '0');
        final month = dob.month.toString().padLeft(2, '0');
        final year = dob.year.toString();
        
        return {
          'day': day,
          'month': month,
          'year': year,
          'ddmmyyyy': '$day$month$year',
          'yyyymmdd': '$year$month$day',
          'ddmmyy': '$day$month${year.substring(2)}',
          'mmddyyyy': '$month$day$year',
          'yymmdd': '${year.substring(2)}$month$day',
          'ddmm': '$day$month',
        };
      }

      // Fallback to profile_data if available
      return profileData?['birthday_formats'];
    } catch (error) {
      print('Error getting user birthday formats: $error');
      return null;
    }
  }
}
