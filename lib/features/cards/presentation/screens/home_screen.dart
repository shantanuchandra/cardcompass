import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/app_config.dart';
import '../../../../core/theme.dart';
import '../../../../core/services/data_pipeline_debug_service.dart';
import '../../../../core/services/user_data_deletion_service.dart';
import '../../../../core/services/password_input_service.dart';
import '../../../../core/services/global_password_service.dart';
import '../../../../core/services/global_message_service.dart';
import '../../../../shared/widgets/credit_card_widget.dart';
import '../../../../shared/widgets/sync_progress_dialog.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../../transactions/presentation/screens/transactions_screen.dart';
import '../../../analytics/presentation/screens/analytics_screen.dart';
import '../../../recommendations/presentation/screens/recommendations_screen.dart';
import '../../../sync/widgets/card_url_input_dialog.dart';
import '../../providers/cards_provider.dart';
import '../../../transactions/providers/transactions_provider.dart';
import 'add_card_screen.dart';
import 'cards_list_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const HomeTab(),
    const TransactionsScreen(),
    const AnalyticsScreen(),
    const RecommendationsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050B18),
      body: Stack(
        children: [
          _screens[_currentIndex],
          
          // Floating Translucent Bottom Navigation Dock
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF0C152B).withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.08),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildNavItem(0, Icons.home_outlined, Icons.home, 'Home'),
                  _buildNavItem(1, Icons.receipt_long_outlined, Icons.receipt_long, 'Txns'),
                  _buildNavItem(2, Icons.analytics_outlined, Icons.analytics, 'Analytics'),
                  _buildNavItem(3, Icons.recommend_outlined, Icons.recommend, 'Advice'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(int index, IconData outlineIcon, IconData filledIcon, String label) {
    final isSelected = _currentIndex == index;
    return InkWell(
      onTap: () => setState(() => _currentIndex = index),
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryColor.withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? filledIcon : outlineIcon,
              color: isSelected ? AppTheme.primaryColor : Colors.white60,
              size: 20,
            ).animate(target: isSelected ? 1 : 0).scale(begin: const Offset(1, 1), end: const Offset(1.15, 1.15), duration: 200.ms),
            if (isSelected) ...[
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.spaceGrotesk(
                  color: AppTheme.primaryColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                  letterSpacing: 0.5,
                ),
              ).animate().fadeIn(duration: 200.ms).slideX(begin: -0.2, end: 0),
            ],
          ],
        ),
      ),
    );
  }
}

class HomeTab extends ConsumerStatefulWidget {
  const HomeTab({super.key});

  @override
  ConsumerState<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends ConsumerState<HomeTab> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  void _loadData() {
    final authState = ref.read(authStateProvider);
    final userId = authState.user?.id;
    if (userId == null) return;
    ref.read(cardsProvider.notifier).loadUserCards(userId);
    ref.read(transactionsProvider.notifier).loadUserTransactions(userId);
  }

