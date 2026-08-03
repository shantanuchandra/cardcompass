import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/supabase_provider.dart';
import '../../../core/providers/repository_providers.dart';
import '../../../shared/models/user_card.dart';
import '../../../shared/models/transaction.dart';
import '../../../shared/models/statement.dart';
import '../../cards/screens/card_detail_screen.dart';
import '../providers/dashboard_provider.dart';
import '../providers/gmail_sync_provider.dart';

final _currencyFmt = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
final _shortCurrency = NumberFormat.compactCurrency(locale: 'en_IN', symbol: '₹', decimalDigits: 1);

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashAsync = ref.watch(dashboardProvider);
    final user = ref.watch(currentUserProvider);

    final isDesktop = MediaQuery.sizeOf(context).width >= 1024;

    return Scaffold(
      backgroundColor: AppColors.surfaceVoid,
      body: RefreshIndicator(
        color: AppColors.neonCyan,
        backgroundColor: AppColors.surface1,
        onRefresh: () => ref.refresh(dashboardProvider.future),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: isDesktop ? 1120 : double.infinity),
            child: CustomScrollView(
              slivers: [
                _DashboardAppBar(user: user),
                dashAsync.when(
                  loading: () => const SliverFillRemaining(child: _DashboardSkeleton()),
                  error: (e, _) => SliverFillRemaining(child: _ErrorState(error: e)),
                  data: (data) => _DashboardContent(data: data, isDesktop: isDesktop),
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
    final name = (user?.userMetadata?['full_name'] as String?)?.split(' ').first ?? 'there';
    final avatar = user?.userMetadata?['avatar_url'] as String?;
    final hour = DateTime.now().hour;
    final greeting = hour < 12 ? 'Good morning' : hour < 17 ? 'Good afternoon' : 'Good evening';
    final syncState = ref.watch(gmailSyncProvider);

    ref.listen(gmailSyncProvider, (previous, next) {
      next.whenOrNull(
        data: (result) {
          if (result == null) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Found ${result.foundCount} statement emails, ${result.newlyStoredCount} new. '
                'Processed ${result.processedAttempted}: ${result.processedSucceeded} succeeded'
                '${result.processedNeedsPassword > 0 ? ', ${result.processedNeedsPassword} need a password' : ''}'
                '${result.processedNeedsCardAssignment > 0 ? ', ${result.processedNeedsCardAssignment} need a card assigned' : ''}'
                '${result.processedFailed > 0 ? ', ${result.processedFailed} failed' : ''}.',
              ),
              duration: const Duration(seconds: 8),
            ),
          );
          ref.invalidate(dashboardProvider);
          ref.invalidate(pendingCardAssignmentsProvider);
        },
        error: (error, _) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gmail sync failed: $error')),
          );
        },
      );
    });

    return SliverAppBar(
      backgroundColor: AppColors.surfaceVoid,
      floating: true,
      snap: true,
      expandedHeight: 0,
      toolbarHeight: 72,
      flexibleSpace: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, 0),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$greeting, $name',
                    style: GoogleFonts.inter(
                      fontSize: 13, color: AppColors.textSecondary, fontWeight: FontWeight.w400,
                    ),
                  ),
                  Text(
                    'CardCompass',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 22, fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary, letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
            ),
            // Sync Gmail button
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
                        color: AppColors.neonCyan,
                      ),
                    )
                  : const Icon(Icons.sync_rounded, color: AppColors.neonCyan),
            ),
            const SizedBox(width: AppSpacing.sm),
            // Avatar
            CircleAvatar(
              radius: 20,
              backgroundColor: AppColors.surface2,
              backgroundImage: avatar != null ? NetworkImage(avatar) : null,
              child: avatar == null
                  ? Text(name[0].toUpperCase(),
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.neonCyan,
                      ))
                  : null,
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
    pageBuilder: (dialogContext, _, __) => _SyncRangeDialog(
      onStartSync: (days) {
        Navigator.of(dialogContext).pop();
        ref.read(gmailSyncProvider.notifier).syncGmail(lookbackDays: days);
      },
    ),
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
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
  static const _options = [
    _SyncRangeOption(7, '7d'),
    _SyncRangeOption(30, '30d'),
    _SyncRangeOption(60, '60d'),
    _SyncRangeOption(90, '90d'),
    _SyncRangeOption(240, '8mo'),
    _SyncRangeOption(369, '1yr'),
  ];

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
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xl),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: isDesktop ? 460 : 420),
          child: Material(
            color: Colors.transparent,
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surface1,
                borderRadius: BorderRadius.circular(AppRadius.xl),
                border: Border.all(color: AppColors.textMuted.withValues(alpha: 0.12)),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.neonCyan.withValues(alpha: 0.08),
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
                    padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.sm, 0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            gradient: AppTheme.cyanFadeGradient,
                            borderRadius: BorderRadius.circular(AppRadius.md),
                          ),
                          child: const Icon(Icons.sync_rounded, size: 20, color: AppColors.textInverse),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Sync from Gmail',
                                  style: GoogleFonts.spaceGrotesk(
                                    fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Import credit card statements',
                                  style: GoogleFonts.inter(fontSize: 12.5, color: AppColors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close_rounded, size: 20),
                          color: AppColors.textMuted,
                          tooltip: 'Close',
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                    child: Text(
                      'LOOK BACK',
                      style: GoogleFonts.inter(
                        fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 1.0,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                    child: GridView.count(
                      crossAxisCount: 3,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: AppSpacing.sm,
                      crossAxisSpacing: AppSpacing.sm,
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
                  const SizedBox(height: AppSpacing.md),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                    child: AnimatedSwitcher(
                      duration: 200.ms,
                      child: Container(
                        key: ValueKey(_selectedDays),
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
                        decoration: BoxDecoration(
                          color: AppColors.surface2,
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline_rounded, size: 15, color: AppColors.textMuted),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Fetches statement emails from $_friendlyRange',
                                style: GoogleFonts.inter(fontSize: 12.5, color: AppColors.textSecondary),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
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
  const _RangeChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: AnimatedContainer(
          duration: 180.ms,
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: selected ? AppColors.neonCyan.withValues(alpha: 0.15) : AppColors.surface2,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: selected ? AppColors.neonCyan : AppColors.textMuted.withValues(alpha: 0.18),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: selected ? AppColors.neonCyan : AppColors.textSecondary,
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
        ? _AddFirstCard().animate(delay: 100.ms).fadeIn()
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionHeader(title: 'Your Cards', action: 'Manage', onTap: () {}),
              _CardsCarousel(cards: data.cards, statements: data.latestStatements)
                  .animate(delay: 100.ms)
                  .fadeIn()
                  .slideX(begin: 0.05),
            ],
          );

    final billsSection = data.latestStatements.isNotEmpty
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionHeader(title: 'Bills Due', action: null, onTap: null),
              _BillsPanel(cards: data.cards, statements: data.latestStatements)
                  .animate(delay: 150.ms)
                  .fadeIn(),
            ],
          )
        : const SizedBox.shrink();

    final transactionsSection = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(title: 'Recent Spend', action: 'View All', onTap: () {}),
        data.recentTransactions.isEmpty
            ? _EmptyTransactions().animate(delay: 200.ms).fadeIn()
            : _RecentTransactions(transactions: data.recentTransactions)
                .animate(delay: 200.ms)
                .fadeIn(),
      ],
    );

    if (isDesktop) {
      return SliverList(
        delegate: SliverChildListDelegate([
          _KpiRow(data: data).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1),
          const SizedBox(height: AppSpacing.lg),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      cardsSection,
                      const SizedBox(height: AppSpacing.lg),
                      billsSection,
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(flex: 2, child: transactionsSection),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),
        ]),
      );
    }

    return SliverList(
      delegate: SliverChildListDelegate([
        _KpiRow(data: data).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1),
        const SizedBox(height: AppSpacing.lg),
        cardsSection,
        const SizedBox(height: AppSpacing.lg),
        if (data.latestStatements.isNotEmpty) ...[
          billsSection,
          const SizedBox(height: AppSpacing.lg),
        ],
        transactionsSection,
        const SizedBox(height: AppSpacing.xxl),
      ]),
    );
  }
}

