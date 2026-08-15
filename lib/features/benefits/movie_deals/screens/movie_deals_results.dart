// lib/features/benefits/movie_deals/screens/movie_deals_results.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/providers/repository_providers.dart';
import '../../../../core/providers/supabase_provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../domain/movie_deal_candidate.dart';
import '../domain/movie_deal_rule.dart';
import '../domain/movie_ticket_request.dart';
import '../providers/movie_deals_provider.dart';

/// Design spec §8's three-section layout: guaranteed owned/overall (falling
/// back to a labeled potential candidate when no guaranteed winner exists),
/// a distinct "Potential" section for anything the guaranteed tier didn't
/// surface, and rewardMultiplier candidates shown separately with their raw
/// rate — never mixed into either savings-based tier.
class MovieDealsResults extends ConsumerWidget {
  const MovieDealsResults({super.key, required this.request});

  final MovieTicketRequest request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(movieDealsSearchProvider(request));
    return async.when(
      data: (recommendation) => _buildRecommendation(context, ref, recommendation),
      loading: () => const Center(
        child: Padding(padding: EdgeInsets.all(32.0), child: CircularProgressIndicator()),
      ),
      error: (error, stack) => _buildRetryCard(context, ref),
    );
  }

  Widget _buildRecommendation(
      BuildContext context, WidgetRef ref, MovieDealsRecommendation recommendation) {
    if (recommendation.status == MovieDealsStatus.unavailable) {
      return _buildRetryCard(context, ref);
    }

    final rewardMultiplierCandidates =
        recommendation.candidates.where((c) => c.rule.offerType == MovieDealOfferType.rewardMultiplier).toList();

    final hasAnyGuaranteed =
        recommendation.bestGuaranteedOwned != null || recommendation.bestGuaranteedOverall != null;
    final hasAnyPotential =
        recommendation.bestPotentialOwned != null || recommendation.bestPotentialOverall != null;

    if (!hasAnyGuaranteed && !hasAnyPotential && rewardMultiplierCandidates.isEmpty) {
      return _buildNoDealCard(context);
    }

    final ownedWinner = recommendation.bestGuaranteedOwned ?? recommendation.bestPotentialOwned;
    final overallWinner = recommendation.bestGuaranteedOverall ?? recommendation.bestPotentialOverall;
    final ownedIsGuaranteed = recommendation.bestGuaranteedOwned != null;
    final overallIsGuaranteed = recommendation.bestGuaranteedOverall != null;
    final sharedWinner = ownedWinner != null &&
        overallWinner != null &&
        ownedWinner.cardId == overallWinner.cardId &&
        ownedWinner.benefitId == overallWinner.benefitId &&
        ownedIsGuaranteed == overallIsGuaranteed;

    Future<void> Function()? confirmCallbackFor(MovieDealCandidate candidate) {
      if (request.preferredPlatform == null) return null;
      if (candidate.platformConfidence == MovieDealPlatformConfidence.explicit) return null;
      // Read once, not force-unwrapped: the button that invokes this closure
      // fires later than the search itself, so the session could have
      // expired or the user signed out in between — falling back to "no
      // button" here matches every other null guard in this function
      // (preferredPlatform, platformConfidence) rather than crashing.
      final userId = ref.read(currentUserProvider)?.id;
      if (userId == null) return null;
      return () => ref.read(movieDealsRepositoryProvider).confirmPlatform(
            benefitId: candidate.benefitId,
            platform: request.preferredPlatform!,
            userId: userId,
          );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (ownedWinner != null)
          _CandidatePanel(
            heading: ownedIsGuaranteed ? 'BEST CARD YOU OWN' : 'POTENTIAL — YOU OWN THIS CARD',
            candidate: ownedWinner,
            isPotential: !ownedIsGuaranteed,
            trailingLabel: sharedWinner ? 'Also best overall' : null,
            onConfirmPlatform: confirmCallbackFor(ownedWinner),
          ),
        if (ownedWinner != null && !sharedWinner) const SizedBox(height: 16),
        if (overallWinner != null && !sharedWinner)
          _CandidatePanel(
            heading: overallIsGuaranteed ? 'BEST CARD OVERALL' : 'POTENTIAL — BEST OVERALL',
            candidate: overallWinner,
            isOwned: false,
            isPotential: !overallIsGuaranteed,
            onConfirmPlatform: confirmCallbackFor(overallWinner),
          ),
        if (rewardMultiplierCandidates.isNotEmpty) ...[
          const SizedBox(height: 24),
          _buildRewardMultiplierSection(rewardMultiplierCandidates),
        ],
      ],
    );
  }

  Widget _buildRewardMultiplierSection(List<MovieDealCandidate> candidates) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'REWARD RATE — NOT A DIRECT DISCOUNT',
          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold, color: AppColors.textMuted, fontSize: 10, letterSpacing: 0.5),
        ),
        const SizedBox(height: 8),
        ...candidates.map((c) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surface1,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: AppColors.surface3),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${c.rule.cardName ?? c.title} — earns via this card\'s points program',
                      style: GoogleFonts.spaceGrotesk(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    Text(c.explanation, style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 12)),
                  ],
                ),
              ),
            )),
      ],
    );
  }

  Widget _buildNoDealCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.surface3),
      ),
      child: Text(
        'No verified eligible deal for this search. Try a different platform or ticket count.',
        style: GoogleFonts.inter(color: AppColors.textSecondary),
      ),
    );
  }

  Widget _buildRetryCard(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Movie deals data is unavailable right now.',
            style: GoogleFonts.inter(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () => ref.invalidate(movieDealsSearchProvider(request)),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

class _CandidatePanel extends StatefulWidget {
  const _CandidatePanel({
    required this.heading,
    required this.candidate,
    this.isOwned,
    this.isPotential = false,
    this.trailingLabel,
    this.onConfirmPlatform,
  });

  final String heading;
  final MovieDealCandidate candidate;
  final bool? isOwned;
  final bool isPotential;
  final String? trailingLabel;
  final Future<void> Function()? onConfirmPlatform;

  @override
  State<_CandidatePanel> createState() => _CandidatePanelState();
}

class _CandidatePanelState extends State<_CandidatePanel> {
  bool _confirmed = false;

  @override
  Widget build(BuildContext context) {
    final candidate = widget.candidate;
    final owned = widget.isOwned ?? candidate.isOwned;
    final borderColor = widget.isPotential
        ? AppColors.textMuted.withValues(alpha: 0.3)
        : (owned ? AppColors.neonCyan.withValues(alpha: 0.25) : AppColors.violet.withValues(alpha: 0.25));
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        border: Border.all(color: borderColor, width: 1.2),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.heading,
            style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold, color: AppColors.textSecondary, fontSize: 11, letterSpacing: 0.5),
          ),
          const SizedBox(height: 8),
          Text(
            candidate.rule.cardName ?? candidate.title,
            style: GoogleFonts.spaceGrotesk(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 8),
          if (widget.isPotential)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Potential — remaining balance not verified',
                  style: GoogleFonts.inter(fontSize: 10, color: AppColors.warning),
                ),
              ),
            ),
          if (candidate.platformConfidence != MovieDealPlatformConfidence.explicit)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.textMuted.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Platform not confirmed for this offer',
                  style: GoogleFonts.inter(fontSize: 10, color: AppColors.textSecondary),
                ),
              ),
            ),
          Text(candidate.explanation, style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 12)),
          const SizedBox(height: 8),
          Text(
            '₹${candidate.grossAmount.toStringAsFixed(0)} → ₹${candidate.finalAmount.toStringAsFixed(0)} · Save ₹${candidate.savings.toStringAsFixed(0)}',
            style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold, color: AppColors.neonCyan, fontSize: 13),
          ),
          if (widget.trailingLabel != null) ...[
            const SizedBox(height: 8),
            Text(widget.trailingLabel!, style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted, fontStyle: FontStyle.italic)),
          ],
          if (widget.onConfirmPlatform != null && !_confirmed) ...[
            const SizedBox(height: 12),
            TextButton(
              onPressed: () async {
                await widget.onConfirmPlatform!();
                if (mounted) setState(() => _confirmed = true);
              },
              child: const Text('Did this work here? Let us know'),
            ),
          ],
          if (_confirmed) ...[
            const SizedBox(height: 12),
            Text('Thanks — this helps other users.', style: GoogleFonts.inter(fontSize: 11, color: AppColors.neonCyan)),
          ],
        ],
      ),
    );
  }
}
