import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/brand_tokens.dart';
import '../../../core/theme/category_display.dart';
import '../../../core/theme/brand_components.dart';
import '../../../core/providers/repository_providers.dart';
import '../../../core/providers/supabase_provider.dart';
import '../../../shared/models/user_card.dart';
import '../../../shared/models/transaction.dart';
import '../../../shared/models/statement.dart';

// ─── providers ───────────────────────────────────────────────────────────────

final cardDetailProvider = FutureProvider.family<UserCard?, String>((
  ref,
  cardId,
) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return null;
  final cards = await ref.read(cardsRepositoryProvider).getUserCards(user.id);
  try {
    return cards.firstWhere((c) => c.id == cardId);
  } catch (_) {
    return null;
  }
});

final cardTransactionsProvider =
    FutureProvider.family<List<Transaction>, String>((ref, cardId) async {
      final user = ref.watch(currentUserProvider);
      if (user == null) return [];
      return ref
          .read(transactionsRepositoryProvider)
          .getTransactions(userId: user.id, userCardId: cardId, limit: 15);
    });

final cardStatementProvider = FutureProvider.family<Statement?, String>((
  ref,
  cardId,
) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return null;
  final map = await ref
      .read(statementsRepositoryProvider)
      .getLatestStatementPerCard(user.id);
  return map[cardId];
});

final cardMonthSpendProvider = FutureProvider.family<double, String>((
  ref,
  cardId,
) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return 0;
  final now = DateTime.now();
  final start = DateTime(now.year, now.month, 1);
  final txns = await ref
      .read(transactionsRepositoryProvider)
      .getTransactions(
        userId: user.id,
        userCardId: cardId,
        from: start,
        to: now,
        limit: 500,
      );
  return txns
      .where((t) => t.isDebit)
      .fold<double>(0.0, (sum, t) => sum + t.amount);
});

// ─── screen ──────────────────────────────────────────────────────────────────

