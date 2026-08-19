import 'package:flutter/material.dart';
import '../../../core/theme/brand_tokens.dart';
import '../data/admin_operator_repository.dart';
import 'customer_models.dart';
import 'customer_repository.dart';

class CustomersSection extends StatefulWidget {
  const CustomersSection({
    super.key,
    required this.repository,
    this.onAuthenticationRequired,
    this.onAccessDenied,
  });
  final CustomerDataSource repository;
  final Future<void> Function()? onAuthenticationRequired;
  final VoidCallback? onAccessDenied;
  @override
  State<CustomersSection> createState() => _CustomersSectionState();
}

class _CustomersSectionState extends State<CustomersSection> {
  final _search = TextEditingController();
  List<CustomerSummary>? _results;
  CustomerDetail? _detail;
  DisableCustomer? _pendingAuthBan;
  String? _selectedId, _message;
  Object? _error;
  bool _loading = false, _submitting = false, _compactDetail = false;
  int _generation = 0;
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _runSearch() async {
    if (_submitting) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      _message = null;
      _detail = null;
      _selectedId = null;
    });
    try {
      final results = await widget.repository.search(_search.text);
      if (!mounted || generation != _generation) return;
      setState(() {
        _results = results;
        _loading = false;
        if (results.isEmpty) {
          _selectedId = null;
          _detail = null;
        }
      });
      if (results.isNotEmpty) {
        await _select(results.first, generation: generation, compact: false);
      }
    } catch (error) {
      if (!mounted || generation != _generation) return;
      await _access(error);
      if (mounted && generation == _generation) {
        setState(() {
          _error = error;
          _loading = false;
        });
      }
    }
  }

  Future<void> _select(
    CustomerSummary customer, {
    int? generation,
    bool compact = true,
    bool explicitSelection = false,
  }) async {
    final active = generation ?? ++_generation;
    setState(() {
      _selectedId = customer.id;
      _compactDetail = compact;
      _error = null;
      _detail = null;
      if (explicitSelection && _pendingAuthBan?.targetId != customer.id) {
        _pendingAuthBan = null;
      }
    });
    try {
      final detail = await widget.repository.detail(customer.id);
      if (!mounted || active != _generation || _selectedId != customer.id) {
        return;
      }
      if (detail.summary.id != customer.id) {
        throw const AdminRequestFailed('request_failed');
      }
      setState(() {
        _detail = detail;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || active != _generation) return;
      await _access(error);
      if (mounted && active == _generation) {
        setState(() {
          _error = error;
          _loading = false;
        });
      }
    }
  }

  Future<void> _access(Object error) async {
    if (error is AdminAuthenticationRequired) {
      await widget.onAuthenticationRequired?.call();
    }
    if (error is AdminAccessDenied) widget.onAccessDenied?.call();
  }

  Future<void> _retry() async {
    final detail = _detail;
    if (detail == null || _submitting || !detail.retryEligible) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Queue Gmail recovery?'),
        content: const Text(
          "This requests a Gmail sync during the customer's next authenticated session. The operator never receives their Google access.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Queue retry'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _mutate(
      QueueGmailRetry(
        requestId: widget.repository.newRequestId(),
        targetId: detail.summary.id,
        observedUpdatedAt: detail.summary.lastActivityAt.toIso8601String(),
      ),
      'Gmail recovery queued for the next authenticated session.',
    );
  }

  Future<void> _confirmed(bool disable) async {
    final detail = _detail;
    if (detail == null || _submitting) return;
    final result = await showDialog<_Confirmation>(
      context: context,
      builder: (_) => _CustomerConfirmationDialog(
        targetId: detail.summary.id,
        disable: disable,
      ),
    );
    if (result == null || !mounted) return;
    final mutation = disable
        ? DisableCustomer(
            requestId: widget.repository.newRequestId(),
            targetId: detail.summary.id,
            observedUpdatedAt: detail.summary.lastActivityAt.toIso8601String(),
            reason: result.reason,
            confirmationUserId: result.target,
          )
        : SetCustomerDeletionStatus(
            requestId: widget.repository.newRequestId(),
            targetId: detail.summary.id,
            observedUpdatedAt:
                detail.deletionUpdatedAt?.toIso8601String() ??
                detail.summary.lastActivityAt.toIso8601String(),
            reason: result.reason,
            confirmationUserId: result.target,
            status: result.status!,
          );
    await _mutate(
      mutation,
      disable ? 'Account access disabled.' : 'Deletion progress updated.',
    );
  }

  Future<void> _mutate(CustomerMutation mutation, String success) async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _message = null;
    });
    try {
      await widget.repository.mutate(mutation);
      if (!mounted) return;
      setState(() {
        _message = success;
        if (mutation is DisableCustomer) _pendingAuthBan = null;
      });
      final current = _results
          ?.where((e) => e.id == mutation.targetId)
          .firstOrNull;
      if (current != null) await _select(current, compact: _compactDetail);
    } on AdminStateConflict {
      if (!mounted) return;
      setState(
        () => _message =
            'Customer state changed. Latest server state has been loaded.',
      );
      final current = _results
          ?.where((e) => e.id == mutation.targetId)
          .firstOrNull;
      if (current != null) await _select(current, compact: _compactDetail);
    } on CustomerAuthBanPending catch (error) {
      if (!mounted) return;
      setState(() {
        _pendingAuthBan = error.operation;
        _message = 'Database access is blocked, but the Auth ban needs retry.';
      });
      final current = _results
          ?.where((e) => e.id == error.operation.targetId)
          .firstOrNull;
      if (current != null) await _select(current, compact: _compactDetail);
    } on AdminRequestFailed {
      if (!mounted) return;
      setState(
        () => _message =
            'Action failed safely. Review the latest state and try again.',
      );
    } catch (error) {
      await _access(error);
      if (mounted) {
        setState(
          () => _message =
              'Action failed safely. Review the latest state and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 1024;
      final content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(BrandSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Customers',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Search safe identity and operational metadata. Customer content and provider credentials stay hidden.',
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('customer-search-field'),
                        controller: _search,
                        enabled: !_submitting,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => _runSearch(),
                        decoration: const InputDecoration(
                          labelText:
                              'Exact user ID or email fragment (3+ characters)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox.square(
                      dimension: 48,
                      child: IconButton(
                        key: const Key('customer-search-submit'),
                        tooltip: 'Search customers',
                        onPressed: _submitting ? null : _runSearch,
                        icon: const Icon(Icons.search),
                      ),
                    ),
                    SizedBox.square(
                      dimension: 48,
                      child: IconButton(
                        key: const Key('customer-refresh'),
                        tooltip: 'Refresh customer results',
                        onPressed: _results == null || _loading || _submitting
                            ? null
                            : _runSearch,
                        icon: const Icon(Icons.refresh),
                      ),
                    ),
                  ],
                ),
                if (_loading) const LinearProgressIndicator(),
              ],
            ),
          ),
          if (_message case final message?)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: BrandSpacing.lg),
              child: Semantics(liveRegion: true, child: Text(message)),
            ),
          if (_pendingAuthBan case final pending?
              when _detail?.summary.id != pending.targetId)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                BrandSpacing.lg,
                BrandSpacing.sm,
                BrandSpacing.lg,
                0,
              ),
              child: Material(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(BrandSpacing.md),
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: BrandSpacing.md,
                    runSpacing: BrandSpacing.sm,
                    children: [
                      Text(
                        'Auth ban still needs retry for ${pending.targetId}. Database access is already blocked.',
                      ),
                      FilledButton.icon(
                        key: const Key('customer-auth-ban-retry'),
                        onPressed: _submitting
                            ? null
                            : () => _mutate(pending, 'Auth ban confirmed.'),
                        icon: const Icon(Icons.lock_reset),
                        label: const Text('Retry Auth ban'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (_error != null && _results == null)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Customer data could not be loaded. Try again.'),
            ),
          Expanded(
            child: _results == null
                ? const Center(child: Text('Search for a customer to begin.'))
                : _results!.isEmpty
                ? const Center(child: Text('No customers found.'))
                : wide
                ? Row(
                    key: const Key('customers-wide-layout'),
                    children: [
                      Expanded(flex: 2, child: _list()),
                      const VerticalDivider(width: 1),
                      Expanded(flex: 3, child: _detailView()),
                    ],
                  )
                : (_compactDetail && _detail != null
                      ? KeyedSubtree(
                          key: const Key('customer-compact-detail'),
                          child: _detailView(compact: true),
                        )
                      : KeyedSubtree(
                          key: const Key('customers-compact-layout'),
                          child: _list(),
                        )),
          ),
        ],
      );
      return content;
    },
  );

  Widget _list() => ListView.separated(
    padding: const EdgeInsets.all(BrandSpacing.md),
    itemCount: _results!.length,
    separatorBuilder: (_, _) => const Divider(),
    itemBuilder: (_, i) {
      final item = _results![i];
      return ListTile(
        minVerticalPadding: 12,
        selected: item.id == _selectedId,
        title: Text(item.email),
        subtitle: Text('${item.isActive ? 'Active' : 'Disabled'} · ${item.id}'),
        onTap: _submitting
            ? null
            : () => _select(item, explicitSelection: true),
      );
    },
  );
  Widget _detailView({bool compact = false}) {
    final item = _detail;
    if (item == null) {
      return const Center(
        key: Key('customer-detail-loading'),
        child: CircularProgressIndicator(),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(BrandSpacing.lg),
      children: [
        if (compact)
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              tooltip: 'Back to customer results',
              onPressed: _submitting
                  ? null
                  : () => setState(() => _compactDetail = false),
              icon: const Icon(Icons.arrow_back),
            ),
          ),
        Text(item.summary.email, style: Theme.of(context).textTheme.titleLarge),
        SelectableText(item.summary.id),
        const SizedBox(height: 16),
        _row('Account', item.summary.isActive ? 'Active' : 'Disabled'),
        _row('Created', _date(item.summary.createdAt)),
        _row('Last activity', _date(item.summary.lastActivityAt)),
        _row(
          'Gmail connection',
          item.gmailConnected ? 'Connected' : 'Not connected',
        ),
        _row('Gmail status', item.gmailStatus?.wireValue ?? 'No request'),
        if (item.gmailFailure != null)
          _row('Safe failure', item.gmailFailure!.label),
        _row('Owned cards', '${item.ownedCardCount}'),
        _row(
          'Statements',
          '${item.processedStatementCount} processed of ${item.statementCount}',
        ),
        _row(
          'Emails',
          '${item.processedEmailCount} processed of ${item.emailCount}',
        ),
        _row('Deletion request', item.deletionStatus?.label ?? 'None'),
        const SizedBox(height: 20),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              key: const Key('customer-retry'),
              onPressed: item.retryEligible && !_submitting ? _retry : null,
              icon: const Icon(Icons.sync),
              label: const Text('Queue Gmail retry'),
            ),
            OutlinedButton.icon(
              key: const Key('customer-disable'),
              onPressed: item.summary.isActive && !_submitting
                  ? () => _confirmed(true)
                  : null,
              icon: const Icon(Icons.block),
              label: const Text('Disable account'),
            ),
            OutlinedButton.icon(
              key: const Key('customer-deletion'),
              onPressed: !_submitting ? () => _confirmed(false) : null,
              icon: const Icon(Icons.assignment_outlined),
              label: const Text('Update deletion status'),
            ),
            if (_pendingAuthBan case final pending?)
              FilledButton.icon(
                key: const Key('customer-auth-ban-retry'),
                onPressed: !_submitting && pending.targetId == item.summary.id
                    ? () => _mutate(pending, 'Auth ban confirmed.')
                    : null,
                icon: const Icon(Icons.lock_reset),
                label: const Text('Retry Auth ban'),
              ),
          ],
        ),
      ],
    );
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 150,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(child: Text(value)),
      ],
    ),
  );
  String _date(DateTime value) => value.toLocal().toString().split('.').first;
}

