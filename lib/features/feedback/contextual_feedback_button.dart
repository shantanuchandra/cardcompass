import 'package:flutter/material.dart';

import 'contextual_feedback_sheet.dart';
import 'feedback_models.dart';

class ContextualFeedbackButton extends StatelessWidget {
  const ContextualFeedbackButton({
    super.key,
    required this.target,
    required this.preview,
  });

  final FeedbackTarget target;
  final String preview;

  String get _previewLabel {
    final separator = preview.indexOf(' · ');
    return separator < 0 ? preview : preview.substring(0, separator);
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Give feedback about $_previewLabel',
    excludeSemantics: true,
    child: TextButton.icon(
      style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
      onPressed: () => showContextualFeedbackSheet(
        context,
        target: target,
        preview: preview,
      ),
      icon: const Icon(Icons.rate_review_outlined, size: 18),
      label: const Text('Give feedback'),
    ),
  );
}
