import 'package:flutter/material.dart';
import 'package:cardcompass/shared/models/statement.dart';
import 'package:cardcompass/config/constants.dart';
import 'package:intl/intl.dart';

class StatementItem extends StatelessWidget {
  final Statement statement;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;
  final bool showActions;

  const StatementItem({
    super.key,
    required this.statement,
    this.onTap,
    this.onDelete,
    this.showActions = true,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Statement date and status
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _formatStatementPeriod(),
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            statement.processed 
                                ? Icons.check_circle 
                                : Icons.pending,
                            size: 16,
                            color: statement.processed 
                                ? Colors.green 
                                : Colors.orange,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            statement.processed ? 'Processed' : 'Pending',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: statement.processed 
                                  ? Colors.green 
                                  : Colors.orange,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  
                  // Actions menu
                  if (showActions)
                    PopupMenuButton<String>(
                      onSelected: (value) {
                        switch (value) {
                          case 'delete':
                            onDelete?.call();
                            break;
                          case 'reprocess':
                            _reprocessStatement(context);
                            break;
                          case 'download':
                            _downloadStatement(context);
                            break;
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'download',
                          child: Row(
                            children: [
                              Icon(Icons.download),
                              SizedBox(width: 8),
                              Text('Download'),
                            ],
                          ),
                        ),
                        if (!statement.processed)
                          const PopupMenuItem(
                            value: 'reprocess',
                            child: Row(
                              children: [
                                Icon(Icons.refresh),
                                SizedBox(width: 8),
                                Text('Reprocess'),
                              ],
                            ),
                          ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete, color: Colors.red),
                              SizedBox(width: 8),
                              Text('Delete', style: TextStyle(color: Colors.red)),
                            ],
                          ),
                        ),
                      ],
                      child: const Icon(Icons.more_vert),
                    ),
                ],
              ),
              
              const SizedBox(height: 12),
              
              // Statement details
              Row(
                children: [
                  Expanded(
                    child: _buildDetailItem(
                      context,
                      'Total Amount',
                      '${AppConstants.currencySymbol}${statement.totalAmount.toStringAsFixed(2)}',
                      Icons.account_balance_wallet,
                    ),
                  ),
                  Expanded(
                    child: _buildDetailItem(
                      context,
                      'Due Date',
                      DateFormat(AppConstants.displayDateFormat).format(statement.dueDate),
                      Icons.schedule,
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 8),
              
              Row(
                children: [
                  Expanded(
                    child: _buildDetailItem(
                      context,
                      'Min Payment',
                      '${AppConstants.currencySymbol}${statement.minimumPayment.toStringAsFixed(2)}',
                      Icons.payment,
                    ),
                  ),
                  Expanded(
                    child: _buildDetailItem(
                      context,
                      'Transactions',
                      '${statement.transactionCount ?? 0}',
                      Icons.receipt,
                    ),
                  ),
                ],
              ),
              
              // Progress indicator for processing
              if (!statement.processed)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Processing statement...',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.orange[700],
                        ),
                      ),
                      const SizedBox(height: 4),
                      LinearProgressIndicator(
                        backgroundColor: Colors.grey[200],
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailItem(
    BuildContext context,
    String label,
    String value,
    IconData icon,
  ) {
    return Row(
      children: [
        Icon(
          icon,
          size: 16,
          color: Colors.grey[600],
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey[600],
                ),
              ),
              Text(
                value,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatStatementPeriod() {
    final formatter = DateFormat('MMM yyyy');
    return 'Statement - ${formatter.format(statement.statementDate)}';
  }

  void _reprocessStatement(BuildContext context) {
    // Show confirmation dialog
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reprocess Statement'),
        content: const Text(
          'This will reprocess the statement and extract transactions again. '
          'Any manually edited transactions will be overwritten.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              // TODO: Implement reprocessing logic
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Reprocessing statement...')),
              );
            },
            child: const Text('Reprocess'),
          ),
        ],
      ),
    );
  }

  void _downloadStatement(BuildContext context) {
    // TODO: Implement download logic
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Downloading statement...')),
    );
  }
}
