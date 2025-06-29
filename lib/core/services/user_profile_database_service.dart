import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cardcompass/core/services/error_handling_service.dart';

/// Service to handle user profile data in the existing users table
class UserProfileDatabaseService {
  static final SupabaseClient _supabase = Supabase.instance.client;

  /// Get user's date of birth from the users table
  static Future<DateTime?> getUserDateOfBirth(String userId) async {
    try {
      final response = await _supabase
          .from('users')
          .select('date_of_birth')
          .eq('id', userId)
          .maybeSingle();

      if (response != null && response['date_of_birth'] != null) {
        return DateTime.parse(response['date_of_birth']);
      }
      
      return null;
    } catch (error) {
      ErrorHandlingService.logError('UserProfileDatabaseService', 'Error fetching date of birth: $error');
      return null;
    }
  }

  /// Store user's date of birth in the users table
  static Future<bool> storeUserDateOfBirth(String userId, DateTime dateOfBirth) async {
    try {
      await _supabase
          .from('users')
          .update({
            'date_of_birth': dateOfBirth.toIso8601String().split('T')[0], // Store as YYYY-MM-DD
          })
          .eq('id', userId);

      return true;
    } catch (error) {
      ErrorHandlingService.logError('UserProfileDatabaseService', 'Error storing date of birth: $error');
      return false;
    }
  }

  /// Get user's display name from the users table
  static Future<String> getUserDisplayName(String userId) async {
    try {
      final response = await _supabase
          .from('users')
          .select('full_name')
          .eq('id', userId)
          .maybeSingle();

      if (response != null && response['full_name'] != null) {
        return response['full_name'] as String;
      }
      
      return 'User';
    } catch (error) {
      ErrorHandlingService.logError('UserProfileDatabaseService', 'Error fetching display name: $error');
      return 'User';
    }
  }

  /// Format birthday for password generation
  static Map<String, String> formatBirthdayForPasswords(DateTime birthday) {
    final year = birthday.year.toString();
    final month = birthday.month.toString().padLeft(2, '0');
    final day = birthday.day.toString().padLeft(2, '0');
    final shortYear = year.substring(2);

    return {
      'ddmm': '$day$month',           // 2512
      'ddmmyy': '$day$month$shortYear', // 251290
      'ddmmyyyy': '$day$month$year',   // 25121990
      'yyyymmdd': '$year$month$day',   // 19901225
      'mmddyyyy': '$month$day$year',   // 12251990
      'raw': '$year-$month-$day',      // 1990-12-25
    };
  }

  /// Check if a birthday is valid (not in future, reasonable age range)
  static bool isValidBirthday(DateTime birthday) {
    final now = DateTime.now();
    final age = now.year - birthday.year;
    
    // Check if birthday is not in the future
    if (birthday.isAfter(now)) return false;
    
    // Check reasonable age range (13-120 years)
    if (age < 13 || age > 120) return false;
    
    return true;
  }
}
