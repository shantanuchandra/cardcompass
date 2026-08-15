// lib/features/benefits/movie_deals/screens/movie_deals_results.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/providers/repository_providers.dart';
import '../../../../core/providers/supabase_provider.dart';
import '../../../../core/theme/brand_tokens.dart';
import '../domain/movie_deal_candidate.dart';
import '../domain/movie_deal_rule.dart';
import '../domain/movie_platform_aliases.dart';
import '../domain/movie_ticket_request.dart';
import '../providers/movie_deals_provider.dart';

bool _hasNoUsageCapToVerify(MovieDealCandidate candidate) {
  final rule = candidate.rule;
  return rule.offerType == MovieDealOfferType.percentDiscount ||
      (rule.offerType == MovieDealOfferType.bogo &&
          rule.cycleRedemptionLimit == null) ||
      (rule.offerType == MovieDealOfferType.fixedDiscount &&
          rule.cycleAmountCap == null);
}

bool _isPotentialCandidate(MovieDealCandidate candidate) =>
    candidate.platformConfidence != MovieDealPlatformConfidence.explicit ||
    (candidate.usageConfidence != MovieDealUsageConfidence.verified &&
        !_hasNoUsageCapToVerify(candidate));

bool _isVerifiedForSearch(
  MovieDealCandidate candidate, {
  required bool isPotential,
}) => !isPotential && !_isPotentialCandidate(candidate);

String _bookingPlatformMessage(
  MovieDealCandidate candidate,
  MovieTicketRequest request,
) {
  final selectedPlatform = request.preferredPlatform;
  if (selectedPlatform != null) {
    return candidate.platformConfidence == MovieDealPlatformConfidence.explicit
        ? 'Book on $selectedPlatform.'
        : 'Selected platform: $selectedPlatform — this offer needs confirmation there.';
  }

  final eligiblePlatforms = eligibleMoviePlatformsFor(candidate.rule).toList()
    ..sort();
  if (eligiblePlatforms.isNotEmpty) {
    final platformLabel = eligiblePlatforms.join(', ');
    return eligiblePlatforms.length == 1
        ? 'Eligible booking platform: $platformLabel.'
        : 'Eligible booking platforms: $platformLabel.';
  }
  return candidate.platformConfidence ==
          MovieDealPlatformConfidence.communityConfirmed
      ? 'A booking platform has community confirmation, but the exact platform is unknown.'
      : 'Booking platform is not confirmed for this offer.';
}

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
    MovieDealOfferType.annualAllowance =>
      'This booking can use ₹${_formatAmount(candidate.savings)} from the card’s annual movie allowance.',
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
      data: (recommendation) =>
          _buildRecommendation(context, ref, recommendation),
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: CircularProgressIndicator(),
        ),
      ),
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

    final directCandidates = recommendation.candidates
        .where((c) => c.rule.offerType != MovieDealOfferType.rewardMultiplier)
        .toList();
    final guaranteedWinner =
        recommendation.bestGuaranteedOwned ??
        recommendation.bestGuaranteedOverall;
    final potentialWinner =
        recommendation.bestPotentialOwned ??
        recommendation.bestPotentialOverall;
    final winner = guaranteedWinner ?? potentialWinner;
    final winnerIsPotential =
        guaranteedWinner == null && potentialWinner != null;

    if (winner == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildNoDealCard(context),
          if (rewardMultiplierCandidates.isNotEmpty) ...[
            const SizedBox(height: 20),
            _buildRewardMultiplierSection(rewardMultiplierCandidates),
          ],
        ],
      );
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

    final alternatives = directCandidates
        .where(
          (candidate) =>
              candidate.cardId != winner.cardId ||
              candidate.benefitId != winner.benefitId,
        )
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _RecommendationCard(
          candidate: winner,
          request: request,
          isPotential: winnerIsPotential,
          onConfirmPlatform: confirmCallbackFor(winner),
        ),
        if (alternatives.isNotEmpty) ...[
          const SizedBox(height: 20),
          _buildAlternatives(alternatives),
        ],
        if (rewardMultiplierCandidates.isNotEmpty) ...[
          const SizedBox(height: 20),
          _buildRewardMultiplierSection(rewardMultiplierCandidates),
        ],
      ],
    );
  }

  Widget _buildAlternatives(List<MovieDealCandidate> candidates) {
    final eligible = candidates
        .where((candidate) => !_isPotentialCandidate(candidate))
        .toList();
    final potential = candidates.where(_isPotentialCandidate).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (eligible.isNotEmpty) ...[
          const _ResultSectionTitle('Other eligible options'),
          const SizedBox(height: 8),
          ...eligible.map(
            (candidate) =>
                _AlternativeRow(candidate: candidate, request: request),
          ),
        ],
        if (eligible.isNotEmpty && potential.isNotEmpty)
          const SizedBox(height: 12),
        if (potential.isNotEmpty) ...[
          const _ResultSectionTitle(
            'Potential options — confirm before booking',
          ),
          const SizedBox(height: 8),
          ...potential.map(
            (candidate) => _AlternativeRow(
              candidate: candidate,
              request: request,
              isPotential: true,
            ),
          ),
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
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: BrandColors.paper,
                borderRadius: BorderRadius.circular(BrandRadius.card),
                border: Border.all(color: BrandColors.paperDeep),
              ),
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

  Widget _buildNoDealCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: BrandColors.paper,
        borderRadius: BorderRadius.circular(BrandRadius.overlay),
        border: Border.all(color: BrandColors.paperDeep),
      ),
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

