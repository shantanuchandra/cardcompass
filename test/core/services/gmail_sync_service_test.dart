import 'package:cardcompass/core/services/gmail_sync_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis/gmail/v1.dart' as gmail;

gmail.MessagePart _pdfPart(String filename, {String? attachmentId}) {
  return gmail.MessagePart(
    mimeType: 'application/pdf',
    filename: filename,
    body: gmail.MessagePartBody(attachmentId: attachmentId ?? filename),
  );
}

void main() {
  final service = GmailSyncService('fake-token');

  group('GmailSyncService.findPdfAttachment', () {
    test('prefers the real statement PDF over an accompanying Terms & Conditions PDF', () {
      // Mirrors the actual MIME structure of an HSBC TravelOne statement
      // email: multipart/mixed with the T&C PDF ordered before the real,
      // password-protected statement PDF.
      final htmlBody = gmail.MessagePart(mimeType: 'text/html', filename: '');
      final termsAndConditions = _pdfPart('Most Important Terms & Conditions.pdf');
      final statement = _pdfPart('20260805.pdf');

      final result = service.findPdfAttachment([htmlBody, termsAndConditions, statement]);

      expect(result.found, true);
      expect(result.filename, '20260805.pdf');
      expect(result.attachmentId, '20260805.pdf');
    });

    test('returns the only PDF attachment when just one is present', () {
      final htmlBody = gmail.MessagePart(mimeType: 'text/html', filename: '');
      final statement = _pdfPart('4315XXXXXXXX6006_140741_Retail_Amazon_NORM.pdf');

      final result = service.findPdfAttachment([htmlBody, statement]);

      expect(result.found, true);
      expect(result.filename, '4315XXXXXXXX6006_140741_Retail_Amazon_NORM.pdf');
    });

    test('returns not found when there is no PDF attachment', () {
      final htmlBody = gmail.MessagePart(mimeType: 'text/html', filename: '');

      final result = service.findPdfAttachment([htmlBody]);

      expect(result.found, false);
      expect(result.attachmentId, null);
      expect(result.filename, null);
    });

    test('falls back to the first PDF when every candidate looks like an ancillary document', () {
      final termsAndConditions = _pdfPart('Terms and Conditions.pdf');
      final disclosure = _pdfPart('Key Fact Disclosure.pdf');

      final result = service.findPdfAttachment([termsAndConditions, disclosure]);

      expect(result.found, true);
      expect(result.filename, 'Terms and Conditions.pdf');
    });

    test('finds a PDF nested inside a sub-container part', () {
      final statement = _pdfPart('statement.pdf');
      final container = gmail.MessagePart(
        mimeType: 'multipart/related',
        parts: [statement],
      );

      final result = service.findPdfAttachment([container]);

      expect(result.found, true);
      expect(result.filename, 'statement.pdf');
    });
  });
}
