import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cardcompass/core/services/pruning_audit_service.dart';
import 'package:cardcompass/features/evals/models/eval_metric.dart';
import 'package:cardcompass/features/evals/widgets/eval_shared_widgets.dart';

class PruningEvalPanel extends StatefulWidget {
  const PruningEvalPanel({super.key, required this.score});
  final SubsystemScore? score;

  @override
  State<PruningEvalPanel> createState() => _PruningEvalPanelState();
}

class _PruningEvalPanelState extends State<PruningEvalPanel> {
  final _auditService = PruningAuditService();
  List<Map<String, dynamic>> _logs = [];
  bool _loading = true;
  String _statusFilter = 'All';
  Map<String, dynamic>? _selected;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final logs = await _auditService.getLogs();
    if (!mounted) return;
    setState(() {
      _logs = logs;
      _loading = false;
    });
  }

  List<Map<String, dynamic>> get _filtered {
    if (_statusFilter == 'All') return _logs;
    return _logs.where((l) => l['reviewStatus'] == _statusFilter).toList();
  }

  Map<String, int> get _markerCounts {
    final counts = <String, int>{};
    for (final log in _logs) {
      final m = log['cutMarker']?.toString() ?? 'None';
      counts[m] = (counts[m] ?? 0) + 1;
    }
    return counts;
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
      subsystemName: 'Statement Pruning',
      icon: '✂️',
      metrics: score.metrics,
      detail: _selected != null ? _buildDetail() : _buildMain(),
    );
  }

  Widget _buildMain() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cut marker breakdown
          _sectionHeader('Cut Marker Frequency'),
          const SizedBox(height: 8),
          ..._buildMarkerBars(),
          const SizedBox(height: 20),
          // Status filter + table
          Row(
            children: [
              _sectionHeader('Pruning Runs (${_filtered.length})'),
              const Spacer(),
              _filterChip('All'),
              const SizedBox(width: 6),
              _filterChip('Needs PM Review'),
              const SizedBox(width: 6),
              _filterChip('Clean'),
            ],
          ),
          const SizedBox(height: 8),
          _buildTable(),
        ],
      ),
    );
  }

  List<Widget> _buildMarkerBars() {
    final entries = _markerCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final max = entries.isEmpty ? 1 : entries.first.value;
    return entries.take(6).map((e) {
      final frac = e.value / max;
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            SizedBox(
              width: 200,
              child: Text(
                e.key.length > 28 ? '…${e.key.substring(e.key.length - 26)}' : e.key,
                style: GoogleFonts.jetBrainsMono(
                    fontSize: 10, color: Colors.white54),
              ),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: frac,
                  minHeight: 10,
                  backgroundColor: Colors.white10,
                  valueColor: const AlwaysStoppedAnimation(Color(0xFF00F5FF)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text('${e.value}',
                style: GoogleFonts.jetBrainsMono(
                    fontSize: 10, color: Colors.white38)),
          ],
        ),
      );
    }).toList();
  }

  Widget _filterChip(String label) {
    final selected = _statusFilter == label;
    return GestureDetector(
      onTap: () => setState(() => _statusFilter = label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF00F5FF).withValues(alpha: 0.15)
              : Colors.white10,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
            color: selected
                ? const Color(0xFF00F5FF)
                : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 10,
            color: selected ? const Color(0xFF00F5FF) : Colors.white38,
          ),
        ),
      ),
    );
  }

  Widget _buildTable() {
    final logs = _filtered;
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(2),
        1: FlexColumnWidth(2),
        2: FixedColumnWidth(70),
        3: FixedColumnWidth(80),
        4: FixedColumnWidth(60),
      },
      border: TableBorder.all(color: Colors.white10, width: 0.5),
      children: [
        _tableHeader(
            ['Bank', 'Card Variant', 'Reduction', 'Status', 'Leaks']),
        ...logs.take(60).map(_tableRow),
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

  TableRow _tableRow(Map<String, dynamic> log) {
    final ratio = (log['reductionRatio'] as num?)?.toDouble() ?? 0;
    final leaks = (log['potentialLeaks'] as List?)?.length ?? 0;
    final isFlagged = log['isFlagged'] == true;

    return TableRow(
      children: [
        InkWell(
          onTap: () => setState(() => _selected = log),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Text(log['bankName']?.toString() ?? '-',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 11, color: const Color(0xFF00F5FF))),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(log['cardVariant']?.toString() ?? '-',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 11, color: Colors.white70)),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text('${ratio.toStringAsFixed(1)} %',
              style: GoogleFonts.jetBrainsMono(
                  fontSize: 10, color: Colors.white54)),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: isFlagged
                  ? const Color(0xFFF59E0B).withValues(alpha: 0.15)
                  : const Color(0xFF10B981).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              isFlagged ? 'FLAGGED' : 'CLEAN',
              style: GoogleFonts.jetBrainsMono(
                  fontSize: 8,
                  color: isFlagged
                      ? const Color(0xFFF59E0B)
                      : const Color(0xFF10B981)),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text('$leaks',
              style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  color: leaks > 0
                      ? const Color(0xFFEF4444)
                      : Colors.white24)),
        ),
      ],
    );
  }

  Widget _buildDetail() {
    final log = _selected!;
    final leaks = (log['potentialLeaks'] as List? ?? []);
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
                '${log['bankName']} · ${log['cardVariant']}',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    color: Colors.white,
                    fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _detailRow('File', log['fileName']?.toString() ?? '-'),
          _detailRow('Cut marker', log['cutMarker']?.toString() ?? 'None'),
          _detailRow(
              'Reduction',
              '${(log['reductionRatio'] as num?)?.toStringAsFixed(1) ?? '?'} %'
                  ' (${log['prunedCharacters']} chars removed)'),
          _detailRow('Status', log['reviewStatus']?.toString() ?? '-'),
          if (log['pmComment']?.toString().isNotEmpty == true)
            _detailRow('PM Comment', log['pmComment'].toString()),
          if (leaks.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text('⚠️  POTENTIAL LEAKS  (${leaks.length})',
                style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    color: const Color(0xFFF59E0B),
                    letterSpacing: 1)),
            const SizedBox(height: 8),
            ...leaks.map((l) => _leakRow(l)),
          ],
          const SizedBox(height: 14),
          _sectionHeader('Removed Text Preview'),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(12),
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFF071225),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white12),
            ),
            child: SelectableText(
              (log['removedText']?.toString() ?? '').length > 1200
                  ? '${log['removedText'].toString().substring(0, 1200)}…'
                  : log['removedText']?.toString() ?? '(empty)',
              style: GoogleFonts.jetBrainsMono(
                  fontSize: 10, color: Colors.white60),
            ),
          ),
        ],
      ),
    );
  }

  Widget _leakRow(dynamic l) {
    if (l is! Map) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('L${l['lineNumber']}  ',
              style: GoogleFonts.jetBrainsMono(
                  fontSize: 10, color: const Color(0xFFF59E0B))),
          Expanded(
            child: Text(l['lineContent']?.toString() ?? '-',
                style: GoogleFonts.jetBrainsMono(
                    fontSize: 10, color: Colors.white54)),
          ),
          const SizedBox(width: 6),
          Text(l['reason']?.toString() ?? '',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 9, color: Colors.white38)),
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
              width: 110,
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
