import 'dart:async';
import 'package:flutter/material.dart';

/// Service for handling manual password input when automated detection fails
class PasswordInputService {
  static final PasswordInputService _instance = PasswordInputService._internal();
  factory PasswordInputService() => _instance;
  PasswordInputService._internal();
  /// Global callback for password input - can be set by the app
  static Future<String?> Function(String bankName, String? hint)? _globalPasswordCallback;
  static int _attemptCount = 0;
  static String? _lastFailedPassword;

  /// Set the global password input callback
  static void setGlobalPasswordCallback(Future<String?> Function(String bankName, String? hint)? callback) {
    _globalPasswordCallback = callback;
  }  /// Get a password using the global callback if available
  static Future<String?> requestPassword(String bankName, {String? hint}) async {
    _attemptCount++;
    print('📝 Requesting password for $bankName (attempt $_attemptCount)');
    
    if (_globalPasswordCallback != null) {
      final password = await _globalPasswordCallback!(bankName, hint);
      if (password != null) {
        _lastFailedPassword = password; // Store in case it fails
        print('✅ Password received from user');
      } else {
        print('❌ No password provided by user');
      }
      return password;
    } else {
      print('❌ No password input callback available. Set one using PasswordInputService.setGlobalPasswordCallback()');
      return null;
    }
  }
  /// Reset attempt tracking (call when starting new PDF processing)
  static void resetAttempts() {
    // print('🔄 Resetting password attempts (was: $_attemptCount)');
    _attemptCount = 0;
    _lastFailedPassword = null;
  }

  /// Create a simple callback function for the password detection service
  static Future<String?> Function() createSimpleCallback(String bankName, {String? hint}) {
    return () async {
      return await requestPassword(bankName, hint: hint);
    };
  }
  /// Show a dialog to get manual password input from the user
  static Future<String?> showPasswordInputDialog(BuildContext context, {
    required String bankName,
    String? hint,
  }) async {
    final TextEditingController controller = TextEditingController();
    final isRetry = _attemptCount > 1;
    
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(isRetry ? 'Password Incorrect - Try Again' : 'PDF Password Required'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isRetry && _lastFailedPassword != null) ...[
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    border: Border.all(color: Colors.red[200]!),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: Colors.red[600], size: 16),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Password "$_lastFailedPassword" was incorrect',
                          style: TextStyle(color: Colors.red[700], fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 12),
                Text('Attempt $_attemptCount of 2'),
                SizedBox(height: 16),
              ],
              Text('The ${bankName.toUpperCase()} statement PDF is password protected.'),
              SizedBox(height: 16),
              if (hint != null) ...[
                Text(
                  'Hint: $hint',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontStyle: FontStyle.italic,
                  ),
                ),
                SizedBox(height: 12),
              ],
              TextField(
                controller: controller,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Enter PDF Password',
                  hintText: bankName.toLowerCase() == 'sbi' 
                      ? 'DOB(DDMMYYYY) + Last4Digits' 
                      : 'Password',
                  border: OutlineInputBorder(),
                ),
                autofocus: true,
                onSubmitted: (value) {
                  Navigator.of(context).pop(value.trim());
                },
              ),
              SizedBox(height: 8),
              if (bankName.toLowerCase() == 'sbi') ...[
                Text(
                  'Example: If DOB is 02/12/1990 and card ends in 9329, password would be: 021219909329',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final password = controller.text.trim();
                Navigator.of(context).pop(password.isEmpty ? null : password);
              },
              child: Text('OK'),
            ),
          ],
        );
      },
    );
  }

  /// Create a callback function that can be used with the PDF password detection service
  static Future<String?> Function() createPasswordInputCallback(
    BuildContext context, {
    required String bankName,
    String? hint,
  }) {
    return () async {
      return await showPasswordInputDialog(
        context,
        bankName: bankName,
        hint: hint,
      );
    };
  }

  /// Show a simple password retry dialog for when a manual password fails
  static Future<String?> showPasswordRetryDialog(BuildContext context, {
    required String bankName,
    required String failedPassword,
  }) async {
    final TextEditingController controller = TextEditingController();
    
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Password Incorrect'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('The password "$failedPassword" did not work.'),
              SizedBox(height: 8),
              Text('Please try a different password:'),
              SizedBox(height: 16),
              TextField(
                controller: controller,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Enter PDF Password',
                  border: OutlineInputBorder(),
                ),
                autofocus: true,
                onSubmitted: (value) {
                  Navigator.of(context).pop(value.trim());
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final password = controller.text.trim();
                Navigator.of(context).pop(password.isEmpty ? null : password);
              },
              child: Text('Try Again'),
            ),
          ],
        );
      },
    );
  }
}
