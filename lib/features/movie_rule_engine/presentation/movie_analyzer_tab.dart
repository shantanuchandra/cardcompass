import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cardcompass/features/auth/providers/auth_provider.dart';
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
    ? _scheme.surfaceVariant.withOpacity(0.35)
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
            Icon(
              Icons.local_movies_rounded,
              size: 28,
              color: Theme.of(context).primaryColor,
            ),
            const SizedBox(width: 12),
            Text(
              'Movie Ticket Optimizer',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).primaryColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Get personalized recommendations for maximum savings on movie tickets',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: _scheme.onSurface.withOpacity(0.7),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.blue[50],
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.blue[200]!, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.star, size: 16, color: Colors.blue[600]),
              const SizedBox(width: 4),
              Text(
                'Smart AI-powered optimization',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.blue[700],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInputForm() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Movie Details',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _ticketCountController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(2),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Number of Tickets',
                      prefixIcon: Icon(Icons.confirmation_number),
                      border: OutlineInputBorder(),
                      hintText: 'e.g., 4',
                    ),
                    validator: (v) {
                      final n = int.tryParse(v ?? '');
                      if (n == null || n <= 0) return 'Enter at least 1 ticket';
                      if (n > 10) return 'That’s a lot! Try up to 10';
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
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9]')),
                      LengthLimitingTextInputFormatter(5),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Price per Ticket (₹)',
                      prefixIcon: Icon(Icons.currency_rupee),
                      border: OutlineInputBorder(),
                      hintText: 'e.g., 280',
                    ),
                    validator: (v) {
                      final p = double.tryParse(v ?? '');
                      if (p == null || p <= 0) return 'Enter a valid price';
                      if (p > 3000) return 'Price looks too high';
                      return null;
                    },
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildQuickChips(),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedPlatform,
                    decoration: const InputDecoration(
                      labelText: 'Preferred Platform (Optional)',
                      prefixIcon: Icon(Icons.smartphone),
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Text('Any Platform'),
                      ),
                      ..._platforms.map((platform) => DropdownMenuItem<String>(
                        value: platform,
                        child: Text(platform),
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
                    decoration: const InputDecoration(
                      labelText: 'Preferred Cinema (Optional)',
                      prefixIcon: Icon(Icons.theater_comedy),
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Text('Any Cinema'),
                      ),
                      ..._cinemas.map((cinema) => DropdownMenuItem<String>(
                        value: cinema,
                        child: Text(cinema),
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
            const SizedBox(height: 12),
            _buildTotalAmount(),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Tip: Try 2 or 4 tickets—many BOGO or 50% offers align with even counts.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
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

    // Show the total even if it's 0 to help with debugging
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Total Amount:',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            total > 0 ? '₹${total.toStringAsFixed(0)}' : '₹0',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).primaryColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickChips() {
    // Presets commonly used in India; tweak as per usage insights
    final ticketOptions = [2, 3, 4, 6];
    final priceOptions = [200, 250, 300, 400];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ...ticketOptions.map((n) => ChoiceChip(
                    label: Text('$n tickets'),
                    selected: int.tryParse(_ticketCountController.text) == n,
                    onSelected: (_) {
                      setState(() => _ticketCountController.text = '$n');
                    },
                  )),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ...priceOptions.map((p) => ChoiceChip(
                    label: Text('₹$p'),
                    selected: double.tryParse(_priceController.text) == p.toDouble(),
                    onSelected: (_) {
                      setState(() => _priceController.text = '$p');
                    },
                  )),
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
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.search),
        label: Text(
          isLoading
              ? 'Analyzing...'
              : total > 0
                  ? '🎬 Find Best Deals • ₹${total.toStringAsFixed(0)}'
                  : '🎬 Find Best Deals',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
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
    return Row(
      children: [
        Icon(
          recommendation.hasRecommendations 
              ? Icons.recommend_rounded 
              : Icons.info_outline,
          color: recommendation.hasRecommendations 
              ? _onSuccessContainer 
              : Colors.orange[600],
          size: 28,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                recommendation.hasRecommendations 
                    ? '🎉 Optimized Strategy Found!' 
                    : 'No Special Offers Found',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: recommendation.hasRecommendations 
                      ? _onSuccessContainer 
                      : Colors.orange[600],
                ),
              ),
              if (recommendation.hasRecommendations && recommendation.savingsPercentage > 0)
                Text(
                  'Save ${recommendation.savingsPercentage.toStringAsFixed(1)}% on your movie tickets!',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: _onSuccessContainer,
                    fontWeight: FontWeight.w500,
                  ),
                )
              else
                Text(
                  recommendation.explanation,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: _scheme.onSurface.withOpacity(0.7),
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
          'Recommended Actions (Top ${steps.length}):',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
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
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: _outline),
        borderRadius: BorderRadius.circular(8),
        color: _surfaceCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 12,
                backgroundColor: Theme.of(context).primaryColor,
                child: Text(
                  stepNumber.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${step.ticketCount} tickets via ${step.cardName}',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _successContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Save ₹${step.savings.toStringAsFixed(0)}',
                  style: TextStyle(
                    color: _onSuccessContainer,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${step.explanation} on ${step.platform}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: _scheme.onSurface.withOpacity(0.75),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '₹${step.amount.toStringAsFixed(0)} → ₹${step.effectiveAmount.toStringAsFixed(0)}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
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

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red[600],
      ),
    );
  }
}
