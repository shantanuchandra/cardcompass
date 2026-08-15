// lib/features/benefits/movie_deals/screens/movie_deals_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/brand_tokens.dart';
import '../domain/movie_platform_aliases.dart';
import '../domain/movie_ticket_request.dart';
import 'movie_deals_results.dart';

class MovieDealsScreen extends ConsumerStatefulWidget {
  const MovieDealsScreen({super.key});

  @override
  ConsumerState<MovieDealsScreen> createState() => _MovieDealsScreenState();
}

class _MovieDealsScreenState extends ConsumerState<MovieDealsScreen> {
  final _ticketCountController = TextEditingController();
  final _priceController = TextEditingController();
  String? _selectedPlatform;
  String? _selectedCinema;
  MovieTicketRequest? _submittedRequest;

  // Design spec §8 correction — sourced from the canonical registry
  // (movie_platform_aliases.dart), never a hardcoded guess at what
  // "sounds right" for movies. toSet().toList() dedupes "Zomato" (which
  // both "zomato" and "district" alias to) into one entry.
  static final _platforms = moviePlatformAliases.values.toSet().toList()
    ..sort();
  static const _cinemas = [
    'PVR Cinemas',
    'INOX',
    'Cinepolis',
    'Moviemax',
    'SRS Cinemas',
    'Wave Cinemas',
  ];
  static const _ticketOptions = [2, 3, 4, 6];
  static const _priceOptions = [200, 250, 300, 400];

  @override
  void dispose() {
    _ticketCountController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  bool get _formValid {
    final tickets = int.tryParse(_ticketCountController.text);
    final price = double.tryParse(_priceController.text);
    return tickets != null && tickets > 0 && price != null && price > 0;
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 24),
          _buildInputForm(),
          const SizedBox(height: 24),
          _buildOptimizeButton(),
          const SizedBox(height: 24),
          if (_submittedRequest != null)
            MovieDealsResults(request: _submittedRequest!),
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
              color: BrandColors.focusDark,
            ),
            const SizedBox(width: 12),
            Text(
              'MOVIE TICKET OPTIMIZER',
              style: const TextStyle(
                fontFamily: 'Fraunces',
                fontWeight: FontWeight.w600,
                fontSize: 22,
                color: BrandColors.ink,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Query ticket combinations across major platforms and calculate optimal savings route.',
          style: TextStyle(
            fontFamily: 'Manrope',
            color: BrandColors.mutedInk,
            fontSize: 12,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: BrandColors.reward,
            borderRadius: BorderRadius.circular(BrandRadius.label),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.confirmation_number_outlined,
                size: 14,
                color: BrandColors.ink,
              ),
              const SizedBox(width: 4),
              Text(
                'RULES-BASED OFFER CHECK',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 9,
                  color: BrandColors.ink,
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
        color: BrandColors.paper,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: BrandColors.paperDeep),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'TICKET SPECIFICATIONS',
              style: TextStyle(
                fontFamily: 'Manrope',
                fontWeight: FontWeight.bold,
                color: BrandColors.ink,
                fontSize: 11,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ticketCountController,
                    keyboardType: TextInputType.number,
                    style: TextStyle(
                      fontFamily: 'Manrope',
                      color: BrandColors.ink,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(2),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Tickets',
                      prefixIcon: Icon(
                        Icons.confirmation_number_outlined,
                        color: BrandColors.focusDark,
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: _priceController,
                    keyboardType: TextInputType.number,
                    style: TextStyle(
                      fontFamily: 'Manrope',
                      color: BrandColors.ink,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9]')),
                      LengthLimitingTextInputFormatter(5),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Price (₹)',
                      prefixIcon: Icon(
                        Icons.currency_rupee,
                        color: BrandColors.focusDark,
                      ),
                    ),
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
                Expanded(child: _buildPlatformDropdown()),
                const SizedBox(width: 16),
                Expanded(child: _buildCinemaDropdown()),
              ],
            ),
            const SizedBox(height: 20),
            _buildTotalAmount(),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(
                  Icons.info_outline,
                  size: 14,
                  color: BrandColors.mutedInk,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Cinema filtering is not yet supported — no current benefit data is tied to a specific cinema chain.',
                    style: TextStyle(
                      fontFamily: 'Manrope',
                      color: BrandColors.mutedInk,
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlatformDropdown() {
    return DropdownButtonFormField<String>(
      initialValue: _selectedPlatform,
      isExpanded: true,
      dropdownColor: BrandColors.paper,
      decoration: const InputDecoration(
        labelText: 'Platform',
        prefixIcon: Icon(
          Icons.smartphone_outlined,
          color: BrandColors.focusDark,
        ),
      ),
      items: [
        DropdownMenuItem<String>(
          value: null,
          child: Text(
            'ANY PLATFORM',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 10,
              color: BrandColors.mutedInk,
            ),
          ),
        ),
        ..._platforms.map(
          (p) => DropdownMenuItem<String>(
            value: p,
            child: Text(
              p.toUpperCase(),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 10,
                color: BrandColors.ink,
              ),
            ),
          ),
        ),
      ],
      onChanged: (value) => setState(() => _selectedPlatform = value),
    );
  }

  Widget _buildCinemaDropdown() {
    return DropdownButtonFormField<String>(
      initialValue: _selectedCinema,
      isExpanded: true,
      dropdownColor: BrandColors.paper,
      decoration: const InputDecoration(
        labelText: 'Cinema',
        prefixIcon: Icon(
          Icons.theater_comedy_outlined,
          color: BrandColors.focusDark,
        ),
      ),
      items: [
        DropdownMenuItem<String>(
          value: null,
          child: Text(
            'ANY CINEMA',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 10,
              color: BrandColors.mutedInk,
            ),
          ),
        ),
        ..._cinemas.map(
          (c) => DropdownMenuItem<String>(
            value: c,
            child: Text(
              c.toUpperCase(),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 10,
                color: BrandColors.ink,
              ),
            ),
          ),
        ),
      ],
      onChanged: (value) => setState(() => _selectedCinema = value),
    );
  }

