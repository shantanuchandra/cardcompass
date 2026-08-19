import 'dart:convert';

import 'package:cardcompass/features/admin2/customers/customer_models.dart';
import 'package:cardcompass/features/admin2/customers/customer_repository.dart';
import 'package:cardcompass/features/admin2/data/admin_operator_api.dart';
import 'package:cardcompass/features/admin2/data/admin_operator_repository.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Api implements AdminOperatorApi {
  _Api(this.responses);
  final List<AdminOperatorResponse> responses;
  final bodies = <Map<String, dynamic>>[];
  @override
  Future<AdminOperatorResponse> invoke(Map<String, dynamic> body) async {
    bodies.add(jsonDecode(jsonEncode(body)) as Map<String, dynamic>);
    return responses.removeAt(0);
  }
}

void main() {
  const user = '00000000-0000-4000-8000-000000000002';
  const request = '00000000-0000-4000-8000-000000000003';
  const updated = '2026-08-19T10:00:00Z';
  Map<String, dynamic> summary() => {
    'id': user,
    'email': 'user@example.com',
    'created_at': updated,
    'last_activity_at': updated,
    'is_active': true,
  };
  Map<String, dynamic> detail() => {
    ...summary(),
    'gmail_connected': true,
    'gmail_last_status': 'failed',
    'gmail_last_failure_category': 'gmail_unavailable',
    'gmail_last_updated_at': updated,
    'owned_card_count': 2,
    'statement_count': 3,
    'processed_statement_count': 1,
    'email_count': 4,
    'processed_email_count': 2,
    'latest_statement_at': updated,
    'latest_email_at': updated,
    'deletion_status': 'verified',
    'deletion_updated_at': updated,
  };

  test('strictly decodes deeply immutable summaries and detail', () async {
    final api = _Api([
      AdminOperatorResponse(200, {
        'items': [summary()],
      }),
      AdminOperatorResponse(200, {'customer': detail()}),
    ]);
    final repository = CustomerRepository(
      AdminOperatorRepository(api),
      requestIds: () => request,
    );
    final results = await repository.search(' USER@Example.com ');
    expect(results.single.email, 'user@example.com');
    expect(() => results.add(results.single), throwsUnsupportedError);
    final customer = await repository.detail(user);
    expect(customer.gmailFailure, CustomerFailure.gmailUnavailable);
    expect(customer.deletionStatus, DeletionStatus.verified);
    expect(api.bodies, [
      {
        'action': 'customer-search',
        'query': 'user@example.com',
        'limit': 25,
        'request_id': request,
      },
      {'action': 'customer-detail', 'target_id': user, 'request_id': request},
    ]);
  });

  test(
    'accepts exact UUID or normalized email fragment of at least three',
    () async {
      final api = _Api([
        const AdminOperatorResponse(200, {'items': []}),
      ]);
      final repository = CustomerRepository(
        AdminOperatorRepository(api),
        requestIds: () => request,
      );
      for (final value in ['', ' a ', 'ab']) {
        await expectLater(
          repository.search(value),
          throwsA(isA<AdminRequestFailed>()),
        );
      }
      await repository.search(user);
      expect(api.bodies.single['query'], user);
    },
  );

  test(
    'rejects extra, missing, coercible, or customer-content response fields',
    () async {
      for (final malformed in [
        {...summary(), 'subject': 'private'},
        {...summary()}..remove('email'),
        {...summary(), 'is_active': 'true'},
      ]) {
        final api = _Api([
          AdminOperatorResponse(200, {
            'items': [malformed],
          }),
        ]);
        await expectLater(
          CustomerRepository(
            AdminOperatorRepository(api),
            requestIds: () => request,
          ).search('user'),
          throwsA(isA<AdminRequestFailed>()),
        );
      }
    },
  );

  test('sends exact retry request and validates canonical receipt', () async {
    final api = _Api([
      const AdminOperatorResponse(200, {
        'result': {'request_id': request, 'status': 'queued'},
      }),
    ]);
    final repository = CustomerRepository(
      AdminOperatorRepository(api),
      requestIds: () => request,
    );
    final receipt = await repository.mutate(
      const QueueGmailRetry(targetId: user, observedUpdatedAt: updated),
    );
    expect(receipt, isA<GmailRetryReceipt>());
    expect(api.bodies.single, {
      'action': 'customer-retry',
      'target_id': user,
      'request_id': request,
      'observed_updated_at': updated,
    });
  });

  test(
    'requires reason and exact typed target for disable and deletion',
    () async {
      final repository = CustomerRepository(
        AdminOperatorRepository(_Api([])),
        requestIds: () => request,
      );
      for (final mutation in <CustomerMutation>[
        const DisableCustomer(
          targetId: user,
          observedUpdatedAt: updated,
          reason: ' ',
          confirmationUserId: user,
        ),
        const DisableCustomer(
          targetId: user,
          observedUpdatedAt: updated,
          reason: 'abuse',
          confirmationUserId: request,
        ),
        const SetCustomerDeletionStatus(
          targetId: user,
          observedUpdatedAt: updated,
          reason: ' ',
          confirmationUserId: user,
          status: DeletionStatus.scheduled,
        ),
      ]) {
        await expectLater(
          repository.mutate(mutation),
          throwsA(isA<AdminRequestFailed>()),
        );
      }
    },
  );

  test('sends exact disable and deletion bodies and maps receipts', () async {
    final api = _Api([
      const AdminOperatorResponse(200, {
        'result': {'user_id': user, 'is_active': false, 'auth_banned': true},
      }),
      const AdminOperatorResponse(200, {
        'result': {
          'user_id': user,
          'status': 'scheduled',
          'updated_at': updated,
        },
      }),
    ]);
    final repository = CustomerRepository(
      AdminOperatorRepository(api),
      requestIds: () => request,
    );
    await repository.mutate(
      const DisableCustomer(
        targetId: user,
        observedUpdatedAt: updated,
        reason: ' suspected abuse ',
        confirmationUserId: user,
      ),
    );
    await repository.mutate(
      const SetCustomerDeletionStatus(
        targetId: user,
        observedUpdatedAt: updated,
        reason: ' verified request ',
        confirmationUserId: user,
        status: DeletionStatus.scheduled,
      ),
    );
    expect(api.bodies.first, {
      'action': 'customer-disable',
      'target_id': user,
      'confirmation_user_id': user,
      'request_id': request,
      'observed_updated_at': updated,
      'reason': 'suspected abuse',
    });
    expect(api.bodies.last, {
      'action': 'customer-deletion-status',
      'target_id': user,
      'confirmation_user_id': user,
      'request_id': request,
      'observed_updated_at': updated,
      'status': 'scheduled',
      'reason': 'verified request',
    });
  });

  test('rejects whole requests over 32KiB before invocation', () async {
    final api = _Api([]);
    final repository = CustomerRepository(
      AdminOperatorRepository(api),
      requestIds: () => request,
    );
    await expectLater(
      repository.mutate(
        DisableCustomer(
          targetId: user,
          observedUpdatedAt: updated,
          reason: 'x' * 33000,
          confirmationUserId: user,
        ),
      ),
      throwsA(isA<AdminRequestFailed>()),
    );
    expect(api.bodies, isEmpty);
  });

  test('preserves auth_ban_pending as a stable operator-safe code', () async {
    final api = _Api([
      const AdminOperatorResponse(502, {'error': 'auth_ban_pending'}),
    ]);
    final repository = CustomerRepository(
      AdminOperatorRepository(api),
      requestIds: () => request,
    );
    await expectLater(
      repository.mutate(
        const DisableCustomer(
          targetId: user,
          observedUpdatedAt: updated,
          reason: 'suspected abuse',
          confirmationUserId: user,
        ),
      ),
      throwsA(
        isA<AdminRequestFailed>().having(
          (error) => error.message,
          'message',
          'auth_ban_pending',
        ),
      ),
    );
  });
}
