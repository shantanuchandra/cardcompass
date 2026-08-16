import 'package:cardcompass/core/services/card_discovery_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('URL resolution parses resolved card identity', () {
    final result = CardUrlResolution.fromJson(const {
      'job_id': 'job-1',
      'status': 'resolved',
      'resolved_card_id': 'card-1',
      'reason_code': null,
      'retry_after': null,
    });

    expect(result.isResolved, isTrue);
    expect(result.requiresReview, isFalse);
    expect(result.resolvedCardId, 'card-1');
  });

  test('URL resolution exposes only safe reason messages', () {
    final review = CardUrlResolution.fromJson(const {
      'job_id': 'job-2',
      'status': 'review_required',
      'reason_code': 'issuer_mismatch',
    });
    final unknown = CardUrlResolution.fromJson(const {
      'job_id': 'job-3',
      'status': 'failed',
      'reason_code': 'raw database details',
    });

    expect(review.requiresReview, isTrue);
    expect(review.userMessage, contains('different bank'));
    expect(unknown.userMessage, 'Could not verify this card page. Try again.');
  });

  test('discovery metadata clears manual assignment and records the job', () {
    final metadata = metadataWithCardDiscovery(
      const {
        'attachmentId': 'attachment-1',
        'needsCardAssignment': true,
        'identityHints': {'last4': '2451'},
      },
      jobId: 'job-1',
      status: 'queued',
    );

    expect(metadata, {
      'attachmentId': 'attachment-1',
      'identityHints': {'last4': '2451'},
      'cardDiscoveryJobId': 'job-1',
      'cardDiscoveryStatus': 'queued',
    });
  });

  test('resolved discovery metadata removes transient discovery state', () {
    final metadata = metadataAfterCardDiscoveryResolved(const {
      'attachmentId': 'attachment-1',
      'cardDiscoveryJobId': 'job-1',
      'cardDiscoveryStatus': 'resolved',
      'identityHints': {'productName': 'Privilege'},
    });

    expect(metadata, {
      'attachmentId': 'attachment-1',
      'identityHints': {'productName': 'Privilege'},
    });
  });
}
