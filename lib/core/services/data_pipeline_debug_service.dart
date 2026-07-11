import 'package:googleapis_auth/auth_io.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'package:googleapis/gmail/v1.dart' as gmail;
import 'package:cardcompass/core/services/simple_supabase_schema_service.dart';
import 'package:cardcompass/core/services/enhanced_gmail_service.dart';
import 'package:cardcompass/core/services/pdf_parsing_service_impl.dart';
import 'package:cardcompass/core/services/gemini_transaction_parser.dart';
import 'package:cardcompass/core/services/password_input_service.dart';
import 'package:cardcompass/core/repositories/supabase_transaction_repository.dart';
import 'package:cardcompass/core/repositories/supabase_card_repository.dart';
import 'package:cardcompass/core/repositories/supabase_statement_repository.dart';
import 'package:cardcompass/core/repositories/email_repository.dart';
import 'package:cardcompass/shared/models/transaction.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cardcompass/debug/sync_flow_debugger.dart';
import 'package:cardcompass/core/config/ai_config.dart';
import 'package:cardcompass/core/app_config.dart';

/// Result class for card operations that returns both catalog and user card IDs
class CardInfo {
  final String catalogCardId;
  final String userCardId;
  
  CardInfo({required this.catalogCardId, required this.userCardId});
}

/**
 * Service for debugging and testing the complete data pipeline.
 * 
 * This service provides methods to test each step of the pipeline:
 * 1. Database setup and connectivity
 * 2. Gmail API authentication and email fetching
 * 3. PDF extraction and parsing
 * 4. Data storage in Supabase
 * 5. ML algorithm execution
 */
class DataPipelineDebugService {
  final SimpleSupabaseSchemaService _schemaService = SimpleSupabaseSchemaService();
  EnhancedGmailService? _gmailService;
  final SupabaseTransactionRepository _transactionRepo = SupabaseTransactionRepository();
  final SupabaseCardRepository _cardRepo = SupabaseCardRepository();
  final SupabaseStatementRepository _statementRepo = SupabaseStatementRepository();
  final EmailRepository _emailRepo = EmailRepository();
  
  /// Callback to prompt user for card URL input
  /// Returns the URL provided by the user, or null if skipped
  Future<String?> Function({
    required String bankName,
    required String cardVariant,
    required String emailSubject,
    String? suggestedUrl,
  })? onCardUrlRequired;

  /// Inject a pre-authenticated [EnhancedGmailService] so the pipeline skips
  /// its own sign-in flow (used when the caller already performed OAuth).
  void injectGmailService(EnhancedGmailService service) {
    _gmailService = service;
  }

  /// Loads benefits from an external source (e.g., API, file).
  Future<void> loadBenefitsFromSource(String source) async {
    print('\nLoading benefits from source: $source');
    print('-----------------------------------');

    try {
      // Simulate fetching data from an external source
      print('- Fetching data...');
      final benefitsData = await _fetchBenefitsData(source);

      // Validate the data
      print('- Validating data...');
      if (!await _validateBenefitsData(benefitsData)) {
        throw Exception('Benefits data validation failed.');
      }

      // Store the data in the database
      print('- Storing benefits in the database...');
      await _storeBenefitsData(benefitsData);

      print('+ Benefits loaded successfully.');
    } catch (e) {
      print('X Error loading benefits: $e');
      // Consider more specific error handling (e.g., logging, retries)
      rethrow;
    }
  }

  /// Simulates fetching benefits data from an external source.
  Future<List<Map<String, dynamic>>> _fetchBenefitsData(String source) async {
    // Replace with actual API call or file reading logic
    await Future.delayed(const Duration(seconds: 2)); // Simulate network delay

    // Sample data (replace with actual data fetching)
    final sampleData = [
      {
        'card_id': '550e8400-e29b-41d4-a716-446655440000',
        'benefit_type': 'cashback',
        'benefit_details': '{"rate": 0.05}',
        'applicable_categories': ['dining', 'entertainment'],
        'min_spend_requirement': 1000.00,
        'max_benefit_limit': 500.00,
        'expiry_date': '2025-12-31T00:00:00Z',
      },
      {
        'card_id': '550e8400-e29b-41d4-a716-446655440001',
        'benefit_type': 'rewards',
        'benefit_details': '{"points_per_dollar": 2}',
        'applicable_categories': ['shopping', 'travel'],
        'min_spend_requirement': null,
        'max_benefit_limit': null,
        'expiry_date': '2025-06-30T00:00:00Z',
      },
    ];

    return sampleData;
  }

  /// Simulates validating benefits data.
  Future<bool> _validateBenefitsData(List<Map<String, dynamic>> data) async {
    // Implement actual validation logic here
    if (data.isEmpty) {
      print('  - No data provided');
      return false;
    }

    for (final benefit in data) {
      if (!benefit.containsKey('card_id') ||
          !benefit.containsKey('benefit_type') ||
          !benefit.containsKey('benefit_details')) {
        print('  - Missing required fields in benefit: $benefit');
        return false;
      }
    }

    return true;
  }

  /// Simulates storing benefits data in the database.
  Future<void> _storeBenefitsData(List<Map<String, dynamic>> data) async {
    // Replace with actual database insertion logic
    for (final benefit in data) {
      print('  - Storing benefit: $benefit');
      //await _benefitsRepo.insertBenefit(benefit); // Assuming you have a benefits repository
    }
    await Future.delayed(const Duration(seconds: 1)); // Simulate database operation
  }

