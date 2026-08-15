import 'package:flutter/material.dart';
import '../../app.dart' show navigatorKey;

/// Service for handling manual password input when automated detection fails
class PasswordInputService {
  static int _attemptCount = 0;
  static String? _lastFailedPassword;

  /// Reset attempt tracking (call when starting new PDF processing)
  static void resetAttempts() {
    _attemptCount = 0;
    _lastFailedPassword = null;
  }

  /// Ask the user for a PDF password via a dialog on the current navigator
  /// context. Returns null if no context is available or the user cancels.
  static Future<String?> requestPassword(String bankName, {String? hint}) async {
    _attemptCount++;
    final context = navigatorKey.currentContext;
    if (context == null || !context.mounted) {
      print('❌ No valid context available for password dialog');
      return null;
    }

    final password = await _showPasswordInputDialog(context, bankName: bankName, hint: hint);
    if (password != null) {
      _lastFailedPassword = password;
    }
    return password;
  }

  static Future<String?> _showPasswordInputDialog(
    BuildContext context, {
    required String bankName,
    String? hint,
  }) async {
    final TextEditingController controller = TextEditingController();
    final isRetry = _attemptCount > 1;

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(isRetry ? 'Password Incorrect - Try Again' : 'PDF Password Required'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isRetry && _lastFailedPassword != null) ...[
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    border: Border.all(color: Colors.red[200]!),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: Colors.red[600], size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Password "$_lastFailedPassword" was incorrect',
                          style: TextStyle(color: Colors.red[700], fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text('Attempt $_attemptCount of 2'),
                const SizedBox(height: 16),
              ],
              Text('The ${bankName.toUpperCase()} statement PDF is password protected.'),
              const SizedBox(height: 16),
              if (hint != null) ...[
                Text(
                  'Hint: $hint',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600], fontStyle: FontStyle.italic),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: controller,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Enter PDF Password',
                  hintText: bankName.toLowerCase() == 'sbi'
                      ? 'DOB(DDMMYYYY) + Last4Digits'
                      : 'Password',
                  border: const OutlineInputBorder(),
                ),
                autofocus: true,
                onSubmitted: (value) => Navigator.of(dialogContext).pop(value.trim()),
              ),
              if (bankName.toLowerCase() == 'sbi') ...[
                const SizedBox(height: 8),
                const Text(
                  'Example: If DOB is 02/12/1990 and card ends in 9329, password would be: 021219909329',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(null),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final password = controller.text.trim();
                Navigator.of(dialogContext).pop(password.isEmpty ? null : password);
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }
}
