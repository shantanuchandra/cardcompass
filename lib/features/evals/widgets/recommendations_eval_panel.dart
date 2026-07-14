import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cardcompass/core/services/gemini_call_log_service.dart';
import 'package:cardcompass/features/evals/models/eval_metric.dart';
import 'package:cardcompass/features/evals/widgets/eval_shared_widgets.dart';

class RecommendationsEvalPanel extends StatefulWidget {
  const RecommendationsEvalPanel({super.key, required this.score});
  final SubsystemScore? score;

  @override
  State<RecommendationsEvalPanel> createState() =>
      _RecommendationsEvalPanelState();
}

class _RecommendationsEvalPanelState extends State<RecommendationsEvalPanel> {
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
    final logs = await _logService.getLogsForType(GeminiCallType.cardRecommendation);
    if (!mounted) return;
    setState(() {
      _logs = logs;
      _loading = false;
    });
  }

  // Confidence buckets for histogram
  Map<String, int> _confidenceBuckets() {
    final buckets = {
      '0.0–0.2': 0,
      '0.2–0.4': 0,
      '0.4–0.6': 0,
      '0.6–0.8': 0,
      '0.8–1.0': 0,
    };
    for (final log in _logs) {
      for (final rec in log.output) {
        final conf = (rec['confidenceScore'] as num?)?.toDouble() ?? 0.0;
        if (conf < 0.2) buckets['0.0–0.2'] = buckets['0.0–0.2']! + 1;
        else if (conf < 0.4) buckets['0.2–0.4'] = buckets['0.2–0.4']! + 1;
        else if (conf < 0.6) buckets['0.4–0.6'] = buckets['0.4–0.6']! + 1;
        else if (conf < 0.8) buckets['0.6–0.8'] = buckets['0.6–0.8']! + 1;
        else buckets['0.8–1.0'] = buckets['0.8–1.0']! + 1;
      }
    }
    return buckets;
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
      subsystemName: 'Card Recommendations',
      icon: '🃏',
      metrics: score.metrics,
      detail: _selected != null ? _buildDrill() : _buildMain(),
    );
  }

  Widget _buildMain() {
    if (_logs.isEmpty) {
      return _emptyState(
          'No recommendation calls logged yet.\nUse the Recommendations screen to trigger calls.');
    }
    final buckets = _confidenceBuckets();
    final maxBucket = buckets.values.fold(0, (a, b) => a > b ? a : b);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader('Confidence Score Distribution'),
          const SizedBox(height: 10),
          ...buckets.entries.map((e) => _histBar(e.key, e.value, maxBucket)),
          const SizedBox(height: 24),
          _sectionHeader('Call Log  (${_logs.length} calls)'),
          const SizedBox(height: 8),
          _buildTable(),
        ],
      ),
    );
  }

  Widget _histBar(String label, int count, int max) {
    final frac = max > 0 ? count / max : 0.0;
    final bucket = label;
    final isHigh = bucket == '0.8–1.0';
    final color = isHigh ? const Color(0xFF10B981) : const Color(0xFF00F5FF);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(label,
                style: GoogleFonts.jetBrainsMono(
                    fontSize: 10, color: Colors.white38)),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: frac,
                minHeight: 18,
                backgroundColor: Colors.white10,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text('$count',
              style: GoogleFonts.jetBrainsMono(
                  fontSize: 10, color: Colors.white38)),
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
        _tableHeader(['Timestamp', 'Provider', 'Recs', 'Latency', 'Mock']),
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
          _detailRow('Recommendations', '${log.output.length}'),
          if (log.errorMessage != null)
            _detailRow('Error', log.errorMessage!),
          const SizedBox(height: 12),
          _sectionHeader('Input Summary'),
          const SizedBox(height: 6),
          _jsonBox(log.inputSummary.toString()),
          const SizedBox(height: 12),
          _sectionHeader('Recommendations Output'),
          const SizedBox(height: 6),
          ...log.output.map(_recCard),
        ],
      ),
    );
  }

  Widget _recCard(Map<String, dynamic> rec) {
    final conf = (rec['confidenceScore'] as num?)?.toDouble() ?? 0.0;
    final color = conf >= 0.8
        ? const Color(0xFF10B981)
        : conf >= 0.5
            ? const Color(0xFFF59E0B)
            : const Color(0xFFEF4444);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B2A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  rec['cardName']?.toString() ?? '-',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      color: Colors.white,
                      fontWeight: FontWeight.bold),
                ),
              ),
              Text(
                'conf: ${conf.toStringAsFixed(2)}',
                style: GoogleFonts.jetBrainsMono(
                    fontSize: 11, color: color),
              ),
            ],
          ),
          if (rec['reason'] != null) ...[
            const SizedBox(height: 4),
            Text(rec['reason'].toString(),
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 11, color: Colors.white54)),
          ],
          if (rec['matchedCategories'] is List &&
              (rec['matchedCategories'] as List).isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Matched: ${(rec['matchedCategories'] as List).join(', ')}',
              style: GoogleFonts.jetBrainsMono(
                  fontSize: 10, color: Colors.white38),
            ),
          ],
          if (rec['expectedAnnualValue'] != null) ...[
            const SizedBox(height: 4),
            Text(
              '₹${rec['expectedAnnualValue']} expected annual value',
              style: GoogleFonts.jetBrainsMono(
                  fontSize: 10, color: const Color(0xFFFFD700)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _jsonBox(String content) => Container(
        padding: const EdgeInsets.all(10),
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFF071225),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white12),
        ),
        child: SelectableText(content,
            style: GoogleFonts.jetBrainsMono(
                fontSize: 10, color: Colors.white60)),
      );

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
              width: 120,
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

  Widget _emptyState(String message) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🃏', style: TextStyle(fontSize: 40)),
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
