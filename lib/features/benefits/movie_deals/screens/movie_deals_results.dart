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
import '../../../feedback/contextual_feedback_sheet.dart';
import '../../../feedback/feedback_models.dart';
import '../../../feedback/feedback_repository.dart';

String _formatAmount(double amount) => amount == amount.roundToDouble()
    ? amount.toStringAsFixed(0)
    : amount.toStringAsFixed(2);

String _platformDisplayLabel(String platform) =>
    platform.toLowerCase() == 'zomato' ? 'Zomato/District' : platform;

String _bankAndCardLabel(MovieDealCandidate candidate) {
  final bank = candidate.rule.bankName?.trim();
  final card = candidate.rule.cardName?.trim();
  if (bank != null && bank.isNotEmpty && card != null && card.isNotEmpty) {
    return '$bank — $card';
  }
  return card?.isNotEmpty == true
      ? card!
      : bank?.isNotEmpty == true
      ? bank!
      : candidate.title;
}

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
    final sortedEligible = eligiblePlatforms.map(_platformDisplayLabel).toList()
      ..sort();
    return tied
        ? 'Tied to ${_platformDisplayLabel(selectedPlatform)}.'
        : 'This offer is not tied to $selectedPlatform. Available on ${sortedEligible.join(', ')}.';
  }
  if (selectedPlatform != null) {
    return candidate.platformConfidence == MovieDealPlatformConfidence.explicit
        ? 'Book on ${_platformDisplayLabel(selectedPlatform)}.'
        : 'Selected platform: ${_platformDisplayLabel(selectedPlatform)} — this offer needs confirmation there.';
  }

  final sortedEligible = eligiblePlatforms.map(_platformDisplayLabel).toList()
    ..sort();
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

bool _isTiedToSearchedPlatform(
  MovieDealCandidate candidate,
  MovieTicketRequest request,
) {
  final selectedPlatform = request.preferredPlatform;
  if (selectedPlatform == null) return false;
  final eligible = eligibleMoviePlatformsFor(candidate.rule);
  return eligible.any((p) => p.toLowerCase() == selectedPlatform.toLowerCase());
}

/// A cinema was searched, but no benefit data in this schema is ever tied
/// to a specific chain — cinema never affects eligibility anywhere (see
/// MovieTicketRequest's own doc comment). Purely informational, shown on
/// every card once a cinema is selected, never a confidence signal.
const _cinemaNotSupportedMessage =
    'Cinema filtering is not yet supported — no benefit data is tied to a specific chain.';

class _RankedDeal {
  _RankedDeal(this.candidate, this.groupLabel);

  final MovieDealCandidate candidate;
  String groupLabel;
}

/// A bento tile's declared weight — how many grid columns it claims at
/// the current column count, and whether it gets the ink-filled "hero"
/// treatment (reserved for Guaranteed·Own — the one group that is both
/// certain AND already in the user's wallet, so it earns the strongest
/// visual claim on the page) versus the quieter outlined paper treatment
/// every other tile uses.
/// One cell in the results bento grid. Renders on [BrandColors.inkSoft]
/// with paper text for [_TileWeight.hero], [BrandColors.paper] with a
/// tone-colored outline otherwise — reusing the exact fill/outline pairing
/// BrandSurface already establishes for BrandSurfaceTone.evidence vs
/// .paper, just exposed here as a raw Container so a tile's title bar can
/// sit flush with its colored top edge (BrandSurface's uniform padding
/// doesn't allow that split).
class _BentoTile extends StatelessWidget {
  const _BentoTile({
    required this.accent,
    required this.title,
    required this.child,
  });

  final Color accent;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: BrandColors.paper,
        borderRadius: BorderRadius.circular(BrandRadius.overlay),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(BrandSpacing.md),
        child: DefaultTextStyle.merge(
          style: const TextStyle(color: BrandColors.ink),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        letterSpacing: 0.5,
                        color: BrandColors.mutedInk,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: BrandSpacing.sm),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

/// Bento-grid redesign of design spec §8's four ranked groups: rather
/// than two stacked columns, every group (and the reward-rate/annual-
/// allowance dedicated sections) is its own tile in one full-width grid,
/// weighted by how much attention it's earned — Guaranteed·You own gets
/// the ink-filled hero treatment (certain AND already in-wallet),
/// Guaranteed·Overall spans wide, the two Potential tiers are standard
/// weight in the app's quieter outlined-paper tone, and reward-rate/
/// annual-allowance collapse into a slim single-row strip since they were
/// always explicitly "not a direct saving." Every eligible candidate in
/// a group still appears — as a compact row inside its tile — so a user
/// comparing offers (e.g. a ₹700 potential fixedDiscount against a ₹70
/// guaranteed percentDiscount) can still see all of them.
class MovieDealsResults extends ConsumerWidget {
  const MovieDealsResults({super.key, required this.request});

