/// Shared service for normalizing bank and card names
/// 
/// This service provides consistent normalization of bank and card names
/// across the entire CardCompass application, ensuring data consistency
/// for both transaction parsing and benefit extraction.
class CardNormalizerService {
  
  /// Normalize a bank name to a canonical form to prevent duplicates
  /// 
  /// Takes raw bank names from various sources (PDFs, websites, user input)
  /// and converts them to standardized forms used throughout the app.
  /// 
  /// Examples:
  /// - "hdfc bank ltd" → "HDFC Bank"
  /// - "sbi cards and payment services" → "SBI Card"
  /// - "axis bank limited" → "Axis Bank"
  static String normalizeBankName(String rawName) {
    final lower = rawName.toLowerCase();
    
    // Major Indian banks - order matters for specificity
    if (lower.contains('hdfc')) return 'HDFC Bank';
    if (lower.contains('sbi')) return 'SBI Card';
    if (lower.contains('axis')) return 'Axis Bank';
    
    // Special case for Amazon ICICI Bank (must come before general ICICI)
    if (lower.contains('amazon') && lower.contains('icici')) return 'Amazon ICICI Bank';
    if (lower.contains('icici')) return 'ICICI Bank';
    
    if (lower.contains('kotak')) return 'Kotak Bank';
    if (lower.contains('idfc')) return 'IDFC FIRST Bank';
    if (lower.contains('yes')) return 'Yes Bank';
    if (lower.contains('au ')) return 'AU Small Finance Bank';
    if (lower.contains('indusind')) return 'IndusInd Bank';
    if (lower.contains('standard chartered')) return 'Standard Chartered';
    if (lower.contains('american express') || lower.contains('amex')) return 'American Express';
    if (lower.contains('citi')) return 'Citibank';
    if (lower.contains('hsbc')) return 'HSBC';
    if (lower.contains('rbl')) return 'RBL Bank';
    if (lower.contains('federal')) return 'Federal Bank';
    if (lower.contains('karur vysya')) return 'Karur Vysya Bank';
    if (lower.contains('bob') || lower.contains('bank of baroda')) return 'Bank of Baroda';
    if (lower.contains('canara')) return 'Canara Bank';
    if (lower.contains('pnb') || lower.contains('punjab national')) return 'Punjab National Bank';
    if (lower.contains('union bank')) return 'Union Bank of India';
    if (lower.contains('indian bank')) return 'Indian Bank';
    if (lower.contains('central bank')) return 'Central Bank of India';
    if (lower.contains('indian overseas')) return 'Indian Overseas Bank';
    if (lower.contains('allahabad') || lower.contains('indian')) return 'Indian Bank';
    
    // Fallback: title-case each word for unknown banks
    return rawName.split(RegExp(r"\s+")).map((w) => w.isEmpty
      ? w
      : w[0].toUpperCase() + w.substring(1).toLowerCase()).join(' ');
  }

  /// Normalize a card name to extract just the variant name
  /// 
  /// Takes raw card names and extracts the specific card variant,
  /// removing bank name prefixes and common suffixes.
  /// 
  /// [rawName] - The raw card name from the input (e.g., "Axis Bank Aura Credit Card")
  /// [bankName] - The normalized bank name (e.g., "Axis Bank")
  /// 
  /// Returns: Just the variant name (e.g., "Aura", "Miles", "Diners Club Rewardz")
  /// 
  /// Examples:
  /// - "HDFC Bank Regalia Credit Card" → "Regalia"
  /// - "SBI Card PRIME" → "PRIME"
  /// - "ICICI Bank Amazon Pay Credit Card" → "Amazon Pay"
  static String normalizeCardName(String rawName, String bankName) {
    var name = rawName.toLowerCase()
      .replaceAll(RegExp(r'credit card', caseSensitive: false), '')
      .replaceAll(RegExp(r'statement for', caseSensitive: false), '')
      .replaceAll(RegExp(r'bank', caseSensitive: false), '')
      .trim();
    
    // Extract just the variant name by removing bank-specific prefixes
    final bankLower = bankName.toLowerCase();
    final bankWords = bankLower.split(' ');
    
    // Remove bank name patterns from the beginning
    for (final bankWord in bankWords) {
      if (bankWord.isNotEmpty && bankWord != 'bank') {
        name = name.replaceAll(RegExp(r'^' + RegExp.escape(bankWord) + r'\s*', caseSensitive: false), '');
      }
    }
    
    // Remove other common bank prefixes/suffixes
    name = name
      .replaceAll(RegExp(r'^axis\s*', caseSensitive: false), '')
      .replaceAll(RegExp(r'^hdfc\s*', caseSensitive: false), '')
      .replaceAll(RegExp(r'^sbi\s*', caseSensitive: false), '')
      .replaceAll(RegExp(r'^icici\s*', caseSensitive: false), '')
      .replaceAll(RegExp(r'^kotak\s*', caseSensitive: false), '')
      .replaceAll(RegExp(r'^idfc\s*', caseSensitive: false), '')
      .replaceAll(RegExp(r'^yes\s*', caseSensitive: false), '')
      .replaceAll(RegExp(r'^au\s*', caseSensitive: false), '')
      .replaceAll(RegExp(r'^indusind\s*', caseSensitive: false), '')
      .replaceAll(RegExp(r'^rbl\s*', caseSensitive: false), '')
      .replaceAll(RegExp(r'first\s*', caseSensitive: false), '')
      .replaceAll(RegExp(r'bank\s*', caseSensitive: false), '')
      .replaceAll(RegExp(r'card\s*$', caseSensitive: false), '')
      .replaceAll(RegExp(r'ltd\s*', caseSensitive: false), '')
      .replaceAll(RegExp(r'limited\s*', caseSensitive: false), '')
      .trim();
    
    // If name is empty after cleanup, use the original name as fallback
    if (name.isEmpty) {
      name = rawName.toLowerCase()
        .replaceAll(RegExp(r'credit card', caseSensitive: false), '')
        .replaceAll(RegExp(r'bank', caseSensitive: false), '')
        .trim();
    }
    
    // Title-case the result
    final result = name.split(RegExp(r"\s+")).map((w) => w.isEmpty
      ? w
      : w[0].toUpperCase() + w.substring(1)).join(' ');
    
    return result.isNotEmpty ? result : rawName;
  }

