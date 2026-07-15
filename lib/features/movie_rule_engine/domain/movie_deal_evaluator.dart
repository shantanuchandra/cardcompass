import 'models/movie_deal_candidate.dart';
import 'models/movie_deal_rule.dart';
import 'models/movie_ticket_request.dart';

export 'models/movie_deal_candidate.dart';

MovieDealsRecommendation evaluateMovieDeals({
  required MovieTicketRequest request,
  required List<MovieDealRule> rules,
  required Map<String, MovieDealContext> contexts,
  required DateTime now,
}) {
  final candidates = <MovieDealCandidate>[];
  final rejected = <RejectedMovieDealCandidate>[];
  final sanitizedRequest = _sanitizeRequest(request);

  for (final rule in rules) {
    final context = contexts[rule.catalogCardId] ?? const MovieDealContext();
    final reason = _ineligibilityReason(rule, sanitizedRequest, context, now);
    if (reason != null) {
      rejected.add(RejectedMovieDealCandidate(
        cardId: rule.catalogCardId,
        benefitId: rule.benefitId,
        rule: rule,
        reason: reason,
      ));
      continue;
    }

    final gross = sanitizedRequest.totalAmount;
    final saving = _calculateSavings(rule, sanitizedRequest, gross);
    candidates.add(MovieDealCandidate(
      cardId: rule.catalogCardId,
      benefitId: rule.benefitId,
      title: rule.title,
      rule: rule,
      isOwned: context.isOwned,
      grossAmount: gross,
      savings: saving,
      finalAmount: gross - saving,
      usageConfidence: context.usageConfidence,
      remainingVerifiedUsage: _remainingUsage(rule, context),
      explanation: _explanation(rule, saving, context.usageConfidence),
    ));
  }

  candidates.sort(_compareCandidates);
  final owned = candidates.where((candidate) => candidate.isOwned).toList();
  return MovieDealsRecommendation(
    candidates: candidates,
    rejectedCandidates: rejected,
    bestOwned: owned.isEmpty ? null : owned.first,
    bestOverall: candidates.isEmpty ? null : candidates.first,
  );
}

MovieTicketRequest _sanitizeRequest(MovieTicketRequest request) =>
    MovieTicketRequest(
      numberOfTickets:
          request.numberOfTickets < 0 ? 0 : request.numberOfTickets,
      pricePerTicket: request.pricePerTicket < 0 ? 0 : request.pricePerTicket,
      preferredCinema: request.preferredCinema,
      preferredPlatform: request.preferredPlatform,
    );

String? _ineligibilityReason(
  MovieDealRule rule,
  MovieTicketRequest request,
  MovieDealContext context,
  DateTime now,
) {
  if (rule.validityStart != null && now.isBefore(rule.validityStart!))
    return 'Not active yet.';
  if (rule.validityEnd != null && now.isAfter(rule.validityEnd!))
    return 'Rule has expired.';
  if (!_matchesWeekday(rule.validWeekdays, now))
    return 'Not valid on this weekday.';
  if (!_matches(rule.platforms, request.preferredPlatform))
    return 'Platform is not eligible.';
  if (!_matches(rule.cinemas, request.preferredCinema))
    return 'Cinema is not eligible.';
  if (_excluded(rule.exclusions, request))
    return 'Request matches an exclusion.';
  if (rule.minimumTransaction != null &&
      request.totalAmount < rule.minimumTransaction!)
    return 'Minimum spend is not met.';
  if (rule.transactionTicketLimit != null &&
      request.numberOfTickets > rule.transactionTicketLimit!)
    return 'Ticket limit per transaction is exceeded.';
  if (rule.cycleTransactionLimit != null &&
      context.usageConfidence == MovieDealUsageConfidence.verified &&
      context.usedTransactions >= rule.cycleTransactionLimit!)
    return 'Transaction limit has been used.';
  if (rule.cycleTicketLimit != null &&
      context.usageConfidence == MovieDealUsageConfidence.verified &&
      request.numberOfTickets > _remainingUsage(rule, context)!)
    return 'Ticket limit for this request is exceeded.';
  if (rule.milestoneThreshold != null) {
    if (context.milestoneSpend == null ||
        context.usageConfidence == MovieDealUsageConfidence.unavailable)
      return 'Milestone progress is unavailable.';
    if (context.milestoneSpend! < rule.milestoneThreshold!)
      return 'Milestone threshold is not met.';
  }
  return null;
}

