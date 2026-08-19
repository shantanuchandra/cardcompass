import '../card_data/card_data_models.dart';

enum AdminInboxSeverity { critical, high, normal }

enum InboxSource { cardIdentity, benefitEnrichment }

final class AdminInboxDestination {
  const AdminInboxDestination({
    required this.section,
    required this.lane,
    required this.targetId,
  });
  final String section;
  final CardReviewLane lane;
  final String targetId;

  factory AdminInboxDestination.fromJson(Map<String, dynamic> json) {
    final section = strictJsonString(json['section']);
    if (section != 'cardData') throw const FormatException('Invalid section');
    return AdminInboxDestination(
      section: section,
      lane: CardReviewLane.parse(json['lane']),
      targetId: strictJsonString(json['target_id']),
    );
  }
}

final class AdminInboxItem {
  const AdminInboxItem({
    required this.id,
    required this.type,
    required this.severity,
    required this.title,
    required this.explanation,
    required this.sourceStatus,
    required this.ageSeconds,
    required this.destination,
  });
  final String id;
  final String type;
  final AdminInboxSeverity severity;
  final String title;
  final String explanation;
  final String sourceStatus;
  final int ageSeconds;
  final AdminInboxDestination destination;

  factory AdminInboxItem.fromJson(Map<String, dynamic> json) {
    final severity = switch (json['severity']) {
      'critical' => AdminInboxSeverity.critical,
      'high' => AdminInboxSeverity.high,
      'normal' => AdminInboxSeverity.normal,
      _ => throw const FormatException('Invalid severity'),
    };
    final age = json['age_seconds'];
    if (age is! int || age < 0) throw const FormatException('Invalid age');
    return AdminInboxItem(
      id: strictJsonString(json['id']),
      type: strictJsonString(json['type']),
      severity: severity,
      title: strictJsonString(json['title']),
      explanation: strictJsonString(json['explanation']),
      sourceStatus: strictJsonString(json['source_status']),
      ageSeconds: age,
      destination: AdminInboxDestination.fromJson(
        strictJsonMap(json['destination']),
      ),
    );
  }
}

final class InboxSnapshot {
  InboxSnapshot({
    required List<AdminInboxItem> items,
    required List<InboxSource> partialFailures,
    required this.refreshedAt,
  }) : items = List.unmodifiable(items),
       partialFailures = List.unmodifiable(partialFailures);
  final List<AdminInboxItem> items;
  final List<InboxSource> partialFailures;
  final DateTime refreshedAt;
}
