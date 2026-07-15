/// The benefit and card data required to normalize one movie-deal record.
class MovieBenefitSource {
  const MovieBenefitSource({
    required this.benefitId,
    required this.catalogCardId,
    required this.title,
    required this.valueConfig,
    this.sourceUrl,
    this.cardName,
    this.displayPriority = 0,
  });

  final String benefitId;
  final String catalogCardId;
  final String title;
  final Map<String, dynamic> valueConfig;
  final String? sourceUrl;
  final String? cardName;
  final int displayPriority;
}

enum MovieDealOfferType {
  bogo,
  percentDiscount,
  fixedDiscount,
  cashback,
  freeTickets,
  voucher,
}

/// An immutable, validated movie-deal rule. Null commercial terms are unknown,
/// rather than inferred from legacy defaults.
class MovieDealRule {
  const MovieDealRule({
    required this.benefitId,
    required this.catalogCardId,
    required this.title,
    required this.offerType,
    this.sourceUrl,
    this.cardName,
    this.displayPriority = 0,
    this.platforms = const {},
    this.cinemas = const {},
    this.buyCount,
    this.freeCount,
    this.discountPercent,
    this.fixedAmount,
    this.maximumDiscount,
    this.minimumTransaction,
    this.transactionTicketLimit,
    this.cycleTicketLimit,
    this.cycleTransactionLimit,
    this.validityStart,
    this.validityEnd,
    this.validWeekdays = const {},
    this.milestoneThreshold,
    this.milestoneReward,
    this.exclusions = const {},
  });

  final String benefitId;
  final String catalogCardId;
  final String title;
  final String? sourceUrl;
  final String? cardName;
  final int displayPriority;
  final MovieDealOfferType offerType;
  final Set<String> platforms;
  final Set<String> cinemas;
  final int? buyCount;
  final int? freeCount;
  final double? discountPercent;
  final double? fixedAmount;
  final double? maximumDiscount;
  final double? minimumTransaction;
  final int? transactionTicketLimit;
  final int? cycleTicketLimit;
  final int? cycleTransactionLimit;
  final DateTime? validityStart;
  final DateTime? validityEnd;
  final Set<String> validWeekdays;
  final double? milestoneThreshold;
  final double? milestoneReward;
  final Set<String> exclusions;
}

sealed class RuleNormalizationResult {
  const RuleNormalizationResult();
}

class AcceptedMovieDealRule extends RuleNormalizationResult {
  const AcceptedMovieDealRule(this.rule);

  final MovieDealRule rule;
}

class RejectedMovieDealRule extends RuleNormalizationResult {
  const RejectedMovieDealRule(this.reason);

  final String reason;
}
