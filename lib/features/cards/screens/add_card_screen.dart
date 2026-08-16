import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/brand_tokens.dart';
import '../../../core/theme/brand_components.dart';
import '../../../core/providers/repository_providers.dart';
import '../../../core/providers/supabase_provider.dart';
import '../providers/cards_provider.dart';

typedef CardCatalogSearch =
    Future<List<Map<String, dynamic>>> Function(String query);

final cardCatalogSearchProvider = Provider<CardCatalogSearch>((ref) {
  return ref.read(cardsRepositoryProvider).searchCatalog;
});

class AddCardScreen extends ConsumerStatefulWidget {
  const AddCardScreen({super.key});

  @override
  ConsumerState<AddCardScreen> createState() => _AddCardScreenState();
}

class _AddCardScreenState extends ConsumerState<AddCardScreen> {
  final _search = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  Map<String, dynamic>? _selected;
  bool _loading = false;
  bool _saving = false;
  bool _saveSucceeded = false;
  String? _requestError;
  String? _lastFourError;
  int _searchGeneration = 0;

  final _lastFour = TextEditingController();
  final _holderName = TextEditingController();

  @override
  void dispose() {
    _searchGeneration++;
    _search.dispose();
    _lastFour.dispose();
    _holderName.dispose();
    super.dispose();
  }

  Future<void> _searchCards(String q) async {
    final generation = ++_searchGeneration;
    final query = q.trim();
    if (query.length < 2) {
      if (!mounted) return;
      setState(() {
        _results = [];
        _loading = false;
        _requestError = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _requestError = null;
    });
    try {
      final r = await ref.read(cardCatalogSearchProvider)(query);
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _results = r;
        _loading = false;
        _requestError = null;
      });
    } catch (_) {
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _loading = false;
        _requestError = 'Could not search the card catalogue. Try again.';
      });
    }
  }

  Future<void> _save() async {
    if (_selected == null || _saving || _saveSucceeded) return;
    final lastFour = _lastFour.text.trim();
    if (lastFour.isNotEmpty && !RegExp(r'^\d{4}$').hasMatch(lastFour)) {
      setState(
        () => _lastFourError = 'Enter exactly four digits or leave this blank',
      );
      return;
    }
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    final catalogCardId = _selected!['id'] as String;
    final holderName = _holderName.text.trim();
    setState(() {
      _saving = true;
      _saveSucceeded = false;
      _lastFourError = null;
      _requestError = null;
    });
    try {
      await ref
          .read(addCardSaveCoordinatorProvider)
          .save(
            userId: user.id,
            catalogCardId: catalogCardId,
            lastFourDigits: lastFour.isEmpty ? null : lastFour,
            cardHolderName: holderName.isEmpty ? null : holderName,
          );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _requestError = 'Could not add this card. Try again.';
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _saving = false;
      _saveSucceeded = true;
      _requestError = null;
    });
    try {
      await Navigator.of(context).maybePop(true);
    } catch (_) {
      // The insert already succeeded. Navigation recovery must never rewrite a
      // successful mutation as a repository error.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BrandColors.paper,
      appBar: AppBar(
        title: Text(
          'Add Card',
          style: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: BrandContentFrame(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: BrandSpacing.md),
          children: [
            _AddCardProgress(
              currentStep: _selected == null
                  ? AddCardStep.search
                  : AddCardStep.confirm,
            ),
            const SizedBox(height: BrandSpacing.lg),
            // Step 1: search catalog
            if (_selected == null) ...[
              Text(
                'Search your card',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: BrandColors.ink,
                ),
              ),
              const SizedBox(height: BrandSpacing.sm),
              TextField(
                key: const Key('card-search'),
                controller: _search,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'e.g. HDFC Regalia, Axis Ace...',
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: BrandColors.mutedInk,
                  ),
                ),
                onChanged: _searchCards,
              ),
              const SizedBox(height: BrandSpacing.sm),
              if (_loading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(BrandSpacing.lg),
                    child: CircularProgressIndicator(
                      color: BrandColors.focusDark,
                      strokeWidth: 2,
                    ),
                  ),
                )
              else
                ..._results.map(
                  (card) => _CatalogTile(
                    card: card,
                    onTap: () => setState(() {
                      _selected = card;
                      _requestError = null;
                      _saveSucceeded = false;
                    }),
                  ),
                ),
              if (_requestError != null) ...[
                const SizedBox(height: BrandSpacing.sm),
                Text(
                  _requestError!,
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 14,
                    color: BrandColors.error,
                  ),
                ),
                TextButton(
                  onPressed: () => _searchCards(_search.text),
                  child: const Text('Retry search'),
                ),
              ],
            ],

            // Step 2: details
            if (_selected != null) ...[
              Container(
                padding: const EdgeInsets.all(BrandSpacing.md),
                decoration: BoxDecoration(
                  color: BrandColors.focusDark.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(BrandRadius.card),
                  border: Border.all(
                    color: BrandColors.focusDark.withValues(alpha: 0.3),
                  ),
                ),
                child: _SelectedCatalogCard(
                  card: _selected!,
                  onChange: () => setState(() {
                    _selected = null;
                    _requestError = null;
                    _saveSucceeded = false;
                  }),
                ),
              ),
              const SizedBox(height: BrandSpacing.lg),
              Text(
                'Card details (optional)',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: BrandColors.ink,
                ),
              ),
              const SizedBox(height: BrandSpacing.sm),
              Semantics(
                key: const Key('last-four-field'),
                container: true,
                label: _lastFourError == null
                    ? 'Last 4 digits'
                    : 'Last 4 digits. Error: $_lastFourError',
                child: TextField(
                  key: const Key('last-four'),
                  controller: _lastFour,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  onChanged: (_) {
                    if (_lastFourError != null) {
                      setState(() => _lastFourError = null);
                    }
                  },
                  decoration: InputDecoration(
                    labelText: 'Last 4 digits',
                    hintText: '1234',
                    counterText: '',
                    errorText: _lastFourError,
                  ),
                ),
              ),
              const SizedBox(height: BrandSpacing.xs),
              Text(
                'Optional — helps match statements to this card. We never ask for the full card number.',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 12,
                  height: 1.4,
                  color: BrandColors.mutedInk,
                ),
              ),
              const SizedBox(height: BrandSpacing.sm),
              TextField(
                controller: _holderName,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Cardholder name'),
              ),
              const SizedBox(height: BrandSpacing.xs),
              Text(
                'Optional — used only to label this card for you.',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 12,
                  height: 1.4,
                  color: BrandColors.mutedInk,
                ),
              ),
              const SizedBox(height: BrandSpacing.lg),
              if (_requestError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: BrandSpacing.sm),
                  child: Text(
                    _requestError!,
                    style: TextStyle(
                      fontFamily: 'Manrope',
                      fontSize: 14,
                      color: BrandColors.error,
                    ),
                  ),
                ),
              if (_saveSucceeded)
                Padding(
                  padding: const EdgeInsets.only(bottom: BrandSpacing.sm),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      'Card added. Return to your cards to see it.',
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 14,
                        color: BrandColors.successInk,
                      ),
                    ),
                  ),
                ),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving || _saveSucceeded ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: BrandColors.ink,
                          ),
                        )
                      : const Text('Add card'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

enum AddCardStep { search, confirm }

class _AddCardProgress extends StatelessWidget {
  const _AddCardProgress({required this.currentStep});

  final AddCardStep currentStep;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.textScalerOf(context).scale(14) >= 21;
    final confirming = currentStep == AddCardStep.confirm;
    return Semantics(
      label:
          'Add card progress. Current step: ${confirming ? 'Confirm' : 'Search'}',
      child: ExcludeSemantics(
        child: compact
            ? Wrap(
                spacing: BrandSpacing.sm,
                runSpacing: BrandSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _step('1 Search', active: !confirming),
                  const Icon(Icons.arrow_forward_rounded, size: 18),
                  _step('2 Confirm', active: confirming),
                ],
              )
            : Row(
                children: [
                  _step('1 Search', active: !confirming),
                  const Expanded(
                    child: Divider(
                      indent: BrandSpacing.sm,
                      endIndent: BrandSpacing.sm,
                    ),
                  ),
                  _step('2 Confirm', active: confirming),
                ],
              ),
      ),
    );
  }

  Widget _step(String label, {bool active = false}) => Text(
    label,
    style: TextStyle(
      fontFamily: 'Manrope',
      fontSize: 12,
      fontWeight: FontWeight.w700,
      color: active ? BrandColors.ink : BrandColors.mutedInk,
    ),
  );
}

