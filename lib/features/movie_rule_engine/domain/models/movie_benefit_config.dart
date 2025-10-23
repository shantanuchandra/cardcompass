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

  /// Helper method to safely parse date strings
  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    
    try {
      if (value is String) {
        return DateTime.parse(value);
      } else if (value is Map) {
        // Handle case where date might be a Map with format used by some libraries
        if (value.containsKey('date') && value['date'] is String) {
          return DateTime.parse(value['date']);
        }
      }
    } catch (e) {
      print('WARNING: Failed to parse date: $value, error: $e');
    }
    
    return null;
  }
  
  /// Helper method to safely convert values to double
  static double? _safeToDouble(dynamic value) {
    if (value == null) return null;
    
    if (value is num) {
      return value.toDouble();
    } else if (value is String) {
      return double.tryParse(value);
    }
    
    return null;
  }

  factory MovieBenefitConfig.fromJson(Map<String, dynamic> json) {
    try {
      // Handle legacy database format (rate, unit, category, platform, base_rate)
      String offerType = json['offer_type'] ?? '';
      double? discountPercent = _safeToDouble(json['discount_percent']);
      List<String>? partnerFilter = json['partner_filter'] != null 
          ? (json['partner_filter'] is List 
              ? List<String>.from(json['partner_filter'])
              : <String>[json['partner_filter'].toString()])
          : null;
      
      // Map legacy format to new format
      if (offerType.isEmpty && json.containsKey('rate')) {
        // Legacy format detected
        final unit = json['unit']?.toString() ?? 'percent';
        final rate = _safeToDouble(json['rate']);
        final platform = json['platform']?.toString();
        
        if (unit == 'percent' && rate != null) {
          offerType = 'PERCENT_DISCOUNT';
          discountPercent = rate;
        } else if (unit == 'fixed') {
          offerType = 'PERCENT_DISCOUNT';
          discountPercent = 15.0; // Default to 15%
        }
        
        if (platform != null && platform.isNotEmpty) {
          partnerFilter = [platform];
        }
      }
      
      return MovieBenefitConfig(
        offerType: offerType,
        partnerFilter: partnerFilter,
        discountPercent: discountPercent,
        maxDiscountAmount: _safeToDouble(json['max_discount_amount']) ?? 150.0,
        freeTicketCount: json['free_ticket_count'] is int 
            ? json['free_ticket_count'] 
            : (json['free_ticket_count'] != null ? int.tryParse(json['free_ticket_count'].toString()) : null),
        transactionTicketLimit: json['txn_ticket_limit'] is int 
            ? json['txn_ticket_limit']
            : (json['txn_ticket_limit'] != null ? int.tryParse(json['txn_ticket_limit'].toString()) : null),
        monthlyTicketLimit: json['month_ticket_limit'] is int 
            ? json['month_ticket_limit']
            : (json['month_ticket_limit'] != null ? int.tryParse(json['month_ticket_limit'].toString()) : null),
        milestoneCurrency: _safeToDouble(json['milestone_currency']),
        milestoneReward: json['milestone_reward'] is int 
            ? json['milestone_reward']
            : (json['milestone_reward'] != null ? int.tryParse(json['milestone_reward'].toString()) : null),
        validDayOfWeek: json['valid_dow'] != null 
            ? (json['valid_dow'] is List 
                ? List<String>.from(json['valid_dow'])
                : <String>[json['valid_dow'].toString()])
            : (json['valid_days'] != null 
                ? (json['valid_days'] is List 
                    ? List<String>.from(json['valid_days'])
                    : <String>[json['valid_days'].toString()])
                : null),
        validTime: json['valid_time']?.toString(),
        startDate: _parseDateTime(json['start_date']),
        endDate: _parseDateTime(json['end_date']),
      excludedShowTypes: json['excluded_show_types'] != null 
          ? (json['excluded_show_types'] is List 
              ? List<String>.from(json['excluded_show_types'])
              : <String>[json['excluded_show_types'].toString()])
          : null,
      minTransactionAmount: _safeToDouble(json['min_transaction_amount']) ?? 300.0,
      efficiencyThreshold: _safeToDouble(json['efficiency_threshold']),
    );
    } catch (e) {
      print('ERROR in MovieBenefitConfig.fromJson: $e');
      print('JSON content: $json');
      // Return a default configuration with empty offer type to avoid null errors
      return MovieBenefitConfig(offerType: 'PERCENT_DISCOUNT', discountPercent: 15.0);
    }
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
