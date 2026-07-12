import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cardcompass/core/services/benefit_import_service.dart';

/// Debug app for testing benefit import functionality in monospaced cyber terminal theme
class BenefitImportDebugApp extends StatefulWidget {
  const BenefitImportDebugApp({super.key});

  @override
  State<BenefitImportDebugApp> createState() => _BenefitImportDebugAppState();
}

class _BenefitImportDebugAppState extends State<BenefitImportDebugApp> {
  final BenefitImportService _importService = BenefitImportService();
  bool _isLoading = false;
  String _status = 'TERMINAL READY. WAITING FOR COMMANDS...';
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
    Color getStatusColor() {
      if (_status.contains('Error') || _status.contains('failed') || _status.contains('❌')) {
        return const Color(0xFFFF3333);
      }
      if (_status.contains('successfully') || _status.contains('✅') || _status.contains('READY')) {
        return const Color(0xFF33FF33);
      }
      return const Color(0xFFFFFF33);
    }

    return Scaffold(
      backgroundColor: const Color(0xFF050505),
      appBar: AppBar(
        backgroundColor: const Color(0xFF050505),
        elevation: 0,
        title: Text(
          'BENEFIT_IMPORTER_DEBUG_v1.0.sh',
          style: GoogleFonts.shareTechMono(
            color: const Color(0xFF33FF33),
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF33FF33)),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status Terminal Panel
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF0B0B0B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF33FF33).withValues(alpha: 0.3), width: 1.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: getStatusColor(),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'SYSTEM_STATUS_LOG:',
                        style: GoogleFonts.shareTechMono(
                          color: const Color(0xFF33FF33),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _status.toUpperCase(),
                    style: GoogleFonts.shareTechMono(
                      color: getStatusColor(),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            
            // Test Button
            OutlinedButton(
              onPressed: _isLoading ? null : _testImportService,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFF33FF33), width: 1.5),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: _isLoading
                  ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF33FF33),
                          ),
                        ),
                      ],
                    )
                  : Text(
                      'EXECUTE: testImport()',
                      style: GoogleFonts.shareTechMono(color: const Color(0xFF33FF33), fontSize: 13, fontWeight: FontWeight.bold),
                    ),
            ),
            const SizedBox(height: 12),
            
            // Run Full Import Button
            ElevatedButton(
              onPressed: _isLoading ? null : _runFullImport,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF33FF33),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: _isLoading
                  ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black,
                          ),
                        ),
                      ],
                    )
                  : Text(
                      'EXECUTE: importFromEnhancedCsv()',
                      style: GoogleFonts.shareTechMono(color: Colors.black, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
            ),
            const SizedBox(height: 28),
            
            if (_lastResult != null) ...[
              Text(
                'COMPILATION_OUTPUT_FEED:',
                style: GoogleFonts.shareTechMono(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0B0B0B),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white10, width: 1),
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildResultRow('SUCCESS', _lastResult!['success']?.toString() ?? 'N/A'),
                        _buildResultRow('MESSAGE', _lastResult!['message']?.toString() ?? 'N/A'),
                        if (_lastResult!.containsKey('cards_processed'))
                          _buildResultRow('CARDS_PROCESSED', _lastResult!['cards_processed']?.toString() ?? '0'),
                        if (_lastResult!.containsKey('benefits_created'))
                          _buildResultRow('BENEFITS_CREATED', _lastResult!['benefits_created']?.toString() ?? '0'),
                        if (_lastResult!.containsKey('total_csv_records'))
                          _buildResultRow('CSV_RECORDS_COUNT', _lastResult!['total_csv_records']?.toString() ?? '0'),
                        if (_lastResult!.containsKey('error'))
                          _buildResultRow('COMPILER_ERROR', _lastResult!['error']?.toString() ?? '', isError: true),
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
    final activeColor = isError ? const Color(0xFFFF3333) : const Color(0xFF33FF33);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              '$label:',
              style: GoogleFonts.shareTechMono(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Text(
              value.toUpperCase(),
              style: GoogleFonts.shareTechMono(
                color: activeColor,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _testImportService() async {
    if (_disposed) return;
    _safeSetState(() {
      _isLoading = true;
      _status = 'RUNNING DIAGNOSTIC TEST ROUTINES...';
    });

    try {
      final result = await _importService.testImport();
      if (_disposed) return;
      _safeSetState(() {
        _lastResult = result;
        _status = result['success'] == true 
            ? 'TEST PIPELINE COMPLETED SUCCESSFULLY ✅'
            : 'TEST SCHEMATICS FAILED ❌';
      });
    } catch (e) {
      if (_disposed) return;
      _safeSetState(() {
        _status = 'TEST COMPILE ERROR: $e';
        _lastResult = {
          'success': false,
          'message': 'Diagnostic routines terminated prematurely',
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

  Future<void> _runFullImport() async {
    if (_disposed) return;
    _safeSetState(() {
      _isLoading = true;
      _status = 'PIPELINE RUNNING: PARSING CSV DATABASE...';
    });

    try {
      final result = await _importService.importFromEnhancedCsv();
      if (_disposed) return;
      _safeSetState(() {
        _lastResult = result;
        _status = result['success'] == true 
            ? 'DATABASE IMPORT COMPLETED SUCCESSFULLY ✅'
            : 'DATABASE IMPORT PROCESS FAILED ❌';
      });
    } catch (e) {
      if (_disposed) return;
      _safeSetState(() {
        _status = 'IMPORT COMPILE ERROR: $e';
        _lastResult = {
          'success': false,
          'message': 'CSV parsing script crashed',
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
