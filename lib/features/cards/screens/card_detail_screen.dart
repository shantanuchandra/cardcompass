import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/repository_providers.dart';
import '../../../core/providers/supabase_provider.dart';
import '../../../shared/models/user_card.dart';
import '../../../shared/models/transaction.dart';
import '../../../shared/models/statement.dart';

// ─── providers ───────────────────────────────────────────────────────────────

final _cardDetailProvider = FutureProvider.family<UserCard?, String>((ref, cardId) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return null;
  final cards = await ref.read(cardsRepositoryProvider).getUserCards(user.id);
  try {
    return cards.firstWhere((c) => c.id == cardId);
  } catch (_) {
    return null;
  }
});

final _cardTransactionsProvider =
    FutureProvider.family<List<Transaction>, String>((ref, cardId) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return [];
  return ref.read(transactionsRepositoryProvider).getTransactions(
        userId: user.id,
        userCardId: cardId,
        limit: 15,
      );
});

final _cardStatementProvider =
    FutureProvider.family<Statement?, String>((ref, cardId) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return null;
  final map = await ref.read(statementsRepositoryProvider).getLatestStatementPerCard(user.id);
  return map[cardId];
});

final _cardMonthSpendProvider =
    FutureProvider.family<double, String>((ref, cardId) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return 0;
  final now = DateTime.now();
  final start = DateTime(now.year, now.month, 1);
  final txns = await ref.read(transactionsRepositoryProvider).getTransactions(
        userId: user.id,
        userCardId: cardId,
        from: start,
        to: now,
        limit: 500,
      );
  return txns.where((t) => t.isDebit).fold<double>(0.0, (sum, t) => sum + t.amount);
});

// ─── screen ──────────────────────────────────────────────────────────────────

