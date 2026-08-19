import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'core/providers/supabase_provider.dart';
import 'features/feedback/feedback_repository.dart';
import 'features/auth/providers/auth_provider.dart';

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
    final auth = ref.watch(authNotifierProvider);
    return MaterialApp.router(
      title: 'CardCompass',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.work,
      routerConfig: router,
      builder: (context, child) => ValueListenableBuilder<RouteInformation>(
        valueListenable: router.routeInformationProvider,
        builder: (context, routeInformation, _) {
          final path = routeInformation.uri.path;
          final content = child ?? const SizedBox.shrink();

          final marketingSurface =
              path == '/login' || (path == '/' && auth.isLoading);
          if (!marketingSurface) {
            return FeedbackRepositoryScope.lazy(
              repositoryFactory: () => FeedbackRepository(
                SupabaseFeedbackApi(ref.read(supabaseClientProvider)),
              ),
              child: content,
            );
          }
          return Theme(data: AppTheme.marketing, child: content);
        },
      ),
    );
  }
}
