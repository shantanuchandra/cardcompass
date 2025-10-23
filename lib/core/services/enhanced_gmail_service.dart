import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:googleapis/gmail/v1.dart' as gmail;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:cardcompass/shared/models/transaction.dart';
import '../services/pdf_parsing_service_impl.dart';
import '../services/password_input_service.dart';
import '../services/gemini_transaction_parser.dart';
import '../services/error_handling_service.dart';
import '../services/simple_birthday_input_service.dart';
import '../services/user_profile_database_service.dart';
import '../config/ai_config.dart';

class GmailEmail {
  final String id;
  final String subject;
  final String from;
  final String to;
  final DateTime date;
  final String? attachmentId;
  final String? attachmentName;

  const GmailEmail({
    required this.id,
    required this.subject,
    required this.from,
    required this.to,
    required this.date,
    this.attachmentId,
    this.attachmentName,
  });
}

/// Helper class for bank email search queries
class BankEmailQuery {
  final String bankName;
  final List<String> fromEmails;

  BankEmailQuery({
    required this.bankName,
    required this.fromEmails,
  });
}

/// Helper class for statement parsing results
class StatementParsingResult {
  final String bankName;
  final String? cardVariantName;  // Add card variant name
  final DateTime statementDate;
  final List<Transaction> transactions;
  final Uint8List originalPdfData;
  final String emailMessageId;
  final bool processingSuccess;
  
  // Additional email-related properties
  final String? emailSubject;
  final String? emailSender;
  
  // Additional statement-related properties
  final DateTime? dueDate;
  final double? totalAmountDue;
  final double? minimumAmountDue;
  final double? availableCredit;
  final double? rewardsEarned;

  StatementParsingResult({
    required this.bankName,
    this.cardVariantName,  // Add card variant name
    required this.statementDate,
    required this.transactions,
    required this.originalPdfData,
    required this.emailMessageId,
    required this.processingSuccess,
    this.emailSubject,
    this.emailSender,
    this.dueDate,
    this.totalAmountDue,
    this.minimumAmountDue,
    this.availableCredit,
    this.rewardsEarned,
  });
}

/// Helper class for PDF attachment information
class PdfAttachment {
  final String attachmentId;
  final String filename;
  final int size;

  PdfAttachment({
    required this.attachmentId,
    required this.filename,
    required this.size,
  });
}

/// Enhanced Gmail service with AI-powered statement processing
class EnhancedGmailService {
  static const List<String> _scopes = [
    gmail.GmailApi.gmailReadonlyScope,
    gmail.GmailApi.gmailModifyScope,
    'https://www.googleapis.com/auth/userinfo.profile',
    'https://www.googleapis.com/auth/user.birthday.read',
  ];

  gmail.GmailApi? _gmailApi;
  final PdfParsingServiceImpl _pdfParsingService;
  http.Client? _httpClient;  // Remove final to allow updating
  GoogleSignIn? _googleSignIn;
  GoogleSignInAccount? _currentUser;
  bool _isAuthenticated = false;

  EnhancedGmailService({
    gmail.GmailApi? gmailApi,
    required PdfParsingServiceImpl pdfParsingService,
    http.Client? httpClient,
  }) : _gmailApi = gmailApi,
       _pdfParsingService = pdfParsingService,
       _httpClient = httpClient {
    // Initialize Google Sign-In if Gmail API is not provided
    if (_gmailApi == null) {
      _googleSignIn = GoogleSignIn(scopes: _scopes);
    } else {
      _isAuthenticated = true; // Assume authenticated if API is provided
    }
  }
  /// Authenticate with Gmail API
  Future<bool> authenticate() async {
    if (_gmailApi != null) {
      // Already authenticated with provided API
      return _isAuthenticated;
    }

    try {
      if (_googleSignIn == null) {
        ErrorHandlingService.logError('Gmail Authentication', 'GoogleSignIn not initialized');
        return false;
      }

      // Try to sign in silently first
      _currentUser = await _googleSignIn!.signInSilently();
      
      // If silent sign-in fails, try interactive sign-in
      _currentUser ??= await _googleSignIn!.signIn();

      if (_currentUser == null) {
        ErrorHandlingService.logError('Gmail Authentication', 'User cancelled sign-in');
        return false;
      }

      // Get authentication headers
      final authHeaders = await _currentUser!.authHeaders;
      final authenticateClient = _AuthenticatedClient(authHeaders);
      
      // Initialize Gmail API and set HTTP client for People API
      _gmailApi = gmail.GmailApi(authenticateClient);
      _httpClient = authenticateClient;  // Use same authenticated client for People API
      _isAuthenticated = true;

      ErrorHandlingService.logError('Gmail Authentication', 'Successfully authenticated: ${_currentUser!.email}');
      return true;
    } catch (error, stackTrace) {
      ErrorHandlingService.logError(
        'Gmail Authentication',
        error,
        stackTrace: stackTrace,
      );
      _isAuthenticated = false;
      return false;
    }
  }
  /// Check if user is authenticated
  bool isAuthenticated() {
    return _isAuthenticated && _gmailApi != null;
  }
  /// Search for credit card statement emails
  Future<List<GmailEmail>> searchStatements({
    DateTime? startDate,
    DateTime? endDate,
    List<String>? bankNames,
  }) async {
    // Build generic search query (no sender filtering)
    String query = 'has:attachment filename:pdf';
    
    // Add comprehensive subject filters for statements
    final subjectKeywords = [
      'credit card statement',
      'card statement',
      'credit card'
    ];
    final subjectPart = subjectKeywords.map((keyword) => 'subject:"$keyword"').join(' OR ');
    query += ' ($subjectPart)';
    
    // Add date filters if provided
    if (startDate != null) {
      query += ' after:${startDate.year}/${startDate.month}/${startDate.day}';
    }
    if (endDate != null) {
      query += ' before:${endDate.year}/${endDate.month}/${endDate.day}';
    }

    // Use the generic search method
    return searchEmails(query);
  }

