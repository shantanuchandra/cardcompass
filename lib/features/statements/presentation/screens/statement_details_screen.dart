import 'package:cardcompass/shared/models/statement.dart';
import 'package:cardcompass/shared/widgets/state_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cardcompass/core/theme.dart';

/// Screen to display details of a single statement and its transactions in tech-neon style
class StatementDetailsScreen extends ConsumerWidget {
  final Statement statement;

  const StatementDetailsScreen({super.key, required this.statement});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: const Color(0xFF050B18),
      appBar: AppBar(
        title: Text(
          statement.fileName.toUpperCase(),
          style: GoogleFonts.spaceGrotesk(
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0,
            fontSize: 14,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppTheme.primaryColor),
            onPressed: () {
              // Refresh statement logic if needed
            },
          ),
        ],
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStatementInfo(context),
          const SizedBox(height: 28),
          Text(
            'STATEMENT TRANSACTIONS',
            style: GoogleFonts.spaceGrotesk(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 12,
              letterSpacing: 1.0,
            ),
          ),
          const Divider(color: Color(0xFF1E293B), height: 20),
          const EmptyState(
            title: 'LEDGER EMPTY',
            message: 'Transactions parsed from statement PDF will compile here.',
            icon: Icons.receipt_long_outlined,
          ),
        ],
      ),
    );
  }

  Widget _buildStatementInfo(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF0C152B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.analytics_outlined, color: AppTheme.primaryColor, size: 20),
              const SizedBox(width: 8),
              Text(
                'STATEMENT DATA SUMMARY',
                style: GoogleFonts.spaceGrotesk(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildInfoRow('FILE SOURCE', statement.fileName),
          _buildInfoRow('TOTAL DUE', '₹${statement.totalAmount.toStringAsFixed(2)}', valueColor: AppTheme.primaryColor),
          _buildInfoRow('MINIMUM PAY', '₹${statement.minimumPayment.toStringAsFixed(2)}'),
          _buildInfoRow('PAYMENT DUE', _formatDate(statement.dueDate), valueColor: AppTheme.warningColor),
          _buildInfoRow('BILLING DATE', _formatDate(statement.statementDate)),
          if (statement.rewardsEarned > 0)
            _buildInfoRow('REWARDS GAINED', statement.rewardsEarned.toString(), valueColor: AppTheme.successColor),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: GoogleFonts.spaceGrotesk(
                color: Colors.white38,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.spaceGrotesk(
                color: valueColor ?? Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }
}
