import 'package:flutter_test/flutter_test.dart';
import 'package:cardcompass/core/config/ai_config.dart';

void main() {
  final models = AIConfig.geminiModelFallbackChain;

  group('Gemini Model Fallback Tests', () {
    setUp(() {
      // Reset to primary model before each test
      AIConfig.resetToPrimaryModel();
    });

    test('Initial state should use primary model', () {
      print('\n🧪 Test: Initial state');
      print('=' * 60);

      expect(AIConfig.geminiModel, equals(models.first));

      final stats = AIConfig.getModelStats();
      print('Current model: ${stats['currentModel']}');
      print('Current index: ${stats['currentModelIndex']}');
      print('Total models: ${stats['totalModels']}');
      print('Remaining fallbacks: ${stats['remainingFallbacks']}');

      expect(stats['currentModelIndex'], equals(0));
      expect(stats['remainingFallbacks'], equals(models.length - 1));

      print('✅ Primary model verified');
      print('=' * 60);
    });

    test('Should switch to fallback model on rate limit', () {
      print('\n🧪 Test: Fallback model switching');
      print('=' * 60);

      print('Starting model: ${AIConfig.geminiModel}');
      expect(AIConfig.geminiModel, equals(models[0]));

      // Simulate rate limit hit - switch to first fallback
      print('\n⚠️  Simulating rate limit on gemini-2.5-flash...');
      final switched1 = AIConfig.switchToFallbackModel();
      expect(switched1, isTrue);
      expect(AIConfig.geminiModel, equals(models[1]));
      print('✅ Switched to: ${AIConfig.geminiModel}');

      // Simulate rate limit on second model
      print('\n⚠️  Simulating rate limit on gemini-2.0-flash...');
      final switched2 = AIConfig.switchToFallbackModel();
      expect(switched2, isTrue);
      expect(AIConfig.geminiModel, equals(models[2]));
      print('✅ Switched to: ${AIConfig.geminiModel}');

      // Continue through the remaining chain, then verify exhaustion.
      for (var i = 3; i < models.length; i++) {
        expect(AIConfig.switchToFallbackModel(), isTrue);
        expect(AIConfig.geminiModel, equals(models[i]));
      }
      final exhausted = AIConfig.switchToFallbackModel();
      expect(exhausted, isFalse);
      print('❌ No more fallbacks available (as expected)');

      final stats = AIConfig.getModelStats();
      print('\n📊 Final stats:');
      print('  Current model: ${stats['currentModel']}');
      print('  Remaining fallbacks: ${stats['remainingFallbacks']}');
      print('  Rate limit counts: ${stats['rateLimitCounts']}');

      print('\n✅ Fallback chain working correctly');
      print('=' * 60);
    });

    test('Should detect rate limit errors from status codes', () {
      print('\n🧪 Test: Rate limit error detection');
      print('=' * 60);

      // Test HTTP 429
      expect(AIConfig.isRateLimitError(429, null), isTrue);
      print('✅ HTTP 429 detected as rate limit');

      // Test HTTP 503
      expect(AIConfig.isRateLimitError(503, null), isTrue);
      print('✅ HTTP 503 detected as rate limit');

      // Test response body with quota message
      expect(AIConfig.isRateLimitError(200, '{"error": "quota exceeded"}'),
          isTrue);
      print('✅ Quota message in body detected');

      // Test response body with rate limit message
      expect(AIConfig.isRateLimitError(200, '{"error": "rate limit exceeded"}'),
          isTrue);
      print('✅ Rate limit message in body detected');

      // Test response body with overloaded message
      expect(
          AIConfig.isRateLimitError(
              503, '{"error": {"message": "The model is overloaded"}}'),
          isTrue);
      print('✅ Overloaded message detected');

      // Test non-rate-limit status
      expect(AIConfig.isRateLimitError(200, '{"status": "ok"}'), isFalse);
      expect(
          AIConfig.isRateLimitError(400, '{"error": "bad request"}'), isFalse);
      print('✅ Non-rate-limit errors not falsely detected');

      print('\n✅ Rate limit detection working correctly');
      print('=' * 60);
    });

    test('Should reset to primary model correctly', () {
      print('\n🧪 Test: Reset to primary model');
      print('=' * 60);

      // Switch to fallback
      AIConfig.switchToFallbackModel();
      print('Switched to: ${AIConfig.geminiModel}');
      expect(AIConfig.geminiModel, equals(models[1]));

      // Reset
      print('\n🔄 Resetting to primary model...');
      AIConfig.resetToPrimaryModel();
      expect(AIConfig.geminiModel, equals(models.first));
      print('✅ Reset to: ${AIConfig.geminiModel}');

      final stats = AIConfig.getModelStats();
      expect(stats['currentModelIndex'], equals(0));
      expect(stats['remainingFallbacks'], equals(models.length - 1));

      print('\n✅ Reset working correctly');
      print('=' * 60);
    });

    test('Should generate correct URLs for different models', () {
      print('\n🧪 Test: Model-specific URL generation');
      print('=' * 60);

      // Test primary model URL
      final primaryUrl = AIConfig.geminiGenerateUrl;
      expect(primaryUrl, contains(models.first));
      expect(primaryUrl, contains('/v1/'));
      expect(primaryUrl, contains(':generateContent'));
      print('Primary URL: $primaryUrl');

      // Test fallback model URLs
      final fallback1Url = AIConfig.getGeminiGenerateUrlForModel(models[1]);
      expect(fallback1Url, contains(models[1]));
      print('Fallback 1 URL: $fallback1Url');

      final fallback2Url = AIConfig.getGeminiGenerateUrlForModel(models[2]);
      expect(fallback2Url, contains(models[2]));
      print('Fallback 2 URL: $fallback2Url');

      print('\n✅ URL generation working correctly');
      print('=' * 60);
    });
  });

  group('Model Statistics Tests', () {
    setUp(() {
      AIConfig.resetStats(); // Reset both index and counts
    });

    test('Should track rate limit counts per model', () {
      print('\n🧪 Test: Rate limit count tracking');
      print('=' * 60);

      // Hit rate limit on primary
      AIConfig.switchToFallbackModel();
      AIConfig.switchToFallbackModel();

      final stats = AIConfig.getModelStats();
      print('📊 Model stats: ${stats['rateLimitCounts']}');

      expect(stats['rateLimitCounts'][models[0]], equals(1));
      expect(stats['rateLimitCounts'][models[1]], equals(1));

      print('✅ Rate limit counts tracked correctly');
      print('=' * 60);
    });

    test('Should provide complete statistics', () {
      print('\n🧪 Test: Complete statistics');
      print('=' * 60);

      AIConfig.switchToFallbackModel();
      final stats = AIConfig.getModelStats();

      print('📊 Complete stats:');
      print('  Current model: ${stats['currentModel']}');
      print('  Current index: ${stats['currentModelIndex']}');
      print('  Total models: ${stats['totalModels']}');
      print('  Remaining fallbacks: ${stats['remainingFallbacks']}');
      print('  Rate limit counts: ${stats['rateLimitCounts']}');

      expect(stats, containsPair('currentModel', models[1]));
      expect(stats, containsPair('currentModelIndex', 1));
      expect(stats, containsPair('totalModels', models.length));
      expect(stats, containsPair('remainingFallbacks', models.length - 2));
      expect(stats['rateLimitCounts'], isA<Map>());

      print('\n✅ Statistics complete and accurate');
      print('=' * 60);
    });
  });
}