  final MovieTicketRequest request;

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
    final annualAllowanceCandidates = recommendation.candidates
        .where((c) => c.rule.offerType == MovieDealOfferType.annualAllowance)
        .toList();

    final hasAnyRanked =
        recommendation.guaranteedOwned.isNotEmpty ||
        recommendation.guaranteedOverall.isNotEmpty ||
        recommendation.potentialOwned.isNotEmpty ||
        recommendation.potentialOverall.isNotEmpty;

    if (!hasAnyRanked &&
        rewardMultiplierCandidates.isEmpty &&
        annualAllowanceCandidates.isEmpty) {
      return _buildNoDealCard(context);
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

    final ranked = <_RankedDeal>[];
    final seen = <String>{};
    void addGroup(List<MovieDealCandidate> candidates, String label) {
      for (final candidate in candidates) {
        final identity = '${candidate.cardId}|${candidate.benefitId}';
        if (seen.add(identity)) {
          ranked.add(_RankedDeal(candidate, label));
        } else {
          final existing = ranked.firstWhere(
            (deal) =>
                deal.candidate.cardId == candidate.cardId &&
                deal.candidate.benefitId == candidate.benefitId,
          );
          existing.groupLabel = '${existing.groupLabel} / $label';
        }
      }
    }

    addGroup(recommendation.guaranteedOwned, 'GUARANTEED · YOU OWN');
    addGroup(recommendation.guaranteedOverall, 'GUARANTEED · OVERALL');
    addGroup(recommendation.potentialOwned, 'POTENTIAL · YOU OWN');
    addGroup(recommendation.potentialOverall, 'POTENTIAL · OVERALL');

    final emptyGroups = <(String, String)>[
      if (recommendation.guaranteedOwned.isEmpty)
        ('GUARANTEED · YOU OWN', 'No guaranteed deals on cards you own'),
      if (recommendation.potentialOwned.isEmpty)
        ('POTENTIAL · YOU OWN', 'No potential deals on cards you own'),
      if (recommendation.guaranteedOverall.isEmpty)
        ('GUARANTEED · OVERALL', 'No guaranteed deals available'),
      if (recommendation.potentialOverall.isEmpty)
        ('POTENTIAL · OVERALL', 'No potential deals available'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (ranked.isNotEmpty) ...[
          _BestMatchCard(
            deal: ranked.first,
            request: request,
            onConfirmPlatform: confirmCallbackFor(ranked.first.candidate),
          ),
          if (ranked.length > 1) ...[
            const SizedBox(height: BrandSpacing.lg),
            const Text(
              'Other cards to consider',
              style: TextStyle(
                fontFamily: 'Manrope',
                fontWeight: FontWeight.w800,
                fontSize: 18,
                color: BrandColors.ink,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Compare each bank and card variant side by side.',
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 13,
                color: BrandColors.mutedInk,
              ),
            ),
            const SizedBox(height: BrandSpacing.md),
            _ComparisonGrid(
              deals: ranked.skip(1).toList(),
              request: request,
              confirmCallbackFor: confirmCallbackFor,
            ),
          ],
        ],
        if (emptyGroups.isNotEmpty) ...[
          const SizedBox(height: BrandSpacing.md),
          _EmptyGroupsSummary(groups: emptyGroups),
        ],
        if (rewardMultiplierCandidates.isNotEmpty) ...[
          const SizedBox(height: BrandSpacing.md),
          _BentoTile(
            accent: BrandColors.mutedInk,
            title: 'REWARD RATE — NOT A TICKET-PRICE SAVING',
            child: _buildStripSection(
              rewardMultiplierCandidates,
              (c) => '${c.rule.cardName ?? c.title} — reward points rate',
              (c) => _plainLanguageReason(c),
            ),
          ),
        ],
        if (annualAllowanceCandidates.isNotEmpty) ...[
          const SizedBox(height: BrandSpacing.md),
          _BentoTile(
            accent: BrandColors.mutedInk,
            title: 'ANNUAL ALLOWANCE — BALANCE NOT TRACKED',
            child: _buildStripSection(
              annualAllowanceCandidates,
              _bankAndCardLabel,
              (c) => '${c.explanation}\n${_bookingPlatformMessage(c, request)}',
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildStripSection(
    List<MovieDealCandidate> candidates,
    String Function(MovieDealCandidate) titleFor,
    String Function(MovieDealCandidate) subtitleFor,
  ) {
    return Wrap(
      spacing: BrandSpacing.md,
      runSpacing: BrandSpacing.sm,
      children: candidates
          .map(
            (c) => ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    titleFor(c),
                    style: const TextStyle(
                      fontFamily: 'Manrope',
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitleFor(c),
                    style: const TextStyle(fontFamily: 'Manrope', fontSize: 12),
                  ),
                ],
              ),
            ),
          )
          .toList(),
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

class _BestMatchCard extends StatelessWidget {
  const _BestMatchCard({
    required this.deal,
    required this.request,
    this.onConfirmPlatform,
  });

  final _RankedDeal deal;
  final MovieTicketRequest request;
  final Future<void> Function()? onConfirmPlatform;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('movie-best-match'),
      width: double.infinity,
      padding: const EdgeInsets.all(BrandSpacing.lg),
      decoration: BoxDecoration(
        color: BrandColors.inkSoft,
        borderRadius: BorderRadius.circular(BrandRadius.overlay),
        border: Border.all(
          color: BrandColors.focusDark.withValues(alpha: 0.55),
          width: 1.4,
        ),
      ),
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: BrandColors.paper),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                const heading = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Best match',
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontWeight: FontWeight.w800,
                        fontSize: 20,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Strongest eligible option for this booking',
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 12,
                        color: BrandColors.mutedPaper,
                      ),
                    ),
                  ],
                );
                final status = _DealStatusLabel(label: deal.groupLabel);
                if (constraints.maxWidth < 560 ||
                    MediaQuery.textScalerOf(context).scale(1) >= 1.5) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      heading,
                      const SizedBox(height: BrandSpacing.sm),
                      status,
                    ],
                  );
                }
                return Row(
                  children: [
                    const Expanded(child: heading),
                    const SizedBox(width: BrandSpacing.md),
                    Flexible(child: status),
                  ],
                );
              },
            ),
            const SizedBox(height: BrandSpacing.md),
            SizedBox(
              width: double.infinity,
              child: _DealRow(
                candidate: deal.candidate,
                request: request,
                onConfirmPlatform: onConfirmPlatform,
                featured: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DealStatusLabel extends StatelessWidget {
  const _DealStatusLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final foreground =
        DefaultTextStyle.of(context).style.color ?? BrandColors.ink;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: BrandColors.focusDark.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(BrandRadius.pill),
        border: Border.all(color: BrandColors.focusDark.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        softWrap: true,
        style: TextStyle(
          fontFamily: 'Manrope',
          fontWeight: FontWeight.w700,
          fontSize: 12,
          height: 1.2,
          color: foreground,
        ),
      ),
    );
  }
}

