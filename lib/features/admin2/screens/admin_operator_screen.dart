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
import '../customers/customer_repository.dart';
import '../customers/customers_section.dart';
import '../inbox/action_inbox_section.dart';
import '../inbox/inbox_models.dart';
import '../inbox/inbox_repository.dart';
import '../feedback/feedback_detail.dart';
import '../feedback/feedback_repository.dart';
import '../feedback/feedback_models.dart';
import '../providers/admin_access_provider.dart';
import '../system/system_models.dart';
import '../system/system_repository.dart';
import '../system/system_section.dart';
import '../widgets/admin_workspace_navigation.dart';

class AdminOperatorScreen extends ConsumerStatefulWidget {
  const AdminOperatorScreen({
    super.key,
    this.onAuthenticationRequired,
    this.onAccessDenied,
    this.cardDataSource,
    this.inboxLoader,
    this.systemSource,
    this.customerSource,
    this.initialCardLane = CardReviewLane.identity,
    this.initialCardTargetId,
    this.initialSectionQuery,
  });

  final Future<void> Function()? onAuthenticationRequired;
  final VoidCallback? onAccessDenied;
  final CardDataSource? cardDataSource;
  final InboxLoader? inboxLoader;
  final SystemDataSource? systemSource;
  final CustomerDataSource? customerSource;
  final CardReviewLane initialCardLane;
  final String? initialCardTargetId;
  final String? initialSectionQuery;

  @override
  ConsumerState<AdminOperatorScreen> createState() =>
      _AdminOperatorScreenState();
}

class _AdminOperatorScreenState extends ConsumerState<AdminOperatorScreen> {
  late AdminWorkspaceSection _section;
  late CardReviewLane _cardLane;
  String? _cardTargetId;
  var _cardSelectionRevision = 0;
  String? _systemControlKey;
  var _systemSelectionRevision = 0;
  String? _feedbackId;
  Future<AdminFeedbackDetail>? _feedbackFuture;
  int _feedbackGeneration = 0;
  int _feedbackEffectGeneration = -1;

