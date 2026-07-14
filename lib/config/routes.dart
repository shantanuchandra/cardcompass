import 'package:flutter/material.dart';
import 'package:cardcompass/features/auth/presentation/screens/splash_screen.dart';
import 'package:cardcompass/features/auth/presentation/screens/login_screen.dart';
import 'package:cardcompass/features/auth/presentation/screens/profile_screen.dart';
import 'package:cardcompass/features/cards/presentation/screens/cards_list_screen.dart';
import 'package:cardcompass/features/cards/presentation/screens/add_card_screen.dart';
import 'package:cardcompass/features/cards/presentation/screens/card_details_screen.dart';
import 'package:cardcompass/features/cards/presentation/screens/home_screen.dart';
import 'package:cardcompass/features/transactions/presentation/screens/transactions_screen.dart';
import 'package:cardcompass/features/transactions/presentation/screens/transaction_advisor_screen.dart';
import 'package:cardcompass/features/transaction_advisor/presentation/screens/enhanced_transaction_advisor_screen.dart';
import 'package:cardcompass/features/analytics/presentation/screens/analytics_screen.dart';
import 'package:cardcompass/features/recommendations/presentation/screens/recommendations_screen.dart';
import 'package:cardcompass/features/statements/presentation/screens/statements_screen.dart';
import 'package:cardcompass/features/settings/presentation/screens/settings_screen.dart';
import 'package:cardcompass/features/benefits/presentation/screens/benefits_screen.dart';
import 'package:cardcompass/features/notifications/presentation/screens/notifications_screen.dart';
import 'package:cardcompass/features/debug/pm_pruning_debug_screen.dart';
import 'package:cardcompass/features/evals/presentation/screens/ai_evals_screen.dart';

/// Application routes configuration
class AppRoutes {
  // Route names
  static const String splash = '/';
  static const String login = '/login';
  static const String home = '/home';
  static const String dashboard = '/dashboard';
  static const String cards = '/cards';
  static const String addCard = '/add-card';
  static const String cardDetails = '/card-details';
  static const String transactions = '/transactions';
  static const String transactionAdvisor = '/transaction-advisor';
  static const String enhancedTransactionAdvisor =
      '/enhanced-transaction-advisor';
  static const String analytics = '/analytics';
  static const String recommendations = '/recommendations';
  static const String benefits = '/benefits';
  static const String notifications = '/notifications';
  static const String statements = '/statements';
  static const String profile = '/profile';
  static const String settings = '/settings';
  static const String adminPm = '/admin/pm';
  static const String adminEvals = '/admin/evals';

  static const Set<String> _startupRoutes = {
    splash,
    login,
    home,
    dashboard,
    cards,
    addCard,
    cardDetails,
    transactions,
    transactionAdvisor,
    enhancedTransactionAdvisor,
    analytics,
    recommendations,
    benefits,
    notifications,
    statements,
    profile,
    settings,
    adminPm,
    adminEvals,
  };

  /// Resolves browser hash links before the splash screen can redirect an
  /// authenticated user to the customer dashboard.
  static String startupRoute({
    required String defaultRouteName,
    String? webHash,
  }) {
    for (final candidate in [webHash, defaultRouteName]) {
      final route = _normalizeStartupRoute(candidate);
      if (route != null && _startupRoutes.contains(route)) return route;
    }
    return splash;
  }

  /// Builds exactly one initial route. Flutter's default implementation
  /// expands `/admin/pm` into `/`, `/admin`, and `/admin/pm`; the splash route
  /// on that prefix stack can later replace the intended admin route.
  static List<Route<dynamic>> generateInitialRoutes(String initialRouteName) {
    return [generateRoute(RouteSettings(name: initialRouteName))];
  }

  static String? _normalizeStartupRoute(String? candidate) {
    if (candidate == null || candidate.trim().isEmpty) return null;
    var route = candidate.trim();
    if (route.startsWith('#')) route = route.substring(1);
    // Ignore Supabase OAuth callback hash fragments (#sb, #access_token=..., etc.)
    // These are processed by supabase_flutter's SupabaseAuth and should not
    // be interpreted as app routes. Let the splash screen handle auth state.
    if (route.startsWith('sb') ||
        route.contains('access_token') ||
        route.contains('refresh_token') ||
        route.contains('error_description')) {
      return null;
    }
    if (!route.startsWith('/')) route = '/$route';
    return route;
  }

  /// Generate routes for the application
  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case splash:
        return MaterialPageRoute(
          builder: (_) => const SplashScreen(),
          settings: settings,
        );

