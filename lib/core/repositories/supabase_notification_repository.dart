import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cardcompass/shared/models/notification.dart';

/// Repository for managing notifications in Supabase
class SupabaseNotificationRepository {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Create a new notification
  Future<AppNotification> createNotification(AppNotification notification) async {
    try {
      final response = await _supabase
          .from('notifications')
          .insert(notification.toJson())
          .select()
          .single();

      return AppNotification.fromJson(response);
    } catch (e) {
      throw Exception('Failed to create notification: $e');
    }
  }

  /// Get notifications for a user
  Future<List<AppNotification>> getUserNotifications(
    String userId, {
    bool? isRead,
    String? type,
    int? limit = 50,
  }) async {
    try {
      var queryBuilder = _supabase
          .from('notifications')
          .select()
          .eq('user_id', userId);

      if (isRead != null) {
        queryBuilder = queryBuilder.eq('is_read', isRead);
      }

      if (type != null) {
        queryBuilder = queryBuilder.eq('type', type);
      }

      var transformBuilder = queryBuilder.order('created_at', ascending: false);

      if (limit != null) {
        transformBuilder = transformBuilder.limit(limit);
      }

      final response = await transformBuilder;

      return (response as List)
          .map((json) => AppNotification.fromJson(json))
          .toList();
    } catch (e) {
      throw Exception('Failed to fetch notifications: $e');
    }
  }

  /// Mark notification as read
  Future<AppNotification> markAsRead(String notificationId) async {
    try {
      final response = await _supabase
          .from('notifications')
          .update({
            'is_read': true,
            'read_at': DateTime.now().toIso8601String(),
          })
          .eq('id', notificationId)
          .select()
          .single();

      return AppNotification.fromJson(response);
    } catch (e) {
      throw Exception('Failed to mark notification as read: $e');
    }
  }

  /// Mark all notifications as read for a user
  Future<void> markAllAsRead(String userId) async {
    try {
      await _supabase
          .from('notifications')
          .update({
            'is_read': true,
            'read_at': DateTime.now().toIso8601String(),
          })
          .eq('user_id', userId)
          .eq('is_read', false);
    } catch (e) {
      throw Exception('Failed to mark all notifications as read: $e');
    }
  }

  /// Delete a notification
  Future<void> deleteNotification(String notificationId) async {
    try {
      await _supabase
          .from('notifications')
          .delete()
          .eq('id', notificationId);
    } catch (e) {
      throw Exception('Failed to delete notification: $e');
    }
  }
  /// Get unread notification count
  Future<int> getUnreadCount(String userId) async {
    try {
      final response = await _supabase
          .from('notifications')
          .select('id')
          .eq('user_id', userId)
          .eq('is_read', false);

      return (response as List).length;
    } catch (e) {
      throw Exception('Failed to get unread count: $e');
    }
  }

  /// Get notification preferences
  Future<NotificationPreferences> getNotificationPreferences(String userId) async {
    try {
      final response = await _supabase
          .from('notification_preferences')
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      if (response == null) {
        // Create default preferences
        return await createDefaultPreferences(userId);
      }

      return NotificationPreferences.fromJson(response);
    } catch (e) {
      throw Exception('Failed to get notification preferences: $e');
    }
  }

  /// Create default notification preferences
  Future<NotificationPreferences> createDefaultPreferences(String userId) async {
    try {
      final defaultPrefs = NotificationPreferences(
        userId: userId,
        updatedAt: DateTime.now(),
      );

      final response = await _supabase
          .from('notification_preferences')
          .insert(defaultPrefs.toJson())
          .select()
          .single();

      return NotificationPreferences.fromJson(response);
    } catch (e) {
      throw Exception('Failed to create default preferences: $e');
    }
  }

  /// Update notification preferences
  Future<NotificationPreferences> updateNotificationPreferences(
    NotificationPreferences preferences,
  ) async {
    try {
      final response = await _supabase
          .from('notification_preferences')
          .upsert(preferences.copyWith(updatedAt: DateTime.now()).toJson())
          .select()
          .single();

      return NotificationPreferences.fromJson(response);
    } catch (e) {
      throw Exception('Failed to update notification preferences: $e');
    }
  }

  /// Get scheduled notifications
  Future<List<AppNotification>> getScheduledNotifications() async {
    try {
      final response = await _supabase
          .from('notifications')
          .select()
          .not('scheduled_for', 'is', null)
          .lte('scheduled_for', DateTime.now().toIso8601String())
          .eq('is_read', false);

      return (response as List)
          .map((json) => AppNotification.fromJson(json))
          .toList();
    } catch (e) {
      throw Exception('Failed to get scheduled notifications: $e');
    }
  }

  /// Create benefit alert notification
  Future<AppNotification> createBenefitAlert({
    required String userId,
    required String title,
    required String message,
    String? benefitId,
    String? cardId,
    double? savingsAmount,
  }) async {
    final notification = AppNotification(
      id: '', // Will be generated by database
      userId: userId,
      type: 'benefit_alert',
      title: title,
      message: message,
      priority: 'medium',
      isActionable: true,
      actionType: 'view_benefit',
      actionData: benefitId,
      data: {
        if (benefitId != null) 'benefit_id': benefitId,
        if (cardId != null) 'card_id': cardId,
        if (savingsAmount != null) 'savings_amount': savingsAmount,
      },
      createdAt: DateTime.now(),
    );

    return await createNotification(notification);
  }

  /// Create card recommendation notification
  Future<AppNotification> createCardRecommendation({
    required String userId,
    required String title,
    required String message,
    required String cardId,
    required double potentialSavings,
  }) async {
    final notification = AppNotification(
      id: '', // Will be generated by database
      userId: userId,
      type: 'card_recommendation',
      title: title,
      message: message,
      priority: 'high',
      isActionable: true,
      actionType: 'view_card',
      actionData: cardId,
      data: {
        'card_id': cardId,
        'potential_savings': potentialSavings,
      },
      createdAt: DateTime.now(),
    );

    return await createNotification(notification);
  }

  /// Create spending insight notification
  Future<AppNotification> createSpendingInsight({
    required String userId,
    required String title,
    required String message,
    String? category,
    double? amount,
  }) async {
    final notification = AppNotification(
      id: '', // Will be generated by database
      userId: userId,
      type: 'spending_insight',
      title: title,
      message: message,
      priority: 'low',
      isActionable: true,
      actionType: 'view_analytics',
      data: {
        if (category != null) 'category': category,
        if (amount != null) 'amount': amount,
      },
      createdAt: DateTime.now(),
    );

    return await createNotification(notification);
  }
}
