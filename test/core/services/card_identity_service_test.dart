import 'package:cardcompass/core/services/card_identity_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CardIdentityEvidence', () {
    test('keeps subject filename and PDF header evidence attributable', () {
      final evidence = CardIdentityEvidence.extract(
        issuer: 'IndusInd Bank',
        subject: 'Your IndusInd Bank Credit Card statement for Jul 2026',
        attachmentFilename: 'CC_STMT_202607.pdf',
        pdfHeader:
            'EAZYDINER INDUSIND BANK PLATINUM CREDIT CARD\nCard ending XX2451',
      );

      expect(evidence.subjectProduct, isNull);
      expect(evidence.filenameProduct, isNull);
      expect(evidence.pdfHeaderProduct, 'EazyDiner Platinum');
      expect(evidence.lastFour, '2451');
      expect(evidence.productSignals, ['EazyDiner Platinum']);
    });

    test('extracts known product variants from statement subjects', () {
      const cases = <String, String>{
        'Your Axis Bank Amex Privilege Credit Card Statement ending XX40':
            'Privilege',
        'Jul-2026 Statement for White Reserve Credit Card X0771':
            'White Reserve',
        'Your HDFC Bank - Tata Neu Infinity HDFC Bank Credit Card Statement':
            'Tata Neu Infinity',
      };

      for (final entry in cases.entries) {
        final evidence = CardIdentityEvidence.extract(
          issuer: entry.key.contains('Axis')
              ? 'Axis Bank'
              : entry.key.contains('HDFC')
              ? 'HDFC Bank'
              : 'Kotak Bank',
          subject: entry.key,
        );
        expect(evidence.subjectProduct, entry.value, reason: entry.key);
      }
    });

    test('extracts product from meaningful filenames but ignores opaque ones', () {
      expect(
        CardIdentityEvidence.extract(
          issuer: 'ICICI Bank',
          attachmentFilename:
              '4786XXXXXXXX3001_674596_Retail_AdaniOne_NORM.pdf',
        ).filenameProduct,
        'Adani One',
      );
      expect(
        CardIdentityEvidence.extract(
          issuer: 'ICICI Bank',
          attachmentFilename: '94XXXXXXXXXXX245.pdf',
        ).filenameProduct,
        isNull,
      );
    });

    test('stores only sanitized PDF evidence and a masked last four', () {
      final evidence = CardIdentityEvidence.extract(
        issuer: 'HSBC',
        pdfHeader:
            'Primary card number 5123 4567 8912 1759\nCustomer Jane Doe\nTravelOne Credit Card Statement',
      );
      final json = evidence.toSafeJson();

      expect(json['last_four'], '1759');
      expect(json['pdf_header_excerpt'], isNot(contains('5123 4567 8912')));
      expect(json['pdf_header_excerpt'], isNot(contains('Jane Doe')));
      expect(json.toString(), isNot(contains('5123456789121759')));
    });

    test('detects payment network separately from product identity', () {
      final evidence = CardIdentityEvidence.extract(
        issuer: 'Axis Bank',
        subject: 'Your Axis Bank Amex Privilege Credit Card Statement',
      );

      expect(evidence.subjectProduct, 'Privilege');
      expect(evidence.network, 'American Express');
    });
  });

  group('CardIdentityMatcher', () {
    const matcher = CardIdentityMatcher();

    test('prefers the most-specific unique product', () {
      final evidence = CardIdentityEvidence.extract(
        issuer: 'Kotak Bank',
        subject: 'Statement for White Reserve Credit Card',
      );
      final result = matcher.match(evidence, const [
        CardCatalogIdentity(id: 'white', issuer: 'Kotak Bank', name: 'White'),
        CardCatalogIdentity(
          id: 'reserve',
          issuer: 'Kotak Bank',
          name: 'White Reserve',
        ),
      ]);

      expect(result?.id, 'reserve');
    });

    test('matches a statement label through a catalog alias', () {
      final evidence = CardIdentityEvidence.extract(
        issuer: 'Axis Bank',
        subject: 'Your Axis Bank Amex Privilege Credit Card Statement',
      );
      final result = matcher.match(evidence, const [
        CardCatalogIdentity(
          id: 'privilege',
          issuer: 'Axis Bank',
          name: 'Privilege',
          aliases: ['Amex Privilege'],
        ),
      ]);

      expect(result?.id, 'privilege');
    });

    test('does not choose between tied normalized candidates', () {
      final evidence = CardIdentityEvidence.extract(
        issuer: 'Example Bank',
        subject: 'Your Example Bank Platinum Credit Card Statement',
      );
      final result = matcher.match(evidence, const [
        CardCatalogIdentity(
          id: 'one',
          issuer: 'Example Bank',
          name: 'Platinum',
        ),
        CardCatalogIdentity(
          id: 'two',
          issuer: 'Example Bank',
          name: 'Platinum',
        ),
      ]);

      expect(result, isNull);
    });

    test('never matches a product from another issuer', () {
      final evidence = CardIdentityEvidence.extract(
        issuer: 'Axis Bank',
        subject: 'Privilege Credit Card Statement',
      );
      final result = matcher.match(evidence, const [
        CardCatalogIdentity(
          id: 'other',
          issuer: 'Other Bank',
          name: 'Privilege',
        ),
      ]);

      expect(result, isNull);
    });
  });
}