final class _Confirmation {
  const _Confirmation(this.reason, this.target, this.status);
  final String reason, target;
  final DeletionStatus? status;
}

class _CustomerConfirmationDialog extends StatefulWidget {
  const _CustomerConfirmationDialog({
    required this.targetId,
    required this.disable,
  });
  final String targetId;
  final bool disable;
  @override
  State<_CustomerConfirmationDialog> createState() =>
      _CustomerConfirmationDialogState();
}

class _CustomerConfirmationDialogState
    extends State<_CustomerConfirmationDialog> {
  final reason = TextEditingController(), target = TextEditingController();
  DeletionStatus status = DeletionStatus.requested;
  @override
  void dispose() {
    reason.dispose();
    target.dispose();
    super.dispose();
  }

  bool get valid =>
      reason.text.trim().length >= 2 && target.text.trim() == widget.targetId;
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.disable
          ? 'Disable customer account?'
          : 'Update deletion progress?',
    ),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.disable
                ? 'This immediately blocks database access. A separate Auth ban is then attempted.'
                : 'This records progress only. It does not delete customer data.',
          ),
          const SizedBox(height: 12),
          if (!widget.disable)
            DropdownButtonFormField<DeletionStatus>(
              initialValue: status,
              decoration: const InputDecoration(labelText: 'Deletion status'),
              items: DeletionStatus.values
                  .map((s) => DropdownMenuItem(value: s, child: Text(s.label)))
                  .toList(),
              onChanged: (v) => setState(() => status = v!),
            ),
          TextField(
            key: const Key('customer-confirm-reason'),
            controller: reason,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Reason'),
          ),
          TextField(
            key: const Key('customer-confirm-target'),
            controller: target,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Type target user ID',
              helperText: widget.targetId,
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const Key('customer-confirm-submit'),
        onPressed: valid
            ? () => Navigator.pop(
                context,
                _Confirmation(
                  reason.text.trim(),
                  target.text.trim(),
                  widget.disable ? null : status,
                ),
              )
            : null,
        child: Text(widget.disable ? 'Disable account' : 'Confirm status'),
      ),
    ],
  );
}