class _ComparisonGrid extends StatelessWidget {
  const _ComparisonGrid({
    required this.deals,
    required this.request,
    required this.confirmCallbackFor,
  });

  final List<_RankedDeal> deals;
  final MovieTicketRequest request;
  final Future<void> Function()? Function(MovieDealCandidate)
  confirmCallbackFor;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1000
            ? 3
            : (constraints.maxWidth >= 640 ? 2 : 1);
        const gap = BrandSpacing.md;
        final cardWidth =
            (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final deal in deals)
              SizedBox(
                width: cardWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 6),
                      child: Text(
                        deal.groupLabel.toUpperCase(),
                        style: const TextStyle(
                          fontFamily: 'Manrope',
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          letterSpacing: 0.5,
                          color: BrandColors.mutedInk,
                        ),
                      ),
                    ),
                    _DealRow(
                      candidate: deal.candidate,
                      request: request,
                      onConfirmPlatform: confirmCallbackFor(deal.candidate),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _EmptyGroupsSummary extends StatelessWidget {
  const _EmptyGroupsSummary({required this.groups});

  final List<(String, String)> groups;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('movie-empty-groups-summary'),
      width: double.infinity,
      padding: const EdgeInsets.all(BrandSpacing.md),
      decoration: BoxDecoration(
        color: BrandColors.paper,
        borderRadius: BorderRadius.circular(BrandRadius.card),
        border: Border.all(color: BrandColors.paperDeep),
      ),
      child: Wrap(
        spacing: BrandSpacing.lg,
        runSpacing: BrandSpacing.sm,
        children: [
          for (final group in groups)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    group.$1,
                    style: const TextStyle(
                      fontFamily: 'Manrope',
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      letterSpacing: 0.5,
                      color: BrandColors.mutedInk,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    group.$2,
                    style: const TextStyle(
                      fontFamily: 'Manrope',
                      fontSize: 12,
                      color: BrandColors.ink,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// One candidate inside a bento tile — a compact row rather than the
/// prior standalone card, since a tile now groups multiple candidates.
/// Keeps every existing piece of information (ownership badge, platform-
/// tie copy, cinema note, price breakdown, plain-language reason, the
/// community platform-confirmation button) at a tighter density.
class _DealRow extends StatefulWidget {
  const _DealRow({
    required this.candidate,
    required this.request,
    this.onConfirmPlatform,
    this.featured = false,
  });

  final MovieDealCandidate candidate;
  final MovieTicketRequest request;
  final Future<void> Function()? onConfirmPlatform;
  final bool featured;

  @override
  State<_DealRow> createState() => _DealRowState();
}

class _DealRowState extends State<_DealRow> {
  bool _confirmed = false;

  @override
  Widget build(BuildContext context) {
    final candidate = widget.candidate;
    final effectiveTicketPrice =
        candidate.finalAmount / widget.request.numberOfTickets;
    final tied = _isTiedToSearchedPlatform(candidate, widget.request);
    final eligiblePlatforms = eligibleMoviePlatformsFor(candidate.rule);
    final hasExplicitPlatformMismatch =
        widget.request.preferredPlatform != null &&
        eligiblePlatforms.isNotEmpty &&
        !tied;

    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (candidate.isOwned) ...[
          const _DealStatusLabel(label: 'You own this'),
          const SizedBox(height: 4),
        ],
        Text(
          candidate.rule.cardName ?? candidate.title,
          style: TextStyle(
            fontFamily: 'Manrope',
            fontWeight: FontWeight.bold,
            fontSize: widget.featured ? 17 : 14,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _bookingPlatformMessage(candidate, widget.request),
          style: TextStyle(
            fontFamily: 'Manrope',
            fontWeight: tied ? FontWeight.w600 : FontWeight.normal,
            fontSize: 12,
          ),
        ),
        if (widget.request.preferredCinema != null)
          const Text(
            _cinemaNotSupportedMessage,
            style: TextStyle(fontFamily: 'Manrope', fontSize: 12),
          ),
        const SizedBox(height: 4),
        if (!hasExplicitPlatformMismatch)
          Text(
            _plainLanguageReason(candidate),
            style: const TextStyle(
              fontFamily: 'Manrope',
              fontSize: 12,
              height: 1.35,
            ),
          ),
      ],
    );
    final priceBlock = hasExplicitPlatformMismatch
        ? const _DealStatusLabel(label: 'Not valid on selected platform')
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '₹${candidate.grossAmount.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 12,
                  decoration: TextDecoration.lineThrough,
                ),
              ),
              Text(
                '₹${candidate.finalAmount.toStringAsFixed(0)}',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontWeight: FontWeight.bold,
                  fontSize: widget.featured ? 24 : 18,
                ),
              ),
              Text(
                'Save ₹${candidate.savings.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontFamily: 'Manrope',
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              Text(
                '₹${effectiveTicketPrice.toStringAsFixed(0)}/ticket',
                style: const TextStyle(fontFamily: 'Manrope', fontSize: 12),
              ),
            ],
          );

    return Container(
      key: Key('movie-card-option-${candidate.cardId}'),
      padding: const EdgeInsets.all(BrandSpacing.md),
      decoration: BoxDecoration(
        color: widget.featured
            ? BrandColors.paper.withValues(alpha: 0.07)
            : BrandColors.paper,
        borderRadius: BorderRadius.circular(BrandRadius.card),
        border: Border.all(
          color: widget.featured
              ? BrandColors.paper.withValues(alpha: 0.22)
              : BrandColors.paperDeep,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (candidate.rule.bankName != null) ...[
            Text(
              candidate.rule.bankName!,
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.7,
                color: DefaultTextStyle.of(
                  context,
                ).style.color?.withValues(alpha: 0.72),
              ),
            ),
            const SizedBox(height: 2),
          ],
          // A genuine Row + Expanded, not ResponsiveValueRow — that shared
          // component's row-mode is a bare `Row(mainAxisSize: min)` with no
          // Expanded on either child, which is fine for short metric-style
          // content but leaves prose Text widgets (the platform/reason
          // sentences here) with no width ceiling to wrap against; their
          // own intrinsic on-one-line width can then exceed the tile and
          // overflow the whole Row (confirmed: reproduced reliably at
          // certain tile widths with real candidate text). Expanded gives
          // the details column a real constraint to wrap within; the
          // narrow-width stack still needs its own explicit switch below,
          // since a plain Row+Expanded never stacks on its own.
          LayoutBuilder(
            builder: (context, constraints) {
              final shouldStack =
                  constraints.maxWidth < 320 ||
                  MediaQuery.textScalerOf(context).scale(1) >= 1.5;
              if (shouldStack) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [details, const SizedBox(height: 8), priceBlock],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: details),
                  const SizedBox(width: 12),
                  priceBlock,
                ],
              );
            },
          ),
          if (widget.onConfirmPlatform != null && !_confirmed)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                ),
                onPressed: () async {
                  await widget.onConfirmPlatform!();
                  if (mounted) setState(() => _confirmed = true);
                },
                child: const Text(
                  'Did this work here? Let us know',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ),
          if (_confirmed)
            const Text(
              'Thanks — this helps other users.',
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 12,
                color: BrandColors.focusDark,
              ),
            ),
          _RecommendationFeedbackAction(
            request: widget.request,
            candidate: candidate,
          ),
        ],
      ),
    );
  }
}

