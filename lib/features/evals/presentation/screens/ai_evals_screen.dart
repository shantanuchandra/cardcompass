import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cardcompass/core/theme.dart';
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

/// Top-level AI Evals Dashboard screen — navigates to /admin/evals.
///
/// Shows a weighted Overall AI Health Score plus 7 subsystem tabs:
///   1. Benefit Extraction   5. Spending Optimizations
///   2. Statement Pruning    6. Reward Intelligence
///   3. Transaction Parsing  7. Benefit Repair Pass
///   4. Card Recommendations
class AiEvalsScreen extends StatefulWidget {
  const AiEvalsScreen({super.key});

  @override
  State<AiEvalsScreen> createState() => _AiEvalsScreenState();
}

class _AiEvalsScreenState extends State<AiEvalsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _aggregator = EvalAggregator();

  bool _isLiveMode = true;   // false = fixture mode
  bool _isLoading = false;
  String? _error;
  EvalFixture? _fixture;

  List<SubsystemScore> _scores = [];
  double _healthScore = 0;

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

  // ─── Data loading ──────────────────────────────────────────────────────────

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
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
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  // ─── Import / Export ───────────────────────────────────────────────────────

  Future<void> _importFixture() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0D1B2A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Import Fixture JSON',
          style: GoogleFonts.plusJakartaSans(
              color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: SizedBox(
          width: 480,
          child: TextField(
            controller: controller,
            maxLines: 12,
            style: GoogleFonts.jetBrainsMono(fontSize: 11, color: Colors.white70),
            decoration: InputDecoration(
              hintText: 'Paste fixture JSON here...',
              hintStyle: const TextStyle(color: Colors.white24),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide:
                    const BorderSide(color: Color(0xFF334155)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide:
                    const BorderSide(color: Color(0xFF334155)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide:
                    const BorderSide(color: Color(0xFF00F5FF)),
              ),
              filled: true,
              fillColor: const Color(0xFF071225),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white38)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.black,
            ),
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Import'),
          ),
        ],
      ),
    );

    if (result == null || result.trim().isEmpty) return;
    try {
      final fixture = EvalFixture.fromJsonString(result.trim());
      setState(() {
        _fixture = fixture;
        _isLiveMode = false;
      });
      await _refresh();
      if (mounted) {
        _showSnack('✅ Fixture "${fixture.label}" imported (${fixture.exportedAt.substring(0, 10)})');
      }
    } catch (e) {
      if (mounted) _showSnack('❌ Invalid fixture: $e', isError: true);
    }
  }

  Future<void> _exportFixture() async {
    setState(() => _isLoading = true);
    try {
      final fixture = await _aggregator.exportFixture();
      final jsonStr = fixture.toJsonString();
      await Clipboard.setData(ClipboardData(text: jsonStr));
      if (mounted) _showSnack('📋 Fixture copied to clipboard (${fixture.label})');
    } catch (e) {
      if (mounted) _showSnack('❌ Export failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message,
          style: GoogleFonts.plusJakartaSans(
              color: isError ? Colors.white : Colors.black)),
      backgroundColor: isError ? AppTheme.errorColor : AppTheme.primaryColor,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  // ─── Tab label ─────────────────────────────────────────────────────────────

  Widget _tabLabel(SubsystemScore? score, int index) {
    final labels = [
      ('🧬', 'Benefit\nExtraction'),
      ('✂️', 'Statement\nPruning'),
      ('🔬', 'Txn\nParsing'),
      ('🃏', 'Card\nRecs'),
      ('📊', 'Spend\nOptimize'),
      ('💎', 'Reward\nIntel'),
      ('🔧', 'Benefit\nRepair'),
    ];
    final (icon, name) = labels[index];
    final bucket = score?.bucket;

    final dotColor = switch (bucket) {
      EvalHealthBucket.good => const Color(0xFF10B981),
      EvalHealthBucket.warn => const Color(0xFFF59E0B),
      EvalHealthBucket.bad => const Color(0xFFEF4444),
      null => Colors.white24,
    };

    return Tab(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(icon, style: const TextStyle(fontSize: 13)),
              const SizedBox(width: 4),
              Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                      color: dotColor, shape: BoxShape.circle)),
            ],
          ),
          const SizedBox(height: 2),
          Text(name,
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(fontSize: 10)),
        ],
      ),
    );
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

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
      title: Row(
        children: [
          Text(
            'AI EVALS',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppTheme.primaryColor,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              _isLiveMode ? 'LIVE' : 'FIXTURE',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 10,
                color: _isLiveMode
                    ? AppTheme.successColor
                    : AppTheme.warningColor,
              ),
            ),
          ),
          if (_fixture != null && !_isLiveMode) ...[
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                _fixture!.label,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 11, color: Colors.white38),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
      actions: [
        // Live / fixture toggle
        Tooltip(
          message: _isLiveMode ? 'Switch to Fixture mode' : 'Switch to Live mode',
          child: IconButton(
            icon: Icon(
              _isLiveMode ? Icons.bolt : Icons.folder_open_outlined,
              color: _isLiveMode ? AppTheme.successColor : AppTheme.warningColor,
            ),
            onPressed: () async {
              if (_isLiveMode) {
                await _importFixture();
              } else {
                setState(() {
                  _isLiveMode = true;
                  _fixture = null;
                });
                await _refresh();
              }
            },
          ),
        ),
        // Export
        Tooltip(
          message: 'Export fixture to clipboard',
          child: IconButton(
            icon: const Icon(Icons.upload_outlined, color: Colors.white54),
            onPressed: _exportFixture,
          ),
        ),
        // Refresh
        Tooltip(
          message: 'Refresh',
          child: IconButton(
            icon: _isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white38))
                : const Icon(Icons.refresh, color: Colors.white54),
            onPressed: _isLoading ? null : _refresh,
          ),
        ),
      ],
    );
  }

  Widget _buildOverallScore() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      decoration: const BoxDecoration(
        color: Color(0xFF071225),
        border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'OVERALL AI HEALTH',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  color: Colors.white38,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 4),
              EvalScoreChip(
                score: _healthScore,
                label: '/ 100',
                size: EvalChipSize.large,
              ),
            ],
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final s in _scores)
                  _MiniScoreBadge(name: s.icon, score: s.score),
              ],
            ),
          ),
          Text(
            _isLoading ? 'Refreshing…' : 'Last updated ${_lastUpdateLabel()}',
            style: GoogleFonts.jetBrainsMono(
                fontSize: 9, color: Colors.white24),
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
        indicatorColor: AppTheme.primaryColor,
        indicatorWeight: 2,
        labelColor: AppTheme.primaryColor,
        unselectedLabelColor: Colors.white38,
        tabs: List.generate(
          7,
          (i) => _tabLabel(_scores.length > i ? _scores[i] : null, i),
        ),
      ),
    );
  }

  Widget _buildTabViews() {
    // If no scores yet, show empty state per tab
    SubsystemScore? _score(int i) =>
        _scores.length > i ? _scores[i] : null;

    return TabBarView(
      controller: _tabs,
      children: [
        BenefitExtractionEvalPanel(score: _score(0)),
        PruningEvalPanel(score: _score(1)),
        TransactionParsingEvalPanel(score: _score(2)),
        RecommendationsEvalPanel(score: _score(3)),
        SpendingOptEvalPanel(score: _score(4)),
        RewardIntelligenceEvalPanel(score: _score(5)),
        BenefitRepairEvalPanel(score: _score(6)),
      ],
    );
  }
}

// ─── Mini badge in the header row ─────────────────────────────────────────────

class _MiniScoreBadge extends StatelessWidget {
  const _MiniScoreBadge({required this.name, required this.score});
  final String name;
  final double score;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(name, style: const TextStyle(fontSize: 13)),
        const SizedBox(width: 3),
        EvalScoreChip(score: score * 100, size: EvalChipSize.small),
      ],
    );
  }
}

// ─── Placeholders ─────────────────────────────────────────────────────────────

class _LoadingPlaceholder extends StatelessWidget {
  const _LoadingPlaceholder();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: Color(0xFF00F5FF),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Computing AI health scores…',
            style: GoogleFonts.jetBrainsMono(
                fontSize: 14, color: Colors.white38),
          ),
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
            const Icon(Icons.error_outline,
                color: Color(0xFFEF4444), size: 48),
            const SizedBox(height: 16),
            Text(error,
                textAlign: TextAlign.center,
                style: GoogleFonts.jetBrainsMono(
                    fontSize: 12, color: Colors.white38)),
            const SizedBox(height: 16),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFEF4444)),
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