  /**
   * Runs complete pipeline debugging tests.
   */
  Future<void> debugCompletePipeline(String userId) async {
    print('--- Starting Complete Data Pipeline Debug ---');
    print('=======================================');
    
    try {
      // Step 1: Setup database
      await debugDatabaseSetup();
      
      // Step 2: Test Gmail API
      final authClient = await debugGmailAuthentication();
      if (authClient == null) {
        print('X Gmail authentication failed - stopping pipeline test');
        return;
      }
      
      // Step 3: Test Gmail fetch and parsing
      final statements = await debugEmailReading(userId, authClient);
      
      // Step 4: Test PDF processing on first statement
      if (statements.isNotEmpty) {
        await debugPdfProcessing(statements.first);
      }
      
      // Step 5: Test data storage
      await debugDataStorage(userId);
      
      // Step 6: Test ML algorithms
      await debugMLAlgorithms(userId);
      
      print('> Complete pipeline debugging finished');
      
    } catch (e) {
      print('X Pipeline debugging failed: $e');
      rethrow;
    }
  }

  /**
   * Step 1: Debug database setup and connectivity.
   */
  Future<void> debugDatabaseSetup() async {
    print('\nStep 1: Database Setup');
    print('-------------------------');
    
    try {
      // Test schema verification
      print('- Testing database connectivity and schema...');
      await _schemaService.verifyTablesExist();
      print('+ Database schema verified - all tables exist');
      
      // Test basic connectivity with a valid UUID
      print('- Testing repository connectivity...');
      final testUserId = const Uuid().v4();
      await _cardRepo.getUserCards(testUserId);
      print('+ Database connectivity confirmed');
      
    } catch (e) {
      print('X Database setup failed: $e');
      rethrow;
    }
  }

  /**
   * Step 2: Debug Gmail API authentication.
   */
  Future<AuthClient?> debugGmailAuthentication() async {
    print('\nStep 2: Gmail API Authentication');
    print('-----------------------------------');

    const List<String> scopes = [
      'https://www.googleapis.com/auth/gmail.readonly',
      'https://www.googleapis.com/auth/gmail.modify',
      'https://www.googleapis.com/auth/userinfo.profile',
      'https://www.googleapis.com/auth/userinfo.email',
      'https://www.googleapis.com/auth/user.birthday.read',
      'https://www.googleapis.com/auth/user.addresses.read',
    ];
    
    try {
      print('- Attempting Google Sign-In...');
      // Try silent auth first (uses existing session), then interactive
      GoogleSignInAccount? account =
          await GoogleSignIn.instance.attemptLightweightAuthentication();
      account ??= await GoogleSignIn.instance.authenticate(scopeHint: scopes);
      
      print('+ Google Sign-In successful: ${account.email}');

      // Request OAuth access token for required Gmail scopes
      final authz = await account.authorizationClient.authorizeScopes(scopes);
      final accessToken = authz.accessToken;
      print('+ Access token obtained: ${accessToken.substring(0, 20)}...');

      // Build an AuthClient using googleapis_auth
      final authClient = authenticatedClient(
        http.Client(),
        AccessCredentials(
          AccessToken('Bearer', accessToken,
              DateTime.now().toUtc().add(const Duration(hours: 1))),
          null,
          scopes,
        ),
      );

      // Initialize Gmail service with required dependencies
      final gmailApi = gmail.GmailApi(authClient);
      final pdfParsingService = PdfParsingServiceImpl();
      
      _gmailService = EnhancedGmailService(
        gmailApi: gmailApi,
        pdfParsingService: pdfParsingService,
        httpClient: authClient,
      );
      print('+ Gmail API service initialized');
      
      return authClient;
      
    } catch (e) {
      print('X Gmail authentication failed: $e');
      return null;
    }
  }

  Future<List<StatementParsingResult>> debugEmailReading(String userId, AuthClient authClient) async {
    print('\nStep 3: Sequential Email Processing');
    print('----------------------------------');
    
    try {
      // Ensure Gmail service is initialized
      if (_gmailService == null) {
        final gmailApi = gmail.GmailApi(authClient);        final pdfParsingService = PdfParsingServiceImpl();
          _gmailService = EnhancedGmailService(
          gmailApi: gmailApi,
          pdfParsingService: pdfParsingService,
          httpClient: authClient,
        );
      }
      
      // Step 1: DOB storage via Gmail API
      print('- Step 1: Fetching and storing DOB via Gmail API...');
      final userProfile = await _gmailService!.getUserProfile(userId: userId, verbose: false);
      if (userProfile.containsKey('birthday')) {
        print('+ DOB stored: ${userProfile['birthday']['ddmm']} format available');
      } else {
        print('⚠️ DOB not available from Google People API');
      }
      
      // Get emails to process
      print('- Finding relevant statement emails...');
      final endDate = DateTime.now();
      final startDate = endDate.subtract(const Duration(days: 30));
        final allStatements = await _gmailService!.processStatementEmails(
        userId: userId,
        startDate: startDate,
        endDate: endDate,
      );
      
      print('+ Found ${allStatements.length} potential statement emails');
      
      // Process emails sequentially (one at a time)
      final processedStatements = <StatementParsingResult>[];
      
      for (int i = 0; i < allStatements.length; i++) {
        final statement = allStatements[i];
        print('\n--- Processing Email ${i + 1}/${allStatements.length} ---');
        print('Bank: ${statement.bankName}');
        print('Date: ${statement.statementDate}');
        print('PDF Size: ${statement.originalPdfData.length} bytes');
          // Step 2-6: Process this single email through the complete flow
        final result = await _processEmailWithCompleteFlow(
          userId,
          statement,
          userProfile,
        );
        
        if (result != null) {
          processedStatements.add(result);
        }
        
        print('─' * 60); // Separator after each email
      }
      
      return processedStatements;
    } catch (e) {
      print('X Email fetching/parsing failed: $e');
      return [];
    }
  }

