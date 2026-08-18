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
    final sortedEligible = eligiblePlatforms.toList()..sort();
    return tied
        ? 'Tied to $selectedPlatform.'
        : 'This offer is not tied to $selectedPlatform. Available on ${sortedEligible.join(', ')}.';
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

/// A bento tile's declared weight — how many grid columns it claims at
/// the current column count, and whether it gets the ink-filled "hero"
/// treatment (reserved for Guaranteed·Own — the one group that is both
/// certain AND already in the user's wallet, so it earns the strongest
/// visual claim on the page) versus the quieter outlined paper treatment
/// every other tile uses.
enum _TileWeight { hero, wide, standard, strip }

/// One cell in the results bento grid. Renders on [BrandColors.inkSoft]
/// with paper text for [_TileWeight.hero], [BrandColors.paper] with a
/// tone-colored outline otherwise — reusing the exact fill/outline pairing
/// BrandSurface already establishes for BrandSurfaceTone.evidence vs
/// .paper, just exposed here as a raw Container so a tile's title bar can
/// sit flush with its colored top edge (BrandSurface's uniform padding
/// doesn't allow that split).
class _BentoTile extends StatelessWidget {
  const _BentoTile({
    super.key,
    required this.weight,
    required this.accent,
    required this.title,
    required this.child,
  });

  final _TileWeight weight;
  final Color accent;
  final String title;
  final Widget child;

  bool get _isHero => weight == _TileWeight.hero;

