import '../../../shared/models/statement.dart';
import '../../../shared/models/transaction.dart';

class CardStatementArchive {
  CardStatementArchive({
    required Iterable<Statement> statements,
    required Iterable<Transaction> transactions,
  }) : statements = List.unmodifiable(
         [...statements]
           ..sort((a, b) => b.statementDate.compareTo(a.statementDate)),
       ),
       transactions = List.unmodifiable(
         [...transactions]
           ..sort((a, b) => b.transactionDate.compareTo(a.transactionDate)),
       );

  final List<Statement> statements;
  final List<Transaction> transactions;

  Statement? get latestStatement => statements.firstOrNull;

  List<Transaction> transactionsFor(String statementId) => List.unmodifiable(
    transactions.where((transaction) => transaction.statementId == statementId),
  );

  List<Transaction> get unbilledTransactions {
    final closedAt = latestStatement?.statementDate;
    if (closedAt == null) return const [];
    return List.unmodifiable(
      transactions.where(
        (transaction) =>
            transaction.statementId == null &&
            transaction.transactionDate.isAfter(closedAt),
      ),
    );
  }
}