class CardDetailScreen extends ConsumerWidget {
  final String cardId;
  const CardDetailScreen({super.key, required this.cardId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cardAsync = ref.watch(cardDetailProvider(cardId));

    return Scaffold(
      backgroundColor: BrandColors.paper,
      appBar: AppBar(
        backgroundColor: BrandColors.paper,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Card details',
          style: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: cardAsync.when(
        loading: () => const BrandLoadingSkeleton(
          key: Key('card-detail-loading'),
          semanticLabel: 'Loading card details',
          minHeight: 280,
        ),
        error: (_, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Could not load this card.',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 14,
                  color: BrandColors.error,
                ),
              ),
              TextButton(
                onPressed: () => ref.invalidate(cardDetailProvider(cardId)),
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
        data: (card) {
          if (card == null) {
            return BrandStateView(
              title: 'Card not found',
              message:
                  'This card may have been removed or is no longer available.',
              icon: Icons.credit_card_off_rounded,
              actionLabel: 'Back to cards',
              onAction: () => Navigator.of(context).maybePop(),
            );
          }
          return _CardDetailBody(card: card, cardId: cardId);
        },
      ),
    );
  }
}

class _CardDetailBody extends ConsumerWidget {
  final UserCard card;
  final String cardId;
  final _historyAnchorKey = GlobalKey();
  _CardDetailBody({required this.card, required this.cardId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txnsAsync = ref.watch(cardTransactionsProvider(cardId));
    final stmtAsync = ref.watch(cardStatementProvider(cardId));
    final spendAsync = ref.watch(cardMonthSpendProvider(cardId));

    return RefreshIndicator(
      color: BrandColors.focusDark,
      backgroundColor: BrandColors.paper,
      onRefresh: () async {
        ref.invalidate(cardDetailProvider(cardId));
        ref.invalidate(cardTransactionsProvider(cardId));
        ref.invalidate(cardStatementProvider(cardId));
        ref.invalidate(cardMonthSpendProvider(cardId));
      },
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: BrandSpacing.md),
        children: [
          BrandContentFrame(
            mode: BrandContentMode.fullWidthData,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionHeader(title: 'Card summary'),
                const SizedBox(height: BrandSpacing.sm),
                Text(
                  card.displayName,
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: BrandColors.ink,
                  ),
                ),
                const SizedBox(height: BrandSpacing.sm),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: _CreditCardWidget(card: card),
                  ),
                ),
                const SizedBox(height: BrandSpacing.sm),
                Semantics(
                  label: 'Review transaction history',
                  button: true,
                  child: ElevatedButton.icon(
                    key: const Key('review-history'),
                    onPressed: () {
                      final historyContext = _historyAnchorKey.currentContext;
                      if (historyContext != null) {
                        Scrollable.ensureVisible(
                          historyContext,
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOut,
                        );
                      }
                    },
                    icon: const Icon(Icons.receipt_long_outlined),
                    label: const Text('Review history'),
                  ),
                ),
                const SizedBox(height: BrandSpacing.md),
                _DetailStatsRow(
                  utilization: stmtAsync.when(
                    loading: _StatCardSkeleton.new,
                    error: (_, _) =>
                        const _StatCard(label: 'Utilization', value: '–'),
                    data: (stmt) {
                      if (stmt == null ||
                          card.creditLimit == null ||
                          card.creditLimit! <= 0) {
                        return const _StatCard(
                          label: 'Utilization',
                          value: '–',
                        );
                      }
                      final pct =
                          (stmt.closingBalance / card.creditLimit!) * 100;
                      return _UtilizationCard(
                        used: stmt.closingBalance,
                        limit: card.creditLimit!,
                        pct: pct.clamp(0, 100),
                      );
                    },
                  ),
                  monthSpend: spendAsync.when(
                    loading: _StatCardSkeleton.new,
                    error: (_, _) =>
                        const _StatCard(label: 'This Month', value: '–'),
                    data: (spend) => _StatCard(
                      label: 'This Month',
                      value: _fmt(spend),
                      icon: Icons.trending_up_rounded,
                      iconColor: BrandColors.focusDark,
                    ),
                  ),
                ),
                const SizedBox(height: BrandSpacing.lg),
                const _SectionHeader(title: 'Best uses'),
                const SizedBox(height: BrandSpacing.sm),
                const BrandSurface(
                  child: Text(
                    'No verified benefit rules are available for this card yet. Add verified card rules before using it for reward recommendations.',
                  ),
                ),
                const SizedBox(height: BrandSpacing.lg),
                const _SectionHeader(title: 'Milestone'),
                const SizedBox(height: BrandSpacing.sm),
                const BrandSurface(
                  child: Text(
                    'No verified milestone data is available for this card.',
                  ),
                ),
                const SizedBox(height: BrandSpacing.lg),
                const _SectionHeader(title: 'Current bill'),
                const SizedBox(height: BrandSpacing.sm),
                stmtAsync.when(
                  loading: _BillPanelSkeleton.new,
                  error: (_, _) => BrandSurface(
                    child: _RetryMessage(
                      message: 'Could not load the current bill.',
                      actionLabel: 'Retry bill',
                      onRetry: () =>
                          ref.invalidate(cardStatementProvider(cardId)),
                    ),
                  ),
                  data: (stmt) => stmt != null
                      ? _BillPanel(
                          stmt: stmt,
                          currentMonthSpend: spendAsync.asData?.value,
                        )
                      : const BrandSurface(
                          child: Text(
                            'No current bill yet. Import a statement to see what is due.',
                          ),
                        ),
                ),
                const SizedBox(height: BrandSpacing.lg),
                ExpansionTile(
                  key: const PageStorageKey('rewards-fees'),
                  title: const Text('Rewards & fees'),
                  subtitle: const Text('Open for costs and reward information'),
                  children: [
                    ListTile(
                      title: const Text('Annual fee'),
                      trailing: Text(
                        card.annualFee == null
                            ? 'Not listed'
                            : _fmt(card.annualFee!),
                      ),
                    ),
                    const ListTile(
                      title: Text('Reward information'),
                      subtitle: Text(
                        'Verified rewards and fee waivers will appear here.',
                      ),
                    ),
                  ],
                ),
                ExpansionTile(
                  key: _historyAnchorKey,
                  title: const Text('History'),
                  subtitle: const Text('Open recent transactions'),
                  children: [
                    txnsAsync.when(
                      loading: () => const Padding(
                        padding: EdgeInsets.all(BrandSpacing.lg),
                        child: CircularProgressIndicator(
                          color: BrandColors.focusDark,
                        ),
                      ),
                      error: (_, _) => Padding(
                        padding: const EdgeInsets.all(BrandSpacing.md),
                        child: _RetryMessage(
                          message: 'Could not load transactions.',
                          actionLabel: 'Retry history',
                          onRetry: () =>
                              ref.invalidate(cardTransactionsProvider(cardId)),
                        ),
                      ),
                      data: (txns) => txns.isEmpty
                          ? _EmptyTransactions()
                          : Column(
                              children: txns
                                  .map((t) => _TxnTile(txn: t))
                                  .toList(),
                            ),
                    ),
                  ],
                ),
                const SizedBox(height: BrandSpacing.xxl),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _fmt(double v) => NumberFormat.compactCurrency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  ).format(v);
}

class _RetryMessage extends StatelessWidget {
  const _RetryMessage({
    required this.message,
    required this.actionLabel,
    required this.onRetry,
  });

  final String message;
  final String actionLabel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(message),
      TextButton(onPressed: onRetry, child: Text(actionLabel)),
    ],
  );
}

