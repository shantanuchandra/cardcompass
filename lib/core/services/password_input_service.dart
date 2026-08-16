import 'package:flutter/material.dart';
import '../../app.dart' show navigatorKey;
import 'parsing_logger.dart';

/// Service for handling manual password input when automated detection fails
class PasswordInputService {
  /// Ask the user for a PDF password via a dialog on the current navigator
  /// context. Returns null if no context is available or the user cancels.
  static Future<String?> requestPassword(
    String bankName, {
    required int attempt,
    required int maxAttempts,
    String? hint,
  }) async {
    final context = navigatorKey.currentContext;
    if (context == null || !context.mounted) {
      ParsingLogger.warning(
        'Password: No valid context available for password dialog',
      );
      return null;
    }

    return _showPasswordInputDialog(
      context,
      bankName: bankName,
      attempt: attempt,
      maxAttempts: maxAttempts,
      hint: hint,
    );
  }

  static Future<String?> _showPasswordInputDialog(
    BuildContext context, {
    required String bankName,
    required int attempt,
    required int maxAttempts,
    String? hint,
  }) async {
    final TextEditingController controller = TextEditingController();
    final isRetry = attempt > 1;

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(
            isRetry
                ? 'Password incorrect — try again'
                : 'PDF password required',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isRetry) ...[
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    border: Border.all(color: Colors.red[200]!),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: Colors.red[600],
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'That password did not unlock this statement.',
                          style: TextStyle(
                            color: Colors.red[700],
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const SizedBox(height: 8),
              ],
              Text('Attempt $attempt of $maxAttempts'),
              const SizedBox(height: 16),
              Text(
                'The ${bankName.toUpperCase()} statement PDF is password protected.',
              ),
              const SizedBox(height: 16),
              if (hint != null) ...[
                Text(
                  'Hint: $hint',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontStyle: FontStyle.italic,
                  ),
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
                onSubmitted: (value) =>
                    Navigator.of(dialogContext).pop(value.trim()),
              ),
              if (bankName.toLowerCase() == 'sbi') ...[
                const SizedBox(height: 8),
                const Text(
                  'Example: If DOB is 02/12/1990 and card ends in 9329, password would be: 021219909329',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
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
                Navigator.of(
                  dialogContext,
                ).pop(password.isEmpty ? null : password);
              },
              child: const Text('Continue'),
            ),
          ],
        );
      },
    );
  }
}
