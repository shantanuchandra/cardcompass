import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'card_normalizer_service.dart';
import 'parsing_logger.dart';
import 'gemini_request_service.dart';
import '../config/ai_config.dart';

/// Builds the Gemini prompt for `parseTransactions()`. Extracted into its
/// own function (rather than inlined) so its exact text is directly
/// unit-testable — catches a future edit accidentally reintroducing the
/// old category vocabulary or the hardcoded INR example, which neither a
/// "prompts aren't testable" stance nor a live-Gemini-call test could
/// catch cheaply.
String buildTransactionsPrompt({required String bankName}) {
  return '''You are an expert at extracting transactions from Indian credit card statements. Analyze this ${bankName.toUpperCase()} statement and extract ALL transactions.

BANK: $bankName

EXTRACTION STRATEGY:
1. Find transaction table sections (look for headers like "Date", "Transaction", "Amount")
2. Extract each row that contains: Date + Description + Amount
3. Skip summary rows, balance rows, and headers
4. Parse amounts carefully - "CR" = credit (+), "D"/"Dr" = debit (-)
5. Clean merchant names (remove codes, URLs, extra numbers)
6. Convert all dates to YYYY-MM-DD format
7. For each transaction, identify the actual currency symbol or code visible on that line (e.g. "Rs.", "₹", "INR", "AED", "د.إ", "USD", "\$"). If no currency marker is visible on that specific line, assume INR only as a last resort — do not assume INR when a different marker is actually present.

JSON OUTPUT (return ONLY this array, no markdown blocks):
[
  {
    "date": "YYYY-MM-DD",
    "description": "Clean merchant name without codes",
    "amount": number (positive for credits, negative for debits),
    "currency": "the actual currency code observed on this line (e.g. INR, AED, USD) — only assume INR if no marker is visible",
    "merchantName": "Primary merchant name",
    "category": "food|fuel|grocery|entertainment|travel|shopping|utilities|insurance|medical|education|investment|transport|rental|subscription|gift|other",
    "type": "debit|credit",
    "reward_points": number or null (reward/loyalty points earned for this transaction, 0 if none),
    "reference": "transaction reference if clearly visible"
  }
]

ANALYZE THIS STATEMENT:''';
}

/// Parses credit card statement PDF text into structured statement info and
/// transactions via Gemini (through gemini_request_service's proxy call).
/// Trimmed from main's gemini_transaction_parser.dart: drops the
/// Ollama/Groq fallback branches (never configured in this project) and the
/// unrelated card-benefit extraction/repair methods.
class GeminiStatementParser {
  static Future<Map<String, dynamic>> parseStatementInfo({
    required String pdfText,
    required String bankName,
  }) async {
    try {
      final prompt =
          '''You are an expert financial statement analyzer. Extract key information from this credit card statement.

BANK: $bankName
TASK: Extract essential statement details into JSON format.

WHAT TO LOOK FOR:
- Statement/billing period dates
- Payment due dates
- Outstanding/total amount due
- Minimum payment required
- Closing/outstanding balance
- Credit limit information
- Card details (last 4 digits, product name)
- Currency (usually INR for Indian banks)
- Reward/loyalty points earned
- Payments received/credits applied during the statement period

COMMON PATTERNS:
- "Statement Date", "Bill Date", "Statement Period"
- "Due Date", "Payment Due", "Last Date for Payment"
- "Total Amount Due", "Outstanding Amount", "Current Balance"
- "Minimum Payment", "Minimum Amount Due"
- "Credit Limit", "Available Credit"
- Card numbers like "XXXX-XXXX-XXXX-1234"
- "Reward Points", "Points Earned", "Loyalty Points"

JSON OUTPUT (return ONLY this object, no markdown or code blocks):
{
  "statement_date": "YYYY-MM-DD or null",
  "due_date": "YYYY-MM-DD or null",
  "total_amount": number or null,
  "minimum_payment": number or null,
  "closing_balance": number or null,
  "credit_limit": number or null,
  "available_credit": number or null,
  "rewards_earned": number or null,
  "payments_received": number or null,
  "currency": "INR",
  "card_last4": "last 4 digits or null",
  "card_name": "card product name or null",
  "card_type": "credit"
}

ANALYZE THE STATEMENT:''';

      final cleanedText = _pruneAndCleanText(pdfText);
      final requestBody = {
        'contents': [
          {
            'parts': [
              {'text': '$prompt\n\n$cleanedText'}
            ]
          }
        ],
        'generationConfig': {'temperature': 0.1, 'maxOutputTokens': 2048}
      };

      final response = await _callGemini(requestBody, maxRetries: 3);

      if (response != null && response.statusCode == 200) {
        final decoded = json.decode(response.body);
        final content = decoded['candidates']?[0]?['content']?['parts']?[0]?['text'];

        if (content != null) {
          try {
            final cleanContent = _extractJsonPayload(content);
            final Map<String, dynamic> result = json.decode(cleanContent);

            final normBank = CardNormalizerService.normalizeBankName(bankName);
            result['bank_name'] = normBank;
            if (result['card_name'] != null) {
              result['card_name'] = CardNormalizerService.normalizeCardName(
                  result['card_name'].toString(), normBank);
            } else {
              result['card_name'] = CardNormalizerService.normalizeCardName(
                  '$normBank Credit Card', normBank);
            }

            ParsingLogger.summary('Gemini Parser: Successfully parsed statement info');
            return result;
          } catch (e) {
            ParsingLogger.error('Gemini Parser: Failed to parse JSON response', e);
          }
        }
      }

      return _fallbackStatementParsing(pdfText, bankName);
    } catch (e) {
      ParsingLogger.error('Gemini Parser: Error parsing statement info', e);
      return _fallbackStatementParsing(pdfText, bankName);
    }
  }

