import 'env.dart';

class AppConfig {
  static const String appName = 'CardCompass';
  static const String appVersion = '1.0.0';
  // Supabase Configuration - injected via --dart-define-from-file, see lib/core/env.dart
  static const String supabaseUrl = Env.supabaseUrl;
  static const String supabaseAnonKey = Env.supabaseAnonKey;

  // Google Sign-In Configuration - injected via --dart-define-from-file, see lib/core/env.dart
  static const String googleClientId = Env.googleClientId;
  
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
