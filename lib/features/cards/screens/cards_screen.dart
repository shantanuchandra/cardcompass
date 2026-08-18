import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/brand_tokens.dart';
import '../../../core/theme/brand_components.dart';
import '../../../shared/models/user_card.dart';
import '../../../shared/models/statement.dart';
import '../providers/cards_provider.dart';

class CardsScreen extends ConsumerWidget {
  const CardsScreen({super.key});

  Future<void> _openAddCard(BuildContext context) async {
    await context.push<bool>('/app/cards/add');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cardsAsync = ref.watch(userCardsProvider);
    final statements = ref.watch(latestCardStatementsProvider).asData?.value;

    return Scaffold(
      backgroundColor: BrandColors.paper,
      appBar: AppBar(
        title: Text(
          'My Cards',
          style: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            onPressed: () => _openAddCard(context),
            tooltip: 'Add card',
          ),
        ],
      ),
      body: cardsAsync.when(
        loading: () => const BrandLoadingSkeleton(
          key: Key('cards-loading'),
          semanticLabel: 'Loading your cards',
          minHeight: 280,
        ),
        error: (_, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Could not load your cards.',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 14,
                  color: BrandColors.error,
                ),
              ),
              TextButton(
                onPressed: () => ref.invalidate(userCardsProvider),
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
        data: (cards) => cards.isEmpty
            ? _EmptyCards(onAddCard: () => _openAddCard(context))
            : BrandContentFrame(
                mode: BrandContentMode.fullWidthData,
                child: RefreshIndicator(
                  color: BrandColors.focusDark,
                  backgroundColor: BrandColors.paper,
                  onRefresh: () => ref.refresh(userCardsProvider.future),
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      vertical: BrandSpacing.md,
                    ),
                    itemCount: cards.length,
                    separatorBuilder: (_, index) =>
                        const SizedBox(height: BrandSpacing.sm),
                    itemBuilder: (_, i) => _CardListTile(
                      card: cards[i],
                      statement: statements?[cards[i].id],
                      ref: ref,
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

class _CardListTile extends StatelessWidget {
  final UserCard card;
  final Statement? statement;
  final WidgetRef ref;
  const _CardListTile({
    required this.card,
    required this.statement,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push('/app/cards/${Uri.encodeComponent(card.id)}'),
      borderRadius: BorderRadius.circular(BrandRadius.overlay),
      child: Container(
        padding: const EdgeInsets.all(BrandSpacing.md),
        decoration: BoxDecoration(
          color: BrandColors.paper,
          borderRadius: BorderRadius.circular(BrandRadius.overlay),
          border: Border.all(
            color: BrandColors.mutedInk.withValues(alpha: 0.12),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CardIdentityMark(bank: card.bank, bankCode: card.bankCode),
                const SizedBox(width: BrandSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        card.displayName,
                        style: TextStyle(
                          fontFamily: 'Manrope',
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: BrandColors.ink,
                        ),
                      ),
                      const SizedBox(height: BrandSpacing.xs),
                      Text(
                        card.lastFourDigits != null
                            ? '${card.bank ?? 'Issuer'} · •••• ${card.lastFourDigits}'
                            : card.bank ?? 'Issuer not available',
                        style: TextStyle(
                          fontFamily: 'Manrope',
                          fontSize: 12,
                          color: BrandColors.mutedInk,
                        ),
                      ),
                      const SizedBox(height: BrandSpacing.xs),
                      Text(
                        card.isActive ? 'Active' : 'Inactive',
                        style: TextStyle(
                          fontFamily: 'Manrope',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: card.isActive
                              ? BrandColors.successInk
                              : BrandColors.mutedInk,
                        ),
                      ),
                      if (card.creditLimit != null) ...[
                        const SizedBox(height: BrandSpacing.xs),
                        Text(
                          '${NumberFormat.compactCurrency(locale: 'en_IN', symbol: '₹', decimalDigits: 0).format(card.creditLimit)} limit',
                          style: TextStyle(
                            fontFamily: 'IBM Plex Mono',
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: BrandColors.ink,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: BrandSpacing.md),
            if (statement != null) ...[
              _StatementStatus(statement: statement!),
              const SizedBox(height: BrandSpacing.sm),
              _CardBillingStrip(statement: statement!),
            ] else
              Text(
                'No statement imported',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 12,
                  color: BrandColors.mutedInk,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatementStatus extends StatelessWidget {
  const _StatementStatus({required this.statement});

  final Statement statement;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final days = DateTime(
      statement.dueDate.year,
      statement.dueDate.month,
      statement.dueDate.day,
    ).difference(DateTime(now.year, now.month, now.day)).inDays;
    final label = switch (statement.paymentStatus) {
      PaymentStatus.paid => 'Paid',
      PaymentStatus.partial => 'Partially paid',
      PaymentStatus.overdue => 'Overdue',
      PaymentStatus.pending when days < 0 => 'Overdue',
      PaymentStatus.pending when days == 0 => 'Due today',
      PaymentStatus.pending => 'Due in $days days',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: BrandColors.paperDeep,
        borderRadius: BorderRadius.circular(BrandRadius.pill),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Manrope',
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: BrandColors.ink,
        ),
      ),
    );
  }
}

class _CardBillingStrip extends StatelessWidget {
  const _CardBillingStrip({required this.statement});

  final Statement statement;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 0,
    );
    final date = DateFormat('d MMM');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(top: BrandSpacing.sm),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: BrandColors.mutedInk.withValues(alpha: 0.12)),
        ),
      ),
      child: Wrap(
        spacing: BrandSpacing.lg,
        runSpacing: BrandSpacing.sm,
        children: [
          _BillingValue(
            label: 'Statement',
            value: money.format(statement.totalAmount),
          ),
          _BillingValue(
            label: 'Remaining',
            value: money.format(statement.outstanding),
          ),
          _BillingValue(
            label: 'Closed',
            value: date.format(statement.statementDate),
          ),
          _BillingValue(label: 'Due', value: date.format(statement.dueDate)),
        ],
      ),
    );
  }
}

class _BillingValue extends StatelessWidget {
  const _BillingValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        label,
        style: TextStyle(
          fontFamily: 'Manrope',
          fontSize: 12,
          color: BrandColors.mutedInk,
        ),
      ),
      Text(
        value,
        style: TextStyle(
          fontFamily: 'IBM Plex Mono',
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: BrandColors.ink,
        ),
      ),
    ],
  );
}

class CardIdentityMark extends StatelessWidget {
  const CardIdentityMark({
    super.key,
    required this.bank,
    required this.bankCode,
  });

  final String? bank;
  final String bankCode;

  @override
  Widget build(BuildContext context) {
    final label = (bank ?? '').trim();
    final monogram = label.isEmpty
        ? 'CC'
        : label
              .split(RegExp(r'\s+'))
              .where((part) => part.isNotEmpty)
              .take(2)
              .map((part) => part.substring(0, 1).toUpperCase())
              .join();
    return Semantics(
      label: label.isEmpty ? 'Card issuer' : '$label card issuer',
      child: Container(
        width: 48,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppTheme.issuerColor(bankCode).withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(BrandRadius.control),
          border: Border.all(
            color: AppTheme.issuerColor(bankCode).withValues(alpha: 0.4),
          ),
        ),
        child: Text(
          monogram,
          style: TextStyle(
            fontFamily: 'IBM Plex Mono',
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: BrandColors.ink,
          ),
        ),
      ),
    );
  }
}

class _EmptyCards extends StatelessWidget {
  const _EmptyCards({required this.onAddCard});

  final VoidCallback onAddCard;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(BrandSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.credit_card_off_rounded,
              size: 56,
              color: BrandColors.mutedInk,
            ),
            const SizedBox(height: BrandSpacing.md),
            Text(
              'No cards yet',
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: BrandColors.ink,
              ),
            ),
            const SizedBox(height: BrandSpacing.sm),
            Text(
              'Add your credit cards to track spend,\nrewards, and upcoming bills.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 14,
                color: BrandColors.mutedInk,
                height: 1.5,
              ),
            ),
            const SizedBox(height: BrandSpacing.xl),
            ElevatedButton.icon(
              onPressed: onAddCard,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Card'),
            ),
          ],
        ),
      ),
    );
  }
}
