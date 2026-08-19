import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/brand_tokens.dart';
import 'feedback_models.dart';
import 'feedback_repository.dart';

Future<void> showContextualFeedbackSheet(
  BuildContext context, {
  required FeedbackTarget target,
  required String preview,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: BrandColors.paper,
  builder: (_) => FeedbackRepositoryScope(
    repository: FeedbackRepositoryScope.of(context),
    child: ContextualFeedbackSheet(target: target, preview: preview),
  ),
);

class ContextualFeedbackSheet extends StatefulWidget {
  const ContextualFeedbackSheet({
    super.key,
    required this.target,
    required this.preview,
  });

  final FeedbackTarget target;
  final String preview;

  @override
  State<ContextualFeedbackSheet> createState() =>
      _ContextualFeedbackSheetState();
}

enum _SendState { editing, sending, failed, sent }

class _ContextualFeedbackSheetState extends State<ContextualFeedbackSheet> {
  final _controller = TextEditingController();
  _SendState _state = _SendState.editing;
  FeedbackSubmission? _failedSubmission;

  String get _trimmed => _controller.text.trim();
  bool get _valid => _trimmed.length >= 10 && _trimmed.length <= 2000;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _changed() {
    if (_state == _SendState.failed &&
        _controller.text != _failedSubmission?.text) {
      _failedSubmission = null;
      _state = _SendState.editing;
    }
    setState(() {});
  }

  Future<void> _send() async {
    if (!_valid || _state == _SendState.sending) return;
    final repository = FeedbackRepositoryScope.of(context);
    final submission =
        _failedSubmission ??
        repository.newSubmission(widget.target, _controller.text);
    setState(() => _state = _SendState.sending);
    try {
      await repository.submit(submission);
      if (mounted) setState(() => _state = _SendState.sent);
    } catch (_) {
      if (!mounted) return;
      _failedSubmission = submission;
      setState(() => _state = _SendState.failed);
    }
  }

  @override
  Widget build(BuildContext context) => Shortcuts(
    shortcuts: const {
      SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
    },
    child: Actions(
      actions: {
        DismissIntent: CallbackAction<DismissIntent>(
          onInvoke: (_) {
            Navigator.of(context).pop();
            return null;
          },
        ),
      },
      child: Focus(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            BrandSpacing.lg,
            BrandSpacing.compact,
            BrandSpacing.lg,
            MediaQuery.viewInsetsOf(context).bottom + BrandSpacing.lg,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: BrandColors.ruleOnPaper,
                      borderRadius: BorderRadius.circular(BrandRadius.pill),
                    ),
                  ),
                ),
                const SizedBox(height: BrandSpacing.lg),
                Text(
                  'Tell us what should be different',
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                const SizedBox(height: BrandSpacing.md),
                Semantics(
                  label: 'Feedback about ${widget.preview}',
                  child: Container(
                    padding: const EdgeInsets.all(BrandSpacing.compact),
                    decoration: BoxDecoration(
                      color: BrandColors.ledger,
                      border: const Border(
                        left: BorderSide(
                          color: BrandColors.focusDark,
                          width: 3,
                        ),
                      ),
                      borderRadius: BorderRadius.circular(BrandRadius.control),
                    ),
                    child: Text(
                      widget.preview,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(height: BrandSpacing.lg),
                if (_state == _SendState.sent)
                  Semantics(
                    liveRegion: true,
                    child: const Text(
                      'Feedback sent',
                      textAlign: TextAlign.center,
                    ),
                  )
                else ...[
                  TextField(
                    controller: _controller,
                    autofocus: true,
                    minLines: 4,
                    maxLines: 7,
                    maxLength: 2000,
                    buildCounter:
                        (
                          _, {
                          required currentLength,
                          required isFocused,
                          maxLength,
                        }) => Text('$currentLength / $maxLength'),
                    onChanged: (_) => _changed(),
                    decoration: const InputDecoration(
                      labelText: 'Your feedback',
                      hintText:
                          'Describe what looks wrong or what you expected instead.',
                      alignLabelWithHint: true,
                    ),
                  ),
                  if (_state == _SendState.failed) ...[
                    Semantics(
                      liveRegion: true,
                      child: const Text(
                        'Feedback could not be sent. Try again.',
                      ),
                    ),
                    const SizedBox(height: BrandSpacing.sm),
                  ],
                  const SizedBox(height: BrandSpacing.md),
                  SizedBox(
                    height: 48,
                    child: FilledButton(
                      onPressed: _valid && _state != _SendState.sending
                          ? _send
                          : null,
                      child: _state == _SendState.sending
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              _state == _SendState.failed
                                  ? 'Try again'
                                  : 'Send feedback',
                            ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
