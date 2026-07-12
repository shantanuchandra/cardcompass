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
import 'package:cardcompass/core/services/app_preferences.dart';
import 'package:cardcompass/core/services/alert_email_parser_service.dart';
import 'package:cardcompass/core/services/transaction_deduplication_service.dart';
import 'package:cardcompass/core/services/alert_email_sync_service.dart';

// Repositories
import 'package:cardcompass/core/repositories/card_repository.dart';
import 'package:cardcompass/core/repositories/supabase_card_repository.dart';
import 'package:cardcompass/core/repositories/mock_card_repository.dart';
import 'package:cardcompass/core/repositories/transaction_repository.dart';
import 'package:cardcompass/core/repositories/supabase_transaction_repository.dart';
import 'package:cardcompass/core/repositories/mock_transaction_repository.dart';
import 'package:cardcompass/core/repositories/statement_repository.dart';
import 'package:cardcompass/core/repositories/supabase_statement_repository.dart';
import 'package:cardcompass/core/repositories/mock_statement_repository.dart';
import 'package:cardcompass/core/repositories/reward_balance_repository.dart';
import 'package:cardcompass/core/repositories/supabase_reward_balance_repository.dart';
import 'package:cardcompass/core/repositories/mock_reward_balance_repository.dart';
import 'package:cardcompass/core/repositories/supabase_notification_repository.dart';
import 'package:cardcompass/core/services/reward_intelligence_service.dart';
import 'package:cardcompass/core/services/rewards_nudge_service.dart';

// Auth (for the guest/live switch)
import 'package:cardcompass/features/auth/providers/auth_provider.dart' hide AuthService;

/// Provider for SharedPreferences
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('SharedPreferences must be initialized in main()');
});

/// True when the signed-in user is the local guest user (no Supabase session).
final isGuestModeProvider = Provider<bool>((ref) {
  return ref.watch(authStateProvider).user?.id == 'guest';
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

/// Provider for CardRepository — mock in guest mode, Supabase otherwise.
final cardRepositoryProvider = Provider<CardRepository>((ref) {
  return ref.watch(isGuestModeProvider) ? MockCardRepository() : SupabaseCardRepository();
});

/// Provider for TransactionRepository — mock in guest mode, Supabase otherwise.
final transactionRepositoryProvider = Provider<TransactionRepository>((ref) {
  return ref.watch(isGuestModeProvider) ? MockTransactionRepository() : SupabaseTransactionRepository();
});

/// Provider for StatementRepository — mock in guest mode, Supabase otherwise.
final statementRepositoryProvider = Provider<StatementRepository>((ref) {
  return ref.watch(isGuestModeProvider) ? MockStatementRepository() : SupabaseStatementRepository();
});

/// Provider for RecommendationService
final recommendationServiceProvider = Provider<RecommendationService>((ref) {
  return RecommendationServiceImpl(
    merchantRateService: MerchantRateService(),
    milestoneTracker: MilestoneTracker(),
    cardRepository: ref.watch(cardRepositoryProvider),
    transactionRepository: ref.watch(transactionRepositoryProvider),
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

/// Provider for AppPreferences (local settings persistence)
final appPreferencesProvider = Provider<AppPreferences>((ref) {
  return AppPreferences(ref.watch(sharedPreferencesProvider));
});

// ---------------------------------------------------------------------------
// Phase 2 — Alert Email Pipeline
// ---------------------------------------------------------------------------

/// Stateless parser for alert email bodies.
final alertEmailParserProvider = Provider<AlertEmailParserService>((ref) {
  return AlertEmailParserService();
});

/// Stateless deduplication engine.
final transactionDeduplicationProvider =
    Provider<TransactionDeduplicationService>((ref) {
  return TransactionDeduplicationService();
});

/// Orchestrator that fetches alert emails, parses them, deduplicates, and
/// upserts into the transaction repository.
/// Requires a [GoogleSignInAccount] — provided by the sync feature at runtime.
final alertEmailSyncServiceProvider =
    Provider<AlertEmailSyncService>((ref) {
  return AlertEmailSyncService(
    parser: ref.watch(alertEmailParserProvider),
    deduplication: ref.watch(transactionDeduplicationProvider),
    transactionRepository: ref.watch(transactionRepositoryProvider),
  );
});

// ---------------------------------------------------------------------------
// Phase 3 — Rewards Intelligence & Nudges
// ---------------------------------------------------------------------------



/// Provider for RewardBalanceRepository — mock in guest, Supabase otherwise.
final rewardBalanceRepositoryProvider = Provider<RewardBalanceRepository>((ref) {
  return ref.watch(isGuestModeProvider)
      ? MockRewardBalanceRepository()
      : SupabaseRewardBalanceRepository();
});

/// Stateless reward intelligence engine (point valuations + insight detection).
final rewardIntelligenceServiceProvider =
    Provider<RewardIntelligenceService>((ref) {
  return RewardIntelligenceService();
});

/// Notification repository (used by nudge service).
final notificationRepositoryProvider =
    Provider<SupabaseNotificationRepository>((ref) {
  return SupabaseNotificationRepository();
});

/// Orchestrator: loads balances → generates insights → persists notifications.
final rewardsNudgeServiceProvider = Provider<RewardsNudgeService>((ref) {
  return RewardsNudgeService(
    intelligence: ref.watch(rewardIntelligenceServiceProvider),
    rewardRepo: ref.watch(rewardBalanceRepositoryProvider),
    notificationRepo: ref.watch(notificationRepositoryProvider),
  );
});