  /// Download PDF attachment from email
  Future<Uint8List> downloadAttachment(String attachmentId) async {
    try {
      // Extract messageId from attachmentId if needed (assuming format messageId:attachmentId)
      final parts = attachmentId.split(':');
      final messageId = parts.length > 1 ? parts[0] : attachmentId;
      final actualAttachmentId = parts.length > 1 ? parts[1] : attachmentId;
      
      return await _downloadAttachment(messageId, actualAttachmentId);
    } catch (error) {
      print('Error downloading attachment: $error');
      rethrow;
    }
  }

  /// Search emails with custom query
  Future<List<GmailEmail>> searchEmails(String query) async {
    if (!isAuthenticated()) {
      throw Exception('Not authenticated with Gmail');
    }

    try {
      final response = await _gmailApi!.users.messages.list(
        'me',
        q: query,
        maxResults: 50,
      );

      if (response.messages == null || response.messages!.isEmpty) {
        return [];
      }

      final emails = <GmailEmail>[];
      for (final message in response.messages!) {
        try {
          final detailedMessage = await _gmailApi!.users.messages.get(
            'me',
            message.id!,
          );
          
          final emailObj = _parseGmailMessage(detailedMessage);
          if (emailObj != null) {
            emails.add(emailObj);
          }
        } catch (e) {
          print('Error getting message details: $e');
        }
      }

      return emails;
    } catch (error) {
      print('Error searching emails: $error');
      return [];
    }
  }

  /// Get email details by ID
  Future<GmailEmail?> getEmailById(String emailId) async {
    try {
      final message = await _gmailApi!.users.messages.get('me', emailId);
      return _parseGmailMessage(message);
    } catch (error) {
      print('Error getting email by ID: $error');
      return null;
    }
  }
  /// Mark email as read
  Future<void> markAsRead(String emailId) async {
    try {
      await _gmailApi!.users.messages.modify(
        gmail.ModifyMessageRequest(removeLabelIds: ['UNREAD']),
        'me',
        emailId,
      );
    } catch (error) {
      print('Error marking email as read: $error');
    }
  }

  /// Sign out from Gmail and revoke access
  Future<void> signOut() async {
    try {
      if (_googleSignIn != null) {
        await _googleSignIn!.signOut();
      }
    } catch (error) {
      print('Error during sign out: $error');
    }
    _isAuthenticated = false;
    _currentUser = null;
    _gmailApi = null;
  }

  /// Revoke Gmail access (alias for signOut)
  Future<void> revokeAccess() async {
    await signOut();
  }

  /// Get email attachment metadata
  Future<Map<String, dynamic>?> getAttachmentMetadata(String attachmentId) async {
    try {
      final parts = attachmentId.split(':');
      final messageId = parts.length > 1 ? parts[0] : attachmentId;
      
      final message = await _gmailApi!.users.messages.get('me', messageId);
      final attachments = await _extractPdfAttachments(message);
      
      return attachments.isNotEmpty ? {
        'filename': attachments.first.filename,
        'size': attachments.first.size,
        'attachmentId': attachments.first.attachmentId,
      } : null;
    } catch (error) {
      print('Error getting attachment metadata: $error');
      return null;
    }
  }

  /// Refresh access token
  Future<bool> refreshToken() async {
    // Token refresh is handled externally, just return current state
    return _isAuthenticated;
  }

  /// Parse Gmail message to GmailEmail object
  GmailEmail? _parseGmailMessage(gmail.Message message) {
    try {
      final headers = message.payload?.headers ?? [];
      
      String subject = '';
      String from = '';
      String to = '';
      DateTime date = DateTime.now();
      String? attachmentId;
      String? attachmentName;

      // Extract headers
      for (final header in headers) {
        switch (header.name?.toLowerCase()) {
          case 'subject':
            subject = header.value ?? '';
            break;
          case 'from':
            from = header.value ?? '';
            break;
          case 'to':
            to = header.value ?? '';
            break;
          case 'date':
            try {
              date = DateTime.parse(header.value ?? '');
            } catch (e) {
              date = DateTime.now();
            }
            break;
        }
      }

      // Check for PDF attachments
      if (message.payload?.parts != null) {
        for (final part in message.payload!.parts!) {
          if (part.filename?.toLowerCase().endsWith('.pdf') == true) {
            attachmentId = '${message.id}:${part.body?.attachmentId}';
            attachmentName = part.filename;
            break;
          }
        }
      }

      return GmailEmail(
        id: message.id ?? '',
        subject: subject,
        from: from,
        to: to,
        date: date,
        attachmentId: attachmentId,
        attachmentName: attachmentName,
      );
    } catch (error) {
      print('Error parsing Gmail message: $error');
      return null;
    }
  }


