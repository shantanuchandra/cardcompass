import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cardcompass/features/auth/providers/auth_provider.dart';
import 'package:cardcompass/core/theme.dart';
import '../providers/movie_optimization_provider.dart';
import '../domain/models/movie_ticket_request.dart';
import '../domain/models/movie_recommendation.dart';
import '../domain/models/transaction_step.dart';

/// Movie ticket analyzer tab for the Smart Transaction Advisor
class MovieAnalyzerTab extends ConsumerStatefulWidget {
  const MovieAnalyzerTab({super.key});

  @override
  ConsumerState<MovieAnalyzerTab> createState() => _MovieAnalyzerTabState();
}

class _MovieAnalyzerTabState extends ConsumerState<MovieAnalyzerTab> {
  final _ticketCountController = TextEditingController();
  final _priceController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  // Theme helpers to keep contrast high on dark/light modes
  ColorScheme get _scheme => Theme.of(context).colorScheme;
  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _surfaceCard => _isDark
    ? _scheme.surfaceContainerHighest.withOpacity(0.35)
    : Colors.grey[50]!;
  Color get _outline => _scheme.outline.withOpacity(_isDark ? 0.5 : 0.35);
  Color get _successContainer =>
    _isDark ? Colors.green.shade900.withOpacity(0.35) : Colors.green.shade50;
  Color get _onSuccessContainer =>
    _isDark ? Colors.green.shade200 : Colors.green.shade700;
  
  String? _selectedPlatform;
  String? _selectedCinema;
  
  final List<String> _platforms = [
    'BookMyShow',
    'PVR',
    'INOX',
    'Cinepolis',
    'Moviemax',
  ];
  
  final List<String> _cinemas = [
    'PVR Cinemas',
    'INOX',
    'Cinepolis',
    'Moviemax',
    'SRS Cinemas',
    'Wave Cinemas',
  ];