bool _matches(Set<String> allowed, String? actual) =>
    allowed.isEmpty ||
    (actual != null &&
        allowed.any((value) => value.toLowerCase() == actual.toLowerCase()));

bool _excluded(Set<String> exclusions, MovieTicketRequest request) {
  final values =
      [request.preferredPlatform, request.preferredCinema].whereType<String>();
  return values.any((value) => exclusions
      .any((excluded) => excluded.toLowerCase() == value.toLowerCase()));
}

bool _matchesWeekday(Set<String> weekdays, DateTime now) {
  if (weekdays.isEmpty) return true;
  const names = [
    '',
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
    'sunday'
  ];
  final name = names[now.weekday];
  final shortName = name.substring(0, 3);
  return weekdays.any(
      (day) => day.toLowerCase() == name || day.toLowerCase() == shortName);
}

double _calculateSavings(
    MovieDealRule rule, MovieTicketRequest request, double gross) {
  final tickets = request.numberOfTickets;
  final price = request.pricePerTicket;
  double savings;
  switch (rule.offerType) {
    case MovieDealOfferType.bogo:
      final buy = rule.buyCount ?? 0;
      final free = rule.freeCount ?? 0;
      savings = buy + free > 0 ? tickets ~/ (buy + free) * free * price : 0;
    case MovieDealOfferType.percentDiscount:
    case MovieDealOfferType.cashback:
      savings = gross * ((rule.discountPercent ?? 0) / 100);
    case MovieDealOfferType.fixedDiscount:
    case MovieDealOfferType.voucher:
      savings = rule.fixedAmount ?? 0;
    case MovieDealOfferType.freeTickets:
      savings = (rule.milestoneReward ?? rule.freeCount ?? 0) * price;
  }
  if (rule.maximumDiscount != null && savings > rule.maximumDiscount!)
    savings = rule.maximumDiscount!;
  return savings.clamp(0, gross).toDouble();
}

int? _remainingUsage(MovieDealRule rule, MovieDealContext context) {
  if (context.usageConfidence != MovieDealUsageConfidence.verified) return null;
  if (rule.cycleTicketLimit != null)
    return (rule.cycleTicketLimit! - context.usedTickets)
        .clamp(0, rule.cycleTicketLimit!);
  if (rule.cycleTransactionLimit != null)
    return (rule.cycleTransactionLimit! - context.usedTransactions)
        .clamp(0, rule.cycleTransactionLimit!);
  return null;
}

String _explanation(MovieDealRule rule, double savings,
        MovieDealUsageConfidence confidence) =>
    '${rule.offerType.name} saves ₹${savings.toStringAsFixed(2)} (${confidence.name} usage).';

int _compareCandidates(MovieDealCandidate left, MovieDealCandidate right) {
  var result = right.savings.compareTo(left.savings);
  if (result != 0) return result;
  result = left.finalAmount.compareTo(right.finalAmount);
  if (result != 0) return result;
  result = _confidenceRank(right.usageConfidence)
      .compareTo(_confidenceRank(left.usageConfidence));
  if (result != 0) return result;
  result = right.rule.displayPriority.compareTo(left.rule.displayPriority);
  if (result != 0) return result;
  result = left.cardId.compareTo(right.cardId);
  return result != 0 ? result : left.benefitId.compareTo(right.benefitId);
}

int _confidenceRank(MovieDealUsageConfidence confidence) =>
    switch (confidence) {
      MovieDealUsageConfidence.verified => 2,
      MovieDealUsageConfidence.unverified => 1,
      MovieDealUsageConfidence.unavailable => 0,
    };
