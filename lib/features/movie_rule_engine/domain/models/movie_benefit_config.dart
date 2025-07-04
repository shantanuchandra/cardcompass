/// Movie benefit configuration parsed from JSON
class MovieBenefitConfig {
  final String offerType; // BOGO, PERCENT_DISCOUNT, CASHBACK, MILESTONE
  final List<String>? partnerFilter; // BookMyShow, PVR, INOX, etc.
  final double? discountPercent;
  final double? maxDiscountAmount;
  final int? freeTicketCount;
  final int? transactionTicketLimit;
  final int? monthlyTicketLimit;
  final double? milestoneCurrency;
  final int? milestoneReward;
  final List<String>? validDayOfWeek;
  final String? validTime;
  final DateTime? startDate;
  final DateTime? endDate;
  final List<String>? excludedShowTypes;
  final double? minTransactionAmount;
  final double? efficiencyThreshold; // New field for preventing high-value benefits on low amounts

  const MovieBenefitConfig({
    required this.offerType,
    this.partnerFilter,
    this.discountPercent,
    this.maxDiscountAmount,
    this.freeTicketCount,
    this.transactionTicketLimit,
    this.monthlyTicketLimit,
    this.milestoneCurrency,
    this.milestoneReward,
    this.validDayOfWeek,
    this.validTime,
    this.startDate,
    this.endDate,
    this.excludedShowTypes,
    this.minTransactionAmount,
    this.efficiencyThreshold,
  });

  /// Check if this benefit is currently valid
  bool get isValid {
    final now = DateTime.now();
    if (startDate != null && now.isBefore(startDate!)) return false;
    if (endDate != null && now.isAfter(endDate!)) return false;
    return true;
  }

  /// Check if benefit applies to given platform
  bool appliesToPlatform(String platform) {
    if (partnerFilter == null || partnerFilter!.isEmpty) return true;
    return partnerFilter!.any((filter) => 
        platform.toLowerCase().contains(filter.toLowerCase()));
  }

  /// Check if benefit meets minimum transaction requirement
  bool meetsMinimumAmount(double amount) {
    return minTransactionAmount == null || amount >= minTransactionAmount!;
  }

  /// Check if benefit exceeds efficiency threshold (prevents high-value benefits on low amounts)
  bool isEfficient(double ticketPrice) {
    return efficiencyThreshold == null || ticketPrice >= efficiencyThreshold!;
  }

  /// Check if day-of-week restriction applies
  bool validForDay(DateTime date) {
    if (validDayOfWeek == null || validDayOfWeek!.isEmpty) return true;
    final dayName = _getDayName(date.weekday);
    return validDayOfWeek!.contains(dayName);
  }

  String _getDayName(int weekday) {
    switch (weekday) {
      case 1: return 'MON';
      case 2: return 'TUE';
      case 3: return 'WED';
      case 4: return 'THU';
      case 5: return 'FRI';
      case 6: return 'SAT';
      case 7: return 'SUN';
      default: return 'MON';
    }
  }

  factory MovieBenefitConfig.fromJson(Map<String, dynamic> json) {
    return MovieBenefitConfig(
      offerType: json['offer_type'] ?? '',
      partnerFilter: json['partner_filter'] != null 
          ? List<String>.from(json['partner_filter']) 
          : null,
      discountPercent: json['discount_percent']?.toDouble(),
      maxDiscountAmount: json['max_discount_amount']?.toDouble(),
      freeTicketCount: json['free_ticket_count'],
      transactionTicketLimit: json['txn_ticket_limit'],
      monthlyTicketLimit: json['month_ticket_limit'],
      milestoneCurrency: json['milestone_currency']?.toDouble(),
      milestoneReward: json['milestone_reward'],
      validDayOfWeek: json['valid_dow'] != null 
          ? List<String>.from(json['valid_dow']) 
          : null,
      validTime: json['valid_time'],
      startDate: json['start_date'] != null 
          ? DateTime.parse(json['start_date']) 
          : null,
      endDate: json['end_date'] != null 
          ? DateTime.parse(json['end_date']) 
          : null,
      excludedShowTypes: json['excluded_show_types'] != null 
          ? List<String>.from(json['excluded_show_types']) 
          : null,
      minTransactionAmount: json['min_transaction_amount']?.toDouble(),
      efficiencyThreshold: json['efficiency_threshold']?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
    'offer_type': offerType,
    'partner_filter': partnerFilter,
    'discount_percent': discountPercent,
    'max_discount_amount': maxDiscountAmount,
    'free_ticket_count': freeTicketCount,
    'txn_ticket_limit': transactionTicketLimit,
    'month_ticket_limit': monthlyTicketLimit,
    'milestone_currency': milestoneCurrency,
    'milestone_reward': milestoneReward,
    'valid_dow': validDayOfWeek,
    'valid_time': validTime,
    'start_date': startDate?.toIso8601String(),
    'end_date': endDate?.toIso8601String(),
    'excluded_show_types': excludedShowTypes,
    'min_transaction_amount': minTransactionAmount,
    'efficiency_threshold': efficiencyThreshold,
  };

  @override
  String toString() => 'MovieBenefitConfig($offerType, partners: $partnerFilter)';
}
