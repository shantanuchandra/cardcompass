import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/brand_tokens.dart';
import '../../../core/providers/repository_providers.dart';
import '../../../core/providers/supabase_provider.dart';

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
  String? _error;

  final _lastFour = TextEditingController();
  final _holderName = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    _lastFour.dispose();
    _holderName.dispose();
    super.dispose();
  }

  Future<void> _searchCards(String q) async {
    if (q.trim().length < 2) {
      setState(() {
        _results = [];
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final r = await ref.read(cardsRepositoryProvider).searchCatalog(q.trim());
      setState(() {
        _results = r;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _save() async {
    if (_selected == null) return;
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(cardsRepositoryProvider)
          .addUserCard(
            userId: user.id,
            catalogCardId: _selected!['id'] as String,
            lastFourDigits: _lastFour.text.trim().isEmpty
                ? null
                : _lastFour.text.trim(),
            cardHolderName: _holderName.text.trim().isEmpty
                ? null
                : _holderName.text.trim(),
          );
      if (mounted) context.pop();
    } catch (e) {
      setState(() {
        _saving = false;
        _error = e.toString();
      });
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
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(BrandSpacing.md),
        children: [
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
                  }),
                ),
              ),
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
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    color: BrandColors.focusDark,
                    size: 20,
                  ),
                  const SizedBox(width: BrandSpacing.sm),
                  Expanded(
                    child: Text(
                      '${_selected!['card_name']} · ${_selected!['bank']}',
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: BrandColors.ink,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _selected = null;
                    }),
                    child: const Text('Change'),
                  ),
                ],
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
            TextField(
              controller: _lastFour,
              keyboardType: TextInputType.number,
              maxLength: 4,
              decoration: const InputDecoration(
                labelText: 'Last 4 digits',
                hintText: '1234',
                counterText: '',
              ),
            ),
            const SizedBox(height: BrandSpacing.sm),
            TextField(
              controller: _holderName,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Cardholder name'),
            ),
            const SizedBox(height: BrandSpacing.lg),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: BrandSpacing.sm),
                child: Text(
                  _error!,
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 12,
                    color: BrandColors.error,
                  ),
                ),
              ),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: BrandColors.ink,
                        ),
                      )
                    : const Text('Add Card'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CatalogTile extends StatelessWidget {
  final Map<String, dynamic> card;
  final VoidCallback onTap;
  const _CatalogTile({required this.card, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: BrandSpacing.xs + 2),
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
                    card['card_name'] ?? '',
                    style: TextStyle(
                      fontFamily: 'Manrope',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: BrandColors.ink,
                    ),
                  ),
                  Text(
                    card['bank'] ?? '',
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
    );
  }
}