  Widget _buildQuickChips() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _ticketOptions.map((n) {
              final selected = int.tryParse(_ticketCountController.text) == n;
              return ChoiceChip(
                label: Text(
                  '$n TICKETS',
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: selected ? Colors.black : BrandColors.mutedInk,
                  ),
                ),
                selectedColor: BrandColors.focusDark,
                backgroundColor: BrandColors.paper,
                selected: selected,
                showCheckmark: false,
                onSelected: (_) =>
                    setState(() => _ticketCountController.text = '$n'),
              );
            }).toList(),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _priceOptions.map((p) {
              final selected =
                  double.tryParse(_priceController.text) == p.toDouble();
              return ChoiceChip(
                label: Text(
                  '₹$p',
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: selected ? Colors.black : BrandColors.mutedInk,
                  ),
                ),
                selectedColor: BrandColors.focusDark,
                backgroundColor: BrandColors.paper,
                selected: selected,
                showCheckmark: false,
                onSelected: (_) => setState(() => _priceController.text = '$p'),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildTotalAmount() {
    final tickets = int.tryParse(_ticketCountController.text) ?? 0;
    final price = double.tryParse(_priceController.text) ?? 0.0;
    final total = tickets * price;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: BrandColors.paper,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: BrandColors.paperDeep),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'TOTAL BASE AMOUNT:',
            style: TextStyle(
              fontFamily: 'Manrope',
              fontWeight: FontWeight.bold,
              color: BrandColors.mutedInk,
              fontSize: 10,
              letterSpacing: 0.5,
            ),
          ),
          Text(
            total > 0 ? '₹${total.toStringAsFixed(0)}' : '₹0',
            style: TextStyle(
              fontFamily: 'Manrope',
              fontWeight: FontWeight.bold,
              color: BrandColors.focusDark,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptimizeButton() {
    final tickets = int.tryParse(_ticketCountController.text) ?? 0;
    final price = double.tryParse(_priceController.text) ?? 0.0;
    final total = tickets * price;
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _formValid
            ? () => setState(() {
                _submittedRequest = MovieTicketRequest(
                  numberOfTickets: tickets,
                  pricePerTicket: price,
                  preferredPlatform: _selectedPlatform,
                  preferredCinema: _selectedCinema,
                );
              })
            : null,
        icon: const Icon(Icons.bolt, color: Colors.black, size: 16),
        label: Text(
          total > 0
              ? 'OPTIMIZE DEALS • ₹${total.toStringAsFixed(0)}'
              : 'OPTIMIZE DEALS',
          style: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0,
            color: Colors.black,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: BrandColors.focusDark,
          disabledBackgroundColor: BrandColors.paperDeep,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
      ),
    );
  }
}
