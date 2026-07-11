import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cardcompass/core/theme.dart';

class ErrorState extends StatelessWidget {
  final String error;
  final VoidCallback? onRetry;
  final String? retryText;
  final IconData? icon;

  const ErrorState({
    super.key,
    required this.error,
    this.onRetry,
    this.retryText,
    this.icon,
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
            border: Border.all(color: AppTheme.errorColor.withValues(alpha: 0.25), width: 1.2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon ?? Icons.warning_amber_outlined,
                size: 48,
                color: AppTheme.errorColor,
              ),
              const SizedBox(height: 16),
              Text(
                'SYSTEM DISCREPANCY',
                style: GoogleFonts.spaceGrotesk(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  letterSpacing: 1.0,
                  color: AppTheme.errorColor,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                error,
                style: GoogleFonts.plusJakartaSans(
                  color: Colors.white70,
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh, size: 14, color: AppTheme.errorColor),
                  label: Text(
                    (retryText ?? 'RETRY CONNECTION').toUpperCase(),
                    style: GoogleFonts.spaceGrotesk(
                      color: AppTheme.errorColor,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppTheme.errorColor, width: 1.2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
