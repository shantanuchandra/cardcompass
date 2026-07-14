import 'package:flutter/foundation.dart';
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
import 'package:cardcompass/core/repositories/card_repository.dart';
import 'package:cardcompass/core/repositories/supabase_card_repository.dart';
import 'package:cardcompass/core/repositories/supabase_statement_repository.dart';
import 'package:cardcompass/core/repositories/email_repository.dart';
import 'package:cardcompass/core/repositories/email_repository_interface.dart';
import 'package:cardcompass/shared/models/credit_card.dart';
import 'package:cardcompass/shared/models/statement_sync_failure.dart';
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

/// Result of matching a statement to an existing user card, identifying which
/// pass produced the match (for logging/testing).
class CardMatchResult {
  final String catalogCardId;
  final String userCardId;
  final String matchPass;

  CardMatchResult({
    required this.catalogCardId,
    required this.userCardId,
    required this.matchPass,
  });
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
  DataPipelineDebugService({
    CardRepository? cardRepo,
    EmailRepositoryInterface? emailRepo,
    Future<String> Function({
      required String userId,
      required String catalogCardId,
    })? associateUserWithCard,
    Future<String> Function({
      required String userId,
      required String bankName,
      required String cardName,
      required String emailSubject,
      required String pdfName,
    })? findOrCreateCatalogCard,
    Future<bool> Function({
      required String userId,
      required String bankName,
      required String cardName,
      required String cardUrl,
    })? submitCardCatalogRequest,
    Future<String?> Function({
      required String bankName,
      required String cardName,
      required String emailSubject,
      required String? cardUrl,
    })? lookupCatalogCard,
  })  : _cardRepo = cardRepo ?? SupabaseCardRepository(),
        _emailRepo = emailRepo,
        _associateUserWithCard =
            associateUserWithCard ?? _defaultAssociateUserWithCard,
        _findOrCreateCatalogCard = findOrCreateCatalogCard,
        _submitCardCatalogRequest =
            submitCardCatalogRequest ?? _defaultSubmitCardCatalogRequest,
        _lookupCatalogCard = lookupCatalogCard ?? _defaultLookupCatalogCard;

  // Lazily constructed: each of these touches `Supabase.instance.client` in
  // its own field initializer, which throws if Supabase hasn't been
  // initialized (e.g. in unit tests that only exercise the card-association
  // path and never need these).
  late final SimpleSupabaseSchemaService _schemaService =
      SimpleSupabaseSchemaService();
  EnhancedGmailService? _gmailService;
  late final SupabaseTransactionRepository _transactionRepo =
      SupabaseTransactionRepository();
  final CardRepository _cardRepo;
  late final SupabaseStatementRepository _statementRepo =
      SupabaseStatementRepository();

  /// Test seam: when null (the production default), [_emailRepoOrDefault]
  /// lazily creates the real Supabase-backed [EmailRepository].
  final EmailRepositoryInterface? _emailRepo;
  late final EmailRepositoryInterface _emailRepoOrDefault =
      _emailRepo ?? EmailRepository();
  final Future<String> Function({
    required String userId,
    required String catalogCardId,
  }) _associateUserWithCard;

  /// Overrides [_findOrCreateCatalogCardWithSeparateBankAndCard] when set
  /// (test seam) — production code leaves this null and uses the real
  /// Supabase-backed lookup.
  final Future<String> Function({
    required String userId,
    required String bankName,
    required String cardName,
    required String emailSubject,
    required String pdfName,
  })? _findOrCreateCatalogCard;

  final Future<bool> Function({
    required String userId,
    required String bankName,
    required String cardName,
    required String cardUrl,
  }) _submitCardCatalogRequest;

  /// Overrides the exact/fuzzy/duplicate-URL catalog lookup queries (test
  /// seam) — production code leaves this null and hits Supabase directly.
  final Future<String?> Function({
    required String bankName,
    required String cardName,
    required String emailSubject,
    required String? cardUrl,
  }) _lookupCatalogCard;

