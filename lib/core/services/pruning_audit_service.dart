import 'package:hive/hive.dart';

/// Service to track and audit PDF statement text pruning logs
class PruningAuditService {
  static final PruningAuditService _instance = PruningAuditService._internal();
  factory PruningAuditService() => _instance;
  PruningAuditService._internal();

  static const String _boxName = 'pdf_pruning_audit_logs';

  /// Log a PDF statement text pruning event
  Future<void> logPruning({
    required String bankName,
    required String cardVariant,
    required String originalText,
    required String prunedText,
    String? fileName,
  }) async {
    try {
      if (originalText.isEmpty) return;

      final box = await Hive.openBox(_boxName);

      // Simple duplicate prevention: check if the last saved log was for the same original text
      // to avoid duplicates due to sequential statement_info & transaction parsing calls.
      final logs = box.values.toList();
      if (logs.isNotEmpty) {
        // Sort by timestamp or ID descending
        final sortedLogs = List<Map<dynamic, dynamic>>.from(logs)
          ..sort((a, b) => (b['timestamp'] as String).compareTo(a['timestamp'] as String));
        final lastLog = sortedLogs.first;
        if (lastLog['originalLength'] == originalText.length && 
            lastLog['bankName'] == bankName &&
            lastLog['cardVariant'] == cardVariant) {
          // It's the same file processed twice (e.g. statement info then transaction parse), skip
          print('ℹ️ Pruning log duplicate detected, skipping redundant entry.');
          return;
        }
      }

      final originalLength = originalText.length;
      final prunedLength = prunedText.length;
      final prunedChars = originalLength - prunedLength;
      
      // Calculate what marker cut the text
      String matchedMarker = 'None';
      final lowerOriginal = originalText.toLowerCase();
      final markers = [
        'most important terms & conditions',
        'most important terms and conditions',
        'mitc',
        'important information for cardholders',
        'important information',
        'rights of cardholder',
        'cardholder agreement',
        'dispute redressal',
        'grievance redressal',
        'branch addresses',
        'list of branches',
      ];
      for (final marker in markers) {
        if (lowerOriginal.contains(marker) && !prunedText.toLowerCase().contains(marker)) {
          matchedMarker = marker;
          break;
        }
      }

      final removedText = originalLength > prunedLength ? originalText.substring(prunedLength) : '';
      final potentialLeaks = detectPotentialLeaks(removedText);

      final logEntry = {
        'id': DateTime.now().microsecondsSinceEpoch.toString(),
        'bankName': bankName,
        'cardVariant': cardVariant,
        'timestamp': DateTime.now().toIso8601String(),
        'originalText': originalText,
        'prunedText': prunedText,
        'removedText': removedText,
        'originalLength': originalLength,
        'prunedLength': prunedLength,
        'prunedCharacters': prunedChars,
        'reductionRatio': originalLength > 0 ? (prunedChars / originalLength) * 100 : 0.0,
        'cutMarker': matchedMarker,
        'fileName': fileName ?? '${bankName.replaceAll(' ', '_')}_Statement.pdf',
        'potentialLeaks': potentialLeaks,
        'isFlagged': potentialLeaks.isNotEmpty,
        'reviewStatus': potentialLeaks.isNotEmpty ? 'Needs PM Review' : 'Clean', // 'Clean', 'Needs PM Review', 'Confirmed', 'Flagged'
        'pmComment': '',
      };

      await box.put(logEntry['id'], logEntry);
      print('💾 Saved PDF pruning log to local Hive box: ${logEntry['id']} (Reduction: ${((logEntry['reductionRatio'] as double?) ?? 0.0).toStringAsFixed(1)}%)');
    } catch (e) {
      print('❌ Failed to log pruning event: $e');
    }
  }

