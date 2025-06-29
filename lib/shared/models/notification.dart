/// Model for app notifications
class AppNotification {
  final String id;
  final String userId;
  final String type; // 'benefit_alert', 'card_recommendation', 'spending_insight', 'payment_reminder'
  final String title;
  final String message;
  final String priority; // 'low', 'medium', 'high', 'urgent'
  final Map<String, dynamic>? data; // Additional data for the notification
  final bool isRead;
  final bool isActionable;
  final String? actionType; // 'view_benefit', 'apply_card', 'view_transaction', etc.
  final String? actionData; // JSON string with action-specific data
  final DateTime? scheduledFor; // For scheduled notifications
  final DateTime createdAt;
  final DateTime? readAt;

  const AppNotification({
    required this.id,
    required this.userId,
    required this.type,
    required this.title,
    required this.message,
    required this.priority,
    this.data,
    this.isRead = false,
    this.isActionable = false,
    this.actionType,
    this.actionData,
    this.scheduledFor,
    required this.createdAt,
    this.readAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      type: json['type'] as String,
      title: json['title'] as String,
      message: json['message'] as String,
      priority: json['priority'] as String,
      data: json['data'] as Map<String, dynamic>?,
      isRead: json['is_read'] as bool? ?? false,
      isActionable: json['is_actionable'] as bool? ?? false,
      actionType: json['action_type'] as String?,
      actionData: json['action_data'] as String?,
      scheduledFor: json['scheduled_for'] != null 
          ? DateTime.parse(json['scheduled_for'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      readAt: json['read_at'] != null 
          ? DateTime.parse(json['read_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'type': type,
      'title': title,
      'message': message,
      'priority': priority,
      'data': data,
      'is_read': isRead,
      'is_actionable': isActionable,
      'action_type': actionType,
      'action_data': actionData,
      'scheduled_for': scheduledFor?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'read_at': readAt?.toIso8601String(),
    };
  }

  AppNotification copyWith({
    String? id,
    String? userId,
    String? type,
    String? title,
    String? message,
    String? priority,
    Map<String, dynamic>? data,
    bool? isRead,
    bool? isActionable,
    String? actionType,
    String? actionData,
    DateTime? scheduledFor,
    DateTime? createdAt,
    DateTime? readAt,
  }) {
    return AppNotification(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      type: type ?? this.type,
      title: title ?? this.title,
      message: message ?? this.message,
      priority: priority ?? this.priority,
      data: data ?? this.data,
      isRead: isRead ?? this.isRead,
      isActionable: isActionable ?? this.isActionable,
      actionType: actionType ?? this.actionType,
      actionData: actionData ?? this.actionData,
      scheduledFor: scheduledFor ?? this.scheduledFor,
      createdAt: createdAt ?? this.createdAt,
      readAt: readAt ?? this.readAt,
    );
  }
}

/// Model for notification preferences
class NotificationPreferences {
  final String userId;
  final bool benefitAlerts;
  final bool cardRecommendations;
  final bool spendingInsights;
  final bool paymentReminders;
  final bool marketingOffers;
  final bool securityAlerts;
  final String emailFrequency; // 'instant', 'daily', 'weekly', 'never'
  final String pushFrequency; // 'instant', 'daily', 'weekly', 'never'
  final List<String> mutedCategories;
  final Map<String, bool> categoryPreferences;
  final DateTime updatedAt;

  const NotificationPreferences({
    required this.userId,
    this.benefitAlerts = true,
    this.cardRecommendations = true,
    this.spendingInsights = true,
    this.paymentReminders = true,
    this.marketingOffers = false,
    this.securityAlerts = true,
    this.emailFrequency = 'daily',
    this.pushFrequency = 'instant',
    this.mutedCategories = const [],
    this.categoryPreferences = const {},
    required this.updatedAt,
  });

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) {
    return NotificationPreferences(
      userId: json['user_id'] as String,
      benefitAlerts: json['benefit_alerts'] as bool? ?? true,
      cardRecommendations: json['card_recommendations'] as bool? ?? true,
      spendingInsights: json['spending_insights'] as bool? ?? true,
      paymentReminders: json['payment_reminders'] as bool? ?? true,
      marketingOffers: json['marketing_offers'] as bool? ?? false,
      securityAlerts: json['security_alerts'] as bool? ?? true,
      emailFrequency: json['email_frequency'] as String? ?? 'daily',
      pushFrequency: json['push_frequency'] as String? ?? 'instant',
      mutedCategories: List<String>.from(json['muted_categories'] ?? []),
      categoryPreferences: Map<String, bool>.from(json['category_preferences'] ?? {}),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'benefit_alerts': benefitAlerts,
      'card_recommendations': cardRecommendations,
      'spending_insights': spendingInsights,
      'payment_reminders': paymentReminders,
      'marketing_offers': marketingOffers,
      'security_alerts': securityAlerts,
      'email_frequency': emailFrequency,
      'push_frequency': pushFrequency,
      'muted_categories': mutedCategories,
      'category_preferences': categoryPreferences,
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  NotificationPreferences copyWith({
    String? userId,
    bool? benefitAlerts,
    bool? cardRecommendations,
    bool? spendingInsights,
    bool? paymentReminders,
    bool? marketingOffers,
    bool? securityAlerts,
    String? emailFrequency,
    String? pushFrequency,
    List<String>? mutedCategories,
    Map<String, bool>? categoryPreferences,
    DateTime? updatedAt,
  }) {
    return NotificationPreferences(
      userId: userId ?? this.userId,
      benefitAlerts: benefitAlerts ?? this.benefitAlerts,
      cardRecommendations: cardRecommendations ?? this.cardRecommendations,
      spendingInsights: spendingInsights ?? this.spendingInsights,
      paymentReminders: paymentReminders ?? this.paymentReminders,
      marketingOffers: marketingOffers ?? this.marketingOffers,
      securityAlerts: securityAlerts ?? this.securityAlerts,
      emailFrequency: emailFrequency ?? this.emailFrequency,
      pushFrequency: pushFrequency ?? this.pushFrequency,
      mutedCategories: mutedCategories ?? this.mutedCategories,
      categoryPreferences: categoryPreferences ?? this.categoryPreferences,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
