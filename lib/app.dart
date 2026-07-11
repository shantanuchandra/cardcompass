import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cardcompass/core/theme.dart';
import 'package:cardcompass/config/routes.dart';

/// Global navigator key for accessing context from anywhere in the app
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Main application widget that provides theming, routing, and global configuration
class CardCompassApp extends ConsumerWidget {
  const CardCompassApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'CardCompass',
      debugShowCheckedModeBanner: false,
      
      // Global Navigator Key
      navigatorKey: navigatorKey,
      
      // App Theme Configuration
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      
      // Initial Route
      initialRoute: AppRoutes.splash,
      
      // Global Route Configuration
      onGenerateRoute: AppRoutes.generateRoute,
      
      // Global Builder for error handling and context management
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.0)),
          child: child!,
        );
      },
    );
  }
}
