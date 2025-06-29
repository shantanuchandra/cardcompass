import 'dart:math';

/// Enhanced transaction parsing service with improved pattern recognition
class TransactionParsingService {
  
  /// Enhanced SBI patterns based on real statement analysis
  static final Map<String, List<RegExp>> enhancedBankPatterns = {
    'sbi': [
      // Format 1: Multi-line SBI format - Date on one line, description on next, amount on next
      // 13 May 25
      // YOUTUBE CYBS SI        MUMBAI        IN
      // 149.00
      // D
      RegExp(r'(\d{1,2}\s+\w{3}\s+\d{2})\s*\n([^\n]+?)\s*\n([\d,]+\.\d{2})\s*\n([DC])', multiLine: true),
      
      // Format 2: Single line SBI format with date in MMM format
      RegExp(r'(\d{1,2}\s+\w{3}\s+\d{2})\s+([A-Za-z0-9\s\.\-&*@#]+?)\s+([\d,]+\.\d{2})\s+([DC])'),
      
      // Format 3: Traditional SBI patterns (fallback)
      // 15/05/2025 16/05/2025 AMAZON.IN 2,500.00
      RegExp(r'(\d{2}\/\d{2}\/\d{4})\s+(\d{2}\/\d{2}\/\d{4})\s+([A-Za-z0-9\s\.\-&*]+?)\s+([\d,]+\.\d{2})(?:\s+(Cr|Dr)?)?'),
      
      // Format 4: Date Description Amount
      // 15/05/2025 PAYTM*GROCERY 1,250.50
      RegExp(r'(\d{2}\/\d{2}\/\d{4})\s+([A-Za-z0-9\s\.\-&*@#]+?)\s+([\d,]+\.\d{2})(?:\s+(Cr|Dr)?)?'),
      
      // Format 5: Transaction with reference numbers
      // 15/05/2025 16/05/2025 UPI/123456789/AMAZON.IN 2,500.00
      RegExp(r'(\d{2}\/\d{2}\/\d{4})\s+(\d{2}\/\d{2}\/\d{4})\s+(UPI\/\d+\/[A-Za-z0-9\s\.\-&*]+?)\s+([\d,]+\.\d{2})(?:\s+(Cr|Dr)?)?'),
      
      // Format 6: Card transactions
      // 15/05/2025 CARD TXN SWIGGY BANGALORE 850.75
      RegExp(r'(\d{2}\/\d{2}\/\d{4})\s+(CARD\s+TXN\s+[A-Za-z0-9\s\.\-&*]+?)\s+([\d,]+\.\d{2})(?:\s+(Cr|Dr)?)?'),
      
      // Format 7: Online transactions
      // 15/05/2025 16/05/2025 POS 123456789012 AMAZON.IN MUMBAI 2,500.00
      RegExp(r'(\d{2}\/\d{2}\/\d{4})\s+(\d{2}\/\d{2}\/\d{4})\s+(POS\s+\d+\s+[A-Za-z0-9\s\.\-&*]+?)\s+([\d,]+\.\d{2})(?:\s+(Cr|Dr)?)?'),
    ],
    
    'hdfc': [
      // HDFC DCB Multi-line format: Date (with timestamp) -> Description -> Amount
      // 16/05/2025 14:39:20
      // TELE TRANSFER CREDIT (Ref# ST251370083000010167944)
      // 28,752.00Cr
      RegExp(r'(\d{2}\/\d{2}\/\d{4}\s+\d{2}:\d{2}:\d{2})\s*\n([^\n]+?)\s*\n\s*([\d,]+\.\d{2}(?:Cr|Dr)?)', multiLine: true),
      
      // HDFC standard patterns
      RegExp(r'(\d{2}\/\d{2}\/\d{4})\s+([A-Za-z0-9\s\.\-&*@#]+?)\s+([\d,]+\.\d{2})(?:\s+(Cr|Dr)?)?'),
      RegExp(r'(\d{2}-\d{2}-\d{4})\s+([A-Za-z0-9\s\.\-&*@#]+?)\s+([\d,]+\.\d{2})(?:\s+(Cr|Dr)?)?'),
    ],
    
    'indusind': [
      // IndusInd multi-line format: Date -> Description -> Category -> Amount (with spaces between)
      // 26/05/2025
      // EAZYDINER PRIVATE LIMI GURGAON IN
      // RESTAURANTS  
      // 9378.00 DR
      RegExp(r'(\d{2}\/\d{2}\/\d{4})\s*\n([A-Za-z0-9\s\.\-&*@#]+?)\s*\n([A-Za-z\s]+?)\s*\n[^\n]*?\n[^\n]*?\n\s*([\d,]+\.\d{2}\s*(?:DR|CR))', multiLine: true),
      
      // IndusInd standard patterns
      RegExp(r'(\d{2}\/\d{2}\/\d{4})\s+([A-Za-z0-9\s\.\-&*@#]+?)\s+([\d,]+\.\d{2})(?:\s+(Dr|Cr)?)?'),
    ],
    
    'icici': [
      // ICICI patterns - handle concatenated format from OCR
      // DateSerNo.Transaction DetailsRewardPointsIntl.#amountAmount (inÁ)...
      RegExp(r'(\d{2}\/\d{2}\/\d{4})\d+([A-Za-z0-9\s\.\-&*@#\/\(\)]+?)\d+([\d,]+\.\d{2})(?:\s+(Cr|Dr)?)?'),
      RegExp(r'(\d{2}\/\d{2}\/\d{4})\s+([A-Za-z0-9\s\.\-&*@#]+?)\s+([\d,]+\.\d{2})(?:\s+(Cr|Dr)?)?'),
      RegExp(r'(\d{2}-\d{2}-\d{4})\s+([A-Za-z0-9\s\.\-&*@#]+?)\s+([\d,]+\.\d{2})(?:\s+(Cr|Dr)?)?'),
    ],
    
    'axis': [
      // Axis patterns - multi-line format observed in test output
      // 23/05/2025
      // BBPS PAYMENT RECEIVED - DP015143165603NAJYJG
      // 149.00 Cr
      RegExp(r'(\d{2}\/\d{2}\/\d{4})\s*\n([A-Za-z0-9\s\.\-&*@#\/\(\)]+?)\s*\n([\d,]+\.\d{2})\s*(Cr|Dr)?', multiLine: true),
      RegExp(r'(\d{2}-\d{2}-\d{4})\s+([A-Za-z0-9\s\.\-&*@#]+?)\s+([\d,]+\.\d{2})(?:\s+(Cr|Dr)?)?'),
    ],
    
    'hsbc': [
      // HSBC patterns based on actual PDF format - DATE | TRANSACTION DETAILS | AMOUNT
      // 10MAY    AP RELIANCE RETAIL LIMITE NOIDA    4,762.50
      RegExp(r'(\d{1,2}MAY|\d{1,2}JUN|\d{1,2}JUL|\d{1,2}AUG|\d{1,2}SEP|\d{1,2}OCT|\d{1,2}NOV|\d{1,2}DEC|\d{1,2}JAN|\d{1,2}FEB|\d{1,2}MAR|\d{1,2}APR)\s+([A-Za-z0-9\s\.\-&*@#]+?)\s+([\d,]+\.\d{2})(?:\s+(Cr|Dr)?)?'),
      
      // HSBC traditional patterns
      RegExp(r'(\d{2}\s+\w{3}\s+\d{4})\s+([A-Za-z0-9\s\.\-&*@#]+?)\s+([\d,]+\.\d{2})(?:\s+(Cr|Dr)?)?'),
      RegExp(r'(\d{2}\/\d{2}\/\d{4})\s+([A-Za-z0-9\s\.\-&*@#]+?)\s+([\d,]+\.\d{2})(?:\s+(Cr|Dr)?)?'),
    ],
    
    'pnb': [
      // PNB patterns - often have different transaction layouts
      RegExp(r'(\d{2}\/\d{2}\/\d{4})\s+([A-Za-z0-9\s\.\-&*@#]+?)\s+([\d,]+\.\d{2})(?:\s+(Cr|Dr)?)?'),
      RegExp(r'(\d{2}-\d{2}-\d{4})\s+([A-Za-z0-9\s\.\-&*@#]+?)\s+([\d,]+\.\d{2})(?:\s+(Cr|Dr)?)?'),
    ],

    'idfc': [
      // IDFC patterns based on actual PDF format
      // Multi-line format: Date -> Description -> Convert -> Amount -> DR/CR
      // 19 May 25
      // HindustanPetroleumCor
      // Convert
      // 3,989.62
      // DR
      RegExp(r'(\d{1,2}\s+\w{3}\s+\d{2})\s*\n([A-Za-z0-9\s\.\-&*@#]+?)\s*\n(?:Convert\s*)?\n\s*([\d,]+\.\d{2})\s*\n(DR|CR)', multiLine: true),
      
      // IDFC standard patterns
      RegExp(r'(\d{2}\/\d{2}\/\d{4})\s+([A-Za-z0-9\s\.\-&*@#]+?)\s+([\d,]+\.\d{2})(?:\s+(Dr|Cr)?)?'),
      RegExp(r'(\d{1,2}\s+\w{3}\s+\d{2})\s+([A-Za-z0-9\s\.\-&*@#]+?)\s+([\d,]+\.\d{2})(?:\s+(Dr|Cr)?)?'),
    ],
    
    'zenith': [
      // Zenith patterns
      RegExp(r'(\d{2}\/\d{2}\/\d{4})\s+([A-Za-z0-9\s\.\-&*@#]+?)\s+([\d,]+\.\d{2})(?:\s+(Cr|Dr)?)?'),
      RegExp(r'(\d{2}-\d{2}-\d{4})\s+([A-Za-z0-9\s\.\-&*@#]+?)\s+([\d,]+\.\d{2})(?:\s+(Cr|Dr)?)?'),
    ],
  };
  
