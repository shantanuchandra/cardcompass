import 'package:flutter/material.dart';
import 'package:cardcompass/core/services/data_pipeline_debug_service.dart';
import 'package:cardcompass/core/services/user_data_deletion_service.dart';
import 'package:cardcompass/core/services/robust_benefit_extraction_service.dart';
import 'package:cardcompass/core/services/password_input_service.dart';
import 'package:cardcompass/core/services/global_password_service.dart';
import 'package:cardcompass/shared/widgets/sync_progress_dialog.dart';

/// Service to handle dashboard operations like sync, delete, and AI benefits
class DashboardOperationsService {
  
  /// Sync data from Gmail with proper error handling
  static Future<bool> syncDataFromGmail({
    required String userId,
    required int numberOfEmails,
    required DateTime? startDate,
    required BuildContext context,
  }) async {
    BuildContext? dialogContext;

    try {
      // Show progress dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          dialogContext = context;
          return const SyncProgressDialog();
        },
      );

      // Set up password input callback
      PasswordInputService.setGlobalPasswordCallback((String bankName, String? hint) async {
        // Close progress dialog temporarily
        if (dialogContext != null && dialogContext!.mounted) {
          Navigator.of(dialogContext!).pop();
          await Future.delayed(const Duration(milliseconds: 200));
        }
        
        // Request password
        final password = await GlobalPasswordService.requestPassword(bankName, hint: hint);
        
        // Restore progress dialog
        if (context.mounted) {
          await Future.delayed(const Duration(milliseconds: 200));
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (BuildContext ctx) {
              dialogContext = ctx;
              return const SyncProgressDialog();
            },
          );
        }
        
        return password;
      });
      
      // Run the sync operation
      final debugService = DataPipelineDebugService();
      await debugService.debugSequentialUserFlow(userId, numberOfEmails, startDate);
      
      // Close progress dialog
      if (dialogContext != null && dialogContext!.mounted) {
        Navigator.of(dialogContext!).pop();
      }
      
      return true;
    } catch (error) {
      // Close progress dialog on error
      if (dialogContext != null && dialogContext!.mounted) {
        Navigator.of(dialogContext!).pop();
      }
      
      throw error; // Re-throw for caller to handle
    }
  }

  /// Delete all user data with confirmation
  static Future<bool> deleteAllUserData({
    required String userId,
    required BuildContext context,
  }) async {
    try {
      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return const AlertDialog(
            content: Row(
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 16),
                Expanded(child: Text('Deleting all data...')),
              ],
            ),
          );
        },
      );

      // Perform deletion
      final success = await UserDataDeletionService.deleteAllUserData(userId);
      
      // Close loading dialog
      if (context.mounted) {
        Navigator.of(context).pop();
      }
      
      return success;
    } catch (error) {
      // Close loading dialog on error
      if (context.mounted) {
        Navigator.of(context).pop();
      }
      
      throw error; // Re-throw for caller to handle
    }
  }

  /// Extract benefits using robust AI pipeline
  static Future<Map<String, dynamic>> extractBenefitsWithAI({
    required String userId,
    required BuildContext context,
  }) async {
    try {
      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.auto_awesome, color: Colors.indigo),
                SizedBox(width: 8),
                Text('AI Benefits Extraction'),
              ],
            ),
            content: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Running robust AI extraction pipeline...'),
                SizedBox(height: 8),
                Text(
                  '🔍 Searching bank websites with AI\n🤖 Classifying credit card pages\n📊 Extracting structured benefits',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          );
        },
      );

      // Run extraction
      final results = await RobustBenefitExtractionService.extractAllCardBenefits(
        userId: userId,
      );
      
      // Close loading dialog
      if (context.mounted) {
        Navigator.of(context).pop();
      }
      
      return results;
    } catch (error) {
      // Close loading dialog on error
      if (context.mounted) {
        Navigator.of(context).pop();
      }
      
      throw error; // Re-throw for caller to handle
    }
  }

  /// Get user data counts for deletion confirmation
  static Future<Map<String, int>> getUserDataCounts(String userId) async {
    return await UserDataDeletionService.getUserDataCounts(userId);
  }
}