class _RecommendationCard extends StatefulWidget {
  const _RecommendationCard({
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
  State<_RecommendationCard> createState() => _RecommendationCardState();
}

class _RecommendationCardState extends State<_RecommendationCard> {
  bool _confirmed = false;

  @override
  Widget build(BuildContext context) {
    final candidate = widget.candidate;
    final effectiveTicketPrice =
        candidate.finalAmount / widget.request.numberOfTickets;
    final owned = candidate.isOwned;
    final verifiedEligibility = _isVerifiedForSearch(
      candidate,
      isPotential: widget.isPotential,
    );
    final borderColor = widget.isPotential
        ? BrandColors.mutedInk.withValues(alpha: 0.3)
        : (owned
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
            Text(
              'Best option',
              style: TextStyle(
                fontFamily: 'Manrope',
                fontWeight: FontWeight.bold,
                color: BrandColors.mutedInk,
                fontSize: 12,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            const _ResultSectionTitle('Recommended route'),
            const SizedBox(height: 4),
            Text(
              'Use ${candidate.rule.cardName ?? candidate.title} for ${candidate.title}.',
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
                color: BrandColors.mutedInk,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              verifiedEligibility
                  ? (owned
                        ? 'Eligible for this search on a card you own.'
                        : 'Eligible for this search on a card you do not own.')
                  : 'Potential option — check availability and remaining usage before booking.',
              style: TextStyle(
                fontFamily: 'Manrope',
                color: BrandColors.mutedInk,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 16),
            _ResultMetric(
              label: 'Expected saving',
              value: '₹${candidate.savings.toStringAsFixed(0)}',
            ),
            const SizedBox(height: 12),
            _ResultMetric(
              label: 'Effective ticket price',
              value: '₹${effectiveTicketPrice.toStringAsFixed(0)} per ticket',
            ),
            const SizedBox(height: 16),
            Text(
              'Why this is recommended',
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: BrandColors.mutedInk,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _plainLanguageReason(candidate),
              style: TextStyle(
                fontFamily: 'Manrope',
                color: BrandColors.mutedInk,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            if (widget.isPotential)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: BrandColors.rewardInk.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Potential — remaining balance not verified',
                    style: TextStyle(
                      fontFamily: 'Manrope',
                      fontSize: 12,
                      color: BrandColors.rewardInk,
                    ),
                  ),
                ),
              ),
            if (candidate.platformConfidence !=
                MovieDealPlatformConfidence.explicit)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: BrandColors.mutedInk.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Platform not confirmed for this offer',
                    style: TextStyle(
                      fontFamily: 'Manrope',
                      fontSize: 12,
                      color: BrandColors.mutedInk,
                    ),
                  ),
                ),
              ),
            _CalculationDisclosure(
              candidate: candidate,
              isPotential: widget.isPotential,
            ),
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

class _ResultMetric extends StatelessWidget {
  const _ResultMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: TextStyle(
          fontFamily: 'Manrope',
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: BrandColors.mutedInk,
          letterSpacing: 0.4,
        ),
      ),
      const SizedBox(height: 2),
      Text(
        value,
        style: TextStyle(
          fontFamily: 'Manrope',
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: BrandColors.focusDark,
        ),
      ),
    ],
  );
}

class _ResultSectionTitle extends StatelessWidget {
  const _ResultSectionTitle(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: TextStyle(
      fontFamily: 'Manrope',
      fontSize: 12,
      fontWeight: FontWeight.bold,
      color: BrandColors.mutedInk,
      letterSpacing: 0.4,
    ),
  );
}

class _AlternativeRow extends StatelessWidget {
  const _AlternativeRow({
    required this.candidate,
    required this.request,
    this.isPotential = false,
  });

