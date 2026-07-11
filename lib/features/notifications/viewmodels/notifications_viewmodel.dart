import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:cardcompass/shared/models/notification.dart';
import 'package:cardcompass/core/repositories/supabase_notification_repository.dart';

/// Repository provider
final supabaseNotificationRepositoryProvider = Provider<SupabaseNotificationRepository>((ref) {
  return SupabaseNotificationRepository();
});

/// Provider for notifications view model
final notificationsViewModelProvider = StateNotifierProvider<NotificationsViewModel, NotificationsViewState>((ref) {
  return NotificationsViewModel(ref);
});

/// Notifications view state
class NotificationsViewState {
  final List<AppNotification> notifications;
  final List<AppNotification> benefitAlerts;
  final List<AppNotification> recommendations;
  final NotificationPreferences? preferences;
  final int unreadCount;
  final bool isLoading;
  final String? error;

  const NotificationsViewState({
    this.notifications = const [],
    this.benefitAlerts = const [],
    this.recommendations = const [],
    this.preferences,
    this.unreadCount = 0,
    this.isLoading = false,
    this.error,
  });

  NotificationsViewState copyWith({
    List<AppNotification>? notifications,
    List<AppNotification>? benefitAlerts,
    List<AppNotification>? recommendations,
    NotificationPreferences? preferences,
    int? unreadCount,
    bool? isLoading,
    String? error,
  }) {
    return NotificationsViewState(
      notifications: notifications ?? this.notifications,
      benefitAlerts: benefitAlerts ?? this.benefitAlerts,
      recommendations: recommendations ?? this.recommendations,
      preferences: preferences ?? this.preferences,
      unreadCount: unreadCount ?? this.unreadCount,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
    );
  }
}

/// Notifications view model
class NotificationsViewModel extends StateNotifier<NotificationsViewState> {
  final Ref _ref;
  late final SupabaseNotificationRepository _repository;

  NotificationsViewModel(this._ref) : super(const NotificationsViewState()) {
    _repository = _ref.read(supabaseNotificationRepositoryProvider);
  }

  /// Load all notifications for user
  Future<void> loadNotifications(String userId) async {
    state = state.copyWith(isLoading: true, error: null);
    
    try {
      // Load all notifications
      final allNotifications = await _repository.getUserNotifications(userId);
      
      // Filter by type
      final benefitAlerts = allNotifications.where((n) => n.type == 'benefit_alert').toList();
      final recommendations = allNotifications.where((n) => n.type == 'card_recommendation').toList();
      
      // Load unread count
      final unreadCount = await _repository.getUnreadCount(userId);
      
      // Load preferences
      final preferences = await _repository.getNotificationPreferences(userId);
      
      state = state.copyWith(
        notifications: allNotifications,
        benefitAlerts: benefitAlerts,
        recommendations: recommendations,
        unreadCount: unreadCount,
        preferences: preferences,
        isLoading: false,
      );
    } catch (e) {
      // Create mock notifications as fallback
      final mockNotifications = _createMockNotifications(userId);
      
      state = state.copyWith(
        notifications: mockNotifications,
        benefitAlerts: mockNotifications.where((n) => n.type == 'benefit_alert').toList(),
        recommendations: mockNotifications.where((n) => n.type == 'card_recommendation').toList(),
        unreadCount: mockNotifications.where((n) => !n.isRead).length,
        isLoading: false,
        error: 'Using mock data: ${e.toString()}',
      );
    }
  }

  /// Mark notification as read
  Future<void> markAsRead(String userId, String notificationId) async {
    try {
      await _repository.markAsRead(notificationId);
      
      // Update local state
      final updatedNotifications = state.notifications.map((n) {
        if (n.id == notificationId) {
          return n.copyWith(isRead: true, readAt: DateTime.now());
        }
        return n;
      }).toList();
      
      final newUnreadCount = updatedNotifications.where((n) => !n.isRead).length;
      
      state = state.copyWith(
        notifications: updatedNotifications,
        benefitAlerts: updatedNotifications.where((n) => n.type == 'benefit_alert').toList(),
        recommendations: updatedNotifications.where((n) => n.type == 'card_recommendation').toList(),
        unreadCount: newUnreadCount,
      );
    } catch (e) {
      state = state.copyWith(error: 'Failed to mark as read: $e');
    }
  }

  /// Mark all notifications as read
  Future<void> markAllAsRead(String userId) async {
    try {
      await _repository.markAllAsRead(userId);
      
      // Update local state
      final updatedNotifications = state.notifications.map((n) {
        return n.copyWith(isRead: true, readAt: DateTime.now());
      }).toList();
      
      state = state.copyWith(
        notifications: updatedNotifications,
        benefitAlerts: updatedNotifications.where((n) => n.type == 'benefit_alert').toList(),
        recommendations: updatedNotifications.where((n) => n.type == 'card_recommendation').toList(),
        unreadCount: 0,
      );
    } catch (e) {
      state = state.copyWith(error: 'Failed to mark all as read: $e');
    }
  }

  /// Handle notification action
  Future<void> handleNotificationAction(String userId, AppNotification notification) async {
    try {
      // Mark as read if not already
      if (!notification.isRead) {
        await markAsRead(userId, notification.id);
      }
      
      // Record action analytics (optional)
      // Could track which actions users take most often
    } catch (e) {
      state = state.copyWith(error: 'Failed to handle action: $e');
    }
  }

