import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/brand_tokens.dart';
import '../../../core/theme/brand_components.dart';
import '../../../core/providers/repository_providers.dart';
import '../../../core/providers/supabase_provider.dart';
import '../../../shared/models/user_card.dart';
import 'card_detail_screen.dart';

final userCardsProvider = FutureProvider<List<UserCard>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return [];
  return ref.read(cardsRepositoryProvider).getUserCards(user.id);
});

class CardsScreen extends ConsumerWidget {
  const CardsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cardsAsync = ref.watch(userCardsProvider);

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
            onPressed: () => context.go('/app/cards/add'),
            tooltip: 'Add card',
          ),
        ],
      ),
      body: cardsAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: BrandColors.focusDark),
        ),
        error: (e, _) => Center(
          child: Text(
            'Error: $e',
            style: TextStyle(fontFamily: 'Manrope', color: BrandColors.error),
          ),
        ),
        data: (cards) => cards.isEmpty
            ? _EmptyCards()
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
                    itemBuilder: (_, i) =>
                        _CardListTile(card: cards[i], ref: ref),
                  ),
                ),
              ),
      ),
    );
  }
}

class _CardListTile extends StatelessWidget {
  final UserCard card;
  final WidgetRef ref;
  const _CardListTile({required this.card, required this.ref});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => CardDetailScreen(cardId: card.id)),
      ),
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
        child: Row(
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
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
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
      ),
    );
  }
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

class _EmptyCards extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
              onPressed: () => context.go('/app/cards/add'),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Card'),
            ),
          ],
        ),
      ),
    );
  }
}
