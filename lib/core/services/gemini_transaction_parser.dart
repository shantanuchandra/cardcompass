import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/ai_config.dart';
import 'package:uuid/uuid.dart';
import 'card_normalizer_service.dart';
import 'pruning_audit_service.dart';
import 'parsing_logger.dart';
import 'gemini_request_service.dart';
import 'benefit_repair_service.dart';

/// Gemini AI Transaction Parser service
class GeminiTransactionParser {
  /// Parse statement-level information using Gemini AI
  static Future<Map<String, dynamic>> parseStatementInfo({
    required String pdfText,
    required String bankName,
  }) async {
    try {
      // Build enhanced prompt for statement information extraction
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
  "currency": "INR",
  "card_last4": "last 4 digits or null",
  "card_name": "card product name or null",
  "card_type": "credit"
}

ANALYZE THE STATEMENT:''';

      final cleanedText = _pruneAndCleanText(pdfText, bankName);
      final requestBody = {
        'contents': [
          {
            'parts': [
              {'text': prompt + '\n\n' + cleanedText}
            ]
          }
        ],
        'generationConfig': {'temperature': 0.1, 'maxOutputTokens': 512}
      };

      // Call Gemini API with automatic fallback
      final response =
          await _callGeminiWithFallback(requestBody, maxRetries: 3);

      if (response != null && response.statusCode == 200) {
        final decoded = json.decode(response.body);
        final content =
            decoded['candidates']?[0]?['content']?['parts']?[0]?['text'];

        if (content != null) {
          try {
            String cleanContent = _extractJsonPayload(content);

            // Try to parse the JSON response
            final Map<String, dynamic> result = json.decode(cleanContent);

            // Normalize bank and card names
            final normBank = normalizeBankName(bankName);
            result['bank_name'] = normBank;
            if (result.containsKey('card_name') &&
                result['card_name'] != null) {
              result['card_name'] =
                  normalizeCardName(result['card_name'].toString(), normBank);
            } else {
              result['card_name'] =
                  normalizeCardName('$normBank Credit Card', normBank);
            }

            ParsingLogger.summary(
                'Gemini Parser: Successfully parsed statement info');
            return result;
          } catch (e) {
            ParsingLogger.error(
                'Gemini Parser: Failed to parse JSON response', e);
            ParsingLogger.debug('Raw content: $content');
          }
        }
      } else if (response != null) {
        ParsingLogger.error(
            'Gemini Parser: Non-200 response, status ${response.statusCode}');
        ParsingLogger.debug('Response body: ${response.body}');
      } else {
        ParsingLogger.error('Gemini Parser: All API attempts failed');
      }

      // Fallback to basic extraction if API fails
      return _fallbackStatementParsing(pdfText, bankName);
    } catch (e) {
      ParsingLogger.error('Gemini Parser: Error parsing statement info', e);
      return _fallbackStatementParsing(pdfText, bankName);
    }
  }

  /// Fallback method for basic statement parsing using regex
  static Map<String, dynamic> _fallbackStatementParsing(
      String pdfText, String bankName) {
    final Map<String, dynamic> statementInfo = {};

    // Normalize bank name upfront
    statementInfo['bank_name'] = normalizeBankName(bankName);

    // Try to extract statement date
    final dateMatch = RegExp(r'statement date[:\s]*(\d{2}[-/]\d{2}[-/]\d{4})',
            caseSensitive: false)
        .firstMatch(pdfText);
    if (dateMatch != null) {
      statementInfo['statement_date'] = _convertDateFormat(dateMatch.group(1)!);
    }

    // Try to extract due date
    final dueDateMatch =
        RegExp(r'due date[:\s]*(\d{2}[-/]\d{2}[-/]\d{4})', caseSensitive: false)
            .firstMatch(pdfText);
    if (dueDateMatch != null) {
      statementInfo['due_date'] = _convertDateFormat(dueDateMatch.group(1)!);
    }

    // Try to extract total amount
    final amountMatch = RegExp(
            r'total[:\s]*(?:amount|outstanding)[:\s]*(?:rs\.?|₹)?\s*([\d,]+\.?\d*)',
            caseSensitive: false)
        .firstMatch(pdfText);
    if (amountMatch != null) {
      statementInfo['total_amount'] =
          double.tryParse(amountMatch.group(1)!.replaceAll(',', '')) ?? 0.0;
    }

    // Set defaults
    statementInfo['currency'] = 'INR';
    statementInfo['card_type'] = 'credit';
    statementInfo['card_name'] =
        normalizeCardName('$bankName Credit Card', statementInfo['bank_name']);

    return statementInfo;
  }

  /// Convert date format from DD/MM/YYYY or DD-MM-YYYY to ISO string
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

  /// Parse individual transactions using Gemini AI
  static Future<List<Map<String, dynamic>>> parseTransactions({
    required String pdfText,
    required String bankName,
  }) async {
    try {
      // Build enhanced prompt for transaction extraction based on bank-specific formats
      final bankSpecificInstructions = _getBankSpecificInstructions(bankName);
      final prompt =
          '''You are an expert at extracting transactions from Indian credit card statements. Analyze this ${bankName.toUpperCase()} statement and extract ALL transactions.

BANK: $bankName

$bankSpecificInstructions

EXTRACTION STRATEGY:
1. Find transaction table sections (look for headers like "Date", "Transaction", "Amount")
2. Extract each row that contains: Date + Description + Amount
3. Skip summary rows, balance rows, and headers
4. Parse amounts carefully - "CR" = credit (+), "D"/"Dr" = debit (-)
5. Clean merchant names (remove codes, URLs, extra numbers)
6. Convert all dates to YYYY-MM-DD format

JSON OUTPUT (return ONLY this array, no markdown blocks):
[
  {
    "date": "YYYY-MM-DD",
    "description": "Clean merchant name without codes",
    "amount": number (positive for credits, negative for debits),
    "currency": "INR",
    "merchantName": "Primary merchant name",
    "category": "shopping|dining|travel|fuel|entertainment|bills|transfer|fee|payment|cash|other",
    "type": "debit|credit",
    "reward_points": number or null (reward/loyalty points earned for this transaction, 0 if none),
    "reference": "transaction reference if clearly visible"
  }
]

ANALYZE THIS STATEMENT:''';

      final cleanedText = _pruneAndCleanText(pdfText, bankName);
      final requestBody = {
        'contents': [
          {
            'parts': [
              {'text': prompt + '\n\n' + cleanedText}
            ]
          }
        ],
        'generationConfig': {
          'temperature': 0.1,
          'maxOutputTokens': 8192, // SBI 39K-char statements need more room
        }
      };

      // Call Gemini API with automatic fallback
      final response =
          await _callGeminiWithFallback(requestBody, maxRetries: 3);

      if (response != null && response.statusCode == 200) {
        final decoded = json.decode(response.body);
        final content =
            decoded['candidates']?[0]?['content']?['parts']?[0]?['text'];

        if (content != null) {
          try {
            String cleanContent = _extractJsonPayload(content);

            final List<dynamic> list = json.decode(cleanContent);

            // Assign UUIDs to each transaction if missing
            final uuid = Uuid();
            final transactions = list.map<Map<String, dynamic>>((item) {
              final m = Map<String, dynamic>.from(item);
              m['id'] = m['id'] ?? uuid.v4();
              return m;
            }).toList();

            ParsingLogger.summary(
                'Gemini Parser: Successfully parsed ${transactions.length} transactions');
            return transactions;
          } catch (e) {
            ParsingLogger.error(
                'Gemini Parser: Failed to parse JSON response', e);
            ParsingLogger.debug('Raw content: $content');
          }
        }
      } else if (response != null) {
        ParsingLogger.error(
            'Gemini Parser: Non-200 response, status ${response.statusCode}');
        ParsingLogger.debug('Response body: ${response.body}');
      } else {
        ParsingLogger.error('Gemini Parser: All API attempts failed');
      }
      return [];
    } catch (e) {
      ParsingLogger.error('Gemini Parser: Error parsing transactions', e);
      return [];
    }
  }

  /// Normalize a bank name to a canonical form to prevent duplicates
  ///
  /// DEPRECATED: Use CardNormalizerService.normalizeBankName() instead
  /// This method is kept for backward compatibility but delegates to the shared service.
  static String normalizeBankName(String rawName) {
    return CardNormalizerService.normalizeBankName(rawName);
  }

  /// Normalize a card name to extract just the variant name
  ///
  /// DEPRECATED: Use CardNormalizerService.normalizeCardName() instead
  /// This method is kept for backward compatibility but delegates to the shared service.
  ///
  /// [rawName] - The raw card name from the input (e.g., "Axis Bank Aura Credit Card")
  /// [bankName] - The normalized bank name (e.g., "Axis Bank")
  ///
  /// Returns: Just the variant name (e.g., "Aura", "Miles", "Diners Club Rewardz")
  static String normalizeCardName(String rawName, String bankName) {
    return CardNormalizerService.normalizeCardName(rawName, bankName);
  }

  /// Get bank-specific transaction parsing instructions
  static String _getBankSpecificInstructions(String bankName) {
    final bank = bankName.toLowerCase();

    if (bank.contains('icici')) {
      return '''
ICICI SPECIFIC INSTRUCTIONS:
- Look for tables with: Date | SerNo | Transaction Details | Reward Points | Amount (₹)
- Date format: DD/MM/YYYY (like 14/05/2025)
- Merchant format: Often includes codes like "IND*AMAZON HTTP://WWW.AM IN"
- Amount format: 5,248.00 or 3,372.08 CR
- Credit indicators: CR at end of amount
- Common merchants: Amazon, BBPS payments, UPI transactions
- Clean merchants: Remove "IND*", "HTTP://", country codes
      ''';
    } else if (bank.contains('sbi')) {
      return '''
SBI CARD SPECIFIC INSTRUCTIONS:
- Look for tables with: Date | Transaction Details | Amount (₹)
- Date format: DD MMM YY (like 05 May 25, 13 May 25)
- Amount format: 648.00 or 149.00 D
- Debit indicator: D at end of amount
- Credit indicator: C or CR at end, or "PAYMENT RECEIVED"
- Common patterns: "YOUTUBE C103 S MUMBAI", "NETFLIX"
- Clean merchants: Remove reference numbers, location codes
      ''';
    } else if (bank.contains('hdfc')) {
      return '''
HDFC BANK SPECIFIC INSTRUCTIONS:
- Look for tables with: Date | Transaction Description | Feature Reward Points | Amount (in Rs.)
- Date format: DD/MM/YYYY HH:MM:SS (like 16/05/2025 14:39:30)
- Amount format: 28,750.00 Cr or 2,783.00 (no suffix = debit)
- Credit indicators: Cr, "CREDIT", "Payment received"
- Merchants often include full URLs and reference numbers
- Clean merchants: Remove "(Ref# ...)", URLs, transaction IDs
      ''';
    } else {
      return '''
GENERAL INDIAN BANK INSTRUCTIONS:
- Look for date + description + amount patterns
- Common date formats: DD/MM/YYYY, DD-MM-YYYY, DD MMM YYYY
- Amount indicators: CR/Cr = credit, D/Dr = debit, no suffix = debit
- Clean merchants by removing codes, URLs, reference numbers
      ''';
    }
  }

  /// NEW: Extract card benefits from web content using Gemini AI
  ///
  /// This method leverages the existing Gemini API integration to extract
  /// structured benefit information from bank websites and card brochures.
  ///
  /// [cardName] - The normalized card name (e.g., "Regalia")
  /// [bankName] - The normalized bank name (e.g., "HDFC Bank")
  /// [htmlContent] - The HTML content from the card's website
  /// [pdfContent] - Optional PDF content from brochures (nullable)
  ///
  /// Returns: Structured benefit data with confidence scoring
  static Future<Map<String, dynamic>> extractCardBenefits({
    required String cardName,
    required String bankName,
    required String htmlContent,
    String? pdfContent,
  }) async {
    try {
      ParsingLogger.summary(
          'Benefits Extraction: Starting extraction for $bankName $cardName using Gemini AI');

      final prompt = buildBenefitExtractionPrompt(cardName, bankName);
      final content = htmlContent +
          (pdfContent != null ? '\n\nPDF CONTENT:\n$pdfContent' : '');

      // Use same API pattern as existing parseStatementInfo method
      final requestBody = {
        'contents': [
          {
            'parts': [
              {'text': prompt + '\n\n' + content}
            ]
          }
        ],
        'generationConfig': benefitGenerationConfig,
      };

      // Call Gemini API with automatic fallback
      final response =
          await _callGeminiWithFallback(requestBody, maxRetries: 3);

      if (response != null && response.statusCode == 200) {
        final jsonResponse = json.decode(response.body);

        if (jsonResponse['candidates'] != null &&
            jsonResponse['candidates'].isNotEmpty) {
          final text =
              jsonResponse['candidates'][0]['content']['parts'][0]['text'];
          ParsingLogger.summary(
              'Benefits Extraction: Received response from Gemini AI');

          // Parse the JSON response from Gemini
          final benefitData = _parseBenefitResponse(text, cardName, bankName);

          if (benefitData['success'] == false) {
            return {
              'success': false,
              'error': benefitData['error'] ?? 'Invalid extraction response',
              'data': benefitData,
            };
          }

          return {
            'success': true,
            'data': benefitData,
            'source': 'gemini_ai',
            'extracted_at': DateTime.now().toIso8601String(),
          };
        }
      }

      if (response != null) {
        ParsingLogger.error(
            'Benefits Extraction: Non-200 response, status ${response.statusCode}: ${response.body.length > 500 ? response.body.substring(0, 500) : response.body}');
        return {
          'success': false,
          'error': 'API request failed with status ${response.statusCode}',
          'data': null,
        };
      } else {
        ParsingLogger.error('Benefits Extraction: All API attempts failed');
        return {
          'success': false,
          'error': 'All API attempts exhausted',
          'data': null,
        };
      }
    } catch (e) {
      ParsingLogger.error('Benefits Extraction: Error extracting benefits', e);
      return {
        'success': false,
        'error': e.toString(),
        'data': null,
      };
    }
  }

  static Map<String, dynamic> get benefitGenerationConfig => const {
        'temperature': 0.1,
        'maxOutputTokens': 8192,
      };

  /// Makes one narrowly scoped repair call after the main extraction. The
  /// caller must still validate and stage the returned candidates; this method
  /// intentionally has no database side effects.
  static Future<Map<String, dynamic>> repairBenefitClaims({
    required String cardName,
    required String bankName,
    required List<BenefitRepairTarget> targets,
  }) async {
    if (targets.isEmpty) {
      return const {'success': true, 'repairs': <dynamic>[]};
    }

    try {
      final prompt = buildBenefitRepairPrompt(
        cardName: cardName,
        bankName: bankName,
        targets: targets,
      );
      final response = await _callGeminiWithFallback({
        'contents': [
          {
            'parts': [
              {'text': prompt}
            ]
          }
        ],
        'generationConfig': const {
          'temperature': 0.0,
          'maxOutputTokens': 4096,
        },
      }, maxRetries: 1);
      if (response == null || response.statusCode != 200) {
        return {
          'success': false,
          'error':
              'Repair call failed${response == null ? '' : ' (${response.statusCode})'}',
        };
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final text =
          body['candidates']?[0]?['content']?['parts']?[0]?['text']?.toString();
      if (text == null || text.trim().isEmpty) {
        return const {
          'success': false,
          'error': 'Repair call returned no text'
        };
      }
      final match = RegExp(r'\{.*\}', dotAll: true).firstMatch(text);
      if (match == null) {
        return const {
          'success': false,
          'error': 'Repair call returned invalid JSON'
        };
      }
      final decoded = jsonDecode(match.group(0)!) as Map<String, dynamic>;
      final repairs = decoded['repairs'];
      if (repairs is! List) {
        return const {
          'success': false,
          'error': 'Repair response has no repairs list'
        };
      }
      return {'success': true, 'repairs': repairs};
    } catch (error) {
      ParsingLogger.error(
          'Benefits repair: Error parsing repair response', error);
      return {'success': false, 'error': error.toString()};
    }
  }

  static String buildBenefitRepairPrompt({
    required String cardName,
    required String bankName,
    required List<BenefitRepairTarget> targets,
  }) {
    final sourceTargets =
        targets.map((target) => jsonEncode(target.toJson())).join('\n');
    return '''
You repair incomplete benefit extraction for exactly $bankName $cardName.

You may interpret ONLY the source targets below. Do not use card knowledge,
other web text, or assumptions. Each source_excerpt is the complete verbatim
evidence you may use for that target.

For each target that contains a real card benefit, emit at most one typed repair.
Preserve every stated cap, threshold, transaction range, exclusion, eligibility
rule, and geography in structured fields or conditions. Do not add a repair for
a heading, navigation label, or text that is not a card benefit.

evidence_excerpt must copy the target source_excerpt exactly as supplied. Never
paraphrase it. target_id must match the supplied id exactly. If the target is
ambiguous, omit it rather than guessing.

Return ONLY JSON:
{
  "repairs": [
    {
      "target_id": "repair:0",
      "category": "FUEL|REWARDS|LOUNGE|FOREX|INSURANCE|TRAVEL|DINING|CONCIERGE|GENERAL",
      "type": "specific benefit type",
      "description": "precise card benefit",
      "rate": "number or null",
      "rate_type": "percentage|points|flat_amount|null",
      "monthly_cap": "number or null",
      "annual_cap": "number or null",
      "min_spend_threshold": "number or null",
      "max_cap_limit": "number or null",
      "conditions": "all non-numeric qualifiers or null",
      "excluded_categories": ["only explicit exclusions"],
      "evidence_excerpt": "exact target source excerpt"
    }
  ]
}

SOURCE TARGETS:
$sourceTargets
''';
  }

  /// Build the specialized prompt for benefit extraction
  static String buildBenefitExtractionPrompt(String cardName, String bankName) {
    return '''
You are a source-grounded credit card analyst. Extract only claims explicitly supported by the supplied source for this exact card variant.

CARD: $bankName $cardName
TASK: Return factual benefit information in structured JSON. The supplied source is the only authority.

STRICT GROUNDING RULES:
- Do not emit a claim unless an exact supporting sentence occurs in the supplied source.
- Copy that sentence into evidence_excerpt. Never paraphrase evidence_excerpt.
- Every percentage, amount, points rate, cap, threshold, fee, waiver, and lounge count must occur in evidence_excerpt.
- Do not use prior knowledge about this card or infer a benefit from the card name.
- Do not complete categories merely because they exist in this schema. Return only categories supported by evidence.
- Do not emit zero-value placeholders such as "Travel benefits" or "Lounge benefits".
- Ignore navigation, headers, footers, calls to action, customer support, savings account or salary account promotions, personal loan promotions, wealth management, unrelated cards, and generic bank services.
- EMI conversion availability, application links, customer service, and generic concierge copy are not card benefits without a concrete card-specific entitlement.
- Missing information must remain null. Never estimate, assume, or substitute a default.
- If the source identifies a different card variant, return no benefits and explain the mismatch in extraction_notes.
- Preserve qualifiers such as "up to", promotional dates, merchant restrictions, exclusions, and spend conditions.
- Return each entitlement as an atomic claim. When a source paragraph contains an entitlement plus an eligibility rule, cap, exclusion, redemption rule, or geographic restriction, preserve every part in the claim's structured fields.
- One card benefit may produce multiple claims only when the source describes genuinely different entitlements. Do not merge distinct benefits merely because they share a section.
- Do not omit a source-backed entitlement because it lacks a numeric value. Extract card-specific hotel, dining, insurance, concierge, forex, and travel offers when supported.
- Preserve all qualifying conditions for lounge, fuel, rewards, insurance, and travel offers: thresholds, date or quarter rules, caps, transaction ranges, exclusions, request requirements, and geographic restrictions.
- After extracting, scan every benefit-like source sentence once more. Do not omit a source-backed entitlement: it must appear in the returned JSON with its exact evidence_excerpt.

JSON OUTPUT FORMAT:
{
  "card_name": "exact card name found",
  "bank_name": "bank name",
  "annual_fee": {
    "first_year": amount_or_null,
    "renewal": amount_or_null,
    "waiver_conditions": "text or null",
    "evidence_excerpt": "exact source sentence or null"
  },
  "cashback_benefits": [
    {
      "category": "DINING|TRAVEL|FUEL|SHOPPING|GROCERY|ENTERTAINMENT|UTILITIES|GENERAL",
      "rate": percentage_as_number,
      "rate_type": "percentage|flat_amount|points",
      "description": "detailed description",
      "conditions": "all qualifying conditions from the evidence, or null",
      "monthly_cap": amount_or_null,
      "annual_cap": amount_or_null,
      "min_spend_threshold": amount_or_null,
      "max_cap_limit": amount_or_null,
      "excluded_categories": ["category names excluded from earning rewards"],
      "excluded_merchants": ["merchant names excluded from earning rewards"],
      "is_accelerated": true_or_false,
      "merchants": ["specific merchant names if any"],
      "evidence_excerpt": "exact source sentence containing the claim"
    }
  ],
  "reward_points": {
    "base_rate": points_per_100_rupees,
    "accelerated_categories": [
      {
        "category": "category name",
        "rate": points_per_100_rupees,
        "conditions": "conditions if any",
        "evidence_excerpt": "exact source sentence containing the claim"
      }
    ]
  },
  "special_benefits": [
    {
      "type": "LOUNGE|INSURANCE|CONCIERGE|OTHER",
      "description": "detailed description",
      "value": "explicit numeric or nonnumeric entitlement value, or null",
      "evidence_excerpt": "exact source sentence containing the claim"
    }
  ],
  "confidence_score": 0.0_to_1.0,
  "extraction_notes": "any ambiguities or assumptions made"
}

CONTENT TO ANALYZE:
''';
  }

  /// Parse the benefit response from Gemini and validate the data
  static Map<String, dynamic> _parseBenefitResponse(
      String responseText, String cardName, String bankName) {
    try {
      // Extract JSON from the response (handle cases where AI adds extra text)
      final jsonMatch =
          RegExp(r'\{.*\}', dotAll: true).firstMatch(responseText);

      if (jsonMatch != null) {
        final jsonString = jsonMatch.group(0)!;
        final benefitData = json.decode(jsonString) as Map<String, dynamic>;

        // Add metadata
        benefitData['extracted_for_card'] = cardName;
        benefitData['extracted_for_bank'] = bankName;
        benefitData['raw_response'] = responseText;

        // Validate and calculate confidence score
        final confidence = _calculateExtractionConfidence(benefitData);
        benefitData['calculated_confidence'] = confidence;

        return benefitData;
      } else {
        ParsingLogger.warning(
            'Benefits Extraction: No JSON found in Gemini response, returning raw text');
        return {
          'success': false,
          'error': 'Could not parse JSON from response',
          'raw_response': responseText,
          'confidence_score': 0.0,
        };
      }
    } catch (e) {
      ParsingLogger.error(
          'Benefits Extraction: Error parsing benefit response', e);
      return {
        'success': false,
        'error': 'JSON parsing failed: $e',
        'raw_response': responseText,
        'confidence_score': 0.0,
      };
    }
  }

  /// Calculate confidence score for extracted benefits
  static double _calculateExtractionConfidence(
      Map<String, dynamic> benefitData) {
    double confidence = 0.0;

    // Check if basic required fields exist
    if (benefitData['card_name'] != null) confidence += 0.2;
    if (benefitData['bank_name'] != null) confidence += 0.2;

    // Check for benefit data
    if (benefitData['cashback_benefits'] is List &&
        (benefitData['cashback_benefits'] as List).isNotEmpty)
      confidence += 0.3;

    if (benefitData['reward_points'] != null) confidence += 0.2;

    // Check if AI provided its own confidence score
    if (benefitData['confidence_score'] is num) {
      final aiConfidence = (benefitData['confidence_score'] as num).toDouble();
      confidence =
          (confidence + aiConfidence) / 2; // Average with AI's confidence
    }

    return confidence.clamp(0.0, 1.0);
  }

  /// Public wrapper around _callGeminiWithFallback for use by external services.
  static Future<http.Response?> callGeminiRaw(
    Map<String, dynamic> requestBody, {
    int maxRetries = 3,
  }) =>
      _callGeminiWithFallback(requestBody, maxRetries: maxRetries);

  /// Call Gemini API with automatic fallback to alternate models on rate limit.
  /// If activeProvider is Ollama, query Ollama instead and wrap the response
  /// to mimic Gemini structure for caller compatibility.
  /// Returns the response if successful, null if all attempts failed
  static Future<http.Response?> _callGeminiWithFallback(
    Map<String, dynamic> requestBody, {
    int maxRetries = 3,
  }) async {
    // Extract the prompt from requestBody
    final contentsList = requestBody['contents'] as List?;
    final partsList = contentsList?[0]?['parts'] as List?;
    final prompt = partsList?[0]?['text'] as String? ?? '';

    // ── OLLAMA PROVIDER ROAD ──
    if (AIConfig.activeProvider == AIProvider.ollama) {
      final response = await _executeOllamaRequest(prompt);
      if (response != null) return response;
      return null;
    }

    // ── GROQ PROVIDER ROAD ──
    if (AIConfig.activeProvider == AIProvider.groq) {
      if (AIConfig.groqApiKey.isEmpty) {
        throw Exception(
            'Groq API Key is empty. Please enter your Groq key in settings.');
      }

      // Model fallback queue (try the user's active configuration first)
      final groqModels = [
        'llama-3.1-8b-instant',
        'llama-3.3-70b-versatile',
        'mixtral-8x7b-32768'
      ];
      final activeModel = AIConfig.groqModel;
      final modelQueue = [activeModel];
      for (final m in groqModels) {
        if (m != activeModel) modelQueue.add(m);
      }

      http.Response? lastResponse;

      for (int i = 0; i < modelQueue.length; i++) {
        final currentModel = modelQueue[i];
        try {
          ParsingLogger.summary(
              'Groq Parser: Attempting request using model: $currentModel');

          final groqReq = {
            'model': currentModel,
            'messages': [
              {
                'role': 'user',
                'content': prompt,
              }
            ],
            'temperature': 0.1,
          };

          final response = await http
              .post(
                Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
                headers: {
                  'Content-Type': 'application/json',
                  'Authorization': 'Bearer ${AIConfig.groqApiKey}',
                },
                body: jsonEncode(groqReq),
              )
              .timeout(const Duration(seconds: 45));

          lastResponse = response;

          if (response.statusCode == 200) {
            final jsonResponse = jsonDecode(response.body);
            final text = jsonResponse['choices']?[0]?['message']?['content']
                    as String? ??
                '';

            final geminiJsonWrapper = {
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {'text': text}
                    ]
                  }
                }
              ]
            };

            return http.Response(
              jsonEncode(geminiJsonWrapper),
              200,
              headers: response.headers,
            );
          } else {
            ParsingLogger.warning(
                'Groq Parser: Model $currentModel returned error ${response.statusCode}');
            // If it is a rate limit or prompt size error, try next model immediately
            if (response.statusCode == 429 ||
                response.statusCode == 413 ||
                response.statusCode == 400) {
              continue;
            }
            return response;
          }
        } catch (e) {
          ParsingLogger.error(
              'Groq Parser: Call failed on model $currentModel', e);
        }
      }

      // If all Groq models failed, check if Ollama is available locally as a backup
      if (await _isOllamaAvailable()) {
        ParsingLogger.warning(
            'Groq Parser: All Groq API models failed/rate-limited. Automatically switching to local Ollama fallback...');
        final backupResponse = await _executeOllamaRequest(prompt);
        if (backupResponse != null) return backupResponse;
      }

      return lastResponse;
    }

    // ── GEMINI PROVIDER ROAD ──
    int attempt = 0;

    while (attempt < maxRetries) {
      attempt++;

      try {
        ParsingLogger.summary(
            'Gemini Parser: API call attempt $attempt/$maxRetries using model: ${AIConfig.geminiModel}');

        final response = await sendGeminiRequest(requestBody);

        // Check if rate limit error occurred (429)
        if (AIConfig.isRateLimitError(response.statusCode, response.body)) {
          ParsingLogger.warning(
              'Gemini Parser: Rate limit detected (Status: ${response.statusCode})');

          // Try to switch to fallback model
          final switched = AIConfig.switchToFallbackModel();

          if (!switched) {
            ParsingLogger.error(
                'Gemini Parser: No more fallback models available');
            if (attempt < maxRetries) {
              // Free-tier resets every 60s — wait for the window to pass
              ParsingLogger.summary(
                  'Gemini Parser: Waiting 60s for rate limit reset...');
              await Future.delayed(const Duration(seconds: 60));
              AIConfig.resetToPrimaryModel();
              continue;
            }
            return response;
          }

          // Stepped backoff when switching models: 15s → 30s → 45s
          final waitSeconds = attempt * 15;
          ParsingLogger.summary(
              'Gemini Parser: Waiting ${waitSeconds}s before retry with fallback model...');
          await Future.delayed(Duration(seconds: waitSeconds));
          continue;
        }

        // Success or non-rate-limit error — return the response
        if (response.statusCode == 200) {
          ParsingLogger.summary(
              'Gemini Parser: API call successful with model: ${AIConfig.geminiModel}');
        }
        return response;
      } catch (e) {
        ParsingLogger.error(
            'Gemini Parser: API call error on attempt $attempt', e);

        if (attempt < maxRetries) {
          ParsingLogger.summary(
              'Gemini Parser: Waiting 10 seconds before retry...');
          await Future.delayed(const Duration(seconds: 10));
          AIConfig.switchToFallbackModel();
        }
      }
    }

    ParsingLogger.error('Gemini Parser: All API attempts exhausted');

    if (await _isOllamaAvailable()) {
      ParsingLogger.warning(
          'Gemini Parser: Gemini API failed/rate-limited. Automatically switching to local Ollama fallback...');
      final backupResponse = await _executeOllamaRequest(prompt);
      if (backupResponse != null) return backupResponse;
    }

    return null;
  }

  static String _pruneAndCleanText(String text, [String? bankName]) {
    if (text.isEmpty) return text;

    // 1. Clean whitespace
    String cleaned = text.replaceAll(RegExp(r'\n+'), '\n');
    cleaned = cleaned.replaceAll(RegExp(r' {2,}'), ' ');
    cleaned = cleaned.trim();

    // 2. Prune boilerplate (T&C, grievance redressal, branches list) at the end
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

    int bestCutIndex = -1;
    for (final marker in markers) {
      final idx = lowerText.indexOf(marker);
      if (idx != -1) {
        if (bestCutIndex == -1 || idx < bestCutIndex) {
          bestCutIndex = idx;
        }
      }
    }

    // Truncate only if we keep at least 3500 chars (safe threshold for transactions)
    if (bestCutIndex > 3500) {
      ParsingLogger.summary(
          'Text Pruning: PDF statement text reduced from ${cleaned.length} to $bestCutIndex characters');
      final original = cleaned;
      cleaned = cleaned.substring(0, bestCutIndex);

      // Log the pruning event to the audit service (async)
      PruningAuditService().logPruning(
        bankName: bankName ?? 'Unknown Bank',
        cardVariant: bankName ?? 'Unknown Card',
        originalText: original,
        prunedText: cleaned,
      );
    }

    return cleaned;
  }

  static Future<bool> _isOllamaAvailable() async {
    try {
      final response = await http
          .get(
            Uri.parse('${AIConfig.ollamaUrl}/api/tags'),
          )
          .timeout(const Duration(milliseconds: 500));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<http.Response?> _executeOllamaRequest(String prompt) async {
    try {
      final ollamaReq = {
        'model': AIConfig.ollamaModel,
        'prompt': prompt,
        'stream': false,
        'options': {
          'temperature': 0.1,
        }
      };

      final targetUrl = '${AIConfig.ollamaUrl}/api/generate';
      ParsingLogger.summary(
          'Ollama Parser: Sending fallback request using model: ${AIConfig.ollamaModel}');

      final response = await http
          .post(
        Uri.parse(targetUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(ollamaReq),
      )
          .timeout(const Duration(minutes: 5), onTimeout: () {
        throw Exception('Ollama API timeout.');
      });

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);
        final text = jsonResponse['response'] as String? ?? '';

        final geminiJsonWrapper = {
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': text}
                ]
              }
            }
          ]
        };

        return http.Response(
          jsonEncode(geminiJsonWrapper),
          200,
          headers: response.headers,
        );
      }
    } catch (e) {
      ParsingLogger.error('Ollama Parser: Fallback call failed', e);
    }
    return null;
  }

  static String _extractJsonPayload(String text) {
    text = text.trim();

    // Find the first bracket/brace
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

    // Heal the JSON payload to recover truncated arrays or objects
    text = _healJsonPayload(text);
    return text;
  }

  static String _healJsonPayload(String text) {
    text = text.trim();
    if (text.isEmpty) return text;

    if (text.startsWith('[')) {
      if (!text.endsWith(']')) {
        // If it doesn't end with a closing array bracket, it was truncated.
        // Find the last complete object in the array
        final lastBrace = text.lastIndexOf('}');
        if (lastBrace != -1) {
          text = text.substring(0, lastBrace + 1);
        }
        // If there's a trailing comma (like between objects), remove it
        text = text.trim();
        if (text.endsWith(',')) {
          text = text.substring(0, text.length - 1).trim();
        }
        text += ']';
        ParsingLogger.summary(
            'JSON Healing: Recovered incomplete JSON array and appended "]"');
      }
    } else if (text.startsWith('{')) {
      if (!text.endsWith('}')) {
        // For a JSON object, if it's incomplete, close open braces
        int openBraces = 0;
        int closeBraces = 0;
        for (int i = 0; i < text.length; i++) {
          if (text[i] == '{') openBraces++;
          if (text[i] == '}') closeBraces++;
        }
        if (openBraces > closeBraces) {
          text += '}' * (openBraces - closeBraces);
        }
        ParsingLogger.summary(
            'JSON Healing: Recovered incomplete JSON object by closing open braces');
      }
    }
    return text;
  }
}
