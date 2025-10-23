// Example: How to integrate SyncFlowDebugger into existing code
// This shows the key integration points in the sync flow
//
// NOTE: This file contains example code snippets showing WHERE to add debug calls.
// These are not meant to be compiled - they show integration patterns.
// Copy the relevant SyncFlowDebugger.logStep() calls into your actual code.

// ignore_for_file: unused_element, undefined_identifier

import 'package:cardcompass/debug/sync_flow_debugger.dart';

/// STEP 1: In DashboardOperationsService.syncDataFromGmail()
/// Add at the very beginning:
void example_syncDataFromGmail() {
  // Example variables (your actual code will have these)
  // final userId = '...';
  // final numberOfEmails = 30;
  // final startDate = DateTime.now();
  // Start debugging session
  SyncFlowDebugger.start('user-123-abc');
  SyncFlowDebugger.logStep('SYNC_STARTED', 'User initiated sync', data: {
    'numberOfEmails': 30,
    'startDate': DateTime.now().subtract(Duration(days: 30)).toIso8601String(),
  });
  
  // ... existing code ...
}

/// STEP 2: In EnhancedGmailService.processStatementEmails()
/// Add after authentication:
void example_gmailSearch() {
  // Example variables (your actual code will have these)
  // final startDate = ...;
  // final endDate = ...;
  // final maxEmails = ...;
  // final allStatements = [...];
  
  SyncFlowDebugger.logStep('GMAIL_AUTH', 'Gmail API authenticated successfully');
  
  // Before search
  // SyncFlowDebugger.logStep('GMAIL_SEARCH', 'Searching for statement emails', data: {
  //   'startDate': startDate.toIso8601String(),
  //   'endDate': endDate.toIso8601String(),
  //   'maxEmails': maxEmails,
  // });
  
  // After search
  // SyncFlowDebugger.logStep('EMAIL_FOUND', 'Found statement emails', data: {
  //   'count': allStatements.length,
  // });
}

/// STEP 3: In DataPipelineDebugService._processEmailSequentially()
/// Add at the start of each email processing:
void example_processEmail() {
  // Example variables (your actual code will have these)
  // final emailIndex = 1;
  // final totalEmails = 3;
  // final statement = ...;
  
  // final emailTimer = SyncFlowDebugger.startTimer('Process Email $emailIndex');
  
  // SyncFlowDebugger.logStep('EMAIL_PROCESSED', 'Processing email $emailIndex/$totalEmails', data: {
  //   'bank': statement.bankName,
  //   'date': statement.statementDate.toIso8601String(),
  //   'pdfSize': statement.originalPdfData.length,
  // });
  
  // ... PDF processing ...
  
  // SyncFlowDebugger.endTimer('Process Email $emailIndex', emailTimer);
}

/// STEP 4: In PdfPasswordDetectionService.findPasswordAndExtractText()
/// Add password unlock tracking:
void example_pdfUnlock() {
  // Example variables (your actual code will have these)
  // final bankName = '...';
  // final attemptCount = 3;
  // final extractedText = '...';
  
  // When trying auto passwords
  // SyncFlowDebugger.logStep('PDF_LOCKED', 'Attempting automatic password unlock', data: {
  //   'bankName': bankName,
  //   'attemptCount': attemptCount,
  // });
  
  // On success
  // SyncFlowDebugger.logStep('PDF_UNLOCKED', 'PDF unlocked successfully', data: {
  //   'method': 'automatic',
  //   'passwordType': 'DOB-based',
  //   'textLength': extractedText.length,
  // });
  
  // On manual password required
  // SyncFlowDebugger.logStep('PDF_LOCKED', 'Manual password required', data: {
  //   'autoAttempts': attemptCount,
  // });
}

