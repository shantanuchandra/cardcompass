import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/supabase_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../shared/models/user_card.dart';
import '../../../shared/models/transaction.dart';
import '../../../shared/models/statement.dart';
import '../providers/dashboard_provider.dart';

final _currencyFmt = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
final _shortCurrency = NumberFormat.compactCurrency(locale: 'en_IN', symbol: '₹', decimalDigits: 1);

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashAsync = ref.watch(dashboardProvider);
    final user = ref.watch(currentUserProvider);

    return Scaffold(
      backgroundColor: AppColors.surfaceVoid,
      body: RefreshIndicator(
        color: AppColors.neonCyan,
        backgroundColor: AppColors.surface1,
        onRefresh: () => ref.refresh(dashboardProvider.future),
        child: CustomScrollView(
          slivers: [
            _DashboardAppBar(user: user),
            dashAsync.when(
              loading: () => const SliverFillRemaining(child: _DashboardSkeleton()),
              error: (e, _) => SliverFillRemaining(child: _ErrorState(error: e)),
              data: (data) => _DashboardContent(data: data),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── App Bar ────────────────────────────────────────────────────────────────
class _DashboardAppBar extends StatelessWidget {
  final dynamic user;
  const _DashboardAppBar({this.user});

  @override
  Widget build(BuildContext context) {
    final name = (user?.userMetadata?['full_name'] as String?)?.split(' ').first ?? 'there';
    final avatar = user?.userMetadata?['avatar_url'] as String?;
    final hour = DateTime.now().hour;
    final greeting = hour < 12 ? 'Good morning' : hour < 17 ? 'Good afternoon' : 'Good evening';

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

// ─── Main Content ───────────────────────────────────────────────────────────
class _DashboardContent extends StatelessWidget {
  final DashboardData data;
  const _DashboardContent({required this.data});

  @override
  Widget build(BuildContext context) {
    return SliverList(
      delegate: SliverChildListDelegate([
        // KPI row
        _KpiRow(data: data)
            .animate()
            .fadeIn(duration: 400.ms)
            .slideY(begin: 0.1),
        const SizedBox(height: AppSpacing.lg),

        // Cards carousel (or empty state)
        if (data.cards.isEmpty)
          _AddFirstCard()
              .animate(delay: 100.ms)
              .fadeIn()
        else ...[
          _SectionHeader(title: 'Your Cards', action: 'Manage', onTap: () {}),
          _CardsCarousel(cards: data.cards, statements: data.latestStatements)
              .animate(delay: 100.ms)
              .fadeIn()
              .slideX(begin: 0.05),
        ],
        const SizedBox(height: AppSpacing.lg),

        // Upcoming bills
        if (data.latestStatements.isNotEmpty) ...[
          _SectionHeader(title: 'Bills Due', action: null, onTap: null),
          _BillsPanel(cards: data.cards, statements: data.latestStatements)
              .animate(delay: 150.ms)
              .fadeIn(),
          const SizedBox(height: AppSpacing.lg),
        ],

        // Recent transactions
        _SectionHeader(
          title: 'Recent Spend',
          action: 'View All',
          onTap: () {},
        ),
        data.recentTransactions.isEmpty
            ? _EmptyTransactions()
                .animate(delay: 200.ms)
                .fadeIn()
            : _RecentTransactions(transactions: data.recentTransactions)
                .animate(delay: 200.ms)
                .fadeIn(),
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
class _CardsCarousel extends StatefulWidget {
  final List<UserCard> cards;
  final Map<String, Statement> statements;
  const _CardsCarousel({required this.cards, required this.statements});

  @override
  State<_CardsCarousel> createState() => _CardsCarouselState();
}

class _CardsCarouselState extends State<_CardsCarousel> {
  int _current = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 200,
          child: PageView.builder(
            itemCount: widget.cards.length,
            padEnds: false,
            controller: PageController(viewportFraction: 0.88),
            onPageChanged: (i) => setState(() => _current = i),
            itemBuilder: (context, i) {
              final card = widget.cards[i];
              return Padding(
                padding: EdgeInsets.only(
                  left: i == 0 ? AppSpacing.md : AppSpacing.sm,
                  right: i == widget.cards.length - 1 ? AppSpacing.md : AppSpacing.sm,
                ),
                child: _CreditCardTile(card: card),
              );
            },
          ),
        ),
        if (widget.cards.length > 1) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(widget.cards.length, (i) => AnimatedContainer(
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
  }
}

class _CreditCardTile extends StatelessWidget {
  final UserCard card;
  const _CreditCardTile({required this.card});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: AppTheme.cardGradient(card.bankCode),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 20,
            offset: const Offset(0, 8),
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
                onPressed: () => context.go(AppRoutes.addCard),
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
