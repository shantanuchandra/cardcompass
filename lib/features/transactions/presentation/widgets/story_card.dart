// lib/features/transactions/presentation/widgets/story_card.dart

import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cardcompass/core/services/merchant_logo_service.dart';

/// A glass‑morphism card that displays a spending story for a category.
///
/// The card animates in with a fade‑in and slide‑up effect when it first
/// appears in the list. It shows the merchant logo (if available), the category
/// name, the total amount spent and a short narrative.
class StoryCard extends ConsumerStatefulWidget {
  final String categoryName;
  final double amountSpent; // absolute value in user's currency
  final String? merchantDomain; // optional domain for logo lookup

  const StoryCard({
    Key? key,
    required this.categoryName,
    required this.amountSpent,
    this.merchantDomain,
  }) : super(key: key);

  @override
  ConsumerState<StoryCard> createState() => _StoryCardState();
}

class _StoryCardState extends ConsumerState<StoryCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _offsetAnimation;
  late final Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _offsetAnimation = Tween<Offset>(
      begin: const Offset(0, 0.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _opacityAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeIn));
    // Start the animation after the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => _controller.forward());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<String> _logoUrl() async {
    if (widget.merchantDomain == null) {
      return 'assets/images/placeholder_merchant.png';
    }
    final service = MerchantLogoService();
    return await service.fetchLogoUrl(widget.merchantDomain!);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const borderRadius = BorderRadius.all(Radius.circular(20));

    return FadeTransition(
      opacity: _opacityAnimation,
      child: SlideTransition(
        position: _offsetAnimation,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ClipRRect(
            borderRadius: borderRadius,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.white.withOpacity(0.25),
                      Colors.white.withOpacity(0.15),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.2),
                  ),
                  borderRadius: borderRadius,
                ),
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    FutureBuilder<String>(
                      future: _logoUrl(),
                      builder: (context, snapshot) {
                        final logo = snapshot.data ??
                            'assets/images/placeholder_merchant.png';
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            logo,
                            width: 48,
                            height: 48,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => Image.asset(
                              'assets/images/placeholder_merchant.png',
                              width: 48,
                              height: 48,
                              fit: BoxFit.contain,
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.categoryName,
                            style: theme.textTheme.titleLarge?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "Spent \$${widget.amountSpent.toStringAsFixed(2)}",
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: Colors.white70,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _generateNarrative(),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _generateNarrative() {
    // Simple placeholder narrative – can be expanded later.
    return "Your spending in ${widget.categoryName.toLowerCase()} shapes your financial story.";
  }
}
