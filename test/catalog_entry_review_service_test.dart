import 'package:cardcompass/core/services/catalog_entry_review_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CatalogEntryReviewService', () {
    test('listPendingRequests returns parsed rows from edge function', () async {
      final service = CatalogEntryReviewService(
        invokeAdminAction: (action, {stagingId}) async {
          expect(action, CatalogEntryAdminAction.list);
          return {
            'requests': [
              {
                'id': 'staging-1',
                'source_url': 'https://bank.example/card',
                'bank_name': 'Example Bank',
                'card_name': 'Platinum',
                'requested_by': 'user-1',
                'created_at': '2026-07-14T00:00:00Z',
              },
            ],
          };
        },
      );

      final requests = await service.listPendingRequests();
      expect(requests, hasLength(1));
      expect(requests.first.id, 'staging-1');
      expect(requests.first.bankName, 'Example Bank');
      expect(requests.first.cardName, 'Platinum');
    });

    test('approveRequest returns card id and metadata', () async {
      final service = CatalogEntryReviewService(
        invokeAdminAction: (action, {stagingId}) async {
          expect(action, CatalogEntryAdminAction.approve);
          expect(stagingId, 'staging-1');
          return {
            'success': true,
            'card_id': 'card-99',
            'bank_name': 'Example Bank',
            'card_name': 'Platinum',
            'source_url': 'https://bank.example/card',
          };
        },
      );

      final result = await service.approveRequest('staging-1');
      expect(result.success, isTrue);
      expect(result.cardId, 'card-99');
      expect(result.bankName, 'Example Bank');
    });

    test('rejectRequest surfaces edge function errors', () async {
      final service = CatalogEntryReviewService(
        invokeAdminAction: (action, {stagingId}) async {
          expect(action, CatalogEntryAdminAction.reject);
          return {'success': false, 'error': 'Already processed'};
        },
      );

      final result = await service.rejectRequest('staging-1');
      expect(result.success, isFalse);
      expect(result.error, 'Already processed');
    });
  });
}
