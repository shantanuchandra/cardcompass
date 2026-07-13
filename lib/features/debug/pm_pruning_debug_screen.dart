import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cardcompass/core/theme.dart';
import 'package:cardcompass/core/services/pruning_audit_service.dart';
import 'package:cardcompass/core/services/pm_feedback_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cardcompass/core/services/advanced_benefit_calculation_service.dart';
import 'package:cardcompass/features/debug/models/benefit_review_candidate.dart';
import 'package:cardcompass/features/debug/widgets/benefit_candidate_review.dart';
import 'package:cardcompass/features/debug/widgets/benefit_refresh_pipeline.dart';
import 'dart:convert';
import 'package:cardcompass/core/services/parsing_logger.dart';

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
  String _statusFilter =
      'All'; // 'All', 'Needs PM Review', 'Confirmed', 'Clean'

  final TextEditingController _commentController = TextEditingController();
  final TextEditingController _feedbackInputController =
      TextEditingController();
  List<Map<String, dynamic>> _feedbacks = [];
  bool _disposed = false;

  // New tab state variables
  int _activeTab = 1; // 0 = Pruning Audit, 1 = Card Benefits Refresh
  final SupabaseClient _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _catalogCards = [];
  bool _isCatalogLoading = false;
  String _catalogSearchQuery = '';
  List<String> _extractionLogs = [];
  final ScrollController _logScrollController = ScrollController();
  final TextEditingController _customBankController = TextEditingController();
  final TextEditingController _customCardController = TextEditingController();
  final TextEditingController _customUrlController = TextEditingController();
  bool _isExtracting = false;
  Map<String, dynamic>? _selectedCardBenefits;
  String? _selectedCardName;
  String? _selectedValidationStatus;
  num? _selectedValidationConfidence;
  List<dynamic> _selectedValidationReasons = [];
  bool _showRawJson = false;
  @override
  void initState() {
    super.initState();
    _loadLogs();
    _loadFeedbacks();
    _loadCatalogCards();
    ParsingLogger.addListener(_onLogReceived);
  }

  @override
  void dispose() {
    _disposed = true;
    _commentController.dispose();
    _logScrollController.dispose();
    _customBankController.dispose();
    _customCardController.dispose();
    _customUrlController.dispose();
    ParsingLogger.removeListener(_onLogReceived);
    super.dispose();
  }

  void _onLogReceived(String log) {
    _safeSetState(() {
      _extractionLogs.add(log);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScrollController.hasClients) {
        _logScrollController.animateTo(
          _logScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _autoExtractAll() async {
    _safeSetState(() => _isExtracting = true);
    for (final card in _catalogCards) {
      bool hasBenefits = false;
      if (card['card_benefit_mapping'] is List &&
          (card['card_benefit_mapping'] as List).isNotEmpty) {
        hasBenefits = true;
      }
      if (hasBenefits) continue;

      _onLogReceived(
          '--- AUTO EXTRACTING: ${card['bank']} - ${card['card_name']} ---');
      final benefitService = AdvancedBenefitCalculationService();
      try {
        final result = await benefitService.extractAndUpdateBenefits(
          cardId: card['id'],
          cardName: card['card_name'],
          bankName: card['bank'],
          customUrl: card['card_url'] as String?,
        );

        if (result['success'] == true) {
          _onLogReceived(
              '✅ Validated and staged for PM review: ${card['card_name']}');
        } else {
          _onLogReceived(result['status'] == 'rejected'
              ? '⛔ Extraction rejected for ${card['card_name']}: ${result['validation_reasons']}'
              : '❌ Extraction failed: ${result['error']}');
        }
      } catch (e) {
        _onLogReceived('❌ Exception: $e');
      }
      // Small delay to prevent rate limits
      await Future.delayed(const Duration(seconds: 3));
    }
    _safeSetState(() => _isExtracting = false);
    _onLogReceived('🎉 AUTO-EXTRACTION BATCH COMPLETE!');
  }

  Future<void> _loadCatalogCards() async {
    _safeSetState(() {
      _isCatalogLoading = true;
    });
    try {
      final response = await _supabase
          .from('card_catalog')
          .select(
              '*, card_benefit_mapping(*), card_benefits_staging(id, status, created_at, calculated_confidence, validation_reasons, validation_warnings)')
          .order('bank', ascending: true);

      _safeSetState(() {
        _catalogCards = List<Map<String, dynamic>>.from(response);
      });
      _onLogReceived('✅ Loaded ${_catalogCards.length} cards from catalog.');
    } catch (e) {
      // Fallback without staging join (in case table doesn't exist)
      try {
        final response = await _supabase
            .from('card_catalog')
            .select('*, card_benefit_mapping(*)')
            .order('bank', ascending: true);
        _safeSetState(() {
          _catalogCards = List<Map<String, dynamic>>.from(response);
        });
        _onLogReceived(
            '✅ Loaded ${_catalogCards.length} cards (staging join unavailable).');
      } catch (e2) {
        _onLogReceived('❌ Error loading catalog: $e2');
      }
    } finally {
      _safeSetState(() {
        _isCatalogLoading = false;
      });
    }
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
          if (_selectedLog == null ||
              !logs.any((l) => l['id'] == _selectedLog!['id'])) {
            _selectLog(logs.first);
          } else {
            // Update the selected log with the latest data from the loaded list
            final updatedLog =
                logs.firstWhere((l) => l['id'] == _selectedLog!['id']);
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
        content: Text('STATUS UPDATED TO: $status',
            style: GoogleFonts.shareTechMono(
                color: Colors.black, fontWeight: FontWeight.bold)),
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
        title: Text('PURGE AUDIT LOGS',
            style: GoogleFonts.spaceGrotesk(
                color: AppTheme.errorColor,
                fontWeight: FontWeight.bold,
                fontSize: 14)),
        content: Text(
            'This will permanently delete all pruning audit logs in the local Hive box. Continue?',
            style: GoogleFonts.plusJakartaSans(
                color: Colors.white70, fontSize: 12)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('CANCEL',
                  style: GoogleFonts.spaceGrotesk(color: Colors.white60))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style:
                ElevatedButton.styleFrom(backgroundColor: AppTheme.errorColor),
            child: Text('PURGE',
                style: GoogleFonts.spaceGrotesk(
                    color: Colors.white, fontWeight: FontWeight.bold)),
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
        content: Text('MOCK STATEMENTS SEEDED ✅',
            style: GoogleFonts.shareTechMono(
                color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF10B981),
      ),
    );
  }

  List<Map<String, dynamic>> _getFilteredLogs() {
    return _logs.where((log) {
      final matchesSearch = log['bankName']
              .toString()
              .toLowerCase()
              .contains(_searchQuery.toLowerCase()) ||
          log['cardVariant']
              .toString()
              .toLowerCase()
              .contains(_searchQuery.toLowerCase()) ||
          log['fileName']
              .toString()
              .toLowerCase()
              .contains(_searchQuery.toLowerCase());

      if (!matchesSearch) return false;

      if (_statusFilter == 'All') return true;
      if (_statusFilter == 'Needs PM Review')
        return log['reviewStatus'] == 'Needs PM Review';
      if (_statusFilter == 'Confirmed')
        return log['reviewStatus'] == 'Confirmed';
      if (_statusFilter == 'Clean')
        return log['reviewStatus'] == 'Clean' ||
            log['reviewStatus'] == 'Confirmed';
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filteredLogs = _getFilteredLogs();
    final totalProcessed = _logs.length;
    final flaggedCount = _logs.where((l) => l['isFlagged'] == true).length;
    final confirmedCount =
        _logs.where((l) => l['reviewStatus'] == 'Confirmed').length;

    double avgReduction = 0.0;
    if (_logs.isNotEmpty) {
      final totalReduction = _logs
          .map((l) => (l['reductionRatio'] as num).toDouble())
          .reduce((a, b) => a + b);
      avgReduction = totalReduction / _logs.length;
    }

    return Scaffold(
      backgroundColor: const Color(0xFF050B18),
      endDrawer: _buildFeedbackDrawer(context),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0C152B),
        elevation: 1,
        title: Text(
          'CARDCOMPASS_AGENT_COMMAND_CENTER.bin',
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
              icon: const Icon(Icons.feedback_outlined,
                  color: Color(0xFF00F5FF), size: 14),
              label: Text('PM FEEDBACK',
                  style: GoogleFonts.shareTechMono(
                      color: const Color(0xFF00F5FF), fontSize: 11)),
              onPressed: () => Scaffold.of(scaffoldContext).openEndDrawer(),
            ),
          ),
          const SizedBox(width: 8),
          if (_activeTab == 0) ...[
            TextButton.icon(
              icon:
                  const Icon(Icons.refresh, color: Color(0xFF00F5FF), size: 14),
              label: Text('RELOAD',
                  style: GoogleFonts.shareTechMono(
                      color: const Color(0xFF00F5FF), fontSize: 11)),
              onPressed: _loadLogs,
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              icon: const Icon(Icons.bolt_outlined,
                  color: Color(0xFF10B981), size: 14),
              label: Text('SEED MOCK',
                  style: GoogleFonts.shareTechMono(
                      color: const Color(0xFF10B981), fontSize: 11)),
              onPressed: _seedMock,
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined,
                  color: AppTheme.errorColor, size: 18),
              onPressed: _clearAll,
              tooltip: 'Clear All Audits',
            ),
          ] else ...[
            TextButton.icon(
              icon:
                  const Icon(Icons.bolt, color: Colors.orangeAccent, size: 14),
              label: Text('AUTO-EXTRACT ALL',
                  style: GoogleFonts.shareTechMono(
                      color: Colors.orangeAccent, fontSize: 11)),
              onPressed: () async {
                _safeSetState(() => _isExtracting = true);
                for (final card in _catalogCards) {
                  // Skip if recently scraped (e.g., has benefits) to save time, or we can force it.
                  // Since goal is to populate ALL, we process those without benefits.
                  bool hasBenefits = false;
                  if (card['card_benefit_mapping'] is List &&
                      (card['card_benefit_mapping'] as List).isNotEmpty) {
                    hasBenefits = true;
                  }
                  if (hasBenefits) continue;

                  _onLogReceived(
                      '--- AUTO EXTRACTING: ${card['bank']} - ${card['card_name']} ---');
                  final benefitService = AdvancedBenefitCalculationService();
                  try {
                    final result =
                        await benefitService.extractAndUpdateBenefits(
                      cardId: card['id'],
                      cardName: card['card_name'],
                      bankName: card['bank'],
                      customUrl: card['card_url'] as String?,
                    );

                    if (result['success'] == true) {
                      _onLogReceived(
                          '✅ Validated and staged for PM review: ${card['card_name']}');
                    } else {
                      _onLogReceived(result['status'] == 'rejected'
                          ? '⛔ Extraction rejected for ${card['card_name']}: ${result['validation_reasons']}'
                          : '❌ Extraction failed: ${result['error']}');
                    }
                  } catch (e) {
                    _onLogReceived('❌ Exception: $e');
                  }
                  // Small delay to prevent rate limits
                  await Future.delayed(const Duration(seconds: 3));
                }
                _safeSetState(() => _isExtracting = false);
                _loadCatalogCards();
                _onLogReceived('🎉 AUTO-EXTRACTION BATCH COMPLETE!');
              },
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              icon:
                  const Icon(Icons.refresh, color: Color(0xFF00F5FF), size: 14),
              label: Text('RELOAD CATALOG',
                  style: GoogleFonts.shareTechMono(
                      color: const Color(0xFF00F5FF), fontSize: 11)),
              onPressed: _loadCatalogCards,
            ),
          ],
          const SizedBox(width: 10),
        ],
        iconTheme: const IconThemeData(color: Color(0xFF00F5FF)),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTabBar(),
          Expanded(
            child: _activeTab == 0
                ? (_isLoading
                    ? const Center(
                        child:
                            CircularProgressIndicator(color: Color(0xFF00F5FF)))
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final isWide = constraints.maxWidth > 900;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Metrics Strip
                              _buildMetricsStrip(totalProcessed, flaggedCount,
                                  confirmedCount, avgReduction),

                              // Main layout
                              Expanded(
                                child: isWide
                                    ? Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          // Left sidebar: List
                                          SizedBox(
                                            width: 320,
                                            child: _buildSidebarPanel(
                                                filteredLogs),
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
                                            child: _buildSidebarPanel(
                                                filteredLogs),
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
                      ))
                : _buildBenefitsRefreshView(),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0C152B),
        border: Border(bottom: BorderSide(color: Color(0xFF1E293B), width: 1)),
      ),
      child: Row(
        children: [
          _buildTabButton(0, 'STATEMENT PRUNING AUDIT'),
          _buildTabButton(1, 'CARD BENEFITS REFRESH'),
        ],
      ),
    );
  }

  Widget _buildTabButton(int index, String label) {
    final isSelected = _activeTab == index;
    return InkWell(
      onTap: () {
        setState(() {
          _activeTab = index;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isSelected ? const Color(0xFF00F5FF) : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.shareTechMono(
            color: isSelected ? const Color(0xFF00F5FF) : Colors.white30,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0,
          ),
        ),
      ),
    );
  }

  Widget _buildBenefitsRefreshView() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 380,
          child: _buildCatalogPanel(),
        ),
        Expanded(
          child: _buildBenefitsDisplayPanel(),
        ),
      ],
    );
  }

  Widget _buildCatalogPanel() {
    final filteredCards = _catalogCards.where((card) {
      final query = _catalogSearchQuery.toLowerCase();
      final name = (card['card_name'] ?? '').toString().toLowerCase();
      final bank = (card['bank'] ?? '').toString().toLowerCase();
      return name.contains(query) || bank.contains(query);
    }).toList();

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF070E1A),
        border: Border(right: BorderSide(color: Color(0xFF1E293B), width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Search box
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              style:
                  GoogleFonts.shareTechMono(color: Colors.white, fontSize: 12),
              decoration: InputDecoration(
                hintText: 'SEARCH CATALOG CARD...',
                hintStyle: GoogleFonts.shareTechMono(
                    color: Colors.white24, fontSize: 11),
                prefixIcon:
                    const Icon(Icons.search, color: Colors.white24, size: 16),
                fillColor: const Color(0xFF0B1426),
                filled: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: const BorderSide(color: Color(0xFF1E293B))),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: const BorderSide(color: Color(0xFF00F5FF))),
              ),
              onChanged: (val) {
                setState(() {
                  _catalogSearchQuery = val;
                });
              },
            ),
          ),

          const Divider(color: Color(0xFF1E293B), height: 1),

          Expanded(
            child: _isCatalogLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF00F5FF)))
                : filteredCards.isEmpty
                    ? Center(
                        child: Text(
                          'NO CARDS FOUND IN CATALOG.',
                          style: GoogleFonts.shareTechMono(
                              color: Colors.white24, fontSize: 11),
                        ),
                      )
                    : ListView.builder(
                        itemCount: filteredCards.length,
                        itemBuilder: (context, index) {
                          final card = filteredCards[index];
                          final cardId = card['id'] as String;
                          final cardName = card['card_name'] as String;
                          final bankName =
                              (card['bank'] ?? 'Unknown Bank') as String;

                          // Look for card benefit metadata if joined
                          dynamic lastScraped;
                          dynamic confidence;
                          bool hasStagingData = false;
                          // Also check staging data
                          if (card['card_benefits_staging'] is List &&
                              (card['card_benefits_staging'] as List)
                                  .isNotEmpty) {
                            final stagingMeta =
                                (card['card_benefits_staging'] as List).first;
                            lastScraped = stagingMeta['created_at'];
                            confidence = stagingMeta['calculated_confidence'];
                            hasStagingData = true;
                          }

                          String scrapedStr = 'Never Scraped';
                          if (lastScraped != null) {
                            final date =
                                DateTime.tryParse(lastScraped.toString());
                            if (date != null) {
                              final prefix =
                                  hasStagingData ? 'Staged' : 'Scrape';
                              scrapedStr =
                                  '$prefix: ${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
                            }
                          }

                          String confidenceStr = confidence != null
                              ? '${((confidence as num) * 100).toStringAsFixed(0)}%'
                              : 'N/A';

                          return InkWell(
                            onTap: () async {
                              _onLogReceived(
                                  '🤖 User selected: $bankName - $cardName');
                              _safeSetState(() {
                                _selectedCardName = '$bankName - $cardName';
                                _selectedCardBenefits = null; // reset
                                _selectedValidationStatus = null;
                                _selectedValidationConfidence = null;
                                _selectedValidationReasons = [];
                              });
                              {
                                // Staging is the only extraction/audit record. Active data is
                                // read through card_benefit_mapping in the review dialog.
                                _onLogReceived(
                                    '🔍 Checking staging table for $cardName...');
                                try {
                                  final stagingData = await _supabase
                                      .from('card_benefits_staging')
                                      .select(
                                          'extracted_data, status, created_at, calculated_confidence, validation_reasons')
                                      .eq('card_id', cardId)
                                      .order('created_at', ascending: false)
                                      .limit(1)
                                      .maybeSingle();
                                  if (stagingData != null &&
                                      stagingData['extracted_data'] != null) {
                                    _onLogReceived(
                                        '✅ Staging benefits found for $cardName (status: ${stagingData['status']})');
                                    _safeSetState(() {
                                      _selectedCardBenefits =
                                          stagingData['extracted_data']
                                              as Map<String, dynamic>;
                                      _selectedValidationStatus =
                                          stagingData['status']?.toString();
                                      _selectedValidationConfidence =
                                          stagingData['calculated_confidence']
                                              as num?;
                                      _selectedValidationReasons =
                                          stagingData['validation_reasons']
                                                  as List? ??
                                              [];
                                    });
                                  } else {
                                    _onLogReceived(
                                        '⚠️ No benefits found for $cardName (neither in DB nor staging)');
                                  }
                                } catch (e) {
                                  _onLogReceived(
                                      '⚠️ No active mappings or staging record found for $cardName');
                                }
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              decoration: const BoxDecoration(
                                border: Border(
                                    bottom: BorderSide(
                                        color: Color(0xFF1E293B), width: 1)),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${bankName.toUpperCase()} - ${cardName.toUpperCase()}',
                                          style: GoogleFonts.shareTechMono(
                                            color: Colors.white
                                                .withValues(alpha: 0.87),
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'SCRAPE: $scrapedStr | CONF: $confidenceStr',
                                          style: GoogleFonts.shareTechMono(
                                              color: Colors.white30,
                                              fontSize: 9),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton(
                                    onPressed: _isExtracting
                                        ? null
                                        : () => _triggerExtraction(
                                            cardId, cardName, bankName,
                                            customUrl:
                                                card['card_url'] as String?),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF0F172A),
                                      foregroundColor: const Color(0xFF00F5FF),
                                      side: const BorderSide(
                                          color: Color(0xFF00F5FF), width: 1),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 8),
                                      minimumSize: const Size(60, 30),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(4)),
                                    ),
                                    child: Text(
                                      'REFRESH',
                                      style: GoogleFonts.shareTechMono(
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold),
                                    ),
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

  Widget _buildBenefitsDisplayPanel() {
    if (_selectedCardBenefits == null) {
      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0A0F24), Color(0xFF030510)],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.auto_awesome,
                  size: 64,
                  color: const Color(0xFF00F5FF).withValues(alpha: 0.2)),
              const SizedBox(height: 24),
              Text(
                'SELECT A CARD TO VIEW EXTRACTED BENEFITS',
                style: GoogleFonts.shareTechMono(
                  color: const Color(0xFF00F5FF).withValues(alpha: 0.5),
                  fontSize: 14,
                  letterSpacing: 2.0,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Experience next-gen AI parsing visualization',
                style: GoogleFonts.plusJakartaSans(
                  color: Colors.white24,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final b = _selectedCardBenefits!;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0A0F24), Color(0xFF030510)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header with Glassmorphism
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              border: const Border(
                  bottom: BorderSide(color: Color(0xFF1E293B), width: 1)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _selectedCardName?.toUpperCase() ?? 'UNKNOWN CARD',
                      style: GoogleFonts.spaceGrotesk(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'VALIDATION: ${(_selectedValidationStatus ?? 'UNKNOWN').toUpperCase()} | CONF: ${_selectedValidationConfidence == null ? 'N/A' : '${(_selectedValidationConfidence! * 100).toStringAsFixed(0)}%'}',
                      style: GoogleFonts.shareTechMono(
                        color: _selectedValidationStatus == 'rejected'
                            ? AppTheme.errorColor
                            : const Color(0xFF10B981),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (_selectedValidationReasons.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      SizedBox(
                        width: 620,
                        child: Text(
                          _selectedValidationReasons
                              .map((reason) => reason is Map
                                  ? '${reason['code']}: ${reason['message']}'
                                  : reason.toString())
                              .join(' • '),
                          style: GoogleFonts.shareTechMono(
                            color: AppTheme.errorColor,
                            fontSize: 10,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF8B5CF6).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                            color:
                                const Color(0xFF8B5CF6).withValues(alpha: 0.5)),
                      ),
                      child: Text(
                        'ANNUAL FEE: ${_formatAnnualFee(b['annual_fee'])}',
                        style: GoogleFonts.shareTechMono(
                            color: const Color(0xFFD8B4FE),
                            fontSize: 11,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                // Toggle Button
                InkWell(
                  onTap: () =>
                      _safeSetState(() => _showRawJson = !_showRawJson),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: _showRawJson
                          ? const Color(0xFF00F5FF).withValues(alpha: 0.1)
                          : Colors.transparent,
                      border: Border.all(
                          color:
                              const Color(0xFF00F5FF).withValues(alpha: 0.5)),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Row(
                      children: [
                        Icon(_showRawJson ? Icons.code_off : Icons.code,
                            size: 16, color: const Color(0xFF00F5FF)),
                        const SizedBox(width: 8),
                        Text(
                          _showRawJson ? 'VIEW UI' : 'VIEW JSON',
                          style: GoogleFonts.shareTechMono(
                              color: const Color(0xFF00F5FF),
                              fontSize: 11,
                              fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Body
          Expanded(
            child: _showRawJson
                ? Container(
                    color: const Color(0xFF050508),
                    padding: const EdgeInsets.all(24),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        const JsonEncoder.withIndent('  ').convert(b),
                        style: GoogleFonts.shareTechMono(
                            color: const Color(0xFF10B981),
                            fontSize: 13,
                            height: 1.5),
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      // === STAGING FORMAT: benefits[] with categories ===
                      if (b['benefits'] != null &&
                          (b['benefits'] as List).isNotEmpty) ...[
                        // Annual fee info
                        if (b['annual_fee'] != null) ...[
                          _buildSectionTitle(
                              'FEES & CHARGES', Icons.account_balance_wallet),
                          const SizedBox(height: 12),
                          _buildStagingFeeCard(
                              b['annual_fee'] as Map<String, dynamic>),
                          const SizedBox(height: 24),
                        ],
                        // Group benefits by category
                        ..._buildStagingBenefitSections(b['benefits'] as List),
                        // Special benefits from staging
                        if (b['special_benefits'] != null &&
                            (b['special_benefits'] as List).isNotEmpty) ...[
                          _buildSectionTitle(
                              'SPECIAL BENEFITS', Icons.workspace_premium),
                          const SizedBox(height: 16),
                          ...(b['special_benefits'] as List).map((sb) =>
                              _buildStagingSpecialCard(
                                  sb as Map<String, dynamic>)),
                          const SizedBox(height: 32),
                        ],
                      ]
                      // === LEGACY FORMAT: reward_points, cashback_benefits, etc. ===
                      else ...[
                        if (_rewardPointEntries(b['reward_points'])
                            .isNotEmpty) ...[
                          _buildSectionTitle('REWARD MULTIPLIERS', Icons.stars),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 16,
                            runSpacing: 16,
                            children: _rewardPointEntries(b['reward_points'])
                                .map((rp) => _buildRewardCard(rp))
                                .toList(),
                          ),
                          const SizedBox(height: 32),
                        ],
                        if (b['special_benefits'] != null &&
                            (b['special_benefits'] as List).isNotEmpty) ...[
                          _buildSectionTitle(
                              'SPECIAL BENEFITS', Icons.workspace_premium),
                          const SizedBox(height: 16),
                          Column(
                            children: (b['special_benefits'] as List)
                                .map((sb) => _buildSpecialBenefitCard(sb))
                                .toList(),
                          ),
                          const SizedBox(height: 32),
                        ],
                        if (b['cashback_benefits'] != null &&
                            (b['cashback_benefits'] as List).isNotEmpty) ...[
                          _buildSectionTitle('CASHBACK', Icons.currency_rupee),
                          const SizedBox(height: 16),
                          Column(
                            children: (b['cashback_benefits'] as List)
                                .map((cb) => _buildCashbackCard(cb))
                                .toList(),
                          ),
                          const SizedBox(height: 32),
                        ],
                        if (b['milestone_benefits'] != null &&
                            (b['milestone_benefits'] as List).isNotEmpty) ...[
                          _buildSectionTitle('MILESTONE BENEFITS', Icons.flag),
                          const SizedBox(height: 16),
                          Column(
                            children: (b['milestone_benefits'] as List)
                                .map((mb) => _buildMilestoneCard(mb))
                                .toList(),
                          ),
                          const SizedBox(height: 32),
                        ],
                        if (b['redemption_value'] != null) ...[
                          _buildSectionTitle(
                              'REDEMPTION VALUE', Icons.monetization_on),
                          const SizedBox(height: 16),
                          _buildRedemptionCard(b['redemption_value']),
                          const SizedBox(height: 32),
                        ],
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF00F5FF), size: 18),
        const SizedBox(width: 8),
        Text(
          title,
          style: GoogleFonts.shareTechMono(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(child: Container(height: 1, color: const Color(0xFF1E293B))),
      ],
    );
  }

  // ─── Staging Format Widget Builders ───

  String _formatAnnualFee(dynamic fee) {
    if (fee == null) return 'N/A';
    if (fee is Map) {
      final first = fee['first_year'];
      final renewal = fee['renewal'];
      if (first != null && renewal != null) return '₹$first / ₹$renewal';
      if (first != null) return '₹$first';
      if (renewal != null) return '₹$renewal';
      return 'N/A';
    }
    return '₹$fee';
  }

  static const _categoryIcons = <String, IconData>{
    'REWARDS': Icons.stars,
    'CASHBACK': Icons.currency_rupee,
    'FUEL': Icons.local_gas_station,
    'DINING': Icons.restaurant,
    'TRAVEL': Icons.flight_takeoff,
    'SHOPPING': Icons.shopping_bag,
    'GROCERY': Icons.local_grocery_store,
    'ENTERTAINMENT': Icons.movie,
    'UTILITY': Icons.bolt,
    'LOUNGE': Icons.airline_seat_flat,
    'INSURANCE': Icons.shield,
    'MILESTONE': Icons.flag,
    'FOREX': Icons.currency_exchange,
    'GENERAL': Icons.credit_card,
  };

  static const _categoryColors = <String, Color>{
    'REWARDS': Color(0xFFFBBF24),
    'CASHBACK': Color(0xFF10B981),
    'FUEL': Color(0xFFF97316),
    'DINING': Color(0xFFEC4899),
    'TRAVEL': Color(0xFF3B82F6),
    'SHOPPING': Color(0xFF8B5CF6),
    'GROCERY': Color(0xFF22C55E),
    'ENTERTAINMENT': Color(0xFFEF4444),
    'UTILITY': Color(0xFF06B6D4),
    'LOUNGE': Color(0xFF6366F1),
    'INSURANCE': Color(0xFF14B8A6),
    'MILESTONE': Color(0xFFF59E0B),
    'FOREX': Color(0xFF0EA5E9),
    'GENERAL': Color(0xFF64748B),
  };

  Widget _buildStagingFeeCard(Map<String, dynamic> fee) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          if (fee['first_year'] != null)
            _buildFeeChip(
                '1ST YEAR', '₹${fee['first_year']}', const Color(0xFF8B5CF6)),
          if (fee['renewal'] != null) ...[
            const SizedBox(width: 16),
            _buildFeeChip(
                'RENEWAL', '₹${fee['renewal']}', const Color(0xFFF59E0B)),
          ],
          if (fee['waiver_conditions'] != null) ...[
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                '⚡ ${fee['waiver_conditions']}',
                style: GoogleFonts.plusJakartaSans(
                    color: Colors.white60, fontSize: 11),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFeeChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          Text(label,
              style: GoogleFonts.shareTechMono(
                  color: color, fontSize: 9, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(value,
              style: GoogleFonts.spaceGrotesk(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  List<Widget> _buildStagingBenefitSections(List benefits) {
    // Group by category
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final b in benefits) {
      final cat = (b['category'] as String?)?.toUpperCase() ?? 'GENERAL';
      grouped.putIfAbsent(cat, () => []);
      grouped[cat]!.add(Map<String, dynamic>.from(b));
    }

    final widgets = <Widget>[];
    for (final entry in grouped.entries) {
      final cat = entry.key;
      final items = entry.value;
      final icon = _categoryIcons[cat] ?? Icons.star;
      final color = _categoryColors[cat] ?? const Color(0xFF64748B);

      widgets.addAll([
        _buildSectionTitle(cat, icon),
        const SizedBox(height: 12),
        ...items.map((b) => _buildStagingBenefitCard(b, color)),
        const SizedBox(height: 24),
      ]);
    }
    return widgets;
  }

  Widget _buildStagingBenefitCard(Map<String, dynamic> b, Color accentColor) {
    final desc = b['description'] ?? 'Benefit';
    final value = b['value'];
    final valueType = b['value_type'] ?? '';
    final cap = b['monthly_cap'] ?? b['annual_cap'];

    String valueStr = '';
    if (value != null) {
      if (valueType == 'percentage') {
        valueStr = '$value%';
      } else if (valueType == 'multiplier') {
        valueStr = '${value}X';
      } else if (valueType == 'points_per_100') {
        valueStr = '$value pts/₹100';
      } else if (valueType == 'flat_amount') {
        valueStr = '₹$value';
      } else {
        valueStr = '$value';
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accentColor.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          if (valueStr.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                valueStr,
                style: GoogleFonts.spaceGrotesk(
                    color: accentColor,
                    fontSize: 14,
                    fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Text(
              desc,
              style: GoogleFonts.plusJakartaSans(
                  color: Colors.white.withValues(alpha: 0.85), fontSize: 13),
            ),
          ),
          if (cap != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Cap: $cap',
                style: GoogleFonts.shareTechMono(
                    color: Colors.white38, fontSize: 9),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStagingSpecialCard(Map<String, dynamic> sb) {
    final desc = sb['description'] ?? 'Special benefit';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF8B5CF6).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border:
            Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome, color: Color(0xFFD8B4FE), size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              desc,
              style: GoogleFonts.plusJakartaSans(
                  color: Colors.white.withValues(alpha: 0.8), fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRewardCard(Map<String, dynamic> rp) {
    return Container(
      width: 200,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${rp['rate'] ?? 0}x',
            style: GoogleFonts.spaceGrotesk(
              color: const Color(0xFF00F5FF),
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            (rp['category'] ?? '').toString().toUpperCase(),
            style: GoogleFonts.shareTechMono(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            rp['conditions'] ?? '',
            style: GoogleFonts.plusJakartaSans(
                color: Colors.white30, fontSize: 11),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _rewardPointEntries(dynamic rewardPoints) {
    if (rewardPoints is List) {
      return rewardPoints
          .whereType<Map>()
          .map(Map<String, dynamic>.from)
          .toList();
    }
    if (rewardPoints is! Map) return [];
    final rewards = Map<String, dynamic>.from(rewardPoints);
    final entries = <Map<String, dynamic>>[];
    if (rewards['base_rate'] is num) {
      entries.add({
        'rate': rewards['base_rate'],
        'category': 'Base rewards',
        'conditions': rewards['evidence_excerpt'] ?? '',
      });
    }
    if (rewards['accelerated_categories'] is List) {
      entries.addAll((rewards['accelerated_categories'] as List)
          .whereType<Map>()
          .map(Map<String, dynamic>.from));
    }
    return entries;
  }

  Widget _buildSpecialBenefitCard(Map<String, dynamic> sb) {
    IconData icon = Icons.check_circle_outline;
    Color accent = const Color(0xFF8B5CF6);

    if (sb['type'] == 'LOUNGE') {
      icon = Icons.flight_takeoff;
      accent = const Color(0xFFF59E0B);
    } else if (sb['type'] == 'FOREX') {
      icon = Icons.public;
      accent = const Color(0xFF10B981);
    } else if (sb['type'] == 'INSURANCE') {
      icon = Icons.shield;
      accent = const Color(0xFFEF4444);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: accent, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (sb['value'] ?? '').toString().toUpperCase(),
                  style: GoogleFonts.spaceGrotesk(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  sb['description'] ?? '',
                  style: GoogleFonts.plusJakartaSans(
                      color: Colors.white60, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCashbackCard(Map<String, dynamic> cb) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF10B981).withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${cb['rate'] ?? 0}%',
            style: GoogleFonts.spaceGrotesk(
                color: const Color(0xFF10B981),
                fontSize: 24,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  (cb['category'] ?? '').toString().toUpperCase(),
                  style: GoogleFonts.shareTechMono(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  cb['conditions'] ?? '',
                  style: GoogleFonts.plusJakartaSans(
                      color: Colors.white60, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMilestoneCard(Map<String, dynamic> mb) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF59E0B).withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.emoji_events,
                color: Color(0xFFF59E0B), size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (mb['threshold'] ?? '').toString().toUpperCase(),
                  style: GoogleFonts.spaceGrotesk(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  mb['reward'] ?? '',
                  style: GoogleFonts.plusJakartaSans(
                      color: const Color(0xFFF59E0B),
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRedemptionCard(Map<String, dynamic> rv) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF3B82F6).withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: const Color(0xFF3B82F6).withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: rv.entries.map((entry) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3B82F6).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    entry.key.toUpperCase(),
                    style: GoogleFonts.shareTechMono(
                        color: const Color(0xFF93C5FD),
                        fontSize: 10,
                        fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    entry.value.toString(),
                    style: GoogleFonts.plusJakartaSans(
                        color: Colors.white70, fontSize: 12),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCustomExtractionForm() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Color(0xFF070E1A),
        border: Border(bottom: BorderSide(color: Color(0xFF1E293B), width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'TRIGGER CUSTOM BENEFIT EXTRACTION',
            style: GoogleFonts.shareTechMono(
                color: Colors.white54,
                fontSize: 10,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _customBankController,
                  style: GoogleFonts.shareTechMono(
                      color: Colors.white, fontSize: 12),
                  decoration: InputDecoration(
                    labelText: 'BANK NAME',
                    labelStyle: GoogleFonts.shareTechMono(
                        color: Colors.white30, fontSize: 11),
                    hintText: 'e.g., HDFC Bank',
                    hintStyle: GoogleFonts.shareTechMono(
                        color: Colors.white12, fontSize: 11),
                    fillColor: const Color(0xFF050B18),
                    filled: true,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: const BorderSide(color: Color(0xFF1E293B))),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: const BorderSide(color: Color(0xFF00F5FF))),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _customCardController,
                  style: GoogleFonts.shareTechMono(
                      color: Colors.white, fontSize: 12),
                  decoration: InputDecoration(
                    labelText: 'CARD NAME',
                    labelStyle: GoogleFonts.shareTechMono(
                        color: Colors.white30, fontSize: 11),
                    hintText: 'e.g., Regalia Gold',
                    hintStyle: GoogleFonts.shareTechMono(
                        color: Colors.white12, fontSize: 11),
                    fillColor: const Color(0xFF050B18),
                    filled: true,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: const BorderSide(color: Color(0xFF1E293B))),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: const BorderSide(color: Color(0xFF00F5FF))),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _customUrlController,
                  style: GoogleFonts.shareTechMono(
                      color: Colors.white, fontSize: 12),
                  decoration: InputDecoration(
                    labelText: 'WEBSITE URL (OPTIONAL)',
                    labelStyle: GoogleFonts.shareTechMono(
                        color: Colors.white30, fontSize: 11),
                    hintText: 'e.g., https://www.hdfcbank.com/...',
                    hintStyle: GoogleFonts.shareTechMono(
                        color: Colors.white12, fontSize: 11),
                    fillColor: const Color(0xFF050B18),
                    filled: true,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: const BorderSide(color: Color(0xFF1E293B))),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: const BorderSide(color: Color(0xFF00F5FF))),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: _isExtracting
                    ? null
                    : () {
                        final bank = _customBankController.text.trim();
                        final card = _customCardController.text.trim();
                        final customUrl = _customUrlController.text.trim();
                        if (bank.isEmpty || card.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('BANK AND CARD NAMES ARE REQUIRED',
                                  style: GoogleFonts.shareTechMono(
                                      color: Colors.white)),
                              backgroundColor: AppTheme.errorColor,
                            ),
                          );
                          return;
                        }
                        _triggerExtraction(
                          'custom-run-${DateTime.now().millisecondsSinceEpoch}',
                          card,
                          bank,
                          customUrl: customUrl.isNotEmpty ? customUrl : null,
                        );
                      },
                icon: _isExtracting
                    ? const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.black),
                      )
                    : const Icon(Icons.bolt, size: 14),
                label: Text(
                  _isExtracting ? 'RUNNING...' : 'EXTRACT',
                  style: GoogleFonts.shareTechMono(
                      fontWeight: FontWeight.bold, fontSize: 12),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00F5FF),
                  foregroundColor: const Color(0xFF050508),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _triggerExtraction(
      String cardId, String cardName, String bankName,
      {String? customUrl}) async {
    _safeSetState(() {
      _isExtracting = true;
    });

    _onLogReceived('⚡ Starting extraction run for $bankName $cardName...');

    try {
      String finalCardId = cardId;
      if (cardId.startsWith('custom-run-')) {
        _onLogReceived(
            '🔍 Checking catalog database for $bankName $cardName...');
        final existing = await _supabase
            .from('card_catalog')
            .select('id')
            .eq('bank', bankName)
            .eq('card_name', cardName)
            .maybeSingle();

        if (existing != null) {
          finalCardId = existing['id'] as String;
          _onLogReceived('✅ Match found in catalog with ID: $finalCardId');
          if (customUrl != null && customUrl.isNotEmpty) {
            _onLogReceived('🔗 Updating catalog with provided source URL...');
            await _supabase
                .from('card_catalog')
                .update({'card_url': customUrl}).eq('id', finalCardId);
          }
        } else {
          _onLogReceived('🆕 Card not in catalog. Creating new entry...');
          final newCard = await _supabase
              .from('card_catalog')
              .insert({
                'card_name': cardName,
                'bank': bankName,
                'card_url': customUrl,
                'card_type': 'credit',
                'network': 'visa',
                'annual_fee': 0.0,
                'joining_fee': 0.0,
                'is_discontinued': false,
              })
              .select('id')
              .single();
          finalCardId = newCard['id'] as String;
          _onLogReceived('✅ Created catalog card with ID: $finalCardId');
        }
      }

      final benefitService = AdvancedBenefitCalculationService();
      final result = await benefitService.extractAndUpdateBenefits(
        cardId: finalCardId,
        cardName: cardName,
        bankName: bankName,
        customUrl: customUrl,
      );

      if (result['success'] == true) {
        if (result['direct_applied'] == true) {
          _onLogReceived(
              '✅ SUCCESS: Extracted ${result['benefits_extracted']} benefits (Direct Commit Fallback).');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('REFRESH COMPLETE: DIRECTLY APPLIED',
                  style: GoogleFonts.shareTechMono(
                      color: Colors.black, fontWeight: FontWeight.bold)),
              backgroundColor: const Color(0xFF10B981),
            ),
          );
          _loadCatalogCards();
        } else {
          final stagingId = result['staging_id'] as String;
          final extractedData =
              result['extracted_data'] as Map<String, dynamic>;
          _onLogReceived(
              '📋 STAGING: Benefits extracted and saved to staging (Staging ID: $stagingId). Opening review dialog...');

          _showReviewDialog(stagingId, cardName, bankName, extractedData);
        }
      } else {
        _onLogReceived('❌ FAILED: ${result['error']}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('REFRESH FAILED: ${result['error']}',
                style: GoogleFonts.shareTechMono(
                    color: Colors.white, fontWeight: FontWeight.bold)),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    } catch (e) {
      _onLogReceived('❌ EXCEPTION: $e');
    } finally {
      _safeSetState(() {
        _isExtracting = false;
      });
      // Reload catalog so the right panel can fetch fresh data
      _loadCatalogCards();
    }
  }

  Future<void> _showReviewDialog(
    String stagingId,
    String cardName,
    String bankName,
    Map<String, dynamic> candidateData,
  ) async {
    List<dynamic> activeBenefits = [];
    Map<String, dynamic>? activeFees;

    try {
      final cardCatalog = await _supabase
          .from('card_catalog')
          .select('annual_fee, joining_fee, rewards_summary')
          .eq('card_name', cardName)
          .eq('bank', bankName)
          .maybeSingle();
      if (cardCatalog != null) {
        activeFees = cardCatalog;
      }

      final catalogCard = _catalogCards.firstWhere(
        (c) => c['card_name'] == cardName && c['bank'] == bankName,
        orElse: () => <String, dynamic>{},
      );

      if (catalogCard.isNotEmpty) {
        final benefitsRes =
            await _supabase.from('card_benefit_mapping').select('''
              mapping_id, card_id, benefit_id, display_priority, is_primary,
              benefits!inner(benefit_id, title, description, benefit_category,
                benefit_type, value_config, is_active)
            ''').eq('card_id', catalogCard['id']);
        activeBenefits = benefitsRes as List;
      }
    } catch (e) {
      _onLogReceived('⚠️ Could not load active benefits for diff: $e');
    }

    if (!mounted) return;

    var reviewState = BenefitReviewState.fromExtractedData(candidateData);
    var applying = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(builder: (context, setDialogState) {
          return Dialog(
            backgroundColor: const Color(0xFF0C152B),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: const BorderSide(color: Color(0xFF00F5FF), width: 1)),
            child: Container(
              width: 1120,
              height: 720,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'AI_BENEFITS_REVIEW_DIFF_FLOW // ${bankName.toUpperCase()} ${cardName.toUpperCase()}',
                        style: GoogleFonts.shareTechMono(
                            color: const Color(0xFF00F5FF),
                            fontSize: 14,
                            fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close,
                            color: Colors.white30, size: 18),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const Divider(color: Color(0xFF1E293B), height: 16),
                  Expanded(
                      child: Row(children: [
                    const Expanded(
                      flex: 3,
                      child: BenefitRefreshPipeline(
                        stage: BenefitRefreshStage.pendingReview,
                      ),
                    ),
                    const VerticalDivider(color: Color(0xFF1E293B), width: 24),
                    Expanded(
                      flex: 4,
                      child: _buildReviewColumn(
                        title: 'ACTIVE BENEFITS (CURRENT MAPPINGS)',
                        headerColor: Colors.white54,
                        fees: activeFees,
                        benefits: activeBenefits.map((b) {
                          final benefit = b['benefits'] as Map?;
                          final category =
                              benefit?['benefit_category'] ?? 'GENERAL';
                          final title = benefit?['title'] ?? 'Benefit';
                          return '$category: $title';
                        }).toList(),
                        isCandidate: false,
                      ),
                    ),
                    const VerticalDivider(color: Color(0xFF1E293B), width: 24),
                    Expanded(
                      flex: 5,
                      child: BenefitCandidateReview(
                        state: reviewState,
                        onChanged: (next) =>
                            setDialogState(() => reviewState = next),
                      ),
                    ),
                  ])),
                  const Divider(color: Color(0xFF1E293B), height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: applying
                            ? null
                            : () async {
                                setDialogState(() => applying = true);
                                final discarded = reviewState.rejectAll();
                                await AdvancedBenefitCalculationService()
                                    .rejectStagedReview(
                                  stagingId,
                                  reviewDecisions: discarded.toStagingJson(),
                                );
                                if (context.mounted)
                                  Navigator.of(context).pop();
                                _onLogReceived(
                                    '❌ REJECTED: Candidate benefits discarded; active mappings unchanged.');
                                _loadCatalogCards();
                              },
                        child: Text('DISCARD CHANGES',
                            style: GoogleFonts.shareTechMono(
                                color: AppTheme.errorColor,
                                fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 16),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.check, size: 14),
                        label: Text(
                            reviewState.hasUnresolved
                                ? 'RESOLVE ALL CANDIDATES'
                                : 'APPLY ACCEPTED BENEFITS',
                            style: GoogleFonts.shareTechMono(
                                fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4)),
                        ),
                        onPressed: applying || reviewState.hasUnresolved
                            ? null
                            : () async {
                                setDialogState(() => applying = true);
                                _onLogReceived(
                                    '⚡ Applying approved benefits from staging...');
                                final applyRes =
                                    await AdvancedBenefitCalculationService()
                                        .applyApprovedBenefits(
                                  stagingId,
                                  reviewDecisions: reviewState.toStagingJson(),
                                );
                                if (applyRes['success'] == true) {
                                  if (context.mounted)
                                    Navigator.of(context).pop();
                                  _onLogReceived(
                                      '✅ SUCCESS: ${applyRes['benefits_mapped'] ?? 0} benefit mappings applied.');
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                          'BENEFITS SYNCED AND APPLIED SUCCESSFULLY',
                                          style: GoogleFonts.shareTechMono(
                                              color: Colors.black,
                                              fontWeight: FontWeight.bold)),
                                      backgroundColor: const Color(0xFF10B981),
                                    ),
                                  );
                                  _loadCatalogCards();
                                } else {
                                  _onLogReceived(
                                      '❌ FAILED: ${applyRes['error']}');
                                  setDialogState(() => applying = false);
                                }
                              },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  Widget _buildReviewColumn({
    required String title,
    required Color headerColor,
    dynamic fees,
    required List<String> benefits,
    required bool isCandidate,
  }) {
    String annualFeeStr = 'N/A';
    String joiningFeeStr = 'N/A';
    String waiverStr = 'None';

    if (fees != null) {
      if (isCandidate) {
        annualFeeStr = fees['renewal']?.toString() ??
            fees['first_year']?.toString() ??
            'Free';
        joiningFeeStr = fees['first_year']?.toString() ?? 'Free';
        waiverStr = fees['waiver_conditions']?.toString() ?? 'None';
      } else {
        annualFeeStr = fees['annual_fee']?.toString() ?? 'Free';
        joiningFeeStr = fees['joining_fee']?.toString() ?? 'Free';
        waiverStr = fees['rewards_summary']?.toString() ?? 'None';
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: GoogleFonts.shareTechMono(
              color: headerColor, fontSize: 11, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
              color: const Color(0xFF050B18),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFF1E293B))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('FEES & CONDITIONS:',
                  style: GoogleFonts.shareTechMono(
                      color: Colors.white30,
                      fontSize: 9,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text('Annual Fee: ₹$annualFeeStr',
                  style: GoogleFonts.shareTechMono(
                      color: Colors.white70, fontSize: 11)),
              Text('Joining Fee: ₹$joiningFeeStr',
                  style: GoogleFonts.shareTechMono(
                      color: Colors.white70, fontSize: 11)),
              const SizedBox(height: 4),
              Text('Waiver: $waiverStr',
                  style: GoogleFonts.shareTechMono(
                      color: Colors.white30, fontSize: 9),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: const Color(0xFF030305),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xFF1E293B))),
            child: benefits.isEmpty
                ? Center(
                    child: Text('NO RECORDED BENEFITS',
                        style: GoogleFonts.shareTechMono(
                            color: Colors.white12, fontSize: 10)))
                : ListView.builder(
                    itemCount: benefits.length,
                    itemBuilder: (context, index) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6.0),
                        child: Text(
                          benefits[index],
                          style: GoogleFonts.shareTechMono(
                              color: Colors.white70, fontSize: 10, height: 1.2),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  List<String> _getCandidateBenefitSummaryList(Map<String, dynamic> data) {
    final list = <String>[];
    if (data['cashback_benefits'] is List) {
      for (final b in data['cashback_benefits']) {
        final cat = b['category'] ?? 'GENERAL';
        final desc = b['description'] ?? 'Cashback';
        final rate = b['rate'] != null ? '${b['rate']}%' : 'Yes';
        list.add('$cat: $desc ($rate)');
      }
    }
    if (data['reward_points'] is Map) {
      final base = data['reward_points']['base_rate'];
      if (base != null) {
        list.add('POINTS: Base rate of $base pts per ₹100');
      }
    }
    if (data['special_benefits'] is List) {
      for (final b in data['special_benefits']) {
        final type = b['type'] ?? 'OTHER';
        final desc = b['description'] ?? '';
        list.add('$type: $desc');
      }
    }
    return list;
  }

  Widget _buildMetricsStrip(
      int total, int flagged, int confirmed, double avgReduction) {
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
              _buildMetricItem(
                  'TOTAL_PROCESSED', total.toString(), Colors.white),
              const SizedBox(width: 20),
              _buildMetricItem('POTENTIAL_LEAKS_⚠️', flagged.toString(),
                  flagged > 0 ? AppTheme.errorColor : Colors.white24),
              const SizedBox(width: 20),
              _buildMetricItem('CONFIRMED_OK_✅', confirmed.toString(),
                  confirmed > 0 ? const Color(0xFF10B981) : Colors.white24),
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
          style: GoogleFonts.shareTechMono(
              color: Colors.white30, fontSize: 9, fontWeight: FontWeight.bold),
        ),
        Text(
          value,
          style: GoogleFonts.shareTechMono(
              color: valueColor, fontSize: 16, fontWeight: FontWeight.bold),
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
                  style: GoogleFonts.shareTechMono(
                      color: Colors.white, fontSize: 12),
                  decoration: InputDecoration(
                    hintText: 'SEARCH BANK/FILE...',
                    hintStyle: GoogleFonts.shareTechMono(
                        color: Colors.white24, fontSize: 11),
                    prefixIcon: const Icon(Icons.search,
                        color: Colors.white24, size: 16),
                    fillColor: const Color(0xFF0B1426),
                    filled: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: const BorderSide(color: Color(0xFF1E293B))),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: const BorderSide(color: Color(0xFF00F5FF))),
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
                    children:
                        ['All', 'Needs PM Review', 'Confirmed'].map((filter) {
                      final isSelected = _statusFilter == filter;
                      Color btnColor =
                          isSelected ? const Color(0xFF00F5FF) : Colors.white24;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6.0),
                        child: InkWell(
                          onTap: () {
                            setState(() {
                              _statusFilter = filter;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFF00F5FF)
                                      .withValues(alpha: 0.1)
                                  : Colors.transparent,
                              border: Border.all(color: btnColor, width: 1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              filter.toUpperCase(),
                              style: GoogleFonts.shareTechMono(
                                color: isSelected
                                    ? const Color(0xFF00F5FF)
                                    : Colors.white54,
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
                        style: GoogleFonts.shareTechMono(
                            color: Colors.white24, fontSize: 11),
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: filteredLogs.length,
                    itemBuilder: (context, idx) {
                      final log = filteredLogs[idx];
                      final isSelected = _selectedLog != null &&
                          _selectedLog!['id'] == log['id'];

                      Color statusColor =
                          const Color(0xFF10B981); // Green for Clean/Confirmed
                      if (log['reviewStatus'] == 'Needs PM Review') {
                        statusColor = AppTheme.errorColor; // Red for Warnings
                      } else if (log['reviewStatus'] == 'Flagged') {
                        statusColor =
                            AppTheme.warningColor; // Amber for PM Flagged
                      }

                      return InkWell(
                        onTap: () => _selectLog(log),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFF00F5FF)
                                    .withValues(alpha: 0.05)
                                : Colors.transparent,
                            border: Border(
                              bottom: const BorderSide(
                                  color: Color(0xFF1E293B), width: 1),
                              left: BorderSide(
                                  color: isSelected
                                      ? const Color(0xFF00F5FF)
                                      : Colors.transparent,
                                  width: 3),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${log['bankName'].toString().toUpperCase()} - ${log['cardVariant'].toString().toUpperCase()}',
                                      style: GoogleFonts.shareTechMono(
                                        color: isSelected
                                            ? const Color(0xFF00F5FF)
                                            : Colors.white
                                                .withValues(alpha: 0.87),
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Text(
                                    '${(log['reductionRatio'] as num).toStringAsFixed(0)}% CUT',
                                    style: GoogleFonts.shareTechMono(
                                      color: const Color(0xFF00F5FF)
                                          .withValues(alpha: 0.7),
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                log['fileName'] ?? 'statement.pdf',
                                style: GoogleFonts.shareTechMono(
                                    color: Colors.white30, fontSize: 9),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 6),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    log['reviewStatus']
                                        .toString()
                                        .toUpperCase(),
                                    style: GoogleFonts.shareTechMono(
                                      color: statusColor,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  if (log['potentialLeaks'] != null &&
                                      (log['potentialLeaks'] as List)
                                          .isNotEmpty)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 4, vertical: 1),
                                      decoration: BoxDecoration(
                                          color: AppTheme.errorColor
                                              .withValues(alpha: 0.2),
                                          borderRadius:
                                              BorderRadius.circular(2)),
                                      child: Row(
                                        children: [
                                          const Icon(
                                              Icons.warning_amber_rounded,
                                              color: AppTheme.errorColor,
                                              size: 8),
                                          const SizedBox(width: 2),
                                          Text(
                                            '${(log['potentialLeaks'] as List).length} LEAKS',
                                            style: GoogleFonts.shareTechMono(
                                                color: AppTheme.errorColor,
                                                fontSize: 8,
                                                fontWeight: FontWeight.bold),
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
                  style: GoogleFonts.shareTechMono(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  'FILE_REF: ${log['fileName']} | TIMESTAMP: ${log['timestamp']}',
                  style: GoogleFonts.shareTechMono(
                      color: Colors.white30, fontSize: 9),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'CUT_MARKER: "${log['cutMarker']}"',
                style: GoogleFonts.shareTechMono(
                    color: const Color(0xFF8B5CF6),
                    fontSize: 9,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 2),
              Text(
                'REDUCTION: ${log['originalLength']} → ${log['prunedLength']} Chars',
                style: GoogleFonts.shareTechMono(
                    color: Colors.white54, fontSize: 9),
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
        border: const Border(
            bottom: BorderSide(color: AppTheme.errorColor, width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded,
                  color: AppTheme.errorColor, size: 16),
              const SizedBox(width: 6),
              Text(
                'WARNING: POTENTIAL TRANSACTION DATA DETECTED IN PRUNED TEXT',
                style: GoogleFonts.shareTechMono(
                    color: AppTheme.errorColor,
                    fontSize: 11,
                    fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ...leaks.map((leak) {
            return Padding(
              padding: const EdgeInsets.only(left: 22, bottom: 4),
              child: RichText(
                text: TextSpan(
                  style: GoogleFonts.shareTechMono(
                      color: Colors.white70, fontSize: 10),
                  children: [
                    TextSpan(
                        text:
                            'Line ${leak['lineNumber']} [${leak['reason']}]: ',
                        style: const TextStyle(color: Colors.white30)),
                    TextSpan(
                        text: '"${leak['lineContent']}"',
                        style: const TextStyle(
                            color: AppTheme.errorColor,
                            fontWeight: FontWeight.bold)),
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
              labelStyle: GoogleFonts.shareTechMono(
                  fontSize: 10, fontWeight: FontWeight.bold),
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
                  alertLines: List<Map<dynamic, dynamic>>.from(
                      log['potentialLeaks'] ?? []),
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
            style: GoogleFonts.shareTechMono(
                color: textColor, fontSize: 11, height: 1.4),
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
            (leak) =>
                leak['lineNumber'] == lineNum ||
                (leak['lineContent'] != null &&
                    leak['lineContent'].toString().trim() == line.trim()),
            orElse: () => {},
          );

          final isAlert = matchingAlert.isNotEmpty;

          return Container(
            color: isAlert
                ? AppTheme.errorColor.withValues(alpha: 0.15)
                : Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 32,
                  child: Text(
                    lineNum.toString().padLeft(3, '0'),
                    style: GoogleFonts.shareTechMono(
                        color: isAlert ? AppTheme.errorColor : Colors.white12,
                        fontSize: 10),
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
                style: GoogleFonts.shareTechMono(
                    color: Colors.white70,
                    fontSize: 10,
                    fontWeight: FontWeight.bold),
              ),
              Row(
                children: [
                  Text(
                    'CURRENT_STATUS: ',
                    style: GoogleFonts.shareTechMono(
                        color: Colors.white30, fontSize: 9),
                  ),
                  Text(
                    log['reviewStatus'].toString().toUpperCase(),
                    style: GoogleFonts.shareTechMono(
                        color: reviewStatusColor,
                        fontSize: 9,
                        fontWeight: FontWeight.bold),
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
                  style: GoogleFonts.shareTechMono(
                      color: Colors.white, fontSize: 11),
                  decoration: InputDecoration(
                    hintText: 'WRITE FEEDBACK / COMPILATION OBSERVATIONS...',
                    hintStyle: GoogleFonts.shareTechMono(
                        color: Colors.white24, fontSize: 11),
                    fillColor: const Color(0xFF050B18),
                    filled: true,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: const BorderSide(color: Color(0xFF1E293B))),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: const BorderSide(color: Color(0xFF00F5FF))),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      minimumSize: const Size(120, 36),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4)),
                    ),
                    child: Text(
                      'CONFIRM RULES',
                      style: GoogleFonts.shareTechMono(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Flag Error Button
                  OutlinedButton(
                    onPressed: () => _updateStatus('Flagged'),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(
                          color: AppTheme.errorColor, width: 1),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      minimumSize: const Size(120, 36),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4)),
                      foregroundColor: AppTheme.errorColor,
                    ),
                    child: Text(
                      'FLAG LEAK / BUG',
                      style: GoogleFonts.shareTechMono(
                          fontSize: 11, fontWeight: FontWeight.bold),
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
      backgroundColor: const Color(0xFF0C152B),
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
                    icon: const Icon(Icons.close,
                        color: Colors.white60, size: 18),
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
                style: GoogleFonts.shareTechMono(
                    color: Colors.white, fontSize: 12),
                decoration: InputDecoration(
                  hintText: 'TYPE SYSTEM RULES OR PARSING FEEDBACK...',
                  hintStyle: GoogleFonts.shareTechMono(
                      color: Colors.white24, fontSize: 11),
                  fillColor: const Color(0xFF0F172A),
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppBorderRadius.sm),
                    borderSide: const BorderSide(color: Color(0xFF1E293B)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppBorderRadius.sm),
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
                      content: Text('FEEDBACK COMMITTED TO WORKSPACE ✅',
                          style: GoogleFonts.shareTechMono(
                              color: Colors.black,
                              fontWeight: FontWeight.bold)),
                      backgroundColor: const Color(0xFF10B981),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00F5FF),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppBorderRadius.sm)),
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
                          style: GoogleFonts.shareTechMono(
                              color: Colors.white12, fontSize: 10),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _feedbacks.length,
                        itemBuilder: (context, idx) {
                          final item = _feedbacks[idx];
                          final date = DateTime.tryParse(item['timestamp']) ??
                              DateTime.now();
                          final dateStr =
                              '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A),
                              borderRadius:
                                  BorderRadius.circular(AppBorderRadius.sm),
                              border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.05)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'ENTRY #${item['id'].toString().substring(item['id'].toString().length.clamp(0, 4))}',
                                      style: GoogleFonts.shareTechMono(
                                          color: const Color(0xFF8B5CF6),
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold),
                                    ),
                                    Text(
                                      dateStr,
                                      style: GoogleFonts.shareTechMono(
                                          color: Colors.white24, fontSize: 9),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  item['feedback'] ?? '',
                                  style: GoogleFonts.shareTechMono(
                                      color: Colors.white70,
                                      fontSize: 11,
                                      height: 1.3),
                                ),
                                const SizedBox(height: 6),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: InkWell(
                                    onTap: () async {
                                      await PmFeedbackService()
                                          .deleteFeedback(item['id']);
                                      await _loadFeedbacks();
                                    },
                                    child: Text(
                                      'DELETE',
                                      style: GoogleFonts.shareTechMono(
                                          color: AppTheme.errorColor,
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold),
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
