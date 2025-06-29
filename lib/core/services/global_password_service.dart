import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cardcompass/app.dart'; // Import for navigatorKey

/// Global password request service using completers for proper async handling
class GlobalPasswordService {
  static final GlobalPasswordService _instance = GlobalPasswordService._internal();
  factory GlobalPasswordService() => _instance;
  GlobalPasswordService._internal();

  static Completer<String?>? _passwordCompleter;
  static String? _bankName;
  static String? _hint;
  /// Request a password and return it via completer
  static Future<String?> requestPassword(String bankName, {String? hint}) async {
    if (_passwordCompleter != null && !_passwordCompleter!.isCompleted) {
      _passwordCompleter!.complete(null); // Cancel previous request
    }

    _passwordCompleter = Completer<String?>();
    _bankName = bankName;
    _hint = hint;

    // Schedule the dialog to show on the next frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showPasswordDialog();
    });

    // Add a timeout to prevent indefinite waiting
    return _passwordCompleter!.future.timeout(
      const Duration(minutes: 5), // 5 minute timeout for password input
      onTimeout: () {
        print('⏰ Password dialog timed out after 5 minutes');
        return null;
      },
    );
  }
  /// Show the password dialog using global navigator key
  static void _showPasswordDialog() async {
    final context = navigatorKey.currentContext;
    if (context == null || !context.mounted) {
      print('❌ No valid context available for password dialog');
      _passwordCompleter?.complete(null);
      return;
    }

    print('🔐 Showing password dialog for ${_bankName ?? 'unknown bank'}');

    try {
      final password = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          final TextEditingController controller = TextEditingController();
          
          return AlertDialog(
            title: Text('PDF Password Required'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('The ${_bankName?.toUpperCase()} statement PDF is password protected.'),
                SizedBox(height: 16),
                if (_hint != null) ...[
                  Text(
                    'Hint: $_hint',
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
                    hintText: _bankName?.toLowerCase() == 'sbi' 
                        ? 'DOB(DDMMYYYY) + Last4Digits' 
                        : 'Password',
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
                child: Text('OK'),
              ),
            ],
          );
        },
      );

      print('🔑 Password dialog completed: ${password != null ? 'provided' : 'cancelled'}');
      _passwordCompleter?.complete(password);
    } catch (e) {
      print('❌ Error in password dialog: $e');
      _passwordCompleter?.complete(null);
    }
  }
}