  @override
  Widget build(BuildContext context) {
    final background = _isHero ? BrandColors.inkSoft : BrandColors.paper;
    final foreground = _isHero ? BrandColors.paper : BrandColors.ink;
    final mutedForeground = _isHero
        ? BrandColors.mutedPaper
        : BrandColors.mutedInk;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(BrandRadius.overlay),
        border: Border.all(
          color: _isHero
              ? accent.withValues(alpha: 0.4)
              : accent.withValues(alpha: 0.22),
          width: _isHero ? 1.4 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(BrandSpacing.md),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: foreground),
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
                        color: mutedForeground,
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

/// Lays [tiles] out as a bento grid: [columns] evenly-sized units per row
/// (computed from available width, matching the app's 600/1024 responsive
/// conventions used elsewhere), where a tile's [_GridItem.span] claims
/// that many units. Plain flow layout (Wrap of fixed-width boxes) rather
/// than a real CSS-grid engine — Flutter has none built in, and this is
/// the correct-enough primitive for a handful of variably-sized tiles
/// that never need to backfill a gap left by a taller neighbor.
class _GridItem {
  const _GridItem(this.span, this.child);
  final int span;
  final Widget child;
}

class _BentoGrid extends StatelessWidget {
  const _BentoGrid({required this.items});

  final List<_GridItem> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 1024 ? 3 : (width >= 600 ? 2 : 1);
        const gap = BrandSpacing.md;
        final unitWidth = (width - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final item in items)
              SizedBox(
                width:
                    (unitWidth * item.span.clamp(1, columns)) +
                    gap * (item.span.clamp(1, columns) - 1),
                child: item.child,
              ),
          ],
        );
      },
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

    final populatedRankedGroupCount = [
      recommendation.guaranteedOwned,
      recommendation.potentialOwned,
      recommendation.guaranteedOverall,
      recommendation.potentialOverall,
    ].where((group) => group.isNotEmpty).length;

    int rankedSpan(List<MovieDealCandidate> group, int preferredSpan) {
      if (group.isEmpty) return 1;
      if (populatedRankedGroupCount == 1) return 3;
      return preferredSpan;
    }

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

    Widget buildTileBody(
      String emptyNoun,
      List<MovieDealCandidate> group, {
      required bool isOverallFlavor,
    }) {
      if (group.isEmpty) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            'No $emptyNoun deals ${isOverallFlavor ? 'available' : 'on cards you own'} for this search.',
            style: const TextStyle(fontFamily: 'Manrope', fontSize: 12),
          ),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < group.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i == group.length - 1 ? 0 : 12),
              child: _DealRow(
                candidate: group[i],
                request: request,
                onConfirmPlatform: confirmCallbackFor(group[i]),
              ),
            ),
        ],
      );
    }

    final tiles = <_GridItem>[
      _GridItem(
        rankedSpan(recommendation.guaranteedOwned, 2),
        _BentoTile(
          key: const Key('movie-group-guaranteed-owned'),
          weight: recommendation.guaranteedOwned.isEmpty
              ? _TileWeight.standard
              : _TileWeight.hero,
          accent: BrandColors.focusDark,
          title: 'GUARANTEED · YOU OWN',
          child: buildTileBody(
            'guaranteed',
            recommendation.guaranteedOwned,
            isOverallFlavor: false,
          ),
        ),
      ),
      _GridItem(
        rankedSpan(recommendation.potentialOwned, 1),
        _BentoTile(
          key: const Key('movie-group-potential-owned'),
          weight: _TileWeight.standard,
          accent: BrandColors.rewardInk,
          title: 'POTENTIAL · YOU OWN',
          child: buildTileBody(
            'potential',
            recommendation.potentialOwned,
            isOverallFlavor: false,
          ),
        ),
      ),
      _GridItem(
        rankedSpan(recommendation.guaranteedOverall, 2),
        _BentoTile(
          key: const Key('movie-group-guaranteed-overall'),
          weight: _TileWeight.wide,
          accent: BrandColors.focusDark,
          title: 'GUARANTEED · OVERALL',
          child: buildTileBody(
            'guaranteed',
            recommendation.guaranteedOverall,
            isOverallFlavor: true,
          ),
        ),
      ),
      _GridItem(
        rankedSpan(recommendation.potentialOverall, 1),
        _BentoTile(
          key: const Key('movie-group-potential-overall'),
          weight: _TileWeight.standard,
          accent: BrandColors.rewardInk,
          title: 'POTENTIAL · OVERALL',
          child: buildTileBody(
            'potential',
            recommendation.potentialOverall,
            isOverallFlavor: true,
          ),
        ),
      ),
      if (rewardMultiplierCandidates.isNotEmpty)
        _GridItem(
          3,
          _BentoTile(
            weight: _TileWeight.strip,
            accent: BrandColors.mutedInk,
            title: 'REWARD RATE — NOT A TICKET-PRICE SAVING',
            child: _buildStripSection(
              rewardMultiplierCandidates,
              (c) => '${c.rule.cardName ?? c.title} — reward points rate',
              (c) => _plainLanguageReason(c),
            ),
          ),
        ),
      if (annualAllowanceCandidates.isNotEmpty)
        _GridItem(
          3,
          _BentoTile(
            weight: _TileWeight.strip,
            accent: BrandColors.mutedInk,
            title: 'ANNUAL ALLOWANCE — BALANCE NOT TRACKED',
            child: _buildStripSection(
              annualAllowanceCandidates,
              (c) => c.rule.cardName ?? c.title,
              (c) => c.explanation,
            ),
          ),
        ),
    ];

    return _BentoGrid(items: tiles);
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
  });

  final MovieDealCandidate candidate;
  final MovieTicketRequest request;
  final Future<void> Function()? onConfirmPlatform;

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
          const BrandStatusChip(
            label: 'You own this',
            tone: BrandStatusTone.success,
          ),
          const SizedBox(height: 4),
        ],
        Text(
          candidate.rule.cardName ?? candidate.title,
          style: const TextStyle(
            fontFamily: 'Manrope',
            fontWeight: FontWeight.bold,
            fontSize: 13,
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
        ? const BrandStatusChip(
            label: 'Not valid on selected platform',
            tone: BrandStatusTone.neutral,
          )
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
                style: const TextStyle(
                  fontFamily: 'Manrope',
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
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
        color: BrandColors.paper.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(BrandRadius.card),
        border: Border.all(
          color: BrandColors.paperDeep.withValues(alpha: 0.55),
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
                  MediaQuery.textScalerOf(context).scale(14) >= 1.5;
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
        ],
      ),
    );
  }
}
