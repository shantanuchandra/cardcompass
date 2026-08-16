import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/splash_screen.dart';
import '../../features/dashboard/screens/dashboard_screen.dart';
import '../../features/cards/screens/cards_screen.dart';
import '../../features/cards/screens/add_card_screen.dart';
import '../../features/cards/screens/card_detail_screen.dart';
import '../../features/transactions/screens/transactions_screen.dart';
import '../../features/benefits/movie_deals/screens/movie_deals_screen.dart';
import '../../features/settings/screens/settings_screen.dart';
import '../theme/brand_components.dart';
import '../theme/brand_tokens.dart';
import '../../app.dart' show navigatorKey;
import 'app_tab_selection.dart';

const _kTabPaths = [
  '/app',
  '/app/cards',
  '/app/transactions',
  '/app/movie-deals',
  '/app/settings',
];

int _tabIndexFor(String loc) {
  if (loc.startsWith('/app/cards')) return 1;
  if (loc.startsWith('/app/transactions')) return 2;
  if (loc.startsWith('/app/movie-deals')) return 3;
  if (loc.startsWith('/app/settings')) return 4;
  return 0;
}

// The current tab index — a simple ValueNotifier so _AppShell rebuilds on change.
final _tabIndexNotifier = ValueNotifier<int>(0);

NoTransitionPage<void> _appShellPage() => const NoTransitionPage<void>(
  key: ValueKey('app-shell'),
  child: _AppShell(),
);

// Bridges Riverpod's authNotifierProvider to GoRouter's refreshListenable so
// that auth-state ticks (including background token-refresh emissions from
// Supabase's onAuthStateChange, which fire well after login/logout) only
// re-evaluate `redirect` instead of rebuilding the whole GoRouter/Router
// widget subtree — a full router rebuild on every token refresh was tearing
// down and recreating the Navigator, which broke in-app tab-switch taps.
class _AuthRefreshListenable extends ChangeNotifier {
  _AuthRefreshListenable(this._ref) {
    _sub = _ref.listen(authNotifierProvider, (_, _) => notifyListeners());
  }

  final Ref _ref;
  late final ProviderSubscription<AsyncValue<AuthStatus>> _sub;

