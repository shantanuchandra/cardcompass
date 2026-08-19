import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../core/theme/brand_tokens.dart';
import '../data/admin_operator_repository.dart';
import 'feedback_models.dart';

typedef FeedbackAdminAction =
    Future<AdminFeedbackReceipt> Function(AdminFeedbackAction action);

class FeedbackDetailView extends StatefulWidget {
  const FeedbackDetailView({
    super.key,
    required this.detail,
    required this.onAction,
    this.onRefresh,
    this.onAuthenticationRequired,
    this.onAccessDenied,
  });
  final AdminFeedbackDetail detail;
  final FeedbackAdminAction onAction;
  final Future<void> Function()? onRefresh;
  final Future<void> Function()? onAuthenticationRequired;
  final VoidCallback? onAccessDenied;
  @override
  State<FeedbackDetailView> createState() => _FeedbackDetailViewState();
}

class _FeedbackDetailViewState extends State<FeedbackDetailView> {
  final behavior = TextEditingController(),
      output = TextEditingController(),
      rubric = TextEditingController(),
      severe = TextEditingController();
  String? message;
  bool busy = false;
  bool groundTruthConfirmed = false;
  String? caseId;
  DateTime? caseUpdated;
  @override
  void initState() {
    super.initState();
    output.text = '';
    rubric.text = '';
    severe.text = '';
    caseId = widget.detail.caseId;
    caseUpdated = widget.detail.caseUpdatedAt;
  }

  @override
  void dispose() {
    behavior.dispose();
    output.dispose();
    rubric.dispose();
    severe.dispose();
    super.dispose();
  }

  Future<void> createDraft() async {
    if ([
          behavior.text,
          output.text,
          rubric.text,
          severe.text,
        ].any((v) => v.trim().isEmpty) ||
        !groundTruthConfirmed) {
      setState(() => message = 'Complete all operator ground-truth fields.');
      return;
    }
    await _run(() async {
      final receipt = await widget.onAction(
        AdminFeedbackAction(
          kind: AdminFeedbackActionKind.createDraft,
          feedbackId: widget.detail.id,
          operatorBehavior: behavior.text.trim(),
          expectedOutput: parseJsonObject(output.text),
          rubric: parseJsonObject(rubric.text),
          severeConditions: parseJsonObject(severe.text),
          groundTruthConfirmed: groundTruthConfirmed,
        ),
      );
      if (mounted) {
        setState(() {
          caseId = receipt.caseId;
          caseUpdated = receipt.updatedAt;
          message = 'Draft created from operator ground truth.';
        });
      }
    });
  }

