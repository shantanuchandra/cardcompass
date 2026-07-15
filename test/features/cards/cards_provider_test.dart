import 'package:cardcompass/core/providers/service_providers.dart'
    show statementRepositoryProvider;
import 'package:cardcompass/core/repositories/statement_repository.dart';
import 'package:cardcompass/features/auth/providers/auth_provider.dart';
import 'package:cardcompass/features/cards/providers/cards_provider.dart';
import 'package:cardcompass/shared/models/statement.dart';
import 'package:cardcompass/shared/models/user.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _AuthenticatedAuthNotifier extends AuthNotifier {
  @override
  AuthState build() => AuthState.authenticated(User(
        id: 'user-1',
        email: 'user@example.com',
        createdAt: DateTime(2026, 7, 1),
      ));
}

class _StatementRepositoryFake implements StatementRepository {
  _StatementRepositoryFake(this.statements);

  final List<Statement> statements;
  final List<String> requestedUserIds = [];

  @override
  Future<List<Statement>> getStatements(String userId) async {
    requestedUserIds.add(userId);
    return statements;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('statement summary provider loads and refreshes the signed-in user data',
      () async {
    final repository = _StatementRepositoryFake([
      Statement(
        id: 'statement-1',
        userId: 'user-1',
        userCardId: 'card-1',
        statementDate: DateTime(2026, 7, 1),
        dueDate: DateTime(2026, 7, 25),
        totalAmount: 900.50,
        paidAmount: 0,
        minimumPayment: 100,
        closingBalance: 900.50,
        availableCredit: 0,
        rewardsEarned: 0,
        interestCharged: 0,
        feesCharged: 0,
        paymentStatus: PaymentStatus.pending,
        filePath: '',
        fileName: 'statement.pdf',
        createdAt: DateTime(2026, 7, 1),
      ),
    ]);
    final container = ProviderContainer(overrides: [
      authProvider.overrideWith(_AuthenticatedAuthNotifier.new),
      statementRepositoryProvider.overrideWithValue(repository),
    ]);
    addTearDown(container.dispose);

    final first = await container.read(cardStatementSummariesProvider.future);
    container.invalidate(cardStatementSummariesProvider);
    final refreshed =
        await container.read(cardStatementSummariesProvider.future);

    expect(first['card-1']!.remainingAmount, 900.50);
    expect(refreshed['card-1']!.remainingAmount, 900.50);
    expect(repository.requestedUserIds, ['user-1', 'user-1']);
  });
}
