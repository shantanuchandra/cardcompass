import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cardcompass/core/theme.dart';

class SyncProgressDialog extends StatelessWidget {
  const SyncProgressDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF0C152B),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: AppTheme.primaryColor.withValues(alpha: 0.25), width: 1.2),
      ),
      content: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'SYNCING GMAIL LEDGER...',
              style: GoogleFonts.spaceGrotesk(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Parsing email statements and extracting transaction entries.',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 10,
                color: Colors.white38,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