// ─── KPI Row ────────────────────────────────────────────────────────────────
class _KpiRow extends StatelessWidget {
  final DashboardData data;
  const _KpiRow({required this.data});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Row(
        children: [
          Expanded(child: _KpiCard(
            label: 'This Month',
            value: _shortCurrency.format(data.monthlySpend),
            icon: Icons.trending_up_rounded,
            color: AppColors.neonCyan,
          )),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: _KpiCard(
            label: 'Rewards',
            value: _shortCurrency.format(data.rewardsEarned),
            icon: Icons.star_rounded,
            color: AppColors.violet,
          )),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: _KpiCard(
            label: 'Total Limit',
            value: _shortCurrency.format(data.totalCreditLimit),
            icon: Icons.account_balance_wallet_rounded,
            color: AppColors.neonGreen,
          )),
        ],
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _KpiCard({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: color.withValues(alpha: 0.2), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: AppSpacing.sm),
          Text(
            value,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

// ─── Section Header ─────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onTap;

  const _SectionHeader({required this.title, required this.action, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
      child: Row(
        children: [
          Text(
            title,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary,
            ),
          ),
          const Spacer(),
          if (action != null)
            TextButton(
              onPressed: onTap,
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero, minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                action!,
                style: GoogleFonts.inter(fontSize: 13, color: AppColors.neonCyan, fontWeight: FontWeight.w500),
              ),
            ),
        ],
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
        final cardWidth = constraints.maxWidth * 0.6 > _maxCardWidth
            ? _maxCardWidth
            : constraints.maxWidth * 0.6;
        final cardHeight = cardWidth / _cardAspectRatio;
        final viewportFraction = ((cardWidth + AppSpacing.sm) / constraints.maxWidth).clamp(0.3, 0.9);

        // Only replace the controller when the viewport math actually
        // changes (e.g. window resize) — recreating it on every rebuild
        // (which happens whenever pendingCardAssignmentsProvider refreshes)
        // resets the user's scroll position back to page 0 mid-swipe.
        if (_controller == null || _controllerViewportFraction != viewportFraction) {
          _controller?.dispose();
          _controller = PageController(viewportFraction: viewportFraction, initialPage: _current);
          _controllerViewportFraction = viewportFraction;
        }

        return Column(
          children: [
            SizedBox(
              height: cardHeight,
              child: PageView.builder(
                itemCount: itemCount,
                padEnds: false,
                controller: _controller,
                onPageChanged: (i) => setState(() => _current = i),
                itemBuilder: (context, i) {
                  final isPending = i >= widget.cards.length;
                  final tile = isPending
                      ? _PendingBankTile(email: pending[i - widget.cards.length])
                      : GestureDetector(
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => CardDetailScreen(cardId: widget.cards[i].id),
                            ),
                          ),
                          child: _CreditCardTile(card: widget.cards[i]),
                        );
                  return Padding(
                    padding: EdgeInsets.only(
                      left: i == 0 ? AppSpacing.md : AppSpacing.sm,
                      right: i == itemCount - 1 ? AppSpacing.md : AppSpacing.sm,
                    ),
                    child: SizedBox(width: cardWidth, child: tile),
                  );
                },
              ),
            ),
            if (itemCount > 1) ...[
              const SizedBox(height: AppSpacing.sm),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(itemCount, (i) => AnimatedContainer(
                  duration: 250.ms,
                  width: i == _current ? 20 : 6,
                  height: 6,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: i == _current ? AppColors.neonCyan : AppColors.textMuted.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                )),
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
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(
          color: AppColors.warning.withValues(alpha: 0.4),
          width: 1.5,
          style: BorderStyle.solid,
        ),
      ),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  bankDetected,
                  style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w500, letterSpacing: 0.5),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              GestureDetector(
                onTap: () => _showBankResolveDialog(context, email),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.priority_high_rounded, size: 16, color: AppColors.warning),
                ),
              ),
            ],
          ),
          const Spacer(),
          Icon(Icons.help_outline_rounded, size: 28, color: AppColors.textMuted.withValues(alpha: 0.5)),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Which card is this?',
            style: GoogleFonts.inter(fontSize: 13, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

void _showBankResolveDialog(BuildContext context, Map<String, dynamic> email) {
  final bankDetected = email['bank_detected'] as String? ?? '';
  showDialog<void>(
    context: context,
    builder: (dialogContext) => _BankResolveDialog(email: email, bankDetected: bankDetected),
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
  String? _error;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  Future<void> _search(String query) async {
    setState(() => _loading = true);
    try {
      final results = await ref
          .read(cardsRepositoryProvider)
          .searchCatalogForBank(widget.bankDetected, query: query);
      if (mounted) setState(() { _options = results; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _resolve(Map<String, dynamic> catalogEntry) async {
    setState(() { _resolving = true; _error = null; });
    try {
      await ref.read(cardAssignmentProvider.notifier).resolveWithCatalogEntry(
            email: widget.email,
            catalogCardId: catalogEntry['id'] as String,
          );
      ref.invalidate(dashboardProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = 'Failed to assign card: $e');
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xl)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 480),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Which card is this?',
                style: GoogleFonts.spaceGrotesk(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 2),
              Text(
                widget.bankDetected,
                style: GoogleFonts.inter(fontSize: 12.5, color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Type to search ${widget.bankDetected} cards…',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                ),
                onChanged: _search,
              ),
              const SizedBox(height: AppSpacing.sm),
              Flexible(
                child: _loading
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : _error != null
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                            child: Text(_error!, style: GoogleFonts.inter(fontSize: 12, color: AppColors.error)),
                          )
                        : _options.isEmpty
                            ? Padding(
                                padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                                child: Text(
                                  'No matching card found. Try a different search.',
                                  style: GoogleFonts.inter(fontSize: 12.5, color: AppColors.textMuted),
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
                                      style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                                    ),
                                    subtitle: Text(
                                      entry['bank'] as String? ?? '',
                                      style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted),
                                    ),
                                    trailing: _resolving
                                        ? const SizedBox(
                                            width: 16, height: 16,
                                            child: CircularProgressIndicator(strokeWidth: 2),
                                          )
                                        : const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
                                    onTap: _resolving ? null : () => _resolve(entry),
                                  );
                                },
                              ),
              ),
              const SizedBox(height: AppSpacing.sm),
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
    final gradient = AppTheme.cardGradient(card.bankCode);
    return Container(
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10), width: 1),
        boxShadow: [
          BoxShadow(
            color: gradient.colors.last.withValues(alpha: 0.45),
            blurRadius: 20,
            spreadRadius: 1,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  card.bank ?? '',
                  style: GoogleFonts.inter(
                    fontSize: 12, color: Colors.white.withValues(alpha: 0.7), fontWeight: FontWeight.w500,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              Text(
                card.network ?? '',
                style: GoogleFonts.inter(
                  fontSize: 12, color: Colors.white.withValues(alpha: 0.7), fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const Spacer(),
          if (card.lastFourDigits != null)
            Text(
              '••••  ••••  ••••  ${card.lastFourDigits}',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 16, color: Colors.white, fontWeight: FontWeight.w600, letterSpacing: 2,
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: Text(
                  card.displayName,
                  style: GoogleFonts.inter(
                    fontSize: 14, color: Colors.white, fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (card.creditLimit != null)
                Text(
                  _currencyFmt.format(card.creditLimit),
                  style: GoogleFonts.inter(
                    fontSize: 13, color: Colors.white.withValues(alpha: 0.85), fontWeight: FontWeight.w500,
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
        .where((c) => statements.containsKey(c.id) && !statements[c.id]!.isPaid)
        .toList();

    if (pending.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.success.withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'All bills paid — you\'re good!',
                style: GoogleFonts.inter(fontSize: 14, color: AppColors.success, fontWeight: FontWeight.w500),
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
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.surface1,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(
                color: isOverdue
                    ? AppColors.error.withValues(alpha: 0.4)
                    : AppColors.warning.withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        card.displayName,
                        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Due ${DateFormat('d MMM').format(stmt.dueDate)}',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: isOverdue ? AppColors.error : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  _currencyFmt.format(stmt.outstanding),
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 16, fontWeight: FontWeight.w700,
                    color: isOverdue ? AppColors.error : AppColors.textPrimary,
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
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
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
    final amount = isDebit ? '-${_currencyFmt.format(txn.amount)}' : '+${_currencyFmt.format(txn.amount)}';
    final color = isDebit ? AppColors.textPrimary : AppColors.success;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs + 2),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.textMuted.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          // Category icon
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: _categoryColor(txn.category).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(_categoryIcon(txn.category), size: 18, color: _categoryColor(txn.category)),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  txn.merchantName ?? txn.description,
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  DateFormat('d MMM · hh:mm a').format(txn.transactionDate.toLocal()),
                  style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                amount,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 14, fontWeight: FontWeight.w700, color: color,
                ),
              ),
              if ((txn.rewardEarned ?? 0) > 0)
                Text(
                  '+${txn.rewardEarned!.toStringAsFixed(0)} pts',
                  style: GoogleFonts.inter(fontSize: 10, color: AppColors.violet),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static Color _categoryColor(String? cat) {
    switch (cat?.toLowerCase()) {
      case 'dining': return AppColors.warning;
      case 'travel': return const Color(0xFF38BDF8);
      case 'shopping': return AppColors.violet;
      case 'fuel': return const Color(0xFFF97316);
      case 'entertainment': return const Color(0xFFEC4899);
      case 'groceries': return AppColors.success;
      default: return AppColors.textSecondary;
    }
  }

  static IconData _categoryIcon(String? cat) {
    switch (cat?.toLowerCase()) {
      case 'dining': return Icons.restaurant_rounded;
      case 'travel': return Icons.flight_rounded;
      case 'shopping': return Icons.shopping_bag_rounded;
      case 'fuel': return Icons.local_gas_station_rounded;
      case 'entertainment': return Icons.theaters_rounded;
      case 'groceries': return Icons.local_grocery_store_rounded;
      default: return Icons.receipt_rounded;
    }
  }
}

// ─── Empty / Placeholder States ──────────────────────────────────────────────
class _AddFirstCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.xl),
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(color: AppColors.neonCyan.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                color: AppColors.neonCyan.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: const Icon(Icons.add_card_rounded, size: 28, color: AppColors.neonCyan),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Add your first card',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Connect your credit cards to see\nspend insights and reward tracking.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary, height: 1.5),
            ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => context.go('/app/cards/add'),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Card'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyTransactions extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.xl),
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.textMuted.withValues(alpha: 0.1)),
        ),
        child: Center(
          child: Text(
            'No transactions yet this month',
            style: GoogleFonts.inter(fontSize: 13, color: AppColors.textMuted),
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
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // KPI row skeleton
          Row(
            children: List.generate(3, (_) => Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: AppSpacing.sm),
                child: _SkeletonBox(height: 90, radius: AppRadius.lg),
              ),
            )),
          ),
          const SizedBox(height: AppSpacing.lg),
          _SkeletonBox(height: 200, radius: AppRadius.xl),
          const SizedBox(height: AppSpacing.lg),
          ...List.generate(5, (_) => Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: _SkeletonBox(height: 64, radius: AppRadius.md),
          )),
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

class _SkeletonBoxState extends State<_SkeletonBox> with SingleTickerProviderStateMixin {
  late final _ctrl = AnimationController(vsync: this, duration: 1200.ms)..repeat(reverse: true);
  late final _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        height: widget.height,
        decoration: BoxDecoration(
          color: Color.lerp(AppColors.surface1, AppColors.surface3, _anim.value),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

// ─── Error State ─────────────────────────────────────────────────────────────
class _ErrorState extends ConsumerWidget {
  final Object error;
  const _ErrorState({required this.error});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 48, color: AppColors.textMuted),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Couldn\'t load dashboard',
              style: GoogleFonts.spaceGrotesk(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              error.toString(),
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted),
            ),
            const SizedBox(height: AppSpacing.lg),
            ElevatedButton.icon(
              onPressed: () => ref.invalidate(dashboardProvider),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
