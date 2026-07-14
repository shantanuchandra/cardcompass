import 'package:cardcompass/core/services/advanced_benefit_calculation_service.dart';
import 'package:cardcompass/core/services/catalog_entry_review_service.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class CatalogEntryRequestsPanel extends StatefulWidget {
  const CatalogEntryRequestsPanel({
    super.key,
    required this.onLog,
    this.reviewService,
    this.benefitService,
  });

  final void Function(String message) onLog;
  final CatalogEntryReviewService? reviewService;
  final AdvancedBenefitCalculationService? benefitService;

  @override
  State<CatalogEntryRequestsPanel> createState() =>
      _CatalogEntryRequestsPanelState();
}

class _CatalogEntryRequestsPanelState extends State<CatalogEntryRequestsPanel> {
  late final CatalogEntryReviewService _reviewService =
      widget.reviewService ?? CatalogEntryReviewService();
  late final AdvancedBenefitCalculationService _benefitService =
      widget.benefitService ?? AdvancedBenefitCalculationService();

  List<PendingCatalogEntryRequest> _requests = [];
  bool _isLoading = false;
  String? _processingId;

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    setState(() => _isLoading = true);
    try {
      final requests = await _reviewService.listPendingRequests();
      if (!mounted) return;
      setState(() => _requests = requests);
      widget.onLog('Loaded ${requests.length} pending catalog request(s).');
    } catch (error) {
      widget.onLog('Failed to load catalog requests: $error');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _approve(PendingCatalogEntryRequest request) async {
    setState(() => _processingId = request.id);
    widget.onLog(
      'Approving catalog entry: ${request.bankName} ${request.cardName}',
    );
    try {
      final approval = await _reviewService.approveRequest(request.id);
      if (!approval.success || approval.cardId == null) {
        widget.onLog(
          'Approval failed: ${approval.error ?? 'unknown error'}',
        );
        return;
      }

      widget.onLog(
        'Catalog row created/linked (${approval.cardId}). Starting benefit extraction...',
      );

      final extraction = await _benefitService.extractAndUpdateBenefits(
        cardId: approval.cardId!,
        cardName: approval.cardName ?? request.cardName,
        bankName: approval.bankName ?? request.bankName,
        customUrl: approval.sourceUrl ?? request.sourceUrl,
      );

      if (extraction['success'] == true) {
        widget.onLog(
          'Benefit extraction staged for review: ${approval.cardName ?? request.cardName}',
        );
      } else {
        widget.onLog(
          'Catalog approved, but benefit extraction failed: ${extraction['error'] ?? extraction['validation_reasons'] ?? 'unknown error'}',
        );
      }

      await _loadRequests();
    } catch (error) {
      widget.onLog('Approval error: $error');
    } finally {
      if (mounted) {
        setState(() => _processingId = null);
      }
    }
  }

  Future<void> _reject(PendingCatalogEntryRequest request) async {
    setState(() => _processingId = request.id);
    widget.onLog(
      'Rejecting catalog entry: ${request.bankName} ${request.cardName}',
    );
    try {
      final result = await _reviewService.rejectRequest(request.id);
      if (result.success) {
        widget.onLog('Catalog request rejected.');
        await _loadRequests();
      } else {
        widget.onLog('Rejection failed: ${result.error ?? 'unknown error'}');
      }
    } catch (error) {
      widget.onLog('Rejection error: $error');
    } finally {
      if (mounted) {
        setState(() => _processingId = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 2,
          child: _buildRequestList(),
        ),
        Expanded(
          child: _buildLogHintPanel(),
        ),
      ],
    );
  }

  Widget _buildRequestList() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF070E1A),
        border: Border(right: BorderSide(color: Color(0xFF1E293B), width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'PENDING NEW-CARD REQUESTS',
                    style: GoogleFonts.shareTechMono(
                      color: const Color(0xFF00F5FF),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _isLoading ? null : _loadRequests,
                  icon: const Icon(Icons.refresh, size: 14, color: Colors.white54),
                  label: Text(
                    'REFRESH',
                    style: GoogleFonts.shareTechMono(
                      color: Colors.white54,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: Color(0xFF1E293B), height: 1),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF00F5FF)),
                  )
                : _requests.isEmpty
                    ? Center(
                        child: Text(
                          'NO PENDING CATALOG REQUESTS.',
                          style: GoogleFonts.shareTechMono(
                            color: Colors.white24,
                            fontSize: 11,
                          ),
                        ),
                      )
                    : ListView.separated(
                        itemCount: _requests.length,
                        separatorBuilder: (_, __) =>
                            const Divider(color: Color(0xFF1E293B), height: 1),
                        itemBuilder: (context, index) {
                          final request = _requests[index];
                          final isProcessing = _processingId == request.id;
                          return ListTile(
                            title: Text(
                              '${request.bankName} — ${request.cardName}',
                              style: GoogleFonts.shareTechMono(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Text(
                                  request.sourceUrl,
                                  style: GoogleFonts.shareTechMono(
                                    color: Colors.white38,
                                    fontSize: 10,
                                  ),
                                ),
                                if (request.createdAt != null)
                                  Text(
                                    'Requested ${request.createdAt}',
                                    style: GoogleFonts.shareTechMono(
                                      color: Colors.white24,
                                      fontSize: 10,
                                    ),
                                  ),
                              ],
                            ),
                            trailing: isProcessing
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Color(0xFF00F5FF),
                                    ),
                                  )
                                : Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      TextButton(
                                        onPressed: () => _reject(request),
                                        child: Text(
                                          'REJECT',
                                          style: GoogleFonts.shareTechMono(
                                            color: Colors.redAccent,
                                            fontSize: 10,
                                          ),
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: () => _approve(request),
                                        child: Text(
                                          'APPROVE',
                                          style: GoogleFonts.shareTechMono(
                                            color: const Color(0xFF00F5FF),
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
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
    );
  }

  Widget _buildLogHintPanel() {
    return Container(
      color: const Color(0xFF0C152B),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'CATALOG ENTRY WORKFLOW',
            style: GoogleFonts.shareTechMono(
              color: const Color(0xFF00F5FF),
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Users queue unmatched cards during statement sync. Approving creates the card_catalog row and immediately runs benefit extraction into staging for the Card Benefits Refresh tab.',
            style: GoogleFonts.shareTechMono(
              color: Colors.white54,
              fontSize: 11,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Watch the extraction log on the Card Benefits Refresh tab after approval.',
            style: GoogleFonts.shareTechMono(
              color: Colors.white24,
              fontSize: 10,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
