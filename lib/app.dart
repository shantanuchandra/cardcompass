import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';

/// Global navigator key so services (Gmail sync's password/DOB dialogs) can
/// show a dialog mid-async-flow without a BuildContext being threaded
/// through every call site. Passed to GoRouter (not MaterialApp.router,
/// whose navigatorKey is hardcoded to null when using routerConfig) in
/// app_router.dart.
final navigatorKey = GlobalKey<NavigatorState>();

class CardCompassApp extends ConsumerWidget {
  const CardCompassApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'CardCompass',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.editorial,
      routerConfig: router,
      builder: (context, child) => SelectionArea(
        child: MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.0)),
          child: child!,
        ),
      ),
    );
  }
}
