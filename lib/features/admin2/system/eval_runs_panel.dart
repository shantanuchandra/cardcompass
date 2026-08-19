import 'package:flutter/material.dart';
import '../../../core/theme/brand_components.dart';
import '../../../core/theme/brand_tokens.dart';
import '../data/admin_operator_repository.dart';
import 'eval_models.dart';

abstract interface class EvalDataSource {
  Future<EvalConfigCatalog> configs();
  Future<EvalRunsPage> runs({
    int page = 1,
    int limit = 20,
    String? status,
    EvalFeature? feature,
  });
  Future<EvalRunDetail> detail(
    String id, {
    int resultPage = 1,
    int resultLimit = 25,
  });
  Future<EvalRunReceipt> start(EvalStartRequest request);
  Future<EvalRunReceipt> cancel(String id, String observed);
  Future<EvalRunReceipt> resumeFailed(String id, String observed);
}

class EvalRunsPanel extends StatefulWidget {
  const EvalRunsPanel({
    super.key,
    required this.source,
    this.onAuthenticationRequired,
    this.onAccessDenied,
    this.initialRunId,
  });
  final EvalDataSource source;
  final Future<void> Function()? onAuthenticationRequired;
  final VoidCallback? onAccessDenied;
  final String? initialRunId;
  @override
  State<EvalRunsPanel> createState() => _EvalRunsPanelState();
}

class _EvalRunsPanelState extends State<EvalRunsPanel> {
  EvalConfigCatalog? _configs;
  EvalRunsPage? _runs;
  EvalRunDetail? _detail;
  String? _selectedId;
  bool _loading = true,
      _refreshing = false,
      _acting = false,
      _compactDetail = false;
  Object? _error;
  String? _notice;
  int _generation = 0;
  int _page = 1;
  int _resultPage = 1;
  int _maximumCases = 10;
  int _latencyCeilingMs = 5000;
  String? _candidateKey;
  String? _statusFilter;
  @override
  void initState() {
    super.initState();
    _selectedId = widget.initialRunId;
    _load(initial: true);
  }

  Future<void> _effects(Object e) async {
    if (e is AdminAuthenticationRequired) {
      await widget.onAuthenticationRequired?.call();
    }
    if (e is AdminAccessDenied) widget.onAccessDenied?.call();
  }

