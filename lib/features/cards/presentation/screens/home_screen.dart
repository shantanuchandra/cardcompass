import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';

import '../../../../core/app_config.dart';
import '../../../../core/theme.dart';
import '../../../../core/services/data_pipeline_debug_service.dart';
import '../../../../core/services/user_data_deletion_service.dart';
import '../../../../core/services/password_input_service.dart';
import '../../../../core/services/global_password_service.dart';
import '../../../../core/services/global_message_service.dart';
import '../../../../shared/widgets/credit_card_widget.dart';
import '../../../../shared/widgets/sync_progress_dialog.dart';
import '../../../../core/providers/service_providers.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../../transactions/presentation/screens/transactions_screen.dart';
import '../../../analytics/presentation/screens/analytics_screen.dart';
import '../../../recommendations/presentation/screens/recommendations_screen.dart';
import '../../../sync/widgets/card_url_input_dialog.dart';
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
      body: _screens[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Transactions',
          ),
          NavigationDestination(
            icon: Icon(Icons.analytics_outlined),
            selectedIcon: Icon(Icons.analytics),
            label: 'Analytics',
          ),
          NavigationDestination(
            icon: Icon(Icons.recommend_outlined),
            selectedIcon: Icon(Icons.recommend),
            label: 'Recommendations',
          ),
        ],
      ),
    );
  }
}

class HomeTab extends ConsumerWidget {
  const HomeTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Good Morning!',              style: AppTextStyles.caption.copyWith(
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
            onPressed: () {
              // TODO: Show user profile
            },
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
        
        // Refresh the UI by invalidating providers
        ref.invalidate(activeCardsProvider);
        ref.invalidate(recentTransactionsProvider);
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
          
