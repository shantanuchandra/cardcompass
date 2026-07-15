import 'models/movie_deal_rule.dart';

RuleNormalizationResult normalizeMovieDealRule(MovieBenefitSource source) {
  final config = source.valueConfig;
  final malformedOptionalField = _malformedOptionalField(config);
  if (malformedOptionalField != null) {
    return RejectedMovieDealRule(
      'The supplied $malformedOptionalField field is malformed.',
    );
  }
  final explicitType = _string(config['offer_type'])?.toUpperCase();
  final discountPercent = _number(config['discount_percent']);
  final rate = _number(config['rate']);
  final unit = _string(config['unit'])?.toLowerCase();
  final discountAmount = _number(config['discount_amount']);

  final type = _offerType(
    explicitType: explicitType,
    hasDiscountPercent: discountPercent != null,
    hasPercentRate: rate != null && unit == 'percent',
    hasDiscountAmount: discountAmount != null,
  );
  if (type == null) {
    return const RejectedMovieDealRule(
        'No unambiguous movie offer type was supplied.');
  }

  final percent = discountPercent ?? (unit == 'percent' ? rate : null);
  if ((type == MovieDealOfferType.percentDiscount ||
          type == MovieDealOfferType.cashback) &&
      (percent == null || percent <= 0 || percent > 100)) {
    return const RejectedMovieDealRule(
        'A percentage offer requires a rate between 0 and 100.');
  }

  final fixedAmount = discountAmount ?? _number(config['fixed_amount']);
  if ((type == MovieDealOfferType.fixedDiscount ||
          type == MovieDealOfferType.voucher) &&
      (fixedAmount == null || fixedAmount <= 0)) {
    return const RejectedMovieDealRule(
        'A fixed-value offer requires a positive discount amount.');
  }

  final freeCount =
      _integer(config['free_ticket_count']) ?? _integer(config['free_count']);
  final buyCount = _integer(config['buy_ticket_count']) ??
      _integer(config['buy_count']) ??
      (type == MovieDealOfferType.bogo ? 1 : null);
  if ((type == MovieDealOfferType.bogo ||
          type == MovieDealOfferType.freeTickets) &&
      (freeCount == null ||
          freeCount <= 0 ||
          (type == MovieDealOfferType.bogo &&
              (buyCount == null || buyCount <= 0)))) {
    return const RejectedMovieDealRule(
        'A ticket offer requires positive buy and free ticket counts.');
  }

  final milestoneThreshold = _number(config['milestone_threshold']) ??
      _number(config['milestone_currency']);
  final milestoneReward = _number(config['milestone_reward']);
  if (explicitType == 'MILESTONE' &&
      (milestoneThreshold == null || milestoneReward == null)) {
    return const RejectedMovieDealRule(
        'A milestone requires both a threshold and reward.');
  }

  final validityStart =
      _date(config['start_date']) ?? _date(config['valid_from']);
  final validityEnd = _date(config['end_date']) ?? _date(config['valid_until']);
  if (validityStart != null &&
      validityEnd != null &&
      validityEnd.isBefore(validityStart)) {
    return const RejectedMovieDealRule(
        'The validity end precedes the validity start.');
  }

  return AcceptedMovieDealRule(
    MovieDealRule(
      benefitId: source.benefitId,
      catalogCardId: source.catalogCardId,
      title: source.title,
      sourceUrl: source.sourceUrl,
      cardName: source.cardName,
      displayPriority: source.displayPriority,
      offerType: type,
      platforms: _strings(config['platform'])
          .followedBy(_strings(config['partner_filter']))
          .toSet(),
      cinemas: _strings(config['cinema'])
          .followedBy(_strings(config['cinemas']))
          .toSet(),
      buyCount: buyCount,
      freeCount: freeCount,
      discountPercent: percent,
      fixedAmount: fixedAmount,
      maximumDiscount: _number(config['max_discount_amount']) ??
          _number(config['maximum_discount']),
      minimumTransaction: _number(config['min_transaction_amount']) ??
          _number(config['min_transaction']),
      transactionTicketLimit: _integer(config['txn_ticket_limit']),
      cycleTicketLimit: _integer(config['month_ticket_limit']) ??
          _integer(config['cycle_ticket_limit']),
      cycleTransactionLimit: _integer(config['max_usage_per_month']) ??
          _integer(config['cycle_transaction_limit']),
      validityStart: validityStart,
      validityEnd: validityEnd,
      validWeekdays: _strings(config['valid_dow'])
          .followedBy(_strings(config['valid_days']))
          .toSet(),
      milestoneThreshold: milestoneThreshold,
      milestoneReward: milestoneReward,
      exclusions: _strings(config['excluded_show_types']).toSet(),
    ),
  );
}

