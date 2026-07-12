import 'package:cardcompass/shared/models/statement.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cardcompass/shared/widgets/state_widgets.dart';
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

    return Scaffold(
      backgroundColor: const Color(0xFF050B18),
      appBar: AppBar(
        title: Text(
          'STATEMENTS LEDGER',
          style: GoogleFonts.spaceGrotesk(
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
            fontSize: 16,
          ),
        ),
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
      ),
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
      return const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(AppTheme.primaryColor)));
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
            padding: const EdgeInsets.all(12.0),
            child: Text(
              state.uploadProgress!.toUpperCase(),
              style: GoogleFonts.spaceGrotesk(color: AppTheme.primaryColor, fontSize: 11, fontWeight: FontWeight.bold),
            ),
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
        title: 'NO DOCUMENTS FOUND',
        message: 'Upload credit card statement PDFs or sync with Gmail API.',
        icon: Icons.description_outlined,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
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
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
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
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      statement.fileName.toUpperCase(),
                      style: GoogleFonts.spaceGrotesk(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'STAGED: ${_formatDate(statement.createdAt)}',
                      style: GoogleFonts.spaceGrotesk(
                        color: Colors.white30,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              _buildStatusChip(statement.processed),
            ],
          ),
          const SizedBox(height: 16),
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
                  child: Text('VIEW DETAILED DATA', style: GoogleFonts.spaceGrotesk(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.primaryColor)),
                ),
              ),
              const SizedBox(width: 12),
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: chipColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: chipColor.withValues(alpha: 0.2)),
      ),
      child: Text(
        isProcessed ? 'PROCESSED' : 'PENDING',
        style: GoogleFonts.spaceGrotesk(
          color: chipColor,
          fontWeight: FontWeight.bold,
          fontSize: 9,
          letterSpacing: 0.5,
        ),
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
          content: Text('Identity required to upload statements.', style: GoogleFonts.spaceGrotesk(fontSize: 12)),
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
                borderRadius: BorderRadius.circular(20),
                side: const BorderSide(color: Color(0xFF1E293B)),
              ),
              title: Text(
                'UPLOAD STATEMENT PDF',
                style: GoogleFonts.spaceGrotesk(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
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
                          style: GoogleFonts.plusJakartaSans(color: Colors.white70),
                        )
                      else
                        DropdownButtonFormField<CreditCard>(
                          dropdownColor: const Color(0xFF0C152B),
                          initialValue: selectedCard,
                          hint: Text('SELECT TARGET CARD', style: GoogleFonts.spaceGrotesk(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold)),
                          isExpanded: true,
                          items: userCards.map((card) {
                            return DropdownMenuItem<CreditCard>(
                              value: card,
                              child: Text(
                                '${card.cardName.toUpperCase()} - ${card.bankName.toUpperCase()}',
                                style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
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
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppTheme.primaryColor),
                        ),
                        icon: const Icon(Icons.attach_file, color: AppTheme.primaryColor, size: 16),
                        label: Text('CHOOSE STATEMENT FILE', style: GoogleFonts.spaceGrotesk(color: AppTheme.primaryColor, fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                      if (selectedFileName != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12.0),
                          child: Text(
                            'FILE SELECTED: $selectedFileName',
                            style: GoogleFonts.spaceGrotesk(color: AppTheme.successColor, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                    ],
                  );
                },
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text('CANCEL', style: GoogleFonts.spaceGrotesk(color: Colors.white70)),
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
                  child: Text('PROCESS STATEMENT', style: GoogleFonts.spaceGrotesk(color: const Color(0xFF050B18), fontWeight: FontWeight.bold, fontSize: 11)),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
