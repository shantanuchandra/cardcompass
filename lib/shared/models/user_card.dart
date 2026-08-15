class UserCard {
  final String id;
  final String userId;
  final String catalogCardId;
  final String? lastFourDigits;
  final String? cardHolderName;
  final double? creditLimit;
  final int? statementDate;
  final int? dueDate;
  final bool isActive;
  final DateTime createdAt;

  // Joined from card_catalog
  final String? cardName;
  final String? bank;
  final String? network;
  final String? cardType;
  final double? annualFee;
  final String? cardUrl;

  const UserCard({
    required this.id,
    required this.userId,
    required this.catalogCardId,
    this.lastFourDigits,
    this.cardHolderName,
    this.creditLimit,
    this.statementDate,
    this.dueDate,
    this.isActive = true,
    required this.createdAt,
    this.cardName,
    this.bank,
    this.network,
    this.cardType,
    this.annualFee,
    this.cardUrl,
  });

  factory UserCard.fromJson(Map<String, dynamic> json) {
    final catalog = json['card_catalog'] as Map<String, dynamic>?;
    return UserCard(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      catalogCardId: json['catalog_card_id'] as String,
      lastFourDigits: json['last_four_digits'] as String?,
      cardHolderName: json['card_holder_name'] as String?,
      creditLimit: (json['credit_limit'] as num?)?.toDouble(),
      statementDate: json['statement_date'] as int?,
      dueDate: json['due_date'] as int?,
      isActive: json['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
      cardName: catalog?['card_name'] as String?,
      bank: catalog?['bank'] as String?,
      network: catalog?['network'] as String?,
      cardType: catalog?['card_type'] as String?,
      annualFee: (catalog?['annual_fee'] as num?)?.toDouble(),
      cardUrl: catalog?['card_url'] as String?,
    );
  }

  String get displayName => cardName ?? 'Card ••••${lastFourDigits ?? ''}';
  String get maskedNumber => lastFourDigits != null ? '••••  ••••  ••••  $lastFourDigits' : '';

  // Maps any bank name variant to a short gradient key.
  // "HDFC Bank", "hdfc" → "hdfc"; "SBI Cards" → "sbi"; "Bpcl" → "bpcl"; etc.
  String get bankCode {
    final b = (bank ?? '').toLowerCase();
    if (b.contains('hdfc')) return 'hdfc';
    if (b.contains('sbi')) return 'sbi';
    if (b.contains('icici')) return 'icici';
    if (b.contains('axis')) return 'axis';
    if (b.contains('kotak')) return 'kotak';
    if (b.contains('amex') || b.contains('american express')) return 'amex';
    if (b.contains('bpcl')) return 'bpcl';
    if (b.contains('indusind')) return 'indusind';
    if (b.contains('yes bank') || b == 'yes') return 'yes';
    if (b.contains('rbl')) return 'rbl';
    if (b.contains('idfc')) return 'idfc';
    if (b.contains('bob') || b.contains('bank of baroda')) return 'bob';
    return b.replaceAll(' ', '');
  }
}
