import 'package:supabase_flutter/supabase_flutter.dart';

enum CatalogEntryAdminAction { list, approve, reject }

class PendingCatalogEntryRequest {
  const PendingCatalogEntryRequest({
    required this.id,
    required this.sourceUrl,
    required this.bankName,
    required this.cardName,
    required this.requestedBy,
    required this.createdAt,
  });

  final String id;
  final String sourceUrl;
  final String bankName;
  final String cardName;
  final String? requestedBy;
  final String? createdAt;

  factory PendingCatalogEntryRequest.fromJson(Map<String, dynamic> json) {
    return PendingCatalogEntryRequest(
      id: json['id']?.toString() ?? '',
      sourceUrl: json['source_url']?.toString() ?? '',
      bankName: json['bank_name']?.toString() ?? '',
      cardName: json['card_name']?.toString() ?? '',
      requestedBy: json['requested_by']?.toString(),
      createdAt: json['created_at']?.toString(),
    );
  }
}

class CatalogEntryApprovalResult {
  const CatalogEntryApprovalResult({
    required this.success,
    this.cardId,
    this.bankName,
    this.cardName,
    this.sourceUrl,
    this.error,
  });

  final bool success;
  final String? cardId;
  final String? bankName;
  final String? cardName;
  final String? sourceUrl;
  final String? error;
}

class CatalogEntryReviewService {
  CatalogEntryReviewService({
    Future<Map<String, dynamic>> Function(
      CatalogEntryAdminAction action, {
      String? stagingId,
    })? invokeAdminAction,
  }) : _invokeAdminAction = invokeAdminAction ?? _defaultInvokeAdminAction;

  final Future<Map<String, dynamic>> Function(
    CatalogEntryAdminAction action, {
    String? stagingId,
  }) _invokeAdminAction;

  Future<List<PendingCatalogEntryRequest>> listPendingRequests() async {
    final response = await _invokeAdminAction(CatalogEntryAdminAction.list);
    final requests = response['requests'];
    if (requests is! List) {
      return const [];
    }
    return requests
        .whereType<Map>()
        .map((row) => PendingCatalogEntryRequest.fromJson(
              Map<String, dynamic>.from(row),
            ))
        .where((request) => request.id.isNotEmpty)
        .toList();
  }

  Future<CatalogEntryApprovalResult> approveRequest(String stagingId) async {
    final response = await _invokeAdminAction(
      CatalogEntryAdminAction.approve,
      stagingId: stagingId,
    );
    if (response['success'] == true) {
      return CatalogEntryApprovalResult(
        success: true,
        cardId: response['card_id']?.toString(),
        bankName: response['bank_name']?.toString(),
        cardName: response['card_name']?.toString(),
        sourceUrl: response['source_url']?.toString(),
      );
    }
    return CatalogEntryApprovalResult(
      success: false,
      error: response['error']?.toString() ?? 'Approval failed',
    );
  }

  Future<CatalogEntryApprovalResult> rejectRequest(String stagingId) async {
    final response = await _invokeAdminAction(
      CatalogEntryAdminAction.reject,
      stagingId: stagingId,
    );
    if (response['success'] == true) {
      return const CatalogEntryApprovalResult(success: true);
    }
    return CatalogEntryApprovalResult(
      success: false,
      error: response['error']?.toString() ?? 'Rejection failed',
    );
  }

  static Future<Map<String, dynamic>> _defaultInvokeAdminAction(
    CatalogEntryAdminAction action, {
    String? stagingId,
  }) async {
    final response = await Supabase.instance.client.functions.invoke(
      'admin-catalog-entry',
      body: {
        'action': action.name,
        if (stagingId != null) 'staging_id': stagingId,
      },
    );
    if (response.data is Map) {
      return Map<String, dynamic>.from(response.data as Map);
    }
    return {
      'success': false,
      'error': response.data?.toString() ?? 'Unexpected admin response',
    };
  }
}
