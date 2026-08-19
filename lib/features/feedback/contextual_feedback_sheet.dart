import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/brand_tokens.dart';
import 'feedback_models.dart';
import 'feedback_repository.dart';

Future<void> showContextualFeedbackSheet(
  BuildContext context, {
  required FeedbackTarget target,
  required String preview,
  Future<FeedbackTarget> Function()? recreateTarget,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: BrandColors.paper,
  builder: (_) => FeedbackRepositoryScope(
    repository: FeedbackRepositoryScope.of(context),
    child: ContextualFeedbackSheet(
      target: target,
      preview: preview,
      recreateTarget: recreateTarget,
    ),
  ),
);

class ContextualFeedbackSheet extends StatefulWidget {
  const ContextualFeedbackSheet({
    super.key,
    required this.target,
    required this.preview,
    this.recreateTarget,
  });

  final FeedbackTarget target;
  final String preview;
  final Future<FeedbackTarget> Function()? recreateTarget;

  @override
  State<ContextualFeedbackSheet> createState() =>
      _ContextualFeedbackSheetState();
}

enum _SendState { editing, sending, failed, sent }

class _ContextualFeedbackSheetState extends State<ContextualFeedbackSheet> {
  final _controller = TextEditingController();
  _SendState _state = _SendState.editing;
  FeedbackSubmission? _failedSubmission;
  FeedbackSubmission? _activeSubmission;
  bool _recreatedExpiredTarget = false;

  String get _trimmed => _controller.text.trim();
  bool get _valid => _trimmed.length >= 10 && _trimmed.length <= 2000;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _changed() {
    if (_state == _SendState.sending) {
      final frozenText = _activeSubmission?.text;
      if (frozenText != null && _controller.text != frozenText) {
        _controller.value = TextEditingValue(
          text: frozenText,
          selection: TextSelection.collapsed(offset: frozenText.length),
        );
      }
      return;
    }
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
    _activeSubmission = submission;
    _controller.value = TextEditingValue(
      text: submission.text,
      selection: TextSelection.collapsed(offset: submission.text.length),
    );
    setState(() => _state = _SendState.sending);
    try {
      await repository.submit(submission);
      if (mounted) {
        setState(() {
          _state = _SendState.sent;
          _activeSubmission = null;
        });
      }
    } on FeedbackFailed catch (error) {
      var retrySubmission = submission;
      if (error.code == 'not_found' &&
          !_recreatedExpiredTarget &&
          widget.recreateTarget != null) {
        _recreatedExpiredTarget = true;
        try {
          final refreshedTarget = await widget.recreateTarget!();
          final refreshed = repository.newSubmission(
            refreshedTarget,
            submission.text,
          );
          retrySubmission = refreshed;
          _activeSubmission = refreshed;
          await repository.submit(refreshed);
          if (mounted) {
            setState(() {
              _state = _SendState.sent;
              _activeSubmission = null;
            });
          }
          return;
        } catch (_) {
          // Fall through to the same safe retry state as other failures.
        }
      }
      if (!mounted) return;
      _failedSubmission = retrySubmission;
      _controller.value = TextEditingValue(
        text: retrySubmission.text,
        selection: TextSelection.collapsed(offset: retrySubmission.text.length),
      );
      setState(() {
        _state = _SendState.failed;
        _activeSubmission = null;
      });
    } catch (_) {
      if (!mounted) return;
      _failedSubmission = submission;
      _controller.value = TextEditingValue(
        text: submission.text,
        selection: TextSelection.collapsed(offset: submission.text.length),
      );
      setState(() {
        _state = _SendState.failed;
        _activeSubmission = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _state != _SendState.sending,
    child: Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
      },
      child: Actions(
        actions: {
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (_) {
              if (_state != _SendState.sending) Navigator.of(context).pop();
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
                        borderRadius: BorderRadius.circular(
                          BrandRadius.control,
                        ),
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
                      enabled: _state != _SendState.sending,
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
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
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
    ),
  );
}