  /// Extract transactions using enhanced patterns and text analysis
  static List<Map<String, dynamic>> extractTransactionsFromText({
    required String text,
    required String bankName,
  }) {    final transactions = <Map<String, dynamic>>[];
    
    // Split text into lines for analysis (filtering already done at PDF extraction level)
    final lines = text.split('\n').where((line) => line.trim().isNotEmpty).toList();
    
    // Look for transaction table markers
    final transactionSectionStart = _findTransactionSectionStart(lines);
    final transactionSectionEnd = _findTransactionSectionEnd(lines, transactionSectionStart);    
    if (transactionSectionStart != -1) {      
      final transactionLines = lines.sublist(
        transactionSectionStart,
        transactionSectionEnd != -1 ? transactionSectionEnd : lines.length,
      );      
      
      print('🔍 Transaction section found: start=${transactionSectionStart}, end=${transactionSectionEnd}, lines=${transactionLines.length}');
      print('🔍 First 10 transaction lines:');
      for (int i = 0; i < 10 && i < transactionLines.length; i++) {
        print('  Line $i: "${transactionLines[i]}"');
      }
      
      // DEBUG: Show more lines for IndusInd specifically 
      if (bankName.toLowerCase() == 'indusind' && transactionLines.length < 20) {
        print('🔍 IndusInd DEBUG: Expanding section to look for more transaction data...');
        final expandedLines = lines.sublist(
          transactionSectionStart,
          min(transactionSectionStart + 50, lines.length),
        );
        print('🔍 Expanded to ${expandedLines.length} lines');
        
        // Try IndusInd extraction on expanded section
        final indusindTransactions = TransactionParsingService.extractIndusIndMultiLineTransactions(expandedLines);
        print('🔍 IndusInd expanded extraction returned ${indusindTransactions.length} transactions');
        if (indusindTransactions.isNotEmpty) {
          transactions.addAll(indusindTransactions);
          print('✅ Added ${indusindTransactions.length} IndusInd expanded transactions. Total now: ${transactions.length}');
        }
      }
      
      // DEBUG: Show more lines for HDFC specifically 
      if (bankName.toLowerCase() == 'hdfc' && transactionLines.length < 20) {
        print('🔍 HDFC DEBUG: Expanding section to look for more transaction data...');
        // Look for "Domestic Transactions" section specifically
        int domesticSectionStart = -1;
        for (int i = 0; i < lines.length; i++) {
          if (lines[i].toLowerCase().contains('domestic transactions')) {
            domesticSectionStart = i;
            print('🔍 HDFC: Found "Domestic Transactions" at line $i');
            break;
          }
        }
        
        if (domesticSectionStart != -1) {
          final expandedLines = lines.sublist(
            domesticSectionStart,
            min(domesticSectionStart + 100, lines.length),
          );
          print('🔍 HDFC: Expanded to ${expandedLines.length} lines from Domestic Transactions section');
          
          // Try HDFC extraction on expanded section
          final hdfcTransactions = TransactionParsingService.extractHDFCMultiLineTransactions(expandedLines);
          print('🔍 HDFC expanded extraction returned ${hdfcTransactions.length} transactions');
          if (hdfcTransactions.isNotEmpty) {
            transactions.addAll(hdfcTransactions);
            print('✅ Added ${hdfcTransactions.length} HDFC expanded transactions. Total now: ${transactions.length}');
          }
        }
      }
      
      // Use enhanced patterns for the specific bank
      final patterns = enhancedBankPatterns[bankName.toLowerCase()] ?? enhancedBankPatterns['sbi']!;
      
      // For SBI, try multi-line extraction first
      if (bankName.toLowerCase() == 'sbi') {
        final sbiTransactions = TransactionParsingService.extractSBIMultiLineTransactions(transactionLines);
        print('🔍 SBI multi-line extraction returned ${sbiTransactions.length} transactions');
        if (sbiTransactions.isNotEmpty) {
          transactions.addAll(sbiTransactions);
          print('✅ Added ${sbiTransactions.length} SBI transactions to main list. Total now: ${transactions.length}');
        }
      }
      
      // For HDFC, try multi-line extraction
      if (bankName.toLowerCase() == 'hdfc') {
        final hdfcTransactions = TransactionParsingService.extractHDFCMultiLineTransactions(transactionLines);
        print('🔍 HDFC multi-line extraction returned ${hdfcTransactions.length} transactions');
        if (hdfcTransactions.isNotEmpty) {
          transactions.addAll(hdfcTransactions);
          print('✅ Added ${hdfcTransactions.length} HDFC transactions to main list. Total now: ${transactions.length}');
        }
      }
      
      // For ICICI, try multi-line extraction
      if (bankName.toLowerCase() == 'icici') {
        final iciciTransactions = TransactionParsingService.extractICICITransactions(transactionLines);
        print('🔍 ICICI extraction returned ${iciciTransactions.length} transactions');
        if (iciciTransactions.isNotEmpty) {
          transactions.addAll(iciciTransactions);
          print('✅ Added ${iciciTransactions.length} ICICI transactions to main list. Total now: ${transactions.length}');
        }
      }
      
      // For Axis, try multi-line extraction
      if (bankName.toLowerCase() == 'axis') {
        final axisTransactions = TransactionParsingService.extractAxisMultiLineTransactions(transactionLines);
        print('🔍 Axis multi-line extraction returned ${axisTransactions.length} transactions');
        if (axisTransactions.isNotEmpty) {
          transactions.addAll(axisTransactions);
          print('✅ Added ${axisTransactions.length} Axis transactions to main list. Total now: ${transactions.length}');
        }
      }
      
      // For IDFC, try multi-line extraction
      if (bankName.toLowerCase() == 'idfc') {
        final idfcTransactions = TransactionParsingService.extractIDFCMultiLineTransactions(transactionLines);
        print('🔍 IDFC multi-line extraction returned ${idfcTransactions.length} transactions');
        if (idfcTransactions.isNotEmpty) {
          transactions.addAll(idfcTransactions);
          print('✅ Added ${idfcTransactions.length} IDFC transactions to main list. Total now: ${transactions.length}');
        }
      }
      
      // For HSBC, try multi-line extraction from ALL lines (not just transaction section)
      if (bankName.toLowerCase() == 'hsbc') {
        final hsbcTransactions = TransactionParsingService.extractHSBCMultiLineTransactions(lines);
        print('🔍 HSBC multi-line extraction returned ${hsbcTransactions.length} transactions');
        if (hsbcTransactions.isNotEmpty) {
          transactions.addAll(hsbcTransactions);
          print('✅ Added ${hsbcTransactions.length} HSBC transactions to main list. Total now: ${transactions.length}');
        }
      }
      
      // For PNB, try multi-line extraction from ALL lines (concatenated format like ICICI)
      if (bankName.toLowerCase() == 'pnb') {
        final pnbTransactions = TransactionParsingService.extractPNBMultiLineTransactions(lines);
        print('🔍 PNB multi-line extraction returned ${pnbTransactions.length} transactions');
        if (pnbTransactions.isNotEmpty) {
          transactions.addAll(pnbTransactions);
          print('✅ Added ${pnbTransactions.length} PNB transactions to main list. Total now: ${transactions.length}');
        }
      }
      
      // For Zenith, try multi-line extraction from ALL lines
      if (bankName.toLowerCase() == 'zenith') {
        final zenithTransactions = TransactionParsingService.extractZenithMultiLineTransactions(lines);
        print('🔍 Zenith multi-line extraction returned ${zenithTransactions.length} transactions');
        if (zenithTransactions.isNotEmpty) {
          transactions.addAll(zenithTransactions);
          print('✅ Added ${zenithTransactions.length} Zenith transactions to main list. Total now: ${transactions.length}');
        }
      }
      
      // Then try pattern matching
      for (final line in transactionLines) {
        final lineTransactions = _extractTransactionsFromLine(line, patterns, bankName);
        if (lineTransactions.isNotEmpty) {
          transactions.addAll(lineTransactions);        }
      }
      
      // If no transactions found with patterns, try fallback analysis
      if (transactions.isEmpty) {
        transactions.addAll(_fallbackTransactionExtraction(transactionLines, bankName));
      }
    } else {
      transactions.addAll(_analyzeFullText(lines, bankName));
    }
      // Post-process and validate transactions
    final validTransactions = _validateAndCleanTransactions(transactions);
    
    print('🎯 FINAL RESULT: ${validTransactions.length} valid transactions extracted');
    
    return validTransactions;
  }
  