  /// Regex-extracts a statement date directly from the PDF text, independent
  /// of Gemini. Used as a second-chance fallback when Gemini's JSON call
  /// *succeeds* but returns "statement_date": null for a given statement
  /// format — that path previously fell straight through to DateTime.now(),
  /// which silently collided every such statement onto one upsert row
  /// (statements are keyed on user_card_id + statement_date).
  static DateTime? extractStatementDateFromText(String pdfText) {
    final dateMatch = RegExp(r'statement date[:\s]*(\d{2}[-/]\d{2}[-/]\d{4})', caseSensitive: false)
        .firstMatch(pdfText);
    if (dateMatch == null) return null;
    try {
      final parts = dateMatch.group(1)!.split(RegExp(r'[-/]'));
      if (parts.length != 3) return null;
      final day = int.parse(parts[0]);
      final month = int.parse(parts[1]);
      final year = int.parse(parts[2]);
      return DateTime(year, month, day);
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic> _fallbackStatementParsing(String pdfText, String bankName) {
    final Map<String, dynamic> statementInfo = {};
    statementInfo['bank_name'] = CardNormalizerService.normalizeBankName(bankName);

    final dateMatch = RegExp(r'statement date[:\s]*(\d{2}[-/]\d{2}[-/]\d{4})', caseSensitive: false)
        .firstMatch(pdfText);
    if (dateMatch != null) {
      statementInfo['statement_date'] = _convertDateFormat(dateMatch.group(1)!);
    }

    final dueDateMatch = RegExp(r'due date[:\s]*(\d{2}[-/]\d{2}[-/]\d{4})', caseSensitive: false)
        .firstMatch(pdfText);
    if (dueDateMatch != null) {
      statementInfo['due_date'] = _convertDateFormat(dueDateMatch.group(1)!);
    }

    final amountMatch = RegExp(
            r'total[:\s]*(?:amount|outstanding)[:\s]*(?:rs\.?|₹)?\s*([\d,]+\.?\d*)',
            caseSensitive: false)
        .firstMatch(pdfText);
    if (amountMatch != null) {
      statementInfo['total_amount'] = double.tryParse(amountMatch.group(1)!.replaceAll(',', '')) ?? 0.0;
    }

    statementInfo['currency'] = 'INR';
    statementInfo['card_type'] = 'credit';
    statementInfo['card_name'] =
        CardNormalizerService.normalizeCardName('$bankName Credit Card', statementInfo['bank_name']);

    return statementInfo;
  }

  static String _convertDateFormat(String dateStr) {
    try {
      final parts = dateStr.split(RegExp(r'[-/]'));
      if (parts.length == 3) {
        final day = int.parse(parts[0]);
        final month = int.parse(parts[1]);
        final year = int.parse(parts[2]);
        return DateTime(year, month, day).toIso8601String();
      }
    } catch (e) {
      ParsingLogger.warning('Gemini Parser: Error parsing date $dateStr');
    }
    return DateTime.now().toIso8601String();
  }

  static Future<List<Map<String, dynamic>>> parseTransactions({
    required String pdfText,
    required String bankName,
  }) async {
    try {
      final prompt = buildTransactionsPrompt(bankName: bankName);

      final cleanedText = _pruneAndCleanText(pdfText);
      final requestBody = {
        'contents': [
          {
            'parts': [
              {'text': '$prompt\n\n$cleanedText'}
            ]
          }
        ],
        'generationConfig': {'temperature': 0.1, 'maxOutputTokens': 8192}
      };

      final response = await _callGemini(requestBody, maxRetries: 3);

      if (response != null && response.statusCode == 200) {
        final decoded = json.decode(response.body);
        final content = decoded['candidates']?[0]?['content']?['parts']?[0]?['text'];

        if (content != null) {
          try {
            final cleanContent = _extractJsonPayload(content);
            final List<dynamic> list = json.decode(cleanContent);

            const uuid = Uuid();
            final transactions = list.map<Map<String, dynamic>>((item) {
              final m = Map<String, dynamic>.from(item);
              m['id'] = m['id'] ?? uuid.v4();
              return m;
            }).toList();

            ParsingLogger.summary('Gemini Parser: Successfully parsed ${transactions.length} transactions');
            return transactions;
          } catch (e) {
            ParsingLogger.error('Gemini Parser: Failed to parse JSON response', e);
          }
        }
      }
      return [];
    } catch (e) {
      ParsingLogger.error('Gemini Parser: Error parsing transactions', e);
      return [];
    }
  }

  /// Call Gemini via the proxy, retrying on 429 with a fixed backoff. Trimmed
  /// from main's _callGeminiWithFallback: no Ollama/Groq branches, no
  /// multi-model fallback chain (this project always uses AIConfig.geminiModel).
  static Future<http.Response?> _callGemini(
    Map<String, dynamic> requestBody, {
    int maxRetries = 3,
  }) async {
    int attempt = 0;

    while (attempt < maxRetries) {
      attempt++;
      try {
        ParsingLogger.summary('Gemini Parser: API call attempt $attempt/$maxRetries');
        final response = await sendGeminiRequest(requestBody);

        if (AIConfig.isRateLimitError(response.statusCode, response.body)) {
          ParsingLogger.warning('Gemini Parser: Rate limit detected (Status: ${response.statusCode})');
          if (attempt < maxRetries) {
            await Future.delayed(const Duration(seconds: 15));
            continue;
          }
          return response;
        }

        return response;
      } catch (e) {
        ParsingLogger.error('Gemini Parser: API call error on attempt $attempt', e);
        if (attempt < maxRetries) {
          await Future.delayed(const Duration(seconds: 10));
        }
      }
    }

    ParsingLogger.error('Gemini Parser: All API attempts exhausted');
    return null;
  }

  /// Trims trailing boilerplate (T&Cs, grievance redressal, branch lists)
  /// from statement text before sending to Gemini, to stay under token
  /// limits, without cutting into the transaction table itself.
  static String _pruneAndCleanText(String text) {
    if (text.isEmpty) return text;

    String cleaned = text.replaceAll(RegExp(r'\n+'), '\n');
    cleaned = cleaned.replaceAll(RegExp(r' {2,}'), ' ');
    cleaned = cleaned.trim();

    final lowerText = cleaned.toLowerCase();
    final markers = [
      'most important terms & conditions',
      'most important terms and conditions',
      'mitc',
      'important information for cardholders',
      'important information',
      'rights of cardholder',
      'cardholder agreement',
      'dispute redressal',
      'grievance redressal',
      'branch addresses',
      'list of branches',
    ];

    final candidateIndexes = <int>[];
    for (final marker in markers) {
      var searchFrom = 0;
      while (true) {
        final idx = lowerText.indexOf(marker, searchFrom);
        if (idx == -1) break;
        candidateIndexes.add(idx);
        searchFrom = idx + marker.length;
      }
    }
    candidateIndexes.sort();

    int bestCutIndex = -1;
    for (final idx in candidateIndexes) {
      if (idx <= 3500) continue;
      final tail = cleaned.substring(idx);
      final leaks = _detectPotentialLeaks(tail);
      if (leaks.isEmpty) {
        bestCutIndex = idx;
        break;
      }
    }

    if (bestCutIndex > 3500) {
      ParsingLogger.summary(
          'Text Pruning: PDF statement text reduced from ${cleaned.length} to $bestCutIndex characters');
      cleaned = cleaned.substring(0, bestCutIndex);
    }

    return cleaned;
  }

  /// Checks whether a candidate boilerplate cut-point's tail still contains
  /// transaction-shaped content (date+amount / merchant+amount lines) — if
  /// so, it's not safe to cut there. Ported from main's
  /// PruningAuditService.detectPotentialLeaks, dropping the Hive-backed
  /// audit-log persistence (not needed here — only the leak check itself).
  static List<Map<String, dynamic>> _detectPotentialLeaks(String removedText) {
    final lines = removedText.split('\n');
    final leaks = <Map<String, dynamic>>[];

    final dateRegex = RegExp(
        r'\b\d{2}[-/.]\d{2}[-/.]\d{2,4}\b|\b\d{2}\s+(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\s+\d{2,4}\b',
        caseSensitive: false);
    final currencyRegex = RegExp(
        r'(?:Rs\.?|₹|INR)\s*[\d,]+\.?\d*|\b[\d,]+\.\d{2}\s*(?:CR|DR|Cr|Dr|C|D)\b',
        caseSensitive: false);
    final merchantRegex = RegExp(
        r'swiggy|zomato|amazon|flipkart|uber|ola|petrol|payment received|paytm|gpay|phonepe|netflix|spotify|interest charged|finance charge',
        caseSensitive: false);

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.length < 15 || line.length > 200) continue;

      final hasDate = dateRegex.hasMatch(line);
      final hasCurrency = currencyRegex.hasMatch(line);
      final hasMerchant = merchantRegex.hasMatch(line);

      if ((hasDate && hasCurrency) || (hasMerchant && hasCurrency)) {
        leaks.add({'lineNumber': i + 1, 'lineContent': line});
      }
    }
    return leaks;
  }

