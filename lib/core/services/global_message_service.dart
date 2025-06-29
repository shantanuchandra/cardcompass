import 'package:flutter/material.dart';
import 'package:cardcompass/app.dart'; // Import for navigatorKey

/// Global message service for showing snackbars safely from anywhere
class GlobalMessageService {
  static final GlobalMessageService _instance = GlobalMessageService._internal();
  factory GlobalMessageService() => _instance;
  GlobalMessageService._internal();

  /// Show a success message using the global navigator
  static void showSuccess(String message) {
    _showMessage(message, Colors.green);
  }

  /// Show an error message using the global navigator
  static void showError(String message) {
    _showMessage(message, Colors.red);
  }

  /// Show an info message using the global navigator
  static void showInfo(String message) {
    _showMessage(message, null);
  }

  /// Internal method to show a message safely
  static void _showMessage(String message, Color? backgroundColor) {
    final context = navigatorKey.currentContext;
    if (context == null || !context.mounted) {
      print('⚠️ Cannot show message (no valid context): $message');
      return;
    }

    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: backgroundColor,
          duration: const Duration(seconds: 4),
        ),
      );
      print('📱 Message shown: $message');
    } catch (e) {
      print('❌ Error showing message: $e');
      print('📝 Message was: $message');
    }
  }
}
