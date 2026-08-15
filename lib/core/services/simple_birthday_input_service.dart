import 'package:flutter/material.dart';

/// Service to handle birthday input from users
class SimpleBirthdayInputService {
  /// Request birthday input from user via dialog
  static Future<DateTime?> requestBirthdayInput({
    required BuildContext? context,
    required String userId,
    required String reason,
  }) async {
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

  /// Format birthday for password generation
  static Map<String, String> formatBirthdayForPasswords(DateTime birthday) {
    final year = birthday.year.toString();
    final month = birthday.month.toString().padLeft(2, '0');
    final day = birthday.day.toString().padLeft(2, '0');
    final shortYear = year.substring(2);

    return {
      'ddmm': '$day$month',
      'ddmmyy': '$day$month$shortYear',
      'ddmmyyyy': '$day$month$year',
      'yyyymmdd': '$year$month$day',
      'mmddyyyy': '$month$day$year',
      'raw': '$year-$month-$day',
    };
  }
}
