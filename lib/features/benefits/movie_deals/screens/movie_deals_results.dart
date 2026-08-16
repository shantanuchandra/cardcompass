// lib/features/benefits/movie_deals/screens/movie_deals_results.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/providers/repository_providers.dart';
import '../../../../core/providers/supabase_provider.dart';
import '../../../../core/theme/brand_tokens.dart';
import '../../../../core/theme/brand_components.dart';
import '../domain/movie_deal_candidate.dart';
import '../domain/movie_deal_rule.dart';
import '../domain/movie_platform_aliases.dart';
import '../domain/movie_ticket_request.dart';
import '../providers/movie_deals_provider.dart';

String _formatAmount(double amount) => amount == amount.roundToDouble()
    ? amount.toStringAsFixed(0)
    : amount.toStringAsFixed(2);

String _plainLanguageReason(MovieDealCandidate candidate) {
  final rule = candidate.rule;
  return switch (rule.offerType) {
    MovieDealOfferType.percentDiscount =>
      'This offer takes ${_formatAmount(rule.discountPercent ?? 0)}% off the ticket total.',
    MovieDealOfferType.fixedDiscount =>
      'This offer takes ₹${_formatAmount(candidate.savings)} off this booking.',
    // annualAllowance always reports savings=0 (design decision: no
    // remaining-balance tracking exists, so a per-visit figure would be
    // invented) — candidate.explanation already carries the honest
    // "Up to ₹X/year" wording; this reason line names the mechanism
    // instead of repeating a rupee amount that is never this booking's
    // real number.
    MovieDealOfferType.annualAllowance =>
      'This booking can draw from the card’s annual movie allowance.',
    MovieDealOfferType.milestone =>
      'You met the required spend milestone for this movie voucher.',
    MovieDealOfferType.bogo =>
      'Buy ${rule.buyCount} ticket${rule.buyCount == 1 ? '' : 's'} and get ${rule.freeCount} free.',
    MovieDealOfferType.rewardMultiplier =>
      rule.rewardMultiplierRate == null
          ? 'This card may earn extra rewards through its points program; this is not a ticket-price discount.'
          : '${rule.rewardMultiplierRate} ${rule.rewardMultiplierUnit ?? 'reward points'} may be earned through the card’s points program; this is not a ticket-price discount.',
  };
}

/// Names whether THIS candidate's rule is tied to the platform the user
/// actually searched for, rather than a generic "not confirmed" chip that
/// never says what was searched. Falls back to naming the rule's own
/// eligible platform(s) when nothing was searched, or an honest
/// "not confirmed" line when the rule carries no platform data to check
/// at all — same three states this screen has always distinguished.
String _bookingPlatformMessage(
  MovieDealCandidate candidate,
  MovieTicketRequest request,
) {
  final selectedPlatform = request.preferredPlatform;
  final eligiblePlatforms = eligibleMoviePlatformsFor(candidate.rule);

  if (selectedPlatform != null && eligiblePlatforms.isNotEmpty) {
    final tied = eligiblePlatforms.any(
      (p) => p.toLowerCase() == selectedPlatform.toLowerCase(),
    );
    return tied
        ? 'Tied to $selectedPlatform.'
        : 'This offer is not tied to $selectedPlatform.';
  }
  if (selectedPlatform != null) {
    return candidate.platformConfidence == MovieDealPlatformConfidence.explicit
        ? 'Book on $selectedPlatform.'
        : 'Selected platform: $selectedPlatform — this offer needs confirmation there.';
  }

  final sortedEligible = eligiblePlatforms.toList()..sort();
  if (sortedEligible.isNotEmpty) {
    final platformLabel = sortedEligible.join(', ');
    return sortedEligible.length == 1
        ? 'Eligible booking platform: $platformLabel.'
        : 'Eligible booking platforms: $platformLabel.';
  }
  return candidate.platformConfidence ==
          MovieDealPlatformConfidence.communityConfirmed
      ? 'A booking platform has community confirmation, but the exact platform is unknown.'
      : 'Booking platform is not confirmed for this offer.';
}