class CardDetailScreen extends ConsumerWidget {
  final String cardId;
  const CardDetailScreen({super.key, required this.cardId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cardAsync = ref.watch(_cardDetailProvider(cardId));

    return Scaffold(
      backgroundColor: AppColors.surfaceVoid,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceVoid,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: cardAsync.maybeWhen(
          data: (c) => Text(c?.displayName ?? 'Card Detail',
              style: GoogleFonts.spaceGrotesk(fontSize: 18, fontWeight: FontWeight.w700)),
          orElse: () => const SizedBox.shrink(),
        ),
      ),
      body: cardAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.neonCyan)),
        error: (e, _) => Center(child: Text('Error: $e', style: GoogleFonts.inter(color: AppColors.error))),
        data: (card) {
          if (card == null) {
            return Center(
              child: Text('Card not found', style: GoogleFonts.inter(color: AppColors.textMuted)),
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
  const _CardDetailBody({required this.card, required this.cardId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txnsAsync = ref.watch(_cardTransactionsProvider(cardId));
    final stmtAsync = ref.watch(_cardStatementProvider(cardId));
    final spendAsync = ref.watch(_cardMonthSpendProvider(cardId));

    return RefreshIndicator(
      color: AppColors.neonCyan,
      backgroundColor: AppColors.surface1,
      onRefresh: () async {
        ref.invalidate(_cardDetailProvider(cardId));
        ref.invalidate(_cardTransactionsProvider(cardId));
        ref.invalidate(_cardStatementProvider(cardId));
        ref.invalidate(_cardMonthSpendProvider(cardId));
      },
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          // Credit card visual — cap at 480px so it doesn't stretch full-width on desktop
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: _CreditCardWidget(card: card),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Stats row: utilization + month spend
          Row(
            children: [
              Expanded(
                child: stmtAsync.when(
                  loading: () => _StatCardSkeleton(),
                  error: (_, _e) => _StatCard(label: 'Utilization', value: '–'),
                  data: (stmt) {
                    if (stmt == null || card.creditLimit == null || card.creditLimit! <= 0) {
                      return _StatCard(label: 'Utilization', value: '–');
                    }
                    final pct = (stmt.closingBalance / card.creditLimit!) * 100;
                    return _UtilizationCard(
                      used: stmt.closingBalance,
                      limit: card.creditLimit!,
                      pct: pct.clamp(0, 100),
                    );
                  },
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: spendAsync.when(
                  loading: () => _StatCardSkeleton(),
                  error: (_, _e) => _StatCard(label: 'This Month', value: '–'),
                  data: (spend) => _StatCard(
                    label: 'This Month',
                    value: _fmt(spend),
                    icon: Icons.trending_up_rounded,
                    iconColor: AppColors.neonCyan,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          // Bill panel
          stmtAsync.when(
            loading: () => _BillPanelSkeleton(),
            error: (_, _e) => const SizedBox.shrink(),
            data: (stmt) => stmt != null ? _BillPanel(stmt: stmt) : const SizedBox.shrink(),
          ),
          const SizedBox(height: AppSpacing.md),

          // Recent transactions
          _SectionHeader(title: 'Recent Transactions'),
          const SizedBox(height: AppSpacing.sm),
          txnsAsync.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: CircularProgressIndicator(color: AppColors.neonCyan),
              ),
            ),
            error: (e, _) => Center(
              child: Text('Could not load transactions',
                  style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 13)),
            ),
            data: (txns) {
              if (txns.isEmpty) {
                return _EmptyTransactions();
              }
              return Column(
                children: txns.map((t) => _TxnTile(txn: t)).toList(),
              );
            },
          ),
          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }

  static String _fmt(double v) =>
      NumberFormat.compactCurrency(locale: 'en_IN', symbol: '₹', decimalDigits: 0).format(v);
}

// ─── credit card visual ───────────────────────────────────────────────────────

class _CreditCardWidget extends StatelessWidget {
  final UserCard card;
  const _CreditCardWidget({required this.card});

  @override
  Widget build(BuildContext context) {
    final gradient = AppTheme.cardGradient(card.bankCode);

    return AspectRatio(
      aspectRatio: 1.586, // standard credit card ratio
      child: Container(
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.12),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: gradient.colors.last.withValues(alpha: 0.5),
              blurRadius: 24,
              spreadRadius: 2,
              offset: const Offset(0, 8),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Subtle circuit pattern overlay
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                child: CustomPaint(painter: _CircuitPainter()),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top row: bank name + network
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        card.bank ?? '',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                      _NetworkBadge(network: card.network),
                    ],
                  ),
                  const Spacer(),
                  // Card number
                  Text(
                    card.maskedNumber.isNotEmpty
                        ? card.maskedNumber
                        : '••••  ••••  ••••  ••••',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  // Bottom row: name + credit limit
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('CARD HOLDER',
                              style: GoogleFonts.inter(
                                  fontSize: 9,
                                  color: Colors.white70,
                                  letterSpacing: 1)),
                          Text(
                            card.cardHolderName ?? 'YOUR NAME',
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      if (card.creditLimit != null)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('LIMIT',
                                style: GoogleFonts.inter(
                                    fontSize: 9,
                                    color: Colors.white70,
                                    letterSpacing: 1)),
                            Text(
                              NumberFormat.compactCurrency(
                                      locale: 'en_IN', symbol: '₹', decimalDigits: 0)
                                  .format(card.creditLimit),
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NetworkBadge extends StatelessWidget {
  final String? network;
  const _NetworkBadge({this.network});

  @override
  Widget build(BuildContext context) {
    final n = (network ?? '').toLowerCase();
    if (n == 'visa') {
      return Text('VISA',
          style: GoogleFonts.spaceGrotesk(
              fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 1));
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
                      color: Color(0xFFEB001B), shape: BoxShape.circle)),
            ),
            Positioned(
              right: 0,
              child: Container(
                  width: 24,
                  height: 24,
                  decoration:
                      BoxDecoration(color: Colors.orange.withValues(alpha: 0.85), shape: BoxShape.circle)),
            ),
          ],
        ),
      );
    }
    if (n == 'rupay') {
      return Text('RuPay',
          style: GoogleFonts.spaceGrotesk(
              fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white));
    }
    if (n == 'amex') {
      return Text('AMEX',
          style: GoogleFonts.spaceGrotesk(
              fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white));
    }
    return const SizedBox.shrink();
  }
}

// Subtle geometric circuit lines painted on the card background
class _CircuitPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    final path = Path();
    path.moveTo(size.width * 0.6, 0);
    path.lineTo(size.width * 0.6, size.height * 0.3);
    path.lineTo(size.width * 0.85, size.height * 0.3);
    path.moveTo(size.width * 0.85, size.height * 0.3);
    path.lineTo(size.width * 0.85, size.height * 0.6);
    path.moveTo(size.width * 0.6, size.height * 0.3);
    path.lineTo(size.width * 0.45, size.height * 0.3);
    path.lineTo(size.width * 0.45, size.height * 0.7);
    path.lineTo(size.width * 0.7, size.height * 0.7);
    canvas.drawPath(path, paint);

    canvas.drawCircle(
        Offset(size.width * 0.85, size.height * 0.6), 4, paint..style = PaintingStyle.fill);
    canvas.drawCircle(
        Offset(size.width * 0.45, size.height * 0.7), 3, paint);
  }

  @override
  bool shouldRepaint(_CircuitPainter _) => false;
}

// ─── utilization card ─────────────────────────────────────────────────────────

class _UtilizationCard extends StatelessWidget {
  final double used;
  final double limit;
  final double pct;
  const _UtilizationCard({required this.used, required this.limit, required this.pct});

  @override
  Widget build(BuildContext context) {
    final color = pct > 80
        ? AppColors.error
        : pct > 50
            ? AppColors.warning
            : AppColors.success;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.textMuted.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Utilization',
              style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w500)),
          const SizedBox(height: AppSpacing.sm),
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
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 9, fontWeight: FontWeight.w700, color: color),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _fmt(used),
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text('of ${_fmt(limit)}',
                        style: GoogleFonts.inter(fontSize: 10, color: AppColors.textMuted),
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _fmt(double v) =>
      NumberFormat.compactCurrency(locale: 'en_IN', symbol: '₹', decimalDigits: 0).format(v);
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
        rect, -math.pi / 2, 2 * math.pi, false,
        Paint()
          ..color = AppColors.surface3
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round);

    if (pct > 0) {
      canvas.drawArc(
          rect, -math.pi / 2, 2 * math.pi * pct, false,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 5
            ..strokeCap = StrokeCap.round);
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
  const _StatCard({required this.label, required this.value, this.icon, this.iconColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.textMuted.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w500)),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: iconColor ?? AppColors.neonCyan),
                const SizedBox(width: AppSpacing.xs),
              ],
              Text(value,
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
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
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.textMuted.withValues(alpha: 0.08)),
      ),
    );
  }
}