  /// Update notification preference
  Future<void> updatePreference(String userId, String key, bool value) async {
    try {
      final currentPrefs = state.preferences ?? NotificationPreferences(
        userId: userId,
        updatedAt: DateTime.now(),
      );
        NotificationPreferences updatedPrefs;
      switch (key) {
        case 'benefit_alerts':
          updatedPrefs = currentPrefs.copyWith(benefitAlerts: value);
          break;
        case 'card_recommendations':
          updatedPrefs = currentPrefs.copyWith(cardRecommendations: value);
          break;
        case 'spending_insights':
          updatedPrefs = currentPrefs.copyWith(spendingInsights: value);
          break;
        case 'email_notifications':
          updatedPrefs = currentPrefs.copyWith(emailFrequency: value ? 'daily' : 'never');
          break;
        default:
          return;
      }
      
      await _repository.updateNotificationPreferences(updatedPrefs);
      
      state = state.copyWith(preferences: updatedPrefs);
    } catch (e) {
      state = state.copyWith(error: 'Failed to update preference: $e');
    }
  }

  /// Create benefit alert notification
  Future<void> createBenefitAlert({
    required String userId,
    required String title,
    required String message,
    String? benefitId,
    String? cardId,
    double? savingsAmount,
  }) async {
    try {
      final notification = await _repository.createBenefitAlert(
        userId: userId,
        title: title,
        message: message,
        benefitId: benefitId,
        cardId: cardId,
        savingsAmount: savingsAmount,
      );
      
      // Add to local state
      final updatedNotifications = [notification, ...state.notifications];
      
      state = state.copyWith(
        notifications: updatedNotifications,
        benefitAlerts: [notification, ...state.benefitAlerts],
        unreadCount: state.unreadCount + 1,
      );
    } catch (e) {
      state = state.copyWith(error: 'Failed to create benefit alert: $e');
    }
  }

  /// Create card recommendation notification
  Future<void> createCardRecommendation({
    required String userId,
    required String title,
    required String message,
    required String cardId,
    required double potentialSavings,
  }) async {
    try {
      final notification = await _repository.createCardRecommendation(
        userId: userId,
        title: title,
        message: message,
        cardId: cardId,
        potentialSavings: potentialSavings,
      );
      
      // Add to local state
      final updatedNotifications = [notification, ...state.notifications];
      
      state = state.copyWith(
        notifications: updatedNotifications,
        recommendations: [notification, ...state.recommendations],
        unreadCount: state.unreadCount + 1,
      );
    } catch (e) {
      state = state.copyWith(error: 'Failed to create recommendation: $e');
    }
  }

  /// Create spending insight notification
  Future<void> createSpendingInsight({
    required String userId,
    required String title,
    required String message,
    String? category,
    double? amount,
  }) async {
    try {
      final notification = await _repository.createSpendingInsight(
        userId: userId,
        title: title,
        message: message,
        category: category,
        amount: amount,
      );
      
      // Add to local state
      final updatedNotifications = [notification, ...state.notifications];
      
      state = state.copyWith(
        notifications: updatedNotifications,
        unreadCount: state.unreadCount + 1,
      );
    } catch (e) {
      state = state.copyWith(error: 'Failed to create insight: $e');
    }
  }

  /// Create mock notifications for fallback
  List<AppNotification> _createMockNotifications(String userId) {
    final now = DateTime.now();
    
    return [
      AppNotification(
        id: 'mock_1',
        userId: userId,
        type: 'benefit_alert',
        title: 'New Dining Benefit Available!',
        message: 'Your HDFC Regalia card now offers 5% cashback on dining until December 31st.',
        priority: 'high',
        isActionable: true,
        actionType: 'view_benefit',
        actionData: 'dining_benefit',
        data: {'category': 'dining', 'cashback_rate': 5},
        createdAt: now.subtract(const Duration(hours: 2)),
        isRead: false,
      ),
      AppNotification(
        id: 'mock_2',
        userId: userId,
        type: 'card_recommendation',
        title: 'Better Card for Your Spending',
        message: 'Based on your spending pattern, you could save ₹2,400 annually with the ICICI Amazon Pay card.',
        priority: 'medium',
        isActionable: true,
        actionType: 'view_card',
        actionData: 'icici_amazon_pay',
        data: {'potential_savings': 2400, 'card_name': 'ICICI Amazon Pay'},
        createdAt: now.subtract(const Duration(days: 1)),
        isRead: false,
      ),
      AppNotification(
        id: 'mock_3',
        userId: userId,
        type: 'spending_insight',
        title: 'Monthly Spending Summary',
        message: 'You spent ₹15,600 this month and saved ₹780 through your credit cards. Great job!',
        priority: 'low',
        isActionable: true,
        actionType: 'view_analytics',
        data: {'spending': 15600, 'savings': 780},
        createdAt: now.subtract(const Duration(days: 2)),
        isRead: true,
        readAt: now.subtract(const Duration(days: 1)),
      ),
      AppNotification(
        id: 'mock_4',
        userId: userId,
        type: 'benefit_alert',
        title: 'Fuel Surcharge Waiver Ending Soon',
        message: 'Your SBI Card fuel surcharge waiver benefit expires on December 15th. Consider renewing.',
        priority: 'medium',
        isActionable: true,
        actionType: 'view_benefit',
        actionData: 'fuel_benefit',
        data: {'category': 'fuel', 'expiry_date': '2024-12-15'},
        createdAt: now.subtract(const Duration(days: 3)),
        isRead: true,
        readAt: now.subtract(const Duration(days: 2)),
      ),
    ];
  }
}
