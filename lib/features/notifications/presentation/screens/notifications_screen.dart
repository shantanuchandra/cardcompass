import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cardcompass/shared/models/notification.dart';
import 'package:cardcompass/features/notifications/viewmodels/notifications_viewmodel.dart';
import 'package:cardcompass/features/auth/providers/auth_provider.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadNotifications();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _loadNotifications() {
    final userId = ref.read(authStateProvider).user?.id;
    if (userId != null) {
      ref.read(notificationsViewModelProvider.notifier).loadNotifications(userId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(notificationsViewModelProvider);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'All'),
            Tab(text: 'Benefit Alerts'),
            Tab(text: 'Recommendations'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.mark_email_read),
            onPressed: () => _markAllAsRead(),
            tooltip: 'Mark all as read',
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => _showNotificationSettings(),
            tooltip: 'Settings',
          ),
        ],
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : state.error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(state.error!, style: Theme.of(context).textTheme.bodyMedium),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadNotifications,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildNotificationsList(state.notifications),
                    _buildNotificationsList(state.benefitAlerts),
                    _buildNotificationsList(state.recommendations),
                  ],
                ),
    );
  }

  Widget _buildNotificationsList(List<AppNotification> notifications) {
    if (notifications.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.notifications_none, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No notifications',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'We\'ll notify you about benefits and recommendations here',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey[500],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async => _loadNotifications(),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: notifications.length,
        itemBuilder: (context, index) {
          final notification = notifications[index];
          return _buildNotificationCard(notification);
        },
      ),
    );
  }

  Widget _buildNotificationCard(AppNotification notification) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _handleNotificationTap(notification),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _buildNotificationIcon(notification),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          notification.title,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: notification.isRead ? FontWeight.normal : FontWeight.bold,
                          ),
                        ),
                        if (notification.message.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            notification.message,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _buildPriorityChip(notification.priority),
                      const SizedBox(height: 4),
                      Text(
                        _formatDateTime(notification.createdAt),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (notification.isActionable) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Spacer(),
                    TextButton(
                      onPressed: () => _handleNotificationAction(notification),
                      child: Text(_getActionText(notification.actionType)),
                    ),
                    const SizedBox(width: 8),
                    if (!notification.isRead)
                      TextButton(
                        onPressed: () => _markAsRead(notification),
                        child: const Text('Mark as Read'),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNotificationIcon(AppNotification notification) {
    IconData iconData;
    Color color;

    switch (notification.type) {
      case 'benefit_alert':
        iconData = Icons.card_giftcard;
        color = Colors.green;
        break;
      case 'card_recommendation':
        iconData = Icons.credit_card;
        color = Colors.blue;
        break;
      case 'spending_insight':
        iconData = Icons.analytics;
        color = Colors.orange;
        break;
      default:
        iconData = Icons.notifications;
        color = Colors.grey;
    }

    return Container(
      width: 48,
      height: 48,      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(iconData, color: color, size: 24),
    );
  }

  Widget _buildPriorityChip(String priority) {
    Color color;
    switch (priority) {
      case 'high':
        color = Colors.red;
        break;
      case 'medium':
        color = Colors.orange;
        break;
      case 'low':
        color = Colors.green;
        break;
      default:
        color = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        priority.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }

  String _getActionText(String? actionType) {
    switch (actionType) {
      case 'view_benefit':
        return 'View Benefit';
      case 'view_card':
        return 'View Card';
      case 'view_analytics':
        return 'View Analytics';
      default:
        return 'View';
    }
  }

  void _handleNotificationTap(AppNotification notification) {
    if (!notification.isRead) {
      _markAsRead(notification);
    }
  }

  void _handleNotificationAction(AppNotification notification) {
    final userId = ref.read(authStateProvider).user?.id;
    if (userId == null) return;

    ref.read(notificationsViewModelProvider.notifier)
        .handleNotificationAction(userId, notification);

    // Navigate based on action type
    switch (notification.actionType) {
      case 'view_benefit':
        Navigator.pushNamed(context, '/benefits');
        break;
      case 'view_card':
        Navigator.pushNamed(context, '/cards');
        break;
      case 'view_analytics':
        Navigator.pushNamed(context, '/analytics');
        break;
    }
  }

  void _markAsRead(AppNotification notification) {
    final userId = ref.read(authStateProvider).user?.id;
    if (userId == null) return;

    ref.read(notificationsViewModelProvider.notifier)
        .markAsRead(userId, notification.id);
  }

  void _markAllAsRead() {
    final userId = ref.read(authStateProvider).user?.id;
    if (userId == null) return;

    ref.read(notificationsViewModelProvider.notifier)
        .markAllAsRead(userId);
  }

  void _showNotificationSettings() {
    showModalBottomSheet(
      context: context,
      builder: (context) => const NotificationSettingsSheet(),
    );
  }
}

class NotificationSettingsSheet extends ConsumerWidget {
  const NotificationSettingsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(notificationsViewModelProvider);
    final preferences = state.preferences;

    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Notification Settings',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 24),          SwitchListTile(
            title: const Text('Benefit Alerts'),
            subtitle: const Text('Get notified about new benefits and rewards'),
            value: preferences?.benefitAlerts ?? true,
            onChanged: (value) => _updatePreference(ref, 'benefit_alerts', value),
          ),
          SwitchListTile(
            title: const Text('Card Recommendations'),
            subtitle: const Text('Receive personalized card recommendations'),
            value: preferences?.cardRecommendations ?? true,
            onChanged: (value) => _updatePreference(ref, 'card_recommendations', value),
          ),
          SwitchListTile(
            title: const Text('Spending Insights'),
            subtitle: const Text('Get insights about your spending patterns'),
            value: preferences?.spendingInsights ?? true,
            onChanged: (value) => _updatePreference(ref, 'spending_insights', value),
          ),
          SwitchListTile(
            title: const Text('Email Notifications'),
            subtitle: const Text('Receive notifications via email'),
            value: preferences?.emailFrequency != 'never',
            onChanged: (value) => _updatePreference(ref, 'email_notifications', value),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ),
        ],
      ),
    );
  }

  void _updatePreference(WidgetRef ref, String key, bool value) {
    final userId = ref.read(authStateProvider).user?.id;
    if (userId == null) return;

    ref.read(notificationsViewModelProvider.notifier)
        .updatePreference(userId, key, value);
  }
}