  Future<void> approve() async {
    final confirmation = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Approve eval case'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Type APPROVE to add this case to the dataset.'),
            TextField(
              key: const Key('approval-confirmation'),
              controller: confirmation,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, confirmation.text == 'APPROVE'),
            child: const Text('Approve'),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    await _run(() async {
      final receipt = await widget.onAction(
        AdminFeedbackAction(
          kind: AdminFeedbackActionKind.approve,
          feedbackId: widget.detail.id,
          caseId: caseId,
          observedUpdatedAt: caseUpdated,
          confirmation: 'APPROVE',
        ),
      );
      if (mounted) {
        setState(
          () => message =
              'Approved in dataset version ${receipt.datasetVersion ?? 'confirmed'}.',
        );
      }
    });
  }

  Future<void> route(AdminFeedbackActionKind kind, String title) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          maxLength: 1000,
          decoration: const InputDecoration(labelText: 'Operator reason'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (reason == null || reason.length < 2) return;
    await _run(() async {
      await widget.onAction(
        AdminFeedbackAction(
          kind: kind,
          feedbackId: widget.detail.id,
          reason: reason,
        ),
      );
      if (mounted) setState(() => message = '$title recorded.');
    });
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (busy) return;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await operation();
      await widget.onRefresh?.call();
    } on AdminStateConflict {
      if (mounted) {
        setState(
          () => message = 'This record changed. Reloading the latest version.',
        );
      }
      await widget.onRefresh?.call();
    } on AdminAuthenticationRequired {
      await widget.onAuthenticationRequired?.call();
    } on AdminAccessDenied {
      widget.onAccessDenied?.call();
    } on FormatException {
      if (mounted) {
        setState(
          () => message =
              'Use valid, non-empty JSON objects with meaningful fields.',
        );
      }
    } on AdminRequestFailed {
      if (mounted) {
        setState(
          () => message = 'The action could not be completed. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(BrandSpacing.lg),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Feedback review',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 16),
            _Panel(
              title: 'User feedback',
              child: Text(widget.detail.feedbackText),
            ),
            _Panel(
              title: 'Captured output',
              child: SelectableText(jsonEncode(widget.detail.capturedOutput)),
            ),
            _Panel(
              title: 'Safe context',
              child: SelectableText(jsonEncode(widget.detail.safeContext)),
            ),
            _Panel(
              title: 'LLM proposal · advisory',
              color: Colors.amber.shade50,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${widget.detail.advisorySeverity.toUpperCase()} · ${widget.detail.advisoryDiagnosis}',
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    jsonEncode(widget.detail.advisoryExpectedOutput),
                  ),
                ],
              ),
            ),
            _Panel(
              title: 'Source metadata',
              child: Text(
                'Feature: ${widget.detail.feature}\nProvider: ${widget.detail.provider ?? 'Unknown'}\nModel: ${widget.detail.model ?? 'Unknown'}\nEngine: ${widget.detail.engineVersion ?? 'Unknown'}\nPrompt: ${widget.detail.promptVersion ?? 'Unknown'}\nParser: ${widget.detail.parserVersion ?? 'Unknown'}\nTrace: ${widget.detail.traceId ?? 'Not captured'}\nCreated: ${widget.detail.createdAt.toIso8601String()}',
              ),
            ),
            _Panel(
              title: 'Eval case',
              child: Text(
                'Status: ${widget.detail.caseStatus ?? 'Not created'}\nRevision: ${widget.detail.caseRevision?.toString() ?? 'Unknown'}\nApproved dataset: ${widget.detail.approvedDatasetVersion?.toString() ?? 'Not approved'}\nRetired dataset: ${widget.detail.retiredDatasetVersion?.toString() ?? 'Not retired'}\nApproved: ${widget.detail.approvedAt?.toIso8601String() ?? 'Not approved'}',
              ),
            ),
            _Panel(
              title: 'Operator ground truth',
              child: Column(
                children: [
                  TextField(
                    key: const Key('operator-behavior'),
                    controller: behavior,
                    decoration: const InputDecoration(
                      labelText: 'Expected behavior',
                    ),
                  ),
                  CheckboxListTile(
                    key: const Key('ground-truth-confirmed'),
                    value: groundTruthConfirmed,
                    onChanged: busy
                        ? null
                        : (value) => setState(
                            () => groundTruthConfirmed = value == true,
                          ),
                    title: const Text(
                      'I reviewed and authored this ground truth',
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  TextField(
                    key: const Key('operator-output'),
                    controller: output,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Expected output (JSON)',
                    ),
                  ),
                  TextField(
                    key: const Key('operator-rubric'),
                    controller: rubric,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Scoring rubric (JSON)',
                    ),
                  ),
                  TextField(
                    key: const Key('operator-severe'),
                    controller: severe,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Severe failure conditions (JSON)',
                    ),
                  ),
                ],
              ),
            ),
            if (message != null)
              Semantics(liveRegion: true, child: Text(message!)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                FilledButton(
                  onPressed: busy ? null : createDraft,
                  child: const Text('Create eval draft'),
                ),
                if (caseId != null)
                  OutlinedButton(
                    onPressed: busy ? null : approve,
                    child: const Text('Approve eval case'),
                  ),
                if (widget.detail.reviewStatus == 'pending') ...[
                  OutlinedButton(
                    onPressed: busy
                        ? null
                        : () => route(
                            AdminFeedbackActionKind.dataIssue,
                            'Route as data issue',
                          ),
                    child: const Text('Data issue'),
                  ),
                  OutlinedButton(
                    onPressed: busy
                        ? null
                        : () => route(
                            AdminFeedbackActionKind.productDefect,
                            'Route as product defect',
                          ),
                    child: const Text('Product defect'),
                  ),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => route(
                            AdminFeedbackActionKind.dismiss,
                            'Dismiss feedback',
                          ),
                    child: const Text('Dismiss'),
                  ),
                ],
                if (widget.detail.triageStatus == 'triage_failed')
                  OutlinedButton(
                    onPressed: busy
                        ? null
                        : () async {
                            await _run(() async {
                              await widget.onAction(
                                AdminFeedbackAction(
                                  kind: AdminFeedbackActionKind.retryTriage,
                                  feedbackId: widget.detail.id,
                                ),
                              );
                              if (mounted) {
                                setState(
                                  () => message = 'Triage retry scheduled.',
                                );
                              }
                            });
                          },
                    child: const Text('Retry triage'),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child, this.color});
  final String title;
  final Widget child;
  final Color? color;
  @override
  Widget build(BuildContext context) => Card(
    color: color,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          child,
        ],
      ),
    ),
  );
}
