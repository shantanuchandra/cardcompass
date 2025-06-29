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
      
      // Create pattern analysis
      final pattern = _analyzePasswordPattern(
        password: password,
        bankName: bankName,
        userProfile: userProfile,
        fileName: fileName,
      );
      
      // Store bank-specific successful passwords
      await _storeBankPassword(prefs, bankName, userEmail, password, pattern);
        // Store general patterns for learning
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
    String? fileName,  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final candidates = <String>[];
      
      // Get bank-specific stored passwords
      final bankPasswords = await _getBankPasswords(prefs, bankName, userEmail);
      candidates.addAll(bankPasswords);
      
      // Generate candidates based on learned patterns
      final learnedCandidates = await _generateFromLearnedPatterns(
        prefs: prefs,
        bankName: bankName,
        userProfile: userProfile,        fileName: fileName,
      );
      candidates.addAll(learnedCandidates);
      
      // Remove duplicates and return
      final uniqueCandidates = candidates.toSet().toList();
      
      return uniqueCandidates;
    } catch (e) {
      print('Error getting learned passwords: $e');
      return [];
    }
  }
  
  /// Analyze a successful password to extract patterns
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
    
    // Analyze DOB patterns if user profile is available
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
          
          // Check what comes after DOB
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
    
    // Analyze numeric patterns
    if (RegExp(r'^\d+$').hasMatch(password)) {
      pattern['isNumericOnly'] = true;
      
      if (password.length == 12) {
        pattern['type'] = pattern['type'] ?? 'numeric_12_digit';
        pattern['description'] = pattern['description'] ?? '12-digit numeric pattern';
      }
    }
    
    // Check for card number patterns from filename
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
  
  /// Store bank-specific password
  static Future<void> _storeBankPassword(
    SharedPreferences prefs,
    String bankName,
    String userEmail,
    String password,
    Map<String, dynamic> pattern,
  ) async {
    final bankPasswordsJson = prefs.getString(_bankPasswordsKey) ?? '{}';
    final bankPasswords = Map<String, dynamic>.from(json.decode(bankPasswordsJson));
    
    final bankKey = '${bankName.toLowerCase()}_${userEmail}';
    bankPasswords[bankKey] = {
      'password': password,
      'pattern': pattern,
      'successCount': (bankPasswords[bankKey]?['successCount'] ?? 0) + 1,
      'lastUsed': DateTime.now().toIso8601String(),
    };
    
    await prefs.setString(_bankPasswordsKey, json.encode(bankPasswords));
  }
  
  /// Store general password pattern
  static Future<void> _storePasswordPattern(
    SharedPreferences prefs,
    Map<String, dynamic> pattern,
  ) async {
    final patternsJson = prefs.getString(_passwordPatternsKey) ?? '[]';
    final patterns = List<Map<String, dynamic>>.from(
      json.decode(patternsJson).map((p) => Map<String, dynamic>.from(p))
    );
    
    patterns.add(pattern);
    
    // Keep only last 50 patterns to avoid storage bloat
    if (patterns.length > 50) {
      patterns.removeRange(0, patterns.length - 50);
    }
    
    await prefs.setString(_passwordPatternsKey, json.encode(patterns));
  }
  
  /// Get stored passwords for a specific bank and user
  static Future<List<String>> _getBankPasswords(
    SharedPreferences prefs,
    String bankName,
    String userEmail,
  ) async {
    final bankPasswordsJson = prefs.getString(_bankPasswordsKey) ?? '{}';
    final bankPasswords = Map<String, dynamic>.from(json.decode(bankPasswordsJson));
    
    final bankKey = '${bankName.toLowerCase()}_${userEmail}';
    final bankData = bankPasswords[bankKey];
    
    if (bankData != null) {
      return [bankData['password'] as String];
    }
    
    return [];
  }
  
  /// Generate password candidates based on learned patterns
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
    
    // Filter patterns for the same bank
    final bankPatterns = patterns.where((p) => 
      p['bankName'] == bankName.toLowerCase()
    ).toList();
    
    for (final pattern in bankPatterns) {
      if (pattern['type'] == 'dob_plus_4digits' && userProfile != null) {
        // Try to apply this pattern with current user's DOB
        final birthday = userProfile['birthday'] as Map<String, dynamic>?;
        if (birthday != null) {
          final dobFormat = pattern['dobFormat'] as String?;
          if (dobFormat != null && birthday.containsValue(dobFormat)) {
            // Find 4-digit numbers from filename or other sources
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
  
  /// Clear all stored password data (for testing or privacy)
  static Future<void> clearAllStoredData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_passwordPatternsKey);
    await prefs.remove(_bankPasswordsKey);
    print('🗑️ Cleared all stored password learning data');
  }
  
  /// Get statistics about learned patterns
  static Future<Map<String, dynamic>> getLearnedStatistics() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      final patternsJson = prefs.getString(_passwordPatternsKey) ?? '[]';
      final patterns = List<Map<String, dynamic>>.from(
        json.decode(patternsJson).map((p) => Map<String, dynamic>.from(p))
      );
      
      final bankPasswordsJson = prefs.getString(_bankPasswordsKey) ?? '{}';
      final bankPasswords = Map<String, dynamic>.from(json.decode(bankPasswordsJson));
      
      return {
        'totalPatterns': patterns.length,
        'bankSpecificPasswords': bankPasswords.length,
        'patternTypes': patterns.map((p) => p['type']).toSet().toList(),
        'banksLearned': patterns.map((p) => p['bankName']).toSet().toList(),
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  }
}