  @override
  void dispose() {
    _sub.close();
    super.dispose();
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  GoRouter.optionURLReflectsImperativeAPIs = true;
  final refreshListenable = _AuthRefreshListenable(ref);
  ref.onDispose(refreshListenable.dispose);

  return GoRouter(
    navigatorKey: navigatorKey,
    initialLocation: '/',
    refreshListenable: refreshListenable,
    redirect: (context, state) {
      final authState = ref.read(authNotifierProvider);
      if (authState.isLoading) return null;
      final isAuthed = authState.valueOrNull == AuthStatus.authenticated;
      final loc = state.matchedLocation;
      if (Uri.base.fragment.contains('access_token')) return null;
      if (!isAuthed && loc.startsWith('/app')) return '/login';
      if (isAuthed && loc.startsWith('/app')) {
        _tabIndexNotifier.value = _tabIndexFor(loc);
      }
      if (isAuthed && (loc == '/login' || loc == '/')) {
        // Restore tab from URL on initial load
        final fragment = Uri.base.fragment;
        _tabIndexNotifier.value = _tabIndexFor(
          fragment.isEmpty ? '/app' : '/$fragment',
        );
        return '/app';
      }
      if (loc == '/' && !isAuthed) return '/login';
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (_, s) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, s) => const LoginScreen()),
      GoRoute(
        path: '/app',
        pageBuilder: (_, s) => _appShellPage(),
      ),
      GoRoute(
        path: '/app/cards',
        pageBuilder: (_, s) => _appShellPage(),
        routes: [
          // A nested page preserves the app shell beneath Add Card. Cards uses
          // push semantics so both Back and a successful save can pop to the
          // existing list without reconstructing navigation state.
          GoRoute(
            path: 'add',
            pageBuilder: (_, s) =>
                const NoTransitionPage(child: AddCardScreen()),
          ),
          GoRoute(
            path: ':cardId',
            pageBuilder: (_, state) => NoTransitionPage(
              child: CardDetailScreen(cardId: state.pathParameters['cardId']!),
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/app/transactions',
        pageBuilder: (_, s) => _appShellPage(),
      ),
      GoRoute(
        path: '/app/movie-deals',
        pageBuilder: (_, s) => _appShellPage(),
      ),
      GoRoute(
        path: '/app/settings',
        pageBuilder: (_, s) => _appShellPage(),
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
    MovieDealsScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ValueListenableBuilder<int>(
      valueListenable: _tabIndexNotifier,
      builder: (context, tabIndex, _) {
        void onTap(int i) {
          _tabIndexNotifier.value = i;
          context.go(_kTabPaths[i]);
        }

        final isDesktop =
            MediaQuery.sizeOf(context).width >= _kDesktopBreakpoint;

        final shell = isDesktop
            ? Scaffold(
                body: Row(
                  children: [
                    AppSideRail(selectedIndex: tabIndex, onTap: onTap),
                    Expanded(
                      child: IndexedStack(index: tabIndex, children: _bodies),
                    ),
                  ],
                ),
              )
            : Scaffold(
                body: IndexedStack(index: tabIndex, children: _bodies),
                bottomNavigationBar: AppBottomNav(
                  selectedIndex: tabIndex,
                  onTap: onTap,
                ),
              );

        return AppTabSelection(
          onSelect: (tab) => onTap(tab.index),
          child: shell,
        );
      },
    );
  }
}

class AppSideRail extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTap;
  const AppSideRail({
    super.key,
    required this.selectedIndex,
    required this.onTap,
  });

  static const _items = [
    (
      icon: Icons.dashboard_outlined,
      activeIcon: Icons.dashboard,
      label: 'Dashboard',
    ),
    (
      icon: Icons.credit_card_outlined,
      activeIcon: Icons.credit_card,
      label: 'Cards',
    ),
    (
      icon: Icons.receipt_long_outlined,
      activeIcon: Icons.receipt_long,
      label: 'Transactions',
    ),
    (
      icon: Icons.local_movies_outlined,
      activeIcon: Icons.local_movies,
      label: 'Movies',
    ),
    (
      icon: Icons.settings_outlined,
      activeIcon: Icons.settings,
      label: 'Settings',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      decoration: const BoxDecoration(
        color: BrandColors.inkSoft,
        border: Border(right: BorderSide(color: BrandColors.ruleOnInk)),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 24, 20, 32),
              child: Row(
                children: [
                  BrandCompassMark(size: 30),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'CardCompass',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: BrandColors.paper,
                        letterSpacing: -.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            ...List.generate(_items.length, (i) {
              final item = _items[i];
              final selected = i == selectedIndex;
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 3,
                ),
                child: Semantics(
                  selected: selected,
                  button: true,
                  label: item.label,
                  onTap: () => onTap(i),
                  child: ExcludeSemantics(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(BrandRadius.control),
                      onTap: () => onTap(i),
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 48),
                        decoration: BoxDecoration(
                          color: selected
                              ? BrandColors.signal
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(
                            BrandRadius.control,
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              selected ? item.activeIcon : item.icon,
                              size: 19,
                              color: selected
                                  ? BrandColors.ink
                                  : BrandColors.mutedPaper,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                item.label,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: 'Manrope',
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: selected
                                      ? BrandColors.ink
                                      : BrandColors.mutedPaper,
                                ),
                              ),
                            ),
                            if (selected) ...[
                              const SizedBox(width: 8),
                              Container(
                                width: 5,
                                height: 5,
                                decoration: const BoxDecoration(
                                  color: BrandColors.ink,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ],
                          ],
                        ),
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

class AppBottomNav extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTap;
  const AppBottomNav({
    super.key,
    required this.selectedIndex,
    required this.onTap,
  });

  static const _items = [
    (
      icon: Icons.dashboard_outlined,
      activeIcon: Icons.dashboard,
      label: 'Dashboard',
    ),
    (
      icon: Icons.credit_card_outlined,
      activeIcon: Icons.credit_card,
      label: 'Cards',
    ),
    (
      icon: Icons.receipt_long_outlined,
      activeIcon: Icons.receipt_long,
      label: 'Transactions',
    ),
    (
      icon: Icons.local_movies_outlined,
      activeIcon: Icons.local_movies,
      label: 'Movies',
    ),
    (
      icon: Icons.settings_outlined,
      activeIcon: Icons.settings,
      label: 'Settings',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final labelHeight = MediaQuery.textScalerOf(context).scale(14) * 2;
    final navigationHeight = (labelHeight + 44).clamp(76.0, 132.0);

    return Container(
      decoration: const BoxDecoration(
        color: BrandColors.inkSoft,
        border: Border(top: BorderSide(color: BrandColors.ruleOnInk)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: navigationHeight,
          child: Row(
            children: List.generate(_items.length, (i) {
              final item = _items[i];
              final selected = i == selectedIndex;
              return Expanded(
                child: Semantics(
                  selected: selected,
                  button: true,
                  label: item.label,
                  onTap: () => onTap(i),
                  child: ExcludeSemantics(
                    child: InkWell(
                      onTap: () => onTap(i),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            selected ? item.activeIcon : item.icon,
                            size: 20,
                            color: selected
                                ? BrandColors.signal
                                : BrandColors.mutedPaper,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            item.label,
                            style: TextStyle(
                              fontFamily: 'Manrope',
                              fontSize: 14,
                              letterSpacing: -0.6,
                              height: 1,
                              overflow: TextOverflow.visible,
                              fontWeight: FontWeight.w700,
                              color: selected
                                  ? BrandColors.signal
                                  : BrandColors.mutedPaper,
                            ),
                            maxLines: 2,
                            softWrap: true,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
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