/// A cinema was searched, but no benefit data in this schema is ever tied
/// to a specific chain — cinema never affects eligibility anywhere (see
/// MovieTicketRequest's own doc comment). Purely informational, shown on
/// every card once a cinema is selected, never a confidence signal.
const _cinemaNotSupportedMessage =
    'Cinema filtering is not yet supported — no benefit data is tied to a specific chain.';

/// Which half of the confirmed 2-column layout a [MovieDealsResults]
/// instance renders — the input form sits above [owned] on the left,
/// [overall] fills the right on its own. Both slots independently watch
/// the same [movieDealsSearchProvider], so Riverpod serves both from one
/// cached call — no duplicate network work, just two views over the same
/// recommendation.
enum ResultsSlot { owned, overall }

/// Design spec §8's layout, extended per user feedback: rather than a
/// single winner per guaranteed/potential × owned/overall slot, EVERY
/// eligible candidate in each of the 4 groups is listed, ranked by
/// savings — a user comparing offers (e.g. a ₹700 potential fixedDiscount
/// against a ₹70 guaranteed percentDiscount) can see all of them, not
/// just whichever one the evaluator picked as "best." rewardMultiplier/
/// annualAllowance candidates stay in their own dedicated, non-competitive
/// sections, always under [ResultsSlot.overall] — they're never
/// ownership-split so a standalone "You own" copy would just duplicate
/// the overall one.
class MovieDealsResults extends ConsumerWidget {
  const MovieDealsResults({super.key, required this.request, required this.slot});