          // Refresh the UI by invalidating all data providers
          ref.invalidate(activeCardsProvider);
          ref.invalidate(recentTransactionsProvider);
          ref.invalidate(totalCreditLimitProvider);
          ref.invalidate(monthlyRewardsProvider);
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
                  return totalCreditLimit.when(
                    data: (value) => _buildStatCard(
                      context,
                      'Total Credit',
                      '₹${(value / 1000).toStringAsFixed(0)}K',
                      Icons.credit_card,
                      Theme.of(context).primaryColor,
                    ),
                    loading: () => _buildStatCard(
                      context,
                      'Total Credit',
                      '₹100K',
                      Icons.credit_card,
                      Theme.of(context).primaryColor,
                    ),
                    error: (_, __) => _buildStatCard(
                      context,
                      'Total Credit',
                      '₹100K',
                      Icons.credit_card,
                      Theme.of(context).primaryColor,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Consumer(
                builder: (context, ref, child) {
                  final monthlyRewards = ref.watch(monthlyRewardsProvider);
                  return monthlyRewards.when(
                    data: (value) => _buildStatCard(
                      context,
                      'This Month Rewards',
                      '₹${value.toStringAsFixed(0)}',
                      Icons.star,
                      Colors.amber,
                    ),
                    loading: () => _buildStatCard(
                      context,
                      'This Month Rewards',
                      '₹412',
                      Icons.star,
                      Colors.amber,
                    ),
                    error: (_, __) => _buildStatCard(
                      context,
                      'This Month Rewards',
                      '₹412',
                      Icons.star,
                      Colors.amber,
                    ),
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: AppTextStyles.caption.copyWith(color: color),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: AppTextStyles.heading3.copyWith(color: color),
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
                final cardsAsync = ref.watch(activeCardsProvider);
                return cardsAsync.when(
                  data: (cards) => cards.isNotEmpty
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
                      : const SizedBox.shrink(),
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 16),
        Consumer(
          builder: (context, ref, child) {
            final cardsAsync = ref.watch(activeCardsProvider);
            return cardsAsync.when(
              data: (cards) {
                if (cards.isEmpty) {
                  return _buildEmptyCardsWidget(context);
                }
                return _buildCardsGrid(context, cards);
              },
              loading: () => _buildCardsLoadingWidget(),
              error: (error, _) {
                print('Error loading cards: $error');
                return _buildEmptyCardsWidget(context);
              },
            );
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

  Widget _buildCardsLoadingWidget() {
    return Container(
      height: 200,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.grey[100],
      ),
      child: const Center(
        child: CircularProgressIndicator(),
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
              width: 320,              child: CreditCardWidget(
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
                final transactionsAsync = ref.watch(recentTransactionsProvider);
                return transactionsAsync.when(
                  data: (transactions) => transactions.isNotEmpty
                      ? TextButton(
                          onPressed: () {
                            // TODO: Show all transactions
                          },
                          child: const Text('View All'),
                        )
                      : const SizedBox.shrink(),
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 16),
        Consumer(
          builder: (context, ref, child) {
            final transactionsAsync = ref.watch(recentTransactionsProvider);
            return transactionsAsync.when(
              data: (transactions) {
                if (transactions.isEmpty) {
                  return _buildEmptyTransactionsWidget(context);
                }
                return _buildTransactionsList(context, transactions);
              },
              loading: () => _buildTransactionsLoadingWidget(),
              error: (error, _) {
                print('Error loading transactions: $error');
                return _buildEmptyTransactionsWidget(context);
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildEmptyTransactionsWidget(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.receipt_long_outlined,
            size: 48,
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'No transactions yet',
            style: AppTextStyles.body1.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your recent transactions will appear here',
            style: AppTextStyles.caption.copyWith(
              color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.7),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionsLoadingWidget() {
    return Container(
      height: 200,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.grey[100],
      ),
      child: const Center(
        child: CircularProgressIndicator(),
      ),
    );
  }

  Widget _buildTransactionsList(BuildContext context, List<dynamic> transactions) {
    return Column(
      children: transactions.take(5).map((transaction) {
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _getCategoryColor(transaction.categoryString).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _getCategoryIcon(transaction.categoryString),
                  color: _getCategoryColor(transaction.categoryString),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      transaction.merchantName ?? transaction.description ?? 'Unknown Transaction',
                      style: AppTextStyles.body1.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatDate(transaction.transactionDate),
                      style: AppTextStyles.caption.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
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
                    style: AppTextStyles.body1.copyWith(
                      fontWeight: FontWeight.w600,
                      color: transaction.type == 'debit' 
                          ? Theme.of(context).colorScheme.error
                          : Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  if (transaction.rewardEarned != null && transaction.rewardEarned > 0) ...[
                    const SizedBox(height: 2),
                    Text(
                      '+₹${transaction.rewardEarned.toStringAsFixed(0)} rewards',
                      style: AppTextStyles.caption.copyWith(
                        color: Colors.green,
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
                    child: Text(
                      'Use HDFC Card for Grocery',
                      style: AppTextStyles.body1.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Get 5% cashback on grocery purchases with your HDFC card this month. Potential savings: ₹500',
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

// Real providers that use Supabase instead of mock data
final activeCardsProvider = FutureProvider<List<dynamic>>((ref) async {
  final cardRepo = ref.read(cardRepositoryProvider);
  final authState = ref.read(authStateProvider);
  
  if (authState.user == null) {
    return [];
  }
  
  try {
    return await cardRepo.getUserCards(authState.user!.id);
  } catch (e) {
    print('Error loading user cards: $e');
    return [];
  }
});

final recentTransactionsProvider = FutureProvider<List<dynamic>>((ref) async {
  final transactionRepo = ref.read(transactionRepositoryProvider);
  final authState = ref.read(authStateProvider);
  
  if (authState.user == null) {
    return [];
  }
  
  try {
    return await transactionRepo.getUserTransactions(authState.user!.id, limit: 5);
  } catch (e) {
    print('Error loading recent transactions: $e');
    return [];
  }
});

final totalCreditLimitProvider = FutureProvider<double>((ref) async {
  final cards = await ref.watch(activeCardsProvider.future);
  
  double total = 0.0;
  for (var card in cards) {
    if (card.creditLimit != null) {
      total += card.creditLimit;
    }
  }
  
  // If no real data, show placeholder
  return total > 0 ? total : 100000.0;
});

final monthlyRewardsProvider = FutureProvider<double>((ref) async {
  final transactions = await ref.watch(recentTransactionsProvider.future);
  
  double totalRewards = 0.0;
  final now = DateTime.now();
  
  for (var transaction in transactions) {
    // Only count current month rewards
    if (transaction.transactionDate.month == now.month && 
        transaction.transactionDate.year == now.year &&
        transaction.rewardEarned != null) {
      totalRewards += transaction.rewardEarned;
    }
  }
  
  // If no real data, show placeholder
  return totalRewards > 0 ? totalRewards : 412.0;
});