  /// Determine bank name from sender email address (Implementation 1)
  String _getBankNameFromSender(String senderEmail) {
    final email = senderEmail.toLowerCase();
    
    // Amazon ICICI Bank (most specific first - check for Amazon keywords)
    if (email.contains('@icicibank.com') && 
        (email.contains('amazon') || email.contains('amazonpay'))) {
      return 'Amazon ICICI Bank';
    }
    
    // Amazon from domain
    if (email.contains('@amazon.com')) {
      return 'Amazon ICICI Bank';
    }
    
    // ICICI Bank (general)
    if (email.contains('@icicibank.com')) {
      return 'ICICI Bank';
    }
    
    // SBI Card
    if (email.contains('@sbicard.com')) {
      return 'SBI Card';
    }
    
    // HDFC Bank
    if (email.contains('@hdfcbank.com') || email.contains('@hdfcbank.net')) {
      return 'HDFC Bank';
    }
    
    // Axis Bank
    if (email.contains('@axisbank.com')) {
      return 'Axis Bank';
    }
    
    // Kotak Mahindra Bank
    if (email.contains('@kotak.com')) {
      return 'Kotak Mahindra Bank';
    }
    
    // Standard Chartered Bank
    if (email.contains('@sc.com') || email.contains('@standardchartered.com')) {
      return 'Standard Chartered Bank';
    }
    
    // AU Small Finance Bank
    if (email.contains('aubank.in') || email.contains('@aufinance.com') || email.contains('@ausfb.com')) {
      return 'AU Small Finance Bank';
    }
    
    // Punjab National Bank
    if (email.contains('@punjabnationalbank.in') || email.contains('@pnb.co.in')) {
      return 'Punjab National Bank';
    }
    
    // IDFC First Bank
    if (email.contains('@idfcfirstbank.com') || email.contains('@idfc.com')) {
      return 'IDFC First Bank';
    }
    
    // HSBC India
    if (email.contains('@hsbc.co.in') || email.contains('@hsbc.com')) {
      return 'HSBC India';
    }
    
    // IndusInd Bank
    if (email.contains('@indusind.com')) {
      return 'IndusInd Bank';
    }
    
    // OneCard (by FPL Technologies)
    if (email.contains('@onecardapp.com') || email.contains('@getonecard.app')) {
      return 'OneCard';
    }
    
    // Canara Bank
    if (email.contains('@canarabank.com') || email.contains('@canarabank.in')) {
      return 'Canara Bank';
    }
    
    // Bank of Baroda
    if (email.contains('@bankofbaroda.com') || email.contains('@bankofbaroda.in')) {
      return 'Bank of Baroda';
    }
    
    // Union Bank of India
    if (email.contains('@unionbankofindia.co.in') || email.contains('@ubi.co.in')) {
      return 'Union Bank of India';
    }
    
    // Bank of India
    if (email.contains('@bankofindia.co.in')) {
      return 'Bank of India';
    }
    
    // Central Bank of India
    if (email.contains('@centralbankofindia.co.in')) {
      return 'Central Bank of India';
    }
    
    // Indian Bank
    if (email.contains('@indianbank.co.in')) {
      return 'Indian Bank';
    }
    
    // RBL Bank
    if (email.contains('@rblbank.com')) {
      return 'RBL Bank';
    }
    
    // Yes Bank
    if (email.contains('@yesbank.in')) {
      return 'Yes Bank';
    }
    
    // Federal Bank
    if (email.contains('@federalbank.co.in')) {
      return 'Federal Bank';
    }
    
    // South Indian Bank
    if (email.contains('@southindianbank.com')) {
      return 'South Indian Bank';
    }
    
    // Karur Vysya Bank
    if (email.contains('@kvb.co.in')) {
      return 'Karur Vysya Bank';
    }
    
    // City Union Bank
    if (email.contains('@cityunionbank.com')) {
      return 'City Union Bank';
    }
    
    // Tamilnad Mercantile Bank
    if (email.contains('@tmb.in')) {
      return 'Tamilnad Mercantile Bank';
    }
    
    // Fallback: try to extract from domain
    if (email.contains('@')) {
      final domain = email.split('@').last;
      if (domain.contains('icici')) return 'ICICI Bank';
      if (domain.contains('sbi')) return 'SBI Card';
      if (domain.contains('hdfc')) return 'HDFC Bank';
      if (domain.contains('axis')) return 'Axis Bank';
      if (domain.contains('kotak')) return 'Kotak Mahindra Bank';
      if (domain.contains('sc') || domain.contains('standard')) return 'Standard Chartered Bank';
      if (domain.contains('au') || domain.contains('aubank') || domain.contains('aufinance')) return 'AU Small Finance Bank';
      if (domain.contains('pnb') || domain.contains('punjab')) return 'Punjab National Bank';
      if (domain.contains('idfc')) return 'IDFC First Bank';
      if (domain.contains('hsbc')) return 'HSBC India';
      if (domain.contains('indusind')) return 'IndusInd Bank';
      if (domain.contains('onecard')) return 'OneCard';
      if (domain.contains('canara')) return 'Canara Bank';
      if (domain.contains('baroda')) return 'Bank of Baroda';
      if (domain.contains('union')) return 'Union Bank of India';
      if (domain.contains('bankofindia')) return 'Bank of India';
      if (domain.contains('central')) return 'Central Bank of India';
      if (domain.contains('indian')) return 'Indian Bank';
      if (domain.contains('rbl')) return 'RBL Bank';
      if (domain.contains('yes')) return 'Yes Bank';
      if (domain.contains('federal')) return 'Federal Bank';
      if (domain.contains('south')) return 'South Indian Bank';
      if (domain.contains('kvb')) return 'Karur Vysya Bank';
      if (domain.contains('city')) return 'City Union Bank';
      if (domain.contains('tmb')) return 'Tamilnad Mercantile Bank';
    }
    
    return 'Unknown Bank';
  }

