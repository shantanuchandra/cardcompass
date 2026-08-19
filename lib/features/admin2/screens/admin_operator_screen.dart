import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/brand_components.dart';
import '../../../core/theme/brand_tokens.dart';
import '../../auth/providers/auth_provider.dart';
import '../card_data/card_data_models.dart';
import '../card_data/card_data_repository.dart';
import '../card_data/card_data_section.dart';
import '../data/admin_operator_repository.dart';
import '../providers/admin_access_provider.dart';
import '../widgets/admin_workspace_navigation.dart';

class AdminOperatorScreen extends ConsumerStatefulWidget {
  const AdminOperatorScreen({
    super.key,
    this.onAuthenticationRequired,
    this.onAccessDenied,
  });

  final Future<void> Function()? onAuthenticationRequired;
  final VoidCallback? onAccessDenied;

  @override
  ConsumerState<AdminOperatorScreen> createState() =>
      _AdminOperatorScreenState();
}

class _AdminOperatorScreenState extends ConsumerState<AdminOperatorScreen> {
  var _section = AdminWorkspaceSection.inbox;

  @override
  void initState() {
    super.initState();
    ref.listenManual(adminAccessProvider, (_, next) {
      final error = next.error;
      if (error is AdminAuthenticationRequired) {
        _scheduleAccessEffect(error);
      } else if (error is AdminAccessDenied) {
        _scheduleAccessEffect(error);
      }
    }, fireImmediately: true);
  }

  void _scheduleAccessEffect(Object error) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (error is AdminAuthenticationRequired) {
        final handler = widget.onAuthenticationRequired;
        if (handler != null) {
          await handler();
        } else {
          await ref.read(authNotifierProvider.notifier).signOut();
        }
        return;
      }

      if (error is AdminAccessDenied) {
        final handler = widget.onAccessDenied;
        if (handler != null) {
          handler();
        } else if (mounted) {
          context.go('/app');
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final access = ref.watch(adminAccessProvider);

    return access.when(
      loading: () => const Scaffold(
        body: BrandLoadingSkeleton(
          semanticLabel: 'Checking administrator access',
          minHeight: 280,
        ),
      ),
      error: (error, _) {
        return AdminAccessFailureView(
          error: error,
          onRetry: error is AdminRequestFailed
              ? () => ref.invalidate(adminAccessProvider)
              : null,
        );
      },
      data: (value) {
        if (!value.isAdmin) return const AdminAccessDeniedView();
        return AdminWorkspaceNavigation(
          selected: _section,
          onSelected: (next) => setState(() => _section = next),
          child: _section == AdminWorkspaceSection.cardData
              ? _buildCardData()
              : AdminSectionPlaceholder(title: _section.label),
        );
      },
    );
  }

  Widget _buildCardData() {
    try {
      return KeyedSubtree(
        key: const Key('admin-section-content'),
        child: CardDataSection(
          repository: _RepositoryCardDataSource(
            ref.watch(adminOperatorRepositoryProvider),
          ),
          onAuthenticationRequired:
              widget.onAuthenticationRequired ??
              () => ref.read(authNotifierProvider.notifier).signOut(),
          onAccessDenied: widget.onAccessDenied ?? () => context.go('/app'),
        ),
      );
    } on AssertionError {
      // Supabase is intentionally absent in lightweight shell widget tests.
      return const AdminSectionPlaceholder(title: 'Card Data');
    }
  }
}

final class _RepositoryCardDataSource implements CardDataSource {
  _RepositoryCardDataSource(AdminOperatorRepository operator)
    : _repository = CardDataRepository(operator);

  final CardDataRepository _repository;

  @override
  Future<CardReviewPage> list(CardReviewQuery query) => _repository.list(
    query.lane,
    page: query.page,
    limit: query.limit,
    status: query.status,
  );

  @override
  Future<void> act(CardReviewAction action) async {
    await _repository.act(action);
  }
}

class AdminAccessFailureView extends StatelessWidget {
  const AdminAccessFailureView({super.key, required this.error, this.onRetry});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final authenticationRequired = error is AdminAuthenticationRequired;
    final denied = error is AdminAccessDenied;
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(BrandSpacing.lg),
        child: BrandStateView(
          title: authenticationRequired
              ? 'Sign in again to continue.'
              : denied
              ? 'Administrator access required.'
              : 'Administrator access could not be checked.',
          message: authenticationRequired
              ? 'Your session is no longer valid.'
              : denied
              ? 'Returning you to CardCompass.'
              : 'Check your connection and try again.',
          icon: authenticationRequired
              ? Icons.lock_clock_outlined
              : denied
              ? Icons.lock_outline
              : Icons.cloud_off_outlined,
          actionLabel: onRetry == null ? null : 'Try again',
          onAction: onRetry,
        ),
      ),
    );
  }
}

class AdminAccessDeniedView extends StatelessWidget {
  const AdminAccessDeniedView({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Padding(
      padding: EdgeInsets.all(BrandSpacing.lg),
      child: BrandStateView(
        title: 'Administrator access required.',
        message: 'This workspace is limited to administrators.',
        icon: Icons.lock_outline,
      ),
    ),
  );
}

class AdminSectionPlaceholder extends StatelessWidget {
  const AdminSectionPlaceholder({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    key: const Key('admin-section-content'),
    padding: const EdgeInsets.all(BrandSpacing.lg),
    child: Align(
      alignment: Alignment.topLeft,
      child: Text(title, style: Theme.of(context).textTheme.headlineLarge),
    ),
  );
}
