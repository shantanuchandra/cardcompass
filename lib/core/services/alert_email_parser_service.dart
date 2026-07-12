import 'package:cardcompass/core/services/alert_email_gmail_service.dart';
import 'package:cardcompass/shared/models/transaction.dart';

/// Result of parsing a single alert email.
class AlertEmailParseResult {
  final String alertEmailId;
  final double? amount;
  final String? merchant;
  final String? cardLastFour;
  final TransactionType transactionType;
  final DateTime transactionDate;
  final bool success;
  final String? rawText; // for debug

  const AlertEmailParseResult({
    required this.alertEmailId,
    this.amount,
    this.merchant,
    this.cardLastFour,
    this.transactionType = TransactionType.debit,
    required this.transactionDate,
    required this.success,
    this.rawText,
  });
}

/// Parses instant bank alert emails into structured transaction data.
///
/// Uses a multi-pass approach:
///   1. Regex patterns for common bank alert formats (fast, free)
///   2. Gemini fallback for unrecognised formats (accurate, costs tokens)
class AlertEmailParserService {
  // ---------------------------------------------------------------------------
  // Regex patterns shared across Indian bank alert emails
  // ---------------------------------------------------------------------------

  /// Captures the transaction amount, e.g.:
  ///   "Rs. 1,250.00", "INR 4500", "₹ 9,999.50", "Rs 750"
  static final _amountRegex = RegExp(
    r'(?:Rs\.?\s*|INR\s*|₹\s*)([\d,]+(?:\.\d{1,2})?)',
    caseSensitive: false,
  );

  /// Captures merchant name from common patterns:
  ///   "at AMAZON INDIA", "at Swiggy", "merchant: Zomato"
  static final _merchantAtRegex = RegExp(
    r'''(?:at\s+|merchant[:\s]+)([A-Z0-9][A-Z0-9\s\-&.]{2,40})''',
    caseSensitive: false,
  );

  /// Captures card last 4 digits:
  ///   "card ending in 1234", "card XX1234", "card no. XXXX1234"
  static final _cardLastFourRegex = RegExp(
    r'(?:card\s+(?:ending\s+(?:in\s+)?|no\.?\s*(?:xx+)?))(\d{4})',
    caseSensitive: false,
  );

  /// Detects credit transactions
  static final _creditKeywordRegex = RegExp(
    r'\b(?:credited|credit|refund|reversed|cashback)\b',
    caseSensitive: false,
  );

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Parse a list of [AlertEmail] objects into [AlertEmailParseResult]s.
  List<AlertEmailParseResult> parseAll(List<AlertEmail> emails) {
    return emails.map(parse).toList();
  }

  /// Parse a single [AlertEmail] into an [AlertEmailParseResult].
  AlertEmailParseResult parse(AlertEmail email) {
    // Use plain text body first; strip HTML tags from HTML body as fallback
    final body = email.bodyText.isNotEmpty
        ? email.bodyText
        : _stripHtml(email.bodyHtml);

    // Combine subject + body for pattern matching
    final fullText = '${email.subject}\n$body';

    final amount = _extractAmount(fullText);
    final merchant = _extractMerchant(fullText);
    final cardLastFour = _extractCardLastFour(fullText);
    final isCredit = _creditKeywordRegex.hasMatch(fullText);

    final success = amount != null; // Amount is the minimum required field

    return AlertEmailParseResult(
      alertEmailId: email.id,
      amount: amount,
      merchant: _cleanMerchant(merchant),
      cardLastFour: cardLastFour,
      transactionType:
          isCredit ? TransactionType.credit : TransactionType.debit,
      transactionDate: email.date,
      success: success,
      rawText: fullText.substring(0, fullText.length.clamp(0, 500)),
    );
  }

  // ---------------------------------------------------------------------------
  // Field extractors
  // ---------------------------------------------------------------------------

  double? _extractAmount(String text) {
    final match = _amountRegex.firstMatch(text);
    if (match == null) return null;
    final raw = match.group(1)!.replaceAll(',', '');
    return double.tryParse(raw);
  }

  String? _extractMerchant(String text) {
    final match = _merchantAtRegex.firstMatch(text);
    return match?.group(1)?.trim();
  }

  String? _extractCardLastFour(String text) {
    final match = _cardLastFourRegex.firstMatch(text);
    return match?.group(1);
  }

  /// Remove HTML tags for text extraction
  String _stripHtml(String html) {
    return html
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
  }

  /// Normalise merchant names: title case, remove extra spaces
  String? _cleanMerchant(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    return raw
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }
}
