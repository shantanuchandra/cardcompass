import 'package:cardcompass/core/services/catalog_entry_staging_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CatalogEntryStagingPolicy', () {
    test('identifies pending catalog_entry rows with null card_id', () {
      expect(
        CatalogEntryStagingPolicy.isPendingCatalogEntry({
          'status': 'pending',
          'card_id': null,
          'extracted_data': {
            'request_type': 'catalog_entry',
            'bank_name': 'HDFC Bank',
            'card_name': 'Millennia',
          },
        }),
        isTrue,
      );
    });

    test('rejects benefit-extraction staging rows', () {
      expect(
        CatalogEntryStagingPolicy.isPendingCatalogEntry({
          'status': 'pending',
          'card_id': 'existing-card-id',
          'extracted_data': {'benefits': []},
        }),
        isFalse,
      );
    });

    test('parses bank and card name from extracted_data', () {
      final fields = CatalogEntryStagingPolicy.parseFields({
        'extracted_data': {
          'request_type': 'catalog_entry',
          'bank_name': '  Axis Bank ',
          'card_name': ' Flipkart ',
        },
        'source_url': 'https://www.axisbank.com/flipkart',
      });

      expect(fields.bankName, 'Axis Bank');
      expect(fields.cardName, 'Flipkart');
      expect(fields.sourceUrl, 'https://www.axisbank.com/flipkart');
    });

    test('canApprove requires pending catalog_entry with required fields', () {
      expect(
        CatalogEntryStagingPolicy.canApprove({
          'status': 'pending',
          'card_id': null,
          'extracted_data': {
            'request_type': 'catalog_entry',
            'bank_name': 'SBI',
            'card_name': 'Cashback',
          },
          'source_url': 'https://www.sbi.co.in/card',
        }),
        isTrue,
      );
      expect(
        CatalogEntryStagingPolicy.canApprove({
          'status': 'rejected',
          'card_id': null,
          'extracted_data': {
            'request_type': 'catalog_entry',
            'bank_name': 'SBI',
            'card_name': 'Cashback',
          },
          'source_url': 'https://www.sbi.co.in/card',
        }),
        isFalse,
      );
      expect(
        CatalogEntryStagingPolicy.canApprove({
          'status': 'pending',
          'card_id': null,
          'extracted_data': {
            'request_type': 'catalog_entry',
            'bank_name': '',
            'card_name': 'Cashback',
          },
          'source_url': 'https://www.sbi.co.in/card',
        }),
        isFalse,
      );
    });
  });
}
