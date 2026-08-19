import 'package:flutter/material.dart';
import '../../../core/theme/brand_components.dart';
import '../../../core/theme/brand_tokens.dart';
import '../data/admin_operator_repository.dart';
import 'system_models.dart';

abstract interface class SystemDataSource {
  Future<SystemStatusSnapshot> status();
  Future<SystemJobsPage> jobs(
    SystemJobFamily family, {
    int page = 1,
    int limit = 25,
    String? status,
  });
  Future<void> mutate(SystemMutation mutation);
}

class SystemSection extends StatefulWidget {
  const SystemSection({
    super.key,
    required this.repository,
    this.onAuthenticationRequired,
    this.onAccessDenied,
  });
  final SystemDataSource repository;
  final Future<void> Function()? onAuthenticationRequired;
  final VoidCallback? onAccessDenied;
  @override
  State<SystemSection> createState() => _SystemSectionState();
}

class _SystemSectionState extends State<SystemSection> {
  SystemStatusSnapshot? _status;
  SystemJobsPage? _jobs;
  SystemJobFamily _family = SystemJobFamily.benefitEnrichment;
  SystemJob? _selected;
  Object? _error;
  String? _notice;
  bool _loading = true;
  bool _refreshing = false;
  bool _submitting = false;
  bool _compactDetail = false;
  @override
  void initState() {
    super.initState();
    _load(initial: true);
  }

