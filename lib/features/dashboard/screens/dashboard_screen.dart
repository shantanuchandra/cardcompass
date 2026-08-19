import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/router/app_tab_selection.dart';
import '../../../core/theme/brand_components.dart';
import '../../../core/theme/brand_tokens.dart';
import '../../../core/theme/category_display.dart';
import '../../../core/providers/supabase_provider.dart';
import '../../../core/providers/repository_providers.dart';
import '../../../core/services/statement_processing_service.dart'
    show buildStatementIssueLines;
import '../../../core/services/card_discovery_service.dart';
import '../../../core/services/card_identity_service.dart';
import '../../../core/services/gmail_sync_service.dart';
import '../../../shared/models/user_card.dart';
import '../../../shared/models/transaction.dart';
import '../../../shared/models/statement.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/dashboard_provider.dart';
import '../providers/gmail_sync_provider.dart';
import '../providers/imported_data_refresh_provider.dart';

typedef GmailReconnect = Future<void> Function();
typedef QueuedRecoveryInitializer = Future<void> Function();

final gmailReconnectProvider = Provider<GmailReconnect>((ref) {
  return () => ref.read(authNotifierProvider.notifier).signInWithGoogle();
});

final _currencyFmt = NumberFormat.currency(
  locale: 'en_IN',
  symbol: '₹',
  decimalDigits: 0,
);
final _shortCurrency = NumberFormat.compactCurrency(
  locale: 'en_IN',
  symbol: '₹',
  decimalDigits: 1,
);

typedef BankCatalogSearch =
    Future<List<Map<String, dynamic>>> Function(String bank, String query);

final bankCatalogSearchProvider = Provider<BankCatalogSearch>((ref) {
  return (bank, query) => ref
      .read(cardsRepositoryProvider)
      .searchCatalogForBank(bank, query: query);
});

typedef CardResolution =
    Future<void> Function(Map<String, dynamic> email, String catalogCardId);

final cardResolutionProvider = Provider<CardResolution>((ref) {
  return (email, catalogCardId) => ref
      .read(cardAssignmentProvider.notifier)
      .resolveWithCatalogEntry(email: email, catalogCardId: catalogCardId);
});

typedef CardUrlResolver =
    Future<CardUrlResolution> Function(
      Map<String, dynamic> email,
      String sourceUrl,
    );

final cardUrlResolverProvider = Provider<CardUrlResolver>((ref) {
  return (email, sourceUrl) {
    final metadata = email['metadata'];
    final safeMetadata = metadata is Map
        ? Map<String, dynamic>.from(metadata)
        : const <String, dynamic>{};
    final rawHints = safeMetadata['identityHints'];
    final hints = rawHints is Map
        ? Map<String, dynamic>.from(rawHints)
        : const <String, dynamic>{};
    final extracted = CardIdentityEvidence.extract(
      issuer: email['bank_detected'] as String? ?? '',
      subject: email['subject'] as String?,
      attachmentFilename:
          safeMetadata['attachmentFilename'] as String? ??
          email['attachment_filename'] as String?,
      pdfHeader: hints['pdfHeaderExcerpt'] as String?,
    );
    final evidence = CardIdentityEvidence(
      issuer: extracted.issuer,
      subjectProduct:
          extracted.subjectProduct ?? hints['productName'] as String?,
      filenameProduct: extracted.filenameProduct,
      pdfHeaderProduct: extracted.pdfHeaderProduct,
      network: extracted.network ?? hints['network'] as String?,
      lastFour: extracted.lastFour ?? hints['last4'] as String?,
      attachmentFilename: extracted.attachmentFilename,
      pdfHeaderExcerpt: extracted.pdfHeaderExcerpt,
      warnings: extracted.warnings,
    );
    return CardDiscoveryService(
      ref.read(supabaseClientProvider),
    ).resolveUrl(evidence, sourceUrl);
  };
});

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key, this.queuedRecoveryInitializer});

  /// Test/embedding seam. Production leaves this null so recovery resolves
  /// through the authenticated Riverpod notifier.
  final QueuedRecoveryInitializer? queuedRecoveryInitializer;

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final initialize =
          widget.queuedRecoveryInitializer ??
          ref.read(gmailSyncProvider.notifier).initializeQueuedRecovery;
      unawaited(initialize());
    });
  }

  @override
  Widget build(BuildContext context) {
    final dashAsync = ref.watch(dashboardProvider);
    final user = ref.watch(currentUserProvider);

    final isDesktop = MediaQuery.sizeOf(context).width >= 1024;

    return Scaffold(
      backgroundColor: BrandColors.paper,
      body: RefreshIndicator(
        color: BrandColors.focusDark,
        backgroundColor: BrandColors.paper,
        onRefresh: () => ref.refresh(dashboardProvider.future),
        child: Center(
          child: BrandContentFrame(
            mode: BrandContentMode.fullWidthData,
            child: CustomScrollView(
              slivers: [
                _DashboardAppBar(user: user),
                dashAsync.when(
                  loading: () =>
                      const SliverFillRemaining(child: _DashboardSkeleton()),
                  error: (_, _) =>
                      const SliverFillRemaining(child: _ErrorState()),
                  data: (data) =>
                      _DashboardContent(data: data, isDesktop: isDesktop),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── App Bar ────────────────────────────────────────────────────────────────
class _DashboardAppBar extends ConsumerWidget {
  final dynamic user;
  const _DashboardAppBar({this.user});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name =
        (user?.userMetadata?['full_name'] as String?)?.split(' ').first ??
        'there';
    final avatar = user?.userMetadata?['avatar_url'] as String?;
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
        ? 'Good afternoon'
        : 'Good evening';
    final syncState = ref.watch(gmailSyncProvider);

    ref.listen(gmailSyncProvider, (previous, next) {
      next.whenOrNull(
        data: (result) {
          if (result == null) return;
          final issueLines = buildStatementIssueLines(result.issues);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result.summaryMessage),
              duration: const Duration(seconds: 8),
              action: issueLines.isEmpty
                  ? null
                  : SnackBarAction(
                      label: 'Details',
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) => Dialog(
                          child: StatementSyncDetails(issueLines: issueLines),
                        ),
                      ),
                    ),
            ),
          );
          ref.read(importedDataRefreshProvider)();
        },
        error: (error, _) {
          final needsReconnect =
              error is GmailAuthException || error is NoGmailTokenException;
          if (needsReconnect) {
            unawaited(ref.read(gmailReconnectProvider)());
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                needsReconnect
                    ? 'Reconnect Gmail to continue syncing.'
                    : 'Couldn\'t sync Gmail. Check your connection and try again.',
              ),
              action: SnackBarAction(
                label: needsReconnect ? 'Reconnect' : 'Try again',
                onPressed: needsReconnect
                    ? ref.read(gmailReconnectProvider)
                    : () => _showSyncRangeDialog(context, ref),
              ),
            ),
          );
        },
      );
    });

    final usesLargeText = MediaQuery.textScalerOf(context).scale(14) >= 21;

    final identity = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$greeting, $name',
          style: const TextStyle(
            fontFamily: 'Manrope',
            fontSize: 13,
            color: BrandColors.mutedInk,
            fontWeight: FontWeight.w400,
          ),
        ),
        Text(
          'CardCompass',
          style: const TextStyle(
            fontFamily: 'Manrope',
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: BrandColors.ink,
            letterSpacing: -0.5,
          ),
        ),
      ],
    );
    final controls = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Sync Gmail',
          onPressed: syncState.isLoading
              ? null
              : () => _showSyncRangeDialog(context, ref),
          icon: syncState.isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: BrandColors.focusDark,
                  ),
                )
              : const Icon(Icons.sync_rounded, color: BrandColors.focusDark),
        ),
        const SizedBox(width: BrandSpacing.sm),
        CircleAvatar(
          radius: 20,
          backgroundColor: BrandColors.paperDeep,
          backgroundImage: avatar != null ? NetworkImage(avatar) : null,
          child: avatar == null
              ? Text(
                  name[0].toUpperCase(),
                  style: const TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: BrandColors.focusDark,
                  ),
                )
              : null,
        ),
      ],
    );

    return SliverToBoxAdapter(
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.all(BrandSpacing.md),
          child: usesLargeText
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    identity,
                    const SizedBox(height: BrandSpacing.sm),
                    controls,
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: identity),
                    controls,
                  ],
                ),
        ),
      ),
    );
  }
}

