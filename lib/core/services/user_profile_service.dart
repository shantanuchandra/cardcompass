import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Reads and writes the current user's date of birth — from Supabase first,
/// falling back to Google's People API (requires the user.birthday.read
/// OAuth scope, requested at login).
class UserProfileService {
  static Future<DateTime?> getDateOfBirth(String userId) async {
    try {
      final response = await Supabase.instance.client
          .from('users')
          .select('date_of_birth')
          .eq('id', userId)
          .maybeSingle();

      if (response != null && response['date_of_birth'] != null) {
        return DateTime.parse(response['date_of_birth']);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> storeDateOfBirth(String userId, DateTime dob) async {
    try {
      await Supabase.instance.client.from('users').update({
        'date_of_birth': dob.toIso8601String().split('T')[0],
      }).eq('id', userId);
    } catch (_) {
      // Non-fatal: password resolution can proceed with the in-memory DOB
      // even if persisting it for next time fails.
    }
  }

  /// Fetches the user's birthday via Google's People API using the given
  /// OAuth access token. Returns null on any failure (missing scope, no
  /// birthday set on the Google account, network error) — this is one step
  /// in a fallback chain, so it must never throw.
  static Future<DateTime?> getGoogleBirthday(String accessToken) async {
    try {
      final response = await http.get(
        Uri.parse('https://people.googleapis.com/v1/people/me?personFields=birthdays'),
        headers: {'Authorization': 'Bearer $accessToken'},
      );

      if (response.statusCode != 200) return null;

      final decoded = json.decode(response.body) as Map<String, dynamic>;
      final birthdays = decoded['birthdays'] as List<dynamic>?;
      if (birthdays == null || birthdays.isEmpty) return null;

      final date = birthdays.first['date'] as Map<String, dynamic>?;
      if (date == null || date['year'] == null || date['month'] == null || date['day'] == null) {
        return null;
      }

      return DateTime(date['year'] as int, date['month'] as int, date['day'] as int);
    } catch (_) {
      return null;
    }
  }
}