class _DetailStatsRow extends StatelessWidget {
  const _DetailStatsRow({required this.utilization, required this.monthSpend});

  final Widget utilization;
  final Widget monthSpend;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final stack =
          constraints.maxWidth < 600 ||
          MediaQuery.textScalerOf(context).scale(14) >= 21;
      if (stack) {
        return Column(
          children: [
            SizedBox(width: double.infinity, child: utilization),
            const SizedBox(height: BrandSpacing.sm),
            SizedBox(width: double.infinity, child: monthSpend),
          ],
        );
      }
      return Row(
        children: [
          Expanded(child: utilization),
          const SizedBox(width: BrandSpacing.sm),
          Expanded(child: monthSpend),
        ],
      );
    },
  );
}

// ─── credit card visual ───────────────────────────────────────────────────────

class _CreditCardWidget extends StatelessWidget {
  final UserCard card;
  const _CreditCardWidget({required this.card});

  @override
  Widget build(BuildContext context) {
    final largeText = MediaQuery.textScalerOf(context).scale(14) >= 21;
    final cardContent = Container(
      decoration: BoxDecoration(
        color: BrandColors.paperDeep,
        borderRadius: BorderRadius.circular(BrandRadius.overlay),
        border: Border(
          left: BorderSide(
            color: AppTheme.issuerColor(card.bankCode),
            width: 7,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(BrandSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: largeText ? MainAxisSize.min : MainAxisSize.max,
          children: [
            Wrap(
              spacing: BrandSpacing.sm,
              runSpacing: BrandSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  card.bank ?? '',
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: BrandColors.ink,
                    letterSpacing: 0.5,
                  ),
                ),
                _NetworkBadge(network: card.network),
              ],
            ),
            if (!largeText)
              const Spacer()
            else
              const SizedBox(height: BrandSpacing.lg),
            Text(
              card.maskedNumber.isNotEmpty
                  ? card.maskedNumber
                  : '••••  ••••  ••••  ••••',
              softWrap: true,
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: BrandColors.ink,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: BrandSpacing.md),
            ResponsiveValueRow(
              spacing: BrandSpacing.md,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _CardLabel(label: 'CARD HOLDER'),
                    Text(
                      card.cardHolderName ?? 'YOUR NAME',
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: BrandColors.ink,
                      ),
                    ),
                  ],
                ),
                if (card.creditLimit != null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _CardLabel(label: 'LIMIT'),
                      Text(
                        NumberFormat.compactCurrency(
                          locale: 'en_IN',
                          symbol: '₹',
                          decimalDigits: 0,
                        ).format(card.creditLimit),
                        style: TextStyle(
                          fontFamily: 'Manrope',
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: BrandColors.ink,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
    return largeText
        ? cardContent
        : AspectRatio(aspectRatio: 1.586, child: cardContent);
  }
}

class _CardLabel extends StatelessWidget {
  const _CardLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: TextStyle(
      fontFamily: 'Manrope',
      fontSize: 12,
      color: BrandColors.mutedInk,
      letterSpacing: 1,
    ),
  );
}

class _NetworkBadge extends StatelessWidget {
  final String? network;
  const _NetworkBadge({this.network});

  @override
  Widget build(BuildContext context) {
    final n = (network ?? '').toLowerCase();
    if (n == 'visa') {
      return Text(
        'VISA',
        style: TextStyle(
          fontFamily: 'Manrope',
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: Colors.white,
          letterSpacing: 1,
        ),
      );
    }
    if (n == 'mastercard') {
      return SizedBox(
        width: 40,
        height: 24,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              child: Container(
                width: 24,
                height: 24,
                decoration: const BoxDecoration(
                  color: Color(0xFFEB001B),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Positioned(
              right: 0,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.85),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        ),
      );
    }
    if (n == 'rupay') {
      return Text(
        'RuPay',
        style: TextStyle(
          fontFamily: 'Manrope',
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      );
    }
    if (n == 'amex') {
      return Text(
        'AMEX',
        style: TextStyle(
          fontFamily: 'Manrope',
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

// ─── utilization card ─────────────────────────────────────────────────────────

class _UtilizationCard extends StatelessWidget {
  final double used;
  final double limit;
  final double pct;
  const _UtilizationCard({
    required this.used,
    required this.limit,
    required this.pct,
  });

  @override
  Widget build(BuildContext context) {
    final color = pct > 80
        ? BrandColors.error
        : pct > 50
        ? BrandColors.rewardInk
        : BrandColors.successInk;

    return Container(
      padding: const EdgeInsets.all(BrandSpacing.md),
      decoration: BoxDecoration(
        color: BrandColors.paper,
        borderRadius: BorderRadius.circular(BrandRadius.overlay),
        border: Border.all(color: BrandColors.mutedInk.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Utilization',
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 12,
              color: BrandColors.mutedInk,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: BrandSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              SizedBox(
                width: 44,
                height: 44,
                child: CustomPaint(
                  painter: _RingPainter(pct: pct / 100, color: color),
                  child: Center(
                    child: Text(
                      '${pct.round()}%',
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: BrandSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _fmt(used),
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: BrandColors.ink,
                      ),
                    ),
                    Text(
                      'of ${_fmt(limit)}',
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 12,
                        color: BrandColors.mutedInk,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _fmt(double v) => NumberFormat.compactCurrency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  ).format(v);
}

class _RingPainter extends CustomPainter {
  final double pct;
  final Color color;
  const _RingPainter({required this.pct, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = math.min(cx, cy) - 3;
    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: r);

    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi,
      false,
      Paint()
        ..color = BrandColors.paperDeep
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round,
    );

    if (pct > 0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * pct,
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.pct != pct || old.color != color;
}

// ─── simple stat card ─────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData? icon;
  final Color? iconColor;
  const _StatCard({
    required this.label,
    required this.value,
    this.icon,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(BrandSpacing.md),
      decoration: BoxDecoration(
        color: BrandColors.paper,
        borderRadius: BorderRadius.circular(BrandRadius.overlay),
        border: Border.all(color: BrandColors.mutedInk.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 12,
              color: BrandColors.mutedInk,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: BrandSpacing.sm),
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: iconColor ?? BrandColors.focusDark),
                const SizedBox(width: BrandSpacing.xs),
              ],
              Text(
                value,
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: BrandColors.ink,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatCardSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 76,
      padding: const EdgeInsets.all(BrandSpacing.md),
      decoration: BoxDecoration(
        color: BrandColors.paper,
        borderRadius: BorderRadius.circular(BrandRadius.overlay),
        border: Border.all(color: BrandColors.mutedInk.withValues(alpha: 0.08)),
      ),
    );
  }
}

// ─── bill panel ───────────────────────────────────────────────────────────────

class _BillPanel extends StatelessWidget {
  final Statement stmt;
  final double? currentMonthSpend;
  const _BillPanel({required this.stmt, this.currentMonthSpend});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final daysLeft = stmt.dueDate.difference(now).inDays;
    final isOverdue = daysLeft < 0;
    final statusColor = stmt.isPaid
        ? BrandColors.successInk
        : isOverdue
        ? BrandColors.error
        : daysLeft <= 3
        ? BrandColors.rewardInk
        : BrandColors.mutedInk;

    final statusLabel = stmt.isPaid
        ? 'Paid'
        : isOverdue
        ? 'Overdue'
        : 'Due in $daysLeft day${daysLeft == 1 ? '' : 's'}';
    final balanceNote = stmt.outstanding > 0 && currentMonthSpend == 0
        ? 'No purchases are recorded this month. This statement balance may '
              'include earlier balances, EMIs, fees, or transactions not yet '
              'imported.'
        : 'Statement balance and this month’s purchases are different '
              'measures; the balance may include earlier cycles, EMIs, fees, '
              'or interest.';

    final billDetails = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Bill Due',
          style: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 12,
            color: BrandColors.mutedInk,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          NumberFormat.currency(
            locale: 'en_IN',
            symbol: '₹',
            decimalDigits: 0,
          ).format(stmt.outstanding),
          style: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: BrandColors.ink,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          DateFormat('d MMM yyyy').format(stmt.dueDate),
          style: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 12,
            color: BrandColors.mutedInk,
          ),
        ),
      ],
    );
    final paymentStatus = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(BrandRadius.pill),
          ),
          child: Text(
            statusLabel,
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: statusColor,
            ),
          ),
        ),
        if (stmt.minimumPayment > 0) ...[
          const SizedBox(height: BrandSpacing.xs),
          Text(
            'Min ₹${NumberFormat.compact().format(stmt.minimumPayment)}',
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 12,
              color: BrandColors.mutedInk,
            ),
          ),
        ],
      ],
    );

    return Container(
      padding: const EdgeInsets.all(BrandSpacing.md),
      decoration: BoxDecoration(
        color: BrandColors.paper,
        borderRadius: BorderRadius.circular(BrandRadius.overlay),
        border: Border.all(
          color: stmt.isPaid
              ? BrandColors.successInk.withValues(alpha: 0.3)
              : isOverdue
              ? BrandColors.error.withValues(alpha: 0.3)
              : BrandColors.mutedInk.withValues(alpha: 0.12),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stack =
              constraints.maxWidth < 420 ||
              MediaQuery.textScalerOf(context).scale(14) >= 21;
          final summary = stack
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    billDetails,
                    const SizedBox(height: BrandSpacing.sm),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: paymentStatus,
                    ),
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: billDetails),
                    paymentStatus,
                  ],
                );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              summary,
              const SizedBox(height: BrandSpacing.sm),
              Text(
                balanceNote,
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 12,
                  height: 1.4,
                  color: BrandColors.mutedInk,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _BillPanelSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 80,
      decoration: BoxDecoration(
        color: BrandColors.paper,
        borderRadius: BorderRadius.circular(BrandRadius.overlay),
        border: Border.all(color: BrandColors.mutedInk.withValues(alpha: 0.08)),
      ),
    );
  }
}

// ─── section header ───────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        fontFamily: 'Manrope',
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: BrandColors.ink,
      ),
    );
  }
}

