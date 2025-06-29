import 'package:flutter/material.dart';

/// Configuration constants for dashboard
class DashboardConfig {
  // Layout constants
  static const double defaultPadding = 16.0;
  static const double sectionSpacing = 24.0;
  static const double cardSpacing = 16.0;
  static const double smallSpacing = 8.0;
  static const double iconSize = 24.0;
  static const double smallIconSize = 18.0;
  
  // Grid configuration
  static const int quickActionsWideScreenCount = 4;
  static const int quickActionsNormalScreenCount = 3;
  static const double quickActionsWideScreenHeight = 70.0;
  static const double quickActionsNormalScreenHeight = 65.0;
  static const double wideScreenBreakpoint = 600.0;
  
  // Colors
  static const Color morningColor = Colors.orange;
  static const Color afternoonColor = Colors.amber;
  static const Color eveningColor = Colors.indigo;
  
  // Animation durations
  static const Duration quickAnimationDuration = Duration(milliseconds: 200);
  static const Duration normalAnimationDuration = Duration(milliseconds: 300);
  
  // Text styles
  static const double greetingFontSize = 14.0;
  static const double compactButtonFontSize = 10.0;
  
  // Card configuration
  static const double cardBorderRadius = 12.0;
  static const double containerBorderRadius = 16.0;
  static const double cardElevation = 2.0;
  
  // Progress indicators
  static const double savingsExcellentRate = 10.0; // 10% is excellent
  static const double savingsGoodRate = 3.0;       // 3% is good
  
  // Recent transactions
  static const int maxRecentTransactions = 5;
  
  // Loading configuration
  static const double loadingIconSize = 32.0;
  static const double loadingStrokeWidth = 3.0;
  
  // Notification badge
  static const double notificationBadgeSize = 12.0;
  static const double notificationBadgeRadius = 6.0;
}

/// Dashboard text constants
class DashboardTexts {
  // Greetings
  static const String goodMorning = 'Good Morning';
  static const String goodAfternoon = 'Good Afternoon';
  static const String goodEvening = 'Good Evening';
  static const String readyToManage = 'Ready to manage your finances?';
  
  // Section titles
  static const String quickActions = 'Quick Actions';
  static const String thisMonth = 'This Month';
  static const String spendingInsights = 'Spending Insights';
  static const String recentActivity = 'Recent Activity';
  
  // Card labels
  static const String spending = 'Spending';
  static const String rewards = 'Rewards';
  static const String cards = 'Cards';
  static const String savings = 'Savings';
  static const String rate = 'Rate';
  static const String earned = 'Earned';
  static const String active = 'Active';
  static const String thisMonthSubtitle = 'This month';
  
  // Action labels
  static const String cardsAction = 'Cards';
  static const String benefitsAction = 'Benefits';
  static const String advisorAction = 'Advisor';
  static const String analyticsAction = 'Analytics';
  static const String aiBenefitsAction = 'AI Benefits';
  static const String syncAction = 'Sync';
  static const String deleteAction = 'Delete';
  
  // Insights
  static const String savingsRateGood = 'Great job! You\'re maximizing your card benefits.';
  static const String savingsRateImprove = 'Consider using cards with better rewards for your spending categories.';
  static const String monthlyGoal = 'Monthly Goal';
  static const String potential = 'Potential';
  static const String targetSpending = 'Target spending';
  static const String extraRewards = 'Extra rewards';
  
  // Navigation
  static const String dashboard = 'Dashboard';
  static const String seeAll = 'See All';
  
  // Empty states
  static const String noRecentActivity = 'No Recent Activity';
  static const String recentTransactionsMessage = 'Your recent transactions will appear here';
  
  // Loading
  static const String settingUpDashboard = 'Setting up your dashboard...';
  static const String appName = 'CardCompass';
  static const String appTagline = 'Smart Credit Card Management';
  
  // Error messages
  static const String defaultUser = 'User';
  static const String unknownMerchant = 'Unknown Merchant';
}
