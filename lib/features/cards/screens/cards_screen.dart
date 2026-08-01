import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/repository_providers.dart';
import '../../../core/providers/supabase_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../shared/models/user_card.dart';

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
      backgroundColor: AppColors.surfaceVoid,
      appBar: AppBar(
        title: Text('My Cards',
            style: GoogleFonts.spaceGrotesk(fontSize: 20, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            onPressed: () => context.go(AppRoutes.addCard),
            tooltip: 'Add card',
          ),
        ],
      ),
      body: cardsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.neonCyan)),
        error: (e, _) => Center(child: Text('Error: $e', style: GoogleFonts.inter(color: AppColors.error))),
        data: (cards) => cards.isEmpty
            ? _EmptyCards()
            : RefreshIndicator(
                color: AppColors.neonCyan,
                backgroundColor: AppColors.surface1,
                onRefresh: () => ref.refresh(_userCardsProvider.future),
                child: ListView.separated(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  itemCount: cards.length,
                  separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (_, i) => _CardListTile(card: cards[i], ref: ref),
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
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.textMuted.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              gradient: AppTheme.cardGradient(card.bankCode),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: const Icon(Icons.credit_card, size: 22, color: Colors.white),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(card.displayName,
                    style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                Text(card.lastFourDigits != null ? '••••  ${card.lastFourDigits}' : card.bank ?? '',
                    style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted)),
              ],
            ),
          ),
          if (card.creditLimit != null)
            Text(
              NumberFormat.compactCurrency(locale: 'en_IN', symbol: '₹', decimalDigits: 0)
                  .format(card.creditLimit),
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
            ),
        ],
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
            const Icon(Icons.credit_card_off_rounded, size: 56, color: AppColors.textMuted),
            const SizedBox(height: AppSpacing.md),
            Text('No cards yet',
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(height: AppSpacing.sm),
            Text('Add your credit cards to track spend,\nrewards, and upcoming bills.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 14, color: AppColors.textSecondary, height: 1.5)),
            const SizedBox(height: AppSpacing.xl),
            ElevatedButton.icon(
              onPressed: () => context.go(AppRoutes.addCard),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Card'),
            ),
          ],
        ),
      ),
    );
  }
}
