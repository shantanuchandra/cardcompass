import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cardcompass/features/evals/models/eval_metric.dart';
import 'package:cardcompass/features/evals/widgets/eval_shared_widgets.dart';

class RewardIntelligenceEvalPanel extends StatefulWidget {
  const RewardIntelligenceEvalPanel({super.key, required this.score});
  final SubsystemScore? score;

  @override
  State<RewardIntelligenceEvalPanel> createState() =>
      _RewardIntelligenceEvalPanelState();
}

class _RewardIntelligenceEvalPanelState
    extends State<RewardIntelligenceEvalPanel> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _balances = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final raw = await _supabase
          .from('reward_balances')
          .select('*')
          .limit(200);
      if (!mounted) return;
      setState(() {
        _balances = (raw as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _highValue => _balances
      .where((b) => ((b['inr_value'] as num?)?.toDouble() ?? 0) >= 500)
      .toList()
    ..sort((a, b) => ((b['inr_value'] as num?)?.toDouble() ?? 0)
        .compareTo((a['inr_value'] as num?)?.toDouble() ?? 0));

  @override
  Widget build(BuildContext context) {
    final score = widget.score;
    if (score == null || _loading) {
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFF00F5FF)));
    }

    return EvalPanelShell(
      score: score,
      subsystemName: 'Reward Intelligence',
      icon: '💎',
      metrics: score.metrics,
      detail: _buildMain(),
    );
  }

  Widget _buildMain() {
    if (_balances.isEmpty) {
      return _emptyState('No reward balances found.\nSync card statements to populate reward data.');
    }

    final highValue = _highValue;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Bar chart of INR values
          _sectionHeader('INR Value Distribution  (all cards)'),
          const SizedBox(height: 10),
          _buildValueBars(),
          const SizedBox(height: 24),
          if (highValue.isNotEmpty) ...[
            _sectionHeader('High-Value Alerts  (≥ ₹500 unredeemed)'),
            const SizedBox(height: 8),
            ...highValue.take(10).map(_alertCard),
            const SizedBox(height: 24),
          ],
          _sectionHeader('All Balances  (${_balances.length})'),
          const SizedBox(height: 8),
          _buildTable(),
        ],
      ),
    );
  }

  Widget _buildValueBars() {
    final sorted = List.of(_balances)
      ..sort((a, b) => ((b['inr_value'] as num?)?.toDouble() ?? 0)
          .compareTo((a['inr_value'] as num?)?.toDouble() ?? 0));
    final max = (sorted.firstOrNull?['inr_value'] as num?)?.toDouble() ?? 1.0;

    return Column(
      children: sorted.take(15).map((b) {
        final inr = (b['inr_value'] as num?)?.toDouble() ?? 0.0;
        final frac = (inr / max).clamp(0.0, 1.0);
        final color = inr >= 500
            ? const Color(0xFFFFD700)
            : inr >= 100
                ? const Color(0xFF10B981)
                : Colors.white38;
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              SizedBox(
                width: 130,
                child: Text(
                  b['card_name']?.toString() ?? b['card_id']?.toString() ?? '-',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 10, color: Colors.white60),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: frac,
                    minHeight: 12,
                    backgroundColor: Colors.white10,
                    valueColor: AlwaysStoppedAnimation(color),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '₹${inr.toStringAsFixed(0)}',
                style: GoogleFonts.jetBrainsMono(
                    fontSize: 10, color: color),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _alertCard(Map<String, dynamic> b) {
    final inr = (b['inr_value'] as num?)?.toDouble() ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B2A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFFFFD700).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          const Text('💎', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  b['card_name']?.toString() ?? b['card_id']?.toString() ?? '-',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      color: Colors.white,
                      fontWeight: FontWeight.w600),
                ),
                Text(
                  '${b['points_balance'] ?? '?'} pts · ${b['bank_name'] ?? ''}',
                  style: GoogleFonts.jetBrainsMono(
                      fontSize: 10, color: Colors.white38),
                ),
              ],
            ),
          ),
          Text(
            '₹${inr.toStringAsFixed(0)}',
            style: GoogleFonts.jetBrainsMono(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: const Color(0xFFFFD700)),
          ),
        ],
      ),
    );
  }

  Widget _buildTable() {
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(2),
        1: FlexColumnWidth(2),
        2: FixedColumnWidth(80),
        3: FixedColumnWidth(80),
      },
      border: TableBorder.all(color: Colors.white10, width: 0.5),
      children: [
        _tableHeader(['Card', 'Bank', 'Points', 'INR Value']),
        ..._balances.take(60).map(_tableRow),
      ],
    );
  }

  TableRow _tableHeader(List<String> cols) => TableRow(
        decoration: const BoxDecoration(color: Color(0xFF0D1B2A)),
        children: cols
            .map((c) => Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(c,
                      style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          color: Colors.white38,
                          fontWeight: FontWeight.bold)),
                ))
            .toList(),
      );

  TableRow _tableRow(Map<String, dynamic> b) {
    final inr = (b['inr_value'] as num?)?.toDouble() ?? 0.0;
    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(b['card_name']?.toString() ?? '-',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 11, color: Colors.white70)),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(b['bank_name']?.toString() ?? '-',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 11, color: Colors.white54)),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text('${b['points_balance'] ?? '-'}',
              style: GoogleFonts.jetBrainsMono(
                  fontSize: 10, color: Colors.white54)),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            inr > 0 ? '₹${inr.toStringAsFixed(0)}' : '-',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10,
              color: inr >= 500
                  ? const Color(0xFFFFD700)
                  : inr > 0
                      ? const Color(0xFF10B981)
                      : Colors.white24,
            ),
          ),
        ),
      ],
    );
  }

  Widget _sectionHeader(String t) => Text(
        t.toUpperCase(),
        style: GoogleFonts.jetBrainsMono(
            fontSize: 10, color: Colors.white38, letterSpacing: 1.2),
      );

  Widget _emptyState(String message) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('💎', style: TextStyle(fontSize: 40)),
              const SizedBox(height: 12),
              Text(message,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 13, color: Colors.white38)),
            ],
          ),
        ),
      );
}