MovieDealOfferType? _offerType({
  required String? explicitType,
  required bool hasDiscountPercent,
  required bool hasPercentRate,
  required bool hasDiscountAmount,
}) {
  switch (explicitType) {
    case 'BOGO':
      return MovieDealOfferType.bogo;
    case 'PERCENT_DISCOUNT':
    case 'PERCENTAGE_DISCOUNT':
      return MovieDealOfferType.percentDiscount;
    case 'FIXED_DISCOUNT':
    case 'FIXED':
      return MovieDealOfferType.fixedDiscount;
    case 'CASHBACK':
      return MovieDealOfferType.cashback;
    case 'FREE_TICKETS':
      return MovieDealOfferType.freeTickets;
    case 'VOUCHER':
      return MovieDealOfferType.voucher;
  }
  if (hasDiscountPercent || hasPercentRate)
    return MovieDealOfferType.percentDiscount;
  if (hasDiscountAmount) return MovieDealOfferType.fixedDiscount;
  return null;
}

double? _number(Object? value) {
  final number = value is num
      ? value.toDouble()
      : value is String
          ? double.tryParse(value)
          : null;
  return number?.isFinite ?? false ? number : null;
}

int? _integer(Object? value) {
  if (value is int) return value;
  if (value is num && value.isFinite && value == value.roundToDouble()) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '');
}

String? _string(Object? value) =>
    value is String && value.trim().isNotEmpty ? value.trim() : null;

Iterable<String> _strings(Object? value) {
  if (value is Iterable) return value.map(_string).whereType<String>();
  final single = _string(value);
  return single == null ? const [] : [single];
}

DateTime? _date(Object? value) {
  final string = _string(value);
  return string == null ? null : DateTime.tryParse(string);
}

String? _malformedOptionalField(Map<String, dynamic> config) {
  const dateFields = ['start_date', 'valid_from', 'end_date', 'valid_until'];
  for (final field in dateFields) {
    if (_isSupplied(config, field) && _date(config[field]) == null) return field;
  }

  const numberFields = [
    'max_discount_amount',
    'maximum_discount',
    'min_transaction_amount',
    'min_transaction',
  ];
  for (final field in numberFields) {
    if (_isSupplied(config, field) && !_isFiniteNumber(config[field])) {
      return field;
    }
  }

  const integerFields = [
    'buy_ticket_count',
    'buy_count',
    'free_ticket_count',
    'free_count',
    'txn_ticket_limit',
    'month_ticket_limit',
    'cycle_ticket_limit',
    'max_usage_per_month',
    'cycle_transaction_limit',
  ];
  for (final field in integerFields) {
    if (_isSupplied(config, field) && _integer(config[field]) == null) {
      return field;
    }
  }

  const listFields = [
    'platform',
    'partner_filter',
    'cinema',
    'cinemas',
    'excluded_show_types',
  ];
  for (final field in listFields) {
    if (_isSupplied(config, field) && !_isStringList(config[field])) return field;
  }

  const weekdayFields = ['valid_dow', 'valid_days'];
  for (final field in weekdayFields) {
    if (_isSupplied(config, field) && !_isWeekdayList(config[field])) return field;
  }
  return null;
}

bool _isSupplied(Map<String, dynamic> config, String field) =>
    config.containsKey(field) && config[field] != null;

bool _isFiniteNumber(Object? value) =>
    _number(value)?.isFinite ?? false;

bool _isStringList(Object? value) {
  if (value is String) return _string(value) != null;
  return value is Iterable && value.every((item) => _string(item) != null);
}

bool _isWeekdayList(Object? value) {
  const weekdays = {
    'monday', 'mon', 'tuesday', 'tue', 'tues', 'wednesday', 'wed',
    'thursday', 'thu', 'thur', 'thurs', 'friday', 'fri', 'saturday', 'sat',
    'sunday', 'sun',
  };
  if (!_isStringList(value)) return false;
  final values = value is String ? [value] : value as Iterable;
  return values.every((item) => weekdays.contains(_string(item)?.toLowerCase()));
}
