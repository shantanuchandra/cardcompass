/// Application constants and configuration
class AppConstants {
  // App Information
  static const String appName = 'CardCompass';
  static const String appTagline = 'Navigate Your Credit Card Benefits';
  static const String appVersion = '1.0.0';

  // NOTE: Supabase URL/anon key, Gmail client ID and a Gmail *client secret*
  // used to be hardcoded here as dead, unused fields (never referenced
  // anywhere in the app). Removed rather than migrated to lib/core/env.dart
  // to avoid keeping two parallel config sources - lib/core/app_config.dart
  // (backed by lib/core/env.dart) is the single source of truth. The client
  // secret in particular should never have shipped in a client app; if
  // Gmail OAuth needs it again, that's a sign the OAuth client should be
  // reconfigured as a public/native client (PKCE) instead of resurrecting a
  // secret into client-side code.

  // API Endpoints
  static const String baseApiUrl = 'https://your-api.com/api/v1';

  static const List<String> gmailScopes = [
    'https://www.googleapis.com/auth/gmail.readonly'
  ];

  // Transaction Categories
  static const List<String> transactionCategories = [
    'Dining',
    'Groceries',
    'Fuel',
    'Shopping',
    'Entertainment',
    'Travel',
    'Healthcare',
    'Education',
    'Bills & Utilities',
    'ATM',
    'Others',
  ];

  // Credit Card Types
  static const List<String> cardTypes = [
    'entry-level',
    'mid-tier',
    'premium',
    'super-premium',
  ];

  // Credit Card Networks
  static const List<String> cardNetworks = [
    'VISA',
    'Mastercard',
    'RuPay',
    'American Express',
    'Diners Club',
  ];

  // Indian Banks
  static const List<String> indianBanks = [
    'HDFC Bank',
    'SBI Card',
    'Axis Bank',
    'ICICI Bank',
    'Kotak Bank',
    'IDFC FIRST Bank',
    'Yes Bank',
    'IndusInd Bank',
    'Standard Chartered',
    'Citibank',
    'HSBC',
    'RBL Bank',
    'BOB Financial',
    'PNB',
    'Canara Bank',
    'Union Bank',
  ];

  // Spending Categories for Analytics
  static const Map<String, String> categoryIcons = {
    'Dining': '🍽️',
    'Groceries': '🛒',
    'Fuel': '⛽',
    'Shopping': '🛍️',
    'Entertainment': '🎬',
    'Travel': '✈️',
    'Healthcare': '🏥',
    'Education': '📚',
    'Bills & Utilities': '📄',
    'ATM': '🏧',
    'Others': '📦',
  };

  // Reward Calculation Constants
  static const double defaultRewardRate = 1.0; // 1% default
  static const double premiumRewardRate = 2.5; // 2.5% for premium cards
  static const double superPremiumRewardRate = 3.33; // 3.33% for super premium

  // UI Constants
  static const double defaultPadding = 16.0;
  static const double smallPadding = 8.0;
  static const double largePadding = 24.0;
  static const double borderRadius = 12.0;
  static const double cardRadius = 16.0;

  // Animation Durations
  static const Duration shortAnimation = Duration(milliseconds: 200);
  static const Duration mediumAnimation = Duration(milliseconds: 300);
  static const Duration longAnimation = Duration(milliseconds: 500);

  // Currency
  static const String defaultCurrency = 'INR';
  static const String currencySymbol = '₹';

  // Date Formats
  static const String dateFormat = 'dd/MM/yyyy';
  static const String dateTimeFormat = 'dd/MM/yyyy HH:mm';
  static const String monthYearFormat = 'MMM yyyy';
  static const String displayDateFormat = 'dd MMM yyyy';
  static const String apiDateFormat = 'yyyy-MM-dd';
  static const String fullDateTimeFormat = 'dd MMM yyyy, hh:mm a';

  // File Types
  static const List<String> supportedStatementFormats = ['pdf'];
  static const int maxFileSize = 10 * 1024 * 1024; // 10MB

  // Validation Constants
  static const int minCardNameLength = 2;
  static const int maxCardNameLength = 50;
  static const int cardDigitsLength = 4;
  static const double minTransactionAmount = 0.01;
  static const double maxTransactionAmount = 1000000.0;

  // Preferences Keys
  static const String prefUserData = 'user_data';
  static const String prefThemeMode = 'theme_mode';
  static const String prefFirstLaunch = 'first_launch';
  static const String prefLastSync = 'last_sync';

  // Error Messages
  static const String genericError = 'Something went wrong. Please try again.';
  static const String networkError = 'Network error. Please check your connection.';
  static const String authError = 'Authentication failed. Please login again.';
  static const String noDataError = 'No data available.';
  static const String invalidFileError = 'Invalid file format.';
  static const String fileSizeError = 'File size exceeds limit.';

  // Success Messages
  static const String cardAddedSuccess = 'Credit card added successfully!';
  static const String statementImportedSuccess = 'Statement imported successfully!';
  static const String transactionSyncedSuccess = 'Transactions synced successfully!';
  static const String profileUpdatedSuccess = 'Profile updated successfully!';

  // Feature Flags
  static const bool enableGmailIntegration = true;
  static const bool enablePdfParsing = true;
  static const bool enablePushNotifications = true;
  static const bool enableAnalytics = true;
  static const bool enableCrashReporting = true;

  // Debug Settings
  static const bool enableDebugLogs = true;
  static const bool enablePerformanceMonitoring = true;

  // Test User ID for Movie Rule Engine
  static const String testUserIdMovieRuleEngine = '5dc9b591-40b6-4486-944e-3b4ef58c3d47';
}
