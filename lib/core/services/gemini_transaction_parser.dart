import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/ai_config.dart';
import 'package:uuid/uuid.dart';
import 'card_normalizer_service.dart';

/// Gemini AI Transaction Parser service
class GeminiTransactionParser {
  
  /// Parse statement-level information using Gemini AI
  static Future<Map<String, dynamic>> parseStatementInfo({
    required String pdfText,
    required String bankName,
  }) async {
    try {
      // Build enhanced prompt for statement information extraction
      final prompt = '''You are an expert financial statement analyzer. Extract key information from this credit card statement.

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
      
      final cleanedText = _pruneAndCleanText(pdfText);
      final requestBody = {
        'contents': [{
          'parts': [{
            'text': prompt + '\n\n' + cleanedText
          }]
        }],
        'generationConfig': {
          'temperature': 0.1,
          'maxOutputTokens': 512
        }
      };

      
      // Call Gemini API with automatic fallback
      final response = await _callGeminiWithFallback(requestBody, maxRetries: 3);
      
      if (response != null && response.statusCode == 200) {
        final decoded = json.decode(response.body);
        final content = decoded['candidates']?[0]?['content']?['parts']?[0]?['text'];
        
        if (content != null) {
          try {
            // Strip markdown code fences robustly (Gemini wraps in ```json\n...\n```)
            String cleanContent = content.trim();
            cleanContent = cleanContent.replaceAll(RegExp(r'^```(?:json)?\s*', multiLine: false), '');
            cleanContent = cleanContent.replaceAll(RegExp(r'\s*```$', multiLine: false), '');
            cleanContent = cleanContent.trim();
            
            // Try to parse the JSON response
            final Map<String, dynamic> result = json.decode(cleanContent);
            
            // Normalize bank and card names
            final normBank = normalizeBankName(bankName);
            result['bank_name'] = normBank;
            if (result.containsKey('card_name') && result['card_name'] != null) {
              result['card_name'] = normalizeCardName(result['card_name'].toString(), normBank);
            } else {
              result['card_name'] = normalizeCardName('$normBank Credit Card', normBank);
            }
            
            print('✅ GEMINI PARSING: Successfully parsed statement info');
            return result;
          } catch (e) {
            print('❌ GEMINI PARSING: Failed to parse JSON response: $e');
            print('Raw content: $content');
          }
        }
      } else if (response != null) {
        print('❌ GEMINI PARSING: Non-200 response, status ${response.statusCode}');
        print('Response body: ${response.body}');
      } else {
        print('❌ GEMINI PARSING: All API attempts failed');
      }
      
      // Fallback to basic extraction if API fails
      return _fallbackStatementParsing(pdfText, bankName);
      
    } catch (e) {
      print('❌ GEMINI PARSER: Error parsing statement info: $e');
      return _fallbackStatementParsing(pdfText, bankName);
    }
  }
  
  /// Fallback method for basic statement parsing using regex
  static Map<String, dynamic> _fallbackStatementParsing(String pdfText, String bankName) {
    final Map<String, dynamic> statementInfo = {};
    
    // Normalize bank name upfront
    statementInfo['bank_name'] = normalizeBankName(bankName);
    
    // Try to extract statement date
    final dateMatch = RegExp(r'statement date[:\s]*(\d{2}[-/]\d{2}[-/]\d{4})', caseSensitive: false).firstMatch(pdfText);
    if (dateMatch != null) {
      statementInfo['statement_date'] = _convertDateFormat(dateMatch.group(1)!);
    }
    
    // Try to extract due date
    final dueDateMatch = RegExp(r'due date[:\s]*(\d{2}[-/]\d{2}[-/]\d{4})', caseSensitive: false).firstMatch(pdfText);
    if (dueDateMatch != null) {
      statementInfo['due_date'] = _convertDateFormat(dueDateMatch.group(1)!);
    }
    
    // Try to extract total amount
    final amountMatch = RegExp(r'total[:\s]*(?:amount|outstanding)[:\s]*(?:rs\.?|₹)?\s*([\d,]+\.?\d*)', caseSensitive: false).firstMatch(pdfText);
    if (amountMatch != null) {
      statementInfo['total_amount'] = double.tryParse(amountMatch.group(1)!.replaceAll(',', '')) ?? 0.0;
    }
    
    // Set defaults
    statementInfo['currency'] = 'INR';
    statementInfo['card_type'] = 'credit';
    statementInfo['card_name'] = normalizeCardName('$bankName Credit Card', statementInfo['bank_name']);
    
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
      print('Error parsing date: $dateStr');
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
      final prompt = '''You are an expert at extracting transactions from Indian credit card statements. Analyze this ${bankName.toUpperCase()} statement and extract ALL transactions.

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
      
      final cleanedText = _pruneAndCleanText(pdfText);
      final requestBody = {
        'contents': [{
          'parts': [{
            'text': prompt + '\n\n' + cleanedText
          }]
        }],
        'generationConfig': {
          'temperature': 0.1,
          'maxOutputTokens': 8192,  // SBI 39K-char statements need more room
        }
      };

      
      // Call Gemini API with automatic fallback
      final response = await _callGeminiWithFallback(requestBody, maxRetries: 3);
      
      if (response != null && response.statusCode == 200) {
        final decoded = json.decode(response.body);
        final content = decoded['candidates']?[0]?['content']?['parts']?[0]?['text'];
        
        if (content != null) {
          try {
            // Strip markdown code fences robustly (Gemini wraps in ```json\n...\n```)
            String cleanContent = content.trim();
            cleanContent = cleanContent.replaceAll(RegExp(r'^```(?:json)?\s*', multiLine: false), '');
            cleanContent = cleanContent.replaceAll(RegExp(r'\s*```$', multiLine: false), '');
            cleanContent = cleanContent.trim();

            final List<dynamic> list = json.decode(cleanContent);
            // Assign UUIDs to each transaction if missing
            final uuid = Uuid();
            final transactions = list.map<Map<String, dynamic>>((item) {
              final m = Map<String, dynamic>.from(item);
              m['id'] = m['id'] ?? uuid.v4();
              return m;
            }).toList();
            
            print('✅ GEMINI PARSING: Successfully parsed ${transactions.length} transactions');
            return transactions;
          } catch (e) {
            print('❌ GEMINI PARSING: Failed to parse JSON response: $e');
            print('Raw content: $content');
          }
        }
      } else if (response != null) {
        print('❌ GEMINI PARSING: Non-200 response, status ${response.statusCode}');
        print('Response body: ${response.body}');
      } else {
        print('❌ GEMINI PARSING: All API attempts failed');
      }
      return [];
    } catch (e) {
      print('❌ GEMINI PARSER: Error parsing transactions: $e');
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
      print('🤖 EXTRACTING BENEFITS: $bankName $cardName');
      
      final prompt = _buildBenefitExtractionPrompt(cardName, bankName);
      final content = htmlContent + (pdfContent != null ? '\n\nPDF CONTENT:\n$pdfContent' : '');
      
      // Use same API pattern as existing parseStatementInfo method
      final requestBody = {
        'contents': [{
          'parts': [{'text': prompt + '\n\n' + content}]
        }],
        'generationConfig': {
          'temperature': 0.1, // Low temperature for factual extraction
          'maxOutputTokens': 4096, // Higher limit for detailed benefits
        }
      };

      // Call Gemini API with automatic fallback
      final response = await _callGeminiWithFallback(requestBody, maxRetries: 3);

      if (response != null && response.statusCode == 200) {
        final jsonResponse = json.decode(response.body);
        
        if (jsonResponse['candidates'] != null && 
            jsonResponse['candidates'].isNotEmpty) {
          
          final text = jsonResponse['candidates'][0]['content']['parts'][0]['text'];
          print('✅ GEMINI BENEFIT EXTRACTION: Received response');
          
          // Parse the JSON response from Gemini
          final benefitData = _parseBenefitResponse(text, cardName, bankName);
          
          return {
            'success': true,
            'data': benefitData,
            'source': 'gemini_ai',
            'extracted_at': DateTime.now().toIso8601String(),
          };
        }
      }
      
      if (response != null) {
        print('❌ GEMINI BENEFIT EXTRACTION: Non-200 response, status ${response.statusCode}');
        return {
          'success': false,
          'error': 'API request failed with status ${response.statusCode}',
          'data': null,
        };
      } else {
        print('❌ GEMINI BENEFIT EXTRACTION: All API attempts failed');
        return {
          'success': false,
          'error': 'All API attempts exhausted',
          'data': null,
        };
      }
      
    } catch (e) {
      print('❌ GEMINI BENEFIT EXTRACTION: Error extracting benefits: $e');
      return {
        'success': false,
        'error': e.toString(),
        'data': null,
      };
    }
  }