  Future<void> _load({bool initial = false, int? page}) async {
    setState(() {
      if (initial && _status == null) _loading = true;
      if (_status != null) _refreshing = true;
      _error = null;
    });
    try {
      final results = await Future.wait<Object>([
        widget.repository.status(),
        widget.repository.jobs(_family, page: page ?? _jobs?.page ?? 1),
      ]);
      if (!mounted) return;
      final jobs = results[1] as SystemJobsPage;
      setState(() {
        _status = results[0] as SystemStatusSnapshot;
        _jobs = jobs;
        _selected = jobs.items
            .where((item) => item.id == _selected?.id)
            .firstOrNull;
        _loading = false;
        _refreshing = false;
      });
    } catch (error) {
      await _effects(error);
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
        _refreshing = false;
      });
    }
  }

  Future<void> _effects(Object error) async {
    if (error is AdminAuthenticationRequired) {
      await widget.onAuthenticationRequired?.call();
    }
    if (error is AdminAccessDenied) widget.onAccessDenied?.call();
  }

  Future<void> _changeFamily(SystemJobFamily family) async {
    if (family == _family || _submitting) return;
    setState(() {
      _family = family;
      _jobs = null;
      _selected = null;
      _compactDetail = false;
      _loading = true;
    });
    await _load(initial: true, page: 1);
  }

  Future<void> _confirm(
    SystemMutation Function(String reason) build, {
    required String title,
    required String action,
    bool reasonRequired = false,
  }) async {
    if (_submitting) return;
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _SystemConfirmationDialog(
        title: title,
        action: action,
        reasonRequired: reasonRequired,
      ),
    );
    if (reason == null || !mounted) return;
    setState(() {
      _submitting = true;
      _notice = null;
    });
    try {
      await widget.repository.mutate(build(reason));
      if (!mounted) return;
      setState(() => _notice = 'System state confirmed by server.');
      await _load();
    } on AdminStateConflict {
      if (mounted) {
        setState(
          () => _notice =
              'System state changed. Reloaded the latest server state.',
        );
      }
      await _load();
    } catch (error) {
      await _effects(error);
      if (mounted &&
          error is! AdminAuthenticationRequired &&
          error is! AdminAccessDenied) {
        setState(
          () =>
              _notice = 'Action failed. Review the latest state and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _status == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_status == null) {
      return BrandStateView(
        title: 'System state unavailable.',
        message: 'No operational data was loaded.',
        icon: Icons.cloud_off_outlined,
        actionLabel: 'Try again',
        onAction: () => _load(initial: true),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1024;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_refreshing) const LinearProgressIndicator(minHeight: 2),
            Padding(
              padding: const EdgeInsets.all(BrandSpacing.lg),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: BrandSectionHeader(
                      eyebrow: 'Operations',
                      title: 'System',
                      description:
                          'Live pipeline state, bounded recovery, and the scheduled enrichment control.',
                    ),
                  ),
                  IconButton(
                    key: const Key('system-refresh'),
                    tooltip: 'Refresh system state',
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                    onPressed: _refreshing || _submitting ? null : _load,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
            ),
            if (_notice != null) _Banner(_notice!),
            if (_error != null)
              const _Banner(
                'Refresh failed. Showing the last loaded system state.',
              ),
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    BrandSpacing.lg,
                    0,
                    BrandSpacing.lg,
                    BrandSpacing.xl,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Refreshed ${_time(_status!.refreshedAt)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: BrandSpacing.md),
                      Wrap(
                        spacing: BrandSpacing.md,
                        runSpacing: BrandSpacing.md,
                        children: _status!.pipelines
                            .map(
                              (p) => SizedBox(
                                width: wide ? 300 : constraints.maxWidth,
                                child: _PipelineCard(p),
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: BrandSpacing.md),
                      _ControlCard(
                        control: _status!.controls.firstOrNull,
                        unavailable: _status!.controlSourceError != null,
                        submitting: _submitting,
                        onAction: _controlAction,
                      ),
                      const SizedBox(height: BrandSpacing.lg),
                      if (wide)
                        Row(
                          key: const Key('system-wide-layout'),
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 3, child: _jobList()),
                            const SizedBox(width: BrandSpacing.md),
                            Expanded(flex: 2, child: _detail()),
                          ],
                        )
                      else
                        KeyedSubtree(
                          key: const Key('system-compact-layout'),
                          child: _compactDetail
                              ? _detail(compact: true)
                              : _jobList(),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _jobList() => BrandSurface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Recovery queue', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: BrandSpacing.sm),
        SegmentedButton<SystemJobFamily>(
          segments: SystemJobFamily.values
              .map((f) => ButtonSegment(value: f, label: Text(f.label)))
              .toList(),
          selected: {_family},
          onSelectionChanged: _submitting
              ? null
              : (v) => _changeFamily(v.single),
        ),
        const SizedBox(height: BrandSpacing.md),
        if (_jobs == null)
          const Center(child: CircularProgressIndicator())
        else if (_jobs!.items.isEmpty)
          const Text('No jobs in this family.')
        else
          ..._jobs!.items.map(
            (job) => Material(
              color: Colors.transparent,
              child: ListTile(
                minVerticalPadding: 10,
                contentPadding: EdgeInsets.zero,
                title: Text(job.failureCategory ?? job.status),
                subtitle: Text('${job.status} · ${job.id.substring(0, 8)}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => setState(() {
                  _selected = job;
                  _compactDetail = true;
                }),
              ),
            ),
          ),
        if (_jobs != null)
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                tooltip: 'Previous page',
                onPressed: _jobs!.page > 1
                    ? () => _load(page: _jobs!.page - 1)
                    : null,
                icon: const Icon(Icons.chevron_left),
              ),
              Text('Page ${_jobs!.page}'),
              IconButton(
                tooltip: 'Next page',
                onPressed: _jobs!.hasMore
                    ? () => _load(page: _jobs!.page + 1)
                    : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
      ],
    ),
  );

  Widget _detail({bool compact = false}) {
    final job = _selected;
    final actions = job == null
        ? const <SystemJobAction>{}
        : SystemJobPolicy.actionsFor(job.family, job.status);
    return BrandSurface(
      key: const Key('system-job-detail'),
      tone: BrandSurfaceTone.ledger,
      child: job == null
          ? const Text('Select one job to inspect recovery options.')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (compact)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => setState(() => _compactDetail = false),
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Back to jobs'),
                    ),
                  ),
                Text(
                  job.family.label,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: BrandSpacing.sm),
                SelectableText(job.id),
                const SizedBox(height: BrandSpacing.md),
                Text('Status: ${job.status}'),
                Text('Attempt ${job.attemptCount}'),
                Text('Updated ${_time(job.updatedAt)}'),
                if (job.failureCategory != null)
                  Text('Failure: ${job.failureCategory}'),
                const SizedBox(height: BrandSpacing.lg),
                if (actions.contains(SystemJobAction.retry))
                  OutlinedButton(
                    key: const Key('system-retry-action'),
                    onPressed: _submitting
                        ? null
                        : () => _confirm(
                            (_) => RetrySystemJob(
                              family: job.family,
                              targetId: job.id,
                              status: job.status,
                              observedUpdatedAt: job.updatedAt
                                  .toIso8601String(),
                            ),
                            title: 'Retry this job?',
                            action: 'Confirm retry',
                          ),
                    child: const Text('Retry job'),
                  ),
                if (actions.contains(SystemJobAction.unquarantine))
                  FilledButton(
                    key: const Key('system-unquarantine-action'),
                    onPressed: _submitting
                        ? null
                        : () => _confirm(
                            (_) => UnquarantineSystemJob(
                              family: job.family,
                              targetId: job.id,
                              status: job.status,
                              observedUpdatedAt: job.updatedAt
                                  .toIso8601String(),
                            ),
                            title: 'Return this job to the queue?',
                            action: 'Confirm return',
                          ),
                    child: const Text('Return to queue'),
                  ),
                if (actions.contains(SystemJobAction.quarantine))
                  FilledButton(
                    key: const Key('system-quarantine-action'),
                    onPressed: _submitting
                        ? null
                        : () => _confirm(
                            (reason) => QuarantineSystemJob(
                              family: job.family,
                              targetId: job.id,
                              status: job.status,
                              observedUpdatedAt: job.updatedAt
                                  .toIso8601String(),
                              reason: reason,
                            ),
                            title: 'Quarantine this job?',
                            action: 'Confirm quarantine',
                            reasonRequired: true,
                          ),
                    child: const Text('Quarantine job'),
                  ),
              ],
            ),
    );
  }

  void _controlAction(RuntimeControl control) => _confirm(
    (reason) => control.isPaused
        ? ResumeSystemControl(
            observedUpdatedAt: control.updatedAt.toIso8601String(),
            reason: reason,
          )
        : PauseSystemControl(
            observedUpdatedAt: control.updatedAt.toIso8601String(),
            reason: reason,
          ),
    title: control.isPaused
        ? 'Resume scheduled enrichment?'
        : 'Pause scheduled enrichment?',
    action: control.isPaused ? 'Confirm resume' : 'Confirm pause',
    reasonRequired: true,
  );
}