  Future<void> _load({bool initial = false}) async {
    final generation = ++_generation;
    if (initial) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else {
      setState(() {
        _refreshing = true;
        _error = null;
      });
    }
    try {
      final values = await Future.wait([
        widget.source.configs(),
        widget.source.runs(page: _page, status: _statusFilter),
      ]);
      if (!mounted || generation != _generation) return;
      final page = values[1] as EvalRunsPage;
      var id = _selectedId;
      if (id != null && !page.items.any((r) => r.id == id)) id = null;
      id ??= page.items.firstOrNull?.id;
      final detail = id == null
          ? null
          : await widget.source.detail(id, resultPage: _resultPage);
      if (!mounted || generation != _generation) return;
      setState(() {
        _configs = values[0] as EvalConfigCatalog;
        _runs = page;
        _selectedId = id;
        _detail = detail;
        _loading = false;
        _refreshing = false;
      });
    } catch (e) {
      if (!mounted || generation != _generation) return;
      await _effects(e);
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
        _refreshing = false;
      });
    }
  }

  Future<void> _select(EvalRun run) async {
    setState(() {
      _selectedId = run.id;
      _resultPage = 1;
      _compactDetail = true;
      _acting = true;
    });
    try {
      final d = await widget.source.detail(run.id, resultPage: 1);
      if (mounted) setState(() => _detail = d);
    } catch (e) {
      await _effects(e);
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _start() async {
    final catalog = _configs;
    if (catalog == null || catalog.candidates.isEmpty) return;
    final candidate = catalog.candidates
        .where((value) => value.key == _candidateKey)
        .firstOrNull;
    if (candidate == null) return;
    final max = _maximumCases, latency = _latencyCeilingMs;
    final cost =
        (candidate.estimatedMaximumCostUsd +
            (candidate.feature == EvalFeature.recommendation
                ? catalog.judge.estimatedMaximumCostUsd
                : 0.0)) *
        max;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Start evaluation?'),
        content: Text(
          '$max cases · \$${cost.toStringAsFixed(6)} ceiling · $latency ms latency\n${candidate.scopeNote ?? candidate.taskScope}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Start evaluation'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _act(
      () => widget.source.start(
        EvalStartRequest(
          datasetVersion: catalog.datasetVersion,
          candidate: candidate,
          maximumCaseCount: max,
          costCeilingUsd: cost,
          latencyCeilingMs: latency,
        ),
      ),
      'Evaluation queued.',
    );
  }

  Future<void> _mutate(bool resume) async {
    final run = _detail?.run;
    if (run == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          resume ? 'Resume failed evaluation?' : 'Cancel evaluation?',
        ),
        content: Text(
          'The server will verify the latest run version before ${resume ? 'resuming' : 'cancelling'}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep run'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(resume ? 'Resume failed' : 'Cancel run'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _act(
      () => resume
          ? widget.source.resumeFailed(run.id, run.updatedAt.toIso8601String())
          : widget.source.cancel(run.id, run.updatedAt.toIso8601String()),
      resume ? 'Evaluation resumed.' : 'Evaluation cancelled.',
    );
  }

  Future<void> _act(
    Future<EvalRunReceipt> Function() action,
    String notice,
  ) async {
    setState(() {
      _acting = true;
      _notice = null;
    });
    try {
      await action();
      if (mounted) setState(() => _notice = notice);
      await _load();
    } on AdminStateConflict {
      if (mounted) {
        setState(
          () => _notice = 'Run changed on the server. Loaded the latest state.',
        );
      }
      await _load();
    } catch (e) {
      await _effects(e);
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _runs == null) {
      return const BrandLoadingSkeleton(
        semanticLabel: 'Loading evaluation runs',
        minHeight: 280,
      );
    }
    if (_runs == null) {
      return BrandStateView(
        title: 'Evaluation runs unavailable.',
        message: 'Check the connection and try again.',
        icon: Icons.science_outlined,
        actionLabel: 'Try again',
        onAction: () => _load(initial: true),
      );
    }
    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 900;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_refreshing) const LinearProgressIndicator(minHeight: 2),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'AI evaluation runs',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  key: const Key('eval-refresh'),
                  tooltip: 'Refresh evaluation runs',
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                  ),
                  onPressed: _refreshing || _acting ? null : _load,
                  icon: const Icon(Icons.refresh),
                ),
                FilledButton.icon(
                  onPressed:
                      _acting ||
                          (_configs?.datasetVersion ?? 0) < 1 ||
                          _candidateKey == null
                      ? null
                      : _start,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Start evaluation'),
                ),
              ],
            ),
            if (_notice != null)
              Padding(
                padding: const EdgeInsets.only(top: BrandSpacing.sm),
                child: Text(_notice!),
              ),
            if (_error != null)
              const Padding(
                padding: EdgeInsets.only(top: BrandSpacing.sm),
                child: Text(
                  'Refresh failed. Showing the last loaded evaluation state.',
                ),
              ),
            const SizedBox(height: BrandSpacing.md),
            _startControls(),
            const SizedBox(height: BrandSpacing.md),
            if (wide)
              Expanded(
                child: Row(
                  key: const Key('eval-wide-layout'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 2, child: _list()),
                    const SizedBox(width: BrandSpacing.md),
                    Expanded(flex: 3, child: _detailView()),
                  ],
                ),
              )
            else
              Expanded(
                child: KeyedSubtree(
                  key: const Key('eval-compact-layout'),
                  child: _compactDetail ? _detailView(compact: true) : _list(),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _startControls() {
    final catalog = _configs;
    final candidates = catalog?.candidates ?? const <EvalConfig>[];
    final selected = candidates
        .where((c) => c.key == _candidateKey)
        .firstOrNull;
    final perCase = selected == null
        ? 0.0
        : selected.estimatedMaximumCostUsd +
              (selected.feature == EvalFeature.recommendation
                  ? (catalog?.judge.estimatedMaximumCostUsd ?? 0)
                  : 0);
    final cost = perCase * _maximumCases;
    return BrandSurface(
      child: Wrap(
        spacing: BrandSpacing.md,
        runSpacing: BrandSpacing.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 260,
            child: DropdownButtonFormField<String>(
              key: const Key('eval-config-select'),
              initialValue: _candidateKey,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Candidate / family',
              ),
              items: [
                for (final c in candidates)
                  DropdownMenuItem(
                    value: c.key,
                    child: Text(_featureLabel(c.feature)),
                  ),
              ],
              onChanged: _acting
                  ? null
                  : (value) => setState(() => _candidateKey = value),
            ),
          ),
          DropdownButton<int>(
            key: const Key('eval-max-cases'),
            value: _maximumCases,
            items: const [10, 25, 50, 100]
                .map((v) => DropdownMenuItem(value: v, child: Text('$v cases')))
                .toList(),
            onChanged: _acting
                ? null
                : (v) => setState(() => _maximumCases = v!),
          ),
          DropdownButton<int>(
            key: const Key('eval-latency-ceiling'),
            value: _latencyCeilingMs,
            items: const [5000, 10000, 30000]
                .map(
                  (v) =>
                      DropdownMenuItem(value: v, child: Text('$v ms ceiling')),
                )
                .toList(),
            onChanged: _acting
                ? null
                : (v) => setState(() => _latencyCeilingMs = v!),
          ),
          if (selected == null)
            const Text('Select an available candidate to preflight the run.')
          else
            SizedBox(
              width: 420,
              child: Text(
                '${_featureLabel(selected.feature)} · ${selected.taskScope}\n'
                'Candidate ${selected.key} · ${selected.provider}/${selected.model} · ${selected.promptVersion}\n'
                'Baseline ${catalog!.baseline.key} · Judge ${catalog.judge.key}\n'
                '${selected.scopeNote ?? ''}${selected.scopeNote == null ? '' : ' · '}'
                'Preflight: $_maximumCases cases · \$${cost.toStringAsFixed(6)} max · $_latencyCeilingMs ms/case',
              ),
            ),
        ],
      ),
    );
  }

  Widget _list() => BrandSurface(
    child: ListView(
      shrinkWrap: true,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Runs',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            DropdownButton<String?>(
              key: const Key('eval-status-filter'),
              value: _statusFilter,
              items: const [
                DropdownMenuItem(value: null, child: Text('All statuses')),
                DropdownMenuItem(value: 'queued', child: Text('Queued')),
                DropdownMenuItem(value: 'running', child: Text('Running')),
                DropdownMenuItem(value: 'completed', child: Text('Completed')),
                DropdownMenuItem(
                  value: 'completed_with_failures',
                  child: Text('With failures'),
                ),
                DropdownMenuItem(value: 'failed', child: Text('Failed')),
                DropdownMenuItem(value: 'cancelled', child: Text('Cancelled')),
              ],
              onChanged: _acting
                  ? null
                  : (value) {
                      setState(() {
                        _statusFilter = value;
                        _page = 1;
                      });
                      _load();
                    },
            ),
          ],
        ),
        const SizedBox(height: BrandSpacing.sm),
        if (_runs!.items.isEmpty)
          const Text('No evaluation runs yet.')
        else
          for (final run in _runs!.items)
            Material(
              color: Colors.transparent,
              child: ListTile(
                minTileHeight: 56,
                selected: _selectedId == run.id,
                title: Text(_featureLabel(run.feature)),
                subtitle: Text(
                  '${run.status} · ${run.estimatedCostUsd.toStringAsFixed(6)} USD',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _select(run),
              ),
            ),
        if (_runs!.total > _runs!.limit) ...[
          const Divider(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                tooltip: 'Previous evaluation runs',
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                onPressed: _page <= 1 || _acting
                    ? null
                    : () {
                        setState(() => _page--);
                        _load();
                      },
                icon: const Icon(Icons.chevron_left),
              ),
              Text('Page $_page'),
              IconButton(
                tooltip: 'Next evaluation runs',
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                onPressed: !_runs!.hasMore || _acting
                    ? null
                    : () {
                        setState(() => _page++);
                        _load();
                      },
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ],
      ],
    ),
  );
  Widget _detailView({bool compact = false}) {
    final d = _detail;
    if (d == null) {
      return const BrandSurface(
        child: Text('Select a run to inspect its evidence.'),
      );
    }
    final r = d.run;
    return BrandSurface(
      key: const Key('eval-detail'),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (compact)
              TextButton.icon(
                onPressed: () => setState(() => _compactDetail = false),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Back to runs'),
              ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _featureLabel(r.feature),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                _DecisionChip(d.decision),
              ],
            ),
            const SizedBox(height: BrandSpacing.sm),
            Text(
              r.scopeNote ?? r.taskScope,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: BrandSpacing.md),
            Text(
              'Baseline ${(d.metrics.baselinePassRate * 100).round()}% → Candidate ${(d.metrics.candidatePassRate * 100).round()}%',
            ),
            Text(
              'P95 ${d.metrics.p95CandidateLatencyMs} ms · \$${r.estimatedCostUsd.toStringAsFixed(6)}',
            ),
            Text(
              '${r.tokenUsage['candidate_input'] ?? 0} input · ${r.tokenUsage['candidate_output'] ?? 0} output tokens',
            ),
            if (d.blockers.isNotEmpty) ...[
              const SizedBox(height: BrandSpacing.md),
              for (final blocker in d.blockers)
                Text('• ${blocker.replaceAll('_', ' ')}'),
            ],
            const SizedBox(height: BrandSpacing.md),
            if (['queued', 'running'].contains(r.status))
              OutlinedButton(
                onPressed: _acting ? null : () => _mutate(false),
                child: const Text('Cancel run'),
              ),
            if (['failed', 'completed_with_failures'].contains(r.status))
              FilledButton(
                onPressed: _acting ? null : () => _mutate(true),
                child: const Text('Resume failed'),
              ),
            const Divider(),
            Text(
              'Case summaries',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (d.results.isEmpty)
              const Text('No case summaries recorded.')
            else
              for (final result in d.results)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '${_featureLabel(result.feature)} · revision ${result.caseRevision}',
                  ),
                  subtitle: Text(
                    result.requiresReview
                        ? 'Manual review required'
                        : result.candidatePassed
                        ? 'Candidate passed'
                        : 'Candidate failed',
                  ),
                ),
            if (d.resultTotal > d.resultLimit) ...[
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    key: const Key('eval-results-prev'),
                    tooltip: 'Previous case results',
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                    onPressed: d.resultPage <= 1 || _acting
                        ? null
                        : () => _loadResultPage(d.resultPage - 1),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: Text(
                      'Results ${(d.resultPage - 1) * d.resultLimit + 1}–${(d.resultPage * d.resultLimit).clamp(0, d.resultTotal)} of ${d.resultTotal}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                  IconButton(
                    key: const Key('eval-results-next'),
                    tooltip: 'Next case results',
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                    onPressed:
                        d.resultPage * d.resultLimit >= d.resultTotal || _acting
                        ? null
                        : () => _loadResultPage(d.resultPage + 1),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _loadResultPage(int page) async {
    final id = _selectedId;
    if (id == null) return;
    setState(() => _acting = true);
    try {
      final detail = await widget.source.detail(id, resultPage: page);
      if (!mounted || _selectedId != id) return;
      setState(() {
        _detail = detail;
        _resultPage = page;
        _error = null;
      });
    } catch (e) {
      await _effects(e);
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }
}

class _DecisionChip extends StatelessWidget {
  const _DecisionChip(this.decision);
  final EvalDecision decision;
  @override
  Widget build(BuildContext context) => Chip(
    label: Text(
      decision == EvalDecision.candidateSupported
          ? 'Candidate supported'
          : 'Review required',
    ),
    avatar: Icon(
      decision == EvalDecision.candidateSupported
          ? Icons.check_circle_outline
          : Icons.rate_review_outlined,
      size: 18,
    ),
  );
}

String _featureLabel(EvalFeature feature) => switch (feature) {
  EvalFeature.statementProcessing => 'Statement processing',
  EvalFeature.cardData => 'Card data',
  EvalFeature.recommendation => 'Recommendation',
  EvalFeature.all => 'All features',
};