  /// Extracts the JSON payload from Gemini's raw text response, then heals
  /// truncated arrays/objects (Gemini sometimes cuts off mid-response when
  /// hitting maxOutputTokens on large statements). Ported verbatim from
  /// main's gemini_transaction_parser.dart.
  static String _extractJsonPayload(String text) {
    text = text.trim();

    final firstBracket = text.indexOf('[');
    final firstBrace = text.indexOf('{');

    int startIdx = -1;

    if (firstBracket != -1 && (firstBrace == -1 || firstBracket < firstBrace)) {
      startIdx = firstBracket;
    } else if (firstBrace != -1) {
      startIdx = firstBrace;
    }

    if (startIdx != -1) {
      text = text.substring(startIdx);
    }

    text = _healJsonPayload(text);
    return text;
  }

  static String _healJsonPayload(String text) {
    text = text.trim();
    if (text.isEmpty) return text;

    if (text.startsWith('[')) {
      if (!text.endsWith(']')) {
        final lastBrace = text.lastIndexOf('}');
        if (lastBrace != -1) {
          text = text.substring(0, lastBrace + 1);
        }
        text = text.trim();
        if (text.endsWith(',')) {
          text = text.substring(0, text.length - 1).trim();
        }
        text += ']';
        ParsingLogger.summary('JSON Healing: Recovered incomplete JSON array and appended "]"');
      }
    } else if (text.startsWith('{')) {
      if (!text.endsWith('}')) {
        int openBraces = 0;
        int closeBraces = 0;
        for (int i = 0; i < text.length; i++) {
          if (text[i] == '{') openBraces++;
          if (text[i] == '}') closeBraces++;
        }
        if (openBraces > closeBraces) {
          text += '}' * (openBraces - closeBraces);
        }
        ParsingLogger.summary('JSON Healing: Recovered incomplete JSON object by closing open braces');
      }
    }
    return text;
  }
}
