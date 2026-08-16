import 'package:cardcompass/core/services/pdf_password_detection_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final service = PdfPasswordDetectionService();

  test(
    'returns the issuer password-format sentence without surrounding body',
    () {
      const body =
          'Dear customer. Your statement is attached. '
          'Your password is the first four letters of your name followed by '
          'your date of birth in DDMM format. Please do not reply to this email.';

      expect(
        service.extractPasswordInstruction(body),
        'Your password is the first four letters of your name followed by '
        'your date of birth in DDMM format.',
      );
    },
  );

  test('does not expose an explicit password value as a display hint', () {
    const body = 'The password is PRIVATE123. Keep it confidential.';

    expect(service.extractPasswordInstruction(body), isNull);
  });

  test('returns null for generic password-protected boilerplate', () {
    const body = 'The attached statement is password protected.';

    expect(service.extractPasswordInstruction(body), isNull);
  });

  test('accepts issuer instructions phrased as how to open the PDF', () {
    const body =
        'Your statement is password protected. '
        'To open the PDF, use the first four letters of your name followed '
        'by your date of birth in DDMM format.';

    expect(
      service.extractPasswordInstruction(body),
      'To open the PDF, use the first four letters of your name followed '
      'by your date of birth in DDMM format.',
    );
  });

  test('keeps a password sentence with its following format instruction', () {
    const body =
        'The attached PDF is protected by a password. '
        'Use your date of birth in DDMM format followed by the last four '
        'digits of your card number. Contact the bank for support.';

    expect(
      service.extractPasswordInstruction(body),
      'The attached PDF is protected by a password. '
      'Use your date of birth in DDMM format followed by the last four '
      'digits of your card number.',
    );
  });

  test(
    'uses a standalone issuer sentence containing a strong format token',
    () {
      const body =
          'Statements are password protected. Security information. '
          'For your protection, do not share personal details. '
          'Enter your date of birth in DDMM followed by the last four digits '
          'of your card number. Never share your OTP.';

      expect(
        service.extractPasswordInstruction(body),
        'Enter your date of birth in DDMM followed by the last four digits '
        'of your card number.',
      );
    },
  );

  test('removes issuer examples after the useful password rule', () {
    const body =
        'Your password is a combination of your date of birth (in DDMMYY '
        'format) followed by the last 6 digits of the primary credit card '
        'number • For example: if your card number is 5120 0000 0000 4200, '
        'use 020670004200.';

    expect(
      service.extractPasswordInstruction(body),
      'Your password is a combination of your date of birth (in DDMMYY '
      'format) followed by the last 6 digits of the primary credit card '
      'number',
    );
  });
}
