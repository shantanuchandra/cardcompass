import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cardcompass/features/evals/models/eval_metric.dart';
import 'package:cardcompass/features/evals/widgets/eval_shared_widgets.dart';

class TransactionParsingEvalPanel extends StatefulWidget {
  const TransactionParsingEvalPanel({super.key, required this.score});
  final SubsystemScore? score;

  @override
  State<TransactionParsingEvalPanel> createState() =>
      _TransactionParsingEvalPanelState();
}

class _TransactionParsingEvalPanelState
    extends State<TransactionParsingEvalPanel> {
  final _supabase = Supabase.instance.client;
  bool _loading = true;
  List<Map<String, dynamic>> _statements = [];
  Map<String, dynamic> _fieldCoverage = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      // Fetch recent statements
      final stmtRaw = await _supabase
          .from('statements')
          .select('id, bank_name, statement_date, total_amount, due_date, card_name')
          .order('statement_date', ascending: false)
          .limit(100);
      final stmts = (stmtRaw as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      // Field coverage: for each statement, count how many key fields are populated
      int totalTxns = 0;
      int withDate = 0, withAmount = 0, withMerchant = 0, withCategory = 0;

      for (final stmt in stmts.take(30)) {
        try {
          final txnRaw = await _supabase
              .from('transactions')
              .select('transaction_date, amount, merchant_name, category')
              .eq('statement_id', stmt['id'])
              .limit(20);
          final txns = (txnRaw as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          for (final t in txns) {
            totalTxns++;
            if (t['transaction_date'] != null) withDate++;
            if (t['amount'] != null) withAmount++;
            if ((t['merchant_name']?.toString() ?? '').isNotEmpty) withMerchant++;
            if ((t['category']?.toString() ?? '').isNotEmpty) withCategory++;
          }
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        _statements = stmts;
        _fieldCoverage = {
          'date': totalTxns > 0 ? withDate / totalTxns : 0.0,
          'amount': totalTxns > 0 ? withAmount / totalTxns : 0.0,
          'merchant': totalTxns > 0 ? withMerchant / totalTxns : 0.0,
          'category': totalTxns > 0 ? withCategory / totalTxns : 0.0,
          'totalTxns': totalTxns,
        };
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final score = widget.score;
    if (score == null || _loading) {
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFF00F5FF)));
    }

    return EvalPanelShell(
      score: score,
      subsystemName: 'Transaction Parsing',
      icon: '🔬',
      metrics: score.metrics,
      detail: _buildDetail(),
    );
  }

  Widget _buildDetail() {
    final totalTxns = (_fieldCoverage['totalTxns'] as num?)?.toInt() ?? 0;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader('Field Coverage Heatmap  (n=$totalTxns transactions)'),
          const SizedBox(height: 10),
          _fieldBar('transaction_date', _fieldCoverage['date'] ?? 0.0),
          _fieldBar('amount', _fieldCoverage['amount'] ?? 0.0),
          _fieldBar('merchant_name', _fieldCoverage['merchant'] ?? 0.0),
          _fieldBar('category', _fieldCoverage['category'] ?? 0.0),
          const SizedBox(height: 24),
          _sectionHeader('Recent Statements  (${_statements.length})'),
          const SizedBox(height: 8),
          _buildTable(),
        ],
      ),
    );
  }

  Widget _fieldBar(String field, double coverage) {
    final color = coverage >= 0.9
        ? const Color(0xFF10B981)
        : coverage >= 0.7
            ? const Color(0xFFF59E0B)
            : const Color(0xFFEF4444);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 160,
                child: Text(field,
                    style: GoogleFonts.jetBrainsMono(
                        fontSize: 11, color: Colors.white54)),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: coverage.clamp(0.0, 1.0),
                    minHeight: 16,
                    backgroundColor: Colors.white10,
                    valueColor: AlwaysStoppedAnimation(color),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${(coverage * 100).toStringAsFixed(1)} %',
                style: GoogleFonts.jetBrainsMono(
                    fontSize: 11, color: color, fontWeight: FontWeight.bold),
              ),
            ],
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
        2: FixedColumnWidth(110),
        3: FixedColumnWidth(90),
      },
      border: TableBorder.all(color: Colors.white10, width: 0.5),
      children: [
        _tableHeader(['Bank', 'Card', 'Date', 'Total Due']),
        ..._statements.take(50).map(_tableRow),
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

  TableRow _tableRow(Map<String, dynamic> s) => TableRow(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(s['bank_name']?.toString() ?? '-',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 11, color: Colors.white70)),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(s['card_name']?.toString() ?? '-',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 11, color: Colors.white54)),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
                (s['statement_date']?.toString() ?? '-').substring(0, 10),
                style: GoogleFonts.jetBrainsMono(
                    fontSize: 10, color: Colors.white54)),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              s['total_amount'] != null
                  ? '₹${(s['total_amount'] as num).toStringAsFixed(0)}'
                  : '-',
              style: GoogleFonts.jetBrainsMono(
                  fontSize: 10, color: Colors.white54),
            ),
          ),
        ],
      );

  Widget _sectionHeader(String t) => Text(
        t.toUpperCase(),
        style: GoogleFonts.jetBrainsMono(
            fontSize: 10, color: Colors.white38, letterSpacing: 1.2),
      );
}
