# 🔍 Sync Flow Debugging - Quick Reference

## Debug Commands

### Start a Debug Session
```dart
SyncFlowDebugger.start('user-id-123');
```

### Log a Step
```dart
SyncFlowDebugger.logStep('STEP_NAME', 'Message', data: {'key': 'value'});
```

### Log an Error
```dart
SyncFlowDebugger.logError('STEP_NAME', 'Error message', exception: e);
```

### Time an Operation
```dart
final timer = SyncFlowDebugger.startTimer('Operation Name');
// ... do work ...
SyncFlowDebugger.endTimer('Operation Name', timer);
```

### Generate Report
```dart
SyncFlowDebugger.printReport();
```

---

## Standard Step Names

Use these consistent step names for better reporting:

| Step Name | Description | When to Use |
|-----------|-------------|-------------|
| `SYNC_STARTED` | Sync initiated | Start of sync flow |
| `GMAIL_AUTH` | Gmail authenticated | After successful Gmail auth |
| `GMAIL_SEARCH` | Searching emails | Before email search |
| `EMAIL_FOUND` | Emails found | After email search results |
| `EMAIL_PROCESSED` | Processing email | Start of each email |
| `PDF_DOWNLOAD` | Downloading PDF | PDF attachment download |
| `PDF_LOCKED` | PDF is locked | Before password attempts |
| `PDF_UNLOCKED` | PDF unlocked | After successful unlock |
| `GEMINI_PARSE` | Gemini AI parsing | Before Gemini API call |
| `STATEMENT_INFO` | Statement parsed | After statement extraction |
| `TRANSACTION_PARSE` | Transaction parsing | Transaction extraction |
| `CARD_MAPPING` | Card mapping | Card catalog lookup |
| `DB_STORED` | Database storage | Statement stored |
| `TRANSACTION_STORED` | Transactions saved | Transactions inserted |
| `VALIDATION_FAIL` | Validation failed | Validation check failed |
| `SKIP_EMAIL` | Email skipped | Skip processing |

---

## Integration Points

### 1. DashboardOperationsService
```dart
static Future<bool> syncDataFromGmail(...) async {
  SyncFlowDebugger.start(userId);
  SyncFlowDebugger.logStep('SYNC_STARTED', 'User initiated sync', data: {
    'numberOfEmails': numberOfEmails,
    'startDate': startDate?.toIso8601String(),
  });
  // ... rest of code
}
```

### 2. EnhancedGmailService
```dart
Future<List<StatementParsingResult>> processStatementEmails(...) async {
  SyncFlowDebugger.logStep('GMAIL_SEARCH', 'Searching emails');
  // ... search code
  SyncFlowDebugger.logStep('EMAIL_FOUND', 'Found emails', data: {'count': results.length});
}
```

### 3. DataPipelineDebugService
```dart
Future<bool> _processEmailSequentially(...) async {
  final timer = SyncFlowDebugger.startTimer('Email ${emailIndex}');
  SyncFlowDebugger.logStep('EMAIL_PROCESSED', 'Processing', data: {
    'bank': statement.bankName,
  });
  // ... processing
  SyncFlowDebugger.endTimer('Email ${emailIndex}', timer);
}
```

### 4. PdfPasswordDetectionService
```dart
Future<String?> findPasswordAndExtractText(...) async {
  SyncFlowDebugger.logStep('PDF_LOCKED', 'Attempting unlock');
  // ... unlock attempts
  if (success) {
    SyncFlowDebugger.logStep('PDF_UNLOCKED', 'Unlocked', data: {
      'method': 'automatic',
    });
  }
}
```

### 5. GeminiTransactionParser
```dart
static Future<Map<String, dynamic>> parseStatementInfo(...) async {
  SyncFlowDebugger.logStep('GEMINI_PARSE', 'Parsing statement');
  // ... Gemini API call
  SyncFlowDebugger.logStep('STATEMENT_INFO', 'Extracted', data: result);
}
```

---

## Reading the Report

### Header
```
╔════════════════════════════════════════════════════════════════════╗
║              SYNC FLOW DEBUG REPORT                                ║
╚════════════════════════════════════════════════════════════════════╝
```

### Session Summary
- **User ID**: Who triggered the sync
- **Total Duration**: Total time from start to finish
- **Total Steps**: Number of operations logged
- **Errors**: Number of errors encountered

### Step Execution Counts
Shows how many times each step was executed:
```
📈 Step Execution Counts
  TRANSACTION_STORED                      142 times
  EMAIL_PROCESSED                           3 times
  PDF_UNLOCKED                              3 times
```

### Timed Operations
Shows duration of timed operations (slowest first):
```
⏱️  Timed Operations
  Gemini Parse Transactions            3245ms
  Store to Database                    1823ms
  Process Email 1                      8934ms
```

### Timeline
Chronological log of all steps:
```
📧 [0s]      EMAIL_FOUND               Found statement emails
└─ count: 3

📄 [1s]      EMAIL_PROCESSED           Processing email 1/3
└─ bank: HDFC
└─ pdfSize: 2348952
```