// ─── transaction tile ─────────────────────────────────────────────────────────

class _TxnTile extends StatelessWidget {
  final Transaction txn;
  const _TxnTile({required this.txn});

  @override
  Widget build(BuildContext context) {
    final isDebit = txn.isDebit;
    final amountColor = isDebit ? BrandColors.ink : BrandColors.successInk;
    final amountPrefix = isDebit ? '−' : '+';

    return Container(
      margin: const EdgeInsets.only(bottom: BrandSpacing.xs),
      padding: const EdgeInsets.symmetric(
        horizontal: BrandSpacing.md,
        vertical: BrandSpacing.sm + 2,
      ),
      decoration: BoxDecoration(
        color: BrandColors.paper,
        borderRadius: BorderRadius.circular(BrandRadius.card),
        border: Border.all(color: BrandColors.mutedInk.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: BrandColors.paperDeep,
              borderRadius: BorderRadius.circular(BrandRadius.control),
            ),
            child: Icon(
              _categoryIcon(txn.category),
              size: 18,
              color: BrandColors.mutedInk,
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
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: BrandColors.ink,
                  ),
                ),
                Text(
                  DateFormat('d MMM').format(txn.transactionDate) +
                      (txn.category != null ? '  ·  ${txn.category}' : ''),
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 12,
                    color: BrandColors.mutedInk,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '$amountPrefix₹${NumberFormat.compact(locale: 'en_IN').format(txn.amount)}',
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: amountColor,
            ),
          ),
        ],
      ),
    );
  }

  IconData _categoryIcon(String? category) => categoryIcon(category);
}

class _EmptyTransactions extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(BrandSpacing.xl),
      alignment: Alignment.center,
      child: Column(
        children: [
          const Icon(
            Icons.receipt_long_outlined,
            size: 40,
            color: BrandColors.mutedInk,
          ),
          const SizedBox(height: BrandSpacing.sm),
          Text(
            'No transactions yet',
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 14,
              color: BrandColors.mutedInk,
            ),
          ),
        ],
      ),
    );
  }
}