  /// Scan removed boilerplate text for potential transaction indicators
  List<Map<String, dynamic>> detectPotentialLeaks(String removedText) {
    final lines = removedText.split('\n');
    final leaks = <Map<String, dynamic>>[];
    
    // Match date formats like 28/05/2026, 28-05-2026, 05 May 26, etc.
    final dateRegex = RegExp(r'\b\d{2}[-/.]\d{2}[-/.]\d{2,4}\b|\b\d{2}\s+(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\s+\d{2,4}\b', caseSensitive: false);
    // Match currency amounts like Rs. 5,200.00, ₹149.00, 2500.00 CR, etc.
    final currencyRegex = RegExp(r'(?:Rs\.?|₹|INR)\s*[\d,]+\.?\d*|\b[\d,]+\.\d{2}\s*(?:CR|DR|Cr|Dr|C|D)\b', caseSensitive: false);
    // Match common credit card transaction keywords
    final merchantRegex = RegExp(r'swiggy|zomato|amazon|flipkart|uber|ola|petrol|payment received|paytm|gpay|phonepe|netflix|spotify|interest charged|finance charge', caseSensitive: false);

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.length < 15 || line.length > 200) continue; // Skip too short or too long sentences
      
      bool hasDate = dateRegex.hasMatch(line);
      bool hasCurrency = currencyRegex.hasMatch(line);
      bool hasMerchant = merchantRegex.hasMatch(line);
      
