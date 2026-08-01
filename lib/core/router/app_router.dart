import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/splash_screen.dart';
import '../../features/dashboard/screens/dashboard_screen.dart';
import '../../features/cards/screens/cards_screen.dart';
import '../../features/cards/screens/add_card_screen.dart';
import '../../features/transactions/screens/transactions_screen.dart';
import '../../features/settings/screens/settings_screen.dart';

class AppRoutes {
  static const splash = '/';
  static const login = '/login';
  static const dashboard = '/app';
  static const cards = '/app/cards';
  static const addCard = '/app/cards/add';
  static const transactions = '/app/transactions';
  static const settings = '/app/settings';
}

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authNotifierProvider);

  return GoRouter(
    initialLocation: AppRoutes.splash,
    debugLogDiagnostics: false,
    redirect: (context, state) {
      final isLoading = authState.isLoading;
      if (isLoading) return null;

      final isAuthed = authState.valueOrNull == AuthStatus.authenticated;
      final onSplash = state.matchedLocation == AppRoutes.splash;
      final onLogin = state.matchedLocation == AppRoutes.login;
      final onApp = state.matchedLocation.startsWith('/app');

      // Handle Supabase OAuth callback hash
      final uri = Uri.base;
      if (uri.fragment.contains('access_token')) return null;

      if (!isAuthed && onApp) return AppRoutes.login;
      if (isAuthed && (onLogin || onSplash)) return AppRoutes.dashboard;
      if (onSplash && !isAuthed) return AppRoutes.login;
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (_, __) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (_, __) => const LoginScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: AppRoutes.dashboard,
            builder: (_, __) => const DashboardScreen(),
          ),
          GoRoute(
            path: AppRoutes.cards,
            builder: (_, __) => const CardsScreen(),
            routes: [
              GoRoute(
                path: 'add',
                builder: (_, __) => const AddCardScreen(),
              ),
            ],
          ),
          GoRoute(
            path: AppRoutes.transactions,
            builder: (_, __) => const TransactionsScreen(),
          ),
          GoRoute(
            path: AppRoutes.settings,
            builder: (_, __) => const SettingsScreen(),
          ),
        ],
      ),
    ],
  );
});

// Bottom nav shell wrapper
class AppShell extends ConsumerStatefulWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _selectedIndex = 0;

  static const _tabs = [
    AppRoutes.dashboard,
    AppRoutes.cards,
    AppRoutes.transactions,
    AppRoutes.settings,
  ];

  void _onTap(int index) {
    if (index == _selectedIndex) return;
    setState(() => _selectedIndex = index);
    context.go(_tabs[index]);
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final currentIndex = _tabs.indexWhere((t) => location.startsWith(t));
    final idx = currentIndex < 0 ? 0 : currentIndex;

    return Scaffold(
      body: widget.child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: idx,
        onDestinationSelected: _onTap,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Dashboard'),
          NavigationDestination(icon: Icon(Icons.credit_card_outlined), selectedIcon: Icon(Icons.credit_card), label: 'Cards'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Ledger'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}
