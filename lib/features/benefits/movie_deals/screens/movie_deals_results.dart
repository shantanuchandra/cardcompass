// lib/features/benefits/movie_deals/screens/movie_deals_results.dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/providers/repository_providers.dart';
import '../../../../core/providers/supabase_provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../domain/movie_deal_candidate.dart';
import '../domain/movie_deal_rule.dart';
import '../domain/movie_ticket_request.dart';
import '../providers/movie_deals_provider.dart';
import '../widgets/sprocket_rail_painter.dart';

/// Design spec §8's layout, extended per user feedback: rather than a
/// single winner per guaranteed/potential × owned/overall slot, EVERY
/// eligible candidate in each of the 4 groups is listed, ranked by savings —
/// a user comparing offers (e.g. a ₹700 potential fixedDiscount against a
/// ₹70 guaranteed percentDiscount) can see all of them, not just whichever
/// one the evaluator picked as "best." rewardMultiplier/annualAllowance
/// candidates stay in their own dedicated, non-competitive sections.
///
/// Each result renders as a "frame" (a film-strip metaphor: a sprocket rail
/// down the left edge, matching the app's existing CustomPainter texture
/// technique). The six MovieDealOfferTypes carry genuinely different proof
/// of eligibility — a BOGO's redemption count, a milestone's real progress
/// bar, a reward-rate's honest non-currency badge — so each gets its own
/// "proof strip" widget instead of one generic confidence chip for all six.
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
    // Same reasoning as rewardMultiplier — an annualAllowance's true
    // per-visit savings is unknowable (no remaining-balance tracking
    // exists), so it's never in any of the 4 ranked groups below (the
    // evaluator itself already excludes both types — see
    // evaluateMovieDeals' winnerEligible filter). Shown in its own
    // dedicated, non-competitive section instead.
    final annualAllowanceCandidates =
        recommendation.candidates.where((c) => c.rule.offerType == MovieDealOfferType.annualAllowance).toList();

    final hasAnyRanked = recommendation.guaranteedOwned.isNotEmpty ||
        recommendation.guaranteedOverall.isNotEmpty ||
        recommendation.potentialOwned.isNotEmpty ||
        recommendation.potentialOverall.isNotEmpty;

    if (!hasAnyRanked && rewardMultiplierCandidates.isEmpty && annualAllowanceCandidates.isEmpty) {
      return _buildNoDealCard(context);
    }

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

    var frameIndex = 0;

    Widget buildGroup(String label, _DividerTone tone, List<MovieDealCandidate> group, {required bool isOverallFlavor}) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionDivider(label: label, tone: tone),
          const SizedBox(height: 12),
          if (group.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                'No ${tone == _DividerTone.guaranteed ? 'guaranteed' : 'potential'} deals ${isOverallFlavor ? 'available' : 'on cards you own'} for this search.',
                style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 12),
              ),
            )
          else
            for (final candidate in group)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _FilmFrame(
                  candidate: candidate,
                  isPotential: tone == _DividerTone.potential,
                  isOverallFlavor: isOverallFlavor,
                  onConfirmPlatform: confirmCallbackFor(candidate),
                ).animate(delay: (frameIndex++ * 50).ms).fadeIn(duration: 250.ms).slideY(begin: 0.04),
              ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        buildGroup('GUARANTEED · YOU OWN', _DividerTone.guaranteed, recommendation.guaranteedOwned, isOverallFlavor: false),
        const SizedBox(height: 18),
        buildGroup('GUARANTEED · OVERALL', _DividerTone.guaranteed, recommendation.guaranteedOverall, isOverallFlavor: true),
        const SizedBox(height: 18),
        buildGroup('POTENTIAL · YOU OWN', _DividerTone.potential, recommendation.potentialOwned, isOverallFlavor: false),
        const SizedBox(height: 18),
        buildGroup('POTENTIAL · OVERALL', _DividerTone.potential, recommendation.potentialOverall, isOverallFlavor: true),
        if (rewardMultiplierCandidates.isNotEmpty) ...[
          const SizedBox(height: 22),
          _SectionDivider(label: 'REWARD RATE — NOT A DIRECT DISCOUNT', tone: _DividerTone.reward),
          const SizedBox(height: 12),
          _buildRewardMultiplierSection(rewardMultiplierCandidates, frameIndex),
        ],
        if (annualAllowanceCandidates.isNotEmpty) ...[
          const SizedBox(height: 22),
          _SectionDivider(label: 'ANNUAL ALLOWANCE — BALANCE NOT TRACKED', tone: _DividerTone.allowance),
          const SizedBox(height: 12),
          _buildAnnualAllowanceSection(annualAllowanceCandidates, frameIndex + rewardMultiplierCandidates.length),
        ],
      ],
    );
  }

  Widget _buildRewardMultiplierSection(List<MovieDealCandidate> candidates, int startIndex) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < candidates.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _RewardRateStrip(candidate: candidates[i])
                .animate(delay: ((startIndex + i) * 60).ms)
                .fadeIn(duration: 250.ms)
                .slideY(begin: 0.04),
          ),
      ],
    );
  }

  Widget _buildAnnualAllowanceSection(List<MovieDealCandidate> candidates, int startIndex) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < candidates.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _AnnualAllowanceStrip(candidate: candidates[i])
                .animate(delay: ((startIndex + i) * 60).ms)
                .fadeIn(duration: 250.ms)
                .slideY(begin: 0.04),
          ),
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