  /// Find the start of transaction section
  /// Find the start of transaction section with improved detection for all banks
  static int _findTransactionSectionStart(List<String> lines) {
    int transactionsForIndex = -1;
    int transactionDetailsIndex = -1;
    int datePatternIndex = -1;
    int domesticTransactionsIndex = -1;
    int statementDateIndex = -1;
    
    // First pass: Look for all possible markers
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].toLowerCase();
      
      // Look for "TRANSACTIONS FOR" specifically (highest priority)
      if (line.contains('transactions for') && transactionsForIndex == -1) {
        transactionsForIndex = i;
        print('🔍 "TRANSACTIONS FOR" found at line $i: "${lines[i]}"');
      }
      
      // Look for "Domestic Transactions" (specific to HDFC)
      if (line.contains('domestic transactions') && domesticTransactionsIndex == -1) {
        domesticTransactionsIndex = i;
        print('🔍 "Domestic Transactions" found at line $i: "${lines[i]}"');
      }
      
      // Look for "Transaction Details" (medium priority)
      if (line.contains('transaction details') && transactionDetailsIndex == -1) {
        transactionDetailsIndex = i;
        print('🔍 "Transaction Details" found at line $i: "${lines[i]}"');
      }
      
      // Look for "Statement Date" (for Zenith and others)
      if (line.contains('statement date') && statementDateIndex == -1) {
        statementDateIndex = i;
        print('🔍 "Statement Date" found at line $i: "${lines[i]}"');
      }
      