  final MovieDealCandidate candidate;
  final MovieTicketRequest request;
  final bool isPotential;

  @override
  Widget build(BuildContext context) {
    final price = candidate.finalAmount / request.numberOfTickets;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: BrandColors.paper,
          border: Border.all(color: BrandColors.paperDeep),
          borderRadius: BorderRadius.circular(BrandRadius.card),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              candidate.rule.cardName ?? candidate.title,
              style: TextStyle(
                fontFamily: 'Manrope',
                fontWeight: FontWeight.bold,
                color: BrandColors.ink,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Save ₹${candidate.savings.toStringAsFixed(0)} · ₹${price.toStringAsFixed(0)} per ticket',
              style: TextStyle(
                fontFamily: 'Manrope',
                color: BrandColors.mutedInk,
                fontSize: 12,
              ),
            ),
            if (isPotential) ...[
              const SizedBox(height: 4),
              Text(
                'Potential — confirm before booking',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  color: BrandColors.mutedInk,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CalculationDisclosure extends StatelessWidget {
  const _CalculationDisclosure({
    required this.candidate,
    required this.isPotential,
  });

  final MovieDealCandidate candidate;
  final bool isPotential;

  @override
  Widget build(BuildContext context) {
    final rule = candidate.rule;
    final caps = [
      if (rule.perTransactionCap != null)
        'Up to ₹${rule.perTransactionCap!.toStringAsFixed(0)} per booking',
      if (rule.cycleAmountCap != null)
        'Up to ₹${rule.cycleAmountCap!.toStringAsFixed(0)} in this cycle',
      if (rule.annualCap != null)
        'Up to ₹${rule.annualCap!.toStringAsFixed(0)} each year',
    ];
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      title: const Text('Show calculation'),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Booking total',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontWeight: FontWeight.bold,
                  color: BrandColors.mutedInk,
                ),
              ),
              Text(
                '₹${candidate.grossAmount.toStringAsFixed(0)} − ₹${candidate.savings.toStringAsFixed(0)} = ₹${candidate.finalAmount.toStringAsFixed(0)}',
                style: TextStyle(
                  fontFamily: 'IBM Plex Mono',
                  color: BrandColors.ink,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _isVerifiedForSearch(candidate, isPotential: isPotential)
                    ? 'Eligibility: confirmed for this search.'
                    : 'Eligibility: potential — platform or remaining usage needs confirmation.',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  color: BrandColors.mutedInk,
                  fontSize: 12,
                ),
              ),
              if (caps.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  'Offer cap: ${caps.join('; ')}.',
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    color: BrandColors.mutedInk,
                    fontSize: 12,
                  ),
                ),
              ],
              if (rule.cycleRedemptionLimit != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Monthly usage limit: ${rule.cycleRedemptionLimit} redemption${rule.cycleRedemptionLimit == 1 ? '' : 's'} per month.',
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    color: BrandColors.mutedInk,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
