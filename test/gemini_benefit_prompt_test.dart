import 'package:cardcompass/core/services/gemini_transaction_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('benefit prompt requires source evidence and forbids category filler',
      () {
    final prompt = GeminiTransactionParser.buildBenefitExtractionPrompt(
      'Airtel',
      'Axis Bank',
    ).toLowerCase();

    expect(prompt, contains('evidence_excerpt'));
    expect(prompt, contains('do not emit'));
    expect(prompt, contains('navigation'));
    expect(prompt, contains('savings account'));
    expect(prompt, contains('personal loan'));
    expect(prompt, contains('missing information'));
    expect(prompt, contains('must remain null'));
    expect(prompt, isNot(contains('extract all benefits')));
  });

  test('benefit generation requests complete JSON output', () {
    final config = GeminiTransactionParser.benefitGenerationConfig;

    expect(config['maxOutputTokens'], greaterThanOrEqualTo(8192));
    expect(config['temperature'], lessThanOrEqualTo(0.1));
  });
}