class _SelectedCatalogCard extends StatelessWidget {
  const _SelectedCatalogCard({required this.card, required this.onChange});

  final Map<String, dynamic> card;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final selectedCard = Text(
      '${card['card_name']} · ${card['bank']}',
      style: TextStyle(
        fontFamily: 'Manrope',
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: BrandColors.ink,
      ),
    );
    final icon = const Icon(
      Icons.check_circle_rounded,
      color: BrandColors.focusDark,
      size: 20,
    );
    final change = TextButton(onPressed: onChange, child: const Text('Change'));
    final compact = MediaQuery.textScalerOf(context).scale(14) >= 21;
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              icon,
              const SizedBox(width: BrandSpacing.sm),
              Expanded(child: selectedCard),
            ],
          ),
          Align(alignment: Alignment.centerRight, child: change),
        ],
      );
    }
    return Row(
      children: [
        icon,
        const SizedBox(width: BrandSpacing.sm),
        Expanded(child: selectedCard),
        change,
      ],
    );
  }
}

class _CatalogTile extends StatelessWidget {
  final Map<String, dynamic> card;
  final VoidCallback onTap;
  const _CatalogTile({required this.card, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cardName = card['card_name'] as String? ?? '';
    final bank = card['bank'] as String? ?? '';
    final id = card['id'] as String? ?? '$cardName-$bank';
    return Semantics(
      key: Key('catalog-card-$id'),
      label: '$cardName, $bank',
      button: true,
      onTap: onTap,
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(BrandRadius.card),
            child: Container(
              margin: const EdgeInsets.only(bottom: BrandSpacing.xs + 2),
              constraints: const BoxConstraints(minHeight: 44),
              padding: const EdgeInsets.symmetric(
                horizontal: BrandSpacing.md,
                vertical: 12,
              ),
              decoration: BoxDecoration(
                color: BrandColors.paper,
                borderRadius: BorderRadius.circular(BrandRadius.card),
                border: Border.all(
                  color: BrandColors.mutedInk.withValues(alpha: 0.1),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          cardName,
                          style: TextStyle(
                            fontFamily: 'Manrope',
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: BrandColors.ink,
                          ),
                        ),
                        Text(
                          bank,
                          style: TextStyle(
                            fontFamily: 'Manrope',
                            fontSize: 12,
                            color: BrandColors.mutedInk,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: BrandColors.mutedInk,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