  static Future<String> _defaultAssociateUserWithCard({
    required String userId,
    required String catalogCardId,
  }) async {
    final userCardId =
        await Supabase.instance.client.rpc('associate_user_with_card', params: {
      '_user_id': userId,
      '_catalog_card_id': catalogCardId,
      '_last_four_digits': '1234', // Default placeholder
    });
    return userCardId.toString();
  }

  /// Queues a new-card request for admin review via the
  /// `request-card-catalog-entry` edge function (which validates input and
  /// calls `submit_card_catalog_request` with the service-role key —
  /// `card_catalog`/`card_benefits_staging` writes are not reachable
  /// directly by authenticated clients). Returns whether the request was
  /// accepted (queued or already pending) — the card itself won't exist in
  /// `card_catalog` until an admin approves it.
  static Future<bool> _defaultSubmitCardCatalogRequest({
    required String userId,
    required String bankName,
    required String cardName,
    required String cardUrl,
  }) async {
    final response = await Supabase.instance.client.functions.invoke(
      'request-card-catalog-entry',
      body: {
        'bank_name': bankName,
        'card_name': cardName,
        'card_url': cardUrl,
      },
    );
    return response.data is Map && response.data['success'] == true;
  }

  /// Callback to prompt user for card URL input
  /// Returns the URL provided by the user, or null if skipped
  Future<String?> Function({
    required String bankName,
    required String cardVariant,
    required String emailSubject,
    required String pdfName,
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
    await Future.delayed(
        const Duration(seconds: 1)); // Simulate database operation
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

  Future<List<StatementParsingResult>> debugEmailReading(
      String userId, AuthClient authClient) async {
    print('\nStep 3: Sequential Email Processing');
    print('----------------------------------');

    try {
      // Ensure Gmail service is initialized
      if (_gmailService == null) {
        final gmailApi = gmail.GmailApi(authClient);
        final pdfParsingService = PdfParsingServiceImpl();
        _gmailService = EnhancedGmailService(
          gmailApi: gmailApi,
          pdfParsingService: pdfParsingService,
          httpClient: authClient,
        );
      }

      // Step 1: DOB storage via Gmail API
      print('- Step 1: Fetching and storing DOB via Gmail API...');
      final userProfile =
          await _gmailService!.getUserProfile(userId: userId, verbose: false);
      if (userProfile.containsKey('birthday')) {
        print(
            '+ DOB stored: ${userProfile['birthday']['ddmm']} format available');
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
      print(
          '- Parsing already done. Transactions count: ${transactions.length}');
      if (transactions.isNotEmpty) {
        final tx = transactions.first;
        print(
            '  Sample: Date=${tx.transactionDate}, Desc=${tx.description}, Amount=Rs.${tx.amount}');
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
      final userTransactions =
          await _transactionRepo.getUserTransactions(userId, limit: 10);
      print(
          '+ Retrieved ${userCards.length} cards and ${userTransactions.length} transactions');
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
      print(
          '- Running ML analysis placeholder (integrate your ML services here)');
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
      print(
          '- Step 2: Reading PDF content...'); // Step 3: Try passwords and store the right one (with manual fallback)
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
          print(
              '⏭️ Skipping this email - no password found after manual attempts');
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
        print(
            '   Note: Due amount check relaxed to prioritize transaction data');
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
          transactions: transactions
              .map((t) => Transaction.fromJson(Map<String, dynamic>.from(t)))
              .toList(),
          originalPdfData: statement.originalPdfData,
          emailMessageId: statement.emailMessageId,
          processingSuccess: true,
          // Copy over additional properties from original statement
          emailSubject: statement.emailSubject,
          emailSender: statement.emailSender,
          attachmentName: statement.attachmentName,
          cardVariantName: statement.cardVariantName,
          dueDate: statement.dueDate,
          totalAmountDue: statement.totalAmountDue,
          minimumAmountDue: statement.minimumAmountDue,
          availableCredit: statement.availableCredit,
          rewardsEarned: statement.rewardsEarned,
        );
      } else {
        print('❌ Conditions not met:');
        if (transactionCount <= 0)
          print('  - Transaction count is $transactionCount (must be > 0)');
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
          attachmentName: statement.attachmentName,
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
    print('  • Creating credit card record...');
    print('  • Creating statement record...');
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

  /// Sequential user flow as per requirements. Returns a summary map with
  /// sync results — `emailsProcessed`, `emailsStored`, and
  /// `transactionsStored` are ints; `failures` is a `List<StatementSyncFailure>`
  /// of statements whose transactions could not be saved.
  Future<Map<String, dynamic>> debugSequentialUserFlow(String userId,
      [int? maxEmailsToRead, DateTime? customStartDate]) async {
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
          SyncFlowDebugger.logError(
              'GMAIL_AUTH', 'Gmail authentication failed');
          throw Exception('Gmail authentication failed');
        }
        SyncFlowDebugger.logStep(
            'GMAIL_AUTH', 'Gmail API authenticated successfully');

        // Build GmailService from the auth client
        final gmailApi = gmail.GmailApi(authClient);
        final pdfParsingService = PdfParsingServiceImpl();
        _gmailService = EnhancedGmailService(
          gmailApi: gmailApi,
          pdfParsingService: pdfParsingService,
          httpClient: authClient,
        );
      } else {
        SyncFlowDebugger.logStep('GMAIL_AUTH',
            'Using pre-authenticated Gmail service (skipping OAuth)');
      }

      // Fetch user profile — uses DB first, then Google People API, then manual fallback
      final userProfile = await _gmailService!
          .getUserProfileWithFallback(userId: userId, verbose: false);

      // Get all relevant emails
      print('\n📧 Step 2: Finding relevant statement emails...');
      final endDate = DateTime.now();
      final startDate =
          customStartDate ?? endDate.subtract(const Duration(days: 365));

      SyncFlowDebugger.logStep(
          'GMAIL_SEARCH', 'Searching for statement emails');
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
      final failures = <StatementSyncFailure>[];

      for (int i = 0; i < allStatements.length; i++) {
        final statement = allStatements[i];
        print('\n' + '=' * 60);
        print('📄 Processing Email ${i + 1}/${allStatements.length}');
        print('Bank: ${statement.bankName}');
        print('Date: ${statement.statementDate.toString().substring(0, 19)}');
        print(
            'PDF Size: ${(statement.originalPdfData.length / 1024).toStringAsFixed(1)}KB');
        print('=' * 60);

        SyncFlowDebugger.logStep('EMAIL_PROCESSED',
            'Processing email ${i + 1}/${allStatements.length}',
            data: {
              'bank': statement.bankName,
              'date': statement.statementDate.toIso8601String(),
              'pdfSize': statement.originalPdfData.length,
            });

        // Process this single email with complete flow
        final emailStartTime =
            SyncFlowDebugger.startTimer('Process Email ${i + 1}');
        final result = await _processEmailSequentially(
          userId,
          statement,
          userProfile,
          i + 1,
          allStatements.length,
        );
        SyncFlowDebugger.endTimer('Process Email ${i + 1}', emailStartTime);

        emailsProcessed++;
        if (result.transactionCount > 0) {
          emailsStoredToDb++;
          totalTransactionsStored += result.transactionCount;
        }
        if (result.failure != null) {
          failures.add(result.failure!);
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
      print(
          '⏱️ Processing completed at: ${DateTime.now().toString().substring(0, 19)}');

      SyncFlowDebugger.logStep(
          'SYNC_COMPLETE', 'All emails processed successfully',
          data: {
            'emailsProcessed': emailsProcessed,
            'emailsStored': emailsStoredToDb,
            'totalTransactions': totalTransactionsStored,
            'failures': failures.length,
          });

      return {
        'emailsProcessed': emailsProcessed,
        'emailsStored': emailsStoredToDb,
        'transactionsStored': totalTransactionsStored,
        'failures': failures,
      };
    } catch (e) {
      print('❌ Sequential user flow failed: $e');
      SyncFlowDebugger.logError('SYNC_FLOW', 'Sequential user flow failed',
          exception: e);
      rethrow;
    }
  }

  /// Test-only entry point for [_processEmailSequentially].
  @visibleForTesting
  Future<({int transactionCount, StatementSyncFailure? failure})>
      processEmailSequentially(
    String userId,
    StatementParsingResult statement,
    Map<String, dynamic> userProfile,
    int emailIndex,
    int totalEmails,
  ) =>
          _processEmailSequentially(
            userId,
            statement,
            userProfile,
            emailIndex,
            totalEmails,
          );

  /// Process a single email with the complete sequential flow. Returns the
  /// count of transactions stored, and — when transactions existed but
  /// storage failed — a [StatementSyncFailure] describing what was lost.
  Future<({int transactionCount, StatementSyncFailure? failure})>
      _processEmailSequentially(
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

      SyncFlowDebugger.logStep('PDF_DOWNLOAD', 'Downloaded PDF attachment',
          data: {
            'size':
                '${(statement.originalPdfData.length / (1024 * 1024)).toStringAsFixed(1)}MB',
          });

      SyncFlowDebugger.logStep('PDF_UNLOCKED', 'PDF unlocked successfully',
          data: {
            'method': 'automatic',
            'textLength': statement.originalPdfData.length,
          });

      SyncFlowDebugger.logStep('GEMINI_PARSE', 'Extracting statement info',
          data: {
            'bankName': statement.bankName,
          });

      SyncFlowDebugger.logStep('STATEMENT_INFO', 'Statement info extracted',
          data: {
            'statementDate': statement.statementDate.toIso8601String(),
            'dueDate': statement.dueDate?.toIso8601String(),
          });

      SyncFlowDebugger.logStep('TRANSACTION_PARSE', 'Parsing transactions',
          data: {
            'bankName': statement.bankName,
          });

      SyncFlowDebugger.logStep(
          'TRANSACTION_PARSE', 'Transactions parsed successfully',
          data: {
            'count': transactionCount,
          });

      if (transactionCount == 0) {
        print('⚠️ No transactions found - skipping database storage');
        return (transactionCount: 0, failure: null);
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

      print(
          '💰 Step 4: Due amount check - Due: ₹${dueAmount.toStringAsFixed(2)} | Has due: $hasDueAmount');
      // Step 5: Check conditions for database storage - UPDATED: Prioritize transactions
      if (transactionCount > 0) {
        print(
            '✅ Step 5: Conditions met (transactions > 0) - proceeding with database storage...');
        print(
            '   Note: Due amount check relaxed to prioritize transaction data');

        // Store to database using existing logic
        try {
          final storeStartTime =
              SyncFlowDebugger.startTimer('Store to Database $emailIndex');
          await _storeStatementToDatabase(userId, statement, userProfile);
          SyncFlowDebugger.endTimer(
              'Store to Database $emailIndex', storeStartTime);
          print('💾 Database storage completed successfully');
          return (transactionCount: transactionCount, failure: null);
        } catch (e) {
          print('❌ Database storage failed: $e');
          // A discovered email is not successfully processed until its
          // statement and transactions are durable. Keep it retryable when
          // card mapping, URL resolution, or persistence fails.
          try {
            await _emailRepoOrDefault.updateEmailStatus(
              userId: userId,
              emailId: statement.emailMessageId,
              processed: false,
            );
          } catch (_) {}
          SyncFlowDebugger.logError('DB_STORE', 'Database storage failed',
              exception: e);
          return (
            transactionCount: 0,
            failure: StatementSyncFailure(
              bankName: statement.bankName,
              statementDate: statement.statementDate,
              reason: e.toString(),
            ),
          );
        }
      } else {
        print('⚠️ Step 5: Conditions not met - NOT storing to database');
        print('   Transaction count > 0: ${transactionCount > 0}');
        SyncFlowDebugger.logStep(
            'DB_STORE', 'Skipping database storage - no transactions');
        return (transactionCount: 0, failure: null);
      }
    } catch (e) {
      print('❌ Error processing email sequentially: $e');
      return (
        transactionCount: 0,
        failure: StatementSyncFailure(
          bankName: statement.bankName,
          statementDate: statement.statementDate,
          reason: e.toString(),
        ),
      );
    }
  }

  /// Store statement data to database (actual implementation)
  Future<void> _storeStatementToDatabase(
    String userId,
    StatementParsingResult statement,
    Map<String, dynamic> userProfile,
  ) async {
    print('📊 Storing statement data to database tables...');

    try {
      // Step 1: Store email record first
      print('   - Storing email record...');
      String? emailRecordId;

      // Check if email already exists to avoid duplicates
      final emailExists = await _emailRepoOrDefault.emailExists(
        userId,
        statement.emailMessageId,
      );
      if (!emailExists) {
        emailRecordId = await _emailRepoOrDefault.storeEmail(
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
            'pdf_name': statement.attachmentName,
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
      SyncFlowDebugger.logStep('CARD_MAPPING', 'Looking for existing user card',
          data: {
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
      try {
        final statementData = {
          'statement_date': statement.statementDate.toIso8601String(),
          'due_date': statement.dueDate?.toIso8601String() ??
              statement.statementDate
                  .add(const Duration(days: 30))
                  .toIso8601String(),
          'total_amount': statement.totalAmountDue ?? 0.0,
          'minimum_payment': statement.minimumAmountDue ?? 0.0,
          'closing_balance': statement.totalAmountDue ?? 0.0,
          'available_credit': statement.availableCredit ?? 0.0,
          'rewards_earned': statement.rewardsEarned ?? 0.0,
          'interest_charged':
              0.0, // Could be extracted from statement if available
          'fees_charged': 0.0, // Could be extracted from statement if available
          'payment_status': 'pending',
          'file_path': 'gmail_attachment', // Indicates source
          'file_name': statement.attachmentName ??
              '${statement.bankName}_statement_${statement.statementDate.millisecondsSinceEpoch}.pdf',
          'metadata': {
            'bank_name': statement.bankName,
            'card_variant': statement.cardVariantName,
            'transaction_count': statement.transactions.length,
            'parsed_from': 'gmail_attachment',
          },
          'processed': true,
          'transaction_count': statement.transactions.length,
        };
        final statementRecord = await _statementRepo.createStatement(
          userId: userId,
          userCardId: cardInfo
              .userCardId, // Use user card ID instead of catalog card ID
          statementData: statementData,
          emailId: statement.emailMessageId,
        );

        statementRecordId = statementRecord.id;
        print('   ✅ Statement record stored: $statementRecordId');
      } catch (e) {
        print(
            '   ⚠️ Statement storage failed (continuing with transactions): $e');
      } // Step 5: Store transactions with duplicate prevention
      print('   - Storing ${statement.transactions.length} transactions...');
      SyncFlowDebugger.logStep('DB_STORED', 'Storing statement to database',
          data: {
            'userCardId': cardInfo.userCardId,
            'transactionCount': statement.transactions.length,
          });
      await _storeTransactionsWithDeduplication(
        transactions: statement.transactions,
        userCardId: cardInfo.userCardId,
        userId: userId,
        statementId: statementRecordId,
      );
      SyncFlowDebugger.logStep('TRANSACTION_STORED', 'Transactions stored',
          data: {
            'count': statement.transactions.length,
          });
      // Step 6: Update email status if we have email record — mark processed
      // regardless of whether statement storage succeeded, to prevent re-processing
      try {
        await _emailRepoOrDefault.updateEmailStatus(
          userId: userId,
          emailId: statement.emailMessageId,
          processed: true,
          statementId: statementRecordId,
        );
        print('   ✅ Email status updated');
      } catch (e) {
        print('   ⚠️ Email status update failed: $e');
      }
      print('✅ All data stored successfully to database');
    } catch (error) {
      print('❌ Error storing to database: $error');
      throw error;
    }
  }

  /// Finds an existing user card to attach a statement to, or `null` if none
  /// is a safe match (the caller should then fall through to catalog
  /// lookup/creation).
  ///
  /// Pass 1 matches on both bank and card name. Pass 2 is a same-bank
  /// fallback, but only when [expectedCardName] carries no real card-variant
  /// information beyond the bank name itself (Gemini/regex couldn't detect a
  /// specific variant) AND exactly one card from that bank exists — merging
  /// into "whichever card happens to be first" when a real, distinct variant
  /// name (e.g. "Diners Black") doesn't match any existing card would
  /// silently misattribute that statement's transactions to the wrong card.
  @visibleForTesting
  static CardMatchResult? findMatchingUserCard({
    required List<CreditCard> existingUserCards,
    required String bankName,
    required String expectedCardName,
  }) {
    bool bankMatches(CreditCard card) =>
        card.bankName.toLowerCase().contains(bankName.toLowerCase()) ||
        bankName.toLowerCase().contains(card.bankName.toLowerCase());

    // ── Pass 1: exact bank + card match ──────────────────────────────
    for (final creditCard in existingUserCards) {
      final cardMatches = creditCard.cardName
              .toLowerCase()
              .contains(expectedCardName.toLowerCase()) ||
          expectedCardName
              .toLowerCase()
              .contains(creditCard.cardName.toLowerCase());
      if (bankMatches(creditCard) && cardMatches) {
        return CardMatchResult(
          catalogCardId: creditCard.catalogCardId ?? '',
          userCardId: creditCard.id,
          matchPass: 'Pass-1 (bank + card)',
        );
      }
    }

    // ── Pass 2: bank-only fallback — only when no real variant was detected ──
    // The variant returned by Gemini may just be the bank name ("SBI Card")
    // because the statement layout gave no specific card name. If the user
    // owns exactly one card from that bank, it's safe to attach the
    // statement there without demanding a URL.
    final expectedCardNameIsJustBankName =
        expectedCardName.toLowerCase().trim() == bankName.toLowerCase().trim();
    if (expectedCardNameIsJustBankName) {
      final bankCards = existingUserCards.where(bankMatches).toList();
      if (bankCards.length == 1) {
        final creditCard = bankCards.single;
        return CardMatchResult(
          catalogCardId: creditCard.catalogCardId ?? '',
          userCardId: creditCard.id,
          matchPass: 'Pass-2 (bank-only, unambiguous)',
        );
      }
    }

    return null;
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
      print(
          '   🔍 Looking for existing user card: Bank="$bankName", Card="$expectedCardName"');

      final match = findMatchingUserCard(
        existingUserCards: existingUserCards,
        bankName: bankName,
        expectedCardName: expectedCardName,
      );
      if (match != null) {
        print('   ✅ ${match.matchPass} match: userCardId=${match.userCardId}');
        return CardInfo(
          catalogCardId: match.catalogCardId,
          userCardId: match.userCardId,
        );
      }

      // ── Pass 3: catalog lookup — exact bank + card ───────────────────
      print('   📝 No existing user card for $bankName — searching catalog...');
      final resolveCatalogCard = _findOrCreateCatalogCard ??
          _findOrCreateCatalogCardWithSeparateBankAndCard;
      final catalogCardId = await resolveCatalogCard(
        userId: userId,
        bankName: bankName,
        cardName: expectedCardName,
        emailSubject: emailSubject,
        pdfName: statement.attachmentName ?? 'Unknown PDF',
      );
      final userCardId =
          await _createUserCardAssociation(userId, catalogCardId);
      return CardInfo(catalogCardId: catalogCardId, userCardId: userCardId);
    } catch (error) {
      print('   ❌ Error ensuring credit card exists: $error');
      rethrow;
    }
  }

  /// Default [_lookupCatalogCard] implementation: tries an exact bank+card
  /// match, then a fuzzy bank+subject-keyword match; when [cardUrl] is
  /// supplied (the user has already provided one), also checks for an
  /// existing card with that exact URL. Returns the matched catalog card ID,
  /// or `null` if nothing matches any of these.
  static Future<String?> _defaultLookupCatalogCard({
    required String bankName,
    required String cardName,
    required String emailSubject,
    required String? cardUrl,
  }) async {
    if (cardUrl != null) {
      print('   🔍 Checking for existing card with same URL...');
      final duplicateCheck = await Supabase.instance.client
          .from('card_catalog')
          .select('id, bank, card_name')
          .eq('card_url', cardUrl)
          .maybeSingle();
      if (duplicateCheck != null) {
        print('   ✅ Found existing card with same URL:');
        print('      Bank: ${duplicateCheck['bank']}');
        print('      Card: ${duplicateCheck['card_name']}');
        return duplicateCheck['id'] as String;
      }
      return null;
    }

    // ── Exact match: bank + card_name ────────────────────────────────
    final exact = await Supabase.instance.client
        .from('card_catalog')
        .select('*')
        .eq('bank', bankName)
        .eq('card_name', cardName)
        .limit(1);
    if (exact.isNotEmpty) {
      print(
          '   ✅ Catalog exact match: ${exact.first['card_name']} (${exact.first['bank']})');
      return exact.first['id'] as String;
    }

    // ── Fuzzy match tier 1: bank + subject keyword ────────────────────
    // Extract distinctive words from the email subject (e.g. "BPCL", "Coral",
    // "Flipkart") and prefer catalog cards whose card_name contains them.
    final subjectWords = emailSubject
        .toUpperCase()
        .split(RegExp(r'[\s\-_/]+'))
        .where((w) =>
            w.length > 2 &&
            ![
              'YOUR',
              'CARD',
              'CREDIT',
              'BANK',
              'STATEMENT',
              'MONTHLY',
              'ACCOUNT',
              'FOR',
              'THE',
              'AND',
              'DUE',
              'DATE',
              'JAN',
              'FEB',
              'MAR',
              'APR',
              'MAY',
              'JUN',
              'JUL',
              'AUG',
              'SEP',
              'OCT',
              'NOV',
              'DEC',
              'SBI',
              'HDFC',
              'ICICI',
              'AXIS',
              'KOTAK'
            ].contains(w))
        .toSet();
    final bankRoot =
        bankName.replaceAll(' Card', '').replaceAll(' Bank', '').trim();
    for (final keyword in subjectWords) {
      final bySubjectKw = await Supabase.instance.client
          .from('card_catalog')
          .select('id, bank, card_name')
          .ilike('bank', '%$bankRoot%')
          .ilike('card_name', '%$keyword%')
          .limit(1);
      if (bySubjectKw.isNotEmpty) {
        print(
            '   ✅ Catalog subject-keyword match ($keyword): ${bySubjectKw.first['card_name']} (${bySubjectKw.first['bank']})');
        return bySubjectKw.first['id'] as String;
      }
    }

    return null;
  }

  Future<String> _findOrCreateCatalogCardWithSeparateBankAndCard({
    required String userId,
    required String bankName,
    required String cardName,
    required String emailSubject,
    required String pdfName,
  }) async {
    try {
      print(
          '   🔍 Looking for catalog card: Bank="$bankName", Card="$cardName"');

      final match = await _lookupCatalogCard(
        bankName: bankName,
        cardName: cardName,
        emailSubject: emailSubject,
        cardUrl: null,
      );
      if (match != null) {
        return match;
      }

      // ── No catalog match → ask user for URL ──────────────────────────
      // Deliberately no "any card from this bank" fallback here: picking an
      // arbitrary same-bank catalog card with no keyword/name signal tying it
      // to the actual statement creates a phantom user_cards row for a card
      // the user may not even own (e.g. an unrelated ICICI product matched
      // to an ICICI email with no extractable card variant). Falling through
      // to the manual URL prompt below requires explicit user confirmation
      // instead of guessing.
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
      final searchQuery =
          Uri.encodeComponent('$bankName $cardName credit card');
      final suggestedUrl = 'https://www.google.com/search?q=$searchQuery';

      // Prompt user for URL (REQUIRED)
      String? userProvidedUrl;
      print(
          '   🔍 DEBUG: onCardUrlRequired callback is: ${onCardUrlRequired == null ? "NULL" : "SET"}');
      if (onCardUrlRequired != null) {
        print('   📱 Showing URL input dialog to user...');
        userProvidedUrl = await onCardUrlRequired!(
          bankName: bankName,
          cardVariant: cardName,
          emailSubject: emailSubject,
          pdfName: pdfName,
          suggestedUrl: suggestedUrl,
        );
      } else {
        print('   ❌ onCardUrlRequired callback is NULL - cannot show dialog!');
      }

      // If user didn't provide URL, fail gracefully
      if (userProvidedUrl == null || userProvidedUrl.isEmpty) {
        print(
            '   ❌ No URL provided by user. Cannot create card without product page URL.');
        print('   ⚠️  Skipping this card. Please add it manually later.');
        print('');
        throw Exception('Card URL required but not provided by user');
      }

      print('   ✅ User provided URL: $userProvidedUrl');
      print('');

      try {
        // Check if a card with this URL already exists (deduplication)
        final duplicateCardId = await _lookupCatalogCard(
          bankName: bankName,
          cardName: cardName,
          emailSubject: emailSubject,
          cardUrl: userProvidedUrl,
        );
        if (duplicateCardId != null) {
          print(
              '   ✅ Found existing card with same URL. Reusing card ID: $duplicateCardId');
          print('');
          return duplicateCardId;
        }

        print('   ✅ No duplicate found. Queuing card for admin review...');

        // card_catalog writes are admin-reviewed — clients cannot insert
        // directly (see supabase/migrations/20260712043000_security_and_email_hardening.sql).
        // Queue the request instead; the card won't exist until approved.
        await _submitCardCatalogRequest(
          userId: userId,
          bankName: bankName,
          cardName: cardName,
          cardUrl: userProvidedUrl,
        );
        print('   📝 Card submitted for review: $bankName $cardName');
        print('   🔗 URL: $userProvidedUrl');
        print('');

        throw Exception(
            'New card "$bankName $cardName" submitted for admin review — '
            'it will be available once approved. Try syncing again later.');
      } catch (insertError) {
        print('   ❌ Failed to create card: $insertError');
        rethrow;
      }
    } catch (error) {
      print('   ❌ Error finding/creating catalog card: $error');
      rethrow;
    }
  }

  /// Test-only entry point for [_createUserCardAssociation].
  @visibleForTesting
  Future<String> createUserCardAssociation(
          String userId, String catalogCardId) =>
      _createUserCardAssociation(userId, catalogCardId);

  /// Create user-card association and return user card ID
  Future<String> _createUserCardAssociation(
      String userId, String catalogCardId) async {
    try {
      print('   🔄 Creating user-card association...');

      // Use the RPC function directly to get the user card ID
      final userCardId = await _associateUserWithCard(
        userId: userId,
        catalogCardId: catalogCardId,
      );

      print('   ✅ User-card association created with ID: $userCardId');
      return userCardId;
    } catch (associationError) {
      print('   ⚠️ User-card association error: $associationError');

      // Try to find existing association
      try {
        final existingUserCards = await _cardRepo.getUserCards(userId);
        final matchingUserCard = existingUserCards
            .where(
                (uc) => uc.id.contains(catalogCardId) || uc.bankName.isNotEmpty)
            .firstOrNull;

        if (matchingUserCard != null) {
          print(
              '   ✅ Found existing user-card association with ID: ${matchingUserCard.id}');
          return matchingUserCard.id;
        }
      } catch (e) {
        // Ignore and continue
      }

      // No RPC success and no existing association found — surface the
      // failure instead of fabricating an ID that was never persisted to
      // `user_cards`. A fake ID here causes every subsequent statement/
      // transaction insert to fail its FK constraint silently.
      throw Exception(
          'Failed to create or find user-card association for catalog card $catalogCardId: $associationError');
    }
  }

  /// Ensure credit card exists, create if not found  /// Store transactions with deduplication
  Future<void> _storeTransactionsWithDeduplication({
    required List<Transaction> transactions,
    required String userCardId,
    required String userId,
    String? statementId,
  }) async {
    try {
      final updatedTransactions = transactions
          .map((tx) => Transaction(
                id: tx.id,
                userId: userId,
                userCardId: userCardId,
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
                statementId: statementId,
                createdAt: tx.createdAt,
              ))
          .toList();

      // Use the enhanced repository method with duplicate prevention
      await _transactionRepo.addTransactionsBatch(updatedTransactions);
    } catch (error) {
      print('   ❌ Error storing transactions: $error');
      rethrow;
    }
  }

  /// Store statement metadata
}
