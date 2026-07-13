import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cardcompass/shared/models/notification.dart';
import 'package:cardcompass/features/notifications/viewmodels/notifications_viewmodel.dart';
import 'package:cardcompass/features/auth/providers/auth_provider.dart';
import 'package:cardcompass/core/theme.dart';
import 'package:cardcompass/shared/widgets/app_scaffold.dart';
import 'package:cardcompass/shared/widgets/state_widgets.dart';

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
    
    return CardCompassScaffold(
      title: 'Notifications',
      bottom: TabBar(
        controller: _tabController,
        labelColor: AppTheme.primaryColor,
        unselectedLabelColor: Colors.white38,
        indicatorColor: AppTheme.primaryColor,
        indicatorSize: TabBarIndicatorSize.tab,
        labelStyle: GoogleFonts.spaceGrotesk(
          fontWeight: FontWeight.bold,
          fontSize: 10,
          letterSpacing: 0.5,
        ),
        tabs: const [
          Tab(text: 'ALL'),
          Tab(text: 'BENEFITS'),
          Tab(text: 'SUGGESTIONS'),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.mark_email_read_outlined, color: AppTheme.primaryColor),
          onPressed: () => _markAllAsRead(),
          tooltip: 'Mark all as read',
        ),
        IconButton(
          icon: const Icon(Icons.tune, color: AppTheme.primaryColor),
          onPressed: () => _showNotificationSettings(),
          tooltip: 'Settings',
        ),
      ],
      body: state.isLoading
          ? const LoadingState()
          : state.error != null
              ? ErrorState(
                  error: state.error!,
                  onRetry: _loadNotifications,
                  retryText: 'RETRY',
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
      return const EmptyState(
        title: 'No Alerts Found',
        message: 'New optimization opportunities and rule updates will log here.',
        icon: Icons.notifications_none_outlined,
      );
    }

    return RefreshIndicator(
      color: AppTheme.primaryColor,
      backgroundColor: const Color(0xFF0C152B),
      onRefresh: () async => _loadNotifications(),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, 20, AppSpacing.md, 80),
        itemCount: notifications.length,
        itemBuilder: (context, index) {
          final notification = notifications[index];
          return _buildNotificationCard(notification);
        },
      ).animate().fadeIn(duration: 250.ms).slideY(begin: 0.05, end: 0),
    );
  }

  Widget _buildNotificationCard(AppNotification notification) {
    final activeBorderColor = notification.isRead 
        ? Colors.white.withValues(alpha: 0.06) 
        : AppTheme.primaryColor.withValues(alpha: 0.25);
    final textWeight = notification.isRead ? FontWeight.normal : FontWeight.bold;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0C152B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: activeBorderColor, width: 1.2),
        boxShadow: notification.isRead 
            ? null 
            : AppTheme.neonGlow(color: AppTheme.primaryColor, opacity: 0.08, blurRadius: 10),
      ),
      child: InkWell(
        onTap: () => _handleNotificationTap(notification),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildNotificationIcon(notification),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          notification.title.toUpperCase(),
                          style: GoogleFonts.spaceGrotesk(
                            color: Colors.white,
                            fontWeight: textWeight,
                            fontSize: 12,
                            letterSpacing: 0.5,
                          ),
                        ),
                        if (notification.message.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            notification.message,
                            style: GoogleFonts.plusJakartaSans(
                              color: Colors.white70,
                              fontSize: 11,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _buildPriorityChip(notification.priority),
                      const SizedBox(height: 8),
                      Text(
                        _formatDateTime(notification.createdAt).toUpperCase(),
                        style: GoogleFonts.spaceGrotesk(
                          color: Colors.white30,
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
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
                    OutlinedButton(
                      onPressed: () => _handleNotificationAction(notification),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        side: const BorderSide(color: AppTheme.primaryColor, width: 1),
                      ),
                      child: Text(
                        _getActionText(notification.actionType).toUpperCase(),
                        style: GoogleFonts.spaceGrotesk(color: AppTheme.primaryColor, fontSize: 9, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (!notification.isRead)
                      TextButton(
                        onPressed: () => _markAsRead(notification),
                        child: Text(
                          'DISMISS',
                          style: GoogleFonts.spaceGrotesk(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold),
                        ),
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
        color = AppTheme.successColor;
        break;
      case 'card_recommendation':
        iconData = Icons.credit_card;
        color = AppTheme.primaryColor;
        break;
      case 'spending_insight':
        iconData = Icons.analytics_outlined;
        color = AppTheme.secondaryColor;
        break;
      default:
        iconData = Icons.notifications_none_outlined;
        color = Colors.white54;
    }

    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Icon(iconData, color: color, size: 18),
    );
  }

  Widget _buildPriorityChip(String priority) {
    Color color;
    switch (priority) {
      case 'high':
        color = AppTheme.errorColor;
        break;
      case 'medium':
        color = AppTheme.warningColor;
        break;
      case 'low':
        color = AppTheme.successColor;
        break;
      default:
        color = Colors.white38;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(
        priority.toUpperCase(),
        style: GoogleFonts.spaceGrotesk(
          color: color,
          fontSize: 8,
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
      return 'now';
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
      backgroundColor: const Color(0xFF0C152B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
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

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ALERT SETTINGS',
              style: GoogleFonts.spaceGrotesk(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
                letterSpacing: 1.0,
              ),
            ),
            const Divider(color: Color(0xFF1E293B), height: AppSpacing.lg),
            SwitchListTile(
              title: Text('BENEFIT ALERTS', style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
              subtitle: Text('Get notified about card perks', style: GoogleFonts.plusJakartaSans(color: Colors.white30, fontSize: 10)),
              value: preferences?.benefitAlerts ?? true,
              activeColor: AppTheme.primaryColor,
              onChanged: (value) => _updatePreference(ref, 'benefit_alerts', value),
            ),
            SwitchListTile(
              title: Text('CARD RECOMMENDATIONS', style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
              subtitle: Text('Receive optimized match options', style: GoogleFonts.plusJakartaSans(color: Colors.white30, fontSize: 10)),
              value: preferences?.cardRecommendations ?? true,
              activeColor: AppTheme.primaryColor,
              onChanged: (value) => _updatePreference(ref, 'card_recommendations', value),
            ),
            SwitchListTile(
              title: Text('SPENDING INSIGHTS', style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
              subtitle: Text('Get patterns analysis alerts', style: GoogleFonts.plusJakartaSans(color: Colors.white30, fontSize: 10)),
              value: preferences?.spendingInsights ?? true,
              activeColor: AppTheme.primaryColor,
              onChanged: (value) => _updatePreference(ref, 'spending_insights', value),
            ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor),
                child: Text('DONE', style: GoogleFonts.spaceGrotesk(color: const Color(0xFF050B18), fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
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
