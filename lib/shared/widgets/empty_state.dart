import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cardcompass/core/theme.dart';

class EmptyState extends StatelessWidget {
  final String title;
  final String message;
  final IconData? icon;
  final String? buttonText;
  final VoidCallback? onButtonPressed;
  final Widget? illustration;

  const EmptyState({
    super.key,
    required this.title,
    required this.message,
    this.icon,
    this.buttonText,
    this.onButtonPressed,
    this.illustration,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF0C152B),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (illustration != null)
                illustration!
              else
                Icon(
                  icon ?? Icons.inbox_outlined,
                  size: 40,
                  color: Colors.white38,
                ),
              const SizedBox(height: 16),
              Text(
                title.toUpperCase(),
                style: GoogleFonts.spaceGrotesk(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  letterSpacing: 0.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                message,
                style: GoogleFonts.plusJakartaSans(
                  color: Colors.white60,
                  fontSize: 11,
                ),
                textAlign: TextAlign.center,
              ),
              if (buttonText != null && onButtonPressed != null) ...[
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: onButtonPressed,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                  child: Text(
                    buttonText!.toUpperCase(),
                    style: GoogleFonts.spaceGrotesk(
                      color: Colors.black,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