enum _DividerTone { guaranteed, potential, reward, allowance }

class _SectionDivider extends StatelessWidget {
  const _SectionDivider({required this.label, required this.tone});

  final String label;
  final _DividerTone tone;

  @override
  Widget build(BuildContext context) {
    final color = switch (tone) {
      _DividerTone.guaranteed => AppColors.neonCyan,
      _DividerTone.potential => AppColors.warning,
      _DividerTone.reward => AppColors.violet,
      _DividerTone.allowance => AppColors.success,
    };
    return Row(
      children: [
        Expanded(child: Container(height: 1, color: AppColors.surface3)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            label,
            style: GoogleFonts.spaceGrotesk(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.0, color: color),
          ),
        ),
        Expanded(child: Container(height: 1, color: AppColors.surface3)),
      ],
    );
  }
}

class _FilmFrame extends StatefulWidget {
  const _FilmFrame({
    required this.candidate,
    required this.isOverallFlavor,
    this.isPotential = false,
    this.onConfirmPlatform,
  });

  final MovieDealCandidate candidate;
  final bool isOverallFlavor;
  final bool isPotential;
  final Future<void> Function()? onConfirmPlatform;

  @override
  State<_FilmFrame> createState() => _FilmFrameState();
}

class _FilmFrameState extends State<_FilmFrame> {
  bool _confirmed = false;

  @override
  Widget build(BuildContext context) {
    final candidate = widget.candidate;
    final accent = widget.isPotential
        ? AppColors.warning
        : (widget.isOverallFlavor ? AppColors.violet : AppColors.neonCyan);
    final borderColor = accent.withValues(alpha: 0.35);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: borderColor, width: 1.4, style: widget.isPotential ? BorderStyle.solid : BorderStyle.solid),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 22,
              color: AppColors.surfaceVoid,
              child: CustomPaint(painter: SprocketRailPainter(holeColor: accent.withValues(alpha: 0.4))),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (candidate.isOwned)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [_Tag(text: 'YOU OWN THIS', color: accent, filled: true)],
                            ),
                          ),
                        ],
                      ),
                    if (candidate.isOwned) const SizedBox(height: 10),
                    Text(
                      candidate.rule.cardName ?? candidate.title,
                      style: GoogleFonts.spaceGrotesk(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    if (widget.isPotential)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
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
                    const SizedBox(height: 12),
                    _ProofStrip(candidate: candidate),
                    const SizedBox(height: 12),
                    if (candidate.platformConfidence != MovieDealPlatformConfidence.explicit &&
                        candidate.platformConfidence != MovieDealPlatformConfidence.communityConfirmed)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _Tag(text: 'Platform not confirmed', color: AppColors.textMuted, filled: false),
                      ),
                    Text(candidate.explanation, style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 12, height: 1.4)),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.only(top: 12),
                      decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.surface3))),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                '₹${candidate.grossAmount.toStringAsFixed(0)}',
                                style: GoogleFonts.spaceGrotesk(color: AppColors.textMuted, fontSize: 13, decoration: TextDecoration.lineThrough),
                              ),
                              Text('  →  ', style: GoogleFonts.spaceGrotesk(color: AppColors.textMuted, fontSize: 13)),
                              Text(
                                '₹${candidate.finalAmount.toStringAsFixed(0)}',
                                style: GoogleFonts.spaceGrotesk(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 16),
                              ),
                            ],
                          ),
                          Text(
                            'Save ₹${candidate.savings.toStringAsFixed(0)}',
                            style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold, color: accent, fontSize: 15),
                          ),
                        ],
                      ),
                    ),
                    if (widget.onConfirmPlatform != null && !_confirmed) ...[
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () async {
                            await widget.onConfirmPlatform!();
                            if (mounted) setState(() => _confirmed = true);
                          },
                          child: const Text('Did this work here? Let us know'),
                        ),
                      ),
                    ],
                    if (_confirmed) ...[
                      const SizedBox(height: 10),
                      Text('Thanks — this helps other users.', style: GoogleFonts.inter(fontSize: 11, color: AppColors.neonCyan)),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.color, required this.filled});

  // Rendered exactly as passed, never forced to uppercase — a caller-chosen
  // string (e.g. "Also best overall", "Potential") is a functional label
  // other code/tests may search for verbatim, and mangling its case here
  // once already broke that (findByText('Also best overall') failing
  // because this widget silently upper-cased it). Callers that want an
  // uppercase tag pass an already-uppercase string.
  final String text;
  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: filled ? color.withValues(alpha: 0.15) : Colors.transparent,
        border: filled ? null : Border.all(color: color.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        text,
        style: GoogleFonts.spaceGrotesk(fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.4, color: color),
      ),
    );
  }
}

