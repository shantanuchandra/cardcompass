import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cardcompass/features/evals/models/eval_metric.dart';
import 'package:cardcompass/features/evals/models/eval_fixture.dart';
import 'package:cardcompass/features/evals/services/eval_aggregator.dart';
import 'package:cardcompass/features/evals/widgets/eval_shared_widgets.dart';
import 'package:cardcompass/features/evals/widgets/benefit_extraction_eval_panel.dart';
import 'package:cardcompass/features/evals/widgets/pruning_eval_panel.dart';
import 'package:cardcompass/features/evals/widgets/transaction_parsing_eval_panel.dart';
import 'package:cardcompass/features/evals/widgets/recommendations_eval_panel.dart';
import 'package:cardcompass/features/evals/widgets/spending_opt_eval_panel.dart';
import 'package:cardcompass/features/evals/widgets/reward_intelligence_eval_panel.dart';
import 'package:cardcompass/features/evals/widgets/benefit_repair_eval_panel.dart';

class AiEvalsScreen extends StatefulWidget {
  const AiEvalsScreen({super.key});

  @override
  State<AiEvalsScreen> createState() => _AiEvalsScreenState();
}

class _AiEvalsScreenState extends State<AiEvalsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _aggregator = EvalAggregator();

  bool _isLiveMode = true;
  bool _isLoading = false;
  String? _error;
  EvalFixture? _fixture;

  List<SubsystemScore> _scores = [];
  double _healthScore = 0;

  static const _tabDefs = [
    (Icons.biotech_outlined, Icons.biotech, 'Benefit Extraction'),
    (Icons.content_cut_outlined, Icons.content_cut, 'Statement Pruning'),
    (Icons.receipt_long_outlined, Icons.receipt_long, 'Txn Parsing'),
    (Icons.style_outlined, Icons.style, 'Card Recs'),
    (Icons.bar_chart_outlined, Icons.bar_chart, 'Spend Opts'),
    (Icons.diamond_outlined, Icons.diamond, 'Rewards'),
    (Icons.build_outlined, Icons.build, 'Benefit Repair'),
  ];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 7, vsync: this);
    _refresh();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() { _isLoading = true; _error = null; });
    try {
      final scores = _isLiveMode
          ? await _aggregator.computeAll()
          : (_fixture != null
              ? await _aggregator.computeFromFixture(_fixture!)
              : await _aggregator.computeAll());
      if (!mounted) return;
      setState(() {
        _scores = scores;
        _healthScore = _aggregator.computeHealthScore(scores);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  Future<void> _importFixture() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0D1B2A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Import Fixture JSON',
            style: GoogleFonts.plusJakartaSans(
                color: Colors.white, fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: 500,
          child: TextField(
            controller: controller,
            maxLines: 12,
            style: GoogleFonts.jetBrainsMono(fontSize: 11, color: Colors.white70),
            decoration: InputDecoration(
              hintText: 'Paste fixture JSON here…',
              hintStyle: GoogleFonts.jetBrainsMono(color: Colors.white24, fontSize: 11),
              filled: true,
              fillColor: const Color(0xFF071225),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFF1E293B)),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.plusJakartaSans(color: Colors.white38)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF00F5FF)),
            child: Text('Import',
                style: GoogleFonts.plusJakartaSans(
                    color: const Color(0xFF050E1A), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      try {
        final fixture = EvalFixture.fromJsonString(result);
        setState(() {
          _fixture = fixture;
          _isLiveMode = false;
        });
        _refresh();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Invalid fixture JSON: $e'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    }
  }

  Future<void> _exportFixture() async {
    final fixture = await _aggregator.exportFixture(label: 'Export ${_lastUpdateLabel()}');
    final json = fixture.toJsonString();
    await Clipboard.setData(ClipboardData(text: json));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Fixture JSON copied to clipboard',
            style: GoogleFonts.plusJakartaSans()),
        backgroundColor: const Color(0xFF10B981),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050E1A),
      appBar: _buildAppBar(),
      body: _isLoading && _scores.isEmpty
          ? const _LoadingPlaceholder()
          : _error != null && _scores.isEmpty
              ? _ErrorPlaceholder(error: _error!, onRetry: _refresh)
              : Column(
                  children: [
                    _buildOverallScore(),
                    _buildTabBar(),
                    Expanded(child: _buildTabViews()),
                  ],
                ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF071225),
      elevation: 0,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: const Color(0xFF1E293B)),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF00F5FF), Color(0xFF8B5CF6)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.science, size: 16, color: Color(0xFF050E1A)),
          ),
          const SizedBox(width: 10),
          Text('AI EVALS',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 2,
              )),
          const SizedBox(width: 10),
          _ModeBadge(isLive: _isLiveMode),
        ],
      ),
      actions: [
        // Toggle live / fixture
        Tooltip(
          message: _isLiveMode ? 'Switch to Fixture mode' : 'Switch to Live mode',
          child: InkWell(
            onTap: () => setState(() { _isLiveMode = !_isLiveMode; _refresh(); }),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _isLiveMode
                    ? const Color(0xFF10B981).withValues(alpha: 0.12)
                    : const Color(0xFF8B5CF6).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: _isLiveMode
                      ? const Color(0xFF10B981).withValues(alpha: 0.4)
                      : const Color(0xFF8B5CF6).withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _isLiveMode ? Icons.sensors : Icons.folder_open,
                    size: 12,
                    color: _isLiveMode
                        ? const Color(0xFF10B981)
                        : const Color(0xFF8B5CF6),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    _isLiveMode ? 'LIVE' : 'FIXTURE',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: _isLiveMode
                          ? const Color(0xFF10B981)
                          : const Color(0xFF8B5CF6),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        Tooltip(
          message: 'Import Fixture',
          child: IconButton(
            icon: const Icon(Icons.upload_file, size: 18, color: Colors.white54),
            onPressed: _importFixture,
          ),
        ),
        Tooltip(
          message: 'Export Fixture to clipboard',
          child: IconButton(
            icon: const Icon(Icons.file_download_outlined, size: 18, color: Colors.white54),
            onPressed: _exportFixture,
          ),
        ),
        Tooltip(
          message: 'Refresh',
          child: IconButton(
            icon: _isLoading
                ? const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white38))
                : const Icon(Icons.refresh, size: 18, color: Colors.white54),
            onPressed: _isLoading ? null : _refresh,
          ),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildOverallScore() {
    final healthColor = _healthScore >= 80
        ? const Color(0xFF10B981)
        : _healthScore >= 50
            ? const Color(0xFFF59E0B)
            : const Color(0xFFEF4444);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      decoration: const BoxDecoration(
        color: Color(0xFF071225),
        border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Big score gauge
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('OVERALL AI HEALTH',
                  style: GoogleFonts.jetBrainsMono(
                      fontSize: 9, color: Colors.white38, letterSpacing: 1.5)),
              const SizedBox(height: 6),
              EvalScoreChip(
                  score: _healthScore,
                  label: '/ 100',
                  size: EvalChipSize.large),
            ],
          ),
          const SizedBox(width: 28),

          // Progress bar
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: (_healthScore / 100).clamp(0.0, 1.0),
                    minHeight: 10,
                    backgroundColor: Colors.white10,
                    valueColor: AlwaysStoppedAnimation(healthColor),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _healthScore < 40
                      ? 'Needs attention — run pipeline to collect eval data'
                      : _healthScore < 70
                          ? 'Moderate health — some systems need review'
                          : 'AI systems healthy',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 10, color: Colors.white38),
                ),
              ],
            ),
          ),

          const SizedBox(width: 28),

          // Per-subsystem mini bars
          Expanded(
            flex: 3,
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (int i = 0; i < _scores.length; i++)
                  _SubsystemPill(
                    score: _scores[i],
                    icon: _tabDefs[i].$1,
                    shortName: _tabDefs[i].$3.split(' ').first,
                    onTap: () => _tabs.animateTo(i),
                  ),
              ],
            ),
          ),

          const SizedBox(width: 16),
          Text(
            _isLoading
                ? '⟳ refreshing…'
                : 'Updated ${_lastUpdateLabel()}',
            style: GoogleFonts.jetBrainsMono(fontSize: 9, color: Colors.white24),
          ),
        ],
      ),
    );
  }

  String _lastUpdateLabel() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildTabBar() {
    return Container(
      color: const Color(0xFF071225),
      child: TabBar(
        controller: _tabs,
        isScrollable: true,
        indicatorColor: const Color(0xFF00F5FF),
        indicatorWeight: 2,
        labelColor: const Color(0xFF00F5FF),
        unselectedLabelColor: Colors.white38,
        tabAlignment: TabAlignment.start,
        labelPadding: EdgeInsets.zero,
        tabs: List.generate(
          7,
          (i) => _buildTab(_scores.length > i ? _scores[i] : null, i),
        ),
      ),
    );
  }

  Widget _buildTab(SubsystemScore? score, int index) {
    final (inactiveIcon, activeIcon, label) = _tabDefs[index];
    final bucket = score?.bucket;
    final dotColor = switch (bucket) {
      EvalHealthBucket.good => const Color(0xFF10B981),
      EvalHealthBucket.warn => const Color(0xFFF59E0B),
      EvalHealthBucket.bad  => const Color(0xFFEF4444),
      null                  => Colors.white24,
    };

    return AnimatedBuilder(
      animation: _tabs,
      builder: (context, _) {
        final isSelected = _tabs.index == index;
        return Tab(
          height: 52,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isSelected ? activeIcon : inactiveIcon,
                  size: 15,
                  color: isSelected ? const Color(0xFF00F5FF) : Colors.white38,
                ),
                const SizedBox(width: 6),
                Text(label,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                      color: isSelected ? const Color(0xFF00F5FF) : Colors.white38,
                    )),
                const SizedBox(width: 5),
                Container(
                  width: 6, height: 6,
                  decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTabViews() {
    SubsystemScore? score(int i) => _scores.length > i ? _scores[i] : null;
    return TabBarView(
      controller: _tabs,
      children: [
        BenefitExtractionEvalPanel(score: score(0)),
        PruningEvalPanel(score: score(1)),
        TransactionParsingEvalPanel(score: score(2)),
        RecommendationsEvalPanel(score: score(3)),
        SpendingOptEvalPanel(score: score(4)),
        RewardIntelligenceEvalPanel(score: score(5)),
        BenefitRepairEvalPanel(score: score(6)),
      ],
    );
  }
}

// ─── Subsystem pill in header ──────────────────────────────────────────────────

class _SubsystemPill extends StatelessWidget {
  const _SubsystemPill({
    required this.score,
    required this.icon,
    required this.shortName,
    required this.onTap,
  });

  final SubsystemScore score;
  final IconData icon;
  final String shortName;
  final VoidCallback onTap;

  Color get _color {
    switch (score.bucket) {
      case EvalHealthBucket.good: return const Color(0xFF10B981);
      case EvalHealthBucket.warn: return const Color(0xFFF59E0B);
      case EvalHealthBucket.bad:  return const Color(0xFFEF4444);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '${score.name}: ${(score.score * 100).toStringAsFixed(0)}/100',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: _color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _color.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 11, color: _color),
              const SizedBox(width: 4),
              Text(shortName,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 10, color: _color, fontWeight: FontWeight.w600)),
              const SizedBox(width: 4),
              Text(
                '${(score.score * 100).toStringAsFixed(0)}',
                style: GoogleFonts.jetBrainsMono(fontSize: 10, color: _color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Mode badge ────────────────────────────────────────────────────────────────

class _ModeBadge extends StatelessWidget {
  const _ModeBadge({required this.isLive});
  final bool isLive;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

// ─── Placeholders ──────────────────────────────────────────────────────────────

class _LoadingPlaceholder extends StatelessWidget {
  const _LoadingPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 40, height: 40,
            child: CircularProgressIndicator(
              strokeWidth: 3, color: Color(0xFF00F5FF),
            ),
          ),
          const SizedBox(height: 20),
          Text('Computing AI health scores…',
              style: GoogleFonts.jetBrainsMono(fontSize: 13, color: Colors.white38)),
        ],
      ),
    );
  }
}

class _ErrorPlaceholder extends StatelessWidget {
  const _ErrorPlaceholder({required this.error, required this.onRetry});
  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Color(0xFFEF4444), size: 48),
            const SizedBox(height: 16),
            Text(error,
                textAlign: TextAlign.center,
                style: GoogleFonts.jetBrainsMono(fontSize: 12, color: Colors.white38)),
            const SizedBox(height: 16),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Retry'),
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}
