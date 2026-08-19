import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../core/theme/brand_tokens.dart';
import 'feedback_models.dart';

typedef FeedbackAdminAction =
    Future<AdminFeedbackReceipt> Function(AdminFeedbackAction action);

class FeedbackDetailView extends StatefulWidget {
  const FeedbackDetailView({
    super.key,
    required this.detail,
    required this.onAction,
  });
  final AdminFeedbackDetail detail;
  final FeedbackAdminAction onAction;
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
  String? caseId;
  DateTime? caseUpdated;
  @override
  void initState() {
    super.initState();
    output.text = const JsonEncoder.withIndent(
      '  ',
    ).convert(widget.detail.advisoryExpectedOutput);
    rubric.text = '{}';
    severe.text = '{}';
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
    ].any((v) => v.trim().isEmpty)) {
      setState(() => message = 'Complete all operator ground-truth fields.');
      return;
    }
    try {
      final receipt = await widget.onAction(
        AdminFeedbackAction(
          kind: AdminFeedbackActionKind.createDraft,
          feedbackId: widget.detail.id,
          operatorBehavior: behavior.text.trim(),
          expectedOutput: parseJsonObject(output.text),
          rubric: parseJsonObject(rubric.text),
          severeConditions: parseJsonObject(severe.text),
        ),
      );
      if (!mounted) return;
      setState(() {
        caseId = receipt.caseId;
        caseUpdated = receipt.updatedAt;
        message = 'Draft created from operator ground truth.';
      });
    } catch (_) {
      setState(() => message = 'Check each field is a valid JSON object.');
    }
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
    await widget.onAction(
      AdminFeedbackAction(
        kind: kind,
        feedbackId: widget.detail.id,
        reason: reason,
      ),
    );
    if (mounted) setState(() => message = '$title recorded.');
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
              child: Text(
                '${widget.detail.advisorySeverity.toUpperCase()} · ${widget.detail.advisoryDiagnosis}',
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
