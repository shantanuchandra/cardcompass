// lib/features/benefits/movie_deals/screens/movie_deals_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
    // Full-width bento layout: the header stays a plain top banner, then
    // the form and every results group become tiles in ONE grid that
    // uses the whole available width — no more segregating the form
    // into its own column. Padding is the page's only width limiter now;
    // there's no BrandContentFrame cap here (this screen has never used
    // one), matching the explicit "full-width on desktop" direction.
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 20),
          _buildFormAndResultsGrid(context),
        ],
      ),
    );
  }

  Widget _buildFormAndResultsGrid(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 1024 ? 3 : (width >= 600 ? 2 : 1);
        const gap = 16.0;
        final unitWidth = (width - gap * (columns - 1)) / columns;
        // The form claims 2 units on a 3-column grid (roomy enough for
        // its two-field rows without forcing them to stack), 1 unit
        // otherwise — same intrinsic-width tile mechanism the results
        // grid itself uses, so the form visually belongs among the tiles
        // rather than reading as a separate sidebar.
        final formSpan = columns >= 3 ? 2 : 1;
        final formWidth = unitWidth * formSpan + gap * (formSpan - 1);

        final formTile = SizedBox(
          width: formWidth,
          child: Container(
            decoration: BoxDecoration(
              color: BrandColors.paper,
              borderRadius: BorderRadius.circular(BrandRadius.overlay),
              border: Border.all(color: BrandColors.paperDeep),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildInputForm(context),
                  const SizedBox(height: 20),
                  _buildOptimizeButton(),
                ],
              ),
            ),
          ),
        );

        if (_submittedRequest == null) {
          return Wrap(children: [formTile]);
        }

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            formTile,
            SizedBox(
              width: width,
              child: MovieDealsResults(request: _submittedRequest!),
            ),
          ],
        );
      },
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.local_movies_outlined,
              size: 24,
              color: BrandColors.focusDark,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Movie ticket optimizer',
                style: const TextStyle(
                  fontFamily: 'Fraunces',
                  fontWeight: FontWeight.w600,
                  fontSize: 22,
                  color: BrandColors.ink,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Answer a few quick questions and we’ll find the clearest eligible saving.',
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
          child: Wrap(
            spacing: 4,
            runSpacing: 2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Icon(
                Icons.confirmation_number_outlined,
                size: 14,
                color: BrandColors.ink,
              ),
              Text(
                'Offers checked against current rules',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 12,
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

  Widget _buildInputForm(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: BrandColors.paper,
        borderRadius: BorderRadius.circular(BrandRadius.overlay),
        border: Border.all(color: BrandColors.paperDeep),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tell us about your booking',
              style: TextStyle(
                fontFamily: 'Manrope',
                fontWeight: FontWeight.bold,
                color: BrandColors.ink,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 18),
            _responsivePair(
              context: context,
              first: Container(
                key: const Key('ticket-count-question'),
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
                    labelText: 'How many tickets?',
                    prefixIcon: Icon(
                      Icons.confirmation_number_outlined,
                      color: BrandColors.focusDark,
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              second: Container(
                key: const Key('ticket-price-question'),
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
                    labelText: 'Price per ticket',
                    prefixIcon: Icon(
                      Icons.currency_rupee,
                      color: BrandColors.focusDark,
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _buildQuickChips(context),
            const SizedBox(height: 20),
            _responsivePair(
              context: context,
              first: _buildPlatformDropdown(),
              second: _buildCinemaDropdown(),
            ),
            const SizedBox(height: 20),
            _buildTotalAmount(context),
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
                      fontSize: 12,
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

  Widget _responsivePair({
    required BuildContext context,
    required Widget first,
    required Widget second,
  }) {
    final shouldStack =
        MediaQuery.sizeOf(context).width < 600 ||
        MediaQuery.textScalerOf(context).scale(14) >= 21;
    if (shouldStack) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [first, const SizedBox(height: 16), second],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: first),
        const SizedBox(width: 16),
        Expanded(child: second),
      ],
    );
  }

  Widget _buildPlatformDropdown() {
    return DropdownButtonFormField<String>(
      initialValue: _selectedPlatform,
      isExpanded: true,
      dropdownColor: BrandColors.paper,
      decoration: const InputDecoration(
        labelText: 'Where are you booking?',
        prefixIcon: Icon(
          Icons.smartphone_outlined,
          color: BrandColors.focusDark,
        ),
      ),
      items: [
        DropdownMenuItem<String>(
          value: null,
          child: Text(
            'Any platform',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 14,
              color: BrandColors.mutedInk,
            ),
          ),
        ),
        ..._platforms.map(
          (p) => DropdownMenuItem<String>(
            value: p,
            child: Text(
              p,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 14,
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
        labelText: 'Which cinema?',
        prefixIcon: Icon(
          Icons.theater_comedy_outlined,
          color: BrandColors.focusDark,
        ),
      ),
      items: [
        DropdownMenuItem<String>(
          value: null,
          child: Text(
            'Any cinema',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 14,
              color: BrandColors.mutedInk,
            ),
          ),
        ),
        ..._cinemas.map(
          (c) => DropdownMenuItem<String>(
            value: c,
            child: Text(
              c,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 14,
                color: BrandColors.ink,
              ),
            ),
          ),
        ),
      ],
      onChanged: (value) => setState(() => _selectedCinema = value),
    );
  }

  Widget _buildQuickChips(BuildContext context) {
    final ticketChips = Wrap(
      spacing: 6,
      runSpacing: 6,
      children: _ticketOptions.map((n) {
        final selected = int.tryParse(_ticketCountController.text) == n;
        return ChoiceChip(
          label: Text(
            '$n TICKETS',
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: selected ? Colors.black : BrandColors.mutedInk,
            ),
          ),
          selectedColor: BrandColors.focusDark,
          backgroundColor: BrandColors.paper,
          selected: selected,
          showCheckmark: false,
          onSelected: (_) => setState(() => _ticketCountController.text = '$n'),
        );
      }).toList(),
    );
    final priceChips = Wrap(
      spacing: 6,
      runSpacing: 6,
      children: _priceOptions.map((p) {
        final selected = double.tryParse(_priceController.text) == p.toDouble();
        return ChoiceChip(
          label: Text(
            '₹$p',
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 14,
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
    );
    return _responsivePair(
      context: context,
      first: ticketChips,
      second: priceChips,
    );
  }

  Widget _buildTotalAmount(BuildContext context) {
    final tickets = int.tryParse(_ticketCountController.text) ?? 0;
    final price = double.tryParse(_priceController.text) ?? 0.0;
    final total = tickets * price;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: BrandColors.paper,
        borderRadius: BorderRadius.circular(BrandRadius.card),
        border: Border.all(color: BrandColors.paperDeep),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stack =
              constraints.maxWidth < 600 ||
              MediaQuery.textScalerOf(context).scale(14) >= 21;
          final label = Text(
            'TOTAL BASE AMOUNT:',
            style: TextStyle(
              fontFamily: 'Manrope',
              fontWeight: FontWeight.bold,
              color: BrandColors.mutedInk,
              fontSize: 12,
              letterSpacing: 0.5,
            ),
          );
          final amount = Text(
            total > 0 ? '₹${total.toStringAsFixed(0)}' : '₹0',
            style: TextStyle(
              fontFamily: 'Manrope',
              fontWeight: FontWeight.bold,
              color: BrandColors.focusDark,
              fontSize: 16,
            ),
          );
          return stack
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [label, const SizedBox(height: 4), amount],
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [label, amount],
                );
        },
      ),
    );
  }

  Widget _buildOptimizeButton() {
    final tickets = int.tryParse(_ticketCountController.text) ?? 0;
    final price = double.tryParse(_priceController.text) ?? 0.0;
    final total = tickets * price;
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
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
        style: ElevatedButton.styleFrom(
          backgroundColor: BrandColors.focusDark,
          disabledBackgroundColor: BrandColors.paperDeep,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(BrandRadius.card),
          ),
        ),
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Icon(Icons.bolt, color: Colors.black, size: 16),
            Text(
              total > 0
                  ? 'Find my best option • ₹${total.toStringAsFixed(0)}'
                  : 'Find my best option',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 14,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
                color: Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
