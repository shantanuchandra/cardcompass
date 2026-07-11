import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cardcompass/core/theme.dart';
import 'package:cardcompass/core/services/pruning_audit_service.dart';
import 'package:cardcompass/core/services/pm_feedback_service.dart';

/// PM Pruning Verification Ground screen in high-fidelity cyber terminal theme
class PmPruningDebugScreen extends StatefulWidget {
  const PmPruningDebugScreen({super.key});

  @override
  State<PmPruningDebugScreen> createState() => _PmPruningDebugScreenState();
}

class _PmPruningDebugScreenState extends State<PmPruningDebugScreen> {
  final PruningAuditService _auditService = PruningAuditService();
  bool _isLoading = false;
  List<Map<String, dynamic>> _logs = [];
  Map<String, dynamic>? _selectedLog;
  String _searchQuery = '';
  String _statusFilter = 'All'; // 'All', 'Needs PM Review', 'Confirmed', 'Clean'
  
  final TextEditingController _commentController = TextEditingController();
  final TextEditingController _feedbackInputController = TextEditingController();
  List<Map<String, dynamic>> _feedbacks = [];
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _loadLogs();
    _loadFeedbacks();
  }

  @override
  void dispose() {
    _disposed = true;
    _commentController.dispose();
    super.dispose();
  }

  void _safeSetState(VoidCallback fn) {
    if (!_disposed && mounted) {
      setState(fn);
    }
  }

  Future<void> _loadLogs() async {
    _safeSetState(() => _isLoading = true);
    try {
      final logs = await _auditService.getLogs();
      _safeSetState(() {
        _logs = logs;
        if (logs.isNotEmpty) {
          // If no log is selected, or the previously selected log is no longer available, select the first one
          if (_selectedLog == null || !logs.any((l) => l['id'] == _selectedLog!['id'])) {
            _selectLog(logs.first);
          } else {
            // Update the selected log with the latest data from the loaded list
            final updatedLog = logs.firstWhere((l) => l['id'] == _selectedLog!['id']);
            _selectLog(updatedLog);
          }
        } else {
          _selectedLog = null;
        }
      });
    } catch (e) {
      print('Error loading pruning logs: $e');
    } finally {
      _safeSetState(() => _isLoading = false);
    }
  }

  void _selectLog(Map<String, dynamic> log) {
    _selectedLog = log;
    _commentController.text = log['pmComment'] ?? '';
  }

  Future<void> _updateStatus(String status) async {
    if (_selectedLog == null) return;
    final id = _selectedLog!['id'];
    final comment = _commentController.text;
    
    await _auditService.updateLogStatus(id, status, comment);
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('STATUS UPDATED TO: $status', style: GoogleFonts.shareTechMono(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF00F5FF),
      ),
    );
    await _loadLogs();
  }

  Future<void> _clearAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0C152B),
        title: Text('PURGE AUDIT LOGS', style: GoogleFonts.spaceGrotesk(color: AppTheme.errorColor, fontWeight: FontWeight.bold, fontSize: 14)),
        content: Text('This will permanently delete all pruning audit logs in the local Hive box. Continue?', style: GoogleFonts.plusJakartaSans(color: Colors.white70, fontSize: 12)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('CANCEL', style: GoogleFonts.spaceGrotesk(color: Colors.white60))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorColor),
            child: Text('PURGE', style: GoogleFonts.spaceGrotesk(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _auditService.clearLogs();
      _safeSetState(() {
        _logs = [];
        _selectedLog = null;
      });
      await _loadLogs();
    }
  }

  Future<void> _seedMock() async {
    await _auditService.seedMockLogs();
    await _loadLogs();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('MOCK STATEMENTS SEEDED ✅', style: GoogleFonts.shareTechMono(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF10B981),
      ),
    );
  }

  List<Map<String, dynamic>> _getFilteredLogs() {
    return _logs.where((log) {
      final matchesSearch = log['bankName'].toString().toLowerCase().contains(_searchQuery.toLowerCase()) ||
          log['cardVariant'].toString().toLowerCase().contains(_searchQuery.toLowerCase()) ||
          log['fileName'].toString().toLowerCase().contains(_searchQuery.toLowerCase());
      
      if (!matchesSearch) return false;

      if (_statusFilter == 'All') return true;
      if (_statusFilter == 'Needs PM Review') return log['reviewStatus'] == 'Needs PM Review';
      if (_statusFilter == 'Confirmed') return log['reviewStatus'] == 'Confirmed';
      if (_statusFilter == 'Clean') return log['reviewStatus'] == 'Clean' || log['reviewStatus'] == 'Confirmed';
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filteredLogs = _getFilteredLogs();
    final totalProcessed = _logs.length;
    final flaggedCount = _logs.where((l) => l['isFlagged'] == true).length;
    final confirmedCount = _logs.where((l) => l['reviewStatus'] == 'Confirmed').length;
    
    double avgReduction = 0.0;
    if (_logs.isNotEmpty) {
      final totalReduction = _logs.map((l) => (l['reductionRatio'] as num).toDouble()).reduce((a, b) => a + b);
      avgReduction = totalReduction / _logs.length;
    }

    return Scaffold(
      backgroundColor: const Color(0xFF050508),
      endDrawer: _buildFeedbackDrawer(context),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0C152B),
        elevation: 1,
        title: Text(
          'PRUNING_AUDIT_TRAINING_GROUND.bin',
          style: GoogleFonts.shareTechMono(
            color: const Color(0xFF00F5FF),
            fontSize: 15,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0,
          ),
        ),
        actions: [
          Builder(
            builder: (scaffoldContext) => TextButton.icon(
              icon: const Icon(Icons.feedback_outlined, color: Color(0xFF00F5FF), size: 14),
              label: Text('PM FEEDBACK', style: GoogleFonts.shareTechMono(color: const Color(0xFF00F5FF), fontSize: 11)),
              onPressed: () => Scaffold.of(scaffoldContext).openEndDrawer(),
            ),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            icon: const Icon(Icons.refresh, color: Color(0xFF00F5FF), size: 14),
            label: Text('RELOAD', style: GoogleFonts.shareTechMono(color: const Color(0xFF00F5FF), fontSize: 11)),
            onPressed: _loadLogs,
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            icon: const Icon(Icons.bolt_outlined, color: Color(0xFF10B981), size: 14),
            label: Text('SEED MOCK', style: GoogleFonts.shareTechMono(color: const Color(0xFF10B981), fontSize: 11)),
            onPressed: _seedMock,
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined, color: AppTheme.errorColor, size: 18),
            onPressed: _clearAll,
            tooltip: 'Clear All Audits',
          ),
          const SizedBox(width: 10),
        ],
        iconTheme: const IconThemeData(color: Color(0xFF00F5FF)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF00F5FF)))
          : LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 900;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Metrics Strip
                    _buildMetricsStrip(totalProcessed, flaggedCount, confirmedCount, avgReduction),
                    
                    // Main layout
                    Expanded(
                      child: isWide 
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Left sidebar: List
                                SizedBox(
                                  width: 320,
                                  child: _buildSidebarPanel(filteredLogs),
                                ),
                                // Right pane: Diff comparison and PM details
                                Expanded(
                                  child: _buildDetailsPanel(),
                                ),
                              ],
                            )
                          : Column(
                              children: [
                                // Top half: List (collapsible)
                                SizedBox(
                                  height: 220,
                                  child: _buildSidebarPanel(filteredLogs),
                                ),
                                // Bottom half: Diff
                                Expanded(
                                  child: _buildDetailsPanel(),
                                ),
                              ],
                            ),
                    ),
                  ],
                );
              },
            ),
    );
  }

  Widget _buildMetricsStrip(int total, int flagged, int confirmed, double avgReduction) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFF070B14),
        border: Border(bottom: BorderSide(color: Color(0xFF1E293B), width: 1)),
      ),
      child: Wrap(
        spacing: 20,
        runSpacing: 10,
        alignment: WrapAlignment.spaceBetween,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildMetricItem('TOTAL_PROCESSED', total.toString(), Colors.white),
              const SizedBox(width: 20),
              _buildMetricItem('POTENTIAL_LEAKS_⚠️', flagged.toString(), flagged > 0 ? AppTheme.errorColor : Colors.white24),
              const SizedBox(width: 20),
              _buildMetricItem('CONFIRMED_OK_✅', confirmed.toString(), confirmed > 0 ? const Color(0xFF10B981) : Colors.white24),
            ],
          ),
          _buildMetricItem(
            'AVG_COMPRESSION_RATIO', 
            '${avgReduction.toStringAsFixed(1)}%', 
            const Color(0xFF00F5FF),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricItem(String label, String value, Color valueColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: GoogleFonts.shareTechMono(color: Colors.white30, fontSize: 9, fontWeight: FontWeight.bold),
        ),
        Text(
          value,
          style: GoogleFonts.shareTechMono(color: valueColor, fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildSidebarPanel(List<Map<String, dynamic>> filteredLogs) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF070E1A),
        border: Border(right: BorderSide(color: Color(0xFF1E293B), width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Search & Filter
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Search Input
                TextField(
                  style: GoogleFonts.shareTechMono(color: Colors.white, fontSize: 12),
                  decoration: InputDecoration(
                    hintText: 'SEARCH BANK/FILE...',
                    hintStyle: GoogleFonts.shareTechMono(color: Colors.white24, fontSize: 11),
                    prefixIcon: const Icon(Icons.search, color: Colors.white24, size: 16),
                    fillColor: const Color(0xFF0B1426),
                    filled: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: Color(0xFF1E293B))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: Color(0xFF00F5FF))),
                  ),
                  onChanged: (val) {
                    setState(() {
                      _searchQuery = val;
                    });
                  },
                ),
                const SizedBox(height: 8),
                
                // Status Filter Segment
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: ['All', 'Needs PM Review', 'Confirmed'].map((filter) {
                      final isSelected = _statusFilter == filter;
                      Color btnColor = isSelected ? const Color(0xFF00F5FF) : Colors.white24;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6.0),
                        child: InkWell(
                          onTap: () {
                            setState(() {
                              _statusFilter = filter;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: isSelected ? const Color(0xFF00F5FF).withValues(alpha: 0.1) : Colors.transparent,
                              border: Border.all(color: btnColor, width: 1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              filter.toUpperCase(),
                              style: GoogleFonts.shareTechMono(
                                color: isSelected ? const Color(0xFF00F5FF) : Colors.white54,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
          
          const Divider(color: Color(0xFF1E293B), height: 1),
          
          // Logs list
          Expanded(
            child: filteredLogs.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text(
                        'NO AUDIT REGISTERS FOUND.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.shareTechMono(color: Colors.white24, fontSize: 11),
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: filteredLogs.length,
                    itemBuilder: (context, idx) {
                      final log = filteredLogs[idx];
                      final isSelected = _selectedLog != null && _selectedLog!['id'] == log['id'];
                      
                      Color statusColor = const Color(0xFF10B981); // Green for Clean/Confirmed
                      if (log['reviewStatus'] == 'Needs PM Review') {
                        statusColor = AppTheme.errorColor; // Red for Warnings
                      } else if (log['reviewStatus'] == 'Flagged') {
                        statusColor = AppTheme.warningColor; // Amber for PM Flagged
                      }
                      
                      return InkWell(
                        onTap: () => _selectLog(log),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: isSelected ? const Color(0xFF00F5FF).withValues(alpha: 0.05) : Colors.transparent,
                            border: Border(
                              bottom: const BorderSide(color: Color(0xFF1E293B), width: 1),
                              left: BorderSide(color: isSelected ? const Color(0xFF00F5FF) : Colors.transparent, width: 3),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${log['bankName'].toString().toUpperCase()} - ${log['cardVariant'].toString().toUpperCase()}',
                                      style: GoogleFonts.shareTechMono(
                                        color: isSelected ? const Color(0xFF00F5FF) : Colors.white.withValues(alpha: 0.87),
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Text(
                                    '${(log['reductionRatio'] as num).toStringAsFixed(0)}% CUT',
                                    style: GoogleFonts.shareTechMono(
                                      color: const Color(0xFF00F5FF).withValues(alpha: 0.7),
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                log['fileName'] ?? 'statement.pdf',
                                style: GoogleFonts.shareTechMono(color: Colors.white30, fontSize: 9),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 6),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    log['reviewStatus'].toString().toUpperCase(),
                                    style: GoogleFonts.shareTechMono(
                                      color: statusColor,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  if (log['potentialLeaks'] != null && (log['potentialLeaks'] as List).isNotEmpty)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                      decoration: BoxDecoration(color: AppTheme.errorColor.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(2)),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.warning_amber_rounded, color: AppTheme.errorColor, size: 8),
                                          const SizedBox(width: 2),
                                          Text(
                                            '${(log['potentialLeaks'] as List).length} LEAKS',
                                            style: GoogleFonts.shareTechMono(color: AppTheme.errorColor, fontSize: 8, fontWeight: FontWeight.bold),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsPanel() {
    if (_selectedLog == null) {
      return Center(
        child: Text(
          'SELECT A STATEMENT LOG REGISTER TO INITIATE REVIEW RUN.',
          style: GoogleFonts.shareTechMono(color: Colors.white24, fontSize: 12),
        ),
      );
    }

    final log = _selectedLog!;
    final leaks = List<Map<dynamic, dynamic>>.from(log['potentialLeaks'] ?? []);
    final hasLeaks = leaks.isNotEmpty;

    return Container(
      color: const Color(0xFF050508),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Selected Metadata strip
          _buildDetailsHeader(log),

          // Potential leaks warning banner
          if (hasLeaks) _buildLeaksBanner(leaks),

          // Split Views (Retained vs Pruned)
          Expanded(
            child: _buildSplitView(log),
          ),

          // PM Audit Feedback Form
          _buildFeedbackPanel(log),
        ],
      ),
    );
  }

  Widget _buildDetailsHeader(Map<String, dynamic> log) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF0C1426),
        border: Border(bottom: BorderSide(color: Color(0xFF1E293B), width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${log['bankName'].toString().toUpperCase()} - ${log['cardVariant'].toString().toUpperCase()}',
                  style: GoogleFonts.shareTechMono(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  'FILE_REF: ${log['fileName']} | TIMESTAMP: ${log['timestamp']}',
                  style: GoogleFonts.shareTechMono(color: Colors.white30, fontSize: 9),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'CUT_MARKER: "${log['cutMarker']}"',
                style: GoogleFonts.shareTechMono(color: const Color(0xFF8B5CF6), fontSize: 9, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 2),
              Text(
                'REDUCTION: ${log['originalLength']} → ${log['prunedLength']} Chars',
                style: GoogleFonts.shareTechMono(color: Colors.white54, fontSize: 9),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLeaksBanner(List<Map<dynamic, dynamic>> leaks) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.errorColor.withValues(alpha: 0.12),
        border: const Border(bottom: BorderSide(color: AppTheme.errorColor, width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: AppTheme.errorColor, size: 16),
              const SizedBox(width: 6),
              Text(
                'WARNING: POTENTIAL TRANSACTION DATA DETECTED IN PRUNED TEXT',
                style: GoogleFonts.shareTechMono(color: AppTheme.errorColor, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ...leaks.map((leak) {
            return Padding(
              padding: const EdgeInsets.only(left: 22, bottom: 4),
              child: RichText(
                text: TextSpan(
                  style: GoogleFonts.shareTechMono(color: Colors.white70, fontSize: 10),
                  children: [
                    TextSpan(text: 'Line ${leak['lineNumber']} [${leak['reason']}]: ', style: const TextStyle(color: Colors.white30)),
                    TextSpan(text: '"${leak['lineContent']}"', style: const TextStyle(color: AppTheme.errorColor, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildSplitView(Map<String, dynamic> log) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Container(
            height: 32,
            color: const Color(0xFF090E1A),
            child: TabBar(
              dividerColor: Colors.transparent,
              indicatorColor: const Color(0xFF00F5FF),
              labelColor: const Color(0xFF00F5FF),
              unselectedLabelColor: Colors.white30,
              labelStyle: GoogleFonts.shareTechMono(fontSize: 10, fontWeight: FontWeight.bold),
              tabs: const [
                Tab(text: 'RETAINED CONTENT (SENT TO LLM)'),
                Tab(text: 'PRUNED CONTENT (DISCARDED BOILERPLATE)'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                // Retained Text View
                _buildTextContentPanel(
                  content: log['prunedText'] ?? 'Empty',
                  highlightKeyword: null,
                  textColor: const Color(0xFF10B981), // green for retained
                ),
                // Pruned Text View
                _buildTextContentPanel(
                  content: log['removedText'] ?? 'No text was pruned.',
                  highlightKeyword: null,
                  textColor: Colors.white70,
                  alertLines: List<Map<dynamic, dynamic>>.from(log['potentialLeaks'] ?? []),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextContentPanel({
    required String content,
    String? highlightKeyword,
    required Color textColor,
    List<Map<dynamic, dynamic>>? alertLines,
  }) {
    if (alertLines == null || alertLines.isEmpty) {
      return Container(
        color: const Color(0xFF040406),
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: SelectableText(
            content,
            style: GoogleFonts.shareTechMono(color: textColor, fontSize: 11, height: 1.4),
          ),
        ),
      );
    }

    // If we have alert lines (potential leaks), we want to show lines with red highlight
    final lines = content.split('\n');
    return Container(
      color: const Color(0xFF040406),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
      child: ListView.builder(
        itemCount: lines.length,
        itemBuilder: (context, idx) {
          final lineNum = idx + 1;
          final line = lines[idx];
          
          final matchingAlert = alertLines.firstWhere(
            (leak) => leak['lineNumber'] == lineNum || (leak['lineContent'] != null && leak['lineContent'].toString().trim() == line.trim()),
            orElse: () => {},
          );

          final isAlert = matchingAlert.isNotEmpty;

          return Container(
            color: isAlert ? AppTheme.errorColor.withValues(alpha: 0.15) : Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 32,
                  child: Text(
                    lineNum.toString().padLeft(3, '0'),
                    style: GoogleFonts.shareTechMono(color: isAlert ? AppTheme.errorColor : Colors.white12, fontSize: 10),
                  ),
                ),
                Expanded(
                  child: SelectableText(
                    line,
                    style: GoogleFonts.shareTechMono(
                      color: isAlert ? AppTheme.errorColor : textColor,
                      fontWeight: isAlert ? FontWeight.bold : FontWeight.normal,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildFeedbackPanel(Map<String, dynamic> log) {
    Color reviewStatusColor = const Color(0xFF10B981);
    if (log['reviewStatus'] == 'Needs PM Review') {
      reviewStatusColor = AppTheme.errorColor;
    } else if (log['reviewStatus'] == 'Flagged') {
      reviewStatusColor = AppTheme.warningColor;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Color(0xFF0C1426),
        border: Border(top: BorderSide(color: Color(0xFF1E293B), width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'PRODUCT_MANAGER_AUDIT_LOG_AUDIT_REVIEWS',
                style: GoogleFonts.shareTechMono(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold),
              ),
              Row(
                children: [
                  Text(
                    'CURRENT_STATUS: ',
                    style: GoogleFonts.shareTechMono(color: Colors.white30, fontSize: 9),
                  ),
                  Text(
                    log['reviewStatus'].toString().toUpperCase(),
                    style: GoogleFonts.shareTechMono(color: reviewStatusColor, fontSize: 9, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Comment Box
              Expanded(
                child: TextField(
                  controller: _commentController,
                  maxLines: 2,
                  style: GoogleFonts.shareTechMono(color: Colors.white, fontSize: 11),
                  decoration: InputDecoration(
                    hintText: 'WRITE FEEDBACK / COMPILATION OBSERVATIONS...',
                    hintStyle: GoogleFonts.shareTechMono(color: Colors.white24, fontSize: 11),
                    fillColor: const Color(0xFF050B18),
                    filled: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: Color(0xFF1E293B))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: Color(0xFF00F5FF))),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Action buttons
              Column(
                children: [
                  // Confirm OK Button
                  ElevatedButton(
                    onPressed: () => _updateStatus('Confirmed'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      minimumSize: const Size(120, 36),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                    ),
                    child: Text(
                      'CONFIRM RULES',
                      style: GoogleFonts.shareTechMono(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Flag Error Button
                  OutlinedButton(
                    onPressed: () => _updateStatus('Flagged'),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppTheme.errorColor, width: 1),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      minimumSize: const Size(120, 36),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      foregroundColor: AppTheme.errorColor,
                    ),
                    child: Text(
                      'FLAG LEAK / BUG',
                      style: GoogleFonts.shareTechMono(fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _loadFeedbacks() async {
    try {
      final feedbacks = await PmFeedbackService().getFeedbacks();
      _safeSetState(() {
        _feedbacks = feedbacks;
      });
    } catch (e) {
      print('Error loading feedbacks: $e');
    }
  }

  Widget _buildFeedbackDrawer(BuildContext context) {
    return Drawer(
      backgroundColor: const Color(0xFF070E1A),
      surfaceTintColor: Colors.transparent,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'PM FEEDBACK HUB',
                    style: GoogleFonts.shareTechMono(
                      color: const Color(0xFF00F5FF),
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white60, size: 18),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'COMMIT GLOBAL INSTRUCTIONS OR PARSING RULES FOR THE AI AGENT. THESE RULES ARE WRITTEN BACK TO THE WORKSPACE ROOT REGISTRY TO DIRECT FUTURE CODE GENERATION RUNS.',
                style: GoogleFonts.plusJakartaSans(
                  color: Colors.white30,
                  fontSize: 9,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              
              // Input Field
              TextField(
                controller: _feedbackInputController,
                maxLines: 4,
                style: GoogleFonts.shareTechMono(color: Colors.white, fontSize: 12),
                decoration: InputDecoration(
                  hintText: 'TYPE SYSTEM RULES OR PARSING FEEDBACK...',
                  hintStyle: GoogleFonts.shareTechMono(color: Colors.white24, fontSize: 11),
                  fillColor: const Color(0xFF0B1426),
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: const BorderSide(color: Color(0xFF1E293B)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: const BorderSide(color: Color(0xFF00F5FF)),
                  ),
                  contentPadding: const EdgeInsets.all(10),
                ),
              ),
              const SizedBox(height: 10),
              
              // Commit Button
              ElevatedButton(
                onPressed: () async {
                  final text = _feedbackInputController.text.trim();
                  if (text.isEmpty) return;
                  
                  await PmFeedbackService().saveFeedback(text);
                  _feedbackInputController.clear();
                  await _loadFeedbacks();
                  
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('FEEDBACK COMMITTED TO WORKSPACE ✅', style: GoogleFonts.shareTechMono(color: Colors.black, fontWeight: FontWeight.bold)),
                      backgroundColor: const Color(0xFF10B981),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00F5FF),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                ),
                child: Text(
                  'COMMIT TO WORKSPACE',
                  style: GoogleFonts.shareTechMono(
                    color: const Color(0xFF050508),
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              
              Text(
                'COMMITTED REGISTRY',
                style: GoogleFonts.shareTechMono(
                  color: Colors.white30,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              
              // Feedbacks List
              Expanded(
                child: _feedbacks.isEmpty
                    ? Center(
                        child: Text(
                          'NO FEEDBACKS LOGGED YET.',
                          style: GoogleFonts.shareTechMono(color: Colors.white12, fontSize: 10),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _feedbacks.length,
                        itemBuilder: (context, idx) {
                          final item = _feedbacks[idx];
                          final date = DateTime.tryParse(item['timestamp']) ?? DateTime.now();
                          final dateStr = '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
                          
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0B1426),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'ENTRY #${item['id'].toString().substring(item['id'].toString().length.clamp(0, 4))}',
                                      style: GoogleFonts.shareTechMono(color: const Color(0xFF8B5CF6), fontSize: 9, fontWeight: FontWeight.bold),
                                    ),
                                    Text(
                                      dateStr,
                                      style: GoogleFonts.shareTechMono(color: Colors.white24, fontSize: 9),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  item['feedback'] ?? '',
                                  style: GoogleFonts.shareTechMono(color: Colors.white70, fontSize: 11, height: 1.3),
                                ),
                                const SizedBox(height: 6),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: InkWell(
                                    onTap: () async {
                                      await PmFeedbackService().deleteFeedback(item['id']);
                                      await _loadFeedbacks();
                                    },
                                    child: Text(
                                      'DELETE',
                                      style: GoogleFonts.shareTechMono(color: AppTheme.errorColor, fontSize: 9, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
