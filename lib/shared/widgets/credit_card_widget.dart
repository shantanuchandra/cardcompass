import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class CreditCardWidget extends StatefulWidget {
  final String cardName;
  final String bankName;
  final String lastFourDigits;
  final String expiryDate;
  final String cardType;
  final List<Color> gradientColors;

  const CreditCardWidget({
    super.key,
    required this.cardName,
    required this.bankName,
    required this.lastFourDigits,
    required this.expiryDate,
    required this.cardType,
    required this.gradientColors,
  });

  @override
  State<CreditCardWidget> createState() => _CreditCardWidgetState();
}

class _CreditCardWidgetState extends State<CreditCardWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cardColor = widget.gradientColors.first;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTapDown: (_) => _controller.forward(),
        onTapUp: (_) => _controller.reverse(),
        onTapCancel: () => _controller.reverse(),
        child: ScaleTransition(
          scale: _scaleAnimation,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: 320,
            height: 200,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: widget.gradientColors,
              ),
              boxShadow: [
                BoxShadow(
                  color: cardColor.withValues(alpha: _isHovered ? 0.5 : 0.3),
                  blurRadius: _isHovered ? 28 : 20,
                  spreadRadius: _isHovered ? 2 : 0,
                  offset: Offset(0, _isHovered ? 12 : 8),
                ),
                // Inner glow
                BoxShadow(
                  color: Colors.white.withValues(alpha: 0.1),
                  blurRadius: 10,
                  offset: const Offset(1, 1),
                ),
              ],
              border: Border.all(
                color: Colors.white.withValues(alpha: _isHovered ? 0.3 : 0.15),
                width: 1.5,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Stack(
                children: [
                  // Holographic diagonal sheen lines
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          stops: const [0.0, 0.4, 0.45, 0.5, 0.55, 0.6, 1.0],
                          colors: [
                            Colors.transparent,
                            Colors.transparent,
                            Colors.white.withValues(alpha: 0.05),
                            Colors.white.withValues(alpha: 0.12),
                            Colors.white.withValues(alpha: 0.05),
                            Colors.transparent,
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                  
                  // Card details
                  Padding(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Bank Name & Network Type
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              widget.bankName.toUpperCase(),
                              style: GoogleFonts.spaceGrotesk(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                letterSpacing: 1.5,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  width: 1,
                                ),
                              ),
                              child: Text(
                                widget.cardType.toUpperCase(),
                                style: GoogleFonts.spaceGrotesk(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 9,
                                  letterSpacing: 1.0,
                                ),
                              ),
                            ),
                          ],
                        ),
                        
                        // Cyber Chip & contactless wave
                        Row(
                          children: [
                            Container(
                              width: 40,
                              height: 30,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.amber[300]!,
                                    Colors.amber[600]!,
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.black.withValues(alpha: 0.2)),
                              ),
                              child: Stack(
                                children: [
                                  Positioned(
                                    left: 10,
                                    right: 10,
                                    top: 0,
                                    bottom: 0,
                                    child: Container(
                                      decoration: const BoxDecoration(
                                        border: Border(
                                          left: BorderSide(color: Colors.black38, width: 0.5),
                                          right: BorderSide(color: Colors.black38, width: 0.5),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    left: 0,
                                    right: 0,
                                    top: 10,
                                    bottom: 10,
                                    child: Container(
                                      decoration: const BoxDecoration(
                                        border: Border(
                                          top: BorderSide(color: Colors.black38, width: 0.5),
                                          bottom: BorderSide(color: Colors.black38, width: 0.5),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Icon(
                              Icons.wifi,
                              color: Colors.white.withValues(alpha: 0.6),
                              size: 16,
                            ),
                          ],
                        ),
                        
                        // Card Number
                        Text(
                          '•••• •••• •••• ${widget.lastFourDigits}',
                          style: GoogleFonts.shareTechMono(
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                            fontSize: 20,
                            letterSpacing: 3,
                          ),
                        ),
                        
                        // Cardholder & Expiry
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'CARD HOLDER',
                                    style: GoogleFonts.spaceGrotesk(
                                      color: Colors.white.withValues(alpha: 0.5),
                                      fontSize: 8,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.0,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    widget.cardName.toUpperCase(),
                                    style: GoogleFonts.spaceGrotesk(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                      letterSpacing: 0.5,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  'EXPIRES',
                                  style: GoogleFonts.spaceGrotesk(
                                    color: Colors.white.withValues(alpha: 0.5),
                                    fontSize: 8,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.0,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  widget.expiryDate,
                                  style: GoogleFonts.shareTechMono(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ],
                            ),
                          ],
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
    );
  }
}
