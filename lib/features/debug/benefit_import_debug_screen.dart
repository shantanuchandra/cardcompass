import 'package:flutter/material.dart';
import 'package:cardcompass/core/services/benefit_import_service.dart';

/// Debug app for testing benefit import functionality
class BenefitImportDebugApp extends StatefulWidget {
  const BenefitImportDebugApp({super.key});

  @override
  State<BenefitImportDebugApp> createState() => _BenefitImportDebugAppState();
}

class _BenefitImportDebugAppState extends State<BenefitImportDebugApp> {
  final BenefitImportService _importService = BenefitImportService();
  bool _isLoading = false;
  String _status = 'Ready to import benefits';
  Map<String, dynamic>? _lastResult;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _safeSetState(VoidCallback fn) {
    if (!_disposed && mounted) {
      setState(fn);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Benefit Import Debug'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Benefit Import Status',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _status,
                      style: TextStyle(
                        color: _status.contains('Error') || _status.contains('Failed') 
                            ? Colors.red 
                            : _status.contains('Success') || _status.contains('completed')
                            ? Colors.green
                            : Colors.orange,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isLoading ? null : _testImportService,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _isLoading
                  ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(width: 8),
                        Text('Testing...'),
                      ],
                    )
                  : const Text(
                      'Test Import Service',
                      style: TextStyle(fontSize: 16),
                    ),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _isLoading ? null : _runFullImport,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _isLoading
                  ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(width: 8),
                        Text('Importing...'),
                      ],
                    )
                  : const Text(
                      'Run Full Import from CSV',
                      style: TextStyle(fontSize: 16),
                    ),
            ),
            const SizedBox(height: 24),
            if (_lastResult != null) ...[
              const Text(
                'Last Import Result:',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Card(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildResultRow('Success', _lastResult!['success']?.toString() ?? 'N/A'),
                        _buildResultRow('Message', _lastResult!['message']?.toString() ?? 'N/A'),
                        if (_lastResult!.containsKey('cards_processed'))
                          _buildResultRow('Cards Processed', _lastResult!['cards_processed']?.toString() ?? '0'),
                        if (_lastResult!.containsKey('benefits_created'))
                          _buildResultRow('Benefits Created', _lastResult!['benefits_created']?.toString() ?? '0'),
                        if (_lastResult!.containsKey('total_csv_records'))
                          _buildResultRow('CSV Records', _lastResult!['total_csv_records']?.toString() ?? '0'),
                        if (_lastResult!.containsKey('error'))
                          _buildResultRow('Error', _lastResult!['error']?.toString() ?? '', isError: true),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildResultRow(String label, String value, {bool isError = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: isError ? Colors.red : null,
                fontFamily: isError ? 'monospace' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }  Future<void> _testImportService() async {
    if (_disposed) return;
    _safeSetState(() {
      _isLoading = true;
      _status = 'Testing import service...';
    });

    try {
      final result = await _importService.testImport();
      if (_disposed) return;
      _safeSetState(() {
        _lastResult = result;
        _status = result['success'] == true 
            ? 'Test completed successfully ✅'
            : 'Test failed ❌: ${result['message']}';
      });
    } catch (e) {
      if (_disposed) return;
      _safeSetState(() {
        _status = 'Test error: $e';
        _lastResult = {
          'success': false,
          'message': 'Test execution failed',
          'error': e.toString(),
        };
      });
    } finally {
      if (_disposed) return;
      _safeSetState(() {
        _isLoading = false;
      });
    }
  }  Future<void> _runFullImport() async {
    if (_disposed) return;
    _safeSetState(() {
      _isLoading = true;
      _status = 'Running full benefit import from CSV...';
    });

    try {
      final result = await _importService.importFromEnhancedCsv();
      if (_disposed) return;
      _safeSetState(() {
        _lastResult = result;
        _status = result['success'] == true 
            ? 'Import completed successfully ✅'
            : 'Import failed ❌: ${result['message']}';
      });
    } catch (e) {
      if (_disposed) return;
      _safeSetState(() {
        _status = 'Import error: $e';
        _lastResult = {
          'success': false,
          'message': 'Import execution failed',
          'error': e.toString(),
        };
      });
    } finally {
      if (_disposed) return;
      _safeSetState(() {
        _isLoading = false;
      });
    }
  }
}