  @override
  void initState() {
    super.initState();
    _section =
        widget.initialCardTargetId != null ||
            widget.initialSectionQuery == 'card-data'
        ? AdminWorkspaceSection.cardData
        : AdminWorkspaceSection.inbox;
    _cardLane = widget.initialCardLane;
    _cardTargetId = widget.initialCardTargetId;
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
          child: switch (_section) {
            AdminWorkspaceSection.inbox =>
              _feedbackId == null ? _buildInbox() : _buildFeedback(),
            AdminWorkspaceSection.cardData => _buildCardData(),
            AdminWorkspaceSection.system => _buildSystem(),
            AdminWorkspaceSection.customers => _buildCustomers(),
          },
        );
      },
    );
  }

  Widget _buildCardData() {
    return KeyedSubtree(
      key: const Key('admin-section-content'),
      child: KeyedSubtree(
        key: ValueKey('admin-card-data-$_cardSelectionRevision'),
        child: CardDataSection(
          repository:
              widget.cardDataSource ??
              _RepositoryCardDataSource(
                ref.watch(adminOperatorRepositoryProvider),
              ),
          initialLane: _cardLane,
          initialTargetId: _cardTargetId,
          onAuthenticationRequired:
              widget.onAuthenticationRequired ??
              () => ref.read(authNotifierProvider.notifier).signOut(),
          onAccessDenied: widget.onAccessDenied ?? () => context.go('/app'),
        ),
      ),
    );
  }

  Widget _buildInbox() => KeyedSubtree(
    key: const Key('admin-section-content'),
    child: ActionInboxSection(
      loadInbox:
          widget.inboxLoader ??
          InboxRepository(ref.watch(adminOperatorRepositoryProvider)).load,
      onOpenCardTarget: _openCardTarget,
      onOpenSystemControl: _openSystemControl,
      onOpenFeedback: _openFeedback,
      onAuthenticationRequired:
          widget.onAuthenticationRequired ??
          () => ref.read(authNotifierProvider.notifier).signOut(),
      onAccessDenied: widget.onAccessDenied ?? () => context.go('/app'),
    ),
  );

  Widget _buildFeedback() {
    final repository = FeedbackAdminRepository(
      ref.watch(adminOperatorRepositoryProvider),
    );
    _feedbackFuture ??= repository.detail(_feedbackId!);
    final generation = _feedbackGeneration;
    return FutureBuilder(
      future: _feedbackFuture,
      builder: (context, snapshot) {
        final error = snapshot.error;
        if (error != null) {
          if (_feedbackEffectGeneration != generation &&
              generation == _feedbackGeneration) {
            _feedbackEffectGeneration = generation;
            if (error is AdminAuthenticationRequired ||
                error is AdminAccessDenied) {
              _scheduleAccessEffect(error);
            }
          }
          return BrandStateView(
            title: error is AdminAuthenticationRequired
                ? 'Sign in again to continue.'
                : error is AdminAccessDenied
                ? 'Administrator access required.'
                : 'Feedback could not be loaded.',
            message: error is AdminAuthenticationRequired
                ? 'Your session is no longer valid.'
                : error is AdminAccessDenied
                ? 'Returning you to CardCompass.'
                : 'Check your connection and retry.',
            icon: Icons.cloud_off_outlined,
            actionLabel: error is AdminRequestFailed ? 'Try again' : null,
            onAction: error is AdminRequestFailed ? _reloadFeedback : null,
          );
        }
        if (!snapshot.hasData) {
          return const BrandLoadingSkeleton(
            semanticLabel: 'Loading feedback detail',
            minHeight: 280,
          );
        }
        return FeedbackDetailView(
          detail: snapshot.data!,
          onAction: (action) async {
            final receipt = await repository.act(action);
            return receipt;
          },
          onRefresh: _reloadFeedback,
          onAuthenticationRequired:
              widget.onAuthenticationRequired ??
              () => ref.read(authNotifierProvider.notifier).signOut(),
          onAccessDenied: widget.onAccessDenied ?? () => context.go('/app'),
        );
      },
    );
  }

  void _openFeedback(AdminInboxDestination destination) {
    setState(() {
      _feedbackId = destination.feedbackId;
      _feedbackFuture = null;
      _feedbackGeneration++;
    });
  }

  Future<void> _reloadFeedback() async {
    if (!mounted || _feedbackId == null) return;
    final repository = FeedbackAdminRepository(
      ref.read(adminOperatorRepositoryProvider),
    );
    setState(() {
      _feedbackGeneration++;
      _feedbackFuture = repository.detail(_feedbackId!);
    });
    try {
      await _feedbackFuture;
    } catch (_) {}
  }

  Widget _buildSystem() => KeyedSubtree(
    key: const Key('admin-section-content'),
    child: KeyedSubtree(
      key: ValueKey('admin-system-$_systemSelectionRevision'),
      child: SystemSection(
        repository:
            widget.systemSource ??
            _RepositorySystemDataSource(
              ref.watch(adminOperatorRepositoryProvider),
            ),
        onAuthenticationRequired:
            widget.onAuthenticationRequired ??
            () => ref.read(authNotifierProvider.notifier).signOut(),
        onAccessDenied: widget.onAccessDenied ?? () => context.go('/app'),
        initialControlKey: _systemControlKey,
      ),
    ),
  );

  Widget _buildCustomers() => KeyedSubtree(
    key: const Key('admin-section-content'),
    child: CustomersSection(
      repository:
          widget.customerSource ??
          CustomerRepository(ref.watch(adminOperatorRepositoryProvider)),
      onAuthenticationRequired:
          widget.onAuthenticationRequired ??
          () => ref.read(authNotifierProvider.notifier).signOut(),
      onAccessDenied: widget.onAccessDenied ?? () => context.go('/app'),
    ),
  );

  void _openCardTarget(AdminInboxDestination destination) {
    setState(() {
      _cardLane = destination.lane!;
      _cardTargetId = destination.targetId!;
      _cardSelectionRevision++;
      _section = AdminWorkspaceSection.cardData;
    });
  }

  void _openSystemControl(AdminInboxDestination destination) {
    setState(() {
      _systemControlKey = destination.controlKey;
      _systemSelectionRevision++;
      _section = AdminWorkspaceSection.system;
    });
  }
}

final class _RepositorySystemDataSource implements SystemDataSource {
  _RepositorySystemDataSource(AdminOperatorRepository operator)
    : _repository = SystemRepository(operator);

  final SystemRepository _repository;

  @override
  Future<SystemJobsPage> jobs(
    SystemJobFamily family, {
    int page = 1,
    int limit = 25,
    String? status,
  }) => _repository.jobs(family, page: page, limit: limit, status: status);

  @override
  Future<void> mutate(SystemMutation mutation) => _repository.mutate(mutation);

  @override
  Future<SystemStatusSnapshot> status() => _repository.status();
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
    targetId: query.targetId,
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
