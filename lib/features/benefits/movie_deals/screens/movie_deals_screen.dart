// lib/features/benefits/movie_deals/screens/movie_deals_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme/app_theme.dart';
import '../domain/movie_platform_aliases.dart';
import '../domain/movie_ticket_request.dart';
import 'movie_deals_results.dart';

class MovieDealsScreen extends ConsumerStatefulWidget {
  const MovieDealsScreen({super.key});

  @override
  ConsumerState<MovieDealsScreen> createState() => _MovieDealsScreenState();
}

class _MovieDealsScreenState extends ConsumerState<MovieDealsScreen> {
  int _tickets = 2;
  double _price = 250;
  String? _selectedPlatform;
  String? _selectedCinema;
  MovieTicketRequest? _submittedRequest;

  // Design spec §8 correction — sourced from the canonical registry
  // (movie_platform_aliases.dart), never a hardcoded guess at what
  // "sounds right" for movies. toSet().toList() dedupes "Zomato" (which
  // both "zomato" and "district" alias to) into one entry.
  static final _platforms = moviePlatformAliases.values.toSet().toList()..sort();
  static const _cinemas = ['PVR Cinemas', 'INOX', 'Cinepolis', 'Moviemax', 'SRS Cinemas', 'Wave Cinemas'];

  static const _minTickets = 1;
  static const _maxTickets = 20;
  static const _priceStep = 25.0;
  static const _minPrice = 25.0;

  double get _total => _tickets * _price;

  void _submit() {
    setState(() {
      _submittedRequest = MovieTicketRequest(
        numberOfTickets: _tickets,
        pricePerTicket: _price,
        preferredPlatform: _selectedPlatform,
        preferredCinema: _selectedCinema,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 1024;
    final deck = _InputDeck(
      tickets: _tickets,
      price: _price,
      total: _total,
      platforms: _platforms,
      cinemas: _cinemas,
      selectedPlatform: _selectedPlatform,
      selectedCinema: _selectedCinema,
      onTicketsChanged: (v) => setState(() => _tickets = v.clamp(_minTickets, _maxTickets)),
      onPriceChanged: (v) => setState(() => _price = v < _minPrice ? _minPrice : v),
      priceStep: _priceStep,
      onPlatformChanged: (v) => setState(() => _selectedPlatform = v),
      onCinemaChanged: (v) => setState(() => _selectedCinema = v),
      onSubmit: _submit,
    );
    // Split so the left column can stack the form above "You own" results
    // and the right column shows "Overall" on its own — confirmed layout:
    // "input form + below that You Own | Overall on the right." Both watch
    // the same provider, so this never doubles the actual search work.
    final ownedResults = _submittedRequest == null
        ? const SizedBox.shrink()
        : MovieDealsResults(request: _submittedRequest!, slot: ResultsSlot.owned);
    final overallResults = _submittedRequest == null
        ? const SizedBox.shrink()
        : MovieDealsResults(request: _submittedRequest!, slot: ResultsSlot.overall);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 20),
          if (isDesktop)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        deck.animate(delay: 80.ms).fadeIn().slideX(begin: -0.03),
                        const SizedBox(height: 20),
                        ownedResults.animate(delay: 140.ms).fadeIn().slideX(begin: -0.03),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(
                    flex: 3,
                    child: overallResults.animate(delay: 140.ms).fadeIn().slideX(begin: 0.03),
                  ),
                ],
              ),
            )
          else ...[
            deck.animate(delay: 80.ms).fadeIn().slideY(begin: 0.03),
            const SizedBox(height: 20),
            ownedResults,
            const SizedBox(height: 20),
            overallResults,
          ],
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
            const Icon(Icons.local_movies_outlined, size: 24, color: AppColors.neonCyan),
            const SizedBox(width: 12),
            Text(
              'MOVIE DEALS',
              style: GoogleFonts.spaceGrotesk(
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
                fontSize: 16,
                color: AppColors.textPrimary,
              ),
            ),
            const Spacer(),
            const _LivePulse(),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Every offer type gets the proof it actually has — redemptions used, milestone progress, '
          'or an honest reward rate — never one generic confidence label for all six.',
          style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 12, height: 1.4),
        ),
      ],
    ).animate().fadeIn(duration: 300.ms);
  }
}

class _LivePulse extends StatefulWidget {
  const _LivePulse();

  @override
  State<_LivePulse> createState() => _LivePulseState();
}