class _PipelineCard extends StatelessWidget {
  const _PipelineCard(this.pipeline);
  final PipelineSummary pipeline;
  @override
  Widget build(BuildContext context) => BrandSurface(
    tone: pipeline.status == PipelineHealth.healthy
        ? BrandSurfaceTone.paper
        : BrandSurfaceTone.ledger,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          pipeline.key.label,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: BrandSpacing.sm),
        Text(
          pipeline.sourceError == null
              ? pipeline.status.name.toUpperCase()
              : 'Health unavailable',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: BrandSpacing.sm),
        Wrap(
          spacing: BrandSpacing.sm,
          children: [
            Text('${pipeline.queued} queued'),
            Text('${pipeline.running} running'),
            Text('${pipeline.failed} failed'),
            Text('${pipeline.quarantined} quarantined'),
          ],
        ),
        if (pipeline.lastSuccessAt != null)
          Text('Last success ${_time(pipeline.lastSuccessAt!)}'),
      ],
    ),
  );
}

class _ControlCard extends StatelessWidget {
  const _ControlCard({
    required this.control,
    required this.unavailable,
    required this.submitting,
    required this.onAction,
  });
  final RuntimeControl? control;
  final bool unavailable;
  final bool submitting;
  final ValueChanged<RuntimeControl> onAction;
  @override
  Widget build(BuildContext context) => BrandSurface(
    tone: BrandSurfaceTone.evidence,
    child: Row(
      children: [
        const Icon(Icons.pause_circle_outline, color: BrandColors.paper),
        const SizedBox(width: BrandSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Scheduled benefit enrichment',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(
                unavailable || control == null
                    ? 'Control state unavailable'
                    : control!.isPaused
                    ? 'Paused · ${control!.reason ?? 'No reason'}'
                    : 'Running on schedule',
              ),
            ],
          ),
        ),
        if (!unavailable && control != null)
          FilledButton(
            key: const Key('system-control-action'),
            onPressed: submitting ? null : () => onAction(control!),
            child: Text(control!.isPaused ? 'Resume' : 'Pause'),
          ),
      ],
    ),
  );
}

class _Banner extends StatelessWidget {
  const _Banner(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      margin: const EdgeInsets.fromLTRB(
        BrandSpacing.lg,
        0,
        BrandSpacing.lg,
        BrandSpacing.sm,
      ),
      padding: const EdgeInsets.all(BrandSpacing.compact),
      color: BrandColors.ledger,
      child: Text(text),
    ),
  );
}

class _SystemConfirmationDialog extends StatefulWidget {
  const _SystemConfirmationDialog({
    required this.title,
    required this.action,
    required this.reasonRequired,
  });
  final String title;
  final String action;
  final bool reasonRequired;
  @override
  State<_SystemConfirmationDialog> createState() =>
      _SystemConfirmationDialogState();
}

class _SystemConfirmationDialogState extends State<_SystemConfirmationDialog> {
  final _controller = TextEditingController();
  bool _sending = false;
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valid = !widget.reasonRequired || _controller.text.trim().length >= 2;
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'The server will verify the version and write an audit receipt.',
          ),
          if (widget.reasonRequired) ...[
            const SizedBox(height: BrandSpacing.md),
            TextField(
              key: const Key('system-reason'),
              controller: _controller,
              autofocus: true,
              maxLength: 500,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Reason',
                hintText: 'What changed?',
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: !valid || _sending
              ? null
              : () {
                  setState(() => _sending = true);
                  Navigator.pop(context, _controller.text.trim());
                },
          child: Text(widget.action),
        ),
      ],
    );
  }
}

String _time(DateTime value) =>
    value.toUtc().toIso8601String().replaceFirst('.000Z', 'Z');
