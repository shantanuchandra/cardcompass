import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Service for learning and storing successful password patterns
class PasswordLearningService {
  static const String _passwordPatternsKey = 'successful_password_patterns';
  static const String _bankPasswordsKey = 'bank_specific_passwords';

  /// Store a successful password pattern for future use
  static Future<void> storeSuccessfulPassword({
    required String bankName,
    required String password,
    required String userEmail,
    String? fileName,
    Map<String, dynamic>? userProfile,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final pattern = _analyzePasswordPattern(
        password: password,
        bankName: bankName,
        userProfile: userProfile,
        fileName: fileName,
      );

      await _storeBankPassword(prefs, bankName, userEmail, password, pattern);
      await _storePasswordPattern(prefs, pattern);
    } catch (e) {
      print('Error storing successful password: $e');
    }
  }

  /// Get learned password candidates for a bank and user
  static Future<List<String>> getLearnedPasswordCandidates({
    required String bankName,
    required String userEmail,
    Map<String, dynamic>? userProfile,
    String? fileName,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final candidates = <String>[];

      final bankPasswords = await _getBankPasswords(prefs, bankName, userEmail);
      candidates.addAll(bankPasswords);

      final learnedCandidates = await _generateFromLearnedPatterns(
        prefs: prefs,
        bankName: bankName,
        userProfile: userProfile,
        fileName: fileName,
      );
      candidates.addAll(learnedCandidates);

      return candidates.toSet().toList();
    } catch (e) {
      print('Error getting learned passwords: $e');
      return [];
    }
  }

  static Map<String, dynamic> _analyzePasswordPattern({
    required String password,
    required String bankName,
    Map<String, dynamic>? userProfile,
    String? fileName,
  }) {
    final pattern = <String, dynamic>{
      'bankName': bankName.toLowerCase(),
      'passwordLength': password.length,
      'timestamp': DateTime.now().toIso8601String(),
    };

    if (userProfile != null && userProfile['birthday'] != null) {
      final birthday = userProfile['birthday'] as Map<String, dynamic>;
      final dobFormats = [
        birthday['ddmmyyyy'] as String?,
        birthday['yyyymmdd'] as String?,
        birthday['ddmmyy'] as String?,
        birthday['mmddyyyy'] as String?,
      ].where((d) => d != null).cast<String>();

      for (final dobFormat in dobFormats) {
        if (password.contains(dobFormat)) {
          pattern['containsDOB'] = true;
          pattern['dobFormat'] = dobFormat;
          pattern['dobPosition'] = password.indexOf(dobFormat);

          final remainingAfterDOB = password.substring(password.indexOf(dobFormat) + dobFormat.length);
          if (remainingAfterDOB.length == 4 && RegExp(r'^\d{4}$').hasMatch(remainingAfterDOB)) {
            pattern['type'] = 'dob_plus_4digits';
            pattern['description'] = 'DOB ($dobFormat) + 4 digits ($remainingAfterDOB)';
            pattern['digitsSuffix'] = remainingAfterDOB;
          }
          break;
        }
      }
    }

    if (RegExp(r'^\d+$').hasMatch(password)) {
      pattern['isNumericOnly'] = true;

      if (password.length == 12) {
        pattern['type'] = pattern['type'] ?? 'numeric_12_digit';
        pattern['description'] = pattern['description'] ?? '12-digit numeric pattern';
      }
    }

    if (fileName != null) {
      final cardNumberMatch = RegExp(r'(\d{4})_').firstMatch(fileName);
      if (cardNumberMatch != null && password.contains(cardNumberMatch.group(1)!)) {
        pattern['containsCardDigits'] = true;
        pattern['cardDigits'] = cardNumberMatch.group(1);
      }
    }

    pattern['type'] = pattern['type'] ?? 'unknown';
    pattern['description'] = pattern['description'] ?? 'Unknown pattern';

    return pattern;
  }

  static Future<void> _storeBankPassword(
    SharedPreferences prefs,
    String bankName,
    String userEmail,
    String password,
    Map<String, dynamic> pattern,
  ) async {
    final bankPasswordsJson = prefs.getString(_bankPasswordsKey) ?? '{}';
    final bankPasswords = Map<String, dynamic>.from(json.decode(bankPasswordsJson));

    final bankKey = '${bankName.toLowerCase()}_$userEmail';
    bankPasswords[bankKey] = {
      'password': password,
      'pattern': pattern,
      'successCount': (bankPasswords[bankKey]?['successCount'] ?? 0) + 1,
      'lastUsed': DateTime.now().toIso8601String(),
    };

    await prefs.setString(_bankPasswordsKey, json.encode(bankPasswords));
  }

  static Future<void> _storePasswordPattern(
    SharedPreferences prefs,
    Map<String, dynamic> pattern,
  ) async {
    final patternsJson = prefs.getString(_passwordPatternsKey) ?? '[]';
    final patterns = List<Map<String, dynamic>>.from(
      json.decode(patternsJson).map((p) => Map<String, dynamic>.from(p))
    );

    patterns.add(pattern);

    if (patterns.length > 50) {
      patterns.removeRange(0, patterns.length - 50);
    }

    await prefs.setString(_passwordPatternsKey, json.encode(patterns));
  }

  static Future<List<String>> _getBankPasswords(
    SharedPreferences prefs,
    String bankName,
    String userEmail,
  ) async {
    final bankPasswordsJson = prefs.getString(_bankPasswordsKey) ?? '{}';
    final bankPasswords = Map<String, dynamic>.from(json.decode(bankPasswordsJson));

    final bankKey = '${bankName.toLowerCase()}_$userEmail';
    final bankData = bankPasswords[bankKey];

    if (bankData != null) {
      return [bankData['password'] as String];
    }

    return [];
  }

  static Future<List<String>> _generateFromLearnedPatterns({
    required SharedPreferences prefs,
    required String bankName,
    Map<String, dynamic>? userProfile,
    String? fileName,
  }) async {
    final candidates = <String>[];

    final patternsJson = prefs.getString(_passwordPatternsKey) ?? '[]';
    final patterns = List<Map<String, dynamic>>.from(
      json.decode(patternsJson).map((p) => Map<String, dynamic>.from(p))
    );

    final bankPatterns = patterns.where((p) =>
      p['bankName'] == bankName.toLowerCase()
    ).toList();

    for (final pattern in bankPatterns) {
      if (pattern['type'] == 'dob_plus_4digits' && userProfile != null) {
        final birthday = userProfile['birthday'] as Map<String, dynamic>?;
        if (birthday != null) {
          final dobFormat = pattern['dobFormat'] as String?;
          if (dobFormat != null && birthday.containsValue(dobFormat)) {
            if (fileName != null) {
              final matches = RegExp(r'\d{4}').allMatches(fileName);
              for (final match in matches) {
                candidates.add(dobFormat + match.group(0)!);
              }
            }
          }
        }
      }
    }

    return candidates;
  }
}