class _LivePulseState extends State<_LivePulse> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FadeTransition(
          opacity: Tween(begin: 1.0, end: 0.35).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut)),
          child: Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: AppColors.neonCyan,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: AppColors.neonCyan, blurRadius: 6)],
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          'READY',
          style: GoogleFonts.spaceGrotesk(fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.6, color: AppColors.neonCyan),
        ),
      ],
    );
  }
}

class _InputDeck extends StatelessWidget {
  const _InputDeck({
    required this.tickets,
    required this.price,
    required this.total,
    required this.platforms,
    required this.cinemas,
    required this.selectedPlatform,
    required this.selectedCinema,
    required this.onTicketsChanged,
    required this.onPriceChanged,
    required this.onPlatformChanged,
    required this.onCinemaChanged,
    required this.onSubmit,
    required this.priceStep,
  });

  final int tickets;
  final double price;
  final double total;
  final List<String> platforms;
  final List<String> cinemas;
  final String? selectedPlatform;
  final String? selectedCinema;
  final ValueChanged<int> onTicketsChanged;
  final ValueChanged<double> onPriceChanged;
  final double priceStep;
  final ValueChanged<String?> onPlatformChanged;
  final ValueChanged<String?> onCinemaChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: AppColors.surface3),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -60,
            right: -30,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [AppColors.violet.withValues(alpha: 0.10), Colors.transparent],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'TICKET SPECIFICATIONS',
                  style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold, color: AppColors.textMuted, fontSize: 10, letterSpacing: 1.0),
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _Stepper(
                        label: 'Tickets',
                        value: '$tickets',
                        onDecrement: () => onTicketsChanged(tickets - 1),
                        onIncrement: () => onTicketsChanged(tickets + 1),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _Stepper(
                        label: 'Price / ticket',
                        value: '₹${price.toStringAsFixed(0)}',
                        onDecrement: () => onPriceChanged(price - priceStep),
                        onIncrement: () => onPriceChanged(price + priceStep),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _DeckDropdown(
                        label: 'Platform',
                        value: selectedPlatform,
                        options: platforms,
                        onChanged: onPlatformChanged,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _DeckDropdown(
                        label: 'Cinema',
                        value: selectedCinema,
                        options: cinemas,
                        onChanged: onCinemaChanged,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, size: 12, color: AppColors.textMuted),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Cinema filtering is not yet supported — no benefit data is tied to a specific chain.',
                          style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 9.5),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVoid,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: AppColors.surface3),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('BASE AMOUNT', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold, color: AppColors.textSecondary, fontSize: 10, letterSpacing: 0.5)),
                      Text(
                        '₹${total.toStringAsFixed(0)}',
                        style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold, color: AppColors.neonCyan, fontSize: 18),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: total > 0 ? onSubmit : null,
                    icon: const Icon(Icons.bolt, color: Colors.black, size: 16),
                    label: Text(
                      'OPTIMIZE DEALS',
                      style: GoogleFonts.spaceGrotesk(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.0, color: Colors.black),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.neonCyan,
                      disabledBackgroundColor: AppColors.surface3,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.label,
    required this.value,
    required this.onDecrement,
    required this.onIncrement,
  });

  final String label;
  final String value;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceVoid,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.surface3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: GoogleFonts.spaceGrotesk(fontSize: 9, color: AppColors.textMuted, letterSpacing: 0.4)),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(value, style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold, fontSize: 17, color: AppColors.neonCyan)),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _StepButton(icon: Icons.remove, onTap: onDecrement),
                  const SizedBox(width: 4),
                  _StepButton(icon: Icons.add, onTap: onIncrement),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface1,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), border: Border.all(color: AppColors.surface3)),
          child: Icon(icon, size: 13, color: AppColors.textSecondary),
        ),
      ),
    );
  }
}

class _DeckDropdown extends StatelessWidget {
  const _DeckDropdown({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String? value;
  final List<String> options;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      dropdownColor: AppColors.surface1,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      ),
      style: GoogleFonts.spaceGrotesk(fontSize: 10, color: AppColors.textPrimary),
      items: [
        DropdownMenuItem<String>(
          value: null,
          child: Text('ANY', overflow: TextOverflow.ellipsis, style: GoogleFonts.spaceGrotesk(fontSize: 10, color: AppColors.textSecondary)),
        ),
        ...options.map((o) => DropdownMenuItem<String>(
              value: o,
              child: Text(o.toUpperCase(), overflow: TextOverflow.ellipsis, style: GoogleFonts.spaceGrotesk(fontSize: 10, color: AppColors.textPrimary)),
            )),
      ],
      onChanged: onChanged,
    );
  }
}