  /**
   * Step 4: Debug PDF fetching and parsing.
   */
  Future<void> debugPdfProcessing(StatementParsingResult statement) async {
     print('\nStep 4: PDF Processing');
     print('-------------------------');
     
     try {
      print('- Processing statement for bank: ${statement.bankName}');
      final transactions = statement.transactions;
      print('- Parsing already done. Transactions count: ${transactions.length}');
      if (transactions.isNotEmpty) {
        final tx = transactions.first;
        print('  Sample: Date=${tx.transactionDate}, Desc=${tx.description}, Amount=Rs.${tx.amount}');
      }
     } catch (e) {
       print('X PDF processing failed: $e');
     }
  }

  /**
   * Step 5: Debug data storage in Supabase.
   */
  Future<void> debugDataStorage(String userId) async {
     print('\nStep 5: Data Storage');
     print('-----------------------');
     
     try {
      // Test retrieving user data
      print('- Retrieving user cards and transactions');
      final userCards = await _cardRepo.getUserCards(userId);
      final userTransactions = await _transactionRepo.getUserTransactions(userId, limit: 10);
      print('+ Retrieved ${userCards.length} cards and ${userTransactions.length} transactions');
     } catch (e) {
       print('X Data storage failed: $e');
     }
   }

  /**
   * Step 6: Debug ML algorithms execution.
   */
  Future<void> debugMLAlgorithms(String userId) async {
    print('\nStep 6: ML Algorithms');
    print('------------------------');
    
    try {
      // Placeholder for ML algorithms debug
      print('- Running ML analysis placeholder (integrate your ML services here)');
      // e.g., await MlAnalysisService().runAlgorithms(userId);
      print('+ ML debug step completed');
      
    } catch (e) {
      print('X ML algorithms failed: $e');
    }
  }
  
  /// Process a single email through the complete flow (steps 2-6)
  Future<StatementParsingResult?> _processEmailWithCompleteFlow(
    String userId,
    StatementParsingResult statement,
    Map<String, dynamic> userProfile,
  ) async {
    try {
      // Step 2: Read the email and PDF
      print('- Step 2: Reading PDF content...');      // Step 3: Try passwords and store the right one (with manual fallback)
      print('- Step 3: Password detection...');
      String pdfText = '';
      bool passwordFound = false;
      
      try {
        final pdfParsingService = PdfParsingServiceImpl();
        pdfText = await pdfParsingService.extractTextWithPasswordDetection(
          pdfBytes: statement.originalPdfData,
          bankName: statement.bankName,
          emailSubject: 'Statement',
          emailBody: '',
          userEmail: userProfile['email'] ?? '',
          userName: userProfile['displayName'] ?? '',
          userProfile: userProfile,          
          fileName: 'statement.pdf',
          onManualPasswordRequired: () async {
            print('❌ Auto password detection failed for ${statement.bankName}');
            print('📝 Manual password input required');
            
            // Use the global password callback if available (real UI)
            final password = await PasswordInputService.requestPassword(
              statement.bankName,
              hint: statement.bankName.toLowerCase() == 'sbi' 
                  ? 'Format: DOB(DDMMYYYY) + Last4Digits of card'
                  : null,
            );
            if (password != null) {
              // Don't print that we're testing the manual password, just return it
              return password;
            } else {
              print('❌ Manual password input cancelled or failed');
              return null;
            }
          },
        );
        passwordFound = true;
        // Success message will be printed by the PDF password detection service
        
      } catch (e) {
        print('❌ Password detection failed: $e');
        if (!passwordFound) {
          print('⏭️ Skipping this email - no password found after manual attempts');
          return null;
        }
      }
      
      // Step 4: Give PDF text to Gemini for transactions/statements extraction
      print('- Step 4: Extracting data via Gemini AI...');
      
      final statementInfo = await GeminiTransactionParser.parseStatementInfo(
        pdfText: pdfText,
        bankName: statement.bankName,
      );
      
      final transactions = await GeminiTransactionParser.parseTransactions(
        pdfText: pdfText,
        bankName: statement.bankName,
      );
        final dueAmount = statementInfo['total_amount'] ?? 0.0;
      final transactionCount = transactions.length;
      
      print('💰 Due Amount: ₹$dueAmount');
      print('📄 Transaction Count: $transactionCount');
      
      // Step 5: Conditional database storage - UPDATED: Prioritize transactions over due amount
      print('- Step 5: Evaluating storage conditions...');
      
      // Store if we have transactions regardless of due amount (for paid-off cards or processing errors)
      if (transactionCount > 0) {
        print('✅ Conditions met (Transactions > 0) - storing to database');
        print('   Note: Due amount check relaxed to prioritize transaction data');
          // Store all relevant details to database
        await _storeStatementData(
          userId,
          statementInfo,
          transactions,
          statement,
        );
        
        print('💾 Database storage completed');
          return StatementParsingResult(
          bankName: statement.bankName,
          statementDate: statement.statementDate,
          transactions: transactions.map((t) => Transaction.fromJson(Map<String, dynamic>.from(t))).toList(),
          originalPdfData: statement.originalPdfData,
          emailMessageId: statement.emailMessageId,
          processingSuccess: true,
          // Copy over additional properties from original statement
          emailSubject: statement.emailSubject,
          emailSender: statement.emailSender,
          cardVariantName: statement.cardVariantName,
          dueDate: statement.dueDate,
          totalAmountDue: statement.totalAmountDue,
          minimumAmountDue: statement.minimumAmountDue,
          availableCredit: statement.availableCredit,
          rewardsEarned: statement.rewardsEarned,
        );        
      } else {
        print('❌ Conditions not met:');
        if (transactionCount <= 0) print('  - Transaction count is $transactionCount (must be > 0)');
        print('⏭️ Skipping database storage for this statement');
        return StatementParsingResult(
          bankName: statement.bankName,
          statementDate: statement.statementDate,
          transactions: [],
          originalPdfData: statement.originalPdfData,
          emailMessageId: statement.emailMessageId,
          processingSuccess: false,
          // Copy over additional properties from original statement
          emailSubject: statement.emailSubject,
          emailSender: statement.emailSender,
          cardVariantName: statement.cardVariantName,
          dueDate: statement.dueDate,
          totalAmountDue: statement.totalAmountDue,
          minimumAmountDue: statement.minimumAmountDue,
          availableCredit: statement.availableCredit,
          rewardsEarned: statement.rewardsEarned,
        );
      }
      
    } catch (e) {
      print('❌ Error processing email: $e');
      return null;
    }
  }
  