  /// Use Gemini to determine credit card variant (Implementation 2)
  Future<String> _detectCardVariant({
    required String emailSubject,
    required String emailBody,
    required String pdfText,
    required String bankName,
  }) async {
    try {
      // print('🔍 Calling Gemini API for card variant detection...');
      // print('   Subject: "$emailSubject"');
      // print('   Bank: "$bankName"');
      
      final requestBody = {
        'contents': [{
          'parts': [{
            'text': '''Extract only the credit card product name from this email subject. Remove bank names, "Credit Card", "Statement", and dates.

Subject: $emailSubject

Card name:'''
          }]
        }],
        'generationConfig': {
          'temperature': 0.0,
          'maxOutputTokens': 1000
        }
      };
      
      final response = await http.post(
        Uri.parse(AIConfig.geminiGenerateUrl),
        headers: AIConfig.geminiHeaders,
        body: json.encode(requestBody),
      );
      
      // print('📡 Gemini API response: Status ${response.statusCode}');
      // if (response.statusCode != 200) {
      //   print('   Response body: ${response.body}');
      // }
      
      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        // print('🔍 Decoded response keys: ${decoded.keys.toList()}');
        // if (decoded.containsKey('candidates')) {
        //   print('   Candidates: ${decoded['candidates']}');
        //   // Check the structure more deeply
        //   if (decoded['candidates'] is List && decoded['candidates'].isNotEmpty) {
        //     final firstCandidate = decoded['candidates'][0];
        //     print('   First candidate keys: ${firstCandidate.keys.toList()}');
        //     if (firstCandidate.containsKey('content')) {
        //       print('   Content structure: ${firstCandidate['content']}');
        //       if (firstCandidate['content'] is Map && firstCandidate['content'].containsKey('parts')) {
        //         print('   Parts: ${firstCandidate['content']['parts']}');
        //       }
        //     }
        //   }
        // }
        
        final content = decoded['candidates']?[0]?['content']?['parts']?[0]?['text'];
        if (content != null) {
          final variant = content.trim();
          print('🎯 Gemini detected card variant: "$variant" (from subject: "$emailSubject")');
          return variant;
        } else {
          print('❌ Content is null! Check response structure.');
        }
      } else {
        print('❌ Gemini card variant detection failed with status: ${response.statusCode}');
      }
      
      // Fallback to bank name if Gemini fails
      print('⚠️ Using fallback: returning bank name "$bankName"');
      return bankName;
    } catch (e) {
      // Fallback to bank name on error
      print('❌ Exception in _detectCardVariant: $e');
      print('⚠️ Using fallback: returning bank name "$bankName"');
      return bankName;
    }  }

  /// Process statement emails and extract transactions
  Future<List<StatementParsingResult>> processStatementEmails({
    required String userId,
    DateTime? startDate,
    DateTime? endDate,
    int? maxEmails,
  }) async {
    // Set default date range if not provided (last 1 month)
    final effectiveStartDate = startDate ?? DateTime.now().subtract(const Duration(days: 30));
    final effectiveEndDate = endDate ?? DateTime.now();

    // print('🔍 Searching emails from ${effectiveStartDate.toString().substring(0, 10)} to ${effectiveEndDate.toString().substring(0, 10)}');

    try {
      // Since we use generic search, process all statements without bank-specific filtering
      return await _searchAndProcessBankEmails(
        userId: userId,
        bankQuery: BankEmailQuery(
          bankName: 'All Banks',
          fromEmails: [], // No sender filtering - search all emails
        ),
        startDate: effectiveStartDate,
        endDate: effectiveEndDate,
        maxEmails: maxEmails,
      );
    } catch (error) {
      debugPrint('Error processing statement emails: $error');
      return [];
    }
  }

  /// Search and process emails for a specific bank
  Future<List<StatementParsingResult>> _searchAndProcessBankEmails({
    required String userId,
    required BankEmailQuery bankQuery,
    DateTime? startDate,
    DateTime? endDate,
    int? maxEmails,
  }) async {
    final results = <StatementParsingResult>[];    try {
      final query = _buildGmailSearchQuery(bankQuery, startDate, endDate);
      final searchResponse = await _gmailApi!.users.messages.list('me', q: query, maxResults: maxEmails);

      if (searchResponse.messages == null || searchResponse.messages!.isEmpty) {
        return results;
      }      
      
      for (final message in searchResponse.messages!) {
        if (message.id == null) continue;

        try {
          final statementResult = await _processStatementEmail(
            userId: userId,
            messageId: message.id!,
            bankName: bankQuery.bankName,
          );

          if (statementResult != null) {
            results.add(statementResult);
          }
        } catch (error) {
          debugPrint('Error processing message ${message.id}: $error');
        }
      }
    } catch (error) {
      debugPrint('Error searching emails for ${bankQuery.bankName}: $error');
    }

    return results;
  }

  /// Process individual statement email with sender-based bank detection
  Future<StatementParsingResult?> _processStatementEmail({
    required String userId,
    required String messageId,
    required String bankName,
  }) async {
    try {
      // Get full message with attachments
      final message = await _gmailApi!.users.messages.get('me', messageId, format: 'full');
      
      // Extract statement date from email
      final emailDate = DateTime.fromMillisecondsSinceEpoch(
        int.parse(message.internalDate ?? '0'),
      );
      
      // print('EMAIL ${emailDate.toString().substring(0, 19)} | $bankName');
      
      // Extract email headers
      String emailSubject = '';
      String emailBody = '';
      String userEmail = '';
      String senderEmail = '';
      
      if (message.payload?.headers != null) {
        for (final header in message.payload!.headers!) {
          if (header.name?.toLowerCase() == 'subject') {
            emailSubject = header.value ?? '';
          } else if (header.name?.toLowerCase() == 'from') {
            senderEmail = header.value ?? '';
          } else if (header.name?.toLowerCase() == 'delivered-to' || 
                     header.name?.toLowerCase() == 'to') {
            userEmail = header.value ?? '';
          }
        }
      }
      
      // Determine bank name from sender email (more reliable)
      final bankFromSender = _getBankNameFromSender(senderEmail);
      print('SENDER: $senderEmail');
      print('BANK: $bankFromSender (from sender email)');
      print('SUBJECT: $emailSubject');
      
      // Get email body
      emailBody = _extractEmailBody(message.payload);
      
      // Find PDF attachments
      final pdfAttachments = await _extractPdfAttachments(message);
      if (pdfAttachments.isEmpty) return null;
      
      // Process the largest PDF (likely the statement)
      pdfAttachments.sort((a, b) => b.size.compareTo(a.size));
      final statementPdf = pdfAttachments.first;
      
      // Download PDF content
      final pdfData = await _downloadAttachment(messageId, statementPdf.attachmentId);
      
      // Get user profile for password detection with birthday fallback
      final userProfile = await getUserProfileWithFallback(
        userId: userId, 
        verbose: false,
        // context: context, 
        // TODO: Pass context when available in UI
      );
      // if (userProfile.containsKey('birthday')) {
      //   print('📅 Using birthday from profile for password generation: ${userProfile['birthday']['raw']}');
      // } else {
      //   print('⚠️  No birthday found in user profile - password detection may be limited');
      // }
      
      // Extract PDF text for Gemini analysis
      String pdfText = '';
      try {
        pdfText = await _pdfParsingService.extractTextWithPasswordDetection(
          pdfBytes: pdfData,
          bankName: bankFromSender,
          emailSubject: emailSubject,
          emailBody: emailBody,
          userEmail: userEmail,
          userName: userProfile['displayName'],
          userProfile: userProfile,
          fileName: statementPdf.filename,
          onManualPasswordRequired: PasswordInputService.createSimpleCallback(
            bankFromSender,
            hint: _getPasswordHintForBank(bankFromSender),
          ),
        );
      } catch (e) {
        print('Error extracting PDF text: $e');
        pdfText = '';
      }
      
      // Use Gemini to detect the exact card variant
      final cardVariant = await _detectCardVariant(
        emailSubject: emailSubject,
        emailBody: emailBody,
        pdfText: pdfText,
        bankName: bankFromSender,
      );
      print('CARD: $cardVariant (detected by Gemini)');

      // Parse statement-level info using Gemini
      final statementInfo = await GeminiTransactionParser.parseStatementInfo(
        pdfText: pdfText,
        bankName: cardVariant,
      );
      
      // Extract transactions using Gemini
      final geminiTxs = await GeminiTransactionParser.parseTransactions(
        pdfText: pdfText,
        bankName: cardVariant,
      );
      
      // Convert Gemini transactions to Transaction objects with explicit type casting
      final transactions = <Transaction>[];
      for (final geminiTx in geminiTxs) {
        transactions.add(_convertGeminiToTransaction(
          geminiTx, 
          userId: userId, 
          emailDate: emailDate,
        ));
      }
      
      // Log metrics
      final lines = pdfText.split('\n').where((line) => line.trim().isNotEmpty).length;
      final sizeKB = (pdfData.length / 1024).toStringAsFixed(1);
      print('METRICS: Lines: $lines | Text: ${pdfText.length} chars | Size: ${sizeKB}KB');
      print('TRANSACTIONS: ${transactions.length}');
      
      // Add pause
      await Future.delayed(const Duration(seconds: 2));
      
      // Clean up card variant name to remove bank name and "Credit Card" terms
      final cleanCardName = _cleanCardVariantName(cardVariant, bankFromSender);
      
      // Return result
      print('-' * 60);
      return StatementParsingResult(
        bankName: bankFromSender,  // Use bank from sender, not card variant
        cardVariantName: cleanCardName,  // Add clean card name
        statementDate: emailDate,
        transactions: transactions,
        originalPdfData: pdfData,
        emailMessageId: messageId,
        processingSuccess: transactions.isNotEmpty,
        // Additional email properties
        emailSubject: emailSubject,
        emailSender: senderEmail,
        // Additional statement properties (TODO: extract from PDF if needed)
        dueDate: statementInfo['due_date'] != null ? DateTime.tryParse(statementInfo['due_date']) : null,
        totalAmountDue: (statementInfo['total_amount'] as num?)?.toDouble(),
        minimumAmountDue: (statementInfo['minimum_payment'] as num?)?.toDouble(),
        availableCredit: (statementInfo['available_credit'] as num?)?.toDouble(),
        rewardsEarned: (statementInfo['rewards_earned'] as num?)?.toDouble(),
      );
    } catch (error) {
      print('Error processing statement email $messageId: $error');
      print('-' * 60);
      return null;
    }
  }

  /// Convert Gemini transaction format to Transaction model
  Transaction _convertGeminiToTransaction(
    Map<String, dynamic> geminiTx, {
    required String userId,
    required DateTime emailDate,
  }) {
    // Parse transaction date
    DateTime transactionDate;
    try {
      if (geminiTx['date'] != null) {
        transactionDate = DateTime.parse(geminiTx['date']);
      } else {
        transactionDate = emailDate;
      }
    } catch (e) {
      transactionDate = emailDate;
    }

    // Parse category
    TransactionCategory category = TransactionCategory.other;
    if (geminiTx['category'] != null) {
      switch (geminiTx['category'].toString().toLowerCase()) {
        case 'shopping':
          category = TransactionCategory.shopping;
          break;
        case 'dining':
        case 'food':
          category = TransactionCategory.food;
          break;
        case 'travel':
          category = TransactionCategory.travel;
          break;
        case 'fuel':
          category = TransactionCategory.fuel;
          break;
        case 'entertainment':
          category = TransactionCategory.entertainment;
          break;
        case 'bills':
        case 'utilities':
          category = TransactionCategory.utilities;
          break;
        default:
          category = TransactionCategory.other;
      }
    }

    // Parse transaction type
    TransactionType type = TransactionType.debit;
    if (geminiTx['type'] != null) {
      switch (geminiTx['type'].toString().toLowerCase()) {
        case 'credit':
          type = TransactionType.credit;
          break;
        case 'debit':
        default:
          type = TransactionType.debit;
      }
    }

    // Parse amount
    double amount = 0.0;
    if (geminiTx['amount'] != null) {
      if (geminiTx['amount'] is num) {
        amount = geminiTx['amount'].toDouble();
      } else if (geminiTx['amount'] is String) {
        amount = double.tryParse(geminiTx['amount']) ?? 0.0;
      }
    }

    return Transaction(
      id: geminiTx['id'] ?? 'tx_${DateTime.now().millisecondsSinceEpoch}',
      userId: userId,
      amount: amount.abs(),
      currency: geminiTx['currency'] ?? 'INR',
      description: geminiTx['description'] ?? 'Transaction',
      merchantName: geminiTx['merchantName'],
      category: category,
      type: type,
      transactionDate: transactionDate,
      location: null,
      rewardEarned: null,
      rewardType: null,
      metadata: {
        'source': 'gemini',
        'reference': geminiTx['reference'],
      },
      statementId: null,
      isRecurring: false,
      createdAt: DateTime.now(),
    );
  }  /// Build Gmail search query with enhanced filtering
  String _buildGmailSearchQuery(BankEmailQuery bankQuery, DateTime? startDate, DateTime? endDate) {
    final queryParts = <String>[];
    
    // Add domain-based email filtering with OR logic
    if (bankQuery.fromEmails.isNotEmpty) {
      final fromPart = bankQuery.fromEmails.map((domain) => 'from:$domain').join(' OR ');
      queryParts.add('($fromPart)');
    }
    
    // Enhanced attachment filtering
    queryParts.add('has:attachment');
    queryParts.add('filename:pdf');
      // Use comprehensive generic subject keywords for all banks
    final commonSubjectKeywords = [
      'credit card statement',
      'card statement',
      'credit card',
      'billing statement'
    ];
    final genericSubjectPart = commonSubjectKeywords.map((keyword) => 'subject:"$keyword"').join(' OR ');
    queryParts.add('($genericSubjectPart)');
    
    // Ensure it's not spam or promotional
    queryParts.add('-label:spam');
    queryParts.add('-label:promotions');
    
    // Size filter - statements are typically larger than 50KB
    queryParts.add('size:51200'); // 50KB minimum
    
    // Always use 1 month date range for search
    final searchStartDate = startDate ?? DateTime.now().subtract(const Duration(days: 30));
    final searchEndDate = endDate ?? DateTime.now();
    
    queryParts.add('after:${searchStartDate.year}/${searchStartDate.month}/${searchStartDate.day}');
    queryParts.add('before:${searchEndDate.year}/${searchEndDate.month}/${searchEndDate.day}');
    
    final finalQuery = queryParts.join(' ');
    // print('🔍 Gmail search query for ${bankQuery.bankName}: $finalQuery');
    
    return finalQuery;
  }

  /// Extract email body content
  String _extractEmailBody(gmail.MessagePart? payload) {
    if (payload == null) return '';
    
    // Try to get text from body
    if (payload.body?.data != null) {
      try {
        final decodedBytes = base64Decode(payload.body!.data!.replaceAll('-', '+').replaceAll('_', '/'));
        return utf8.decode(decodedBytes);
      } catch (e) {
        // Continue to try parts
      }
    }
    
    // Try to get text from parts
    if (payload.parts != null) {
      for (final part in payload.parts!) {
        if (part.mimeType == 'text/plain' || part.mimeType == 'text/html') {
          final bodyText = _extractEmailBody(part);
          if (bodyText.isNotEmpty) return bodyText;
        }
      }
    }
    
    return '';
  }

  /// Extract PDF attachments from message
  Future<List<PdfAttachment>> _extractPdfAttachments(gmail.Message message) async {
    final attachments = <PdfAttachment>[];
    
    void findAttachments(gmail.MessagePart? part) {
      if (part == null) return;
      
      if (part.filename != null && 
          part.filename!.toLowerCase().endsWith('.pdf') &&
          part.body?.attachmentId != null) {
        attachments.add(PdfAttachment(
          attachmentId: part.body!.attachmentId!,
          filename: part.filename!,
          size: part.body?.size ?? 0,
        ));
      }
      
      if (part.parts != null) {
        for (final subPart in part.parts!) {
          findAttachments(subPart);
        }
      }
    }
    
    findAttachments(message.payload);
    return attachments;
  }

  /// Download attachment by ID
  Future<Uint8List> _downloadAttachment(String messageId, String attachmentId) async {
    final attachment = await _gmailApi!.users.messages.attachments.get(
      'me',
      messageId,
      attachmentId,
    );
    
    if (attachment.data == null) {
      throw Exception('No attachment data found');
    }
    
    return base64Decode(attachment.data!.replaceAll('-', '+').replaceAll('_', '/'));
  }

  /// Get user profile from Google People API
  Future<Map<String, dynamic>> getUserProfile({
    required String userId,
    bool verbose = true,
  }) async {
    try {
      if (_httpClient == null) {
        if (verbose) print('❌ No HTTP client available for People API - authentication may be incomplete');
        return {'displayName': 'User'};
      }
        
      if (verbose) print('🔍 Fetching user profile from People API...');
      
      // Make the API call with proper error handling
      final response = await _httpClient!.get(
        Uri.parse('https://people.googleapis.com/v1/people/me?personFields=names,birthdays,emailAddresses'),
      );
      
      if (verbose) {
        print('📡 People API Response Status: ${response.statusCode}');
        print('📡 People API Response Headers: ${response.headers}');
      }
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (verbose) {
          print('📋 Raw People API Response: ${json.encode(data)}');
        }
        
        final profile = <String, dynamic>{};
        
        // Extract display name
        if (data['names'] != null && data['names'].isNotEmpty) {
          profile['displayName'] = data['names'][0]['displayName'] ?? 'User';
          if (verbose) print('✅ Found display name: ${profile['displayName']}');
        } else {
          profile['displayName'] = 'User';
          if (verbose) print('⚠️  No display name found, using default');
        }
        
        // Extract birthday with comprehensive debugging
        if (data['birthdays'] != null && data['birthdays'].isNotEmpty) {
          if (verbose) {
            print('📅 Processing birthday data...');
            print('📅 Total birthday entries found: ${data['birthdays'].length}');
          }
          
          // Try different birthday entries (Google can have multiple)
          bool foundValidBirthday = false;
          for (int i = 0; i < data['birthdays'].length; i++) {
            final birthdayEntry = data['birthdays'][i];
            // if (verbose) print('📅 Processing birthday entry #${i + 1}: $birthdayEntry');
            
            final birthdayData = birthdayEntry['date'];
            if (birthdayData != null && birthdayData is Map<String, dynamic>) {
              // if (verbose) {
              //   print('📅 Raw birthday data: $birthdayData');
              //   print('📅 Year: ${birthdayData['year']}, Month: ${birthdayData['month']}, Day: ${birthdayData['day']}');
              // }
              
              // Format birthday data for password generation
              final formattedBirthday = _formatBirthdayForPasswordGeneration(birthdayData, verbose: false);
              
              if (formattedBirthday.isNotEmpty) {
                profile['birthday'] = formattedBirthday;
                // if (verbose) print('✅ Found and formatted birthday: ${profile['birthday']['raw']}');
                foundValidBirthday = true;
                break; // Use the first valid birthday found
              } else {
                if (verbose) print('⚠️  Birthday data incomplete for entry #${i + 1}: $birthdayData');
              }
            } else {
              if (verbose) print('⚠️  Birthday entry #${i + 1} has null or invalid date: $birthdayEntry');
            }
          }
          
          // If no valid birthday was found, set it explicitly to null
          if (!foundValidBirthday) {
            profile['birthday'] = null;
            if (verbose) {
              print('⚠️  No valid birthday found in any entry');
              print('💡 This could mean:');
              print('   - User has not set birthday in Google Account');
              print('   - Birthday data is private/restricted');
              print('   - Missing year in birthday data');
              print('   - Authentication scope issue');
            }
          }
        } else {
          profile['birthday'] = null;
          if (verbose) {
            print('⚠️  No birthday data found in profile response');
            print('💡 Possible reasons:');
            print('   - User has not set birthday in Google Account');
            print('   - Birthday.read permission not granted');
            print('   - Birthday data is private in user settings');
          }
        }
        
        // if (verbose) print('📋 Final profile keys available: ${profile.keys.join(', ')}');
        return profile;
      } else {
        if (verbose) {
          print('❌ People API returned status: ${response.statusCode}');
          print('❌ Response body: ${response.body}');
          
          // Provide specific debugging for common error codes
          if (response.statusCode == 403) {
            print('💡 403 Forbidden - This usually means:');
            print('   - Missing birthday.read scope in authentication');
            print('   - API not enabled for the project');
            print('   - Insufficient permissions');
          } else if (response.statusCode == 401) {
            print('💡 401 Unauthorized - This usually means:');
            print('   - Authentication token expired');
            print('   - Invalid or missing authentication');
          }
        }
        return {'displayName': 'User'};
      }
      
    } catch (error) {
      if (verbose) {
        print('❌ Error fetching user profile: $error');
        print('💡 Error details: ${error.runtimeType}');
      }
      return {'displayName': 'User'};
    }
  }

  /// Handle birthday fallback when Google API fails
  Future<Map<String, dynamic>> _handleBirthdayFallback(
    String userId,
    String reason, {
    BuildContext? context,
    bool verbose = true,
    Map<String, dynamic>? profile,
  }) async {
    if (verbose) {
      print('🔄 STEP 3: Initiating birthday fallback...');
      print('📋 Reason: $reason');
    }

    // Use provided profile or create default
    final fallbackProfile = profile ?? <String, dynamic>{'displayName': 'User'};

    try {
      // Request birthday from user
      final birthday = await SimpleBirthdayInputService.requestBirthdayInput(
        context: context,
        userId: userId,
        reason: reason,
      );

      if (birthday != null && SimpleBirthdayInputService.isValidBirthday(birthday)) {
        if (verbose) print('✅ User provided valid birthday: ${birthday.toString().substring(0, 10)}');
        
        // Store birthday in database
        final stored = await UserProfileDatabaseService.storeUserDateOfBirth(userId, birthday);
        if (stored) {
          if (verbose) print('✅ Birthday stored successfully in database');
          
          // Format birthday for password generation
          fallbackProfile['birthday'] = SimpleBirthdayInputService.formatBirthdayForPasswords(birthday);
          if (verbose) print('✅ Birthday formatted for password generation');
          
          return fallbackProfile;
        } else {
          if (verbose) print('⚠️  Could not store birthday in database, but will use for this session');
          fallbackProfile['birthday'] = SimpleBirthdayInputService.formatBirthdayForPasswords(birthday);
          return fallbackProfile;
        }
      } else {
        if (verbose) print('⚠️  User did not provide valid birthday or cancelled');
        fallbackProfile['birthday'] = null;
        return fallbackProfile;
      }
    } catch (error) {
      if (verbose) print('❌ Error in birthday fallback: $error');
      fallbackProfile['birthday'] = null;
      return fallbackProfile;
    }
  }

  /// Get user profile information from Google People API with birthday fallback
  Future<Map<String, dynamic>> getUserProfileWithFallback({
    required String userId,
    bool verbose = true,
    BuildContext? context,
  }) async {
    try {
      // STEP 1: Check database for stored birthday first
      if (verbose) print('📅 Step 1: Checking database for stored birthday...');
      final storedBirthday = await UserProfileDatabaseService.getUserDateOfBirth(userId);
      
      if (storedBirthday != null) {
        if (verbose) {
          print('✅ Found stored birthday: ${storedBirthday.toString().substring(0, 10)} (source: database)');
        }
        
        // Still try to get display name from Google API
        Map<String, dynamic> profile = {'displayName': 'User'};
        if (_httpClient != null) {
          try {
            final response = await _httpClient!.get(
              Uri.parse('https://people.googleapis.com/v1/people/me?personFields=names,emailAddresses'),
            );
            if (response.statusCode == 200) {
              final data = json.decode(response.body);
              if (data['names'] != null && data['names'].isNotEmpty) {
                profile['displayName'] = data['names'][0]['displayName'] ?? 'User';
              }
            }
          } catch (e) {
            if (verbose) print('⚠️  Could not fetch display name from Google API: $e');
            // Use database display name if available
            profile['displayName'] = await UserProfileDatabaseService.getUserDisplayName(userId);
          }
        }
        
        // Use stored birthday
        profile['birthday'] = UserProfileDatabaseService.formatBirthdayForPasswords(storedBirthday);
        return profile;
      }
      
      // STEP 2: Try existing Google People API method
      if (verbose) print('📅 Step 2: Trying Google People API...');
      final googleProfile = await getUserProfile(userId: userId, verbose: verbose);
      
      // If Google API provided birthday, store it and return
      if (googleProfile['birthday'] != null) {
        if (verbose) print('✅ Google API provided birthday successfully');
        try {
          final birthdayDate = DateTime.parse(googleProfile['birthday']['raw']);
          await UserProfileDatabaseService.storeUserDateOfBirth(userId, birthdayDate);
          if (verbose) print('✅ Stored Google API birthday in database for future use');
        } catch (e) {
          if (verbose) print('⚠️  Could not store Google API birthday: $e');
        }
        return googleProfile;
      }
      
      // STEP 3: Google API failed, trigger fallback
      return await _handleBirthdayFallback(
        userId, 
        'Google API did not provide birthday data - see details above',
        context: context,
        verbose: verbose,
        profile: googleProfile,
      );
      
    } catch (error) {
      if (verbose) {
        print('❌ Error in getUserProfileWithFallback: $error');
      }
      return await _handleBirthdayFallback(
        userId, 
        'Unexpected error: ${error.toString()}',
        context: context,
        verbose: verbose,
      );
    }
  }

  /// Format birthday data from Google People API for password generation
  Map<String, String> _formatBirthdayForPasswordGeneration(Map<String, dynamic> birthdayData, {bool verbose = false}) {
    final year = birthdayData['year']?.toString() ?? '';
    final month = birthdayData['month']?.toString().padLeft(2, '0') ?? '';
    final day = birthdayData['day']?.toString().padLeft(2, '0') ?? '';
    
    if (verbose) {
      print('🔍 Formatting birthday - Year: "$year", Month: "$month", Day: "$day"');
    }
    
    if (year.isEmpty || month.isEmpty || day.isEmpty) {
      if (verbose) {
        print('⚠️  Missing required fields for birthday formatting:');
        print('   - Year: ${year.isEmpty ? 'MISSING' : year}');
        print('   - Month: ${month.isEmpty ? 'MISSING' : month}');
        print('   - Day: ${day.isEmpty ? 'MISSING' : day}');
      }
      return {};
    }
    
    final shortYear = year.length >= 4 ? year.substring(2) : year;
    
    final result = {
      'ddmm': '$day$month',           // 0212
      'ddmmyy': '$day$month$shortYear', // 021290
      'ddmmyyyy': '$day$month$year',   // 02121990
      'yyyymmdd': '$year$month$day',   // 19901202
      'mmddyyyy': '$month$day$year',   // 02121990
      'raw': '$year-$month-$day',      // Keep raw format for reference
    };
    
    if (verbose) {
      print('✅ Successfully formatted birthday: $result');
    }
    
    return result;
  }

  /// Get password hint for specific bank
  String? _getPasswordHintForBank(String bankName) {
    final bank = bankName.toLowerCase();
    
    if (bank.contains('sbi')) {
      return 'Format: DOB(DDMMYYYY) + Last4Digits of card';
    } else if (bank.contains('idfc')) {
      return 'Try: Your date of birth (DDMMYYYY) or first name + DOB';
    } else if (bank.contains('hdfc')) {
      return 'Try: Your date of birth (DDMMYYYY) or last 4 digits of card';
    } else if (bank.contains('icici')) {
      return 'Try: Your date of birth (DDMMYYYY) or mobile number last 4 digits';
    } else if (bank.contains('axis')) {
      return 'Try: Your date of birth (DDMMYYYY) or card last 4 digits';
    }
    
    return 'Try: Your date of birth (DDMMYYYY) or card details';
  }

  /// Clean card variant name to remove bank name and "Credit Card" terms
  String _cleanCardVariantName(String cardVariant, String bankName) {
    String cleaned = cardVariant.trim();
    
    // Remove bank name from the beginning or end
    final bankWords = bankName.toLowerCase().split(' ');
    for (final word in bankWords) {
      if (word.isNotEmpty) {
        // Remove bank word from beginning
        if (cleaned.toLowerCase().startsWith(word)) {
          cleaned = cleaned.substring(word.length).trim();
        }
        // Remove bank word from end
        if (cleaned.toLowerCase().endsWith(word)) {
          cleaned = cleaned.substring(0, cleaned.length - word.length).trim();
        }
      }
    }
    
    // Remove "Credit Card" and variations
    cleaned = cleaned.replaceAll(RegExp(r'\bcredit card\b', caseSensitive: false), '').trim();
    cleaned = cleaned.replaceAll(RegExp(r'\bcard\b', caseSensitive: false), '').trim();
    
    // Remove duplicate words (like "Zenith Zenith" -> "Zenith")
    final words = cleaned.split(' ');
    final uniqueWords = <String>[];
    for (final word in words) {
      if (word.isNotEmpty && !uniqueWords.contains(word.toLowerCase())) {
        uniqueWords.add(word);
      }
    }
    cleaned = uniqueWords.join(' ');
    
    // Handle special cases
    if (cleaned.toLowerCase().contains('amazon pay')) {
      cleaned = 'Amazon Pay';
    } else if (cleaned.toLowerCase().contains('diners club black')) {
      cleaned = 'Diners Club Black';
    } else if (cleaned.toLowerCase().contains('first power plus')) {
      cleaned = 'First Power Plus';
    } else if (cleaned.toLowerCase().contains('swiggy')) {
      cleaned = 'Swiggy';
    } else if (cleaned.toLowerCase() == 'zenith') {
      cleaned = 'Zenith';
    }
    
    return cleaned.isNotEmpty ? cleaned : cardVariant;
  }
}
/// Authenticated HTTP client for Gmail API requests
class _AuthenticatedClient extends http.BaseClient {
  final Map<String, String> _authHeaders;
  final http.Client _client = http.Client();

  _AuthenticatedClient(this._authHeaders);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_authHeaders);
    return _client.send(request);
  }

  @override
  void close() {
    _client.close();
  }
}
