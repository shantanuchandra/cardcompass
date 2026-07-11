import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cardcompass/core/config/ai_config.dart';

/// Utility class for managing dashboard dialogs
class DashboardDialogs {
  
  /// Show sync data configuration dialog
  static Future<Map<String, dynamic>?> showSyncDialog(BuildContext context) async {
    final numberOfEmailsController = TextEditingController(text: '30');
    DateTime? startDate = DateTime.now().subtract(const Duration(days: 30));

    // Ollama parameters
    var localProvider = AIConfig.activeProvider;
    final ollamaUrlController = TextEditingController(text: AIConfig.ollamaUrl);
    final ollamaModelController = TextEditingController(text: AIConfig.ollamaModel);

    // Groq parameters
    final groqApiKeyController = TextEditingController(text: AIConfig.groqApiKey);
    final groqModelController = TextEditingController(text: AIConfig.groqModel);

    // Instantly cache in memory as they type
    ollamaUrlController.addListener(() => AIConfig.ollamaUrl = ollamaUrlController.text.trim());
    ollamaModelController.addListener(() => AIConfig.ollamaModel = ollamaModelController.text.trim());
    groqApiKeyController.addListener(() => AIConfig.groqApiKey = groqApiKeyController.text.trim());
    groqModelController.addListener(() => AIConfig.groqModel = groqModelController.text.trim());

    return showDialog<Map<String, dynamic>>(

      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            // Models dropdown lists
            final groqModels = ['llama-3.3-70b-versatile', 'llama-3.1-8b-instant', 'mixtral-8x7b-32768'];
            if (!groqModels.contains(groqModelController.text)) {
              groqModels.insert(0, groqModelController.text);
            }

            final ollamaModels = ['gemma4', 'gemma2', 'llama3', 'mistral'];
            if (!ollamaModels.contains(ollamaModelController.text)) {
              ollamaModels.insert(0, ollamaModelController.text);
            }

            return AlertDialog(

              title: const Row(
                children: [
                  Icon(Icons.sync, color: Colors.blue),
                  SizedBox(width: 8),
                  Text('Sync Data from Gmail'),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                       'This will fetch credit card statements from your Gmail account and import transactions into the app.',
                      style: TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: numberOfEmailsController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Number of emails to read',
                        hintText: 'Enter 999 for all',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Start Date: ${DateFormat.yMd().format(startDate!)}',
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.calendar_today),
                          onPressed: () async {
                            final pickedDate = await showDatePicker(
                              context: context,
                              initialDate: startDate!,
                              firstDate: DateTime(2000),
                              lastDate: DateTime.now(),
                            );
                            if (pickedDate != null) {
                              setState(() {
                                startDate = pickedDate;
                              });
                            }
                          },
                        ),
                      ],
                    ),
                    const Divider(height: 32),
                    const Text(
                      'AI LLM Parsing Engine Settings',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<AIProvider>(
                      value: localProvider,
                      decoration: const InputDecoration(
                        labelText: 'LLM Provider',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: AIProvider.gemini,
                          child: Text('Google Gemini (Cloud)'),
                        ),
                        DropdownMenuItem(
                          value: AIProvider.groq,
                          child: Text('Groq API (Cloud)'),
                        ),
                        DropdownMenuItem(
                          value: AIProvider.ollama,
                          child: Text('Ollama (Local LLM)'),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            localProvider = val;
                          });
                        }
                      },
                    ),
                    if (localProvider == AIProvider.groq) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: groqApiKeyController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Groq API Key',
                          hintText: 'gsk_...',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: groqModelController.text,
                        decoration: const InputDecoration(
                          labelText: 'Groq Model Name',
                          border: OutlineInputBorder(),
                        ),
                        items: groqModels.map((m) => DropdownMenuItem(
                          value: m,
                          child: Text(m),
                        )).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            groqModelController.text = val;
                            setState(() {});
                          }
                        },
                      ),
                    ],

                    if (localProvider == AIProvider.ollama) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: ollamaUrlController,
                        decoration: const InputDecoration(
                          labelText: 'Ollama Host URL',
                          hintText: 'http://localhost:11434',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: ollamaModelController.text,
                        decoration: const InputDecoration(
                          labelText: 'Ollama Model Name',
                          border: OutlineInputBorder(),
                        ),
                        items: ollamaModels.map((m) => DropdownMenuItem(
                          value: m,
                          child: Text(m),
                        )).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            ollamaModelController.text = val;
                            setState(() {});
                          }
                        },
                      ),

                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.amber.shade300),
                        ),
                        child: const Text(
                          'Note: Ensure your local Ollama is running and CORS origins are enabled (set OLLAMA_ORIGINS="*" before starting).',
                          style: TextStyle(fontSize: 11, color: Colors.brown),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    const Text(
                      '• Gmail will be searched for bank statements\n'
                      '• PDF attachments will be parsed\n'
                      '• Transactions will be imported to the database\n'
                      '• Credit cards will be automatically detected',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    // Apply and save LLM configs
                    await AIConfig.saveConfiguration(
                      localProvider,
                      ollamaUrlController.text.trim(),
                      ollamaModelController.text.trim(),
                      groqKey: groqApiKeyController.text.trim(),
                      groqMod: groqModelController.text.trim(),
                    );


                    final numberOfEmails = int.tryParse(numberOfEmailsController.text) ?? 30;
                    Navigator.of(context).pop({
                      'numberOfEmails': numberOfEmails,
                      'startDate': startDate,
                    });
                  },
                  child: const Text('Start Sync'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Show delete confirmation dialog with data counts
  static Future<bool?> showDeleteConfirmationDialog(
    BuildContext context, 
    Map<String, int> counts,
  ) async {
    return showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.delete_forever, color: Colors.red),
              SizedBox(width: 8),
              Text('Delete All Data'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This will permanently delete ALL your data from the app (except your user profile):',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              if (counts.isNotEmpty) ...[
                Text('📊 Current data to be deleted:', 
                     style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                const SizedBox(height: 8),
                ...counts.entries.map((entry) => Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 4),
                  child: Text(
                    '• ${entry.value} ${entry.key}',
                    style: const TextStyle(fontSize: 12),
                  ),
                )),
              ] else ...[
                const Text(
                  '• All credit cards\n'
                  '• All transactions\n'
                  '• All statements\n'
                  '• All email data\n'
                  '\nNote: Your user profile will be preserved.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
              const SizedBox(height: 12),
              const Text(
                '⚠️ This action cannot be undone!',
                style: TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Delete All'),
            ),
          ],
        );
      },
    );
  }

  /// Show results dialog for operations
  static void showResultsDialog(
    BuildContext context, {
    required String title,
    required String message,
    required bool success,
    String? actionButtonText,
    VoidCallback? onActionPressed,
  }) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(
                success ? Icons.check_circle : Icons.error,
                color: success ? Colors.green : Colors.red,
              ),
              const SizedBox(width: 8),
              Text(title),
            ],
          ),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
            if (actionButtonText != null && onActionPressed != null)
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  onActionPressed();
                },
                child: Text(actionButtonText),
              ),
          ],
        );
      },
    );
  }

  /// Show loading dialog with custom message
  static void showLoadingDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 16),
              Expanded(child: Text(message)),
            ],
          ),
        );
      },
    );
  }
}