      // Look for date patterns (lowest priority)
      if (datePatternIndex == -1 && (RegExp(r'\d{2}\/\d{2}\/\d{4}').hasMatch(line) || 
          RegExp(r'\d{1,2}\s+\w{3}\s+\d{2}').hasMatch(line) ||
          RegExp(r'\d{2}\s+\w{3}\s+\d{4}').hasMatch(line))) {
        datePatternIndex = i;
        print('🔍 Date pattern found at line $i: "${lines[i]}"');
      }
    }
    
    // Return the highest priority match
    if (transactionsForIndex != -1) {
      print('✅ Using "TRANSACTIONS FOR" section at line $transactionsForIndex');
      return transactionsForIndex;
    }
    
    if (domesticTransactionsIndex != -1) {
      print('✅ Using "Domestic Transactions" section at line $domesticTransactionsIndex');
      return domesticTransactionsIndex;
    }
    
    if (transactionDetailsIndex != -1) {
      print('✅ Using "Transaction Details" section at line $transactionDetailsIndex');
      return transactionDetailsIndex;
    }
    
    if (statementDateIndex != -1) {
      print('✅ Using "Statement Date" section at line $statementDateIndex');
      return statementDateIndex;
    }
    
    if (datePatternIndex != -1) {
      print('✅ Using date pattern section at line $datePatternIndex');
      return max(0, datePatternIndex - 2); // Start a bit before the first date
    }
    
    // Finally, look for general keywords (as fallback)
    final keywords = [
      'transaction', 'date', 'description', 'amount', 'details',
      'txn', 'merchant', 'pos', 'card', 'payment', 'purchase',
      'statement for', 'card number', 'credit card'
    ];
    
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].toLowerCase();
      
      // Look for table headers or transaction keywords
      if (keywords.any((keyword) => line.contains(keyword)) &&
          (line.contains('date') || line.contains('amount') || line.contains('statement') || line.contains('card number')) &&
          !line.contains('minimum amount due') && // Exclude account summary
          !line.contains('total amount due')) {
        print('🔍 Transaction section start found at line $i: "${lines[i]}"');
        return i;
      }
    }
    
    print('❌ No transaction section start found');
    return -1;
  }
  
  /// Find the end of transaction section
  static int _findTransactionSectionEnd(List<String> lines, int start) {
    if (start == -1) return -1;
    
    final endKeywords = [
      'total', 'summary', 'balance', 'payment due', 'minimum payment',
      'statement period', 'previous balance', 'current balance',
      'schedule of charges', 'important terms', 'charges & cardholder'
    ];
    
    for (int i = start + 1; i < lines.length; i++) {
      final line = lines[i].toLowerCase();
      
      // For SBI specifically, stop at "Schedule of Charges"
      if (line.contains('schedule of charges')) {
        print('🛑 SBI: Stopping at "Schedule of Charges" at line ${i + 1}');
        return i;
      }
      
      if (endKeywords.any((keyword) => line.contains(keyword))) {
        return i;
      }
      
      // If we see many consecutive lines without dates, might be end
      bool hasDatePattern = false;
      for (int j = i; j < min(i + 5, lines.length); j++) {
        if (RegExp(r'\d{2}\/\d{2}\/\d{4}').hasMatch(lines[j]) || 
            RegExp(r'\d{1,2}\s+\w{3}\s+\d{2}').hasMatch(lines[j])) {
          hasDatePattern = true;
          break;
        }
      }
      
      if (!hasDatePattern && i > start + 10) {
        return i;
      }
    }
    
    return -1;
  }
  
  /// Extract transactions from a single line using patterns
  static List<Map<String, dynamic>> _extractTransactionsFromLine(
    String line,
    List<RegExp> patterns,
    String bankName,
  ) {
    final transactions = <Map<String, dynamic>>[];
    
    for (final pattern in patterns) {
      final match = pattern.firstMatch(line);
      if (match != null) {
        try {
          final transaction = _parseTransactionMatch(match, line, bankName);
          if (transaction != null) {
            transactions.add(transaction);
            break; // Use first matching pattern
          }
        } catch (e) {
          print('Error parsing transaction line: $e');
          continue;
        }
      }
    }
    
    return transactions;
  }
  
  /// Parse a regex match into a transaction map
  static Map<String, dynamic>? _parseTransactionMatch(
    RegExpMatch match,
    String originalLine,
    String bankName,
  ) {
    try {
      String? date;
      String? description;
      String? amountStr;
      String? type;
      
      // Handle different pattern formats
      if (match.groupCount >= 4) {
        // Format with two dates (transaction date and posting date)
        if (match.group(2) != null && RegExp(r'\d{2}\/\d{2}\/\d{4}').hasMatch(match.group(2)!)) {
          date = match.group(1); // Transaction date
          description = match.group(3);
          amountStr = match.group(4);
          type = match.groupCount >= 5 ? match.group(5) : null;
        } else {
          // Format with single date
          date = match.group(1);
          description = match.group(2);
          amountStr = match.group(3);
          type = match.groupCount >= 4 ? match.group(4) : null;
        }
      } else if (match.groupCount >= 3) {
        // Basic format
        date = match.group(1);
        description = match.group(2);
        amountStr = match.group(3);
      }
      
      if (date == null || description == null || amountStr == null) {
        return null;
      }
      
      // Clean and parse amount
      print('🔍 _parseTransactionMatch: amountStr = "$amountStr"');
      final cleanAmount = amountStr.replaceAll(',', '');
      print('🔍 _parseTransactionMatch: cleanAmount = "$cleanAmount"');
      final amount = double.tryParse(cleanAmount);
      
      if (amount == null || amount <= 0) {
        return null;
      }
      
      // Determine transaction type
      final isCredit = type?.toLowerCase() == 'cr' || 
                      description.toLowerCase().contains('credit') ||
                      description.toLowerCase().contains('refund');
      
      // Clean description
      final cleanDescription = description.trim()
          .replaceAll(RegExp(r'\s+'), ' ')
          .replaceAll(RegExp(r'[^\w\s\.\-&*@#]'), ' ')
          .trim();
      
      return {
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'date': _convertDateToStandardFormat(date),
        'description': cleanDescription,
        'amount': amount,
        'type': isCredit ? 'credit' : 'debit',
        'merchantName': _extractMerchantName(cleanDescription),
        'category': _categorizeTransaction(cleanDescription),
        'originalLine': originalLine,
        'bankName': bankName,
      };
    } catch (e) {
      print('Error parsing transaction match: $e');
      return null;
    }
  }
  
  /// Convert various date formats to standard dd/MM/yyyy format
  static String _convertDateToStandardFormat(String date) {
    try {
      // Handle SBI format: "13 May 25" -> "13/05/2025"
      final sbiPattern = RegExp(r'(\d{1,2})\s+(\w{3})\s+(\d{2})');
      final sbiMatch = sbiPattern.firstMatch(date);
      
      if (sbiMatch != null) {
        final day = sbiMatch.group(1)!.padLeft(2, '0');
        final monthName = sbiMatch.group(2)!;
        final year = '20${sbiMatch.group(3)!}'; // Convert YY to YYYY
        
        // Convert month name to number
        final monthMap = {
          'Jan': '01', 'Feb': '02', 'Mar': '03', 'Apr': '04',
          'May': '05', 'Jun': '06', 'Jul': '07', 'Aug': '08',
          'Sep': '09', 'Oct': '10', 'Nov': '11', 'Dec': '12'
        };
        
        final month = monthMap[monthName] ?? '01';
        return '$day/$month/$year';
      }
      
      // Handle standard format: dd/MM/yyyy - return as is
      if (RegExp(r'\d{2}\/\d{2}\/\d{4}').hasMatch(date)) {
        return date;
      }
      
      // Handle dd-MM-yyyy format
      if (RegExp(r'\d{2}-\d{2}-\d{4}').hasMatch(date)) {
        return date.replaceAll('-', '/');
      }
      
      return date; // Fallback - return original
    } catch (e) {
      print('Error converting date format: $e');
      return date;
    }
  }
  
  /// Fallback extraction when patterns don't work
  static List<Map<String, dynamic>> _fallbackTransactionExtraction(
    List<String> lines,
    String bankName,  ) {
    final transactions = <Map<String, dynamic>>[];
    
    // For SBI, find where to stop reading
    int endIndex = lines.length;
    if (bankName.toLowerCase() == 'sbi') {
      for (int i = 0; i < lines.length; i++) {
        if (lines[i].toLowerCase().contains('schedule of charges')) {
          endIndex = i;
          print('🛑 SBI Fallback: Stopping at "Schedule of Charges" at line ${i + 1}');
          break;
        }
      }
    }
    
    for (int i = 0; i < endIndex; i++) {
      final line = lines[i];
      
      // Look for lines with date and amount patterns
      final standardDateMatch = RegExp(r'(\d{2}\/\d{2}\/\d{4})').firstMatch(line);
      final sbiDateMatch = RegExp(r'(\d{1,2}\s+\w{3}\s+\d{2})').firstMatch(line);
      final amountMatch = RegExp(r'([\d,]+\.\d{2})').allMatches(line).toList();
      
      final dateMatch = standardDateMatch ?? sbiDateMatch;
      
      if (dateMatch != null && amountMatch.isNotEmpty) {
        try {
          final date = dateMatch.group(1)!;
          final amountStr = amountMatch.last.group(1)!; // Use last amount found
          final amount = double.tryParse(amountStr.replaceAll(',', ''));
          
          if (amount != null && amount > 0) {
            // Extract description (text between date and amount)
            final dateEnd = dateMatch.end;
            final amountStart = amountMatch.last.start;
            
            if (amountStart > dateEnd) {
              final description = line.substring(dateEnd, amountStart).trim()
                  .replaceAll(RegExp(r'\s+'), ' ');
              
              if (description.isNotEmpty && description.length > 3) {
                transactions.add({
                  'id': DateTime.now().millisecondsSinceEpoch.toString(),
                  'date': _convertDateToStandardFormat(date),
                  'description': description,
                  'amount': amount,
                  'type': 'debit',
                  'merchantName': _extractMerchantName(description),
                  'category': _categorizeTransaction(description),
                  'originalLine': line,
                  'bankName': bankName,
                });
              }
            }
          }
        } catch (e) {
          continue;
        }      }
    }
    
    return transactions;
  }
  
  /// Analyze full text when no clear section is found
  static List<Map<String, dynamic>> _analyzeFullText(List<String> lines, String bankName) {
    print('🔍 FULL TEXT: Analyzing entire document for transactions...');
    
    // Use fallback extraction on all lines
    return _fallbackTransactionExtraction(lines, bankName);
  }
  
  /// Extract merchant name from description
  static String? _extractMerchantName(String description) {
    // Remove common prefixes and suffixes
    String clean = description
        .replaceAll(RegExp(r'^(POS|UPI|CARD\s+TXN|TXN)\s*', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*(MUMBAI|DELHI|BANGALORE|CHENNAI|KOLKATA|PUNE|HYDERABAD).*$', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*\d+.*$'), '') // Remove trailing numbers
        .trim();
    
    if (clean.length < 3) return null;
    
    return clean.split(' ').take(3).join(' '); // Take first 3 words
  }
  
  /// Categorize transaction based on description
  static String _categorizeTransaction(String description) {
    final desc = description.toLowerCase();
    
    if (desc.contains('amazon') || desc.contains('flipkart') || desc.contains('shopping')) {
      return 'Shopping';
    } else if (desc.contains('swiggy') || desc.contains('zomato') || desc.contains('food') || desc.contains('restaurant')) {
      return 'Food & Dining';
    } else if (desc.contains('uber') || desc.contains('ola') || desc.contains('metro') || desc.contains('petrol') || desc.contains('fuel')) {
      return 'Transportation';
    } else if (desc.contains('paytm') || desc.contains('phonepe') || desc.contains('gpay') || desc.contains('upi')) {
      return 'Digital Payments';
    } else if (desc.contains('atm') || desc.contains('cash')) {
      return 'Cash Withdrawal';
    } else if (desc.contains('utility') || desc.contains('electricity') || desc.contains('water') || desc.contains('gas')) {
      return 'Utilities';
    } else if (desc.contains('medical') || desc.contains('pharmacy') || desc.contains('hospital')) {
      return 'Healthcare';
    } else {
      return 'Other';
    }
  }
  
  /// Validate and clean transactions
  static List<Map<String, dynamic>> _validateAndCleanTransactions(
    List<Map<String, dynamic>> transactions,
  ) {
    print('🔍 Validating ${transactions.length} transactions...');
    final validTransactions = <Map<String, dynamic>>[];
    final seenTransactions = <String>{};
    
    for (final transaction in transactions) {
      // Create unique key for deduplication
      final key = '${transaction['date']}_${transaction['description']}_${transaction['amount']}';
      
      print('  Checking transaction: ${transaction['date']} | ${transaction['description']} | ${transaction['amount']}');
      
      if (!seenTransactions.contains(key) &&
          transaction['amount'] is double &&
          transaction['amount'] > 0 &&
          transaction['description'].toString().length > 3) {
        
        seenTransactions.add(key);
        validTransactions.add(transaction);
        print('    ✅ Valid transaction added');
      } else {
        print('    ❌ Transaction rejected: duplicate=${seenTransactions.contains(key)}, amount=${transaction['amount']}, descLength=${transaction['description'].toString().length}');
      }
    }
    
    print('🔍 Validation complete: ${validTransactions.length} valid transactions');
    
    // Sort by date (newest first)
    validTransactions.sort((a, b) {
      try {
        final dateA = DateTime.parse(a['date'].toString().split('/').reversed.join('-'));
        final dateB = DateTime.parse(b['date'].toString().split('/').reversed.join('-'));
        return dateB.compareTo(dateA);
      } catch (e) {
        return 0;
      }
    });
    
    return validTransactions;
  }
  
  /// Special SBI extraction for multi-line format
  static List<Map<String, dynamic>> extractSBIMultiLineTransactions(List<String> lines) {
    final transactions = <Map<String, dynamic>>[];
    
    // Find where to stop reading (at "Schedule of Charges" for SBI)
    int endIndex = lines.length;
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].toLowerCase().contains('schedule of charges')) {
        endIndex = i;
        print('🛑 SBI Multi-line: Stopping at "Schedule of Charges" at line ${i + 1}');
        break;
      }
    }
    
    for (int i = 0; i < endIndex - 3; i++) {
      final line1 = lines[i].trim();
      final line2 = lines[i + 1].trim();
      final line3 = lines[i + 2].trim();
      final line4 = lines[i + 3].trim();
      
      // Check if first line has SBI date format
      final dateMatch = RegExp(r'^(\d{1,2}\s+\w{3}\s+\d{2})$').firstMatch(line1);
      if (dateMatch == null) continue;
      
      // Check if third line has amount format
      final amountMatch = RegExp(r'^([\d,]+\.\d{2})$').firstMatch(line3);
      if (amountMatch == null) continue;
      
      // Check if fourth line has transaction type
      if (!RegExp(r'^[DC]$').hasMatch(line4)) continue;
      
      // Second line should be description
      if (line2.isEmpty || line2.length < 3) continue;
      
      try {
        final date = _convertDateToStandardFormat(dateMatch.group(1)!);
        final amount = double.tryParse(amountMatch.group(1)!.replaceAll(',', ''));
        final description = line2.trim()
            .replaceAll(RegExp(r'\s+'), ' ');
        final type = line4 == 'C' ? 'credit' : 'debit';
        
        if (amount != null && amount > 0) {
          transactions.add({
            'id': DateTime.now().millisecondsSinceEpoch.toString(),
            'date': date,
            'description': description,
            'amount': amount,
            'type': type,
            'merchantName': _extractMerchantName(description),
            'category': _categorizeTransaction(description),
            'originalLine': '$line1 $line2 $line3 $line4',
            'bankName': 'sbi',
          });
          
          print('✅ SBI Multi-line transaction extracted: $date - $description - ₹$amount');
        }
      } catch (e) {
        print('❌ Error parsing SBI multi-line transaction: $e');
        continue;
      }
    }
    
    return transactions;
  }
  
  /// HDFC multi-line extraction for tabular format: Date (with timestamp) -> Description -> Reward Points + Amount
  static List<Map<String, dynamic>> extractHDFCMultiLineTransactions(List<String> lines) {
    final transactions = <Map<String, dynamic>>[];
    
    // Find where to stop reading (at "Important Information" for HDFC)
    // But don't stop for Swiggy cards as they may have transactions after this section
    int endIndex = lines.length;
    bool hasSwiggyTransactions = false;
    
    // Check if this is a Swiggy statement by looking for Swiggy-related content
    for (final line in lines) {
      if (line.toLowerCase().contains('swiggy')) {
        hasSwiggyTransactions = true;
        break;
      }
    }
    
    // Only stop at "Important Information" if it's not a Swiggy statement
    if (!hasSwiggyTransactions) {
      for (int i = 0; i < lines.length; i++) {
        if (lines[i].toLowerCase().contains('important information')) {
          endIndex = i;
          print('🛑 HDFC Multi-line: Stopping at "Important Information" at line ${i + 1}');
          break;
        }
      }
    } else {
      print('🔍 HDFC Multi-line: Swiggy statement detected, reading full document');
    }
    
    // Look for "Domestic Transactions" section
    int startIndex = -1;
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].toLowerCase().contains('domestic transactions')) {
        startIndex = i;
        print('🔍 HDFC: Found "Domestic Transactions" section at line ${i + 1}');
        break;
      }
    }
    
    if (startIndex == -1) {
      print('⚠️ HDFC: No "Domestic Transactions" section found');
      return transactions;
    }
    
    // Parse transactions in the domestic transactions section
    for (int i = startIndex; i < endIndex - 1; i++) {
      final line1 = lines[i].trim();
      final line2 = lines[i + 1].trim();
      final line3 = i + 2 < lines.length ? lines[i + 2].trim() : '';
      
      // Check if first line has HDFC date format (with or without timestamp)
      final dateMatch = RegExp(r'^(\d{2}\/\d{2}\/\d{4})(?:\s+(\d{2}:\d{2}:\d{2}))?$').firstMatch(line1);
      if (dateMatch == null) continue;
      
      // Second line should be description (not empty and reasonable length)
      if (line2.isEmpty || line2.length < 5) continue;
      
      // Third line should contain the concatenated reward points + amount
      // Format: [rewardpoints][amount] or just [amount]Cr
      final amountMatch = RegExp(r'^([\d,]+\.\d{2})(Cr|Dr)?$').firstMatch(line3);
      if (amountMatch == null) continue;
      
      try {
        final dateStr = dateMatch.group(1)!;
        final rawAmountStr = amountMatch.group(1)!;
        final creditDebitIndicator = amountMatch.group(2);
        
        // Use robust amount parsing to handle reward points concatenation
        final amount = parseRobustAmount(rawAmountStr);
        final description = line2.trim().replaceAll(RegExp(r'\s+'), ' ');
        final type = creditDebitIndicator?.toLowerCase() == 'cr' ? 'credit' : 'debit';
        
        print('🔍 HDFC Multi-line parsing: Date="$dateStr", Desc="$description", RawAmount="$rawAmountStr"');
        print('🔍 HDFC Robust amount parsing: $rawAmountStr -> $amount');
        
        if (amount != null && amount > 0) {
          transactions.add({
            'id': DateTime.now().millisecondsSinceEpoch.toString(),
            'date': dateStr,
            'description': description,
            'amount': amount,
            'type': type,
            'merchantName': _extractMerchantName(description),
            'category': _categorizeTransaction(description),
            'originalLine': '$line1 $line2 $line3 (parsed: $rawAmountStr -> $amount)',
            'bankName': 'hdfc',
          });
          
          print('✅ HDFC Multi-line transaction extracted: $dateStr - $description - ₹$amount (from $rawAmountStr)');
        }
      } catch (e) {
        print('❌ Error parsing HDFC multi-line transaction: $e');
        continue;
      }
    }
    
    return transactions;
  }

  /// IndusInd multi-line extraction for format: Date -> Description -> Category -> (gaps) -> Amount
  static List<Map<String, dynamic>> extractIndusIndMultiLineTransactions(List<String> lines) {
    final transactions = <Map<String, dynamic>>[];
    
    for (int i = 0; i < lines.length - 6; i++) {
      final line1 = lines[i].trim();        // Date
      final line2 = lines[i + 1].trim();    // Description
      final line3 = lines[i + 2].trim();    // Category
      
      // Check if first line has date format
      final dateMatch = RegExp(r'^(\d{2}\/\d{2}\/\d{4})$').firstMatch(line1);
      if (dateMatch == null) continue;
      
      // Check if description line is reasonable
      if (line2.isEmpty || line2.length < 5) continue;
      
      print('🔍 IndusInd checking: Date="$line1", Desc="$line2", Category="$line3"');
      
      // Look for amount in the next few lines (there can be gaps)
      String? amountLine;
      String? amountValue;
      String? transactionType;
      
      // Look at immediate next lines - IndusInd has amount close to description
      for (int j = i + 2; j < i + 6 && j < lines.length; j++) {
        final candidateLine = lines[j].trim();
        final amountMatch = RegExp(r'^([\d,]+\.\d{2})\s*(DR|CR)?$').firstMatch(candidateLine);
        if (amountMatch != null) {
          amountLine = candidateLine;
          amountValue = amountMatch.group(1);
          transactionType = amountMatch.group(2)?.toLowerCase() == 'cr' ? 'credit' : 'debit';
          print('🔍 IndusInd found amount at line ${j}: "$candidateLine"');
          break;
        }
      }
      
      if (amountValue == null) continue;
      
      try {
        final dateStr = dateMatch.group(1)!;
        final amount = double.tryParse(amountValue.replaceAll(',', ''));
        final description = line2.trim().replaceAll(RegExp(r'\s+'), ' ');
        
        if (amount != null && amount > 0) {
          transactions.add({
            'id': DateTime.now().millisecondsSinceEpoch.toString(),
            'date': dateStr,
            'description': description,
            'amount': amount,
            'type': transactionType ?? 'debit',
            'merchantName': _extractMerchantName(description),
            'category': _categorizeTransaction(description),
            'originalLine': '$line1 $line2 $line3 ... $amountLine',
            'bankName': 'indusind',
          });
          
          print('✅ IndusInd Multi-line transaction extracted: $dateStr - $description - ₹$amount');
        }
      } catch (e) {
        print('❌ Error parsing IndusInd multi-line transaction: $e');
        continue;
      }
    }
    
    return transactions;
  }

  /// Robust amount parsing that handles reward points concatenation and uses comma placement as a signal
  static double? parseRobustAmount(String amountStr) {
    print('🔍 Parsing amount: "$amountStr"');
    try {
      // Remove currency symbols and extra spaces, but keep dots and commas initially
      String cleanAmount = amountStr
          .replaceAll(RegExp(r'[₹\$€£\s]'), '') // Remove currency and spaces
          .replaceAll(RegExp(r'[^\d\.,]'), ''); // Keep only digits, dots, and commas

      print('🔍 Clean amount after initial cleaning: "$cleanAmount"');

      // Check if there are commas - use them as signals for amount boundaries
      bool hasCommas = cleanAmount.contains(',');
      
      // If there are commas, analyze their placement to help with splitting
      List<int> commaPositions = [];
      if (hasCommas) {
        for (int i = 0; i < cleanAmount.length; i++) {
          if (cleanAmount[i] == ',') {
            commaPositions.add(i);
          }
        }
        print('🔍 Comma positions found at: $commaPositions');
      }

      // Handle OCR error where Feature Reward Points get concatenated with amounts
      // Pattern: reward points (usually 1-3 digits) + actual amount
      if (cleanAmount.contains('.')) {
        final parts = cleanAmount.split('.');
        if (parts.length == 2) {
          final beforeDecimal = parts[0];
          final afterDecimal = parts[1];
          
          // Check if this looks like reward points concatenated with amount
          if (beforeDecimal.length >= 4) { // At least 4 digits before decimal to consider splitting
            // Don't split if the original amount is already reasonable (under 5000)
            final originalAmountTest = beforeDecimal.replaceAll(',', '');
            final originalAmount = double.tryParse('$originalAmountTest.$afterDecimal');
            if (originalAmount != null && originalAmount <= 5000) {
              // Skip splitting for reasonable amounts, just remove commas
              cleanAmount = cleanAmount.replaceAll(',', '');
            } else {
              // Find all valid splits and choose the most reasonable one
              String? bestSplit;
              double? bestScore;
              
              for (int rewardPointsLength = 1; rewardPointsLength <= 3; rewardPointsLength++) {
                if (rewardPointsLength < beforeDecimal.length) {
                  final possibleRewardPoints = beforeDecimal.substring(0, rewardPointsLength);
                  final possibleAmount = beforeDecimal.substring(rewardPointsLength);
                  
                  final rewardPoints = int.tryParse(possibleRewardPoints.replaceAll(',', ''));
                  if (rewardPoints != null && rewardPoints >= 1 && rewardPoints <= 999) { // Extended range for reward points
                    if (possibleAmount.isNotEmpty && !possibleAmount.startsWith('0')) {
                      // Remove commas from the amount part for testing
                      final cleanPossibleAmount = possibleAmount.replaceAll(',', '');
                      final testAmount = double.tryParse('$cleanPossibleAmount.$afterDecimal');
                      
                      if (testAmount != null && testAmount >= 50) { // Allow all reasonable amounts
                        // Score this split - prefer amounts in typical ranges but allow larger amounts
                        double score = 0;
                        
                        // Bonus points for comma placement that makes sense
                        if (hasCommas) {
                          // Check if comma placement in the amount part follows Indian numbering (lakhs/crores)
                          // or international numbering (thousands)
                          final amountWithCommas = possibleAmount;
                          if (_isValidCommaPlacement(amountWithCommas)) {
                            score += 15; // Big bonus for valid comma placement
                            print('🔍 Valid comma placement detected in: "$amountWithCommas"');
                          }
                          
                          // Check if splitting at this point preserves meaningful comma structure
                          final originalBeforeDecimal = beforeDecimal;
                          
                          // If the amount part starts right after a comma boundary, bonus points
                          if (rewardPointsLength > 0 && rewardPointsLength < originalBeforeDecimal.length) {
                            final charAtSplit = originalBeforeDecimal[rewardPointsLength - 1];
                            if (charAtSplit == ',' || (rewardPointsLength < originalBeforeDecimal.length && originalBeforeDecimal[rewardPointsLength] != ',')) {
                              score += 8; // Bonus for splitting at natural comma boundaries
                            }
                          }
                        }
                        
                        if (testAmount >= 100 && testAmount <= 5000) score += 10; // Very typical range
                        if (testAmount >= 5001 && testAmount <= 20000) score += 8; // Higher amounts still reasonable (restaurants, shopping)
                        if (testAmount >= 20001 && testAmount <= 100000) score += 6; // Large amounts (flights, hotels, electronics)
                        if (testAmount >= 200 && testAmount <= 3000) score += 5; // Common range
                        if (rewardPointsLength == 2) score += 5; // Prefer 2-digit reward points
                        if (rewardPointsLength == 3 && testAmount <= 50000) score += 3; // 3-digit reward points for larger amounts
                        
                        // Only penalize truly unreasonable amounts (half million+)
                        if (testAmount > 500000) score -= 20; // Half a million+ is likely an error
                        if (testAmount > 1000000) score -= 50; // Million+ is definitely an error
                        
                        if (bestScore == null || score > bestScore) {
                          bestScore = score;
                          bestSplit = '$cleanPossibleAmount.$afterDecimal';
                        }
                        
                        print('🔍 Split candidate: rewards="$possibleRewardPoints", amount="$cleanPossibleAmount.$afterDecimal", score=$score');
                      }
                    }
                  }
                }
              }
              
              if (bestSplit != null) {
                cleanAmount = bestSplit;
                print('🔍 Found best split: "$bestSplit" from "$amountStr" (score: $bestScore)');
              } else {
                // No good split found, just remove commas and use original
                cleanAmount = cleanAmount.replaceAll(',', '');
              }
            }
          } else {
            // Less than 4 digits before decimal, just remove commas
            cleanAmount = cleanAmount.replaceAll(',', '');
          }
        }
      } else if (cleanAmount.length > 4) {
        // No decimal point but large number - might be reward points + amount without decimal
        // Try to split and add decimal point 2 places from the right of the amount part
        String? bestSplit;
        double? bestScore;
        
        for (int rewardPointsLength = 1; rewardPointsLength <= 3; rewardPointsLength++) {
          if (rewardPointsLength < cleanAmount.length - 2) { // Need at least 3 digits for amount part
            final possibleRewardPoints = cleanAmount.substring(0, rewardPointsLength);
            final remainingDigits = cleanAmount.substring(rewardPointsLength);
            
            final rewardPoints = int.tryParse(possibleRewardPoints.replaceAll(',', ''));
            if (rewardPoints != null && rewardPoints >= 1 && rewardPoints <= 999) { // Extended range for reward points
              // Add decimal point 2 places from the right
              if (remainingDigits.length >= 3) {
                final cleanRemainingDigits = remainingDigits.replaceAll(',', '');
                final intPart = cleanRemainingDigits.substring(0, cleanRemainingDigits.length - 2);
                final decPart = cleanRemainingDigits.substring(cleanRemainingDigits.length - 2);
                final testAmount = double.tryParse('$intPart.$decPart');
                
                if (testAmount != null && testAmount >= 50) { // Allow all reasonable amounts
                  double score = 0;
                  
                  // Check comma placement in this split
                  if (hasCommas && _isValidCommaPlacement(remainingDigits)) {
                    score += 15; // Bonus for valid comma placement
                    print('🔍 Valid comma placement in no-decimal split: "$remainingDigits"');
                  }
                  
                  if (testAmount >= 100 && testAmount <= 5000) score += 10;
                  if (rewardPointsLength == 2) score += 5;
                  
                  if (bestScore == null || score > bestScore) {
                    bestScore = score;
                    bestSplit = '$intPart.$decPart';
                  }
                  
                  print('🔍 No-decimal split candidate: rewards="$possibleRewardPoints", amount="$intPart.$decPart", score=$score');
                }
              }
            }
          }
        }
        
        if (bestSplit != null) {
          cleanAmount = bestSplit;
          print('🔍 Found best no-decimal split: "$bestSplit" (score: $bestScore)');
        } else {
          // No good split found, just remove commas
          cleanAmount = cleanAmount.replaceAll(',', '');
        }
      } else {
        // Short amount, just remove commas
        cleanAmount = cleanAmount.replaceAll(',', '');
      }

      // Final parsing attempt
      final result = double.tryParse(cleanAmount);
      print('🔍 Final parsed amount: $result from "$cleanAmount"');
      return result;
    } catch (e) {
      print('❌ Error parsing amount "$amountStr": $e');
      return null;
    }
  }
  
  /// Check if comma placement follows valid Indian or international numbering patterns
  static bool _isValidCommaPlacement(String numberStr) {
    if (!numberStr.contains(',')) return true; // No commas is always valid
    
    // Remove leading/trailing non-digit characters
    final cleanStr = numberStr.replaceAll(RegExp(r'^[^\d]*|[^\d]*$'), '');
    if (cleanStr.isEmpty) return false;
    
    // Split by commas and check patterns
    final parts = cleanStr.split(',');
    if (parts.length < 2) return true; // No commas or single part
    
    // Check Indian numbering system (lakhs/crores): x,xx,xxx or xx,xx,xxx
    // The first part can be 1-3 digits, then all middle parts should be 2 digits, last part should be 3 digits
    if (parts.length >= 2) {
      final firstPart = parts[0];
      final lastPart = parts[parts.length - 1];
      
      // Check if this could be Indian format
      bool isIndianFormat = true;
      if (firstPart.length > 3) isIndianFormat = false; // First part too long
      if (lastPart.length != 3) isIndianFormat = false; // Last part should be 3 digits
      
      // Check middle parts (should be 2 digits each in Indian format)
      for (int i = 1; i < parts.length - 1; i++) {
        if (parts[i].length != 2) {
          isIndianFormat = false;
          break;
        }
      }
      
      if (isIndianFormat) {
        print('🔍 Detected Indian comma format: $numberStr');
        return true;
      }
    }
    
    // Check international numbering system (thousands): xxx,xxx,xxx
    // All parts except the first should be exactly 3 digits
    bool isInternationalFormat = true;
    final firstPart = parts[0];
    if (firstPart.length > 3 || firstPart.isEmpty) isInternationalFormat = false;
    
    for (int i = 1; i < parts.length; i++) {
      if (parts[i].length != 3) {
        isInternationalFormat = false;
        break;
      }
    }
    
    if (isInternationalFormat) {
      print('🔍 Detected international comma format: $numberStr');
      return true;
    }
    
    print('🔍 Invalid comma format detected: $numberStr');
    return false;
  }

  /// ICICI extraction to handle concatenated transaction lines
  static List<Map<String, dynamic>> extractICICITransactions(List<String> lines) {
    final transactions = <Map<String, dynamic>>[];
    
    for (final line in lines) {
      // ICICI format: DateSerNo.Transaction DetailsRewardPointsIntl.#amountAmount (inÁ)...
      // Example: 19/05/202511288228127Annual Fee - 2nd Year Reversal03,500.00 CR19/05/202511288228128...
      
      // Look for the pattern of dates followed by transaction details
      final datePattern = RegExp(r'(\d{2}\/\d{2}\/\d{4})\d{11}([A-Za-z0-9\s\.\-\(\)\/\#]+?)(\d+)([\d,]+\.\d{2})\s*(CR|DR)?');
      final matches = datePattern.allMatches(line);
      
      if (matches.isNotEmpty) {
        print('🔍 ICICI: Processing concatenated line with ${matches.length} potential transactions');
        
        // Split the line by date patterns to separate transactions
        final dateRegex = RegExp(r'(\d{2}\/\d{2}\/\d{4})');
        final dateMatches = dateRegex.allMatches(line).toList();
        
        for (int i = 0; i < dateMatches.length; i++) {
          final currentMatch = dateMatches[i];
          final nextMatch = i + 1 < dateMatches.length ? dateMatches[i + 1] : null;
          
          final startPos = currentMatch.start;
          final endPos = nextMatch?.start ?? line.length;
          final segment = line.substring(startPos, endPos);
          
          // Extract date
          final dateStr = currentMatch.group(1)!;
          
          // Look for amount and transaction type in this segment
          final amountMatch = RegExp(r'([\d,]+\.\d{2})\s*(CR|DR)?').firstMatch(segment);
          if (amountMatch != null) {
            final amountStr = amountMatch.group(1)!;
            final transactionType = amountMatch.group(2)?.toLowerCase() == 'cr' ? 'credit' : 'debit';
            final amount = double.tryParse(amountStr.replaceAll(',', ''));
            
            if (amount != null && amount > 0) {
              // Extract description (between date and amount)
              final descStart = dateStr.length + 11; // Skip date and serial number
              final descEnd = segment.indexOf(amountStr);
              
              if (descEnd > descStart) {
                String description = segment.substring(descStart, descEnd).trim();
                // Clean up description by removing numbers and excess spaces
                description = description.replaceAll(RegExp(r'\d{3,}'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
                
                if (description.length > 3) {
                  transactions.add({
                    'id': DateTime.now().millisecondsSinceEpoch.toString(),
                    'date': dateStr,
                    'description': description,
                    'amount': amount,
                    'type': transactionType,
                    'merchantName': _extractMerchantName(description),
                    'category': _categorizeTransaction(description),
                    'originalLine': segment,
                    'bankName': 'icici',
                  });
                  
                  print('✅ ICICI transaction extracted: $dateStr - $description - ₹$amount');
                }
              }
            }
          }
        }
      }
    }
    
    return transactions;
  }

  /// Axis multi-line extraction for format observed in test output
  static List<Map<String, dynamic>> extractAxisMultiLineTransactions(List<String> lines) {
    final transactions = <Map<String, dynamic>>[];
    
    for (int i = 0; i < lines.length - 2; i++) {
      final line1 = lines[i].trim();        // Date
      final line2 = lines[i + 1].trim();    // Description
      final line3 = lines[i + 2].trim();    // Amount with Cr/Dr
      
      // Check if first line has date format
      final dateMatch = RegExp(r'^(\d{2}\/\d{2}\/\d{4})$').firstMatch(line1);
      if (dateMatch == null) continue;
      
      // Check if description line is reasonable
      if (line2.isEmpty || line2.length < 5) continue;
      
      // Check if third line has amount format
      final amountMatch = RegExp(r'^([\d,]+\.\d{2})\s*(Cr|Dr)?$').firstMatch(line3);
      if (amountMatch == null) continue;
      
      try {
        final dateStr = dateMatch.group(1)!;
        final amountStr = amountMatch.group(1)!;
        final transactionType = amountMatch.group(2)?.toLowerCase() == 'cr' ? 'credit' : 'debit';
        final amount = double.tryParse(amountStr.replaceAll(',', ''));
        final description = line2.trim().replaceAll(RegExp(r'\s+'), ' ');
        
        if (amount != null && amount > 0) {
          transactions.add({
            'id': DateTime.now().millisecondsSinceEpoch.toString(),
            'date': dateStr,
            'description': description,
            'amount': amount,
            'type': transactionType,
            'merchantName': _extractMerchantName(description),
            'category': _categorizeTransaction(description),
            'originalLine': '$line1 | $line2 | $line3',
            'bankName': 'axis',
          });
          
          print('✅ Axis Multi-line transaction extracted: $dateStr - $description - ₹$amount');
        }
      } catch (e) {
        print('❌ Error parsing Axis multi-line transaction: $e');
        continue;
      }
    }
    
    return transactions;
  }

  /// IDFC multi-line extraction for format: Date -> Description -> Convert -> Amount -> DR/CR
  static List<Map<String, dynamic>> extractIDFCMultiLineTransactions(List<String> lines) {
    final transactions = <Map<String, dynamic>>[];
    
    try {
      for (int i = 0; i < lines.length - 4; i++) {
        final line0 = lines[i].trim();
        final line1 = lines[i + 1].trim();
        
        // Look for IDFC date pattern: "19 May 25"
        final dateMatch = RegExp(r'^(\d{1,2}\s+\w{3}\s+\d{2})$').firstMatch(line0);
        if (dateMatch == null) continue;
        
        // Description should be on next line and not be "Convert"
        if (line1.isEmpty || line1.length < 3 || line1.toLowerCase().contains('convert')) continue;
        
        // Skip lines until we find amount
        int amountLineIndex = -1;
        RegExpMatch? finalAmountMatch;
        for (int j = i + 2; j < lines.length && j <= i + 5; j++) {
          final amountMatch = RegExp(r'^[\s]*([\d,]+\.\d{2})[\s]*$').firstMatch(lines[j].trim());
          if (amountMatch != null) {
            amountLineIndex = j;
            finalAmountMatch = amountMatch;
            break;
          }
        }
        
        if (amountLineIndex == -1 || amountLineIndex >= lines.length - 1 || finalAmountMatch == null) continue;
        
        // Look for DR/CR on next line after amount
        final typeMatch = RegExp(r'^(DR|CR)$').firstMatch(lines[amountLineIndex + 1].trim());
        if (typeMatch == null) continue;
        
        final dateStr = dateMatch.group(1)!;
        final description = line1.trim();
        final amountStr = finalAmountMatch.group(1)!;
        final transactionType = typeMatch.group(1)!.toLowerCase() == 'cr' ? 'credit' : 'debit';
        final amount = double.tryParse(amountStr.replaceAll(',', ''));
        
        if (amount != null && amount > 0) {
          transactions.add({
            'id': DateTime.now().millisecondsSinceEpoch.toString(),
            'date': dateStr,
            'description': description,
            'amount': amount,
            'transaction_type': transactionType,
          });
          print('✅ IDFC Multi-line transaction extracted: $dateStr - $description - ₹$amount');
        }
      }
    } catch (e) {
      print('❌ Error parsing IDFC multi-line transactions: $e');
    }
    
    return transactions;
  }

  /// HSBC multi-line extraction for format: DATE + MERCHANT + AMOUNT (like "10MAYIAP NYKAA BANGALORE4,762.00")
  static List<Map<String, dynamic>> extractHSBCMultiLineTransactions(List<String> lines) {
    final transactions = <Map<String, dynamic>>[];
    
    try {
      // Look for transaction lines that start with date pattern and end with amount
      for (int i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.isEmpty) continue;
        
        // HSBC pattern: date (like "10MAY") + merchant + location + amount at end
        final match = RegExp(r'^(\d{1,2}(?:MAY|JUN|JUL|AUG|SEP|OCT|NOV|DEC|JAN|FEB|MAR|APR))([A-Za-z0-9\s\.\-&*@#]+?)([\d,]+\.\d{2})$').firstMatch(line);
        
        if (match != null) {
          final dateStr = match.group(1)!;
          final merchantAndLocation = match.group(2)!.trim().replaceAll(RegExp(r'\s+'), ' ');
          final amountStr = match.group(3)!;
          final amount = double.tryParse(amountStr.replaceAll(',', ''));
          
          if (amount != null && amount > 0 && merchantAndLocation.isNotEmpty) {
            // Clean up the merchant description
            final description = merchantAndLocation.trim();
            
            // Skip balance-related entries and fees
            if (description.toLowerCase().contains('balance') ||
                description.toLowerCase().contains('outstanding') ||
                description.toLowerCase().contains('total') ||
                description.toLowerCase().contains('minimum payment') ||
                description.toLowerCase().contains('due')) {
              continue;
            }
            
            transactions.add({
              'id': DateTime.now().millisecondsSinceEpoch.toString(),
              'date': dateStr,
              'description': description,
              'amount': amount,
              'transaction_type': 'debit', // HSBC typically shows debits
              'merchantName': _extractMerchantName(description),
              'category': _categorizeTransaction(description),
              'originalLine': line,
              'bankName': 'hsbc',
            });
            print('✅ HSBC Multi-line transaction extracted: $dateStr - $description - ₹$amount');
          }
        }
      }
    } catch (e) {
      print('❌ Error parsing HSBC multi-line transactions: $e');
    }
    
    return transactions;
  }

  /// PNB multi-line extraction for concatenated format like ICICI
  /// Format: DATE+DATE+DESCRIPTION+AMOUNT repeated multiple times  
  /// Example: "20-MAY-202520-MAY-2025Bbps Payment1643.00Cr20-MAY-202521-MAY-2025Prabind Kumar30.00"
  static List<Map<String, dynamic>> extractPNBMultiLineTransactions(List<String> lines) {
    final transactions = <Map<String, dynamic>>[];
    
    try {
      // Look for lines with the PNB concatenated transaction format
      for (int i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.isEmpty) continue;
        
        // Look for lines containing multiple concatenated transactions
        // Pattern: multiple date-date-description-amount sequences
        final transactionMatches = RegExp(r'(\d{2}-\w{3}-\d{4})(\d{2}-\w{3}-\d{4})([A-Za-z0-9\s\.\-&*@#]+?)([\d,]+\.\d{2}(?:Cr|Dr)?)')
            .allMatches(line);
        
        if (transactionMatches.isNotEmpty) {
          print('🔍 PNB: Processing concatenated line with ${transactionMatches.length} potential transactions');
          
          for (final match in transactionMatches) {
            final transactionDate = match.group(1)!; // First date is transaction date
            // Second date is post date (group(2)) - not used in transaction record
            final description = match.group(3)!.trim().replaceAll(RegExp(r'\s+'), ' ');
            final amountStr = match.group(4)!;
            
            // Parse amount and determine transaction type
            final isCredit = amountStr.contains('Cr');
            final cleanAmountStr = amountStr.replaceAll(RegExp(r'[CrDr]'), '').replaceAll(',', '');
            final amount = double.tryParse(cleanAmountStr);
            
            if (amount != null && amount > 0 && description.isNotEmpty) {
              // Skip balance-related entries
              if (description.toLowerCase().contains('balance') ||
                  description.toLowerCase().contains('outstanding') ||
                  description.toLowerCase().contains('total') ||
                  description.toLowerCase().contains('minimum payment')) {
                continue;
              }
              
              final transactionType = isCredit ? 'credit' : 'debit';
              
              transactions.add({
                'id': DateTime.now().millisecondsSinceEpoch.toString(),
                'date': transactionDate,
                'description': description,
                'amount': amount,
                'transaction_type': transactionType,
                'merchantName': _extractMerchantName(description),
                'category': _categorizeTransaction(description),
                'originalLine': line,
                'bankName': 'pnb',
              });
              
              print('✅ PNB transaction extracted: $transactionDate - $description - ₹$amount');
            }
          }
        }
      }
    } catch (e) {
      print('❌ Error parsing PNB multi-line transactions: $e');
    }
    
    return transactions;
  }

  /// Zenith multi-line extraction for format: Amount -> Cr/Dr -> Date -> Description
  /// Example:
  /// 811.00
  /// Cr.
  /// 16 / 05 / 2025
  /// PYMNT RCV BBPS
  static List<Map<String, dynamic>> extractZenithMultiLineTransactions(List<String> lines) {
    final transactions = <Map<String, dynamic>>[];
    
    try {
      // Look for Zenith transaction pattern: Amount -> Cr/Dr -> Date -> Description
      for (int i = 0; i < lines.length - 3; i++) {
        final amountLine = lines[i].trim();
        final typeLine = lines[i + 1].trim();
        final dateLine = lines[i + 2].trim();
        final descLine = lines[i + 3].trim();
        
        // Check if this matches Zenith pattern
        final amountMatch = RegExp(r'^[\d,]+\.\d{2}$').hasMatch(amountLine);
        final typeMatch = RegExp(r'^(Cr|Dr)\.?$').hasMatch(typeLine);
        final dateMatch = RegExp(r'^\d{1,2}\s*/\s*\d{1,2}\s*/\s*\d{4}$').hasMatch(dateLine);
        
        if (amountMatch && typeMatch && dateMatch && descLine.isNotEmpty) {
          final amount = double.tryParse(amountLine.replaceAll(',', ''));
          
          if (amount != null && amount > 0) {
            // Clean up date format 
            final cleanDate = dateLine.replaceAll(RegExp(r'\s*\/\s*'), '/');
            final isCredit = typeLine.toLowerCase().contains('cr');
            final transactionType = isCredit ? 'credit' : 'debit';
            
            // Clean description
            final description = descLine.replaceAll(RegExp(r'\s+'), ' ').trim();
            
            // Skip balance-related entries
            if (description.toLowerCase().contains('balance') ||
                description.toLowerCase().contains('outstanding') ||
                description.toLowerCase().contains('total') ||
                description.toLowerCase().contains('opening') ||
                description.toLowerCase().contains('closing')) {
              continue;
            }
            
            transactions.add({
              'id': DateTime.now().millisecondsSinceEpoch.toString(),
              'date': cleanDate,
              'description': description,
              'amount': amount,
              'transaction_type': transactionType,
              'merchantName': _extractMerchantName(description),
              'category': _categorizeTransaction(description),
              'originalLine': '$amountLine | $typeLine | $dateLine | $descLine',
              'bankName': 'zenith',
            });
            
            print('✅ Zenith Multi-line transaction extracted: $cleanDate - $description - ₹$amount ($transactionType)');
          }
        }
      }
    } catch (e) {
      print('❌ Error parsing Zenith multi-line transactions: $e');
    }
    
    return transactions;
  }
}