  /// Build the specialized prompt for benefit extraction
  static String _buildBenefitExtractionPrompt(String cardName, String bankName) {
    return '''
You are an expert credit card analyst. Extract ALL benefits from this $bankName $cardName credit card information.

CARD: $bankName $cardName
TASK: Extract detailed benefit information in structured JSON format.

BENEFIT CATEGORIES TO LOOK FOR:
1. CASHBACK RATES (% or flat amounts)
   - Dining/Food delivery (Zomato, Swiggy, restaurants)
   - Travel (flights, hotels, booking sites)
   - Fuel/Petrol (specific pump chains)
   - Shopping (online/offline, specific merchants)
   - Grocery/Supermarkets
   - Entertainment (movies, streaming, OTT)
   - Utilities (electricity, mobile, DTH)
   - General purchases

2. REWARD POINTS
   - Points per ₹100 spent
   - Category-specific multipliers
   - Point redemption values

3. MILESTONE BENEFITS
   - Annual spending thresholds
   - Bonus points/cashback on milestones

4. CAPS & LIMITS
   - Monthly cashback caps
   - Annual benefit limits
   - Category-wise caps

5. FEES & CHARGES
   - Annual fee (first year, renewal)
   - Joining fee
   - Foreign transaction charges

6. SPECIAL BENEFITS
   - Airport lounge access
   - Insurance benefits
   - Concierge services
   - Movie ticket discounts

EXTRACTION RULES:
- Extract exact percentages and amounts (don't assume)
- Note any conditions or restrictions
- Identify merchant-specific offers
- Look for "up to X%" vs "flat X%" differences
- Extract both promotional and standard rates

JSON OUTPUT FORMAT:
{
  "card_name": "exact card name found",
  "bank_name": "bank name",
  "annual_fee": {
    "first_year": amount_or_null,
    "renewal": amount_or_null,
    "waiver_conditions": "text or null"
  },
  "cashback_benefits": [
    {
      "category": "DINING|TRAVEL|FUEL|SHOPPING|GROCERY|ENTERTAINMENT|UTILITIES|GENERAL",
      "rate": percentage_as_number,
      "rate_type": "percentage|flat_amount|points",
      "description": "detailed description",
      "conditions": "any conditions",
      "monthly_cap": amount_or_null,
      "annual_cap": amount_or_null,
      "merchants": ["specific merchant names if any"]
    }
  ],
  "reward_points": {
    "base_rate": points_per_100_rupees,
    "accelerated_categories": [
      {
        "category": "category name",
        "rate": points_per_100_rupees,
        "conditions": "conditions if any"
      }
    ]
  },
  "special_benefits": [
    {
      "type": "LOUNGE|INSURANCE|CONCIERGE|OTHER",
      "description": "detailed description",
      "value": "estimated annual value"
    }
  ],
  "confidence_score": 0.0_to_1.0,
  "extraction_notes": "any ambiguities or assumptions made"
}

CONTENT TO ANALYZE:
''';
  }