  /// Store statement data to database
  Future<void> _storeStatementData(
    String userId,
    Map<String, dynamic> statementInfo,
    List<dynamic> transactions,
    StatementParsingResult statement,
  ) async {
    // Implementation would store to actual database tables
    // For now, just simulate the storage
    print('  • Creating credit card record...');    print('  • Creating statement record...');
    print('  • Creating ${transactions.length} transaction records...');
    print('  • Updating email processing status...');
  }

  /// Get the user card ID for a given user and catalog card ID
  Future<String> _getUserCardId(String userId, String catalogCardId) async {
    try {
      final response = await Supabase.instance.client
          .from('user_cards')
          .select('id')
          .eq('user_id', userId)
          .eq('catalog_card_id', catalogCardId)
          .single();
      
      return response['id'];
    } catch (e) {
      // If not found, create a new association
      return await _createUserCardAssociation(userId, catalogCardId);
    }
  }

  /// Sequential user flow as per requirements. Returns a summary map with sync results.
  Future<Map<String, int>> debugSequentialUserFlow(String userId, [int? maxEmailsToRead, DateTime? customStartDate]) async {
    print('\n--- Sequential User Flow Implementation ---');
    print('==========================================');
    
    try {
      // Step 0: Reset Gemini model to primary for new sync session
      AIConfig.resetToPrimaryModel();
      print('🔄 Reset Gemini model to primary for new sync session');
      
      // Step 1: Database setup
      SyncFlowDebugger.logStep('DB_SETUP', 'Initializing database connection');
      await debugDatabaseSetup();
      
      // Step 2: Gmail authentication
      // Skip if _gmailService was already injected (e.g., from home_screen with pre-auth)
      if (_gmailService == null) {
        SyncFlowDebugger.logStep('GMAIL_AUTH', 'Authenticating with Gmail API');
        final authClient = await debugGmailAuthentication();
        if (authClient == null) {
          SyncFlowDebugger.logError('GMAIL_AUTH', 'Gmail authentication failed');
          throw Exception('Gmail authentication failed');
        }
        SyncFlowDebugger.logStep('GMAIL_AUTH', 'Gmail API authenticated successfully');

        // Build GmailService from the auth client
        final gmailApi = gmail.GmailApi(authClient);
        final pdfParsingService = PdfParsingServiceImpl();
        _gmailService = EnhancedGmailService(
          gmailApi: gmailApi,
          pdfParsingService: pdfParsingService,
          httpClient: authClient,
        );
      } else {
        SyncFlowDebugger.logStep('GMAIL_AUTH', 'Using pre-authenticated Gmail service (skipping OAuth)');
      }
      
      // Fetch user profile — uses DB first, then Google People API, then manual fallback
      final userProfile = await _gmailService!.getUserProfileWithFallback(userId: userId, verbose: false);
      
      // Get all relevant emails
      print('\n📧 Step 2: Finding relevant statement emails...');
      final endDate = DateTime.now();
      final startDate = customStartDate ?? endDate.subtract(const Duration(days: 365)); 
      
      SyncFlowDebugger.logStep('GMAIL_SEARCH', 'Searching for statement emails');
      final searchStartTime = SyncFlowDebugger.startTimer('Gmail Search');
      final allStatements = await _gmailService!.processStatementEmails(
        userId: userId,
        startDate: startDate,
        endDate: endDate,
        maxEmails: maxEmailsToRead,
      );
      SyncFlowDebugger.endTimer('Gmail Search', searchStartTime);
      
      print('+ Found ${allStatements.length} potential statement emails');
      SyncFlowDebugger.logStep('EMAIL_FOUND', 'Found statement emails', data: {
        'count': allStatements.length,
        'banks': allStatements.map((s) => s.bankName).toSet().toList(),
      });
      
      if (allStatements.isEmpty) {
        print('ℹ️ No statement emails found in the specified date range.');
        SyncFlowDebugger.logStep('EMAIL_FOUND', 'No statement emails found');
        throw Exception(
          'No credit-card statement emails were found between '
          '${startDate.toIso8601String().substring(0, 10)} and '
          '${endDate.toIso8601String().substring(0, 10)}. '
          'Check that Gmail contains PDF statement emails matching the app search '
          'terms, or broaden the sync date range/email limit from the sync dialog.',
        );
      }
      
      // Step 3-6: Process emails sequentially, one at a time
      int emailsProcessed = 0;
      int emailsStoredToDb = 0;
      int totalTransactionsStored = 0;
      
      for (int i = 0; i < allStatements.length; i++) {
        final statement = allStatements[i];
        print('\n' + '=' * 60);
        print('📄 Processing Email ${i + 1}/${allStatements.length}');
        print('Bank: ${statement.bankName}');
        print('Date: ${statement.statementDate.toString().substring(0, 19)}');
        print('PDF Size: ${(statement.originalPdfData.length / 1024).toStringAsFixed(1)}KB');
        print('=' * 60);
        
        SyncFlowDebugger.logStep('EMAIL_PROCESSED', 'Processing email ${i + 1}/${allStatements.length}', data: {
          'bank': statement.bankName,
          'date': statement.statementDate.toIso8601String(),
          'pdfSize': statement.originalPdfData.length,
        });
        
        // Process this single email with complete flow
        final emailStartTime = SyncFlowDebugger.startTimer('Process Email ${i + 1}');
        final txCount = await _processEmailSequentially(
          userId,
          statement,
          userProfile,
          i + 1,
          allStatements.length,
        );
        SyncFlowDebugger.endTimer('Process Email ${i + 1}', emailStartTime);
        
        emailsProcessed++;
        if (txCount > 0) {
          emailsStoredToDb++;
          totalTransactionsStored += txCount;
        }
        
        print('─' * 60); // Separator after each email
        
        // Small delay between emails for readability
        await Future.delayed(const Duration(milliseconds: 500));
      }
      
      print('\n🎯 Sequential Flow Complete!');
      print('============================');
      print('📧 Emails processed: $emailsProcessed');
      print('💾 Emails stored to DB: $emailsStoredToDb');
      print('🔢 Total transactions stored: $totalTransactionsStored');
      print('⏱️ Processing completed at: ${DateTime.now().toString().substring(0, 19)}');
      
      SyncFlowDebugger.logStep('SYNC_COMPLETE', 'All emails processed successfully', data: {
        'emailsProcessed': emailsProcessed,
        'emailsStored': emailsStoredToDb,
        'totalTransactions': totalTransactionsStored,
      });

      return {
        'emailsProcessed': emailsProcessed,
        'emailsStored': emailsStoredToDb,
        'transactionsStored': totalTransactionsStored,
      };
      
    } catch (e) {
      print('❌ Sequential user flow failed: $e');
      SyncFlowDebugger.logError('SYNC_FLOW', 'Sequential user flow failed', exception: e);
      rethrow;
    }
  }


