import 'package:flutter/material.dart';

/// Service to handle birthday input from users
class SimpleBirthdayInputService {
  /// Request birthday input from user via dialog
  static Future<DateTime?> requestBirthdayInput({
    required BuildContext? context,
    required String userId,
    required String reason,
  }) async {
    // If no context provided, return null (can't show dialog)
    if (context == null) {
      print('⚠️  No context provided for birthday input dialog');
      return null;
    }

    final result = await showDialog<DateTime?>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Date of Birth Required'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('We need your date of birth for PDF password detection.'),
              const SizedBox(height: 8),
              Text('Reason: $reason', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              const SizedBox(height: 16),
              const Text('This will be stored securely in your profile for future use.'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(null),
              child: const Text('Skip'),
            ),
            ElevatedButton(
              onPressed: () async {
                final date = await _showDatePicker(dialogContext);
                if (date != null) {
                  Navigator.of(dialogContext).pop(date);
                }
              },
              child: const Text('Select Date'),
            ),
          ],
        );
      },
    );

    return result;
  }

  /// Show date picker dialog
  static Future<DateTime?> _showDatePicker(BuildContext context) async {
    final now = DateTime.now();
    final eighteenYearsAgo = DateTime(now.year - 18, now.month, now.day);
    
    return await showDatePicker(
      context: context,
      initialDate: eighteenYearsAgo,
      firstDate: DateTime(1900),
      lastDate: now,
      helpText: 'Select your date of birth',
    );
  }

  /// Validate birthday
  static bool isValidBirthday(DateTime? birthday) {
    if (birthday == null) return false;
    
    final now = DateTime.now();
    final age = now.year - birthday.year;
    
    // Check if birthday is not in the future
    if (birthday.isAfter(now)) return false;
    
    // Check reasonable age range (13-120 years)
    if (age < 13 || age > 120) return false;
    
    return true;
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
}
