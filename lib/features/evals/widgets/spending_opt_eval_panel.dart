import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cardcompass/core/services/gemini_call_log_service.dart';
import 'package:cardcompass/features/evals/models/eval_metric.dart';
import 'package:cardcompass/features/evals/widgets/eval_shared_widgets.dart';

class SpendingOptEvalPanel extends StatefulWidget {
  const SpendingOptEvalPanel({super.key, required this.score});
  final SubsystemScore? score;

  @override
  State<SpendingOptEvalPanel> createState() => _SpendingOptEvalPanelState();
}

class _SpendingOptEvalPanelState extends State<SpendingOptEvalPanel> {
  final _logService = GeminiCallLogService();
  List<GeminiCallLog> _logs = [];
  bool _loading = true;
  GeminiCallLog? _selected;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final logs =
        await _logService.getLogsForType(GeminiCallType.spendingOptimization);
    if (!mounted) return;
    setState(() {
      _logs = logs;
      _loading = false;
    });
  }

  // Category frequency across all logged calls
  Map<String, double> _categoryDeltas() {
    final deltas = <String, List<double>>{};
    for (final log in _logs) {
      for (final opt in log.output) {
        final cat = opt['category']?.toString() ?? 'Other';
        final cur = (opt['currentRewardRate'] as num?)?.toDouble() ?? 0;
        final opt2 = (opt['optimizedRewardRate'] as num?)?.toDouble() ?? 0;
        deltas.putIfAbsent(cat, () => []).add(opt2 - cur);
      }
    }
    return {
      for (final e in deltas.entries)
        e.key: e.value.fold(0.0, (s, v) => s + v) / e.value.length,
    };
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
      subsystemName: 'Spending Optimizations',
      icon: '📊',
      metrics: score.metrics,
      detail: _selected != null ? _buildDrill() : _buildMain(),
    );
  }

  Widget _buildMain() {
    if (_logs.isEmpty) {
      return EvalEmptyState(
        emoji: '📊',
        title: 'No optimisation calls logged',
        subtitle: 'Open Analytics → Optimisations to trigger AI calls. They will appear here automatically.',
      );
    }

    final deltas = _categoryDeltas();
    final mockCount = _logs.where((l) => l.usedMockFallback).length;
    final realCount = _logs.length - mockCount;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Mock vs Real breakdown
          _sectionHeader('Real AI vs Mock Fallback'),
          const SizedBox(height: 10),
          Row(
            children: [
              _donutSegment('Real AI', realCount, const Color(0xFF10B981)),
              const SizedBox(width: 12),
              _donutSegment('Mock Fallback', mockCount, const Color(0xFFF59E0B)),
            ],
          ),
          const SizedBox(height: 24),
          // Reward rate delta by category
          if (deltas.isNotEmpty) ...[
            _sectionHeader('Avg Reward Rate Delta by Category'),
            const SizedBox(height: 10),
            ...deltas.entries.map((e) => _deltaBar(e.key, e.value)),
            const SizedBox(height: 24),
          ],
          _sectionHeader('Call Log  (${_logs.length} calls)'),
          const SizedBox(height: 8),
          _buildTable(),
        ],
      ),
    );
  }

  Widget _donutSegment(String label, int count, Color color) => Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text('$count $label',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12, color: Colors.white60)),
        ],
      );

  Widget _deltaBar(String category, double delta) {
    final maxDelta = 10.0;
    final frac = (delta / maxDelta).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(category,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 11, color: Colors.white60),
                overflow: TextOverflow.ellipsis),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: frac,
                minHeight: 14,
                backgroundColor: Colors.white10,
                valueColor: const AlwaysStoppedAnimation(Color(0xFF8B5CF6)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text('+${delta.toStringAsFixed(1)} %',
              style: GoogleFonts.jetBrainsMono(
                  fontSize: 10, color: const Color(0xFF8B5CF6))),
        ],
      ),
    );
  }

  Widget _buildTable() {
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(2),
        1: FixedColumnWidth(70),
        2: FixedColumnWidth(60),
        3: FixedColumnWidth(80),
        4: FixedColumnWidth(55),
      },
      border: TableBorder.all(color: Colors.white10, width: 0.5),
      children: [
        _tableHeader(['Timestamp', 'Provider', 'Opts', 'Latency', 'Mock']),
        ..._logs.take(50).map(_tableRow),
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

  TableRow _tableRow(GeminiCallLog log) => TableRow(
        children: [
          InkWell(
            onTap: () => setState(() => _selected = log),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                log.timestamp.length >= 19
                    ? log.timestamp.substring(0, 19).replaceFirst('T', ' ')
                    : log.timestamp,
                style: GoogleFonts.jetBrainsMono(
                    fontSize: 10, color: const Color(0xFF00F5FF)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(log.provider,
                style: GoogleFonts.jetBrainsMono(
                    fontSize: 10, color: Colors.white54)),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text('${log.output.length}',
                style: GoogleFonts.jetBrainsMono(
                    fontSize: 10, color: Colors.white54)),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text('${log.durationMs} ms',
                style: GoogleFonts.jetBrainsMono(
                    fontSize: 10, color: Colors.white54)),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              log.usedMockFallback ? 'YES' : 'no',
              style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  color: log.usedMockFallback
                      ? const Color(0xFFF59E0B)
                      : Colors.white24),
            ),
          ),
        ],
      );

  Widget _buildDrill() {
    final log = _selected!;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new,
                    color: Colors.white54, size: 16),
                onPressed: () => setState(() => _selected = null),
              ),
              Text(
                'Call · ${log.timestamp.substring(0, 10)} via ${log.provider}',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    color: Colors.white,
                    fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _detailRow('Duration', '${log.durationMs} ms'),
          _detailRow('Mock fallback', log.usedMockFallback ? 'YES ⚠️' : 'No'),
          _detailRow('Txn input count',
              '${log.inputSummary['transactionCount'] ?? '?'}'),
          _detailRow(
              'Card count', '${log.inputSummary['cardCount'] ?? '?'}'),
          if (log.errorMessage != null)
            _detailRow('Error', log.errorMessage!),
          const SizedBox(height: 12),
          _sectionHeader('Optimizations  (${log.output.length})'),
          const SizedBox(height: 8),
          ...log.output.map(_optCard),
        ],
      ),
    );
  }

  Widget _optCard(Map<String, dynamic> opt) {
    final cur = (opt['currentRewardRate'] as num?)?.toDouble() ?? 0.0;
    final optimised = (opt['optimizedRewardRate'] as num?)?.toDouble() ?? 0.0;
    final delta = optimised - cur;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B2A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFF8B5CF6).withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  opt['category']?.toString() ?? '-',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      color: Colors.white,
                      fontWeight: FontWeight.bold),
                ),
              ),
              Text(
                '+${delta.toStringAsFixed(1)} %',
                style: GoogleFonts.jetBrainsMono(
                    fontSize: 12, color: const Color(0xFF8B5CF6)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(opt['recommendation']?.toString() ?? '-',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 11, color: Colors.white54)),
          const SizedBox(height: 4),
          Text(
            'Use: ${opt['cardToUse'] ?? '?'} · '
            'Saves ₹${opt['potentialMonthlySavings'] ?? 0}/mo',
            style: GoogleFonts.jetBrainsMono(
                fontSize: 10, color: const Color(0xFFFFD700)),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String t) => Text(
        t.toUpperCase(),
        style: GoogleFonts.jetBrainsMono(
            fontSize: 10, color: Colors.white38, letterSpacing: 1.2),
      );

  Widget _detailRow(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 130,
              child: Text(k,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 11, color: Colors.white38)),
            ),
            Expanded(
              child: SelectableText(v,
                  style: GoogleFonts.jetBrainsMono(
                      fontSize: 11, color: Colors.white70)),
            ),
          ],
        ),
      );

}
