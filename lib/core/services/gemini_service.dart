import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:cardcompass/core/config/ai_config.dart';
import 'gemini_request_service.dart';
import 'gemini_call_log_service.dart';

/// Service for interacting with Google Gemini AI API
class GeminiService {
  /// Generate content using Gemini AI
  Future<String> generateContent({
    required String prompt,
    double temperature = 0.1,
    int maxTokens = 4000,
  }) async {
    try {
      // ── OLLAMA PROVIDER ROAD ──
      if (AIConfig.activeProvider == AIProvider.ollama) {
        final text = await _executeOllamaRequest(prompt, temperature);
        if (text != null) return text;
        throw Exception('Ollama query failed.');
      }

      // ── GROQ PROVIDER ROAD ──
      if (AIConfig.activeProvider == AIProvider.groq) {
        if (AIConfig.groqApiKey.isEmpty) {
          throw Exception(
              'Groq API Key is empty. Please enter your Groq key in settings.');
        }

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

        for (int i = 0; i < modelQueue.length; i++) {
          final currentModel = modelQueue[i];
          try {
            print('🤖 Groq API: Attempting request using model: $currentModel');

            final requestBody = {
              'model': currentModel,
              'messages': [
                {
                  'role': 'user',
                  'content': prompt,
                }
              ],
              'temperature': temperature,
            };

            final response = await http
                .post(
                  Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
                  headers: {
                    'Content-Type': 'application/json',
                    'Authorization': 'Bearer ${AIConfig.groqApiKey}',
                  },
                  body: jsonEncode(requestBody),
                )
                .timeout(const Duration(seconds: 45));

            if (response.statusCode == 200) {
              final jsonResponse = jsonDecode(response.body);
              final text = jsonResponse['choices']?[0]?['message']?['content']
                  as String?;
              if (text != null && text.isNotEmpty) {
                return text;
              }
            } else {
              print(
                  '⚠️ Groq API model $currentModel returned error: ${response.statusCode} - ${response.body}');
              if (response.statusCode == 429 ||
                  response.statusCode == 413 ||
                  response.statusCode == 400) {
                continue;
              }
              throw Exception(
                  'Groq API error: ${response.statusCode} - ${response.body}');
            }
          } catch (e) {
            print('⚠️ Groq API call failed on model $currentModel: $e');
          }
        }

        // Check if local Ollama is available as backup on Groq failure
        if (await _isOllamaAvailable()) {
          print(
              '🔄 [HYBRID BACKUP] Groq content generation failed. Automatically switching to local Ollama fallback...');
          final backupText = await _executeOllamaRequest(prompt, temperature);
          if (backupText != null) return backupText;
        }

        throw Exception('All Groq API model attempts failed.');
      }

      // ── GEMINI PROVIDER ROAD ──
      final requestBody = {
        'contents': [
          {
            'parts': [
              {'text': prompt}
            ]
          }
        ],
        'generationConfig': {
          'temperature': temperature,
          'maxOutputTokens': maxTokens,
          'topP': 0.8,
          'topK': 40,
        }
      };

      final response = await sendGeminiRequest(requestBody);

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);
        final candidates = jsonResponse['candidates'] as List?;

        if (candidates != null && candidates.isNotEmpty) {
          final content = candidates[0]['content'];
          final parts = content['parts'] as List?;

          if (parts != null && parts.isNotEmpty) {
            return parts[0]['text'] as String;
          }
        }

        throw Exception('No content generated');
      } else {
        throw Exception(
            'Gemini API error: ${response.statusCode} - ${response.body}');
      }
    } catch (error) {
      String provName = 'Gemini';
      if (AIConfig.activeProvider == AIProvider.ollama) provName = 'Ollama';
      if (AIConfig.activeProvider == AIProvider.groq) provName = 'Groq';
      throw Exception('Failed to generate content with $provName: $error');
    }
  }

  /// Generate structured JSON response for recommendations
  Future<Map<String, dynamic>> generateStructuredRecommendation({
    required String prompt,
    required String schema,
  }) async {
    try {
      final enhancedPrompt = '''
$prompt

Please respond with a valid JSON object that matches this schema:
$schema

CRITICAL REQUIREMENTS:
- Respond ONLY with valid JSON
- Use only double quotes for strings
- No trailing commas
- No unescaped quotes in string values
- No markdown formatting or code blocks
- Ensure all numeric values are valid numbers
- Ensure all string values are properly quoted
''';

      final response = await generateContent(
        prompt: enhancedPrompt,
        temperature: 0.1, // Minimal temperature for factual accuracy
        maxTokens: 9000,
      );

      return _parseJsonResponse(response);
    } catch (error) {
      debugPrint(
          'JSON parsing error in generateStructuredRecommendation: $error');
      throw Exception('Failed to generate structured recommendation: $error');
    }
  }

  /// Parse JSON response with multiple fallback strategies
  Map<String, dynamic> _parseJsonResponse(String response) {
    String cleanedResponse = response.trim();

    // Strategy 1: Remove markdown formatting
    cleanedResponse = _removeMarkdownFormatting(cleanedResponse);

    // Strategy 2: Try direct parsing
    try {
      return jsonDecode(cleanedResponse) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('Direct JSON parsing failed: $e');
    }

    // Strategy 3: Extract JSON boundaries and try again
    try {
      final jsonString = _extractJsonBoundaries(cleanedResponse);
      return jsonDecode(jsonString) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('JSON boundary extraction failed: $e');
    }

    // Strategy 4: Fix common JSON issues and try again
    try {
      final fixedJson = _fixCommonJsonIssues(cleanedResponse);
      return jsonDecode(fixedJson) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('JSON fixing failed: $e');
    }

    // Strategy 5: Try to extract and fix from boundaries
    try {
      final extractedJson = _extractJsonBoundaries(cleanedResponse);
      final fixedJson = _fixCommonJsonIssues(extractedJson);
      return jsonDecode(fixedJson) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('Combined extraction and fixing failed: $e');
    }

    // Strategy 6: Last resort - try regex to extract JSON structure
    try {
      final regexJson = _extractJsonWithRegex(cleanedResponse);
      return jsonDecode(regexJson) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('Regex JSON extraction failed: $e');
    }

    throw Exception(
        'Failed to parse JSON response after all strategies: $cleanedResponse');
  }

  /// Remove markdown formatting from response
  String _removeMarkdownFormatting(String response) {
    String cleaned = response;

    // Remove code blocks
    cleaned = cleaned.replaceAll(RegExp(r'```json\s*'), '');
    cleaned = cleaned.replaceAll(RegExp(r'```\s*'), '');

    // Remove any text before first { or [
    final jsonStart = cleaned.indexOf(RegExp(r'[{\[]'));
    if (jsonStart > 0) {
      cleaned = cleaned.substring(jsonStart);
    }

    return cleaned.trim();
  }

  /// Extract JSON within boundaries
  String _extractJsonBoundaries(String response) {
    final jsonStart = response.indexOf('{');
    final jsonEnd = response.lastIndexOf('}');

    if (jsonStart != -1 && jsonEnd != -1 && jsonEnd > jsonStart) {
      return response.substring(jsonStart, jsonEnd + 1);
    }

    // Try with array boundaries
    final arrayStart = response.indexOf('[');
    final arrayEnd = response.lastIndexOf(']');

    if (arrayStart != -1 && arrayEnd != -1 && arrayEnd > arrayStart) {
      return response.substring(arrayStart, arrayEnd + 1);
    }

    return response;
  }

  /// Extract JSON using regex patterns
  String _extractJsonWithRegex(String response) {
    // Try to find JSON object pattern
    final objectPattern =
        RegExp(r'\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}', dotAll: true);
    final objectMatch = objectPattern.firstMatch(response);

    if (objectMatch != null) {
      return objectMatch.group(0)!;
    }

    // Try to find JSON array pattern
    final arrayPattern =
        RegExp(r'\[[^\[\]]*(?:\[[^\[\]]*\][^\[\]]*)*\]', dotAll: true);
    final arrayMatch = arrayPattern.firstMatch(response);

    if (arrayMatch != null) {
      return arrayMatch.group(0)!;
    }

    return response;
  }

  /// Fix common JSON formatting issues
  String _fixCommonJsonIssues(String jsonString) {
    String fixed = jsonString.trim();

    try {
      // First, try basic cleanup
      // Remove trailing commas before closing brackets/braces
      fixed = fixed.replaceAll(RegExp(r',(\s*[}\]])'), r'$1');

      // Remove any text before the first { or [
      final jsonStart = fixed.indexOf(RegExp(r'[{\[]'));
      if (jsonStart > 0) {
        fixed = fixed.substring(jsonStart);
      }

      // Remove any text after the last } or ]
      final jsonEnd = fixed.lastIndexOf(RegExp(r'[}\]]'));
      if (jsonEnd != -1 && jsonEnd < fixed.length - 1) {
        fixed = fixed.substring(0, jsonEnd + 1);
      }

      // Fix common quote issues in string values
      // Replace smart quotes with regular quotes
      fixed = fixed.replaceAll('"', '"').replaceAll('"', '"');
      fixed = fixed.replaceAll(''', "'").replaceAll(''', "'");

      // Fix newlines and special characters in strings
      fixed = fixed.replaceAll('\n', '\\n');
      fixed = fixed.replaceAll('\r', '\\r');
      fixed = fixed.replaceAll('\t', '\\t');

      // Remove control characters that can break JSON
      fixed = fixed.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '');

      // Fix incomplete strings (basic attempt)
      fixed =
          fixed.replaceAll(RegExp(r':\s*"([^"]*)"([^,}\]]*)"'), r': "$1$2"');

      // Ensure proper spacing around colons and commas
      fixed = fixed.replaceAll(RegExp(r'\s*:\s*'), ': ');
      fixed = fixed.replaceAll(RegExp(r'\s*,\s*(?![}\]])'), ', ');

      return fixed;
    } catch (error) {
      debugPrint('Error in JSON fixing: $error');
      return jsonString; // Return original if fixing fails
    }
  }

  /// Generate credit card recommendations based on spending patterns
  Future<List<Map<String, dynamic>>> generateCardRecommendations({
    required Map<String, dynamic> userProfile,
    required List<Map<String, dynamic>> spendingData,
    required List<Map<String, dynamic>> availableCards,
    int limit = 5,
  }) async {
    final callLogger = GeminiCallLogService();
    final stopwatch = Stopwatch()..start();
    final provider = _activeProviderName();
    try {
      final prompt = '''
You are an expert credit card advisor in India. Based on the user's profile and spending patterns, recommend the best credit cards from the available options.

User Profile:
${jsonEncode(userProfile)}

Spending Patterns (last 6 months):
${jsonEncode(spendingData)}

Available Credit Cards:
${jsonEncode(availableCards)}

Please analyze the spending patterns and recommend the top $limit credit cards that would maximize rewards and benefits for this user. Consider:
1. Spending categories and amounts
2. Annual income and credit score
3. Card annual fees vs benefits
4. Reward rates for user's top spending categories
5. Welcome bonuses and special offers

For each recommendation, provide:
- Card ID and name
- Reason for recommendation
- Expected annual value/savings
- Key benefits relevant to user
- Confidence score (0-1)
''';

      const schema = '''
{
  "recommendations": [
    {
      "cardId": "string",
      "cardName": "string",
      "bankName": "string",
      "reason": "string",
      "expectedAnnualValue": number,
      "keyBenefits": ["string"],
      "confidenceScore": number,
      "matchedCategories": ["string"]
    }
  ]
}
''';

      final result = await generateStructuredRecommendation(
        prompt: prompt,
        schema: schema,
      );

      final recommendations =
          List<Map<String, dynamic>>.from(result['recommendations'] ?? []);

      stopwatch.stop();
      unawaited(callLogger.logRecommendationCall(
        provider: provider,
        durationMs: stopwatch.elapsedMilliseconds,
        userProfile: userProfile,
        spendingData: spendingData,
        result: recommendations,
      ));

      return recommendations;
    } catch (error) {
      stopwatch.stop();
      unawaited(callLogger.logRecommendationCall(
        provider: provider,
        durationMs: stopwatch.elapsedMilliseconds,
        userProfile: userProfile,
        spendingData: spendingData,
        result: const [],
        errorMessage: error.toString(),
      ));
      throw Exception('Failed to generate card recommendations: $error');
    }
  }

  /// Generate spending optimization suggestions
  Future<List<Map<String, dynamic>>> generateSpendingOptimizations({
    required Map<String, dynamic> userProfile,
    required List<Map<String, dynamic>> transactions,
    required List<Map<String, dynamic>> userCards,
  }) async {
    final callLogger = GeminiCallLogService();
    final stopwatch = Stopwatch()..start();
    final provider = _activeProviderName();
    try {
      final prompt = '''
You are a financial advisor specializing in credit card rewards optimization in India. Analyze the user's transactions and current cards to identify opportunities for better rewards.

User Profile:
${jsonEncode(userProfile)}

Recent Transactions:
${jsonEncode(transactions)}

User's Current Cards:
${jsonEncode(userCards)}

Identify specific opportunities where the user can optimize their spending to earn more rewards. Consider:
1. Using different cards for different categories
2. Meeting minimum spend requirements for bonuses
3. Taking advantage of rotating categories
4. Maximizing category-specific rewards
5. Avoiding high-fee cards for low spending

For each optimization, provide:
- Category of spending
- Current estimated rewards
- Optimized rewards potential
- Specific actionable recommendation
- Monthly/annual savings estimate
''';

      const schema = '''
{
  "optimizations": [
    {
      "category": "string",
      "currentMonthlySpending": 0,
      "currentRewardRate": 0.0,
      "optimizedRewardRate": 0.0,
      "recommendation": "string",
      "potentialMonthlySavings": 0,
      "actionRequired": "string",
      "cardToUse": "string"
    }
  ]
}
''';

      final result = await generateStructuredRecommendation(
        prompt: prompt,
        schema: schema,
      );

      final optimizations = result['optimizations'] as List?;

      if (optimizations == null || optimizations.isEmpty) {
        debugPrint('AI returned null or empty optimizations');
        final mocks = _getMockOptimizations();
        stopwatch.stop();
        unawaited(callLogger.logOptimizationCall(
          provider: provider,
          durationMs: stopwatch.elapsedMilliseconds,
          transactionCount: transactions.length,
          cardCount: userCards.length,
          result: mocks,
          usedMockFallback: true,
        ));
        return mocks;
      }

      final typed = List<Map<String, dynamic>>.from(optimizations);
      stopwatch.stop();
      unawaited(callLogger.logOptimizationCall(
        provider: provider,
        durationMs: stopwatch.elapsedMilliseconds,
        transactionCount: transactions.length,
        cardCount: userCards.length,
        result: typed,
      ));
      return typed;
    } catch (error) {
      debugPrint('Failed to generate spending optimizations with AI: $error');
      final mocks = _getMockOptimizations();
      stopwatch.stop();
      unawaited(callLogger.logOptimizationCall(
        provider: provider,
        durationMs: stopwatch.elapsedMilliseconds,
        transactionCount: transactions.length,
        cardCount: userCards.length,
        result: mocks,
        usedMockFallback: true,
        errorMessage: error.toString(),
      ));
      return mocks;
    }
  }

  /// Get mock optimizations as fallback
  List<Map<String, dynamic>> _getMockOptimizations() {
    return [
      {
        "category": "Dining",
        "currentMonthlySpending": 5000,
        "currentRewardRate": 1.0,
        "optimizedRewardRate": 5.0,
        "recommendation":
            "Use your dining-focused credit card for restaurant purchases to earn 5x rewards instead of 1x",
        "potentialMonthlySavings": 200,
        "actionRequired": "Switch to dining rewards card",
        "cardToUse": "Dining Rewards Card"
      },
      {
        "category": "Groceries",
        "currentMonthlySpending": 3000,
        "currentRewardRate": 1.0,
        "optimizedRewardRate": 4.0,
        "recommendation":
            "Use grocery category card for supermarket purchases to maximize cashback",
        "potentialMonthlySavings": 90,
        "actionRequired": "Use grocery rewards card",
        "cardToUse": "Grocery Cashback Card"
      },
      {
        "category": "Fuel",
        "currentMonthlySpending": 2000,
        "currentRewardRate": 1.0,
        "optimizedRewardRate": 3.5,
        "recommendation":
            "Switch to fuel-specific card for petrol purchases to earn higher rewards",
        "potentialMonthlySavings": 50,
        "actionRequired": "Use fuel rewards card",
        "cardToUse": "Fuel Rewards Card"
      }
    ];
  }

  /// Analyze spending patterns and provide insights
  Future<Map<String, dynamic>> analyzeSpendingPatterns({
    required List<Map<String, dynamic>> transactions,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      final prompt = '''
You are a financial data analyst. Analyze the provided transaction data and generate insights about spending patterns.

Transaction Data (${startDate.toString()} to ${endDate.toString()}):
${jsonEncode(transactions)}

Provide comprehensive analysis including:
1. Spending trends by category
2. Seasonal patterns
3. Unusual spending behaviors
4. Opportunities for savings
5. Budget recommendations
6. Financial health indicators

Generate actionable insights that can help the user make better financial decisions.
''';

      const schema = '''
{
  "totalSpending": number,
  "topCategories": [
    {
      "category": "string",
      "amount": number,
      "percentage": number
    }
  ],
  "trends": [
    {
      "month": "string",
      "amount": number,
      "change": number
    }
  ],
  "insights": [
    {
      "type": "string",
      "title": "string",
      "description": "string",
      "impact": "string",
      "actionable": "string"
    }
  ],
  "budgetRecommendations": [
    {
      "category": "string",
      "currentSpending": number,
      "recommendedBudget": number,
      "reasoning": "string"
    }
  ]
}
''';

      return await generateStructuredRecommendation(
        prompt: prompt,
        schema: schema,
      );
    } catch (error) {
      throw Exception('Failed to analyze spending patterns: $error');
    }
  }

  /// Get the best card recommendation for a specific transaction
  Future<Map<String, dynamic>> getBestCardForTransaction({
    required Map<String, dynamic> userProfile,
    required Map<String, dynamic> transactionDetails,
    required List<Map<String, dynamic>> userCards,
    required List<Map<String, dynamic>> availableCards,
  }) async {
    try {
      final prompt = '''
You are an expert credit card advisor in India. A user is about to make a transaction and wants to know which card to use for maximum rewards.

User Profile:
${jsonEncode(userProfile)}

Transaction Details:
${jsonEncode(transactionDetails)}

User's Current Cards:
${jsonEncode(userCards)}

Available Cards in Market:
${jsonEncode(availableCards)}

Analyze this specific transaction and recommend:
1. The best card from user's current cards (if any)
2. The best overall card in the market for this transaction
3. Expected rewards/cashback for each option
4. Potential savings by using the optimal card
5. Clear explanation for the recommendation

Consider:
- Merchant category and reward rates
- Transaction amount and any caps
- Annual fees vs rewards
- Special promotions or bonus categories
- Historical spending patterns
''';

      const schema = '''
{
  "bestUserCardId": "string",
  "bestUserCardName": "string",
  "estimatedUserReward": number,
  "bestOverallCardId": "string", 
  "bestOverallCardName": "string",
  "estimatedOverallReward": number,
  "potentialSavings": number,
  "explanation": "string",
  "rewardBreakdown": {
    "baseRate": number,
    "categoryBonus": number,
    "totalRate": number
  },
  "recommendations": {
    "immediate": "string",
    "longTerm": "string"
  }
}
''';

      return await generateStructuredRecommendation(
        prompt: prompt,
        schema: schema,
      );
    } catch (error) {
      throw Exception('Failed to recommend a card for transaction: $error');
    }
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

  static Future<String?> _executeOllamaRequest(
      String prompt, double temp) async {
    try {
      final ollamaReq = {
        'model': AIConfig.ollamaModel,
        'prompt': prompt,
        'stream': false,
        'options': {
          'temperature': temp,
        }
      };

      final targetUrl = '${AIConfig.ollamaUrl}/api/generate';
      print(
          '🤖 Ollama API: Sending fallback request to $targetUrl with model: ${AIConfig.ollamaModel}');

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
        final text = jsonResponse['response'] as String?;
        if (text != null && text.isNotEmpty) {
          return text;
        }
      }
    } catch (e) {
      print('❌ Ollama fallback call failed: $e');
    }
    return null;
  }

  /// Returns a human-readable name for the currently active AI provider.
  String _activeProviderName() {
    switch (AIConfig.activeProvider) {
      case AIProvider.ollama:
        return 'ollama';
      case AIProvider.groq:
        return 'groq';
      default:
        return 'gemini';
    }
  }
}