  /// Parse the benefit response from Gemini and validate the data
  static Map<String, dynamic> _parseBenefitResponse(String responseText, String cardName, String bankName) {
    try {
      // Extract JSON from the response (handle cases where AI adds extra text)
      final jsonMatch = RegExp(r'\{.*\}', dotAll: true).firstMatch(responseText);
      
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
        print('⚠️ No JSON found in Gemini response, returning raw text');
        return {
          'success': false,
          'error': 'Could not parse JSON from response',
          'raw_response': responseText,
          'confidence_score': 0.0,
        };
      }
    } catch (e) {
      print('❌ Error parsing benefit response: $e');
      return {
        'success': false,
        'error': 'JSON parsing failed: $e',
        'raw_response': responseText,
        'confidence_score': 0.0,
      };
    }
  }

  /// Calculate confidence score for extracted benefits
  static double _calculateExtractionConfidence(Map<String, dynamic> benefitData) {
    double confidence = 0.0;
    
    // Check if basic required fields exist
    if (benefitData['card_name'] != null) confidence += 0.2;
    if (benefitData['bank_name'] != null) confidence += 0.2;
    
    // Check for benefit data
    if (benefitData['cashback_benefits'] is List && 
        (benefitData['cashback_benefits'] as List).isNotEmpty) confidence += 0.3;
    
    if (benefitData['reward_points'] != null) confidence += 0.2;
    
    // Check if AI provided its own confidence score
    if (benefitData['confidence_score'] is num) {
      final aiConfidence = (benefitData['confidence_score'] as num).toDouble();
      confidence = (confidence + aiConfidence) / 2; // Average with AI's confidence
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
    // ── OLLAMA PROVIDER ROAD ──
    if (AIConfig.activeProvider == AIProvider.ollama) {
      try {
        final contentsList = requestBody['contents'] as List?;
        final partsList = contentsList?[0]?['parts'] as List?;
        final prompt = partsList?[0]?['text'] as String? ?? '';

        final ollamaReq = {
          'model': AIConfig.ollamaModel,
          'prompt': prompt,
          'stream': false,
          'options': {
            'temperature': 0.1,
          }
        };

        final targetUrl = '${AIConfig.ollamaUrl}/api/generate';
        print('🤖 Ollama Parser: Sending request to $targetUrl with model: ${AIConfig.ollamaModel}');

        final response = await http.post(
          Uri.parse(targetUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(ollamaReq),
        ).timeout(const Duration(seconds: 45), onTimeout: () {
          throw Exception('Ollama API timeout. Check if Ollama is running at ${AIConfig.ollamaUrl}');
        });

        if (response.statusCode == 200) {
          final jsonResponse = jsonDecode(response.body);
          final text = jsonResponse['response'] as String? ?? '';
          
          // Wrap the local LLM response into Gemini's JSON structure so
          // existing parser callers can extract the text seamlessly.
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
          return response;
        }
      } catch (e) {
        print('❌ Ollama Parser call error: $e');
        return null;
      }
    }

    // ── GROQ PROVIDER ROAD ──
    if (AIConfig.activeProvider == AIProvider.groq) {
      try {
        if (AIConfig.groqApiKey.isEmpty) {
          throw Exception('Groq API Key is empty. Please enter your Groq key in settings.');
        }

        final contentsList = requestBody['contents'] as List?;
        final partsList = contentsList?[0]?['parts'] as List?;
        final prompt = partsList?[0]?['text'] as String? ?? '';

        final groqReq = {
          'model': AIConfig.groqModel,
          'messages': [
            {
              'role': 'user',
              'content': prompt,
            }
          ],
          'temperature': 0.1,
        };

        print('🤖 Groq Parser: Sending request to completions endpoint with model: ${AIConfig.groqModel}');

        final response = await http.post(
          Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${AIConfig.groqApiKey}',
          },
          body: jsonEncode(groqReq),
        ).timeout(const Duration(seconds: 45), onTimeout: () {
          throw Exception('Groq API timeout. Check your network connection.');
        });

        if (response.statusCode == 200) {
          final jsonResponse = jsonDecode(response.body);
          final text = jsonResponse['choices']?[0]?['message']?['content'] as String? ?? '';

          // Wrap the Groq response into Gemini's JSON structure so
          // existing parser callers can extract the text seamlessly.
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
          return response;
        }
      } catch (e) {
        print('❌ Groq Parser call error: $e');
        return null;
      }
    }


    // ── GEMINI PROVIDER ROAD ──
    int attempt = 0;
    
    while (attempt < maxRetries) {
      attempt++;
      
      try {
        print('🔄 Gemini API call attempt $attempt/$maxRetries using model: ${AIConfig.geminiModel}');
        
        final response = await http.post(
          Uri.parse(AIConfig.geminiGenerateUrl),
          headers: AIConfig.geminiHeaders,
          body: json.encode(requestBody),
        );
        
        // Check if rate limit error occurred (429)
        if (AIConfig.isRateLimitError(response.statusCode, response.body)) {
          print('⚠️  Rate limit detected (Status: ${response.statusCode})');

          // Try to switch to fallback model
          final switched = AIConfig.switchToFallbackModel();

          if (!switched) {
            print('❌ No more fallback models available');
            if (attempt < maxRetries) {
              // Free-tier resets every 60s — wait for the window to pass
              print('⏳ Waiting 60s for Gemini rate limit reset...');
              await Future.delayed(const Duration(seconds: 60));
              AIConfig.resetToPrimaryModel();
              continue;
            }
            return response;
          }

          // Stepped backoff when switching models: 15s → 30s → 45s
          final waitSeconds = attempt * 15;
          print('⏳ Waiting ${waitSeconds}s before retry with fallback model...');
          await Future.delayed(Duration(seconds: waitSeconds));
          continue;
        }

        // Success or non-rate-limit error — return the response
        if (response.statusCode == 200) {
          print('✅ Gemini API call successful with model: ${AIConfig.geminiModel}');
        }
        return response;

      } catch (e) {
        print('❌ Gemini API call error on attempt $attempt: $e');

        if (attempt < maxRetries) {
          print('⏳ Waiting 10 seconds before retry...');
          await Future.delayed(const Duration(seconds: 10));
          AIConfig.switchToFallbackModel();
        }
      }
    }
    
    print('❌ All Gemini API attempts exhausted after $maxRetries tries');
    return null;
  }

  static String _pruneAndCleanText(String text) {
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
      print('✂️ Pruning PDF statement text: reduced from ${cleaned.length} to $bestCutIndex characters');
      cleaned = cleaned.substring(0, bestCutIndex);
    }
    
    return cleaned;
  }
}

