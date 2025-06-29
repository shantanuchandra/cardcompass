class AppConfig {
  static const String appName = 'CardCompass';
  static const String appVersion = '1.0.0';
  // Supabase Configuration
  static const String supabaseUrl = 'https://hpvxlazlgyykqwpmstmw.supabase.co';
  static const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhwdnhsYXpsZ3l5a3F3cG1zdG13Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDk5MDIyODAsImV4cCI6MjA2NTQ3ODI4MH0.tyTQ-6scFQp5e4EVtufTpLtyr0s6-N1DWiXOEujwaFA';
  
  // Google Sign-In Configuration
  static const String googleClientId = '634383830161-cg9q9acc830kdi97shi1fkhifnalvpj4.apps.googleusercontent.com';
  
  // API Endpoints
  static const String baseApiUrl = 'https://api.cardcompass.com';
  
  // Database Configuration
  static const String localDbName = 'cardcompass_local.db';
  
  // Feature Flags
  static const bool enableAnalytics = true;
  static const bool enablePdfParsing = true;
  static const bool enableEmailIntegration = true;
  static const bool enableRecommendations = true;
  
  // UI Configuration
  static const int maxCardsPerUser = 20;
  static const int maxTransactionsPerPage = 50;
  static const Duration cacheExpiration = Duration(hours: 24);
  
  // Security Configuration
  static const String encryptionKey = 'YOUR_ENCRYPTION_KEY';
  static const bool enableBiometricAuth = true;
}