  @override
  void dispose() {
    _ticketCountController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final optimizationState = ref.watch(movieOptimizationControllerProvider);
    final authState = ref.watch(authStateProvider);
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 24),
          _buildInputForm(),
          const SizedBox(height: 24),
          _buildAnalyzeButton(),
          const SizedBox(height: 24),
          _buildResults(optimizationState),
          const SizedBox(height: 32),
          // NEW: Show all available card-benefit combinations
          if (authState.user != null)
            _buildAllCardBenefitsSection(authState.user!.id),
          const SizedBox(height: 24), // Add bottom padding for better UX
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.local_movies_outlined,
              size: 24,
              color: AppTheme.primaryColor,
            ),
            const SizedBox(width: 12),
            Text(
              'MOVIE TICKET OPTIMIZER',
              style: GoogleFonts.spaceGrotesk(
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
                fontSize: 16,
                color: Colors.white,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Query ticket combinations across major platforms and calculate optimal savings route.',
          style: GoogleFonts.plusJakartaSans(
            color: Colors.white60,
            fontSize: 12,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF0C152B),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.25), width: 1.2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.bolt, size: 14, color: AppTheme.primaryColor),
              const SizedBox(width: 4),
              Text(
                'AI RULE OPTIMIZATION ENGINE',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 9,
                  color: AppTheme.primaryColor,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInputForm() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0C152B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'TICKET SPECIFICATIONS',
                style: GoogleFonts.spaceGrotesk(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  fontSize: 11,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _ticketCountController,
                      keyboardType: TextInputType.number,
                      style: GoogleFonts.plusJakartaSans(color: Colors.white),
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(2),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Tickets',
                        prefixIcon: Icon(Icons.confirmation_number_outlined, color: AppTheme.primaryColor),
                      ),
                      validator: (v) {
                        final n = int.tryParse(v ?? '');
                        if (n == null || n <= 0) return 'Required';
                        if (n > 10) return 'Max 10 tickets';
                        return null;
                      },
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _priceController,
                      keyboardType: TextInputType.number,
                      style: GoogleFonts.plusJakartaSans(color: Colors.white),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9]')),
                        LengthLimitingTextInputFormatter(5),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Price (₹)',
                        prefixIcon: Icon(Icons.currency_rupee, color: AppTheme.primaryColor),
                      ),
                      validator: (v) {
                        final p = double.tryParse(v ?? '');
                        if (p == null || p <= 0) return 'Required';
                        if (p > 3000) return 'Price too high';
                        return null;
                      },
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildQuickChips(),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedPlatform,
                      isExpanded: true,
                      dropdownColor: const Color(0xFF0C152B),
                      decoration: const InputDecoration(
                        labelText: 'Platform',
                        prefixIcon: Icon(Icons.smartphone_outlined, color: AppTheme.primaryColor),
                      ),
                      items: [
                        DropdownMenuItem<String>(
                          value: null,
                          child: Text('ANY PLATFORM',
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.spaceGrotesk(fontSize: 10, color: Colors.white70)),
                        ),
                        ..._platforms.map((platform) => DropdownMenuItem<String>(
                          value: platform,
                          child: Text(platform.toUpperCase(),
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.spaceGrotesk(fontSize: 10, color: Colors.white)),
                        )),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _selectedPlatform = value;
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedCinema,
                      isExpanded: true,
                      dropdownColor: const Color(0xFF0C152B),
                      decoration: const InputDecoration(
                        labelText: 'Cinema',
                        prefixIcon: Icon(Icons.theater_comedy_outlined, color: AppTheme.primaryColor),
                      ),
                      items: [
                        DropdownMenuItem<String>(
                          value: null,
                          child: Text('ANY CINEMA',
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.spaceGrotesk(fontSize: 10, color: Colors.white70)),
                        ),
                        ..._cinemas.map((cinema) => DropdownMenuItem<String>(
                          value: cinema,
                          child: Text(cinema.toUpperCase(),
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.spaceGrotesk(fontSize: 10, color: Colors.white)),
                        )),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _selectedCinema = value;
                        });
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _buildTotalAmount(),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.info_outline, size: 14, color: Colors.white30),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'BOGO and 50% movie offers are commonly optimized with even ticket counts.',
                      style: GoogleFonts.plusJakartaSans(color: Colors.white30, fontSize: 10),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTotalAmount() {
    final tickets = int.tryParse(_ticketCountController.text) ?? 0;
    final price = double.tryParse(_priceController.text) ?? 0.0;
    final total = tickets * price;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF050B18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'TOTAL BASE AMOUNT:',
            style: GoogleFonts.spaceGrotesk(
              fontWeight: FontWeight.bold,
              color: Colors.white60,
              fontSize: 10,
              letterSpacing: 0.5,
            ),
          ),
          Text(
            total > 0 ? '₹${total.toStringAsFixed(0)}' : '₹0',
            style: GoogleFonts.spaceGrotesk(
              fontWeight: FontWeight.bold,
              color: AppTheme.primaryColor,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickChips() {
    final ticketOptions = [2, 3, 4, 6];
    final priceOptions = [200, 250, 300, 400];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ...ticketOptions.map((n) {
                final isSelected = int.tryParse(_ticketCountController.text) == n;
                return ChoiceChip(
                  label: Text(
                    '$n TICKETS',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 9, 
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.black : Colors.white60,
                    ),
                  ),
                  selectedColor: AppTheme.primaryColor,
                  backgroundColor: const Color(0xFF050B18),
                  selected: isSelected,
                  side: BorderSide(
                    color: isSelected ? AppTheme.primaryColor : Colors.white.withValues(alpha: 0.08),
                  ),
                  showCheckmark: false,
                  onSelected: (_) {
                    setState(() => _ticketCountController.text = '$n');
                  },
                );
              }),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ...priceOptions.map((p) {
                final isSelected = double.tryParse(_priceController.text) == p.toDouble();
                return ChoiceChip(
                  label: Text(
                    '₹$p',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 9, 
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.black : Colors.white60,
                    ),
                  ),
                  selectedColor: AppTheme.primaryColor,
                  backgroundColor: const Color(0xFF050B18),
                  selected: isSelected,
                  side: BorderSide(
                    color: isSelected ? AppTheme.primaryColor : Colors.white.withValues(alpha: 0.08),
                  ),
                  showCheckmark: false,
                  onSelected: (_) {
                    setState(() => _priceController.text = '$p');
                  },
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAnalyzeButton() {
    final optimizationState = ref.watch(movieOptimizationControllerProvider);
    final isLoading = optimizationState.isLoading;
    final formValid = _formKey.currentState?.validate() ?? false;
    final tickets = int.tryParse(_ticketCountController.text) ?? 0;
    final price = double.tryParse(_priceController.text) ?? 0.0;
    final total = tickets * price;

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: (!isLoading && formValid) ? _analyzeTickets : null,
        icon: isLoading 
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.black)),
              )
            : const Icon(Icons.bolt, color: Colors.black, size: 16),
        label: Text(
          isLoading
              ? 'CALCULATING ROUTE...'
              : total > 0
                  ? 'OPTIMIZE DEALS • ₹${total.toStringAsFixed(0)}'
                  : 'OPTIMIZE DEALS',
          style: GoogleFonts.spaceGrotesk(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0,
            color: Colors.black,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primaryColor,
          disabledBackgroundColor: Colors.white10,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _buildResults(AsyncValue<MovieRecommendation?> optimizationState) {
    return optimizationState.when(
      data: (recommendation) {
        if (recommendation == null) {
          return const SizedBox.shrink();
        }
        return _buildRecommendationCard(recommendation);
      },
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: CircularProgressIndicator(),
        ),
      ),
      error: (error, stack) => _buildErrorCard(error.toString()),
    );
  }

  Widget _buildRecommendationCard(MovieRecommendation recommendation) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildRecommendationHeader(recommendation),
            const SizedBox(height: 16),
            if (recommendation.hasRecommendations) ...[
              _buildStepsSection(recommendation.topRecommendations),
              const SizedBox(height: 16),
              _buildSavingsSummary(recommendation),
            ] else
              _buildNoRecommendationsMessage(recommendation),
          ],
        ),
      ),
    );
  }

  Widget _buildRecommendationHeader(MovieRecommendation recommendation) {
    final hasRec = recommendation.hasRecommendations;
    final activeColor = hasRec ? AppTheme.successColor : AppTheme.warningColor;
    return Row(
      children: [
        Icon(
          hasRec ? Icons.verified_outlined : Icons.info_outline,
          color: activeColor,
          size: 24,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                hasRec ? 'OPTIMIZED ROUTE GENERATED' : 'NO ACTIVE BOGO OFFERS',
                style: GoogleFonts.spaceGrotesk(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  letterSpacing: 1.0,
                  color: activeColor,
                ),
              ),
              if (hasRec && recommendation.savingsPercentage > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    'TOTAL SAVINGS OF ${recommendation.savingsPercentage.toStringAsFixed(1)}% DETECTED',
                    style: GoogleFonts.spaceGrotesk(
                      color: AppTheme.primaryColor,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                )
              else
                Text(
                  recommendation.explanation,
                  style: GoogleFonts.plusJakartaSans(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStepsSection(List<TransactionStep> steps) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'EXECUTION PROTOCOL:',
          style: GoogleFonts.spaceGrotesk(
            fontWeight: FontWeight.bold,
            color: Colors.white,
            fontSize: 11,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 12),
        ...steps.asMap().entries.map((entry) {
          final index = entry.key;
          final step = entry.value;
          return _buildStepCard(step, index + 1);
        }),
      ],
    );
  }

  Widget _buildStepCard(TransactionStep step, int stepNumber) {
    final isOwned = step.isOwned;
    final cardBorderColor = isOwned 
        ? AppTheme.primaryColor.withValues(alpha: 0.25)
        : AppTheme.secondaryColor.withValues(alpha: 0.25);
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0C152B),
        border: Border.all(color: cardBorderColor, width: 1.2),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: const Color(0xFF050B18),
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.primaryColor, width: 1),
                ),
                child: Center(
                  child: Text(
                    stepNumber.toString(),
                    style: GoogleFonts.spaceGrotesk(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${step.ticketCount} TICKETS VIA ${step.cardName.toUpperCase()}',
                      style: GoogleFonts.spaceGrotesk(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    if (step.bank != null)
                      Text(
                        '${step.bank!.toUpperCase()} • ${step.cardNetwork?.toUpperCase() ?? ""}',
                        style: GoogleFonts.spaceGrotesk(
                          color: Colors.white38,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.successColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.successColor.withValues(alpha: 0.2)),
                ),
                child: Text(
                  'SAVE ₹${step.savings.toStringAsFixed(0)}',
                  style: GoogleFonts.spaceGrotesk(
                    color: AppTheme.successColor,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isOwned 
                      ? AppTheme.successColor.withValues(alpha: 0.1) 
                      : AppTheme.secondaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isOwned 
                        ? AppTheme.successColor.withValues(alpha: 0.2) 
                        : AppTheme.secondaryColor.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isOwned ? Icons.verified_outlined : Icons.add_circle_outline,
                      size: 12,
                      color: isOwned ? AppTheme.successColor : AppTheme.secondaryColor,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isOwned ? 'OWNED INTEGRATION' : 'CATALOG RECOMMENDATION',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                        color: isOwned ? AppTheme.successColor : AppTheme.secondaryColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 12),
          Text(
            '${step.explanation} on ${step.platform}',
            style: GoogleFonts.plusJakartaSans(
              color: Colors.white70,
              fontSize: 11,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '₹${step.amount.toStringAsFixed(0)} → ₹${step.effectiveAmount.toStringAsFixed(0)} EFFECTIVE',
            style: GoogleFonts.spaceGrotesk(
              fontWeight: FontWeight.bold,
              color: Colors.white30,
              fontSize: 10,
            ),
          ),
          
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _handleCardAction(step),
              icon: Icon(isOwned ? Icons.bolt : Icons.add_card, color: Colors.black, size: 14),
              label: Text(
                isOwned ? 'ROUTE TRANSACTION' : 'ACQUIRE THIS CARD',
                style: GoogleFonts.spaceGrotesk(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: isOwned 
                    ? AppTheme.primaryColor 
                    : AppTheme.secondaryColor,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  void _handleCardAction(TransactionStep step) {
    if (step.isOwned) {
      // User owns the card - show confirmation or navigate to transaction entry
      _showCardUsageDialog(step);
    } else {
      // User doesn't own the card - show card details and application info
      _showCardAcquisitionDialog(step);
    }
  }
  
  void _showCardUsageDialog(TransactionStep step) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.credit_card, color: Theme.of(context).primaryColor),
            const SizedBox(width: 12),
            Expanded(
              child: Text('Use ${step.cardName}'),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ready to book ${step.ticketCount} tickets on ${step.platform}?'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your Savings:',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.green[700],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '₹${step.amount.toStringAsFixed(0)} → ₹${step.effectiveAmount.toStringAsFixed(0)}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.green[700],
                    ),
                  ),
                  Text(
                    'Save ₹${step.savings.toStringAsFixed(0)} (${step.savingsPercentage.toStringAsFixed(1)}%)',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.green[600],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Tip: Make sure to use the recommended platform and follow the offer terms.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey[600],
                fontStyle: FontStyle.italic,
              ),
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
              _showSnackbar('Great! Don\'t forget to use ${step.cardName} on ${step.platform}', isSuccess: true);
            },
            child: const Text('Got It!'),
          ),
        ],
      ),
    );
  }
  
  void _showCardAcquisitionDialog(TransactionStep step) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.add_card, color: Colors.orange[600]),
            const SizedBox(width: 12),
            Expanded(
              child: Text('Get ${step.cardName}'),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Potential Savings:',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.orange[700],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '₹${step.savings.toStringAsFixed(0)} on this transaction',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange[700],
                      ),
                    ),
                    Text(
                      step.explanation,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange[600],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Card Details:',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              _buildCardDetailRow('Bank', step.bank ?? 'N/A'),
              _buildCardDetailRow('Network', step.cardNetwork ?? 'N/A'),
              _buildCardDetailRow('Best For', 'Movie Tickets (${step.benefitType})'),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: Colors.blue[700]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This card offers great benefits for movie tickets. Consider applying if you frequently watch movies!',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue[700],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Maybe Later'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              _showSnackbar('Feature coming soon: Apply for ${step.cardName}', isSuccess: true);
              // TODO: Navigate to card application or details page
            },
            icon: const Icon(Icons.open_in_new),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange[600],
              foregroundColor: Colors.white,
            ),
            label: const Text('Learn More'),
          ),
        ],
      ),
    );
  }
  
  Widget _buildCardDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '$label:',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.grey[600],
            ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
  
  void _showSnackbar(String message, {bool isSuccess = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isSuccess ? Colors.green[600] : null,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _buildSavingsSummary(MovieRecommendation recommendation) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surfaceCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _outline),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total Amount:',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(
                '₹${recommendation.totalAmount.toStringAsFixed(0)}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total Savings:',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: _onSuccessContainer,
                ),
              ),
              Text(
                '₹${recommendation.totalSavings.toStringAsFixed(0)}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: _onSuccessContainer,
                ),
              ),
            ],
          ),
          Divider(color: _outline),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Final Amount:',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '₹${recommendation.finalAmount.toStringAsFixed(0)}',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
          if (recommendation.savingsPercentage > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'You save ${recommendation.savingsPercentage.toStringAsFixed(1)}%!',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: _onSuccessContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildNoRecommendationsMessage(MovieRecommendation recommendation) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange[50],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Icon(
            Icons.lightbulb_outline,
            size: 48,
            color: Colors.orange[400],
          ),
          const SizedBox(height: 12),
          Text(
            'Consider These Alternatives:',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '• Use a general cashback card for 1-2% rewards\n'
            '• Check for bank-specific movie offers\n'
            '• Look for platform-specific discount codes\n'
            '• Consider group bookings for better deals',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard(String error) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: Colors.red[400],
            ),
            const SizedBox(height: 12),
            Text(
              'Error Analyzing Tickets',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: Colors.red[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                final user = ref.read(authStateProvider).user;
                if (user != null) {
                  ref.read(movieOptimizationControllerProvider.notifier)
                      .retryOptimization(user.id);
                }
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  void _analyzeTickets() async {
    final tickets = int.tryParse(_ticketCountController.text);
    final price = double.tryParse(_priceController.text);

    if (tickets == null || tickets <= 0) {
      _showError('Please enter a valid number of tickets');
      return;
    }

    if (price == null || price <= 0) {
      _showError('Please enter a valid ticket price');
      return;
    }

    final user = ref.read(authStateProvider).user;
    if (user == null) {
      _showError('Please log in to use this feature');
      return;
    }

    final request = MovieTicketRequest(
      numberOfTickets: tickets,
      pricePerTicket: price,
      preferredCinema: _selectedCinema,
      preferredPlatform: _selectedPlatform,
    );

    await ref.read(movieOptimizationControllerProvider.notifier)
        .optimizeTickets(userId: user.id, request: request);
  }

  Widget _buildAllCardBenefitsSection(String userId) {
    final cardBenefitsAsync = ref.watch(allMovieCardBenefitsProvider(userId));
    
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.credit_card_rounded,
                  size: 24,
                  color: Theme.of(context).primaryColor,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'All Movie Benefits Available',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Browse all card benefits for movie tickets',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: _scheme.onSurface.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 20),
            cardBenefitsAsync.when(
              data: (benefits) {
                if (benefits.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Column(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 64,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No movie benefits found',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                
                return Column(
                  children: [
                    _buildBenefitsSummary(benefits),
                    const SizedBox(height: 16),
                    ...benefits.map((benefit) => _buildCardBenefitTile(benefit)),
                  ],
                );
              },
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(32.0),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (error, stack) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Column(
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 64,
                        color: Colors.red[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Error loading benefits',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        error.toString(),
                        style: Theme.of(context).textTheme.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildBenefitsSummary(List<Map<String, dynamic>> benefits) {
    final ownedCount = benefits.where((b) => b['is_owned'] == true).length;
    final totalCount = benefits.length;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _successContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _onSuccessContainer.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildSummaryItem(
              icon: Icons.credit_card,
              label: 'Total Cards',
              value: totalCount.toString(),
            ),
          ),
          Container(
            width: 1,
            height: 40,
            color: _outline,
          ),
          Expanded(
            child: _buildSummaryItem(
              icon: Icons.check_circle,
              label: 'You Own',
              value: ownedCount.toString(),
              color: Colors.green[700],
            ),
          ),
          Container(
            width: 1,
            height: 40,
            color: _outline,
          ),
          Expanded(
            child: _buildSummaryItem(
              icon: Icons.shopping_bag_outlined,
              label: 'Available',
              value: (totalCount - ownedCount).toString(),
              color: Colors.orange[700],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildSummaryItem({
    required IconData icon,
    required String label,
    required String value,
    Color? color,
  }) {
    return Column(
      children: [
        Icon(icon, size: 24, color: color ?? _onSuccessContainer),
        const SizedBox(height: 8),
        Text(
          value,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: color ?? _onSuccessContainer,
          ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: (color ?? _onSuccessContainer).withOpacity(0.8),
          ),
        ),
      ],
    );
  }
  
  Widget _buildCardBenefitTile(Map<String, dynamic> benefit) {
    final isOwned = benefit['is_owned'] as bool;
    final cardName = benefit['card_name'] as String;
    final bank = benefit['bank'] as String?;
    final network = benefit['card_network'] as String?;
    final benefitTitle = benefit['benefit_title'] as String;
    final benefitDesc = benefit['benefit_description'] as String;
    final platform = benefit['platform'] as String;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(
          color: isOwned ? Colors.green.withOpacity(0.5) : _outline,
          width: isOwned ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(12),
        color: _surfaceCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            cardName,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (isOwned)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.green.withOpacity(0.3),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.check_circle,
                                  size: 14,
                                  color: Colors.green[700],
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Owned',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.green[700],
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    if (bank != null || network != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '${bank ?? ''} ${bank != null && network != null ? '•' : ''} ${network ?? ''}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: _scheme.onSurface.withOpacity(0.6),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.confirmation_number_outlined,
                      size: 16,
                      color: Theme.of(context).primaryColor,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        benefitTitle,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).primaryColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.local_offer_outlined,
                      size: 14,
                      color: _scheme.onSurface.withOpacity(0.6),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      benefitDesc,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.location_on_outlined,
                      size: 14,
                      color: _scheme.onSurface.withOpacity(0.6),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      platform,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _scheme.onSurface.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red[600],
      ),
    );
  }
}