/// STEP 5: In GeminiTransactionParser.parseStatementInfo()
/// Add AI parsing tracking:
void example_geminiParsing() {
  // Example variables (your actual code will have these)
  // final bankName = '...';
  // final pdfText = '...';
  // final result = {...};
  
  // final geminiTimer = SyncFlowDebugger.startTimer('Gemini Parse Statement');
  
  // SyncFlowDebugger.logStep('GEMINI_PARSE', 'Requesting statement info from Gemini AI', data: {
  //   'bankName': bankName,
  //   'textLength': pdfText.length,
  // });
  
  // After response
  // SyncFlowDebugger.logStep('STATEMENT_INFO', 'Statement info extracted', data: {
  //   'statementDate': result['statement_date'],
  //   'totalAmount': result['total_amount'],
  //   'dueDate': result['due_date'],
  // });
  
  // SyncFlowDebugger.endTimer('Gemini Parse Statement', geminiTimer);
}

/// STEP 6: In GeminiTransactionParser.parseTransactions()
/// Add transaction parsing tracking:
void example_transactionParsing() {
  // Example variables (your actual code will have these)
  // final bankName = '...';
  // final transactions = [...];
  
  // final parseTimer = SyncFlowDebugger.startTimer('Gemini Parse Transactions');
  
  // SyncFlowDebugger.logStep('TRANSACTION_PARSE', 'Parsing transactions with Gemini AI', data: {
  //   'bankName': bankName,
  // });
  
  // After parsing
  // SyncFlowDebugger.logStep('TRANSACTION_PARSE', 'Transactions parsed successfully', data: {
  //   'count': transactions.length,
  //   'categories': _getCategoryCounts(transactions),
  // });
  
  // SyncFlowDebugger.endTimer('Gemini Parse Transactions', parseTimer);
}

/// STEP 7: In DataPipelineDebugService._ensureCreditCardExistsWithUserCard()
/// Add card mapping tracking:
void example_cardMapping() {
  // Example variables (your actual code will have these)
  // final bankName = '...';
  // final cardVariantName = '...';
  // final catalogCardId = '...';
  // final userCardId = '...';
  // final cardName = '...';
  
  // SyncFlowDebugger.logStep('CARD_MAPPING', 'Looking for existing user card', data: {
  //   'bankName': bankName,
  //   'cardVariant': cardVariantName,
  // });
  
  // If found
  // SyncFlowDebugger.logStep('CARD_MAPPING', 'Found existing user card', data: {
  //   'catalogCardId': catalogCardId,
  //   'userCardId': userCardId,
  // });
  
  // If creating new
  // SyncFlowDebugger.logStep('CARD_MAPPING', 'Creating new card association', data: {
  //   'bankName': bankName,
  //   'cardName': cardName,
  // });
}

/// STEP 8: In DataPipelineDebugService._storeStatementToDatabase()
/// Add database storage tracking:
void example_databaseStorage() {
  // Example variables (your actual code will have these)
  // final userCardId = '...';
  // final statement = ...;
  
  // final dbTimer = SyncFlowDebugger.startTimer('Store to Database');
  
  // SyncFlowDebugger.logStep('DB_STORED', 'Storing statement to database', data: {
  //   'userCardId': userCardId,
  //   'transactionCount': statement.transactions.length,
  // });
  
  // After transactions stored
  // SyncFlowDebugger.logStep('TRANSACTION_STORED', 'Transactions stored', data: {
  //   'count': statement.transactions.length,
  // });
  
  // SyncFlowDebugger.endTimer('Store to Database', dbTimer);
}

/// STEP 9: In DataPipelineDebugService._processEmailSequentially()
/// Add validation failure tracking:
void example_validationFailure() {
  // Example variables (your actual code will have these)
  // final transactionCount = 0;
  // final statement = ...;
  
  // In your actual function that returns bool:
  // if (transactionCount == 0) {
  //   SyncFlowDebugger.logStep('VALIDATION_FAIL', 'No transactions found', data: {
  //     'bank': statement.bankName,
  //     'pdfSize': statement.originalPdfData.length,
  //   });
  //   
  //   SyncFlowDebugger.logStep('SKIP_EMAIL', 'Skipping email - validation failed');
  //   return false;  // This return is in your actual code
  // }
}

