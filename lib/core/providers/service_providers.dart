import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Services
import 'package:cardcompass/core/services/merchant_rate_service.dart';
import 'package:cardcompass/core/services/milestone_tracker.dart';
import 'package:cardcompass/core/services/auth_service.dart';
import 'package:cardcompass/core/services/auth_service_impl.dart';
import 'package:cardcompass/core/services/pdf_service.dart';
import 'package:cardcompass/core/services/pdf_service_impl.dart';
import 'package:cardcompass/core/services/pdf_parsing_service.dart';
import 'package:cardcompass/core/services/pdf_parsing_service_impl.dart';
import 'package:cardcompass/core/services/card_identification_service.dart';
import 'package:cardcompass/core/services/enhanced_gmail_service.dart';
import 'package:cardcompass/core/services/recommendation_service.dart';
import 'package:cardcompass/core/services/recommendation_service_impl.dart';
import 'package:cardcompass/core/services/user_profile_service.dart';
import 'package:cardcompass/core/services/user_profile_service_impl.dart';

// Repositories
import 'package:cardcompass/core/repositories/card_repository.dart';
import 'package:cardcompass/core/repositories/supabase_card_repository.dart';
import 'package:cardcompass/core/repositories/transaction_repository.dart';
import 'package:cardcompass/core/repositories/supabase_transaction_repository.dart';
import 'package:cardcompass/core/repositories/statement_repository.dart';
import 'package:cardcompass/core/repositories/supabase_statement_repository.dart';

/// Provider for SharedPreferences
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('SharedPreferences must be initialized in main()');
});

/// Provider for AuthService
final authServiceProvider = Provider<AuthService>((ref) {
  return AuthServiceImpl();
});

/// Provider for PdfService
final pdfServiceProvider = Provider<PdfService>((ref) {
  return PdfServiceImpl();
});

/// Provider for PdfParsingService
final pdfParsingServiceProvider = Provider<PdfParsingService>((ref) {
  return PdfParsingServiceImpl();
});

/// Provider for EnhancedGmailService
final gmailServiceProvider = Provider<EnhancedGmailService>((ref) {
  throw UnimplementedError('EnhancedGmailService must be initialized with Gmail API');
});

/// Provider for CardRepository
final cardRepositoryProvider = Provider<CardRepository>((ref) {
  return SupabaseCardRepository();
});

/// Provider for TransactionRepository
final transactionRepositoryProvider = Provider<TransactionRepository>((ref) {
  return SupabaseTransactionRepository();
});

/// Provider for StatementRepository
final statementRepositoryProvider = Provider<StatementRepository>((ref) {
  return SupabaseStatementRepository();
});

/// Provider for RecommendationService
final recommendationServiceProvider = Provider<RecommendationService>((ref) {
  return RecommendationServiceImpl(
    merchantRateService: MerchantRateService(),
    milestoneTracker: MilestoneTracker(),
  );
});

/// Provider for UserProfileService
final userProfileServiceProvider = Provider<UserProfileService>((ref) {
  return UserProfileServiceImpl();
});

/// Provider for CardIdentificationService
final cardIdentificationServiceProvider = Provider<CardIdentificationService>((ref) {
  return CardIdentificationService();
});