      case login:
        return MaterialPageRoute(
          builder: (_) => const LoginScreen(),
          settings: settings,
        );
      case home:
      case dashboard:
        return MaterialPageRoute(
          builder: (_) => const HomeScreen(),
          settings: settings,
        );
      case cards:
        return MaterialPageRoute(
          builder: (_) => const CardsListScreen(),
          settings: settings,
        );

      case addCard:
        return MaterialPageRoute(
          builder: (_) => const AddCardScreen(),
          settings: settings,
        );
      case cardDetails:
        final String? cardId = settings.arguments as String?;
        return MaterialPageRoute(
          builder: (_) => CardDetailsScreen(cardId: cardId ?? '1'),
          settings: settings,
        );

      case transactions:
        return MaterialPageRoute(
          builder: (_) => const TransactionsScreen(),
          settings: settings,
        );
      case transactionAdvisor:
        return MaterialPageRoute(
          builder: (_) => const TransactionAdvisorScreen(),
          settings: settings,
        );

      case enhancedTransactionAdvisor:
        return MaterialPageRoute(
          builder: (_) => EnhancedTransactionAdvisorScreen(
            initialTabIndex: settings.arguments as int? ?? 0,
          ),
          settings: settings,
        );

      case analytics:
        return MaterialPageRoute(
          builder: (_) => const AnalyticsScreen(),
          settings: settings,
        );

      case recommendations:
        return MaterialPageRoute(
          builder: (_) => const RecommendationsScreen(),
          settings: settings,
        );
      case statements:
        return MaterialPageRoute(
          builder: (_) => const StatementsScreen(),
          settings: settings,
        );
      case profile:
        return MaterialPageRoute(
          builder: (_) => const ProfileScreen(),
          settings: settings,
        );
      case '/settings':
        return MaterialPageRoute(
          builder: (_) => const SettingsScreen(),
          settings: settings,
        );
      case adminPm:
        return MaterialPageRoute(
          builder: (_) => const PmPruningDebugScreen(),
          settings: settings,
        );
      case adminEvals:
        return MaterialPageRoute(
          builder: (_) => const AiEvalsScreen(),
          settings: settings,
        );
      case '/benefits':
        return MaterialPageRoute(
          builder: (_) => const BenefitsScreen(),
          settings: settings,
        );
      case '/notifications':
        return MaterialPageRoute(
          builder: (_) => const NotificationsScreen(),
          settings: settings,
        );

      default:
        // Unknown routes (including Supabase OAuth fragments like #sb which
        // Flutter web converts to route "/sb") fall through to the splash
        // screen where auth state is checked and the user is redirected
        // to the appropriate screen.
        return MaterialPageRoute(
          builder: (_) => const SplashScreen(),
          settings: settings,
        );
    }
  }

  /// Get route transitions
  static PageRouteBuilder<T> createRoute<T extends Object?>(
    Widget page, {
    RouteSettings? settings,
    Duration duration = const Duration(milliseconds: 300),
  }) {
    return PageRouteBuilder<T>(
      settings: settings,
      pageBuilder: (context, animation, _) => page,
      transitionDuration: duration,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        const begin = Offset(1.0, 0.0);
        const end = Offset.zero;
        const curve = Curves.ease;

        var tween = Tween(begin: begin, end: end).chain(
          CurveTween(curve: curve),
        );

        return SlideTransition(
          position: animation.drive(tween),
          child: child,
        );
      },
    );
  }

  /// Fade transition route
  static PageRouteBuilder<T> fadeRoute<T extends Object?>(
    Widget page, {
    RouteSettings? settings,
    Duration duration = const Duration(milliseconds: 300),
  }) {
    return PageRouteBuilder<T>(
      settings: settings,
      pageBuilder: (context, animation, _) => page,
      transitionDuration: duration,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: animation,
          child: child,
        );
      },
    );
  }

  /// Scale transition route
  static PageRouteBuilder<T> scaleRoute<T extends Object?>(
    Widget page, {
    RouteSettings? settings,
    Duration duration = const Duration(milliseconds: 300),
  }) {
    return PageRouteBuilder<T>(
      settings: settings,
      pageBuilder: (context, animation, _) => page,
      transitionDuration: duration,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        const begin = 0.0;
        const end = 1.0;
        const curve = Curves.ease;

        var tween = Tween(begin: begin, end: end).chain(
          CurveTween(curve: curve),
        );

        return ScaleTransition(
          scale: animation.drive(tween),
          child: child,
        );
      },
    );
  }
}