class _RecommendationFeedbackAction extends StatefulWidget {
  const _RecommendationFeedbackAction({
    required this.request,
    required this.candidate,
  });

  final MovieTicketRequest request;
  final MovieDealCandidate candidate;

  @override
  State<_RecommendationFeedbackAction> createState() =>
      _RecommendationFeedbackActionState();
}

class _RecommendationFeedbackActionState
    extends State<_RecommendationFeedbackAction> {
  bool _opening = false;

  Future<RecommendationFeedbackTarget> _createTarget() {
    final request = widget.request;
    final candidate = widget.candidate;
    final safeInput = <String, Object?>{
      'number_of_tickets': request.numberOfTickets,
      'price_per_ticket': request.pricePerTicket,
      if (request.preferredPlatform != null)
        'preferred_platform': request.preferredPlatform!.characters
            .take(80)
            .toString(),
      if (request.preferredCinema != null)
        'preferred_cinema': request.preferredCinema!.characters
            .take(80)
            .toString(),
    };
    return FeedbackRepositoryScope.of(context).createRecommendationTarget(
      RecommendationTraceInput(
        safeInputContext: safeInput,
        outputSnapshot: {
          'selected_card_id': candidate.cardId,
          'selected_benefit_id': candidate.benefitId,
          'savings': candidate.savings,
          'final_amount': candidate.finalAmount,
        },
        cardIds: [candidate.cardId],
        benefitIds: [candidate.benefitId],
        engineVersion: 'movie-deals-v2',
      ),
    );
  }

  Future<void> _open() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final target = await _createTarget();
      if (!mounted) return;
      final candidate = widget.candidate;
      await showContextualFeedbackSheet(
        context,
        target: target,
        preview:
            '${(candidate.rule.cardName ?? candidate.title).characters.take(80).toString()} · Save ₹${candidate.savings.toStringAsFixed(0)}',
        recreateTarget: _createTarget,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('Could not open feedback. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label:
        'Give feedback about ${widget.candidate.rule.cardName ?? widget.candidate.title}',
    excludeSemantics: true,
    child: TextButton.icon(
      onPressed: _opening ? null : _open,
      icon: _opening
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.rate_review_outlined, size: 18),
      label: const Text('Give feedback'),
    ),
  );
}
