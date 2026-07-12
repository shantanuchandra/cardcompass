import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/gmail/v1.dart' as gmail;
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase_lib;

import '../../../../core/config/ai_config.dart';
import '../../../../core/theme.dart';
import '../../../../core/services/data_pipeline_debug_service.dart';
import '../../../../core/services/enhanced_gmail_service.dart';
import '../../../../core/services/pdf_parsing_service_impl.dart';
import '../../../../core/services/user_data_deletion_service.dart';
import '../../../../core/services/password_input_service.dart';
import '../../../../core/services/global_password_service.dart';
import '../../../../core/services/global_message_service.dart';
import '../../../../core/providers/service_providers.dart' show alertEmailSyncServiceProvider;
import '../../../../core/services/reward_intelligence_service.dart' show InsightType;
import '../../../../shared/widgets/credit_card_widget.dart';
import '../../../../shared/widgets/sync_progress_dialog.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../../transactions/presentation/screens/transactions_screen.dart';
import '../../../analytics/presentation/screens/analytics_screen.dart';
import '../../../recommendations/presentation/screens/recommendations_screen.dart';
import '../../../sync/widgets/card_url_input_dialog.dart';
import '../../../dashboard/widgets/smart_transaction_analyzer.dart';
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
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 900;
          if (isWide) {
            return Row(
              children: [
                _buildWebSidebar(context),
                VerticalDivider(
                  width: 1,
                  color: Colors.white.withValues(alpha: 0.08),
                ),
                Expanded(
                  child: _screens[_currentIndex],
                ),
              ],
            );
          }
          
          return Stack(
            children: [
              _screens[_currentIndex],
              
              // Floating Translucent Bottom Navigation Dock for Mobile
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: _buildMobileBottomNav(context),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildWebSidebar(BuildContext context) {
    return Container(
      width: 250,
      color: const Color(0xFF0C152B),
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // App Logo / Title
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppTheme.primaryColor, AppTheme.secondaryColor],
                  ),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: AppTheme.neonGlow(color: AppTheme.primaryColor, opacity: 0.25, blurRadius: 8),
                ),
                child: const Icon(
                  Icons.credit_card,
                  size: 20,
                  color: Color(0xFF050B18),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'CARDCOMPASS',
                style: GoogleFonts.spaceGrotesk(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 40),
          
          // Navigation Items
          Expanded(
            child: Column(
              children: [
                _buildSidebarNavItem(0, Icons.home_outlined, Icons.home, 'Home Dashboard'),
                const SizedBox(height: 8),
                _buildSidebarNavItem(1, Icons.receipt_long_outlined, Icons.receipt_long, 'Ledger Txns'),
                const SizedBox(height: 8),
                _buildSidebarNavItem(2, Icons.analytics_outlined, Icons.analytics, 'Analytics Hub'),
                const SizedBox(height: 8),
                _buildSidebarNavItem(3, Icons.recommend_outlined, Icons.recommend, 'Smart Advisor'),
              ],
            ),
          ),
          
          // Extra bottom link/metadata or user profile shortcut
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF050B18),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.05),
              ),
            ),
            child: InkWell(
              onTap: () => Navigator.of(context).pushNamed('/profile'),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 14,
                    child: Icon(Icons.person, size: 16),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'USER PROFILE',
                      style: GoogleFonts.spaceGrotesk(
                        color: Colors.white70,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const Icon(Icons.settings, size: 14, color: Colors.white30),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarNavItem(int index, IconData outlineIcon, IconData filledIcon, String label) {
    final isSelected = _currentIndex == index;
    return InkWell(
      onTap: () => setState(() => _currentIndex = index),
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryColor.withValues(alpha: 0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppTheme.primaryColor.withValues(alpha: 0.15) : Colors.transparent,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? filledIcon : outlineIcon,
              color: isSelected ? AppTheme.primaryColor : Colors.white60,
              size: 20,
            ),
            const SizedBox(width: 14),
            Text(
              label,
              style: GoogleFonts.spaceGrotesk(
                color: isSelected ? AppTheme.primaryColor : Colors.white70,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 12,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileBottomNav(BuildContext context) {
    return Container(
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

    // Build welcome greeting with actual user name
    final authState = ref.watch(authStateProvider);
    final userName = authState.user?.name ?? authState.user?.email.split('@').first ?? 'there';
    // Capitalize first letter of name
    final displayName = userName.isNotEmpty
        ? userName[0].toUpperCase() + userName.substring(1)
        : 'there';

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Welcome back, $displayName!',
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
            tooltip: 'Sync Gmail Statements',
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
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 900;
                if (isWide) {
                  // Wide / Web layout: 3-col left | 2-col right
                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildSmartAnalyzerSection(context, ref),
                              const SizedBox(height: 28),
                              _buildQuickStatsSection(context, ref),
                              const SizedBox(height: 28),
                              _buildQuickActionsSection(context, ref),
                              const SizedBox(height: 28),
                              _buildThisMonthSection(context, ref),
                              const SizedBox(height: 28),
                              _buildMyCardsSection(context, ref),
                            ],
                          ),
                        ),
                        const SizedBox(width: 28),
                        Expanded(
                          flex: 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildRecentTransactionsSection(context, ref),
                              const SizedBox(height: 28),
                              _buildRecommendationsSection(context),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }
                // Mobile layout: single column
                return SingleChildScrollView(
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
                          // Smart Transaction Analyzer (Hero)
                          _buildSmartAnalyzerSection(context, ref),
                          const SizedBox(height: 24),

                          // Quick Stats Section
                          _buildQuickStatsSection(context, ref),
                          const SizedBox(height: 24),

                          // Quick Actions Section
                          _buildQuickActionsSection(context, ref),
                          const SizedBox(height: 24),

                          // This Month Summary
                          _buildThisMonthSection(context, ref),
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
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  void _showSyncDataDialog(BuildContext context, WidgetRef ref) {
    int _selectedDays = 30;
    int _maxEmails = 10;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E1E2E) : Colors.white;
    final surfaceBg = isDark ? const Color(0xFF2A2A3E) : const Color(0xFFF8F9FF);
    final accentColor = const Color(0xFF6C63FF);
    final textPrimary = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final textSecondary = isDark ? Colors.white60 : Colors.black45;

    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (BuildContext dialogContext) {
        // Ollama parameters
        var localProvider = AIConfig.activeProvider;
        final ollamaUrlController = TextEditingController(text: AIConfig.ollamaUrl);
        final ollamaModelController = TextEditingController(text: AIConfig.ollamaModel);

        // Groq parameters
        final groqApiKeyController = TextEditingController(text: AIConfig.groqApiKey);
        final groqModelController = TextEditingController(text: AIConfig.groqModel);

        // Instantly cache in memory as they type
        ollamaUrlController.addListener(() => AIConfig.ollamaUrl = ollamaUrlController.text.trim());
        ollamaModelController.addListener(() => AIConfig.ollamaModel = ollamaModelController.text.trim());
        groqApiKeyController.addListener(() => AIConfig.groqApiKey = groqApiKeyController.text.trim());
        groqModelController.addListener(() => AIConfig.groqModel = groqModelController.text.trim());

        return StatefulBuilder(

          builder: (context, setState) {
            // Snap labels for "Look back" slider
            const List<int> daySnaps = [7, 14, 30, 60, 90, 180, 365];
            final daysLabel = _selectedDays == 365
                ? '1 year'
                : '$_selectedDays days';

            // Snap labels for Max Emails slider
            const List<int> emailSnaps = [5, 10, 20, 30, 50];
            final emailsLabel = '$_maxEmails emails';

            // Models dropdown lists
            final groqModels = ['llama-3.3-70b-versatile', 'llama-3.1-8b-instant', 'mixtral-8x7b-32768'];
            if (!groqModels.contains(groqModelController.text)) {
              groqModels.insert(0, groqModelController.text);
            }

            final ollamaModels = ['gemma4', 'qwen2.5', 'llama3', 'mistral'];
            if (!ollamaModels.contains(ollamaModelController.text)) {
              ollamaModels.insert(0, ollamaModelController.text);
            }


            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
              child: Container(
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: accentColor.withOpacity(0.18),
                      blurRadius: 40,
                      spreadRadius: 0,
                      offset: const Offset(0, 8),
                    ),
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ── Header ──
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            accentColor.withOpacity(0.9),
                            const Color(0xFF8B5CF6).withOpacity(0.9),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                      ),
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.sync_rounded, color: Colors.white, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [

                              Text(
                                'Sync from Gmail',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.2,
                                ),
                              ),
                              Text(
                                'Import credit card statements',
                                style: TextStyle(color: Colors.white70, fontSize: 12),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // ── Body ──
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ─ Look-back slider ─
                            _buildSliderSection(
                              context: context,
                              label: 'Look back',
                              icon: Icons.calendar_month_rounded,
                              valueLabel: daysLabel,
                              accentColor: accentColor,
                              surfaceBg: surfaceBg,
                              textPrimary: textPrimary,
                              textSecondary: textSecondary,
                              isDark: isDark,
                              sliderWidget: SliderTheme(
                                data: _premiumSliderTheme(context, accentColor),
                                child: Slider(
                                  value: _selectedDays.toDouble(),
                                  min: 7,
                                  max: 365,
                                  divisions: 52,
                                  label: daysLabel,
                                  onChanged: (v) => setState(() {
                                    final raw = v.round();
                                    final snapped = daySnaps.reduce((a, b) =>
                                        (a - raw).abs() < (b - raw).abs() ? a : b);
                                    _selectedDays = (raw - snapped).abs() < 5 ? snapped : raw;
                                  }),
                                ),
                              ),
                              ticks: const ['7d', '14d', '30d', '60d', '90d', '180d', '1yr'],
                            ),

                            const SizedBox(height: 16),

                            // ─ Max emails slider ─
                            _buildSliderSection(
                              context: context,
                              label: 'Max emails',
                              icon: Icons.email_rounded,
                              valueLabel: emailsLabel,
                              accentColor: const Color(0xFF10B981),
                              surfaceBg: surfaceBg,
                              textPrimary: textPrimary,
                              textSecondary: textSecondary,
                              isDark: isDark,
                              sliderWidget: SliderTheme(
                                data: _premiumSliderTheme(context, const Color(0xFF10B981)),
                                child: Slider(
                                  value: _maxEmails.toDouble(),
                                  min: 5,
                                  max: 50,
                                  divisions: 9,
                                  label: emailsLabel,
                                  onChanged: (v) => setState(() {
                                    final raw = v.round();
                                    final snapped = emailSnaps.reduce((a, b) =>
                                        (a - raw).abs() < (b - raw).abs() ? a : b);
                                    _maxEmails = (raw - snapped).abs() < 3 ? snapped : raw;
                                  }),
                                ),
                              ),
                              ticks: const ['5', '10', '20', '30', '50'],
                            ),

                            const SizedBox(height: 16),
                            const Divider(height: 24),
                            
                            // ─ LLM Provider Dropdown ─
                            Text(
                              'AI Parsing Settings',
                              style: TextStyle(
                                color: textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<AIProvider>(
                              value: localProvider,
                              dropdownColor: surfaceBg,
                              style: TextStyle(color: textPrimary, fontSize: 14),
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: surfaceBg,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(color: textSecondary.withOpacity(0.2)),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(color: textSecondary.withOpacity(0.15)),
                                ),
                              ),
                              items: [
                                DropdownMenuItem(
                                  value: AIProvider.gemini,
                                  child: Text('Google Gemini (Cloud)', style: TextStyle(color: textPrimary)),
                                ),
                                DropdownMenuItem(
                                  value: AIProvider.groq,
                                  child: Text('Groq API (Cloud)', style: TextStyle(color: textPrimary)),
                                ),
                                DropdownMenuItem(
                                  value: AIProvider.ollama,
                                  child: Text('Ollama (Local LLM)', style: TextStyle(color: textPrimary)),
                                ),
                              ],
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() {
                                    localProvider = val;
                                  });
                                }
                              },
                            ),

                            if (localProvider == AIProvider.groq) ...[
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: groqApiKeyController,
                                obscureText: true,
                                style: TextStyle(color: textPrimary, fontSize: 14),
                                decoration: InputDecoration(
                                  labelText: 'Groq API Key',
                                  labelStyle: TextStyle(color: textSecondary, fontSize: 12),
                                  hintText: 'gsk_...',
                                  hintStyle: TextStyle(color: textSecondary.withOpacity(0.5), fontSize: 12),
                                  filled: true,
                                  fillColor: surfaceBg,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ],



                            if (localProvider == AIProvider.ollama) ...[
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: ollamaUrlController,
                                style: TextStyle(color: textPrimary, fontSize: 14),
                                decoration: InputDecoration(
                                  labelText: 'Ollama Host URL',
                                  labelStyle: TextStyle(color: textSecondary, fontSize: 12),
                                  filled: true,
                                  fillColor: surfaceBg,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.amber.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Colors.amber.withOpacity(0.3)),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 16),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Ensure Ollama is running locally and CORS is enabled via OLLAMA_ORIGINS="*".',
                                        style: TextStyle(fontSize: 10, color: textPrimary.withOpacity(0.85)),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],


                            const SizedBox(height: 16),

                            // ─ Info card ─
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: accentColor.withOpacity(isDark ? 0.12 : 0.06),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: accentColor.withOpacity(0.2),
                                  width: 1,
                                ),
                              ),
                              child: Column(
                                children: [
                                  _infoRow(Icons.picture_as_pdf_rounded, 'Scans Gmail for PDF bank statements', textSecondary),
                                  const SizedBox(height: 6),
                                  _infoRow(Icons.auto_awesome_rounded, 'AI extracts transactions automatically', textSecondary),
                                  const SizedBox(height: 6),
                                  _infoRow(Icons.lock_rounded, 'Encrypted PDFs handled with saved passwords', textSecondary),
                                ],
                              ),
                            ),

                            const SizedBox(height: 20),

                            // ─ Action buttons ─
                            Row(
                              children: [
                                Expanded(
                                  child: TextButton(
                                    onPressed: () => Navigator.of(dialogContext).pop(),
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                        side: BorderSide(
                                          color: textSecondary.withOpacity(0.3),
                                        ),
                                      ),
                                    ),
                                    child: Text(
                                      'Cancel',
                                      style: TextStyle(color: textSecondary, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  flex: 2,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [accentColor, const Color(0xFF8B5CF6)],
                                      ),
                                      borderRadius: BorderRadius.circular(14),
                                      boxShadow: [
                                        BoxShadow(
                                          color: accentColor.withOpacity(0.4),
                                          blurRadius: 12,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: ElevatedButton.icon(
                                      icon: const Icon(Icons.sync_rounded, size: 18, color: Colors.white),
                                      label: const Text(
                                        'Start Sync',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 15,
                                        ),
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.transparent,
                                        shadowColor: Colors.transparent,
                                        padding: const EdgeInsets.symmetric(vertical: 14),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(14),
                                        ),
                                      ),
                                      onPressed: () async {
                                        // Save configurations before closing
                                        await AIConfig.saveConfiguration(
                                          localProvider,
                                          ollamaUrlController.text.trim(),
                                          ollamaModelController.text.trim(),
                                          groqKey: groqApiKeyController.text.trim(),
                                          groqMod: groqModelController.text.trim(),
                                        );

                                        final days = _selectedDays;
                                        final maxEmails = _maxEmails;
                                        Navigator.of(dialogContext).pop();
                                        _syncDataFromGmail(context, ref,
                                            lookbackDays: days, maxEmails: maxEmails);
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // Helper: premium SliderThemeData with gradient thumb + active track
  // ─────────────────────────────────────────────────────────────────────
  SliderThemeData _premiumSliderTheme(BuildContext context, Color accent) {
    return SliderTheme.of(context).copyWith(
      trackHeight: 5,
      activeTrackColor: accent,
      inactiveTrackColor: accent.withOpacity(0.18),
      thumbColor: Colors.white,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
      overlayColor: accent.withOpacity(0.18),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
      valueIndicatorShape: const PaddleSliderValueIndicatorShape(),
      valueIndicatorColor: accent,
      valueIndicatorTextStyle: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w700,
        fontSize: 12,
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // Helper: slider section with label, value chip, slider, and tick marks
  // ─────────────────────────────────────────────────────────────────────
  Widget _buildSliderSection({
    required BuildContext context,
    required String label,
    required IconData icon,
    required String valueLabel,
    required Color accentColor,
    required Color surfaceBg,
    required Color textPrimary,
    required Color textSecondary,
    required bool isDark,
    required Widget sliderWidget,
    required List<String> ticks,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      decoration: BoxDecoration(
        color: surfaceBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accentColor.withOpacity(0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(icon, size: 16, color: accentColor),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: textPrimary,
                    ),
                  ),
                ],
              ),
              // Animated value chip
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: accentColor.withOpacity(0.4), width: 1),
                ),
                child: Text(
                  valueLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: accentColor,
                  ),
                ),
              ),
            ],
          ),
          // Slider
          sliderWidget,
          // Tick labels
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: ticks
                  .map((t) => Text(
                        t,
                        style: TextStyle(fontSize: 9, color: textSecondary),
                      ))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  // Helper: info row in the info card
  Widget _infoRow(IconData icon, String text, Color textColor) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 13, color: textColor),
        const SizedBox(width: 7),
        Expanded(
          child: Text(text, style: TextStyle(fontSize: 11, color: textColor, height: 1.4)),
        ),
      ],
    );
  }


  void _syncDataFromGmail(BuildContext context, WidgetRef ref, {int lookbackDays = 90, int maxEmails = 10}) async {
    final authState = ref.read(authStateProvider);
    if (!authState.isAuthenticated || authState.user == null) {
      GlobalMessageService.showError('Please log in first');
      return;
    }
    if (authState.user!.id == 'guest') {
      GlobalMessageService.showError('Gmail sync isn\'t available in guest mode. Sign in with Google to sync.');
      return;
    }

    // ── STEP 1: Get access token — platform-aware
    // On WEB: reuse the Supabase provider token from the existing Google OAuth session.
    //   google_sign_in on web throws UnimplementedError for authenticate().
    // On NATIVE: use GoogleSignIn.instance.authenticate() normally.
    String? accessToken;

    // Native GoogleSignInAccount — hoisted so it's accessible after auth
    // for the Phase 2 alert email pipeline.
    GoogleSignInAccount? googleAccount;

    if (kIsWeb) {
      // Web: Supabase stores the Google provider token in the session right after
      // OAuth redirect. On subsequent page loads it may be null, so we also check
      // SharedPreferences where auth_provider.dart caches it.
      final session = supabase_lib.Supabase.instance.client.auth.currentSession;
      accessToken = session?.providerToken;

      if (accessToken == null || accessToken.isEmpty) {
        // Fallback: read from SharedPreferences (cached on first login)
        final prefs = await SharedPreferences.getInstance();
        accessToken = prefs.getString('google_provider_token');
        if (accessToken != null && accessToken.isNotEmpty) {
          print('✅ Using cached Google provider token from SharedPreferences (web mode)');
        }
      } else {
        print('✅ Using live Supabase provider token for Gmail (web mode)');
      }

      if (accessToken == null || accessToken.isEmpty) {
        // No token available — user needs to re-login with updated Gmail scopes.
        GlobalMessageService.showError(
          'Gmail access not available. Please sign out and sign in again to grant Gmail permissions.',
        );
        return;
      }
      // kIsWeb path ends here — accessToken is now set from Supabase session/cache
    } else {
      // Native: use GoogleSignIn SDK directly.
      try {
        googleAccount =
            await GoogleSignIn.instance.attemptLightweightAuthentication();
        googleAccount ??= await GoogleSignIn.instance.authenticate(
          scopeHint: [
            'https://www.googleapis.com/auth/gmail.readonly',
            'https://www.googleapis.com/auth/gmail.modify',
            'https://www.googleapis.com/auth/userinfo.profile',
            'https://www.googleapis.com/auth/user.birthday.read',
          ],
        );
        const List<String> gmailScopes = [
          'https://www.googleapis.com/auth/gmail.readonly',
          'https://www.googleapis.com/auth/gmail.modify',
          'https://www.googleapis.com/auth/userinfo.profile',
          'https://www.googleapis.com/auth/user.birthday.read',
        ];
        final authz = await googleAccount.authorizationClient.authorizeScopes(gmailScopes);
        accessToken = authz.accessToken;
        print('✅ Google Sign-In successful: ${googleAccount.email}');
      } on GoogleSignInException catch (e) {
        GlobalMessageService.showError('Google Sign-In failed: ${e.description ?? e.code.toString()}');
        return;
      } catch (e) {
        GlobalMessageService.showError('Google Sign-In failed: $e');
        return;
      }
    }

    // ── STEP 2: Show progress dialog now that auth is done
    BuildContext? dialogContext;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) {
        dialogContext = ctx;
        return const SyncProgressDialog();
      },
    );

    try {
      const List<String> gmailScopes = [
        'https://www.googleapis.com/auth/gmail.readonly',
        'https://www.googleapis.com/auth/gmail.modify',
        'https://www.googleapis.com/auth/userinfo.profile',
        'https://www.googleapis.com/auth/user.birthday.read',
      ];

      // Build authenticated HTTP client from the access token
      final authClient = authenticatedClient(
        http.Client(),
        AccessCredentials(
          AccessToken('Bearer', accessToken!,
              DateTime.now().toUtc().add(const Duration(hours: 1))),
          null,
          gmailScopes,
        ),
      );

      // Set up password input callback
      PasswordInputService.setGlobalPasswordCallback((String bankName, String? hint) async {
        print('🔐 Manual password callback triggered for $bankName');
        if (dialogContext != null && dialogContext!.mounted) {
          Navigator.of(dialogContext!).pop();
          await Future.delayed(const Duration(milliseconds: 200));
        }
        final password = await GlobalPasswordService.requestPassword(bankName, hint: hint);
        if (context.mounted) {
          await Future.delayed(const Duration(milliseconds: 200));
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (BuildContext ctx) {
              dialogContext = ctx;
              return const SyncProgressDialog();
            },
          );
        }
        return password;
      });

      // Build the pipeline service with the pre-authenticated client
      final gmailApi = gmail.GmailApi(authClient);
      final pdfParsingService = PdfParsingServiceImpl();
      final gmailService = EnhancedGmailService(
        gmailApi: gmailApi,
        pdfParsingService: pdfParsingService,
        httpClient: authClient,
      );

      final debugService = DataPipelineDebugService();
      debugService.injectGmailService(gmailService);

      debugService.onCardUrlRequired = ({
        required String bankName,
        required String cardVariant,
        required String emailSubject,
        String? suggestedUrl,
      }) async {
        return showCardUrlInputDialog(
          context: context,
          bankName: bankName,
          cardVariant: cardVariant,
          emailSubject: emailSubject,
          suggestedUrl: suggestedUrl,
        );
      };

      // ── STEP 3: Run the pipeline
      print('🔧 Starting sync (lookback: ${lookbackDays}d, maxEmails: $maxEmails)...');
      final customStartDate = DateTime.now().subtract(Duration(days: lookbackDays));
      final syncResult = await debugService.debugSequentialUserFlow(
        authState.user!.id,
        maxEmails,
        customStartDate,
      );

      // Close progress dialog and show result
      if (dialogContext != null && dialogContext!.mounted) {
        Navigator.of(dialogContext!).pop();
        final txCount = syncResult['transactionsStored'] ?? 0;
        final emailCount = syncResult['emailsProcessed'] ?? 0;
        final successMsg = txCount > 0
            ? 'Sync complete! Imported $txCount transactions from $emailCount statement(s).'
            : 'Sync complete! ${emailCount > 0 ? "$emailCount email(s) processed." : "No new statements found."}';
        GlobalMessageService.showSuccess(successMsg);
        _loadData();
        ref.invalidate(availableCreditProvider);
        ref.invalidate(statementRewardsTotalProvider);
      }

      // ── STEP 4 (Phase 2): Run alert email sync in the background ─────────
      // Native-only: requires a GoogleSignInAccount. Runs silently after the
      // main PDF pipeline so it doesn't block the user-visible progress dialog.
      if (!kIsWeb && googleAccount != null) {
        final alertSyncService = ref.read(alertEmailSyncServiceProvider);
        alertSyncService.sync(
          account: googleAccount,
          userId: authState.user!.id,
          lookback: const Duration(days: 7),
        ).then((summary) {
          if (summary.transactionsInserted > 0) {
            print('⚡ Alert sync: +${summary.transactionsInserted} near-realtime transactions added.');
            _loadData();
            ref.invalidate(availableCreditProvider);
          }
        }).catchError((e) {
          // Alert sync errors are non-fatal; log but don't surface to user.
          print('⚠️  Alert email sync failed (non-fatal): $e');
        });
      }
    } catch (error, stack) {
      print('❌ Sync failed: $error\n$stack');
      if (dialogContext != null && dialogContext!.mounted) {
        Navigator.of(dialogContext!).pop();
      }
      
      final errStr = error.toString();
      if (errStr.contains('401') || 
          errStr.contains('Unauthorized') || 
          errStr.contains('Invalid Credentials') ||
          errStr.contains('invalid_grant')) {
        print('⚠️ Expired Google token detected. Clearing SharedPreferences token cached value...');
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove('google_provider_token');
        } catch (e) {
          print('Error clearing token: $e');
        }
        GlobalMessageService.showError(
          'Google / Gmail session expired. Please sign out and sign in again to refresh Google permissions.',
        );
      } else {
        GlobalMessageService.showError('Sync failed: $error');
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

    // Capture navigator BEFORE the async gap so we can always dismiss
    // the dialog even if the widget rebuilds or unmounts during deletion.
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogCtx) {
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
      final success = await UserDataDeletionService.deleteAllUserData(userId);
      print('✅ Deletion process completed with success: $success');

      // Always dismiss — we captured the navigator before the await
      if (navigator.canPop()) navigator.pop();

      if (success) {
        GlobalMessageService.showSuccess('All data deleted successfully! (User profile preserved)');
        _loadData();
      } else {
        GlobalMessageService.showError('Failed to delete some data. Please try again.');
      }

    } catch (error) {
      print('❌ Error during deletion: $error');
      if (navigator.canPop()) navigator.pop();
      GlobalMessageService.showError('Delete failed: ${error.toString()}');
    }
  }



  /// "This Month" summary — 4 stat mini-cards: Spending, Rewards, Active Cards, Savings Rate
  Widget _buildThisMonthSection(BuildContext context, WidgetRef ref) {
    final monthlySpending = ref.watch(monthlySpendingProvider);
    final txRewards = ref.watch(monthlyRewardsProvider);
    final statementRewardsAsync = ref.watch(statementRewardsTotalProvider);
    final statementRewards = statementRewardsAsync.whenOrNull(data: (v) => v) ?? 0.0;
    final monthlyRewards = txRewards + statementRewards;
    final activeCards = ref.watch(activeCardsProvider);
    final savingsRate = monthlySpending > 0
        ? (monthlyRewards / monthlySpending * 100)
        : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('This Month', style: AppTextStyles.heading3),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildThisMonthCard(
                context,
                'Spending',
                monthlySpending > 0
                    ? '₹${_formatAmount(monthlySpending)}'
                    : '₹0',
                'This month',
                Icons.account_balance_wallet_outlined,
                const Color(0xFF6C63FF),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildThisMonthCard(
                context,
                'Rewards',
                monthlyRewards > 0
                    ? '₹${monthlyRewards.toStringAsFixed(0)}'
                    : '₹0',
                'Earned',
                Icons.stars_outlined,
                const Color(0xFF00D4AA),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildThisMonthCard(
                context,
                'Cards',
                '${activeCards.length}',
                'Active',
                Icons.credit_card_outlined,
                const Color(0xFF4DB6FF),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildThisMonthCard(
                context,
                'Savings',
                '${savingsRate.toStringAsFixed(1)}%',
                'Rate',
                Icons.trending_up,
                const Color(0xFFFFB547),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildThisMonthCard(
    BuildContext context,
    String title,
    String value,
    String subtitle,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0C152B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withValues(alpha: 0.2),
          width: 1.5,
        ),
        boxShadow: AppTheme.neonGlow(color: color, opacity: 0.08, blurRadius: 10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: GoogleFonts.spaceGrotesk(
                  color: Colors.white54,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: GoogleFonts.spaceGrotesk(
              color: color,
              fontSize: 22,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
            ),
          ),
          Text(
            subtitle,
            style: GoogleFonts.plusJakartaSans(
              color: Colors.white38,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  String _formatAmount(double amount) {
    if (amount >= 100000) return '${(amount / 100000).toStringAsFixed(1)}L';
    if (amount >= 1000) return '${(amount / 1000).toStringAsFixed(1)}K';
    return amount.toStringAsFixed(0);
  }

  /// Wraps the SmartTransactionAnalyzer widget (reuses existing code)
  Widget _buildSmartAnalyzerSection(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    return SmartTransactionAnalyzer(userId: authState.user?.id);
  }

  Widget _buildQuickActionsSection(BuildContext context, WidgetRef ref) {

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quick Actions',
          style: AppTextStyles.heading3,
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final cols = constraints.maxWidth > 600 ? 6 : 3;
            return GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: cols,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.0,
              children: [
                _buildQuickActionItem(
                  context,
                  'Sync Gmail',
                  Icons.sync,
                  Theme.of(context).colorScheme.primary,
                  () => _showSyncDataDialog(context, ref),
                ),
                _buildQuickActionItem(
                  context,
                  'Add Card',
                  Icons.add_card,
                  Colors.amber,
                  () => Navigator.of(context).pushNamed('/add-card'),
                ),
                _buildQuickActionItem(
                  context,
                  'Advisor AI',
                  Icons.lightbulb_outline,
                  Colors.greenAccent,
                  () => Navigator.of(context).pushNamed('/enhanced-transaction-advisor'),
                ),
                _buildQuickActionItem(
                  context,
                  'Ledger',
                  Icons.receipt_long,
                  Colors.purpleAccent,
                  () => Navigator.of(context).pushNamed('/statements'),
                ),
                _buildQuickActionItem(
                  context,
                  'Benefits',
                  Icons.card_giftcard,
                  Colors.tealAccent,
                  () => Navigator.of(context).pushNamed('/benefits'),
                ),
                _buildQuickActionItem(
                  context,
                  'Clear Data',
                  Icons.delete_forever_outlined,
                  AppTheme.errorColor,
                  () => _showDeleteAllDataDialog(context, ref),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildQuickActionItem(
    BuildContext context,
    String label,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0C152B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withValues(alpha: 0.2),
          width: 1.5,
        ),
        boxShadow: AppTheme.neonGlow(color: color, opacity: 0.08, blurRadius: 10),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    color: color,
                    size: 18,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  label.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.spaceGrotesk(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
        // Responsive: 3 cards in a row on wide screens, wrapped on narrow screens
        LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 480;
            if (isNarrow) {
              // Stack 2 cards on top, 1 centered below on very narrow screens
              return Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: _buildTotalCreditCard(context, ref)),
                      const SizedBox(width: 12),
                      Expanded(child: _buildAvailableCreditCard(context, ref)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildMonthlyRewardsCard(context, ref),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: _buildTotalCreditCard(context, ref)),
                const SizedBox(width: 12),
                Expanded(child: _buildAvailableCreditCard(context, ref)),
                const SizedBox(width: 12),
                Expanded(child: _buildMonthlyRewardsCard(context, ref)),
              ],
            );
          },
        ),
        // Phase 3: Reward nudge banner
        _buildRewardNudgesBanner(context, ref),
      ],
    );
  }

  Widget _buildTotalCreditCard(BuildContext context, WidgetRef ref) {
    final totalCreditLimit = ref.watch(totalCreditLimitProvider);
    final displayStr = totalCreditLimit >= 100000
        ? '₹${(totalCreditLimit / 100000).toStringAsFixed(1)}L'
        : totalCreditLimit >= 1000
            ? '₹${(totalCreditLimit / 1000).toStringAsFixed(0)}K'
            : '₹${totalCreditLimit.toStringAsFixed(0)}';
    return _buildStatCard(
      context,
      'Total Credit',
      displayStr,
      Icons.account_balance_wallet_outlined,
      const Color(0xFF6C63FF),
    );
  }

  Widget _buildAvailableCreditCard(BuildContext context, WidgetRef ref) {
    final availableCreditAsync = ref.watch(availableCreditProvider);
    return availableCreditAsync.when(
      data: (available) {
        final displayStr = available >= 100000
            ? '₹${(available / 100000).toStringAsFixed(1)}L'
            : available >= 1000
                ? '₹${(available / 1000).toStringAsFixed(0)}K'
                : '₹${available.toStringAsFixed(0)}';
        return _buildStatCard(
          context,
          'Available Credit',
          displayStr,
          Icons.credit_score_outlined,
          const Color(0xFF00D4AA),
        );
      },
      loading: () => _buildStatCard(
        context, 'Available Credit', '—',
        Icons.credit_score_outlined, const Color(0xFF00D4AA),
      ),
      error: (_, __) => _buildStatCard(
        context, 'Available Credit', '—',
        Icons.credit_score_outlined, const Color(0xFF00D4AA),
      ),
    );
  }

  Widget _buildMonthlyRewardsCard(BuildContext context, WidgetRef ref) {
    // Combine per-transaction rewards with statement-level rewards
    final txRewards = ref.watch(monthlyRewardsProvider);
    final statementRewardsAsync = ref.watch(statementRewardsTotalProvider);
    final statementRewards = statementRewardsAsync.whenOrNull(data: (v) => v) ?? 0.0;
    final total = txRewards + statementRewards;
    return _buildStatCard(
      context,
      'Monthly Rewards',
      total > 0 ? '₹${total.toStringAsFixed(0)}' : '—',
      Icons.star_outline_rounded,
      const Color(0xFFFFB547),
    );
  }



  // ─────────────────────────────────────────────────────────────────────
  // Phase 3: Reward Nudges Banner
  // ─────────────────────────────────────────────────────────────────────
  Widget _buildRewardNudgesBanner(BuildContext context, WidgetRef ref) {
    final insightsAsync = ref.watch(rewardInsightsProvider);
    return insightsAsync.when(
      data: (insights) {
        if (insights.isEmpty) return const SizedBox.shrink();
        final top = insights.first;
        // Color by priority
        final Color accentColor = top.priority == 'urgent'
            ? const Color(0xFFFF4D4D)
            : top.priority == 'high'
                ? const Color(0xFFFFB547)
                : const Color(0xFF00D4AA);
        return Padding(
          padding: const EdgeInsets.only(top: 14),
          child: GestureDetector(
            onTap: () {
              // Navigate to notifications screen
              Navigator.pushNamed(context, '/notifications');
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    accentColor.withValues(alpha: 0.18),
                    accentColor.withValues(alpha: 0.06),
                  ],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: accentColor.withValues(alpha: 0.45),
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      top.priority == 'urgent'
                          ? Icons.warning_amber_rounded
                          : top.type == InsightType.highValuePoints
                              ? Icons.monetization_on_outlined
                              : Icons.star_rounded,
                      color: accentColor,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          top.title,
                          style: GoogleFonts.spaceGrotesk(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          top.body,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.spaceGrotesk(
                            color: Colors.white70,
                            fontSize: 11,
                          ),
                        ),
                        if (insights.length > 1)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              '+${insights.length - 1} more reward alert${insights.length > 2 ? "s" : ""}',
                              style: GoogleFonts.spaceGrotesk(
                                color: accentColor,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: accentColor.withValues(alpha: 0.8),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
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
