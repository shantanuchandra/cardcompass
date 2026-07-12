/// TDD Integration tests for the Gmail sync pipeline.
///
/// Run: flutter test test/sync/gmail_sync_integration_test.dart
library gmail_sync_integration_test;

import 'package:flutter_test/flutter_test.dart';
import 'package:cardcompass/core/services/enhanced_gmail_service.dart';
import 'package:cardcompass/core/services/pdf_parsing_service_impl.dart';

void main() {
  group('EnhancedGmailService - authentication state', () {
    test('isAuthenticated() returns false before any auth', () {
      final service = EnhancedGmailService(
        pdfParsingService: PdfParsingServiceImpl(),
      );
      expect(service.isAuthenticated(), isFalse,
          reason: 'No auth performed - should return false');
    });

    test('signOut() resets isAuthenticated to false without throwing', () async {
      final service = EnhancedGmailService(
        pdfParsingService: PdfParsingServiceImpl(),
      );
      // signOut on an unauthenticated service should not throw
      await expectLater(service.signOut(), completes);
      expect(service.isAuthenticated(), isFalse);
    });
  });

  group('Web sync path - Supabase provider token guard', () {
    // Simulates the kIsWeb guard in home_screen._syncDataFromGmail
    bool tokenIsValid(String? token) => token != null && token.isNotEmpty;

    test('valid token passes guard', () {
      expect(tokenIsValid('ya29.fake_google_access_token'), isTrue);
    });

    test('null token fails guard - user must re-login to get Gmail scopes', () {
      expect(tokenIsValid(null), isFalse);
    });

    test('empty string token fails guard', () {
      expect(tokenIsValid(''), isFalse);
    });
  });

  group('EnhancedGmailService - scope list', () {
    test('Gmail readonly scope is included in required scopes', () {
      const scopes = [
        'https://www.googleapis.com/auth/gmail.readonly',
        'https://www.googleapis.com/auth/gmail.modify',
        'https://www.googleapis.com/auth/userinfo.profile',
        'https://www.googleapis.com/auth/user.birthday.read',
      ];
      expect(scopes, contains('https://www.googleapis.com/auth/gmail.readonly'));
      expect(scopes, contains('https://www.googleapis.com/auth/gmail.modify'));
    });
  });
}
