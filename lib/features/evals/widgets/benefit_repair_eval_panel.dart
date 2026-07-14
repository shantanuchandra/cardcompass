import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cardcompass/features/evals/models/eval_metric.dart';
import 'package:cardcompass/features/evals/widgets/eval_shared_widgets.dart';

class BenefitRepairEvalPanel extends StatefulWidget {
  const BenefitRepairEvalPanel({super.key, required this.score});
  final SubsystemScore? score;

  @override
  State<BenefitRepairEvalPanel> createState() => _BenefitRepairEvalPanelState();
}

class _BenefitRepairEvalPanelState extends State<BenefitRepairEvalPanel> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _records = [];
  bool _loading = true;
  Map<String, dynamic>? _selected;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final raw = await _supabase
          .from('card_benefit_staging')
          .select('id, card_id, source_url, status, repair_metadata, validated_at')
          .not('repair_metadata', 'is', null)
          .order('validated_at', ascending: false)
          .limit(200);
      if (!mounted) return;
      setState(() {
        _records = (raw as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .where((r) {
          final rm = r['repair_metadata'];
          return rm is Map && rm['attempted'] == true;
        }).toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Rolling outcome stats
  Map<String, int> _outcomeStats() {
    int totalTargets = 0, accepted = 0, zero = 0;
    for (final r in _records) {
      final rm = r['repair_metadata'] as Map;
      final targets = (rm['targets'] as List?)?.length ?? 0;
      final acc = (rm['accepted_count'] as num?)?.toInt() ?? 0;
      totalTargets += targets;
      accepted += acc;
      if (acc == 0 && targets > 0) zero++;
    }
    return {
      'totalTargets': totalTargets,
      'accepted': accepted,
      'zeroAccepted': zero,
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
      subsystemName: 'Benefit Repair Pass',
      icon: '🔧',
      metrics: score.metrics,
      detail: _selected != null ? _buildDrill() : _buildMain(),
    );
  }

  Widget _buildMain() {
    if (_records.isEmpty) {
      return _emptyState('No repair pass records found.\nRun the benefit extraction pipeline to generate repair data.');
    }

    final stats = _outcomeStats();
    final total = stats['totalTargets']!;
    final accepted = stats['accepted']!;
    final hitRate = total > 0 ? accepted / total : 0.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hit rate bar
          _sectionHeader('Repair Target Hit Rate'),
          const SizedBox(height: 10),
          _hitRateBar(hitRate, accepted, total),
          const SizedBox(height: 24),
          _sectionHeader('Records with Repair Metadata  (${_records.length})'),
          const SizedBox(height: 8),
          _buildTable(),
        ],
      ),
    );
  }

  Widget _hitRateBar(double rate, int accepted, int total) {
    final color = rate >= 0.8
        ? const Color(0xFF10B981)
        : rate >= 0.4
            ? const Color(0xFFF59E0B)
            : const Color(0xFFEF4444);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: rate.clamp(0.0, 1.0),
            minHeight: 24,
            backgroundColor: Colors.white10,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '$accepted accepted / $total targets  '
          '(${(rate * 100).toStringAsFixed(1)} %)',
          style: GoogleFonts.jetBrainsMono(fontSize: 11, color: color),
        ),
      ],
    );
  }

  Widget _buildTable() {
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(3),
        1: FixedColumnWidth(70),
        2: FixedColumnWidth(70),
        3: FixedColumnWidth(70),
      },
      border: TableBorder.all(color: Colors.white10, width: 0.5),
      children: [
        _tableHeader(['Source URL', 'Targets', 'Accepted', 'Status']),
        ..._records.take(60).map(_tableRow),
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

  TableRow _tableRow(Map<String, dynamic> r) {
    final rm = r['repair_metadata'] as Map? ?? {};
    final targets = (rm['targets'] as List?)?.length ?? 0;
    final accepted = (rm['accepted_count'] as num?)?.toInt() ?? 0;
    final status = r['status']?.toString() ?? '-';
    final url = r['source_url']?.toString() ?? '-';
    final hitFrac = targets > 0 ? accepted / targets : 0.0;
    final color = hitFrac >= 0.8
        ? const Color(0xFF10B981)
        : hitFrac >= 0.4
            ? const Color(0xFFF59E0B)
            : const Color(0xFFEF4444);

    return TableRow(
      children: [
        InkWell(
          onTap: () => setState(() => _selected = r),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              url.length > 40 ? '…${url.substring(url.length - 38)}' : url,
              style: GoogleFonts.jetBrainsMono(
                  fontSize: 10, color: const Color(0xFF00F5FF)),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text('$targets',
              style: GoogleFonts.jetBrainsMono(
                  fontSize: 10, color: Colors.white54)),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text('$accepted',
              style: GoogleFonts.jetBrainsMono(fontSize: 10, color: color)),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(status,
              style: GoogleFonts.jetBrainsMono(
                  fontSize: 10, color: Colors.white38)),
        ),
      ],
    );
  }

  Widget _buildDrill() {
    final r = _selected!;
    final rm = r['repair_metadata'] as Map? ?? {};
    final targets = (rm['targets'] as List? ?? []).whereType<Map>().toList();
    final accepted = (rm['accepted_count'] as num?)?.toInt() ?? 0;

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
              Expanded(
                child: Text(
                  'Repair Pass Drill-down',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      color: Colors.white,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _detailRow('Source URL', r['source_url']?.toString() ?? '-'),
          _detailRow('Status', r['status']?.toString() ?? '-'),
          _detailRow('Targets', '${targets.length}'),
          _detailRow('Accepted', '$accepted'),
          _detailRow(
            'Hit rate',
            targets.isEmpty
                ? '–'
                : '${(accepted / targets.length * 100).toStringAsFixed(1)} %',
          ),
          const SizedBox(height: 14),
          _sectionHeader('Repair Targets  (${targets.length})'),
          const SizedBox(height: 8),
          ...targets.map(_targetCard),
        ],
      ),
    );
  }

  Widget _targetCard(Map t) {
    final kind = t['kind']?.toString() ?? '-';
    final excerpt = t['source_excerpt']?.toString() ?? '-';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B2A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF8B5CF6).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(kind,
                    style: GoogleFonts.jetBrainsMono(
                        fontSize: 9, color: const Color(0xFF8B5CF6))),
              ),
              const SizedBox(width: 8),
              Text(t['id']?.toString() ?? '-',
                  style: GoogleFonts.jetBrainsMono(
                      fontSize: 9, color: Colors.white24)),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            excerpt,
            style: GoogleFonts.jetBrainsMono(
                fontSize: 10, color: Colors.white60),
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
              width: 100,
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
              const Text('🔧', style: TextStyle(fontSize: 40)),
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