  @override
  Widget build(BuildContext context) {
    // Reload cards/transactions whenever the authenticated user changes
    // (e.g. logout → different login while this tab stays in the navigator stack).
    ref.listen<AuthState>(authStateProvider, (previous, next) {
      final prevId = previous?.user?.id;
      final nextId = next.user?.id;
      if (prevId == nextId) return;
      _loadData();
    });

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Good Morning!',
              style: AppTextStyles.caption.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            Text(
              'Welcome to ${AppConfig.appName}',
              style: AppTextStyles.heading3,
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () {
              Navigator.of(context).pushNamed('/benefits');
            },
            icon: const Icon(Icons.card_giftcard),
            tooltip: 'Benefits',
          ),
          IconButton(
            onPressed: () => _showSyncDataDialog(context, ref),
            icon: const Icon(Icons.sync),
            tooltip: 'Sync Data from Gmail',
          ),
          IconButton(
            onPressed: () => _showDeleteAllDataDialog(context, ref),
            icon: const Icon(Icons.delete_forever),
            tooltip: 'Delete All Data',
            color: Colors.red,
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pushNamed('/profile'),
            icon: const CircleAvatar(
              radius: 16,
              child: Icon(Icons.person, size: 20),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => const AddCardScreen(),
            ),
          );
        },
        icon: const Icon(Icons.add),
        label: const Text('Add Card'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: AnimationLimiter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: AnimationConfiguration.toStaggeredList(
                duration: const Duration(milliseconds: 375),
                childAnimationBuilder: (widget) => SlideAnimation(
                  verticalOffset: 50.0,
                  child: FadeInAnimation(
                    child: widget,
                  ),
                ),
                children: [
                  // Quick Stats Section
                  _buildQuickStatsSection(context, ref),

                  const SizedBox(height: 24),

                  // My Cards Section
                  _buildMyCardsSection(context, ref),

                  const SizedBox(height: 24),

                  // Recent Transactions Section
                  _buildRecentTransactionsSection(context, ref),

                  const SizedBox(height: 24),

                  // Recommendations Section
                  _buildRecommendationsSection(context),

                  const SizedBox(height: 100), // Space for FAB
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showSyncDataDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.sync, color: Colors.blue),
                  SizedBox(width: 8),
                  Text('Sync Data from Gmail'),
                ],
              ),
              content: const Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'This will fetch credit card statements from your Gmail account and import transactions into the app.',
                    style: TextStyle(fontSize: 14),
                  ),
                  SizedBox(height: 16),
                  Text(
                    '• Gmail will be searched for bank statements\n'
                    '• PDF attachments will be parsed\n'
                    '• Transactions will be imported to the database\n'
                    '• Credit cards will be automatically detected',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _syncDataFromGmail(context, ref);
                  },
                  child: const Text('Start Sync'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _syncDataFromGmail(BuildContext context, WidgetRef ref) async {
    // Get current user
    final authState = ref.read(authStateProvider);
    if (!authState.isAuthenticated || authState.user == null) {
      GlobalMessageService.showError('Please log in first');
      return;
    }

    if (authState.user!.id == 'guest') {
      GlobalMessageService.showError('Gmail sync isn\'t available in guest mode. Sign in with Google to sync.');
      return;
    }

    // Store context reference for progress dialogs
    BuildContext? dialogContext;

    // Show progress dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        dialogContext = context; // Store the dialog context
        return const SyncProgressDialog();
      },
    );

    try {
      // Set up password input callback for manual password entry
      PasswordInputService.setGlobalPasswordCallback((String bankName, String? hint) async {
        print('🔐 Manual password callback triggered for $bankName');

        // Close progress dialog temporarily for password input
        if (dialogContext != null && dialogContext!.mounted) {
          Navigator.of(dialogContext!).pop();
          print('📱 Progress dialog closed, showing password input');

          // Add a small delay to ensure dialog is closed
          await Future.delayed(const Duration(milliseconds: 200));
        }

        // Request password using the global service
        final password = await GlobalPasswordService.requestPassword(bankName, hint: hint);
        print('🔑 Password result: ${password != null ? 'provided' : 'cancelled'}');

        // Show progress dialog again after password input
        if (context.mounted) {
          await Future.delayed(const Duration(milliseconds: 200));
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (BuildContext ctx) {
              dialogContext = ctx; // Update the dialog context reference
              return const SyncProgressDialog();
            },
          );
          print('📱 Progress dialog restored');
        }

        return password;
      });

      // Initialize the debug service for data sync
      final debugService = DataPipelineDebugService();
      print('🔧 Created DataPipelineDebugService instance');

      // Set up card URL prompt callback
      debugService.onCardUrlRequired = ({
        required String bankName,
        required String cardVariant,
        required String emailSubject,
        String? suggestedUrl,
      }) async {
        print('🔔 CALLBACK INVOKED in home_screen!');
        print('   Bank: $bankName, Card: $cardVariant');
        print('   Context: $context');
        print('   Context mounted: ${context.mounted}');

        final result = await showCardUrlInputDialog(
          context: context,
          bankName: bankName,
          cardVariant: cardVariant,
          emailSubject: emailSubject,
          suggestedUrl: suggestedUrl,
        );

        print('🔔 CALLBACK RETURNING: $result');
        return result;
      };
      print('🔧 Set onCardUrlRequired callback on debugService');
      print('🔧 Callback is now: ${debugService.onCardUrlRequired == null ? "NULL" : "SET"}');

      // Run the sequential user flow
      print('🔧 About to call debugSequentialUserFlow...');
      await debugService.debugSequentialUserFlow(authState.user!.id);

      // Close progress dialog
      if (dialogContext != null && dialogContext!.mounted) {
        Navigator.of(dialogContext!).pop();

        // Show success message using global service
        GlobalMessageService.showSuccess('Data sync completed! Check your cards and transactions.');

        // Refresh the UI by reloading the underlying data
        _loadData();
      }

    } catch (error) {
      // Close progress dialog
      if (dialogContext != null && dialogContext!.mounted) {
        Navigator.of(dialogContext!).pop();

        // Show error message using global service
        GlobalMessageService.showError('Sync failed: ${error.toString()}');
      }
    }
  }

  void _showDeleteAllDataDialog(BuildContext context, WidgetRef ref) async {
    // Get current user
    final authState = ref.read(authStateProvider);
    if (!authState.isAuthenticated || authState.user == null) {
      GlobalMessageService.showError('Please log in first');
      return;
    }

    if (authState.user!.id == 'guest') {
      GlobalMessageService.showError('Guest data lives only in this session — sign out to clear it, or sign in to manage a real account.');
      return;
    }

    final userId = authState.user!.id;

    // Show loading dialog while fetching counts
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Expanded(child: Text('Loading data counts...')),
            ],
          ),
        );
      },
    );

    try {
      // Get data counts
      final counts = await UserDataDeletionService.getUserDataCounts(userId);

      // Close loading dialog
      if (context.mounted) {
        Navigator.of(context).pop();

        // Show confirmation dialog with counts
        _showDeleteConfirmationDialog(context, ref, counts);
      }
    } catch (error) {
      // Close loading dialog
      if (context.mounted) {
        Navigator.of(context).pop();

        // Show error message
        GlobalMessageService.showError('Failed to load data counts: ${error.toString()}');
      }
    }
  }

  void _showDeleteConfirmationDialog(BuildContext context, WidgetRef ref, Map<String, int> counts) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.delete_forever, color: Colors.red),
              SizedBox(width: 8),
              Text('Delete All Data'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This will permanently delete ALL your data from the app (except your user profile):',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              if (counts.isNotEmpty) ...[
                Text('📊 Current data to be deleted:',
                     style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                const SizedBox(height: 8),
                ...counts.entries.map((entry) => Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 4),
                  child: Text(
                    '• ${entry.value} ${entry.key}',
                    style: const TextStyle(fontSize: 12),
                  ),
                )),
              ] else ...[
                const Text(
                  '• All credit cards\n'
                  '• All transactions\n'
                  '• All statements\n'
                  '• All email data\n'
                  '\nNote: Your user profile will be preserved.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
              const SizedBox(height: 12),
              const Text(
                '⚠️ This action cannot be undone!',
                style: TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _deleteAllUserData(context, ref);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Delete All'),
            ),
          ],
        );
      },
    );
  }

  void _deleteAllUserData(BuildContext context, WidgetRef ref) async {
    // Get current user
    final authState = ref.read(authStateProvider);
    if (!authState.isAuthenticated || authState.user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please log in first'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final userId = authState.user!.id;

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Expanded(child: Text('Deleting all data...')),
            ],
          ),
        );
      },
    );

    try {
      print('🔄 Starting user data deletion process...');

      // Delete all user data
      final success = await UserDataDeletionService.deleteAllUserData(userId);

      print('✅ Deletion process completed with success: $success');

      // Close loading dialog - ensure context is still mounted
      if (context.mounted) {
        Navigator.of(context).pop();
        print('🔄 Loading dialog dismissed');

        if (success) {
          // Show success message
          GlobalMessageService.showSuccess('All data deleted successfully! (User profile preserved)');

          // Refresh the UI by reloading the underlying data
          _loadData();
          print('🔄 All UI providers refreshed');
        } else {
          // Show error message
          GlobalMessageService.showError('Failed to delete some data. Please try again.');
        }
      } else {
        print('⚠️ Context no longer mounted, cannot dismiss dialog');
      }

    } catch (error) {
      print('❌ Error during deletion: $error');

      // Close loading dialog - ensure context is still mounted
      if (context.mounted) {
        Navigator.of(context).pop();
        print('🔄 Loading dialog dismissed after error');

        // Show error message
        GlobalMessageService.showError('Delete failed: ${error.toString()}');
      } else {
        print('⚠️ Context no longer mounted after error, cannot dismiss dialog');
      }
    }
  }

  Widget _buildQuickStatsSection(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quick Overview',
          style: AppTextStyles.heading3,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Consumer(
                builder: (context, ref, child) {
                  final totalCreditLimit = ref.watch(totalCreditLimitProvider);
                  return _buildStatCard(
                    context,
                    'Total Credit',
                    '₹${(totalCreditLimit / 1000).toStringAsFixed(0)}K',
                    Icons.credit_card,
                    Theme.of(context).colorScheme.primary,
                  );
                },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Consumer(
                builder: (context, ref, child) {
                  final monthlyRewards = ref.watch(monthlyRewardsProvider);
                  return _buildStatCard(
                    context,
                    'This Month Rewards',
                    '₹${monthlyRewards.toStringAsFixed(0)}',
                    Icons.star,
                    Colors.amber,
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatCard(
    BuildContext context,
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF0C152B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withValues(alpha: 0.25),
          width: 1.5,
        ),
        boxShadow: AppTheme.neonGlow(color: color, opacity: 0.12, blurRadius: 12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  style: GoogleFonts.spaceGrotesk(
                    color: Colors.white70,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: GoogleFonts.spaceGrotesk(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMyCardsSection(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'My Cards',
              style: AppTextStyles.heading3,
            ),
            Consumer(
              builder: (context, ref, child) {
                final cards = ref.watch(activeCardsProvider);
                return cards.isNotEmpty
                    ? TextButton(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => const CardsListScreen(),
                            ),
                          );
                        },
                        child: const Text('View All'),
                      )
                    : const SizedBox.shrink();
              },
            ),
          ],
        ),
        const SizedBox(height: 16),
        Consumer(
          builder: (context, ref, child) {
            final cards = ref.watch(activeCardsProvider);
            if (cards.isEmpty) {
              return _buildEmptyCardsWidget(context);
            }
            return _buildCardsGrid(context, cards);
          },
        ),
      ],
    );
  }

  Widget _buildEmptyCardsWidget(BuildContext context) {
    return Container(
      height: 200,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
          style: BorderStyle.solid,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.credit_card_off,
            size: 48,
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'No cards added yet',
            style: AppTextStyles.body1.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap the + button to add your first credit card',
            style: AppTextStyles.caption.copyWith(
              color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.7),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildCardsGrid(BuildContext context, List<dynamic> cards) {
    return SizedBox(
      height: 200,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: cards.length,
        itemBuilder: (context, index) {
          final card = cards[index];
          return Padding(
            padding: EdgeInsets.only(
              right: index < cards.length - 1 ? 16 : 0,
            ),
            child: SizedBox(
              width: 320,
              child: GestureDetector(
                onTap: () => Navigator.of(context).pushNamed(
                  '/card-details',
                  arguments: card.id,
                ),
                child: CreditCardWidget(
                  cardName: card.cardName ?? 'Unknown Card',
                  bankName: card.bankName ?? 'Unknown Bank',
                  lastFourDigits: card.cardNumberLast4 ?? '****',
                  expiryDate: card.expiryDate != null
                    ? '${card.expiryDate!.month.toString().padLeft(2, '0')}/${card.expiryDate!.year.toString().substring(2)}'
                    : 'MM/YY',
                  cardType: card.cardType ?? 'credit',
                  gradientColors: _getCardGradientColors(card.network?.toString().split('.').last ?? 'visa'),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildRecentTransactionsSection(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Recent Transactions',
              style: AppTextStyles.heading3,
            ),
            Consumer(
              builder: (context, ref, child) {
                final transactions = ref.watch(recentTransactionsProvider);
                return transactions.isNotEmpty
                    ? TextButton(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => const TransactionsScreen(),
                            ),
                          );
                        },
                        child: const Text('View All'),
                      )
                    : const SizedBox.shrink();
              },
            ),
          ],
        ),
        const SizedBox(height: 16),
        Consumer(
          builder: (context, ref, child) {
            final transactions = ref.watch(recentTransactionsProvider);
            if (transactions.isEmpty) {
              return _buildEmptyTransactionsWidget(context);
            }
            return _buildTransactionsList(context, transactions);
          },
        ),
      ],
    );
  }

  Widget _buildEmptyTransactionsWidget(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF0C152B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.receipt_long_outlined,
            size: 44,
            color: Colors.white24,
          ),
          const SizedBox(height: 16),
          Text(
            'No transactions yet',
            style: GoogleFonts.spaceGrotesk(
              color: Colors.white70,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your recent transactions will appear here',
            style: GoogleFonts.plusJakartaSans(
              color: Colors.white38,
              fontSize: 11,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionsList(BuildContext context, List<dynamic> transactions) {
    return Column(
      children: transactions.take(5).map((transaction) {
        final categoryColor = _getCategoryColor(transaction.categoryString);
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF0C152B),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.06),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              // Category icon inside a glowing ring
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: categoryColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: categoryColor.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Icon(
                  _getCategoryIcon(transaction.categoryString),
                  color: categoryColor,
                  size: 18,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      transaction.merchantName ?? transaction.description ?? 'Unknown Transaction',
                      style: GoogleFonts.plusJakartaSans(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatDate(transaction.transactionDate),
                      style: GoogleFonts.plusJakartaSans(
                        color: Colors.white38,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '₹${transaction.amount.toStringAsFixed(2)}',
                    style: GoogleFonts.spaceGrotesk(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: transaction.typeString == 'debit'
                          ? AppTheme.errorColor
                          : AppTheme.primaryColor,
                    ),
                  ),
                  if (transaction.rewardEarned != null && transaction.rewardEarned > 0) ...[
                    const SizedBox(height: 2),
                    Text(
                      '+₹${transaction.rewardEarned.toStringAsFixed(0)}',
                      style: GoogleFonts.spaceGrotesk(
                        color: AppTheme.successColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildRecommendationsSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Smart Recommendations',
          style: AppTextStyles.heading3,
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.blue.withValues(alpha: 0.1),
                Colors.purple.withValues(alpha: 0.1),
              ],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.blue.withValues(alpha: 0.2),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.lightbulb,
                      color: Colors.blue,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (context) => const RecommendationsScreen()),
                      ),
                      child: Text(
                        'See personalized recommendations',
                        style: AppTextStyles.body1.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Tap Recommendations in the bottom bar to see which card earns you the most on your recent spending.',
                style: AppTextStyles.body2.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Color _getCategoryColor(String? category) {
    switch (category?.toLowerCase()) {
      case 'food':
        return Colors.orange;
      case 'shopping':
        return Colors.blue;
      case 'fuel':
        return Colors.red;
      case 'entertainment':
        return Colors.purple;
      case 'travel':
        return Colors.green;
      case 'groceries':
      case 'grocery':
        return Colors.teal;
      default:
        return Colors.grey;
    }
  }

  IconData _getCategoryIcon(String? category) {
    switch (category?.toLowerCase()) {
      case 'food':
        return Icons.restaurant;
      case 'shopping':
        return Icons.shopping_bag;
      case 'fuel':
        return Icons.local_gas_station;
      case 'entertainment':
        return Icons.movie;
      case 'travel':
        return Icons.flight;
      case 'groceries':
      case 'grocery':
        return Icons.local_grocery_store;
      default:
        return Icons.payment;
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date).inDays;

    if (difference == 0) {
      return 'Today';
    } else if (difference == 1) {
      return 'Yesterday';
    } else if (difference < 7) {
      return '${difference} days ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  List<Color> _getCardGradientColors(String network) {
    switch (network.toLowerCase()) {
      case 'visa':
        return [const Color(0xFF1A1F71), const Color(0xFF3D4ED8)];
      case 'mastercard':
        return [const Color(0xFFEB001B), const Color(0xFFF79E1B)];
      case 'rupay':
        return [const Color(0xFF00A851), const Color(0xFF6CBF2F)];
      case 'amex':
        return [const Color(0xFF006FCF), const Color(0xFF016FD0)];
      default:
        return [const Color(0xFF6366F1), const Color(0xFF8B5CF6)];
    }
  }
}
