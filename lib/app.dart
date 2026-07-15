import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cardcompass/core/theme.dart';
import 'package:cardcompass/core/providers/theme_provider.dart';
import 'package:cardcompass/config/routes.dart';

/// Global navigator key for accessing context from anywhere in the app
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Main application widget that provides theming, routing, and global configuration
class CardCompassApp extends ConsumerWidget {
  const CardCompassApp({super.key});

  static const String initialRoute = AppRoutes.splash;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp(
      title: 'CardCompass',
      debugShowCheckedModeBanner: false,

      // Global Navigator Key
      navigatorKey: navigatorKey,

      // App Theme Configuration
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,

      // Initial Route
      initialRoute: AppRoutes.startupRoute(
        defaultRouteName:
            WidgetsBinding.instance.platformDispatcher.defaultRouteName,
        webHash: Uri.base.fragment,
      ),
      onGenerateInitialRoutes: AppRoutes.generateInitialRoutes,

      // Global Route Configuration
      onGenerateRoute: AppRoutes.generateRoute,

      // Global Builder for error handling and context management
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.0)),
          // SelectionArea needs an Overlay ancestor (SelectableRegion asserts
          // on this at build time) and MaterialApp's own Overlay lives inside
          // its Navigator, below this builder — not above it. A dedicated
          // Overlay here gives SelectionArea somewhere valid to mount.
          child: Overlay(
            initialEntries: [
              OverlayEntry(builder: (context) => SelectionArea(child: child!)),
            ],
          ),
        );
      },
    );
  }
}
