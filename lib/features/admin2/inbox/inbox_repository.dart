import '../card_data/card_data_models.dart';
import '../data/admin_operator_repository.dart';
import 'inbox_models.dart';

final class InboxRepository {
  const InboxRepository(this._operator);
  final AdminOperatorRepository _operator;

  Future<InboxSnapshot> load() async {
    try {
      final json = await _operator.invoke('inbox-list');
      final items = strictJsonList(
        json['items'],
      ).map(strictJsonMap).map(AdminInboxItem.fromJson).toList();
      final failures = strictJsonList(json['partial_failures']).map((value) {
        return switch (value) {
          'card_identity' => InboxSource.cardIdentity,
          'benefit_enrichment' => InboxSource.benefitEnrichment,
          'system_operations' => InboxSource.systemOperations,
          'feedback' => InboxSource.feedback,
          _ => throw const FormatException('Invalid partial failure'),
        };
      }).toList();
      return InboxSnapshot(
        items: items,
        partialFailures: failures,
        refreshedAt: strictJsonDate(json['refreshed_at']),
      );
    } on FormatException {
      throw const AdminRequestFailed('request_failed');
    } on TypeError {
      throw const AdminRequestFailed('request_failed');
    }
  }
}
