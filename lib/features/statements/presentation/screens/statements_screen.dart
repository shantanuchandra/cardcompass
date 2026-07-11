import 'package:cardcompass/shared/models/statement.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cardcompass/shared/widgets/state_widgets.dart';
import 'package:cardcompass/features/statements/viewmodels/statements_viewmodel.dart';
import 'package:cardcompass/features/auth/providers/auth_provider.dart';
import 'package:cardcompass/shared/models/credit_card.dart';
import 'package:file_picker/file_picker.dart';

class StatementsScreen extends ConsumerWidget {
  const StatementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statementsState = ref.watch(statementsViewModelProvider);
    final statementsViewModel = ref.read(statementsViewModelProvider.notifier);
    // Get the current user ID, or handle the case where the user is not logged in
    final userId = ref.watch(authStateProvider).user?.id ?? '';
    
    print('🔍 StatementsScreen: User ID: $userId');
    print('🔍 StatementsScreen: Statements count: ${statementsState.statements.length}');
    print('🔍 StatementsScreen: Loading: ${statementsState.isLoading}');
    print('🔍 StatementsScreen: Error: ${statementsState.error}');

    // Load statements when the screen is first built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (userId.isNotEmpty && statementsState.statements.isEmpty && !statementsState.isLoading) {
        print('🔄 StatementsScreen: Triggering loadStatements');
        statementsViewModel.loadStatements(userId);
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Credit Card Statements'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => statementsViewModel.refreshStatements(userId),
          ),
          IconButton(
            icon: const Icon(Icons.email_outlined),
            onPressed: () => statementsViewModel.fetchStatementsFromGmail(userId),
          ),
        ],
      ),
      body: _buildBody(context, statementsState, statementsViewModel, userId),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showUploadDialog(context, ref),
        child: const Icon(Icons.upload_file),
        tooltip: 'Upload Statement',
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    StatementsViewState state,
    StatementsViewModel viewModel,
    String userId,
  ) {
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.error != null) {
      return ErrorState(
        error: state.error!,
        onRetry: () => viewModel.loadStatements(userId),
      );
    }

    return Column(
      children: [
        if (state.isProcessing) const LinearProgressIndicator(),
        if (state.uploadProgress != null)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(state.uploadProgress!),
          ),
        Expanded(
          child: _buildStatementsList(context, state.statements, viewModel),
        ),
      ],
    );
  }

  Widget _buildStatementsList(
    BuildContext context,
    List<Statement> statements,
    StatementsViewModel viewModel,
  ) {
    if (statements.isEmpty) {
      return const EmptyState(
        title: 'No Statements Found',
        message: 'Upload your first credit card statement to get started',
        icon: Icons.description_outlined,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: statements.length,
      itemBuilder: (context, index) {
        final statement = statements[index];
        return _buildStatementCard(context, statement, viewModel);
      },
    );
  }

  Widget _buildStatementCard(
    BuildContext context,
    Statement statement,
    StatementsViewModel viewModel,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.description,
                  color: Theme.of(context).primaryColor,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        statement.fileName,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        'Uploaded: ${_formatDate(statement.createdAt)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                _buildStatusChip(statement.processed),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showStatementDetail(context, statement),
                    icon: const Icon(Icons.visibility),
                    label: const Text('View'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => viewModel.deleteStatement(statement.id),
                    icon: const Icon(Icons.delete),
                    label: const Text('Delete'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(bool isProcessed) {
    return Chip(
      label: Text(isProcessed ? 'Processed' : 'Pending'),
      backgroundColor: isProcessed ? Colors.green.shade100 : Colors.orange.shade100,
      labelStyle: TextStyle(
        color: isProcessed ? Colors.green.shade800 : Colors.orange.shade800,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  void _showStatementDetail(BuildContext context, Statement statement) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(statement.statementPeriod),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Total due: ₹${statement.totalAmount.toStringAsFixed(0)}'),
            Text('Minimum payment: ₹${statement.minimumPayment.toStringAsFixed(0)}'),
            Text('Due date: ${_formatDate(statement.dueDate)}'),
            Text('Rewards earned: ${statement.rewardsEarned.toStringAsFixed(0)}'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }

  void _showUploadDialog(BuildContext context, WidgetRef ref) {
    final viewModel = ref.read(statementsViewModelProvider.notifier);
    final userId = ref.read(authStateProvider).user?.id;

    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You must be logged in to upload statements.')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (dialogContext) {
        return Consumer(
          builder: (context, consumerRef, child) {
            final userCards = consumerRef.watch(statementsViewModelProvider).userCards;
            CreditCard? selectedCard;
            String? selectedFileName;
            String? selectedFilePath;

            return AlertDialog(
              title: const Text('Upload Statement'),
              content: StatefulBuilder(
                builder: (BuildContext context, StateSetter setState) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (userCards.isEmpty)
                        const Text('No credit cards found. Please add a card first.')
                      else
                        DropdownButtonFormField<CreditCard>(
                          initialValue: selectedCard,
                          hint: const Text('Select Card'),
                          isExpanded: true,
                          items: userCards.map((card) {
                            return DropdownMenuItem<CreditCard>(
                              value: card,
                              child: Text('${card.cardName} - ${card.bankName}'),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setState(() {
                              selectedCard = value;
                            });
                          },
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                        ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final result = await FilePicker.pickFiles(
                            type: FileType.custom,
                            allowedExtensions: ['pdf'],
                          );
                          if (result != null && result.files.single.path != null) {
                            setState(() {
                              selectedFileName = result.files.single.name;
                              selectedFilePath = result.files.single.path;
                            });
                          }
                        },
                        icon: const Icon(Icons.attach_file),
                        label: const Text('Choose PDF File'),
                      ),
                      if (selectedFileName != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            'Selected: $selectedFileName',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                    ],
                  );
                },
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: selectedCard == null || selectedFilePath == null
                      ? null
                      : () {
                          viewModel.processStatement(
                            userId: userId,
                            userCardId: selectedCard!.id,
                            filePath: selectedFilePath!,
                          );
                          Navigator.of(dialogContext).pop();
                        },
                  child: const Text('Upload & Process'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