  final MovieTicketRequest request;
  final ResultsSlot slot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(movieDealsSearchProvider(request));
    return async.when(
      data: (recommendation) =>
          _buildRecommendation(context, ref, recommendation),
      loading: () => const BrandLoadingSkeleton(
        key: Key('movie-results-loading'),
        semanticLabel: 'Finding movie offers',
        minHeight: 280,
      ),
      // Both slots watch the same provider, so a failure surfaces a retry
      // card in each column independently — retrying from either one
      // invalidates the single shared provider entry for both.
      error: (error, stack) => _buildRetryCard(context, ref),
    );
  }

  Widget _buildRecommendation(
    BuildContext context,
    WidgetRef ref,
    MovieDealsRecommendation recommendation,
  ) {
    if (recommendation.status == MovieDealsStatus.unavailable) {
      return _buildRetryCard(context, ref);
    }

    final rewardMultiplierCandidates = recommendation.candidates
        .where((c) => c.rule.offerType == MovieDealOfferType.rewardMultiplier)
        .toList();
    // Same reasoning as rewardMultiplier — an annualAllowance's true
    // per-visit savings is unknowable (no remaining-balance tracking
    // exists), so it's never in any of the 4 ranked groups below (the
    // evaluator itself already excludes both types — see
    // evaluateMovieDeals's winnerEligible filter). Shown in its own
    // dedicated, non-competitive section instead.
    final annualAllowanceCandidates = recommendation.candidates
        .where((c) => c.rule.offerType == MovieDealOfferType.annualAllowance)
        .toList();

    final hasAnyRanked = recommendation.guaranteedOwned.isNotEmpty ||
        recommendation.guaranteedOverall.isNotEmpty ||
        recommendation.potentialOwned.isNotEmpty ||
        recommendation.potentialOverall.isNotEmpty;

    if (!hasAnyRanked &&
        rewardMultiplierCandidates.isEmpty &&
        annualAllowanceCandidates.isEmpty) {
      // Shown only on the overall slot — the owned slot would otherwise
      // duplicate the same "no deal" message right next to it.
      return slot == ResultsSlot.overall
          ? _buildNoDealCard(context)
          : const SizedBox.shrink();
    }

    Future<void> Function()? confirmCallbackFor(MovieDealCandidate candidate) {
      if (request.preferredPlatform == null) return null;
      if (candidate.platformConfidence ==
          MovieDealPlatformConfidence.explicit) {
        return null;
      }
      // Read once, not force-unwrapped: the button that invokes this closure
      // fires later than the search itself, so the session could have
      // expired or the user signed out in between — falling back to "no
      // button" here matches every other null guard in this function
      // (preferredPlatform, platformConfidence) rather than crashing.
      final userId = ref.read(currentUserProvider)?.id;
      if (userId == null) return null;
      return () => ref
          .read(movieDealsRepositoryProvider)
          .confirmPlatform(
            benefitId: candidate.benefitId,
            platform: request.preferredPlatform!,
            userId: userId,
          );
    }

    Widget buildGroup(
      String label,
      List<MovieDealCandidate> group, {
      required bool isPotential,
      required bool isOverallFlavor,
    }) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Manrope',
              fontWeight: FontWeight.bold,
              color: BrandColors.mutedInk,
              fontSize: 12,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          if (group.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                'No ${isPotential ? 'potential' : 'guaranteed'} deals '
                '${isOverallFlavor ? 'available' : 'on cards you own'} for this search.',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  color: BrandColors.mutedInk,
                  fontSize: 12,
                ),
              ),
            )
          else
            for (final candidate in group)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _DealCard(
                  candidate: candidate,
                  request: request,
                  isPotential: isPotential,
                  onConfirmPlatform: confirmCallbackFor(candidate),
                ),
              ),
        ],
      );
    }

    // Owned slot: Guaranteed·Own stacked above Potential·Own (left column,
    // under the input form). Overall slot: Guaranteed·Overall stacked
    // above Potential·Overall, followed by the reward-rate/annual-
    // allowance sections.
    if (slot == ResultsSlot.owned) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          buildGroup(
            'Guaranteed · You own',
            recommendation.guaranteedOwned,
            isPotential: false,
            isOverallFlavor: false,
          ),
          const SizedBox(height: 18),
          buildGroup(
            'Potential · You own',
            recommendation.potentialOwned,
            isPotential: true,
            isOverallFlavor: false,
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        buildGroup(
          'Guaranteed · Overall',
          recommendation.guaranteedOverall,
          isPotential: false,
          isOverallFlavor: true,
        ),
        const SizedBox(height: 18),
        buildGroup(
          'Potential · Overall',
          recommendation.potentialOverall,
          isPotential: true,
          isOverallFlavor: true,
        ),
        if (rewardMultiplierCandidates.isNotEmpty) ...[
          const SizedBox(height: 20),
          _buildRewardMultiplierSection(rewardMultiplierCandidates),
        ],
        if (annualAllowanceCandidates.isNotEmpty) ...[
          const SizedBox(height: 20),
          _buildAnnualAllowanceSection(annualAllowanceCandidates),
        ],
      ],
    );
  }

  Widget _buildRewardMultiplierSection(List<MovieDealCandidate> candidates) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Reward rate — not a ticket-price saving',
          style: TextStyle(
            fontFamily: 'Manrope',
            fontWeight: FontWeight.bold,
            color: BrandColors.mutedInk,
            fontSize: 12,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        ...candidates.map(
          (c) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: BrandSurface(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${c.rule.cardName ?? c.title} — reward points rate',
                    style: TextStyle(
                      fontFamily: 'Manrope',
                      color: BrandColors.ink,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _plainLanguageReason(c),
                    style: TextStyle(
                      fontFamily: 'Manrope',
                      color: BrandColors.mutedInk,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAnnualAllowanceSection(List<MovieDealCandidate> candidates) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Annual allowance — balance not tracked',
          style: TextStyle(
            fontFamily: 'Manrope',
            fontWeight: FontWeight.bold,
            color: BrandColors.mutedInk,
            fontSize: 12,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        ...candidates.map(
          (c) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: BrandSurface(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.rule.cardName ?? c.title,
                    style: TextStyle(
                      fontFamily: 'Manrope',
                      color: BrandColors.ink,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    c.explanation,
                    style: TextStyle(
                      fontFamily: 'Manrope',
                      color: BrandColors.mutedInk,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNoDealCard(BuildContext context) {
    return BrandSurface(
      child: Text(
        'No eligible ticket-saving option',
        style: TextStyle(
          fontFamily: 'Manrope',
          color: BrandColors.ink,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildRetryCard(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: BrandColors.paper,
        borderRadius: BorderRadius.circular(BrandRadius.overlay),
        border: Border.all(color: BrandColors.error.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Movie deals data is unavailable right now.',
            style: TextStyle(
              fontFamily: 'Manrope',
              color: BrandColors.ink,
              fontWeight: FontWeight.w600,
            ),
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

class _DealCard extends StatefulWidget {
  const _DealCard({
    required this.candidate,
    required this.request,
    required this.isPotential,
    this.onConfirmPlatform,
  });

  final MovieDealCandidate candidate;
  final MovieTicketRequest request;
  final bool isPotential;
  final Future<void> Function()? onConfirmPlatform;

  @override
  State<_DealCard> createState() => _DealCardState();
}

class _DealCardState extends State<_DealCard> {
  bool _confirmed = false;

  @override
  Widget build(BuildContext context) {
    final candidate = widget.candidate;
    final effectiveTicketPrice =
        candidate.finalAmount / widget.request.numberOfTickets;
    final borderColor = widget.isPotential
        ? BrandColors.mutedInk.withValues(alpha: 0.3)
        : (candidate.isOwned
              ? BrandColors.focusDark.withValues(alpha: 0.25)
              : BrandColors.reward.withValues(alpha: 0.25));

    return Material(
      color: BrandColors.paper,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: borderColor, width: 1.2),
        borderRadius: BorderRadius.circular(BrandRadius.overlay),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (candidate.isOwned) ...[
              const BrandStatusChip(
                label: 'You own this',
                tone: BrandStatusTone.success,
              ),
              const SizedBox(height: 8),
            ],
            Text(
              candidate.rule.cardName ?? candidate.title,
              style: TextStyle(
                fontFamily: 'Manrope',
                color: BrandColors.ink,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _bookingPlatformMessage(candidate, widget.request),
              style: TextStyle(
                fontFamily: 'Manrope',
                color:
                    _isTiedToSearchedPlatform(candidate, widget.request)
                    ? BrandColors.successInk
                    : BrandColors.mutedInk,
                fontWeight:
                    _isTiedToSearchedPlatform(candidate, widget.request)
                    ? FontWeight.w600
                    : FontWeight.normal,
                fontSize: 12,
              ),
            ),
            if (widget.request.preferredCinema != null) ...[
              const SizedBox(height: 4),
              Text(
                _cinemaNotSupportedMessage,
                style: TextStyle(
                  fontFamily: 'Manrope',
                  color: BrandColors.mutedInk,
                  fontSize: 12,
                ),
              ),
            ],
            const SizedBox(height: 12),
            ResponsiveValueRow(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '₹${candidate.grossAmount.toStringAsFixed(0)}',
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        color: BrandColors.mutedInk,
                        fontSize: 13,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                    Text(
                      '₹${candidate.finalAmount.toStringAsFixed(0)}',
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        color: BrandColors.ink,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      '₹${effectiveTicketPrice.toStringAsFixed(0)} per ticket',
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        color: BrandColors.mutedInk,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                Text(
                  'Save ₹${candidate.savings.toStringAsFixed(0)}',
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontWeight: FontWeight.bold,
                    color: widget.isPotential
                        ? BrandColors.rewardInk
                        : BrandColors.focusDark,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _plainLanguageReason(candidate),
              style: TextStyle(
                fontFamily: 'Manrope',
                color: BrandColors.mutedInk,
                fontSize: 12,
                height: 1.4,
              ),
            ),
            if (widget.onConfirmPlatform != null && !_confirmed) ...[
              const SizedBox(height: 8),
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
              const SizedBox(height: 8),
              Text(
                'Thanks — this helps other users.',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 12,
                  color: BrandColors.focusDark,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

bool _isTiedToSearchedPlatform(
  MovieDealCandidate candidate,
  MovieTicketRequest request,
) {
  final selectedPlatform = request.preferredPlatform;
  if (selectedPlatform == null) return false;
  final eligible = eligibleMoviePlatformsFor(candidate.rule);
  return eligible.any((p) => p.toLowerCase() == selectedPlatform.toLowerCase());
}