  /// Get a standardized card identifier for database lookup
  /// 
  /// Creates a consistent identifier by combining normalized bank and card names,
  /// useful for database queries and matching.
  /// 
  /// Example: "HDFC Bank" + "Regalia" → "hdfc-bank-regalia"
  static String getCardIdentifier(String bankName, String cardName) {
    final normalizedBank = normalizeBankName(bankName);
    final normalizedCard = normalizeCardName(cardName, normalizedBank);
    
    return '${normalizedBank.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-')}-'
           '${normalizedCard.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-')}'
           .replaceAll(RegExp(r'-+'), '-')
           .replaceAll(RegExp(r'^-|-$'), '');
  }

  /// Validate if a bank name is recognized
  /// 
  /// Returns true if the bank is in our known list of Indian banks.
  /// Useful for validation and fallback logic.
  static bool isRecognizedBank(String bankName) {
    final normalized = normalizeBankName(bankName);
    const recognizedBanks = {
      'HDFC Bank',
      'SBI Card',
      'Axis Bank',
      'ICICI Bank',
      'Amazon ICICI Bank',
      'Kotak Bank',
      'IDFC FIRST Bank',
      'Yes Bank',
      'AU Small Finance Bank',
      'IndusInd Bank',
      'Standard Chartered',
      'American Express',
      'Citibank',
      'HSBC',
      'RBL Bank',
      'Federal Bank',
      'Karur Vysya Bank',
      'Bank of Baroda',
      'Canara Bank',
      'Punjab National Bank',
      'Union Bank of India',
      'Indian Bank',
      'Central Bank of India',
      'Indian Overseas Bank',
    };
    
    return recognizedBanks.contains(normalized);
  }

  /// Get bank-specific patterns for enhanced parsing
  /// 
  /// Returns bank-specific information that can be used for
  /// more accurate transaction parsing or benefit extraction.
  static Map<String, dynamic> getBankInfo(String bankName) {
    final normalized = normalizeBankName(bankName);
    
    switch (normalized) {
      case 'HDFC Bank':
        return {
          'type': 'full_service',
          'website': 'hdfcbank.com',
          'card_prefix': 'hdfc',
          'typical_formats': ['DD/MM/YYYY HH:MM:SS', 'DD-MM-YYYY'],
        };
      case 'SBI Card':
        return {
          'type': 'card_only',
          'website': 'sbicard.com',
          'card_prefix': 'sbi',
          'typical_formats': ['DD MMM YY', 'DD-MM-YYYY'],
        };
      case 'ICICI Bank':
      case 'Amazon ICICI Bank':
        return {
          'type': 'full_service',
          'website': 'icicibank.com',
          'card_prefix': 'icici',
          'typical_formats': ['DD/MM/YYYY', 'DD-MM-YY'],
        };
      case 'Axis Bank':
        return {
          'type': 'full_service',
          'website': 'axisbank.com',
          'card_prefix': 'axis',
          'typical_formats': ['DD/MM/YYYY', 'DD-MM-YYYY'],
        };
      default:
        return {
          'type': 'unknown',
          'website': null,
          'card_prefix': normalized.toLowerCase().split(' ')[0],
          'typical_formats': ['DD/MM/YYYY', 'DD-MM-YYYY'],
        };
    }
  }
}