/// Concise, bank-level explanation of statement failures from the latest sync.
class StatementSyncDetails extends StatelessWidget {
  const StatementSyncDetails({required this.issueLines, super.key});

  final List<String> issueLines;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 620, maxHeight: 560),
      child: Padding(
        padding: const EdgeInsets.all(BrandSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Statement issues',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: BrandColors.ink,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close statement issues',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: BrandSpacing.xs),
            const Text(
              'Grouped by bank, possible card, and the stage that needs attention. '
              '“Attachment unavailable” means the older saved email has no Gmail '
              'attachment reference; syncing that date range again can repair it.',
              style: TextStyle(color: BrandColors.mutedInk, height: 1.4),
            ),
            const SizedBox(height: BrandSpacing.lg),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: issueLines.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: BrandSpacing.sm),
                itemBuilder: (context, index) => Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(BrandSpacing.md),
                  decoration: BoxDecoration(
                    color: BrandColors.paper,
                    border: Border.all(color: BrandColors.paperDeep),
                    borderRadius: BorderRadius.circular(BrandRadius.card),
                  ),
                  child: Text(
                    issueLines[index],
                    style: const TextStyle(
                      color: BrandColors.ink,
                      height: 1.45,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void _showSyncRangeDialog(BuildContext context, WidgetRef ref) {
  showGeneralDialog<void>(
    context: context,
    barrierLabel: 'Sync from Gmail',
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    transitionDuration: 220.ms,
    pageBuilder: (dialogContext, _, _) => _SyncRangeDialog(
      onStartSync: (days) {
        Navigator.of(dialogContext).pop();
        ref.read(gmailSyncProvider.notifier).syncGmail(lookbackDays: days);
      },
    ),
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween(begin: 0.94, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _SyncRangeOption {
  final int days;
  final String label;
  const _SyncRangeOption(this.days, this.label);
}

class _SyncRangeDialog extends StatefulWidget {
  final void Function(int days) onStartSync;
  const _SyncRangeDialog({required this.onStartSync});

  @override
  State<_SyncRangeDialog> createState() => _SyncRangeDialogState();
}

class _SyncRangeDialogState extends State<_SyncRangeDialog> {
  int _selectedDays = 7;
  static final _options = gmailSyncLookbackDays.entries
      .map((entry) => _SyncRangeOption(entry.value, entry.key))
      .toList(growable: false);

  String get _friendlyRange {
    if (_selectedDays >= 365) return 'about a year';
    if (_selectedDays >= 240) return 'about 8 months';
    if (_selectedDays == 7) return 'the past week';
    return 'the past $_selectedDays days';
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 1024;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: BrandSpacing.md,
          vertical: BrandSpacing.xl,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: isDesktop ? 460 : 420),
          child: Material(
            color: Colors.transparent,
            child: Container(
              decoration: BoxDecoration(
                color: BrandColors.paper,
                borderRadius: BorderRadius.circular(BrandRadius.overlay),
                border: Border.all(
                  color: BrandColors.mutedInk.withValues(alpha: 0.12),
                ),
                boxShadow: [
                  BoxShadow(
                    color: BrandColors.focusDark.withValues(alpha: 0.08),
                    blurRadius: 40,
                    spreadRadius: -8,
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      BrandSpacing.lg,
                      BrandSpacing.lg,
                      BrandSpacing.sm,
                      0,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: BrandColors.signal,
                            borderRadius: BorderRadius.circular(
                              BrandRadius.card,
                            ),
                          ),
                          child: const Icon(
                            Icons.sync_rounded,
                            size: 20,
                            color: BrandColors.ink,
                          ),
                        ),
                        const SizedBox(width: BrandSpacing.sm),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Sync from Gmail',
                                  style: TextStyle(
                                    fontFamily: 'Manrope',
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                    color: BrandColors.ink,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Import credit card statements',
                                  style: TextStyle(
                                    fontFamily: 'Manrope',
                                    fontSize: 12.5,
                                    color: BrandColors.mutedInk,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close_rounded, size: 20),
                          color: BrandColors.mutedInk,
                          tooltip: 'Close',
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: BrandSpacing.md),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: BrandSpacing.lg,
                    ),
                    child: Text(
                      'LOOK BACK',
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: BrandColors.mutedInk,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                  const SizedBox(height: BrandSpacing.sm),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: BrandSpacing.lg,
                    ),
                    child: GridView.count(
                      crossAxisCount: 3,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: BrandSpacing.sm,
                      crossAxisSpacing: BrandSpacing.sm,
                      childAspectRatio: 1.7,
                      children: _options.map((opt) {
                        final selected = opt.days == _selectedDays;
                        return _RangeChip(
                          label: opt.label,
                          selected: selected,
                          onTap: () => setState(() => _selectedDays = opt.days),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: BrandSpacing.md),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: BrandSpacing.lg,
                    ),
                    child: AnimatedSwitcher(
                      duration: 200.ms,
                      child: Container(
                        key: ValueKey(_selectedDays),
                        padding: const EdgeInsets.symmetric(
                          horizontal: BrandSpacing.sm,
                          vertical: BrandSpacing.sm,
                        ),
                        decoration: BoxDecoration(
                          color: BrandColors.paperDeep,
                          borderRadius: BorderRadius.circular(BrandRadius.card),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.info_outline_rounded,
                              size: 15,
                              color: BrandColors.mutedInk,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Fetches statement emails from $_friendlyRange',
                                style: TextStyle(
                                  fontFamily: 'Manrope',
                                  fontSize: 12.5,
                                  color: BrandColors.mutedInk,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: BrandSpacing.lg),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      BrandSpacing.lg,
                      0,
                      BrandSpacing.lg,
                      BrandSpacing.lg,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: BrandSpacing.sm),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton.icon(
                            onPressed: () => widget.onStartSync(_selectedDays),
                            icon: const Icon(Icons.sync_rounded, size: 18),
                            label: const Text('Sync now'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RangeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _RangeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(BrandRadius.card),
        child: AnimatedContainer(
          duration: 180.ms,
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: selected
                ? BrandColors.focusDark.withValues(alpha: 0.15)
                : BrandColors.paperDeep,
            borderRadius: BorderRadius.circular(BrandRadius.card),
            border: Border.all(
              color: selected
                  ? BrandColors.focusDark
                  : BrandColors.mutedInk.withValues(alpha: 0.18),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: selected ? BrandColors.focusDark : BrandColors.mutedInk,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Main Content ───────────────────────────────────────────────────────────
class _DashboardContent extends StatelessWidget {
  final DashboardData data;
  final bool isDesktop;
  const _DashboardContent({required this.data, required this.isDesktop});

  @override
  Widget build(BuildContext context) {
    final cardsSection = data.cards.isEmpty
        ? const SizedBox.shrink()
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DashboardSectionHeader(
                title: 'Your Cards',
                action: 'Manage cards',
                onTap: () => AppTabSelection.of(context).select(AppTab.cards),
              ),
              _CardsCarousel(
                cards: data.cards,
                statements: data.latestStatements,
              ).animate(delay: 100.ms).fadeIn().slideX(begin: 0.05),
            ],
          );

    final billsSection = data.latestStatements.isNotEmpty
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DashboardSectionHeader(
                title: 'Statement balances',
                action: null,
                onTap: null,
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(
                  BrandSpacing.md,
                  0,
                  BrandSpacing.md,
                  BrandSpacing.sm,
                ),
                child: Text(
                  "Issuer statement balances may include earlier cycles, EMIs, fees, or interest; they are not this month's purchases.",
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 12,
                    height: 1.4,
                    color: BrandColors.mutedInk,
                  ),
                ),
              ),
              _BillsPanel(
                cards: data.cards,
                statements: data.latestStatements,
              ).animate(delay: 150.ms).fadeIn(),
            ],
          )
        : const SizedBox.shrink();

    final statementsUnavailable = data.cards.isEmpty
        ? const SizedBox.shrink()
        : const Padding(
            padding: EdgeInsets.symmetric(horizontal: BrandSpacing.md),
            child: BrandActionRow(
              title: 'Statement history',
              description: 'Statement history is not available here yet.',
              leading: Icon(Icons.description_outlined),
              unavailable: true,
            ),
          );

    final transactionsSection = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DashboardSectionHeader(
          title: 'Recent Spend',
          action: 'View all transactions',
          onTap: () => AppTabSelection.of(context).select(AppTab.transactions),
        ),
        data.recentTransactions.isEmpty
            ? _EmptyTransactions().animate(delay: 200.ms).fadeIn()
            : _RecentTransactions(
                transactions: data.recentTransactions,
              ).animate(delay: 200.ms).fadeIn(),
      ],
    );

    if (isDesktop) {
      return SliverList(
        delegate: SliverChildListDelegate([
          _DashboardOverview(
            data: data,
          ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1),
          const SizedBox(height: BrandSpacing.lg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    cardsSection,
                    const SizedBox(height: BrandSpacing.lg),
                    billsSection,
                    if (data.latestStatements.isEmpty) ...[
                      const SizedBox(height: BrandSpacing.lg),
                      statementsUnavailable,
                    ],
                  ],
                ),
              ),
              const SizedBox(width: BrandSpacing.lg),
              Expanded(flex: 2, child: transactionsSection),
            ],
          ),
          const SizedBox(height: BrandSpacing.xxl),
        ]),
      );
    }

    return SliverList(
      delegate: SliverChildListDelegate([
        _DashboardOverview(
          data: data,
        ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1),
        const SizedBox(height: BrandSpacing.lg),
        cardsSection,
        const SizedBox(height: BrandSpacing.lg),
        if (data.latestStatements.isNotEmpty) ...[
          billsSection,
          const SizedBox(height: BrandSpacing.lg),
        ],
        if (data.latestStatements.isEmpty && data.cards.isNotEmpty) ...[
          statementsUnavailable,
          const SizedBox(height: BrandSpacing.lg),
        ],
        transactionsSection,
        const SizedBox(height: BrandSpacing.xxl),
      ]),
    );
  }
}

// ─── Decision overview ──────────────────────────────────────────────────────
class _DashboardOverview extends StatelessWidget {
  final DashboardData data;
  const _DashboardOverview({required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.cards.isEmpty) {
      return BrandContentFrame(
        child: Padding(
          padding: const EdgeInsets.only(top: BrandSpacing.md),
          child: BrandStateView(
            title: 'Build your dashboard',
            message:
                'Add a credit card to see spending, limits, and rewards in one place.',
            icon: Icons.add_card_rounded,
            actionLabel: 'Add a card',
            onAction: () => AppTabSelection.of(context).select(AppTab.cards),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BrandContentFrame(
          mode: BrandContentMode.fullWidthData,
          child: Padding(
            padding: const EdgeInsets.only(top: BrandSpacing.md),
            child: _DashboardMetrics(data: data),
          ),
        ),
      ],
    );
  }
}

class _DashboardMetrics extends StatelessWidget {
  final DashboardData data;
  const _DashboardMetrics({required this.data});

  @override
  Widget build(BuildContext context) {
    final cardCount = data.cards.length;
    final chips = [
      _MetricChip(
        key: const Key('primary-spend-metric'),
        icon: Icons.credit_card_rounded,
        tone: _MetricTone.primary,
        label: "This month's spend",
        value: _shortCurrency.format(data.monthlySpend),
        trend: data.monthlySpendTrend,
        trendMonths: data.trendMonths,
      ),
      _MetricChip(
        key: const Key('supporting-rewards-metric'),
        icon: Icons.star_rounded,
        tone: _MetricTone.reward,
        label: 'Rewards earned',
        value: _shortCurrency.format(data.rewardsEarned),
        trend: data.monthlyRewardsTrend,
        trendMonths: data.trendMonths,
      ),
      _MetricChip(
        key: const Key('supporting-limit-metric'),
        icon: Icons.crop_square_rounded,
        tone: _MetricTone.limit,
        label: 'Reported card limits',
        value: _shortCurrency.format(data.totalCreditLimit),
        // No month-over-month history exists for a card's credit limit
        // (it's a live snapshot, not a transaction-derived figure) — show
        // the chip without a trend rather than fabricate one.
        trend: null,
        supportingText:
            '$cardCount card${cardCount == 1 ? '' : 's'} · issuer limits may overlap',
      ),
    ];

    final usesLargeText = MediaQuery.textScalerOf(context).scale(14) >= 21;
    return LayoutBuilder(
      builder: (context, constraints) {
        final stack = constraints.maxWidth < 560 || usesLargeText;
        if (stack) {
          return Column(
            children: [
              for (var i = 0; i < chips.length; i++) ...[
                if (i > 0) const SizedBox(height: BrandSpacing.sm),
                chips[i],
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < chips.length; i++) ...[
              if (i > 0) const SizedBox(width: BrandSpacing.sm),
              Expanded(child: chips[i]),
            ],
          ],
        );
      },
    );
  }
}

enum _MetricTone { primary, reward, limit }

class _MetricChip extends StatelessWidget {
  final IconData icon;
  final _MetricTone tone;
  final String label;
  final String value;
  final List<double>? trend;
  final List<DateTime>? trendMonths;
  final String? supportingText;

  const _MetricChip({
    super.key,
    required this.icon,
    required this.tone,
    required this.label,
    required this.value,
    required this.trend,
    this.trendMonths,
    this.supportingText,
  });

  @override
  Widget build(BuildContext context) {
    final (dotColor, dotOnColor, barColor) = switch (tone) {
      _MetricTone.primary => (
        BrandColors.focusDark,
        BrandColors.signal,
        BrandColors.focusDark,
      ),
      _MetricTone.reward => (
        BrandColors.reward,
        BrandColors.rewardInk,
        BrandColors.rewardInk,
      ),
      _MetricTone.limit => (
        BrandColors.ledger,
        BrandColors.focusDark,
        BrandColors.mutedInk,
      ),
    };

    return Semantics(
      label: '$label: $value',
      child: ExcludeSemantics(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(BrandSpacing.md),
          decoration: BoxDecoration(
            color: BrandColors.paperDeep,
            borderRadius: BorderRadius.circular(BrandRadius.overlay),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: dotColor,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: 16, color: dotOnColor),
                  ),
                  const SizedBox(width: BrandSpacing.compact),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          label.toUpperCase(),
                          style: const TextStyle(
                            fontFamily: 'Manrope',
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                            color: BrandColors.mutedInk,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          value,
                          style: const TextStyle(
                            fontFamily: 'IBM Plex Mono',
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: BrandColors.ink,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (trend != null && trend!.any((v) => v > 0)) ...[
                const SizedBox(height: BrandSpacing.compact),
                SizedBox(
                  height: 32,
                  child: _MonthBars(
                    values: trend!,
                    months: trendMonths,
                    color: barColor,
                  ),
                ),
              ] else if (supportingText != null) ...[
                const SizedBox(height: BrandSpacing.xs),
                Text(
                  supportingText!,
                  style: const TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 12,
                    color: BrandColors.mutedInk,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

final _monthLabelFmt = DateFormat('MMM yyyy');

/// Discrete monthly bars (oldest → newest), current month at full opacity
/// so it reads unambiguously as "you are here." Hovering (or tapping, for
/// touch) a bar reveals its real month and value — no data is invented,
/// this only surfaces what's already in [values]/[months].
class _MonthBars extends StatefulWidget {
  final List<double> values;
  final List<DateTime>? months;
  final Color color;
  const _MonthBars({required this.values, this.months, required this.color});

  @override
  State<_MonthBars> createState() => _MonthBarsState();
}

class _MonthBarsState extends State<_MonthBars> {
  int? _hovered;

  void _setHovered(int? index) {
    if (_hovered == index) return;
    setState(() => _hovered = index);
  }

  @override
  Widget build(BuildContext context) {
    final values = widget.values;
    final months = widget.months;
    final color = widget.color;
    final maxValue = values.fold<double>(0, (m, v) => v > m ? v : m);
    final hovered = _hovered;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < values.length; i++) ...[
              if (i > 0) const SizedBox(width: 3),
              Expanded(
                child: MouseRegion(
                  onEnter: (_) => _setHovered(i),
                  onExit: (_) => _setHovered(null),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(2),
                      ),
                      onTap: () => _setHovered(hovered == i ? null : i),
                      child: AnimatedScale(
                        scale: hovered == i ? 1.06 : 1.0,
                        duration: BrandMotion.standard,
                        curve: Curves.easeOut,
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          heightFactor: maxValue <= 0
                              ? 0.05
                              : (0.12 + 0.88 * (values[i] / maxValue)).clamp(
                                  0.05,
                                  1.0,
                                ),
                          alignment: Alignment.bottomCenter,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: color.withValues(
                                alpha: i == values.length - 1
                                    ? 1.0
                                    : (hovered == i ? 0.55 : 0.28),
                              ),
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(2),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        if (hovered != null)
          Positioned(
            bottom: 38,
            left: 0,
            right: 0,
            child: Center(
              child: IgnorePointer(
                child: _MonthBarTooltip(
                  month: months != null && hovered < months.length
                      ? _monthLabelFmt.format(months[hovered])
                      : null,
                  value: _shortCurrency.format(values[hovered]),
                  color: color,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _MonthBarTooltip extends StatelessWidget {
  final String? month;
  final String value;
  final Color color;
  const _MonthBarTooltip({
    required this.month,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: BrandSpacing.sm,
        vertical: BrandSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: BrandColors.ink,
        borderRadius: BorderRadius.circular(BrandRadius.control),
        boxShadow: [
          BoxShadow(
            color: BrandColors.ink.withValues(alpha: 0.25),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (month != null) ...[
            Text(
              month!,
              style: const TextStyle(
                fontFamily: 'Manrope',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: BrandColors.mutedPaper,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            value,
            style: TextStyle(
              fontFamily: 'IBM Plex Mono',
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Section Header ─────────────────────────────────────────────────────────
class DashboardSectionHeader extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onTap;

  const DashboardSectionHeader({
    super.key,
    required this.title,
    required this.action,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final usesLargeText = MediaQuery.textScalerOf(context).scale(14) >= 21;
    final titleWidget = Text(
      title,
      style: const TextStyle(
        fontFamily: 'Fraunces',
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: BrandColors.ink,
      ),
    );
    final actionWidget = action == null
        ? null
        : TextButton(
            onPressed: onTap,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(44, 44),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              action!,
              style: const TextStyle(
                fontFamily: 'Manrope',
                fontSize: 13,
                color: BrandColors.focusDark,
                fontWeight: FontWeight.w500,
              ),
            ),
          );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        BrandSpacing.md,
        0,
        BrandSpacing.md,
        BrandSpacing.sm,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stack = usesLargeText || constraints.maxWidth < 440;
          if (stack) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [titleWidget, ?actionWidget],
            );
          }
          return Row(children: [titleWidget, const Spacer(), ?actionWidget]);
        },
      ),
    );
  }
}

// ─── Cards Carousel ─────────────────────────────────────────────────────────
class _CardsCarousel extends ConsumerStatefulWidget {
  final List<UserCard> cards;
  final Map<String, Statement> statements;
  const _CardsCarousel({required this.cards, required this.statements});

  @override
  ConsumerState<_CardsCarousel> createState() => _CardsCarouselState();
}

class _CardsCarouselState extends ConsumerState<_CardsCarousel> {
  int _current = 0;
  PageController? _controller;
  double? _controllerViewportFraction;

  // Real credit cards are ISO/IEC 7810 ID-1: 85.60mm x 53.98mm ≈ 1.586:1.
  static const _cardAspectRatio = 1.586;
  static const _maxCardWidth = 340.0;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pending = ref.watch(pendingCardAssignmentsProvider).valueOrNull ?? [];
    final itemCount = widget.cards.length + pending.length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final usesLargeText = MediaQuery.textScalerOf(context).scale(14) >= 21;
        final preferredWidth = usesLargeText
            ? constraints.maxWidth
            : constraints.maxWidth * 0.6;
        final cardWidth = math.min(preferredWidth, _maxCardWidth);
        final cardHeight = math
            .max(cardWidth / _cardAspectRatio, usesLargeText ? 340.0 : 180.0)
            .toDouble();
        final viewportFraction =
            ((cardWidth + BrandSpacing.sm) / constraints.maxWidth).clamp(
              0.3,
              0.9,
            );

        // Only replace the controller when the viewport math actually
        // changes (e.g. window resize) — recreating it on every rebuild
        // (which happens whenever pendingCardAssignmentsProvider refreshes)
        // resets the user's scroll position back to page 0 mid-swipe.
        if (_controller == null ||
            _controllerViewportFraction != viewportFraction) {
          _controller?.dispose();
          _controller = PageController(
            viewportFraction: viewportFraction,
            initialPage: _current,
          );
          _controllerViewportFraction = viewportFraction;
        }

        return Column(
          children: [
            SizedBox(
              height: cardHeight,
              child: ScrollConfiguration(
                behavior: const MaterialScrollBehavior().copyWith(
                  dragDevices: const {
                    PointerDeviceKind.touch,
                    PointerDeviceKind.mouse,
                    PointerDeviceKind.stylus,
                    PointerDeviceKind.trackpad,
                  },
                ),
                child: PageView.builder(
                  itemCount: itemCount,
                  padEnds: false,
                  controller: _controller,
                  onPageChanged: (i) => setState(() => _current = i),
                  itemBuilder: (context, i) {
                    final isPending = i >= widget.cards.length;
                    final tile = isPending
                        ? _PendingBankTile(
                            email: pending[i - widget.cards.length],
                          )
                        : Semantics(
                            key: Key('dashboard-card-${widget.cards[i].id}'),
                            label:
                                'Open ${widget.cards[i].displayName} card details',
                            button: true,
                            onTap: () => context.push(
                              '/cards/${Uri.encodeComponent(widget.cards[i].id)}',
                            ),
                            child: ExcludeSemantics(
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () => context.push(
                                    '/cards/${Uri.encodeComponent(widget.cards[i].id)}',
                                  ),
                                  borderRadius: BorderRadius.circular(
                                    BrandRadius.overlay,
                                  ),
                                  child: _CreditCardTile(card: widget.cards[i]),
                                ),
                              ),
                            ),
                          );
                    return Padding(
                      padding: EdgeInsets.only(
                        left: i == 0 ? BrandSpacing.md : BrandSpacing.sm,
                        right: i == itemCount - 1
                            ? BrandSpacing.md
                            : BrandSpacing.sm,
                      ),
                      child: SizedBox(width: cardWidth, child: tile),
                    );
                  },
                ),
              ),
            ),
            if (itemCount > 1) ...[
              const SizedBox(height: BrandSpacing.sm),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  itemCount,
                  (i) => AnimatedContainer(
                    duration: 250.ms,
                    width: i == _current ? 20 : 6,
                    height: 6,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: i == _current
                          ? BrandColors.focusDark
                          : BrandColors.mutedInk.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(BrandRadius.pill),
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

// A dim, outlined placeholder tile for a statement whose bank couldn't be
// matched to any card on file. Tapping the warning badge opens a typeahead
// search over that bank's card_catalog entries to resolve it.
class _PendingBankTile extends StatelessWidget {
  final Map<String, dynamic> email;
  const _PendingBankTile({required this.email});

  @override
  Widget build(BuildContext context) {
    final bankDetected = email['bank_detected'] as String? ?? 'Unknown bank';
    final metadata = email['metadata'];
    final hints = metadata is Map && metadata['identityHints'] is Map
        ? Map<String, dynamic>.from(metadata['identityHints'] as Map)
        : const <String, dynamic>{};
    final last4 = hints['last4'] as String?;
    final productName = hints['productName'] as String?;
    final dueDate = DateTime.tryParse(hints['dueDate'] as String? ?? '');
    final statementDate = DateTime.tryParse(
      hints['statementDate'] as String? ?? '',
    );
    final receivedDate = DateTime.tryParse(
      email['received_date'] as String? ?? '',
    );
    final totalAmount = hints['totalAmount'];
    final subject = (email['subject'] as String?)?.trim();
    final attachmentFilename =
        hints['attachmentFilename'] as String? ??
        (metadata is Map ? metadata['attachmentFilename'] as String? : null);
    final sourceDate = statementDate ?? receivedDate;
    final hasEvidence =
        hints.isNotEmpty ||
        (subject?.isNotEmpty ?? false) ||
        sourceDate != null ||
        (attachmentFilename?.isNotEmpty ?? false);
    final amountDue = totalAmount is num && dueDate != null
        ? '${NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2).format(totalAmount)} due ${DateFormat('d MMM').format(dueDate)}'
        : null;
    return Container(
      decoration: BoxDecoration(
        color: BrandColors.paperDeep,
        borderRadius: BorderRadius.circular(BrandRadius.overlay),
        border: Border.all(
          color: BrandColors.rewardInk.withValues(alpha: 0.4),
          width: 1.5,
          style: BorderStyle.solid,
        ),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: BrandSpacing.lg,
        vertical: BrandSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  last4 == null ? bankDetected : '$bankDetected •••• $last4',
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 12,
                    color: BrandColors.mutedInk,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                key: Key('resolve-bank-${email['email_id'] ?? bankDetected}'),
                tooltip: 'Resolve $bankDetected card',
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                onPressed: () => _showBankResolveDialog(context, email),
                icon: Icon(
                  Icons.priority_high_rounded,
                  size: 20,
                  color: BrandColors.rewardInk,
                  semanticLabel: 'Resolve $bankDetected card',
                ),
              ),
            ],
          ),
          if (hasEvidence) ...[
            if (productName != null)
              Text(
                'Possible card: $productName',
                style: const TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: BrandColors.ink,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            if (subject != null && subject.isNotEmpty) ...[
              if (productName != null) const SizedBox(height: BrandSpacing.xs),
              Text(
                subject,
                style: const TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 12,
                  color: BrandColors.ink,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (amountDue != null) ...[
              const SizedBox(height: BrandSpacing.xs),
              Text(
                amountDue,
                style: const TextStyle(
                  fontFamily: 'IBM Plex Mono',
                  fontSize: 12,
                  color: BrandColors.mutedInk,
                ),
              ),
            ],
            if (amountDue == null && sourceDate != null)
              Text(
                'Statement email · ${DateFormat('d MMM').format(sourceDate)}',
                style: const TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 12,
                  color: BrandColors.mutedInk,
                ),
              ),
            if (attachmentFilename != null &&
                attachmentFilename.isNotEmpty) ...[
              const SizedBox(height: BrandSpacing.xs),
              Text(
                attachmentFilename,
                style: const TextStyle(
                  fontFamily: 'IBM Plex Mono',
                  fontSize: 12,
                  color: BrandColors.mutedInk,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const Spacer(),
            TextButton.icon(
              onPressed: () => _showBankResolveDialog(context, email),
              icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
              label: const Text('Confirm card'),
            ),
          ] else ...[
            const Spacer(),
            Icon(
              Icons.help_outline_rounded,
              size: 28,
              color: BrandColors.mutedInk.withValues(alpha: 0.5),
            ),
            const SizedBox(height: BrandSpacing.sm),
            Text(
              'Which card is this?',
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 13,
                color: BrandColors.mutedInk,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

void _showBankResolveDialog(BuildContext context, Map<String, dynamic> email) {
  final bankDetected = email['bank_detected'] as String? ?? '';
  showDialog<void>(
    context: context,
    builder: (dialogContext) =>
        _BankResolveDialog(email: email, bankDetected: bankDetected),
  );
}

class _BankResolveDialog extends ConsumerStatefulWidget {
  final Map<String, dynamic> email;
  final String bankDetected;
  const _BankResolveDialog({required this.email, required this.bankDetected});

  @override
  ConsumerState<_BankResolveDialog> createState() => _BankResolveDialogState();
}

class _BankResolveDialogState extends ConsumerState<_BankResolveDialog> {
  List<Map<String, dynamic>> _options = [];
  bool _loading = true;
  bool _resolving = false;
  bool _needsGmailReconnect = false;
  String? _error;
  String _lastQuery = '';
  Map<String, dynamic>? _retryResolution;
  int _searchGeneration = 0;
  final TextEditingController _urlController = TextEditingController();
  bool _showUrlFallback = false;
  bool _urlResolving = false;
  String? _urlMessage;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _searchGeneration++;
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _resolveUrl() async {
    if (_urlResolving || _resolving) return;
    final rawUrl = _urlController.text.trim();
    final uri = Uri.tryParse(rawUrl);
    if (uri == null ||
        uri.scheme.toLowerCase() != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      setState(() => _urlMessage = 'Enter a valid HTTPS card page URL.');
      return;
    }
    setState(() {
      _urlResolving = true;
      _urlMessage = null;
    });
    try {
      final result = await ref.read(cardUrlResolverProvider)(
        widget.email,
        rawUrl,
      );
      if (!mounted) return;
      if (result.isResolved) {
        await _resolve({'id': result.resolvedCardId});
      } else {
        setState(() => _urlMessage = result.userMessage);
      }
    } on CardUrlResolutionException catch (error) {
      if (mounted) setState(() => _urlMessage = error.userMessage);
    } catch (_) {
      if (mounted) {
        setState(
          () => _urlMessage = 'Could not verify this card page. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _urlResolving = false);
    }
  }

  Future<void> _search(String query) async {
    final generation = ++_searchGeneration;
    _lastQuery = query;
    setState(() {
      _loading = true;
      _error = null;
      _retryResolution = null;
    });
    try {
      final results = await ref.read(bankCatalogSearchProvider)(
        widget.bankDetected,
        query,
      );
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _options = results;
        _error = null;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _error =
            'Could not load matching cards. Check your connection and try again.';
        _loading = false;
      });
    }
  }

  Future<void> _resolve(Map<String, dynamic> catalogEntry) async {
    if (_resolving) return;
    final resolveCard = ref.read(cardResolutionProvider);
    final refreshImportedData = ref.read(importedDataRefreshProvider);
    setState(() {
      _resolving = true;
      _needsGmailReconnect = false;
      _error = null;
      _retryResolution = catalogEntry;
    });
    try {
      await resolveCard(widget.email, catalogEntry['id'] as String);
      refreshImportedData();
      if (!mounted) return;
      setState(() {
        _error = null;
        _retryResolution = null;
      });
      Navigator.of(context).pop();
    } on NoGmailTokenException {
      if (mounted) {
        setState(() {
          _needsGmailReconnect = true;
          _error = 'Reconnect Gmail to download and process this statement.';
        });
        unawaited(ref.read(gmailReconnectProvider)());
      }
    } on GmailAuthException {
      if (mounted) {
        setState(() {
          _needsGmailReconnect = true;
          _error = 'Reconnect Gmail to download and process this statement.';
        });
        unawaited(ref.read(gmailReconnectProvider)());
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not assign this card. Try again.');
      }
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final metadata = widget.email['metadata'];
    final hints = metadata is Map && metadata['identityHints'] is Map
        ? Map<String, dynamic>.from(metadata['identityHints'] as Map)
        : const <String, dynamic>{};
    final productName = hints['productName'] as String?;
    final last4 = hints['last4'] as String?;
    return Dialog(
      backgroundColor: BrandColors.paper,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BrandRadius.overlay),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 480),
        child: Padding(
          padding: const EdgeInsets.all(BrandSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Which card is this?',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: BrandColors.ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${widget.bankDetected}${last4 == null ? '' : ' · •••• $last4'}${productName == null ? '' : ' · $productName'}',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 12.5,
                  color: BrandColors.mutedInk,
                ),
              ),
              const SizedBox(height: BrandSpacing.md),
              TextField(
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Type to search ${widget.bankDetected} cards…',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                ),
                onChanged: _search,
              ),
              const SizedBox(height: BrandSpacing.sm),
              Flexible(
                child: _loading
                    ? const Padding(
                        padding: EdgeInsets.symmetric(
                          vertical: BrandSpacing.xl,
                        ),
                        child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : _error != null
                    ? Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: BrandSpacing.lg,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _error!,
                              style: TextStyle(
                                fontFamily: 'Manrope',
                                fontSize: 14,
                                color: BrandColors.error,
                              ),
                            ),
                            const SizedBox(height: BrandSpacing.sm),
                            TextButton(
                              onPressed: _resolving
                                  ? null
                                  : _needsGmailReconnect
                                  ? ref.read(gmailReconnectProvider)
                                  : _retryResolution == null
                                  ? () => _search(_lastQuery)
                                  : () => _resolve(_retryResolution!),
                              child: Text(
                                _needsGmailReconnect
                                    ? 'Reconnect Gmail'
                                    : _retryResolution == null
                                    ? 'Retry search'
                                    : 'Retry assignment',
                              ),
                            ),
                          ],
                        ),
                      )
                    : _options.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: BrandSpacing.lg,
                        ),
                        child: Text(
                          'No matching card found. Try a different search.',
                          style: TextStyle(
                            fontFamily: 'Manrope',
                            fontSize: 12.5,
                            color: BrandColors.mutedInk,
                          ),
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: _options.length,
                        itemBuilder: (context, i) {
                          final entry = _options[i];
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              entry['card_name'] as String? ?? '',
                              style: TextStyle(
                                fontFamily: 'Manrope',
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: BrandColors.ink,
                              ),
                            ),
                            subtitle: Text(
                              entry['bank'] as String? ?? '',
                              style: TextStyle(
                                fontFamily: 'Manrope',
                                fontSize: 12,
                                color: BrandColors.mutedInk,
                              ),
                            ),
                            trailing: _resolving
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(
                                    Icons.chevron_right_rounded,
                                    color: BrandColors.mutedInk,
                                  ),
                            onTap: _resolving ? null : () => _resolve(entry),
                          );
                        },
                      ),
              ),
              const SizedBox(height: BrandSpacing.sm),
              TextButton.icon(
                onPressed: _urlResolving
                    ? null
                    : () => setState(() {
                        _showUrlFallback = !_showUrlFallback;
                        _urlMessage = null;
                      }),
                icon: Icon(
                  _showUrlFallback
                      ? Icons.expand_less_rounded
                      : Icons.link_rounded,
                  size: 18,
                ),
                label: const Text("Can't find it? Paste official card page"),
              ),
              if (_showUrlFallback) ...[
                TextField(
                  key: const Key('official-card-url-field'),
                  controller: _urlController,
                  enabled: !_urlResolving,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    hintText: 'https://bank.example/cards/card-name',
                    prefixIcon: Icon(Icons.language_rounded, size: 20),
                  ),
                  onSubmitted: (_) => _resolveUrl(),
                ),
                const SizedBox(height: BrandSpacing.xs),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: _urlResolving ? null : _resolveUrl,
                    child: _urlResolving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Verify card page'),
                  ),
                ),
                if (_urlMessage != null) ...[
                  const SizedBox(height: BrandSpacing.xs),
                  Text(
                    _urlMessage!,
                    style: TextStyle(
                      fontFamily: 'Manrope',
                      fontSize: 12.5,
                      color: _urlMessage!.contains('reviewing')
                          ? BrandColors.mutedInk
                          : BrandColors.error,
                    ),
                  ),
                ],
              ],
              const SizedBox(height: BrandSpacing.sm),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CreditCardTile extends StatelessWidget {
  final UserCard card;
  const _CreditCardTile({required this.card});

  @override
  Widget build(BuildContext context) {
    final issuerColor = AppTheme.issuerColor(card.bankCode);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(BrandRadius.overlay),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(
              issuerColor.withValues(alpha: 0.16),
              BrandColors.paperDeep,
            ),
            BrandColors.paperDeep,
          ],
          stops: const [0.0, 0.7],
        ),
        border: Border.all(color: issuerColor.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: BrandColors.ink.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(BrandSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(right: BrandSpacing.xs),
                decoration: BoxDecoration(
                  color: issuerColor,
                  shape: BoxShape.circle,
                ),
              ),
              Expanded(
                child: Text(
                  card.bank ?? '',
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 12,
                    color: BrandColors.mutedInk,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                (card.network ?? '').toUpperCase(),
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 12,
                  color: issuerColor,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const Spacer(),
          if (card.lastFourDigits != null)
            Text(
              '••••  ••••  ••••  ${card.lastFourDigits}',
              style: const TextStyle(
                fontFamily: 'IBM Plex Mono',
                fontSize: 18,
                color: BrandColors.ink,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.5,
              ),
            ),
          const SizedBox(height: BrandSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  card.displayName,
                  style: const TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 14,
                    color: BrandColors.ink,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (card.creditLimit != null)
                Text(
                  _currencyFmt.format(card.creditLimit),
                  style: TextStyle(
                    fontFamily: 'IBM Plex Mono',
                    fontSize: 13,
                    color: BrandColors.mutedInk,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Bills Panel ─────────────────────────────────────────────────────────────
class _BillsPanel extends StatelessWidget {
  final List<UserCard> cards;
  final Map<String, Statement> statements;

  const _BillsPanel({required this.cards, required this.statements});

  @override
  Widget build(BuildContext context) {
    final pending = cards
        .where(
          (c) =>
              statements.containsKey(c.id) &&
              !statements[c.id]!.isPaid &&
              statements[c.id]!.outstanding > 0,
        )
        .toList();

    if (pending.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: BrandSpacing.md),
        child: Container(
          padding: const EdgeInsets.all(BrandSpacing.md),
          decoration: BoxDecoration(
            color: BrandColors.successInk.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(BrandRadius.overlay),
            border: Border.all(
              color: BrandColors.successInk.withValues(alpha: 0.25),
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.check_circle_rounded,
                color: BrandColors.successInk,
                size: 20,
              ),
              const SizedBox(width: BrandSpacing.sm),
              Text(
                'All bills paid — you\'re good!',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 14,
                  color: BrandColors.successInk,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: pending.map((card) {
        final stmt = statements[card.id]!;
        final isOverdue = stmt.isOverdue;
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            BrandSpacing.md,
            0,
            BrandSpacing.md,
            BrandSpacing.sm,
          ),
          child: Container(
            padding: const EdgeInsets.all(BrandSpacing.md),
            decoration: BoxDecoration(
              color: BrandColors.paper,
              borderRadius: BorderRadius.circular(BrandRadius.overlay),
              border: Border.all(
                color: isOverdue
                    ? BrandColors.error.withValues(alpha: 0.4)
                    : BrandColors.rewardInk.withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (card.bank != null && card.bank!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(
                            card.bank!,
                            style: TextStyle(
                              fontFamily: 'Manrope',
                              fontSize: 12,
                              color: BrandColors.mutedInk,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      Text(
                        card.displayName,
                        style: TextStyle(
                          fontFamily: 'Manrope',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: BrandColors.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Due ${DateFormat('d MMM').format(stmt.dueDate)}',
                        style: TextStyle(
                          fontFamily: 'Manrope',
                          fontSize: 12,
                          color: isOverdue
                              ? BrandColors.error
                              : BrandColors.mutedInk,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  _currencyFmt.format(stmt.outstanding),
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: isOverdue ? BrandColors.error : BrandColors.ink,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ─── Recent Transactions ─────────────────────────────────────────────────────
class _RecentTransactions extends StatelessWidget {
  final List<Transaction> transactions;
  const _RecentTransactions({required this.transactions});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: BrandSpacing.md),
      child: Column(
        children: transactions.asMap().entries.map((entry) {
          final txn = entry.value;
          return _TransactionRow(txn: txn)
              .animate(delay: Duration(milliseconds: entry.key * 40))
              .fadeIn(duration: 300.ms)
              .slideX(begin: 0.05, duration: 300.ms);
        }).toList(),
      ),
    );
  }
}

class _TransactionRow extends StatelessWidget {
  final Transaction txn;
  const _TransactionRow({required this.txn});

  @override
  Widget build(BuildContext context) {
    final isDebit = txn.isDebit;
    final amount = isDebit
        ? '-${_currencyFmt.format(txn.amount)}'
        : '+${_currencyFmt.format(txn.amount)}';
    final color = isDebit ? BrandColors.ink : BrandColors.successInk;

    return Container(
      margin: const EdgeInsets.only(bottom: BrandSpacing.xs + 2),
      padding: const EdgeInsets.symmetric(
        horizontal: BrandSpacing.md,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: BrandColors.paper,
        borderRadius: BorderRadius.circular(BrandRadius.card),
        border: Border.all(color: BrandColors.mutedInk.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          // Category icon
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _categoryColor(txn.category).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(BrandRadius.control),
            ),
            child: Icon(
              _categoryIcon(txn.category),
              size: 18,
              color: _categoryColor(txn.category),
            ),
          ),
          const SizedBox(width: BrandSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  txn.merchantName ?? txn.description,
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: BrandColors.ink,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  DateFormat(
                    'd MMM · hh:mm a',
                  ).format(txn.transactionDate.toLocal()),
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 12,
                    color: BrandColors.mutedInk,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                amount,
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              if ((txn.rewardEarned ?? 0) > 0)
                Text(
                  '+${txn.rewardEarned!.toStringAsFixed(0)} pts',
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 12,
                    color: BrandColors.reward,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static Color _categoryColor(String? cat) => categoryColor(cat);

  static IconData _categoryIcon(String? cat) => categoryIcon(cat);
}

class _EmptyTransactions extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: BrandSpacing.md),
      child: Container(
        padding: const EdgeInsets.all(BrandSpacing.xl),
        decoration: BoxDecoration(
          color: BrandColors.paper,
          borderRadius: BorderRadius.circular(BrandRadius.overlay),
          border: Border.all(
            color: BrandColors.mutedInk.withValues(alpha: 0.1),
          ),
        ),
        child: Center(
          child: Text(
            'No transactions yet this month',
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 13,
              color: BrandColors.mutedInk,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Loading Skeleton ────────────────────────────────────────────────────────
class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(BrandSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // KPI row skeleton
          Row(
            children: List.generate(
              3,
              (_) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: BrandSpacing.sm),
                  child: _SkeletonBox(height: 90, radius: BrandRadius.overlay),
                ),
              ),
            ),
          ),
          const SizedBox(height: BrandSpacing.lg),
          _SkeletonBox(height: 200, radius: BrandRadius.overlay),
          const SizedBox(height: BrandSpacing.lg),
          ...List.generate(
            5,
            (_) => Padding(
              padding: const EdgeInsets.only(bottom: BrandSpacing.sm),
              child: _SkeletonBox(height: 64, radius: BrandRadius.card),
            ),
          ),
        ],
      ),
    );
  }
}

class _SkeletonBox extends StatefulWidget {
  final double height;
  final double radius;
  const _SkeletonBox({required this.height, required this.radius});

  @override
  State<_SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<_SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final _ctrl = AnimationController(vsync: this, duration: 1200.ms)
    ..repeat(reverse: true);
  late final _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, _) => Container(
        height: widget.height,
        decoration: BoxDecoration(
          color: Color.lerp(
            BrandColors.paper,
            BrandColors.paperDeep,
            _anim.value,
          ),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

// ─── Error State ─────────────────────────────────────────────────────────────
class _ErrorState extends ConsumerWidget {
  const _ErrorState();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return BrandContentFrame(
      child: Padding(
        padding: const EdgeInsets.all(BrandSpacing.xl),
        child: BrandStateView(
          title: 'Couldn\'t load dashboard',
          message: 'Check your connection and try again.',
          icon: Icons.cloud_off_rounded,
          actionLabel: 'Retry',
          onAction: () => ref.invalidate(dashboardProvider),
        ),
      ),
    );
  }
}
