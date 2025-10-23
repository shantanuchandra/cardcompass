import 'package:flutter_test/flutter_test.dart';
import 'package:cardcompass/debug/sync_flow_debugger.dart';

/// Integration test simulating a real sync flow scenario
void main() {
  group('SyncFlowDebugger - Real Sync Flow Simulation', () {
    test('should debug complete sync flow with 3 emails', () async {
      // Start debugging session
      SyncFlowDebugger.start('user-abc-123');
      
      // STEP 1: Sync initiated
      SyncFlowDebugger.logStep('SYNC_STARTED', 'User initiated sync', data: {
        'numberOfEmails': 30,
        'startDate': DateTime.now().subtract(const Duration(days: 30)).toIso8601String(),
      });
      
      // STEP 2: Gmail authentication
      await Future.delayed(const Duration(milliseconds: 50));
      SyncFlowDebugger.logStep('GMAIL_AUTH', 'Gmail API authenticated successfully');
      
      // STEP 3: Fetch user DOB
      await Future.delayed(const Duration(milliseconds: 30));
      SyncFlowDebugger.logStep('DOB_FETCHED', 'Retrieved DOB from Google People API', data: {
        'dob': '1995-12-02',
        'formats': ['0212', '02121995'],
      });
      
      // STEP 4: Search emails
      final searchTimer = SyncFlowDebugger.startTimer('Gmail Search');
      await Future.delayed(const Duration(milliseconds: 100));
      SyncFlowDebugger.endTimer('Gmail Search', searchTimer);
      
      SyncFlowDebugger.logStep('GMAIL_SEARCH', 'Searching for statement emails');
      SyncFlowDebugger.logStep('EMAIL_FOUND', 'Found statement emails', data: {
        'count': 3,
        'banks': ['HDFC', 'ICICI', 'Axis'],
      });
      
      // STEP 5-8: Process each email
      final banks = ['HDFC', 'ICICI', 'Axis'];
      final txCounts = [47, 35, 28];
      
      for (int i = 0; i < 3; i++) {
        final emailTimer = SyncFlowDebugger.startTimer('Process Email ${i + 1}');
        
        // Email processing
        SyncFlowDebugger.logStep('EMAIL_PROCESSED', 'Processing email ${i + 1}/3', data: {
          'bank': banks[i],
          'date': DateTime.now().subtract(Duration(days: i)).toIso8601String(),
          'pdfSize': 2345678 + (i * 100000),
        });
        
        // PDF download
        await Future.delayed(const Duration(milliseconds: 30));
        SyncFlowDebugger.logStep('PDF_DOWNLOAD', 'Downloaded PDF attachment', data: {
          'size': '${(2.3 + i * 0.5).toStringAsFixed(1)}MB',
        });
        
        // PDF unlock
        await Future.delayed(const Duration(milliseconds: 50));
        if (i == 1) {
          // Simulate failed auto unlock on second email
          SyncFlowDebugger.logStep('PDF_LOCKED', 'Auto unlock failed, trying manual', data: {
            'autoAttempts': 3,
          });
          await Future.delayed(const Duration(milliseconds: 100));
        }
        
        SyncFlowDebugger.logStep('PDF_UNLOCKED', 'PDF unlocked successfully', data: {
          'method': i == 1 ? 'manual' : 'automatic',
          'textLength': 15000 + (i * 2000),
        });
        
        // Gemini parsing - Statement info
        final geminiStmtTimer = SyncFlowDebugger.startTimer('Gemini Parse Statement ${i + 1}');
        await Future.delayed(const Duration(milliseconds: 80));
        SyncFlowDebugger.endTimer('Gemini Parse Statement ${i + 1}', geminiStmtTimer);
        
        SyncFlowDebugger.logStep('GEMINI_PARSE', 'Extracting statement info', data: {
          'bankName': banks[i],
        });
        
        SyncFlowDebugger.logStep('STATEMENT_INFO', 'Statement info extracted', data: {
          'statementDate': '2025-05-${15 + i}',
          'dueDate': '2025-06-${5 + i}',
          'totalAmount': 25000.0 + (i * 5000),
        });
        
        // Gemini parsing - Transactions
        final geminiTxTimer = SyncFlowDebugger.startTimer('Gemini Parse Transactions ${i + 1}');
        await Future.delayed(const Duration(milliseconds: 150));
        SyncFlowDebugger.endTimer('Gemini Parse Transactions ${i + 1}', geminiTxTimer);
        
        SyncFlowDebugger.logStep('TRANSACTION_PARSE', 'Parsing transactions', data: {
          'bankName': banks[i],
        });
        
        SyncFlowDebugger.logStep('TRANSACTION_PARSE', 'Transactions parsed successfully', data: {
          'count': txCounts[i],
          'categories': {
            'entertainment': 5,
            'shopping': 12,
            'fuel': 8,
            'dining': 15,
            'other': txCounts[i] - 40,
          },
        });
        
        // Card mapping
        await Future.delayed(const Duration(milliseconds: 20));
        SyncFlowDebugger.logStep('CARD_MAPPING', 'Looking for existing user card', data: {
          'bankName': banks[i],
          'cardVariant': '${banks[i]} Premium',
        });
        
        final isNewCard = i == 2; // Axis is new
        if (isNewCard) {
          SyncFlowDebugger.logStep('CARD_MAPPING', 'Creating new card association', data: {
            'bankName': banks[i],
            'cardName': '${banks[i]} Premium',
          });
        } else {
          SyncFlowDebugger.logStep('CARD_MAPPING', 'Found existing user card', data: {
            'catalogCardId': 'catalog-${i}',
            'userCardId': 'user-card-${i}',
          });
        }
        
        // Database storage
        final dbTimer = SyncFlowDebugger.startTimer('Store to Database ${i + 1}');
        await Future.delayed(const Duration(milliseconds: 60));
        SyncFlowDebugger.endTimer('Store to Database ${i + 1}', dbTimer);
        
        SyncFlowDebugger.logStep('DB_STORED', 'Storing statement to database', data: {
          'userCardId': 'user-card-${i}',
          'transactionCount': txCounts[i],
        });
        
        SyncFlowDebugger.logStep('TRANSACTION_STORED', 'Transactions stored', data: {
          'count': txCounts[i],
        });
        
        SyncFlowDebugger.endTimer('Process Email ${i + 1}', emailTimer);
        
        // Small delay between emails
        await Future.delayed(const Duration(milliseconds: 20));
      }
      
      // STEP 9: Complete
      SyncFlowDebugger.logStep('SYNC_COMPLETE', 'All emails processed successfully', data: {
        'emailsProcessed': 3,
        'emailsStored': 3,
        'totalTransactions': 47 + 35 + 28,
      });
      
      // Generate and verify report
      final report = SyncFlowDebugger.generateReport();
      
      print('\n' + '=' * 80);
      print('INTEGRATION TEST - FULL SYNC FLOW REPORT');
      print('=' * 80);
      print(report);
      print('=' * 80);
      
      // Assertions
      final steps = SyncFlowDebugger.getSteps();
      expect(steps.isNotEmpty, true);
      
      // Verify key steps exist
      expect(steps.any((s) => s.stepName == 'SYNC_STARTED'), true);
      expect(steps.any((s) => s.stepName == 'GMAIL_AUTH'), true);
      expect(steps.any((s) => s.stepName == 'EMAIL_FOUND'), true);
      expect(steps.any((s) => s.stepName == 'PDF_UNLOCKED'), true);
      expect(steps.any((s) => s.stepName == 'TRANSACTION_STORED'), true);
      expect(steps.any((s) => s.stepName == 'SYNC_COMPLETE'), true);
      
      // Verify counts
      final emailProcessedCount = SyncFlowDebugger.getStepsByName('EMAIL_PROCESSED').length;
      expect(emailProcessedCount, 3);
      
      final pdfUnlockedCount = SyncFlowDebugger.getStepsByName('PDF_UNLOCKED').length;
      expect(pdfUnlockedCount, 3);
      
      final dbStoredCount = SyncFlowDebugger.getStepsByName('DB_STORED').length;
      expect(dbStoredCount, 3);
      
      // Verify no errors
      final errors = SyncFlowDebugger.getErrors();
      expect(errors.isEmpty, true);
      
      // Verify report content
      expect(report, contains('SYNC FLOW DEBUG REPORT'));
      expect(report, contains('User ID: user-abc-123'));
      expect(report, contains('Emails Processed: 3'));
      expect(report, contains('Statements Stored: 3'));
      expect(report, contains('PDFs Unlocked: 3'));
    });

    test('should handle error scenarios in sync flow', () async {
      SyncFlowDebugger.start('user-error-test');
      
      SyncFlowDebugger.logStep('SYNC_STARTED', 'User initiated sync');
      SyncFlowDebugger.logStep('GMAIL_AUTH', 'Gmail authenticated');
      SyncFlowDebugger.logStep('EMAIL_FOUND', 'Found 2 emails', data: {'count': 2});
      
      // First email - success
      SyncFlowDebugger.logStep('EMAIL_PROCESSED', 'Processing email 1/2');
      SyncFlowDebugger.logStep('PDF_UNLOCKED', 'PDF unlocked');
      SyncFlowDebugger.logStep('TRANSACTION_STORED', 'Stored transactions', data: {'count': 25});
      
      // Second email - PDF unlock error
      SyncFlowDebugger.logStep('EMAIL_PROCESSED', 'Processing email 2/2');
      SyncFlowDebugger.logError('PDF_UNLOCK', 'Failed to unlock PDF after 5 attempts', 
        exception: Exception('Invalid password'));
      SyncFlowDebugger.logStep('SKIP_EMAIL', 'Skipping email due to unlock failure');
      
      // Generate report
      final report = SyncFlowDebugger.generateReport();
      
      print('\n' + '=' * 80);
      print('ERROR SCENARIO TEST REPORT');
      print('=' * 80);
      print(report);
      print('=' * 80);
      
      // Verify error handling
      final errors = SyncFlowDebugger.getErrors();
      expect(errors.length, 1);
      expect(errors.first, contains('PDF_UNLOCK'));
      
      // Verify partial success
      expect(report, contains('Errors: 1'));
      final txStored = SyncFlowDebugger.getStepsByName('TRANSACTION_STORED');
      expect(txStored.length, 1); // Only first email succeeded
    });

    test('should track performance metrics accurately', () async {
      SyncFlowDebugger.start('user-performance-test');
      
      // Simulate operations with varying durations
      final operations = [
        {'name': 'Fast Operation', 'duration': 10},
        {'name': 'Medium Operation', 'duration': 50},
        {'name': 'Slow Operation', 'duration': 200},
      ];
      
      for (final op in operations) {
        final timer = SyncFlowDebugger.startTimer(op['name'] as String);
        await Future.delayed(Duration(milliseconds: op['duration'] as int));
        SyncFlowDebugger.endTimer(op['name'] as String, timer);
      }
      
      final report = SyncFlowDebugger.generateReport();
      
      print('\n' + '=' * 80);
      print('PERFORMANCE METRICS TEST REPORT');
      print('=' * 80);
      print(report);
      print('=' * 80);
      
      // Verify timing section exists
      expect(report, contains('Timed Operations'));
      expect(report, contains('Fast Operation'));
      expect(report, contains('Medium Operation'));
      expect(report, contains('Slow Operation'));
      
      // Slow operation should be listed first (sorted by duration desc)
      final slowIndex = report.indexOf('Slow Operation');
      final fastIndex = report.indexOf('Fast Operation');
      expect(slowIndex < fastIndex, true);
    });
  });
}
