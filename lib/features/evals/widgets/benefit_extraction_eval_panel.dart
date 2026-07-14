import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cardcompass/features/evals/models/eval_metric.dart';
import 'package:cardcompass/features/evals/widgets/eval_shared_widgets.dart';

class BenefitExtractionEvalPanel extends StatefulWidget {
  const BenefitExtractionEvalPanel({super.key, required this.score});
  final SubsystemScore? score;

  @override
  State<BenefitExtractionEvalPanel> createState() =>
      _BenefitExtractionEvalPanelState();
}

class _BenefitExtractionEvalPanelState
    extends State<BenefitExtractionEvalPanel> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _records = [];
  bool _loading = true;
  Map<String, dynamic>? _drillTarget;

  // Reason code → human label
  static const _reasonLabels = {
    'evidence_not_in_source': 'Evidence not in source',
    'placeholder_benefit': 'Placeholder / zero-value',
    'card_identity_mismatch': 'Card identity mismatch',
    'bank_identity_mismatch': 'Bank identity mismatch',
    'missing_evidence': 'Missing evidence',
    'duplicate_benefit': 'Duplicate benefit',
    'unsupported_numeric_value': 'Unsupported number',
    'non_benefit_content': 'Non-benefit content',
    'no_supported_benefits': 'No benefits extracted',
    'category_conflict': 'Category conflict',
    'missing_fee_evidence': 'Missing fee evidence',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final raw = await _supabase
          .from('card_benefit_staging')
          .select(
              'id, card_id, status, calculated_confidence, validation_reasons, validation_warnings, source_url, validated_at, extracted_data')
          .order('validated_at', ascending: false)
          .limit(200);
      if (!mounted) return;
      setState(() {
        _records = (raw as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Aggregate reason codes across all records
  Map<String, int> get _reasonFrequency {
    final counts = <String, int>{};
    for (final r in _records) {
      final reasons = r['validation_reasons'];
      if (reasons is List) {
        for (final reason in reasons) {
          if (reason is Map) {
            final code = reason['code']?.toString() ?? 'unknown';
            counts[code] = (counts[code] ?? 0) + 1;
          }
        }
      }
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
      subsystemName: 'Benefit Extraction',
      icon: '🧬',
      metrics: score.metrics,
      detail: _drillTarget != null
          ? _buildDrillDown()
          : _buildTableAndReasons(),
    );
  }

  Widget _buildTableAndReasons() {
    final reasons = _reasonFrequency.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Reason code breakdown
          if (reasons.isNotEmpty) ...[
            _sectionHeader('Rejection Reason Breakdown'),
            const SizedBox(height: 8),
            ...reasons.take(8).map((e) => _reasonRow(e.key, e.value)),
            const SizedBox(height: 20),
          ],
          _sectionHeader('Staging Records  (${_records.length})'),
          const SizedBox(height: 8),
          _buildTable(),
        ],
      ),
    );
  }

  Widget _reasonRow(String code, int count) {
    final label = _reasonLabels[code] ?? code;
    final max = _reasonFrequency.values.fold(0, (a, b) => a > b ? a : b);
    final frac = max > 0 ? count / max : 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 180,
            child: Text(label,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 11, color: Colors.white60)),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: frac,
                minHeight: 8,
                backgroundColor: Colors.white10,
                valueColor: const AlwaysStoppedAnimation(Color(0xFFEF4444)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text('$count',
              style: GoogleFonts.jetBrainsMono(
                  fontSize: 11, color: Colors.white38)),
        ],
      ),
    );
  }

  Widget _buildTable() {
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(3),
        1: FixedColumnWidth(90),
        2: FixedColumnWidth(70),
        3: FixedColumnWidth(50),
      },
      border: TableBorder.all(color: Colors.white10, width: 0.5),
      children: [
        _tableHeader(['Card / Source', 'Status', 'Confidence', 'Warns']),
        ..._records.take(50).map(_tableRow),
      ],
    );
  }

  TableRow _tableHeader(List<String> cols) {
    return TableRow(
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
  }

  TableRow _tableRow(Map<String, dynamic> r) {
    final status = r['status']?.toString() ?? '-';
    final conf = (r['calculated_confidence'] as num?)?.toDouble() ?? 0.0;
    final warnings = (r['validation_warnings'] as List?)?.length ?? 0;
    final url = r['source_url']?.toString() ?? '-';
    final isAccepted = status == 'pending';

    return TableRow(
      children: [
        InkWell(
          onTap: () => setState(() => _drillTarget = r),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              url.length > 40 ? '…${url.substring(url.length - 38)}' : url,
              style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  color: const Color(0xFF00F5FF),
                  decoration: TextDecoration.underline),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: isAccepted
                  ? const Color(0xFF10B981).withValues(alpha: 0.15)
                  : const Color(0xFFEF4444).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              isAccepted ? 'PENDING' : 'REJECTED',
              style: GoogleFonts.jetBrainsMono(
                  fontSize: 9,
                  color: isAccepted
                      ? const Color(0xFF10B981)
                      : const Color(0xFFEF4444)),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            '${(conf * 100).toStringAsFixed(0)} %',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10,
              color: conf >= 0.8
                  ? const Color(0xFF10B981)
                  : conf >= 0.5
                      ? const Color(0xFFF59E0B)
                      : const Color(0xFFEF4444),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            '$warnings',
            style: GoogleFonts.jetBrainsMono(
                fontSize: 10,
                color: warnings > 0
                    ? const Color(0xFFF59E0B)
                    : Colors.white24),
          ),
        ),
      ],
    );
  }

  Widget _buildDrillDown() {
    final r = _drillTarget!;
    final reasons = (r['validation_reasons'] as List? ?? [])
        .whereType<Map>()
        .toList();
    final warnings = (r['validation_warnings'] as List? ?? [])
        .whereType<Map>()
        .toList();
    final extracted = r['extracted_data'];

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
                onPressed: () => setState(() => _drillTarget = null),
              ),
              const SizedBox(width: 4),
              Text(
                'Record drill-down',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    color: Colors.white,
                    fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _detailRow('Source URL', r['source_url']?.toString() ?? '-'),
          _detailRow(
              'Status', r['status']?.toString() ?? '-'),
          _detailRow(
            'Confidence',
            '${((r['calculated_confidence'] as num?)?.toDouble() ?? 0) * 100 ~/ 1} %',
          ),
          _detailRow('Validated at',
              r['validated_at']?.toString().substring(0, 19) ?? '-'),
          if (reasons.isNotEmpty) ...[
            const SizedBox(height: 12),
            _sectionHeader('Rejection Reasons (${reasons.length})'),
            ...reasons.map((rn) => _codeRow(
                rn['code']?.toString() ?? '-',
                rn['message']?.toString() ?? '')),
          ],
          if (warnings.isNotEmpty) ...[
            const SizedBox(height: 12),
            _sectionHeader('Warnings (${warnings.length})'),
            ...warnings.map((w) => _codeRow(
                w['code']?.toString() ?? '-',
                w['source_excerpt']?.toString() ?? w['message']?.toString() ?? '')),
          ],
          if (extracted != null) ...[
            const SizedBox(height: 12),
            _sectionHeader('Extracted Data'),
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
                extracted.toString(),
                style: GoogleFonts.jetBrainsMono(
                    fontSize: 10, color: Colors.white60),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) => Text(
        title.toUpperCase(),
        style: GoogleFonts.jetBrainsMono(
            fontSize: 10,
            color: Colors.white38,
            letterSpacing: 1.2),
      );

  Widget _detailRow(String key, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 120,
              child: Text(key,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 11, color: Colors.white38)),
            ),
            Expanded(
              child: SelectableText(value,
                  style: GoogleFonts.jetBrainsMono(
                      fontSize: 11, color: Colors.white70)),
            ),
          ],
        ),
      );

  Widget _codeRow(String code, String detail) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(code,
                  style: GoogleFonts.jetBrainsMono(
                      fontSize: 9, color: const Color(0xFFEF4444))),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(detail,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 11, color: Colors.white54)),
            ),
          ],
        ),
      );
}
