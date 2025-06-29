import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cardcompass/core/repositories/card_repository.dart';
import 'package:cardcompass/core/repositories/transaction_repository.dart';
import 'package:cardcompass/core/repositories/statement_repository.dart';
import 'package:cardcompass/core/repositories/supabase_card_repository.dart';
import 'package:cardcompass/core/repositories/supabase_transaction_repository.dart';
import 'package:cardcompass/core/repositories/supabase_statement_repository.dart';

/// Provider for CardRepository
/// For now using Supabase implementation, can be switched based on configuration
final cardRepositoryProvider = Provider<CardRepository>((ref) {
  return SupabaseCardRepository();
});

/// Provider for TransactionRepository
/// Using Supabase implementation
final transactionRepositoryProvider = Provider<TransactionRepository>((ref) {
  return SupabaseTransactionRepository();
});

/// Provider for StatementRepository
final statementRepositoryProvider = Provider<StatementRepository>((ref) {
  return SupabaseStatementRepository();
});
