import 'package:web/web.dart' as web;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/splash_screen.dart';
import '../../features/dashboard/screens/dashboard_screen.dart';
import '../../features/cards/screens/cards_screen.dart';
import '../../features/cards/screens/add_card_screen.dart';
import '../../features/transactions/screens/transactions_screen.dart';
import '../../features/settings/screens/settings_screen.dart';
import '../theme/app_theme.dart';
import '../../app.dart' show navigatorKey;

const _kTabPaths = ['/app', '/app/cards', '/app/transactions', '/app/settings'];

int _tabIndexFor(String loc) {
  if (loc.startsWith('/app/cards')) return 1;
  if (loc.startsWith('/app/transactions')) return 2;
  if (loc.startsWith('/app/settings')) return 3;
  return 0;
}

// The current tab index — a simple ValueNotifier so _AppShell rebuilds on change.
final _tabIndexNotifier = ValueNotifier<int>(0);

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authNotifierProvider);

  return GoRouter(
    navigatorKey: navigatorKey,
    initialLocation: '/',
    redirect: (context, state) {
      if (authState.isLoading) return null;
      final isAuthed = authState.valueOrNull == AuthStatus.authenticated;
      final loc = state.matchedLocation;
      if (Uri.base.fragment.contains('access_token')) return null;
      if (!isAuthed && loc.startsWith('/app')) return '/login';
      if (isAuthed && (loc == '/login' || loc == '/')) {
        // Restore tab from URL on initial load
        final fragment = Uri.base.fragment;
        _tabIndexNotifier.value = _tabIndexFor(fragment.isEmpty ? '/app' : '/$fragment');
        return '/app';
      }
      if (loc == '/' && !isAuthed) return '/login';
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (_, s) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, s) => const LoginScreen()),
      // Single route for ALL app tabs — GoRouter never re-navigates between tabs.
      // Tab switches are handled by _AppShell internally via ValueNotifier +
      // window.history.replaceState to keep the URL in sync.
      GoRoute(
        path: '/app',
        pageBuilder: (_, s) => const NoTransitionPage(child: _AppShell()),
      ),
      // add-card is a separate full-page push on top of the shell
      GoRoute(
        path: '/app/cards/add',
        pageBuilder: (_, s) => const NoTransitionPage(child: AddCardScreen()),
      ),
    ],
  );
});

// Screens ≥1024px get a persistent side rail instead of a bottom bar
// (Material adaptive navigation guidance).
const _kDesktopBreakpoint = 1024.0;

class _AppShell extends ConsumerWidget {
  const _AppShell();

  static const _bodies = <Widget>[
    DashboardScreen(),
    CardsScreen(),
    TransactionsScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ValueListenableBuilder<int>(
      valueListenable: _tabIndexNotifier,
      builder: (context, tabIndex, _) {
        void onTap(int i) {
          _tabIndexNotifier.value = i;
          // Keep browser URL in sync without triggering a GoRouter navigation
          web.window.history.replaceState(null, '', '#${_kTabPaths[i]}');
        }

        final isDesktop = MediaQuery.sizeOf(context).width >= _kDesktopBreakpoint;

        if (isDesktop) {
          return Scaffold(
            body: Row(
              children: [
                _SideRail(selectedIndex: tabIndex, onTap: onTap),
                Expanded(
                  child: IndexedStack(index: tabIndex, children: _bodies),
                ),
              ],
            ),
          );
        }

        return Scaffold(
          body: IndexedStack(
            index: tabIndex,
            children: _bodies,
          ),
          bottomNavigationBar: _BottomNav(
            selectedIndex: tabIndex,
            onTap: onTap,
          ),
        );
      },
    );
  }
}

class _SideRail extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTap;
  const _SideRail({required this.selectedIndex, required this.onTap});

  static const _items = [
    (icon: Icons.dashboard_outlined, activeIcon: Icons.dashboard, label: 'Dashboard'),
    (icon: Icons.credit_card_outlined, activeIcon: Icons.credit_card, label: 'Cards'),
    (icon: Icons.receipt_long_outlined, activeIcon: Icons.receipt_long, label: 'Ledger'),
    (icon: Icons.settings_outlined, activeIcon: Icons.settings, label: 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      decoration: BoxDecoration(
        color: AppColors.surface1,
        border: Border(right: BorderSide(color: AppColors.surface3, width: 1)),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
              child: Text(
                'CardCompass',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 20, fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary, letterSpacing: -0.5,
                ),
              ),
            ),
            ...List.generate(_items.length, (i) {
              final item = _items[i];
              final selected = i == selectedIndex;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                child: Material(
                  color: selected ? AppColors.neonCyan.withValues(alpha: 0.12) : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    onTap: () => onTap(i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          Icon(
                            selected ? item.activeIcon : item.icon,
                            size: 20,
                            color: selected ? AppColors.neonCyan : AppColors.textMuted,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            item.label,
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                              color: selected ? AppColors.neonCyan : AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTap;
  const _BottomNav({required this.selectedIndex, required this.onTap});

  static const _items = [
    (icon: Icons.dashboard_outlined, activeIcon: Icons.dashboard, label: 'Dashboard'),
    (icon: Icons.credit_card_outlined, activeIcon: Icons.credit_card, label: 'Cards'),
    (icon: Icons.receipt_long_outlined, activeIcon: Icons.receipt_long, label: 'Ledger'),
    (icon: Icons.settings_outlined, activeIcon: Icons.settings, label: 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        border: Border(top: BorderSide(color: AppColors.surface3, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: List.generate(_items.length, (i) {
              final item = _items[i];
              final selected = i == selectedIndex;
              return Expanded(
                child: InkWell(
                  onTap: () => onTap(i),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (selected)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.neonCyan.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Icon(item.activeIcon, size: 20, color: AppColors.neonCyan),
                        )
                      else
                        Icon(item.icon, size: 20, color: AppColors.textMuted),
                      const SizedBox(height: 2),
                      Text(
                        item.label,
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                          color: selected ? AppColors.neonCyan : AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