/// Renders the proof a candidate's confidence is actually grounded in,
/// specific to its offer type — never a single generic "confidence" chip
/// standing in for six structurally different kinds of evidence.
class _ProofStrip extends StatelessWidget {
  const _ProofStrip({required this.candidate});

  final MovieDealCandidate candidate;

  @override
  Widget build(BuildContext context) {
    final rule = candidate.rule;
    Widget? content;

    switch (rule.offerType) {
      case MovieDealOfferType.bogo:
        if (rule.cycleRedemptionLimit != null) {
          content = _RedemptionTracker(
            used: candidate.usedTransactions,
            limit: rule.cycleRedemptionLimit!,
            perTicketCap: rule.perTransactionCap,
          );
        }
      case MovieDealOfferType.milestone:
        if (rule.milestoneThreshold != null) {
          content = _MilestoneProgress(
            spend: candidate.milestoneSpend,
            threshold: rule.milestoneThreshold!,
          );
        }
      case MovieDealOfferType.percentDiscount:
      case MovieDealOfferType.fixedDiscount:
      case MovieDealOfferType.annualAllowance:
      case MovieDealOfferType.rewardMultiplier:
        content = null;
    }

    // No offer-type-specific proof to show — fall back to confirmation
    // count when a community confirmation is what's actually backing this
    // candidate's platform confidence.
    content ??= candidate.platformConfidence == MovieDealPlatformConfidence.communityConfirmed &&
            candidate.confirmationCount != null
        ? _ConfirmationCount(count: candidate.confirmationCount!)
        : null;

    if (content == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceVoid,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.surface3),
      ),
      child: content,
    );
  }
}

class _RedemptionTracker extends StatelessWidget {
  const _RedemptionTracker({required this.used, required this.limit, this.perTicketCap});

  final int used;
  final int limit;
  final double? perTicketCap;