// ─── bill panel ───────────────────────────────────────────────────────────────

class _BillPanel extends StatelessWidget {
  final Statement stmt;
  const _BillPanel({required this.stmt});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final daysLeft = stmt.dueDate.difference(now).inDays;
    final isOverdue = daysLeft < 0;
    final statusColor = stmt.isPaid
        ? AppColors.success
        : isOverdue
            ? AppColors.error
            : daysLeft <= 3
                ? AppColors.warning
                : AppColors.textSecondary;

    final statusLabel = stmt.isPaid
        ? 'Paid'
        : isOverdue
            ? 'Overdue'
            : 'Due in $daysLeft day${daysLeft == 1 ? '' : 's'}';

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: stmt.isPaid
              ? AppColors.success.withValues(alpha: 0.3)
              : isOverdue
                  ? AppColors.error.withValues(alpha: 0.3)
                  : AppColors.textMuted.withValues(alpha: 0.12),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Bill Due',
                    style: GoogleFonts.inter(
                        fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                Text(
                  NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0)
                      .format(stmt.outstanding),
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                  DateFormat('d MMM yyyy').format(stmt.dueDate),
                  style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(statusLabel,
                    style: GoogleFonts.inter(
                        fontSize: 12, fontWeight: FontWeight.w600, color: statusColor)),
              ),
              if (stmt.minimumPayment > 0) ...[
                const SizedBox(height: AppSpacing.xs),
                Text('Min ₹${NumberFormat.compact().format(stmt.minimumPayment)}',
                    style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted)),
              ],
            ],
          ),
        ],
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
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.textMuted.withValues(alpha: 0.08)),
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
    return Text(title,
        style: GoogleFonts.spaceGrotesk(
            fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary));
  }
}

// ─── transaction tile ─────────────────────────────────────────────────────────

class _TxnTile extends StatelessWidget {
  final Transaction txn;
  const _TxnTile({required this.txn});

  @override
  Widget build(BuildContext context) {
    final isDebit = txn.isDebit;
    final amountColor = isDebit ? AppColors.textPrimary : AppColors.success;
    final amountPrefix = isDebit ? '−' : '+';

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm + 2),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.textMuted.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.surface3,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(_categoryIcon(txn.category), size: 18, color: AppColors.textSecondary),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  txn.merchantName ?? txn.description,
                  style: GoogleFonts.inter(
                      fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  DateFormat('d MMM').format(txn.transactionDate) +
                      (txn.category != null ? '  ·  ${txn.category}' : ''),
                  style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          Text(
            '$amountPrefix₹${NumberFormat.compact(locale: 'en_IN').format(txn.amount)}',
            style: GoogleFonts.spaceGrotesk(
                fontSize: 14, fontWeight: FontWeight.w700, color: amountColor),
          ),
        ],
      ),
    );
  }

  IconData _categoryIcon(String? category) {
    switch ((category ?? '').toLowerCase()) {
      case 'food':
      case 'dining':
        return Icons.restaurant_rounded;
      case 'travel':
      case 'transport':
        return Icons.flight_rounded;
      case 'shopping':
        return Icons.shopping_bag_rounded;
      case 'entertainment':
        return Icons.movie_rounded;
      case 'fuel':
        return Icons.local_gas_station_rounded;
      case 'groceries':
        return Icons.local_grocery_store_rounded;
      case 'utilities':
        return Icons.bolt_rounded;
      case 'health':
      case 'medical':
        return Icons.medical_services_rounded;
      default:
        return Icons.receipt_rounded;
    }
  }
}

class _EmptyTransactions extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      alignment: Alignment.center,
      child: Column(
        children: [
          const Icon(Icons.receipt_long_outlined, size: 40, color: AppColors.textMuted),
          const SizedBox(height: AppSpacing.sm),
          Text('No transactions yet',
              style: GoogleFonts.inter(fontSize: 14, color: AppColors.textMuted)),
        ],
      ),
    );
  }
}