### Key Metrics
Summary of important counts:
```
🎯 Key Metrics
  📧 Emails Processed: 3
  💾 Statements Stored: 3
  💰 Transactions Stored: 142
  🔓 PDFs Unlocked: 3
  ❌ Errors: 0
```

---

## Troubleshooting Guide

### No Emails Found
**Check these steps:**
- `GMAIL_AUTH`: Was authentication successful?
- `GMAIL_SEARCH`: What were the search parameters?
- Check date range and filters

### PDF Won't Unlock
**Check these steps:**
- `PDF_LOCKED`: How many attempts were made?
- Look for DOB in data: was it fetched correctly?
- Check if manual password was triggered

### Gemini Parsing Failed
**Check these steps:**
- `GEMINI_PARSE`: Was the API call made?
- Look for error messages in timeline
- Check PDF text length (too short/long?)

### Transactions Not Stored
**Check these steps:**
- `TRANSACTION_PARSE`: Were transactions extracted?
- `VALIDATION_FAIL`: Did validation pass?
- `CARD_MAPPING`: Was card mapping successful?
- `DB_STORED`: Check for database errors

### Performance Issues
**Check timed operations:**
- Which operations took longest?
- Are there excessive Gemini calls?
- Is database storage slow?

---

## Best Practices

### 1. Always Start Session
```dart
// First line in sync flow
SyncFlowDebugger.start(userId);
```

### 2. Log Key Data
```dart
// Include relevant data for debugging
SyncFlowDebugger.logStep('CARD_MAPPING', 'Looking up card', data: {
  'bank': bankName,
  'cardVariant': variantName,
  'existingUserCards': userCards.length,
});
```

### 3. Time Long Operations
```dart
final timer = SyncFlowDebugger.startTimer('Long Operation');
try {
  // ... operation ...
} finally {
  SyncFlowDebugger.endTimer('Long Operation', timer);
}
```

### 4. Catch and Log Errors
```dart
try {
  // ... risky operation ...
} catch (e, stackTrace) {
  SyncFlowDebugger.logError('STEP_NAME', 'Failed', 
    exception: e, 
    stackTrace: stackTrace
  );
  rethrow;
}
```

### 5. Generate Report at End
```dart
try {
  // ... sync flow ...
} finally {
  // Always generate report, even on error
  SyncFlowDebugger.printReport();
}
```

---

## Example Output

```dart
🐛 [SYNC DEBUG] Session started for user: abc-123
================================================================================
🚀 [0:00:00] SYNC_STARTED: User clicked sync button
🔐 [0:00:01] GMAIL_AUTH: Authenticated with Gmail
🔍 [0:00:02] GMAIL_SEARCH: Searching for statements
📧 [0:00:04] EMAIL_FOUND: Found 3 statement emails
📄 [0:00:05] EMAIL_PROCESSED: Processing email 1/3 (HDFC)
🔓 [0:00:07] PDF_UNLOCKED: Unlocked with DOB password
🤖 [0:00:08] GEMINI_PARSE: Extracting statement info
📊 [0:00:12] STATEMENT_INFO: Due: ₹28,750, Date: 2025-05-16
🤖 [0:00:13] TRANSACTION_PARSE: Parsing transactions
💳 [0:00:18] TRANSACTION_PARSE: Found 47 transactions
🗂️ [0:00:19] CARD_MAPPING: Mapped to existing card
💾 [0:00:20] DB_STORED: Statement saved
✅ [0:00:23] TRANSACTION_STORED: 47 transactions saved
... (repeat for emails 2-3) ...

╔════════════════════════════════════════════════════════════════════╗
║              SYNC FLOW DEBUG REPORT                                ║
╚════════════════════════════════════════════════════════════════════╝

📊 Session Summary
  User ID: abc-123
  Total Duration: 65s
  Total Steps: 156
  Errors: 0

🎯 Key Metrics
  📧 Emails Processed: 3
  💾 Statements Stored: 3
  💰 Transactions Stored: 142
  🔓 PDFs Unlocked: 3
```

---

## Tips

1. **Clear Before New Session**: Session data accumulates. Clear if running multiple syncs:
   ```dart
   SyncFlowDebugger.clear();
   SyncFlowDebugger.start(newUserId);
   ```

2. **Filter Steps**: Get specific steps for analysis:
   ```dart
   final errors = SyncFlowDebugger.getStepsByName('VALIDATION_FAIL');
   print('Failed validations: ${errors.length}');
   ```

3. **Export Report**: Save report to file for later analysis:
   ```dart
   final report = SyncFlowDebugger.generateReport();
   File('debug_report.txt').writeAsStringSync(report);
   ```

4. **Conditional Debugging**: Only enable in debug mode:
   ```dart
   if (kDebugMode) {
     SyncFlowDebugger.start(userId);
   }
   ```
