import 'package:cardcompass/shared/models/statement.dart';
import 'package:cardcompass/shared/widgets/state_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Screen to display details of a single statement and its transactions
class StatementDetailsScreen extends ConsumerWidget {
  final Statement statement;

  const StatementDetailsScreen({super.key, required this.statement});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: Text(statement.fileName),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              // TODO: Implement refresh functionality
            },
          ),
        ],
      ),      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStatementInfo(context),
          const SizedBox(height: 24),
          Text(
            'Transactions',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const Divider(height: 16),          const EmptyState(
            title: 'Coming Soon',
            message: 'Transaction details will be implemented soon.',
            icon: Icons.receipt_long_outlined,
          ),
        ],
      ),
    );
  }

  Widget _buildStatementInfo(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Statement Details',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            _buildInfoRow('File Name', statement.fileName),
            _buildInfoRow('Total Amount', '₹${statement.totalAmount.toStringAsFixed(2)}'),
            _buildInfoRow('Due Date', _formatDate(statement.dueDate)),
            _buildInfoRow('Statement Date', _formatDate(statement.statementDate)),
            if (statement.rewardsEarned > 0)
              _buildInfoRow('Rewards Earned', statement.rewardsEarned.toString()),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}