/// STEP 10: At the end of DataPipelineDebugService.debugSequentialUserFlow()
/// Generate and print the report:
void example_generateReport() {
  // Print summary
  print('\n' + '=' * 80);
  print('🎯 SYNC FLOW COMPLETE');
  print('=' * 80);
  
  // Generate and print detailed report
  SyncFlowDebugger.printReport();
  
  // Get specific metrics
  final errors = SyncFlowDebugger.getErrors();
  if (errors.isNotEmpty) {
    print('\n⚠️  ATTENTION: ${errors.length} errors occurred');
    for (final error in errors) {
      print('  • $error');
    }
  }
}

/// STEP 11: Error handling example
void example_errorHandling() {
  try {
    // ... some operation ...
  } catch (e, stackTrace) {
    SyncFlowDebugger.logError(
      'PDF_UNLOCK',
      'Failed to unlock PDF',
      exception: e,
      stackTrace: stackTrace,
    );
  }
}

/// Helper function to get category counts
Map<String, int> _getCategoryCounts(List<Map<String, dynamic>> transactions) {
  final counts = <String, int>{};
  for (final tx in transactions) {
    final category = tx['category'] as String? ?? 'unknown';
    counts[category] = (counts[category] ?? 0) + 1;
  }
  return counts;
}

/// COMPLETE INTEGRATION EXAMPLE
/// 
/// Here's what the debug output will look like:
/// 
/// ```
/// 🐛 [SYNC DEBUG] Session started for user: user-123-abc
/// ================================================================================
/// 🚀 [0:00:00.000000] SYNC_STARTED: User initiated sync | Data: {numberOfEmails: 30, ...}
/// 🔐 [0:00:01.234000] GMAIL_AUTH: Gmail API authenticated successfully
/// 🔍 [0:00:01.500000] GMAIL_SEARCH: Searching for statement emails | Data: {startDate: ...}
/// 📧 [0:00:03.200000] EMAIL_FOUND: Found statement emails | Data: {count: 3}
/// 📄 [0:00:03.250000] EMAIL_PROCESSED: Processing email 1/3 | Data: {bank: HDFC, ...}
/// 🔒 [0:00:03.300000] PDF_LOCKED: Attempting automatic password unlock
/// 🔓 [0:00:03.800000] PDF_UNLOCKED: PDF unlocked successfully | Data: {method: automatic}
/// 🤖 [0:00:04.000000] GEMINI_PARSE: Requesting statement info from Gemini AI
/// 📊 [0:00:06.500000] STATEMENT_INFO: Statement info extracted | Data: {totalAmount: 28750.0}
/// 🤖 [0:00:06.600000] TRANSACTION_PARSE: Parsing transactions with Gemini AI
/// 💳 [0:00:10.200000] TRANSACTION_PARSE: Transactions parsed | Data: {count: 47, ...}
/// 🗂️ [0:00:10.250000] CARD_MAPPING: Looking for existing user card
/// 🗂️ [0:00:10.400000] CARD_MAPPING: Found existing user card | Data: {userCardId: ...}
/// 💾 [0:00:10.500000] DB_STORED: Storing statement to database
/// ✅ [0:00:11.800000] TRANSACTION_STORED: Transactions stored | Data: {count: 47}
/// ...
/// 
/// ╔════════════════════════════════════════════════════════════════════╗
/// ║              SYNC FLOW DEBUG REPORT                                ║
/// ╚════════════════════════════════════════════════════════════════════╝
/// 
/// 📊 Session Summary
///   User ID: user-123-abc
///   Total Duration: 45s (45234ms)
///   Total Steps: 156
///   Errors: 0
/// 
/// 📈 Step Execution Counts
///   TRANSACTION_STORED                      142 times
///   EMAIL_PROCESSED                           3 times
///   PDF_UNLOCKED                              3 times
///   CARD_MAPPING                              3 times
///   ...
/// 
/// 🎯 Key Metrics
///   📧 Emails Processed: 3
///   💾 Statements Stored: 3
///   💰 Transactions Stored: 142
///   🔓 PDFs Unlocked: 3
///   ❌ Errors: 0
/// ```
