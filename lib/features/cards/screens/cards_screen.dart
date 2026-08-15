import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/brand_tokens.dart';
import '../../../core/providers/repository_providers.dart';
import '../../../core/providers/supabase_provider.dart';
import '../../../shared/models/user_card.dart';
import 'card_detail_screen.dart';

final _userCardsProvider = FutureProvider<List<UserCard>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return [];
  return ref.read(cardsRepositoryProvider).getUserCards(user.id);
});

class CardsScreen extends ConsumerWidget {
  const CardsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cardsAsync = ref.watch(_userCardsProvider);

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
            : RefreshIndicator(
                color: BrandColors.focusDark,
                backgroundColor: BrandColors.paper,
                onRefresh: () => ref.refresh(_userCardsProvider.future),
                child: ListView.separated(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  itemCount: cards.length,
                  separatorBuilder: (_, _a) =>
                      const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (_, i) =>
                      _CardListTile(card: cards[i], ref: ref),
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
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: BrandColors.paper,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
            color: BrandColors.mutedInk.withValues(alpha: 0.12),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: BrandColors.paperDeep,
                borderRadius: BorderRadius.circular(BrandRadius.control),
                border: Border(
                  left: BorderSide(
                    color: AppTheme.issuerColor(card.bankCode),
                    width: 4,
                  ),
                ),
              ),
              child: const Icon(
                Icons.credit_card,
                size: 22,
                color: BrandColors.ink,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
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
                  Text(
                    card.lastFourDigits != null
                        ? '••••  ${card.lastFourDigits}'
                        : card.bank ?? '',
                    style: TextStyle(
                      fontFamily: 'Manrope',
                      fontSize: 12,
                      color: BrandColors.mutedInk,
                    ),
                  ),
                ],
              ),
            ),
            if (card.creditLimit != null)
              Text(
                NumberFormat.compactCurrency(
                  locale: 'en_IN',
                  symbol: '₹',
                  decimalDigits: 0,
                ).format(card.creditLimit),
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: BrandColors.ink,
                ),
              ),
            const SizedBox(width: AppSpacing.xs),
            const Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: BrandColors.mutedInk,
            ),
          ],
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
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.credit_card_off_rounded,
              size: 56,
              color: BrandColors.mutedInk,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'No cards yet',
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: BrandColors.ink,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
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
            const SizedBox(height: AppSpacing.xl),
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