      // A transaction row typically contains Date + Amount or Merchant + Amount
      if ((hasDate && hasCurrency) || (hasMerchant && hasCurrency)) {
        String reason = '';
        if (hasMerchant && hasCurrency) {
          reason = 'Merchant & Currency match';
        } else if (hasDate && hasCurrency) {
          reason = 'Date & Currency match';
        }
        
        leaks.add({
          'lineNumber': i + 1,
          'lineContent': line,
          'reason': reason,
        });
      }
    }
    return leaks;
  }

  /// Retrieve all logged items, sorted by newest first
  Future<List<Map<String, dynamic>>> getLogs() async {
    try {
      final box = await Hive.openBox(_boxName);
      if (box.isEmpty) {
        // If box is empty, seed it with mock statements so Product Managers see data immediately
        await seedMockLogs();
      }
      
      final list = box.values.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      list.sort((a, b) => (b['timestamp'] as String).compareTo(a['timestamp'] as String));
      return list;
    } catch (e) {
      print('❌ Failed to retrieve pruning logs: $e');
      return [];
    }
  }

  /// Update the review status and comments on a log entry
  Future<void> updateLogStatus(String id, String status, String comment) async {
    try {
      final box = await Hive.openBox(_boxName);
      final log = box.get(id);
      if (log != null) {
        final updated = Map<String, dynamic>.from(log as Map);
        updated['reviewStatus'] = status;
        updated['pmComment'] = comment;
        updated['isFlagged'] = status == 'Flagged' || status == 'Needs PM Review';
        await box.put(id, updated);
        print('✏️ Updated pruning log $id to status: $status');
      }
    } catch (e) {
      print('❌ Failed to update log status: $e');
    }
  }

  /// Delete a log entry
  Future<void> deleteLog(String id) async {
    try {
      final box = await Hive.openBox(_boxName);
      await box.delete(id);
    } catch (e) {
      print('❌ Failed to delete log entry: $e');
    }
  }

  /// Clear all log entries
  Future<void> clearLogs() async {
    try {
      final box = await Hive.openBox(_boxName);
      await box.clear();
    } catch (e) {
      print('❌ Failed to clear pruning logs: $e');
    }
  }

  /// Seed initial logs for PM demonstration
  Future<void> seedMockLogs() async {
    try {
      final box = await Hive.openBox(_boxName);
      
      // Mock Log 1: SBI BPCL (from prompt, correctly pruned, no leaks)
      final originalSbiText = _getSbiOriginalMockText();
      final prunedSbiText = _getSbiPrunedMockText();
      final sbiLog = {
        'id': 'mock-audit-sbi',
        'bankName': 'SBI Card',
        'cardVariant': 'Bpcl',
        'timestamp': DateTime.now().subtract(const Duration(minutes: 5)).toIso8601String(),
        'originalText': originalSbiText,
        'prunedText': prunedSbiText,
        'removedText': originalSbiText.substring(prunedSbiText.length),
        'originalLength': originalSbiText.length,
        'prunedLength': prunedSbiText.length,
        'prunedCharacters': originalSbiText.length - prunedSbiText.length,
        'reductionRatio': ((originalSbiText.length - prunedSbiText.length) / originalSbiText.length) * 100,
        'cutMarker': 'most important terms & conditions',
        'fileName': 'SBI_BPCL_Statement_Jul2026.pdf',
        'potentialLeaks': [], // Clean!
        'isFlagged': false,
        'reviewStatus': 'Confirmed',
        'pmComment': 'Reviewed. Correctly cut at the MITC boilerplate section. No transaction rows affected.',
      };

      // Mock Log 2: HDFC Regalia (Accidentally cut a transaction! Warning flag raised!)
      final originalHdfcText = _getHdfcOriginalMockText();
      final prunedHdfcText = _getHdfcPrunedMockText();
      final removedHdfcText = originalHdfcText.substring(prunedHdfcText.length);
      final hdfcLeaks = detectPotentialLeaks(removedHdfcText);
      final hdfcLog = {
        'id': 'mock-audit-hdfc',
        'bankName': 'HDFC Bank',
        'cardVariant': 'Regalia Gold',
        'timestamp': DateTime.now().subtract(const Duration(hours: 1)).toIso8601String(),
        'originalText': originalHdfcText,
        'prunedText': prunedHdfcText,
        'removedText': removedHdfcText,
        'originalLength': originalHdfcText.length,
        'prunedLength': prunedHdfcText.length,
        'prunedCharacters': originalHdfcText.length - prunedHdfcText.length,
        'reductionRatio': ((originalHdfcText.length - prunedHdfcText.length) / originalHdfcText.length) * 100,
        'cutMarker': 'important information',
        'fileName': 'HDFC_Regalia_Statement_Jun2026.pdf',
        'potentialLeaks': hdfcLeaks, // Has leaks!
        'isFlagged': hdfcLeaks.isNotEmpty,
        'reviewStatus': 'Needs PM Review',
        'pmComment': '',
      };

      // Mock Log 3: ICICI Amazon Pay (Clean pruning)
      final originalIciciText = _getIciciOriginalMockText();
      final prunedIciciText = _getIciciPrunedMockText();
      final iciciLog = {
        'id': 'mock-audit-icici',
        'bankName': 'ICICI Bank',
        'cardVariant': 'Amazon Pay',
        'timestamp': DateTime.now().subtract(const Duration(days: 1)).toIso8601String(),
        'originalText': originalIciciText,
        'prunedText': prunedIciciText,
        'removedText': originalIciciText.substring(prunedIciciText.length),
        'originalLength': originalIciciText.length,
        'prunedLength': prunedIciciText.length,
        'prunedCharacters': originalIciciText.length - prunedIciciText.length,
        'reductionRatio': ((originalIciciText.length - prunedIciciText.length) / originalIciciText.length) * 100,
        'cutMarker': 'dispute redressal',
        'fileName': 'ICICI_AmazonPay_Statement_Jun2026.pdf',
        'potentialLeaks': [],
        'isFlagged': false,
        'reviewStatus': 'Clean',
        'pmComment': '',
      };

      await box.put(sbiLog['id'], sbiLog);
      await box.put(hdfcLog['id'], hdfcLog);
      await box.put(iciciLog['id'], iciciLog);
    } catch (e) {
      print('❌ Failed to seed mock pruning logs: $e');
    }
  }

  // --- Mock text helpers ---
  String _getSbiOriginalMockText() {
    return '''
SBI CARD BPCL MONTHLY STATEMENT
Statement Date: 12-Jul-2026
Card Number: **** **** **** 4321
Credit Limit: Rs. 150,000.00
Payment Due Date: 02-Aug-2026

Transactions:
05 Jul 26  SWIGGY BANGALORE         450.00 D
07 Jul 26  AMAZON.IN               1200.00 D
09 Jul 26  INDIAN OIL PETROL PUMP  2000.00 D
10 Jul 26  PAYMENT RECEIVED BY NET -3650.00 C

MOST IMPORTANT TERMS & CONDITIONS (MITC)
1. Late Payment Charges:
- Nil for amount due up to Rs 100.
- Rs. 100 for amount from Rs. 101 to Rs. 500.
- Rs. 500 for amount from Rs. 501 to Rs. 1000.
- Rs. 750 for amount from Rs. 1001 to Rs. 10000.
- Rs. 950 for amount greater than Rs. 10000.

2. Interest Rates:
- Finance charge is 3.5% per month (42% per annum) for SBI cards.
- Interest is calculated from the date of transaction.

3. Dispute Redressal:
Please call customer care at 1860-180-1290 or write to feedback@sbicards.com.
Grievances can be escalated to the Nodal Officer at Gurgaon.
''';
  }

  String _getSbiPrunedMockText() {
    return '''
SBI CARD BPCL MONTHLY STATEMENT
Statement Date: 12-Jul-2026
Card Number: **** **** **** 4321
Credit Limit: Rs. 150,000.00
Payment Due Date: 02-Aug-2026

Transactions:
05 Jul 26  SWIGGY BANGALORE         450.00 D
07 Jul 26  AMAZON.IN               1200.00 D
09 Jul 26  INDIAN OIL PETROL PUMP  2000.00 D
10 Jul 26  PAYMENT RECEIVED BY NET -3650.00 C
'''.trim() + '\n';
  }

  String _getHdfcOriginalMockText() {
    return '''
HDFC BANK REGALIA CREDIT CARD
Statement Period: 15-May-2026 to 14-Jun-2026
Closing Balance: Rs. 28,450.00
Minimum Payment: Rs. 1,422.00

Domestic Transactions:
16 May 26  ZOMATO ORDER            520.00
18 May 26  FLIPKART INTERNET      8499.00
22 May 26  NETFLIX IND            649.00
25 May 26  HDFC REWARDS CREDITED -1000.00 Cr

IMPORTANT INFORMATION
Please verify transactions on statement. Discrepancies if any must be reported within 30 days.
29 May 26  LATE FEE INTEREST CHARGE  120.00
30 May 26  SWIGGY MEALS            280.00
Grievance Cell: HDFC Bank Cards Division, Chennai - 600002.
Toll free Nodal Helpdesk: 1800-266-4332.
''';
  }

  String _getHdfcPrunedMockText() {
    return '''
HDFC BANK REGALIA CREDIT CARD
Statement Period: 15-May-2026 to 14-Jun-2026
Closing Balance: Rs. 28,450.00
Minimum Payment: Rs. 1,422.00

Domestic Transactions:
16 May 26  ZOMATO ORDER            520.00
18 May 26  FLIPKART INTERNET      8499.00
22 May 26  NETFLIX IND            649.00
25 May 26  HDFC REWARDS CREDITED -1000.00 Cr
'''.trim() + '\n';
  }

  String _getIciciOriginalMockText() {
    return '''
ICICI BANK AMAZON PAY CREDIT CARD STATEMENT
Statement Date: 20-Jun-2026
Due Date: 10-Jul-2026
Total Due: Rs. 12,380.00

Transactions details:
22 May 26 AMAZON PAY ORDER       4500.00
25 May 26 UBER INDIA TRIP         350.00
28 May 26 SWIGGY BANGALORE        620.00
05 Jun 26 ONE CARD AUTO DEBIT   -12380.00 Cr

DISPUTE REDRESSAL PROTOCOLS
In case of any unauthorized transaction, report immediately to 1800-200-3344.
Email: headservicequality@icicibank.com.
If not resolved in 30 days, register complaint with Banking Ombudsman.
''';
  }

  String _getIciciPrunedMockText() {
    return '''
ICICI BANK AMAZON PAY CREDIT CARD STATEMENT
Statement Date: 20-Jun-2026
Due Date: 10-Jul-2026
Total Due: Rs. 12,380.00

Transactions details:
22 May 26 AMAZON PAY ORDER       4500.00
25 May 26 UBER INDIA TRIP         350.00
28 May 26 SWIGGY BANGALORE        620.00
05 Jun 26 ONE CARD AUTO DEBIT   -12380.00 Cr
'''.trim() + '\n';
  }
}