  @override
  Widget build(BuildContext context) {
    final clampedUsed = used.clamp(0, limit);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('REDEMPTIONS THIS CYCLE', style: GoogleFonts.spaceGrotesk(fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 0.5, color: AppColors.textMuted)),
        const SizedBox(height: 8),
        Row(
          children: [
            Row(
              children: List.generate(limit, (i) {
                final isUsed = i < clampedUsed;
                return Padding(
                  padding: const EdgeInsets.only(right: 5),
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isUsed ? AppColors.warning : Colors.transparent,
                      border: Border.all(color: isUsed ? AppColors.warning : AppColors.surface3, width: 1.4),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(
                TextSpan(
                  style: GoogleFonts.inter(fontSize: 11, color: AppColors.textSecondary),
                  children: [
                    TextSpan(text: '$clampedUsed of $limit', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                    const TextSpan(text: ' used'),
                    if (perTicketCap != null) TextSpan(text: ' · ₹${perTicketCap!.toStringAsFixed(0)} cap per ticket'),
                  ],
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MilestoneProgress extends StatelessWidget {
  const _MilestoneProgress({required this.spend, required this.threshold});

  final double? spend;
  final double threshold;

  @override
  Widget build(BuildContext context) {
    // The evaluator only ever lets a milestone candidate through once its
    // threshold is already met (movie_deal_evaluator.dart's
    // _ineligibilityReason rejects unmet/unknown milestones outright) — so a
    // milestone candidate reaching this widget always has spend >= threshold.
    // spend is still nullable here defensively; the fraction is clamped to
    // 1.0 either way rather than trusting that invariant blindly.
    final fraction = spend == null ? 1.0 : (spend! / threshold).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('MONTHLY SPEND MILESTONE', style: GoogleFonts.spaceGrotesk(fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 0.5, color: AppColors.textMuted)),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(100),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 6,
            backgroundColor: AppColors.surface3,
            valueColor: const AlwaysStoppedAnimation(AppColors.success),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              spend == null ? 'Threshold met' : '₹${spend!.toStringAsFixed(0)} spent',
              style: GoogleFonts.spaceGrotesk(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.success),
            ),
            Text(
              'Threshold ₹${threshold.toStringAsFixed(0)}',
              style: GoogleFonts.inter(fontSize: 10, color: AppColors.textMuted),
            ),
          ],
        ),
      ],
    );
  }
}

class _ConfirmationCount extends StatelessWidget {
  const _ConfirmationCount({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 34,
          height: 16,
          child: Stack(
            children: List.generate(count.clamp(0, 3), (i) {
              return Positioned(
                left: i * 9.0,
                child: Container(
                  width: 15,
                  height: 15,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.surface3,
                    border: Border.all(color: AppColors.surface1, width: 1.5),
                  ),
                ),
              );
            }),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'Confirmed by $count ${count == 1 ? 'user' : 'users'} — not an official partner listing',
            style: GoogleFonts.inter(fontSize: 10.5, color: AppColors.textSecondary),
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
        ),
      ],
    );
  }
}

class _RewardRateStrip extends StatelessWidget {
  const _RewardRateStrip({required this.candidate});

  final MovieDealCandidate candidate;

  @override
  Widget build(BuildContext context) {
    final rule = candidate.rule;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.surface3),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.violet.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              rule.rewardMultiplierRate != null ? '${rule.rewardMultiplierRate!.toStringAsFixed(0)}X' : '—',
              style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.violet),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${rule.cardName ?? candidate.title} — earns via this card\'s points program',
                  style: GoogleFonts.spaceGrotesk(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 4),
                // Never clamped/ellipsized — this is the specific rate/cap
                // detail behind the reward-rate disclaimer above (design
                // spec §7 step 6: never a fabricated rupee figure);
                // truncating it away would hide exactly the detail this
                // feature exists to surface honestly. A plain Text, not
                // RichText/TextSpan — the latter's rendered content is
                // invisible to find.textContaining, which only inspects a
                // Text widget's own .data string.
                Text(
                  candidate.explanation,
                  style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 11.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// annualAllowance's own dedicated, non-competitive display — same reasoning
/// as _RewardRateStrip: the true per-visit savings is unknowable (no
/// remaining-balance tracking exists anywhere in the schema), so this must
/// never look like a savings-tier film-frame with "Save ₹0" (which would
/// read as a failed/worthless result rather than "you have annual
/// headroom, details below").
class _AnnualAllowanceStrip extends StatelessWidget {
  const _AnnualAllowanceStrip({required this.candidate});

  final MovieDealCandidate candidate;

  @override
  Widget build(BuildContext context) {
    final rule = candidate.rule;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.surface3),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              rule.annualCap != null ? '₹${rule.annualCap!.toStringAsFixed(0)}/yr' : '—',
              style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.success),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${rule.cardName ?? candidate.title} — annual movie-ticket allowance',
                  style: GoogleFonts.spaceGrotesk(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 4),
                // Never clamped/ellipsized, same reasoning as
                // _RewardRateStrip's explanation Text — this is the
                // disclaimer that remaining balance isn't tracked, never a
                // per-visit rupee claim.
                Text(
                  candidate.explanation,
                  style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 11.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
