import 'package:flutter/material.dart';
import 'package:cardcompass/config/routes.dart';

/// Service for handling dashboard navigation
class DashboardNavigationService {
  
  /// Build bottom navigation bar
  static Widget buildBottomNavigationBar(BuildContext context) {
    return BottomNavigationBar(
      type: BottomNavigationBarType.fixed,
      currentIndex: 0, // Dashboard is selected
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.dashboard),
          label: 'Dashboard',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.credit_card),
          label: 'Cards',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.analytics),
          label: 'Analytics',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.person),
          label: 'Profile',
        ),
      ],
      onTap: (index) => _handleBottomNavTap(context, index),
    );
  }

  /// Handle bottom navigation taps
  static void _handleBottomNavTap(BuildContext context, int index) {
    switch (index) {
      case 0:
        // Already on dashboard
        break;
      case 1:
        Navigator.of(context).pushNamed(AppRoutes.cards);
        break;
      case 2:
        Navigator.of(context).pushNamed(AppRoutes.analytics);
        break;
      case 3:
        Navigator.of(context).pushNamed(AppRoutes.profile);
        break;
    }
  }

  /// Build notification icon with badge
  static Widget buildNotificationIcon() {
    return Builder(
      builder: (context) => Stack(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pushNamed(AppRoutes.notifications),
            icon: const Icon(Icons.notifications_outlined),
            tooltip: 'Notifications',
          ),
          Positioned(
            right: 8,
            top: 8,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(6),
              ),
              constraints: const BoxConstraints(minWidth: 12, minHeight: 12),
              child: const Text(
                '•',
                style: TextStyle(color: Colors.white, fontSize: 8),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Navigate to different sections
  static void navigateTo(BuildContext context, String route) {
    Navigator.of(context).pushNamed(route);
  }

  /// Quick navigation helpers
  static void navigateToCards(BuildContext context) => navigateTo(context, AppRoutes.cards);
  static void navigateToBenefits(BuildContext context) => navigateTo(context, AppRoutes.benefits);
  static void navigateToAnalytics(BuildContext context) => navigateTo(context, AppRoutes.analytics);
  static void navigateToProfile(BuildContext context) => navigateTo(context, AppRoutes.profile);
  static void navigateToTransactions(BuildContext context) => navigateTo(context, AppRoutes.transactions);
  static void navigateToAdvisor(BuildContext context) => navigateTo(context, AppRoutes.enhancedTransactionAdvisor);
}