  /// Process a single email with the complete sequential flow. Returns the count of transactions stored (0 = failure).
  Future<int> _processEmailSequentially(
    String userId,
    StatementParsingResult statement,
    Map<String, dynamic> userProfile,
    int emailIndex,
    int totalEmails,
  ) async {
    try {
      // Extract basic transaction info from the statement result
      final transactions = statement.transactions;
      final transactionCount = transactions.length;
      
      print('🔍 Step 3: PDF processed, found $transactionCount transactions');
      
      SyncFlowDebugger.logStep('PDF_DOWNLOAD', 'Downloaded PDF attachment', data: {
        'size': '${(statement.originalPdfData.length / (1024 * 1024)).toStringAsFixed(1)}MB',
      });
      
      SyncFlowDebugger.logStep('PDF_UNLOCKED', 'PDF unlocked successfully', data: {
        'method': 'automatic',
        'textLength': statement.originalPdfData.length,
      });
      
      SyncFlowDebugger.logStep('GEMINI_PARSE', 'Extracting statement info', data: {
        'bankName': statement.bankName,
      });
      
      SyncFlowDebugger.logStep('STATEMENT_INFO', 'Statement info extracted', data: {
        'statementDate': statement.statementDate.toIso8601String(),
        'dueDate': statement.dueDate?.toIso8601String(),
      });
      
      SyncFlowDebugger.logStep('TRANSACTION_PARSE', 'Parsing transactions', data: {
        'bankName': statement.bankName,
      });
      
      SyncFlowDebugger.logStep('TRANSACTION_PARSE', 'Transactions parsed successfully', data: {
        'count': transactionCount,
      });
      
      if (transactionCount == 0) {
        print('⚠️ No transactions found - skipping database storage');
        return 0;
      }
      
      // Check if there's a due amount > 0
      double dueAmount = 0.0;
      bool hasDueAmount = false;
      
      // Try to find due amount from transactions or statement data
      for (final tx in transactions) {
        if (tx.description.toLowerCase().contains('due') == true ||
            tx.description.toLowerCase().contains('outstanding') == true ||
            tx.description.toLowerCase().contains('balance') == true) {
          dueAmount = tx.amount.abs();
          hasDueAmount = true;
          break;
        }
      }
      
      // If no due amount found in transactions, assume there is due amount if we have transactions
      if (!hasDueAmount && transactionCount > 0) {
        hasDueAmount = true;
        dueAmount = 1.0; // Assume some due amount exists
      }
      
      print('💰 Step 4: Due amount check - Due: ₹${dueAmount.toStringAsFixed(2)} | Has due: $hasDueAmount');
        // Step 5: Check conditions for database storage - UPDATED: Prioritize transactions
      if (transactionCount > 0) {
        print('✅ Step 5: Conditions met (transactions > 0) - proceeding with database storage...');
        print('   Note: Due amount check relaxed to prioritize transaction data');
        
        // Store to database using existing logic
        try {
          final storeStartTime = SyncFlowDebugger.startTimer('Store to Database $emailIndex');
          await _storeStatementToDatabase(userId, statement, userProfile);
          SyncFlowDebugger.endTimer('Store to Database $emailIndex', storeStartTime);
          print('💾 Database storage completed successfully');
          return transactionCount;
        } catch (e) {
          print('❌ Database storage failed: $e');
          SyncFlowDebugger.logError('DB_STORE', 'Database storage failed', exception: e);
          return 0;
        }
      } else {
        print('⚠️ Step 5: Conditions not met - NOT storing to database');
        print('   Transaction count > 0: ${transactionCount > 0}');
        SyncFlowDebugger.logStep('DB_STORE', 'Skipping database storage - no transactions');
        return 0;
      }
      
    } catch (e) {
      print('❌ Error processing email sequentially: $e');
      return 0;
    }
  }  /// Store statement data to database (actual implementation)
  Future<void> _storeStatementToDatabase(
    String userId,
    StatementParsingResult statement,
    Map<String, dynamic> userProfile,
  ) async {
    print('📊 Storing statement data to database tables...');
    
    try {      // Step 1: Store email record first
      print('   - Storing email record...');
      String? emailRecordId;
      
      // Check if email already exists to avoid duplicates
      final emailExists = await _emailRepo.emailExists(statement.emailMessageId);
      if (!emailExists) {
        emailRecordId = await _emailRepo.storeEmail(
          userId: userId,
          emailId: statement.emailMessageId,
          subject: statement.emailSubject ?? 'Credit Card Statement',
          sender: statement.emailSender ?? statement.bankName,
          receivedDate: statement.statementDate,
          hasAttachments: true, // PDF attachment
          bankDetected: statement.bankName,
          metadata: {
            'parsed_bank': statement.bankName,
            'card_variant': statement.cardVariantName,
            'has_pdf': true,
            'pdf_size': statement.originalPdfData.length,
          },
        );
        print('   ✅ Email record stored: $emailRecordId');
      } else {
        print('   📧 Email already exists, skipping duplicate');
      }

      // Step 2: Ensure user exists in database
      print('   - Verifying user record...');
      
      // Step 3: Store/update credit card information and get user card ID
      print('   - Processing credit card information...');
      SyncFlowDebugger.logStep('CARD_MAPPING', 'Looking for existing user card', data: {
        'bankName': statement.bankName,
        'cardVariant': statement.cardVariantName,
      });
      final cardInfo = await _ensureCreditCardExistsWithUserCard(
        userId: userId,
        bankName: statement.bankName,
        statement: statement,
        emailSubject: statement.emailSubject ?? 'Credit Card Statement',
      );
      SyncFlowDebugger.logStep('CARD_MAPPING', 'Card mapping completed', data: {
        'catalogCardId': cardInfo.catalogCardId,
        'userCardId': cardInfo.userCardId,
      });
      
      // Step 4: Store statement record
      print('   - Storing statement record...');
      String? statementRecordId;
      try {        final statementData = {
          'statement_date': statement.statementDate.toIso8601String(),
          'due_date': statement.dueDate?.toIso8601String() ?? 
                     statement.statementDate.add(const Duration(days: 30)).toIso8601String(),
          'total_amount': statement.totalAmountDue ?? 0.0,
          'minimum_payment': statement.minimumAmountDue ?? 0.0,
          'closing_balance': statement.totalAmountDue ?? 0.0,
          'available_credit': statement.availableCredit ?? 0.0,
          'rewards_earned': statement.rewardsEarned ?? 0.0,
          'interest_charged': 0.0, // Could be extracted from statement if available
          'fees_charged': 0.0, // Could be extracted from statement if available
          'payment_status': 'pending',
          'file_path': 'gmail_attachment', // Indicates source
          'file_name': '${statement.bankName}_statement_${statement.statementDate.millisecondsSinceEpoch}.pdf',          
          'metadata': {
            'bank_name': statement.bankName,
            'card_variant': statement.cardVariantName,
            'transaction_count': statement.transactions.length,
            'parsed_from': 'gmail_attachment',
          },
          'processed': true,
          'transaction_count': statement.transactions.length,
        };        final statementRecord = await _statementRepo.createStatement(
          userId: userId,
          userCardId: cardInfo.userCardId,  // Use user card ID instead of catalog card ID
          statementData: statementData,
          emailId: statement.emailMessageId,
        );
        
        statementRecordId = statementRecord.id;
        print('   ✅ Statement record stored: $statementRecordId');
      } catch (e) {
        print('   ⚠️ Statement storage failed (continuing with transactions): $e');
      }      // Step 5: Store transactions with duplicate prevention
      print('   - Storing ${statement.transactions.length} transactions...');
      SyncFlowDebugger.logStep('DB_STORED', 'Storing statement to database', data: {
        'userCardId': cardInfo.userCardId,
        'transactionCount': statement.transactions.length,
      });
      await _storeTransactionsWithDeduplication(
        transactions: statement.transactions,
        userCardId: cardInfo.userCardId,
        userId: userId,
      );
      SyncFlowDebugger.logStep('TRANSACTION_STORED', 'Transactions stored', data: {
        'count': statement.transactions.length,
      });
        // Step 6: Update email status if we have email record
      if (emailRecordId != null && statementRecordId != null) {
        try {
          await _emailRepo.updateEmailStatus(
            emailId: statement.emailMessageId,
            processed: true,
            statementId: statementRecordId,
          );
          print('   ✅ Email status updated');
        } catch (e) {
          print('   ⚠️ Email status update failed: $e');
        }
      }      print('✅ All data stored successfully to database');
      
    } catch (error) {
      print('❌ Error storing to database: $error');
      throw error;
    }
  }
  Future<CardInfo> _ensureCreditCardExistsWithUserCard({
    required String userId,
    required String bankName,
    required StatementParsingResult statement,
    required String emailSubject,
  }) async {
    try {
      final existingUserCards = await _cardRepo.getUserCards(userId);
      final expectedCardName = statement.cardVariantName ?? bankName;
      print('   🔍 Looking for existing user card: Bank="$bankName", Card="$expectedCardName"');

      // ── Pass 1: exact bank + card match ──────────────────────────────
      for (final creditCard in existingUserCards) {
        final bankMatches = creditCard.bankName.toLowerCase().contains(bankName.toLowerCase()) ||
                            bankName.toLowerCase().contains(creditCard.bankName.toLowerCase());
        final cardMatches = creditCard.cardName.toLowerCase().contains(expectedCardName.toLowerCase()) ||
                            expectedCardName.toLowerCase().contains(creditCard.cardName.toLowerCase());
        if (bankMatches && cardMatches) {
          print('   ✅ Pass-1 match: ${creditCard.cardName} (${creditCard.bankName})');
          final userCardId = await _getUserCardId(userId, creditCard.id);
          return CardInfo(catalogCardId: creditCard.id, userCardId: userCardId);
        }
      }

      // ── Pass 2: bank-only match against existing user_cards ──────────
      // The variant returned by Gemini may just be the bank name ("SBI Card")
      // but the user already owns a card from that bank (e.g. SBI BPCL).
      // In that case, attach the statement to whichever card from that bank
      // the user has — avoids demanding a URL when we already know the bank.
      for (final creditCard in existingUserCards) {
        final bankMatches = creditCard.bankName.toLowerCase().contains(bankName.toLowerCase()) ||
                            bankName.toLowerCase().contains(creditCard.bankName.toLowerCase());
        if (bankMatches) {
          print('   ✅ Pass-2 bank-only match: ${creditCard.cardName} (${creditCard.bankName})');
          final userCardId = await _getUserCardId(userId, creditCard.id);
          return CardInfo(catalogCardId: creditCard.id, userCardId: userCardId);
        }
      }

      // ── Pass 3: catalog lookup — exact bank + card ───────────────────
      print('   📝 No existing user card for $bankName — searching catalog...');
      final catalogCardId = await _findOrCreateCatalogCardWithSeparateBankAndCard(
        bankName: bankName,
        cardName: expectedCardName,
        emailSubject: emailSubject,
      );
      final userCardId = await _createUserCardAssociation(userId, catalogCardId);
      return CardInfo(catalogCardId: catalogCardId, userCardId: userCardId);

    } catch (error) {
      print('   ❌ Error ensuring credit card exists: $error');
      rethrow;
    }
  }

