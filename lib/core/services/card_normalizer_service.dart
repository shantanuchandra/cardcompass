/// Shared service for normalizing bank and card names
class CardNormalizerService {
  /// Normalize a bank name to a canonical form to prevent duplicates
  static String normalizeBankName(String rawName) {
    final lower = rawName.toLowerCase();

    if (lower.contains('hdfc')) return 'HDFC Bank';
    if (lower.contains('sbi')) return 'SBI Card';
    if (lower.contains('axis')) return 'Axis Bank';

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

    return rawName.split(RegExp(r"\s+")).map((w) => w.isEmpty
      ? w
      : w[0].toUpperCase() + w.substring(1).toLowerCase()).join(' ');
  }

  /// Normalize a card name to extract just the variant name
  static String normalizeCardName(String rawName, String bankName) {
    var name = rawName.toLowerCase()
      .replaceAll(RegExp(r'credit card', caseSensitive: false), '')
      .replaceAll(RegExp(r'statement for', caseSensitive: false), '')
      .replaceAll(RegExp(r'bank', caseSensitive: false), '')
      .trim();

    final bankLower = bankName.toLowerCase();
    final bankWords = bankLower.split(' ');

    for (final bankWord in bankWords) {
      if (bankWord.isNotEmpty && bankWord != 'bank') {
        name = name.replaceAll(RegExp(r'^' + RegExp.escape(bankWord) + r'\s*', caseSensitive: false), '');
      }
    }

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

    if (name.isEmpty) {
      name = rawName.toLowerCase()
        .replaceAll(RegExp(r'credit card', caseSensitive: false), '')
        .replaceAll(RegExp(r'bank', caseSensitive: false), '')
        .trim();
    }

    final result = name.split(RegExp(r"\s+")).map((w) => w.isEmpty
      ? w
      : w[0].toUpperCase() + w.substring(1)).join(' ');

    return result.isNotEmpty ? result : rawName;
  }
}
