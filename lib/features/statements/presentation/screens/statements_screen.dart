import 'package:cardcompass/shared/models/statement.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cardcompass/shared/widgets/state_widgets.dart';
import 'package:cardcompass/shared/widgets/app_scaffold.dart';
import 'package:cardcompass/features/statements/viewmodels/statements_viewmodel.dart';
import 'package:cardcompass/features/auth/providers/auth_provider.dart';
import 'package:cardcompass/shared/models/credit_card.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cardcompass/core/theme.dart';
import 'statement_details_screen.dart';

class StatementsScreen extends ConsumerWidget {
  const StatementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statementsState = ref.watch(statementsViewModelProvider);
    final statementsViewModel = ref.read(statementsViewModelProvider.notifier);
    final userId = ref.watch(authStateProvider).user?.id ?? '';

    // Load statements when the screen is first built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (userId.isNotEmpty && statementsState.statements.isEmpty && !statementsState.isLoading) {
        statementsViewModel.loadStatements(userId);
      }
    });

    return CardCompassScaffold(
      title: 'Statements Ledger',
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh, color: AppTheme.primaryColor),
          onPressed: () => statementsViewModel.refreshStatements(userId),
        ),
        IconButton(
          icon: const Icon(Icons.mail_outline, color: AppTheme.primaryColor),
          onPressed: () => statementsViewModel.fetchStatementsFromGmail(userId),
        ),
      ],
      body: _buildBody(context, statementsState, statementsViewModel, userId),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 80), // raise above bottom nav
        child: FloatingActionButton(
          backgroundColor: AppTheme.primaryColor,
          elevation: 8,
          onPressed: () => _showUploadDialog(context, ref),
          child: const Icon(Icons.upload_outlined, color: Color(0xFF050B18)),
        ),
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
      return const LoadingState();
    }

    if (state.error != null) {
      return ErrorState(
        error: state.error!,
        onRetry: () => viewModel.loadStatements(userId),
      );
    }

    return Column(
      children: [
        if (state.isProcessing) const LinearProgressIndicator(color: AppTheme.primaryColor, backgroundColor: Color(0xFF050B18)),
        if (state.uploadProgress != null)
          Padding(
            padding: const EdgeInsets.all(AppSpacing.sm + AppSpacing.xs),
            child: Text(
              state.uploadProgress!.toUpperCase(),
              style: AppTextStyles.caption.copyWith(color: AppTheme.primaryColor, fontWeight: FontWeight.bold),
            ),
          ),
        Expanded(
          child: _buildStatementsList(context, state.statements, viewModel, userId),
        ),
      ],
    );
  }

  Widget _buildStatementsList(
    BuildContext context,
    List<Statement> statements,
    StatementsViewModel viewModel,
    String userId,
  ) {
    if (statements.isEmpty) {
      return RefreshIndicator(
        color: AppTheme.primaryColor,
        onRefresh: () => viewModel.refreshStatements(userId),
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: const Center(
                child: EmptyState(
                  title: 'NO DOCUMENTS FOUND',
                  message: 'Upload credit card statement PDFs or sync with Gmail API.',
                  icon: Icons.description_outlined,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: AppTheme.primaryColor,
      onRefresh: () => viewModel.refreshStatements(userId),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md + AppSpacing.xs, vertical: AppSpacing.lg - AppSpacing.xs),
        itemCount: statements.length,
        itemBuilder: (context, index) {
          final statement = statements[index];
          return _buildStatementCard(context, statement, viewModel);
        },
      ),
    ).animate().fadeIn(duration: 250.ms).slideY(begin: 0.05, end: 0);
  }

  Widget _buildStatementCard(
    BuildContext context,
    Statement statement,
    StatementsViewModel viewModel,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: const Color(0xFF0C152B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.description_outlined, color: AppTheme.primaryColor, size: 22),
              const SizedBox(width: AppSpacing.sm + AppSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      statement.fileName.toUpperCase(),
                      style: AppTextStyles.body2.copyWith(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'STAGED: ${_formatDate(statement.createdAt)}',
                      style: AppTextStyles.caption.copyWith(color: Colors.white30, fontSize: 9, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              _buildStatusChip(statement.processed),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => StatementDetailsScreen(statement: statement),
                      ),
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppTheme.primaryColor, width: 1.2),
                  ),
                  child: Text('VIEW DETAILED DATA', style: AppTextStyles.caption.copyWith(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.primaryColor)),
                ),
              ),
              const SizedBox(width: AppSpacing.sm + AppSpacing.xs),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: AppTheme.errorColor, size: 20),
                onPressed: () => viewModel.deleteStatement(statement.id),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(bool isProcessed) {
    final chipColor = isProcessed ? AppTheme.successColor : AppTheme.warningColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: chipColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppBorderRadius.md),
        border: Border.all(color: chipColor.withValues(alpha: 0.2)),
      ),
      child: Text(
        isProcessed ? 'PROCESSED' : 'PENDING',
        style: AppTextStyles.caption.copyWith(color: chipColor, fontWeight: FontWeight.bold, fontSize: 9, letterSpacing: 0.5),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  void _showUploadDialog(BuildContext context, WidgetRef ref) {
    final viewModel = ref.read(statementsViewModelProvider.notifier);
    final userId = ref.read(authStateProvider).user?.id;

    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Identity required to upload statements.', style: AppTextStyles.caption),
          backgroundColor: AppTheme.errorColor,
        ),
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
              backgroundColor: const Color(0xFF0C152B),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppBorderRadius.xl),
                side: const BorderSide(color: Color(0xFF1E293B)),
              ),
              title: Text(
                'UPLOAD STATEMENT PDF',
                style: AppTextStyles.heading3.copyWith(color: Colors.white, fontSize: 14),
              ),
              content: StatefulBuilder(
                builder: (BuildContext context, StateSetter setState) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (userCards.isEmpty)
                        Text(
                          'No credit cards linked. Please register a card profile first.',
                          style: AppTextStyles.body2.copyWith(color: Colors.white70),
                        )
                      else
                        DropdownButtonFormField<CreditCard>(
                          dropdownColor: const Color(0xFF0C152B),
                          initialValue: selectedCard,
                          hint: Text('SELECT TARGET CARD', style: AppTextStyles.caption.copyWith(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold)),
                          isExpanded: true,
                          items: userCards.map((card) {
                            return DropdownMenuItem<CreditCard>(
                              value: card,
                              child: Text(
                                '${card.cardName.toUpperCase()} - ${card.bankName.toUpperCase()}',
                                style: AppTextStyles.caption.copyWith(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setState(() {
                              selectedCard = value;
                            });
                          },
                          decoration: const InputDecoration(
                            contentPadding: EdgeInsets.symmetric(horizontal: AppSpacing.sm + AppSpacing.xs, vertical: AppSpacing.sm),
                          ),
                        ),
                      const SizedBox(height: AppSpacing.md),
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
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppTheme.primaryColor),
                        ),
                        icon: const Icon(Icons.attach_file, color: AppTheme.primaryColor, size: 16),
                        label: Text('CHOOSE STATEMENT FILE', style: AppTextStyles.caption.copyWith(color: AppTheme.primaryColor, fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                      if (selectedFileName != null)
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.sm + AppSpacing.xs),
                          child: Text(
                            'FILE SELECTED: $selectedFileName',
                            style: AppTextStyles.caption.copyWith(color: AppTheme.successColor, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                    ],
                  );
                },
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text('CANCEL', style: AppTextStyles.body2.copyWith(color: Colors.white70)),
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
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    disabledBackgroundColor: Colors.white10,
                  ),
                  child: Text('PROCESS STATEMENT', style: AppTextStyles.caption.copyWith(color: const Color(0xFF050B18), fontWeight: FontWeight.bold, fontSize: 11)),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