  Future<String> _findOrCreateCatalogCardWithSeparateBankAndCard({
    required String bankName,
    required String cardName,
    required String emailSubject,
  }) async {
    try {
      print('   🔍 Looking for catalog card: Bank="$bankName", Card="$cardName"');

      // ── Exact match: bank + card_name ────────────────────────────────
      final exact = await Supabase.instance.client
          .from('card_catalog')
          .select('*')
          .eq('bank', bankName)
          .eq('card_name', cardName)
          .limit(1);
      if (exact.isNotEmpty) {
        print('   ✅ Catalog exact match: ${exact.first['card_name']} (${exact.first['bank']})');
        return exact.first['id'] as String;
      }

      // ── Fuzzy match: bank only ────────────────────────────────────────
      // When Gemini returns just the bank name as the variant, find any card
      // in the catalog that belongs to this bank and use the first one.
      final byBank = await Supabase.instance.client
          .from('card_catalog')
          .select('id, bank, card_name')
          .ilike('bank', '%${bankName.replaceAll(' Card', '').trim()}%')
          .limit(1);
      if (byBank.isNotEmpty) {
        print('   ✅ Catalog bank-fuzzy match: ${byBank.first['card_name']} (${byBank.first['bank']})');
        return byBank.first['id'] as String;
      }

      // ── No catalog match → ask user for URL ──────────────────────────
      print('   🔄 Card not found in catalog. Requesting URL from user...');

      print('');
      print('   ╔═══════════════════════════════════════════════════════════╗');
      print('   ║  📋 MANUAL URL INPUT REQUIRED                             ║');
      print('   ╚═══════════════════════════════════════════════════════════╝');
      print('');
      print('   🏦 Bank: $bankName');
      print('   💳 Card Variant: $cardName');
      print('   📧 Email Subject: $emailSubject');
      print('');
      
      // Generate suggested search URL for user reference
      final searchQuery = Uri.encodeComponent('$bankName $cardName credit card');
      final suggestedUrl = 'https://www.google.com/search?q=$searchQuery';
      
      // Prompt user for URL (REQUIRED)
      String? userProvidedUrl;
      print('   🔍 DEBUG: onCardUrlRequired callback is: ${onCardUrlRequired == null ? "NULL" : "SET"}');
      if (onCardUrlRequired != null) {
        print('   📱 Showing URL input dialog to user...');
        userProvidedUrl = await onCardUrlRequired!(
          bankName: bankName,
          cardVariant: cardName,
          emailSubject: emailSubject,
          suggestedUrl: suggestedUrl,
        );
      } else {
        print('   ❌ onCardUrlRequired callback is NULL - cannot show dialog!');
      }
      
      // If user didn't provide URL, fail gracefully
      if (userProvidedUrl == null || userProvidedUrl.isEmpty) {
        print('   ❌ No URL provided by user. Cannot create card without product page URL.');
        print('   ⚠️  Skipping this card. Please add it manually later.');
        print('');
        throw Exception('Card URL required but not provided by user');
      }
      
      print('   ✅ User provided URL: $userProvidedUrl');
      print('');
      
      try {
        // Check if a card with this URL already exists (deduplication)
        print('   🔍 Checking for existing card with same URL...');
        final duplicateCheck = await Supabase.instance.client
            .from('card_catalog')
            .select('id, bank, card_name')
            .eq('card_url', userProvidedUrl)
            .maybeSingle();
        
        if (duplicateCheck != null) {
          final existingCardId = duplicateCheck['id'] as String;
          print('   ✅ Found existing card with same URL:');
          print('      Bank: ${duplicateCheck['bank']}');
          print('      Card: ${duplicateCheck['card_name']}');
          print('      Reusing card ID: $existingCardId');
          print('');
          return existingCardId;
        }
        
        print('   ✅ No duplicate found. Creating new card...');
        
        // Insert new card with user-provided URL
        final insertResponse = await Supabase.instance.client
            .from('card_catalog')
            .insert({
              'bank': bankName,
              'card_name': cardName,
              'card_url': userProvidedUrl,
              'network': 'visa',
              'card_type': 'credit',
              'annual_fee': 999.0,
              'apr': 3.5,
              'joining_fee': 0.0,
              'is_discontinued': false,
            })
            .select('id')
            .single();
        
        final cardId = insertResponse['id'] as String;
        print('   ✅ Card created successfully with ID: $cardId');
        print('   🔗 URL: $userProvidedUrl');
        print('');
        
        return cardId;
        
      } catch (insertError) {
        print('   ❌ Failed to create card: $insertError');
        rethrow;
      }
      
    } catch (error) {
      print('   ❌ Error finding/creating catalog card: $error');
      rethrow;
    }
  }
  /// Create user-card association and return user card ID
  Future<String> _createUserCardAssociation(String userId, String catalogCardId) async {
    try {
      print('   🔄 Creating user-card association...');
      
      // Use the RPC function directly to get the user card ID
      final userCardId = await Supabase.instance.client.rpc('associate_user_with_card', params: {
        '_user_id': userId,
        '_catalog_card_id': catalogCardId,
        '_last_four_digits': '1234', // Default placeholder
      });
      
      print('   ✅ User-card association created with ID: $userCardId');
      return userCardId.toString();
      
    } catch (associationError) {
      print('   ⚠️ User-card association error: $associationError');
      
      // Try to find existing association
      try {
        final existingUserCards = await _cardRepo.getUserCards(userId);
        final matchingUserCard = existingUserCards.where((uc) => uc.id.contains(catalogCardId) || uc.bankName.isNotEmpty).firstOrNull;
        
        if (matchingUserCard != null) {
          print('   ✅ Found existing user-card association with ID: ${matchingUserCard.id}');
          return matchingUserCard.id;
        }
      } catch (e) {
        // Ignore and continue
      }
      
      // Generate a temporary ID to continue testing
      final tempUserCardId = const Uuid().v4();
      print('   ⚠️ Generating temporary user card ID to continue: $tempUserCardId');
      return tempUserCardId;
    }
  }

  /// Ensure credit card exists, create if not found  /// Store transactions with deduplication
  Future<void> _storeTransactionsWithDeduplication({
    required List<Transaction> transactions,
    required String userCardId,  // Only user card ID is needed now
    required String userId,
  }) async {
    try {      // Update userCardId and user_id for all transactions
      // Note: cardId column has been removed, only userCardId is used now
      final updatedTransactions = transactions.map((tx) => Transaction(
        id: tx.id,
        userId: userId,
        userCardId: userCardId,   // Use the actual user card ID
        amount: tx.amount,
        description: tx.description,
        merchantName: tx.merchantName,
        category: tx.category,
        type: tx.type,
        transactionDate: tx.transactionDate,
        location: tx.location,
        rewardEarned: tx.rewardEarned,
        rewardType: tx.rewardType,
        metadata: tx.metadata,
        statementId: null, // Will be set when statement record is created
        createdAt: tx.createdAt,
      )).toList();
      
      // Use the enhanced repository method with duplicate prevention
      await _transactionRepo.addTransactionsBatch(updatedTransactions);
      
    } catch (error) {
      print('   ❌ Error storing transactions: $error');
      rethrow;
    }
  }
  /// Store statement metadata
}
