import 'package:flutter_test/flutter_test.dart';
import 'package:cardcompass/core/services/enhanced_gmail_service.dart';

void main() {
  group('statement card variant detection', () {
    test('uses the ICICI PDF filename when the subject is generic', () {
      final variant = EnhancedGmailService.detectKnownCardVariant(
        emailSubject:
            'ICICI Bank Credit Card Statement for the period June 12 2026 to July 11 2026',
        attachmentName: '3769XXXXXXXX3003_777450_ICICI_Sapphiro_NORM.pdf',
      );

      expect(variant, 'Sapphiro');
    });

    test('prefers a specific variant in the subject', () {
      final variant = EnhancedGmailService.detectKnownCardVariant(
        emailSubject: 'Amazon Pay ICICI Bank Credit Card Statement',
        attachmentName: '4315XXXXXXXX6006_ICICI_Sapphiro.pdf',
      );

      expect(variant, 'Amazon Pay');
    });

    test('recognises ICICI Amazon in a PDF filename', () {
      final variant = EnhancedGmailService.detectKnownCardVariant(
        emailSubject: 'ICICI Bank Credit Card Statement',
        attachmentName: '4315XXXXXXXX6006_1343157_ICICI_Amazon_NORM.pdf',
      );

      expect(variant, 'Amazon Pay');
    });
  });
}
