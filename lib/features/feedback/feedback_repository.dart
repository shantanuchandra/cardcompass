import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'feedback_models.dart';

class FeedbackApiResponse {
  const FeedbackApiResponse(this.status, this.data);
  final int status;
  final Object? data;
}

abstract interface class FeedbackApi {
  Future<FeedbackApiResponse> invoke(Map<String, Object?> body);
}

class SupabaseFeedbackApi implements FeedbackApi {
  const SupabaseFeedbackApi(this._client);
  final SupabaseClient _client;

  @override
  Future<FeedbackApiResponse> invoke(Map<String, Object?> body) async {
    final response = await _client.functions.invoke(
      'feedback-submit',
      body: body,
    );
    return FeedbackApiResponse(response.status, response.data);
  }
}

class FeedbackInvalidRequest implements Exception {}

class FeedbackFailed implements Exception {
  const FeedbackFailed(this.code);
  final String code;
}

class FeedbackRepository {
  FeedbackRepository(this._api, {this.requestIds});

  final FeedbackApi _api;
  final Iterator<String>? requestIds;
  static final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  String _nextRequestId() {
    final ids = requestIds;
    if (ids == null) return const Uuid().v4();
    if (!ids.moveNext()) throw StateError('Request ID source exhausted');
    return ids.current;
  }

  FeedbackSubmission newSubmission(FeedbackTarget target, String text) =>
      FeedbackSubmission(
        target: target,
        text: text,
        requestId: _nextRequestId(),
      );

  Future<FeedbackSubmitResult> submit(FeedbackSubmission submission) async {
    final text = submission.text.trim();
    if (text.length < 10 ||
        text.length > 2000 ||
        !_uuid.hasMatch(submission.target.outputRefId) ||
        !_uuid.hasMatch(submission.requestId)) {
      throw FeedbackInvalidRequest();
    }
    final body = <String, Object?>{
      'action': 'feedback-submit',
      'feature_key': submission.target.featureKey,
      'output_ref_type': submission.target.outputRefType,
      'output_ref_id': submission.target.outputRefId,
      'feedback_text': text,
      'request_id': submission.requestId,
    };
    _ensureBounded(body);
    final response = await _invoke(body);
    final data = _strictMap(response.data);
    if (response.status != 202) throw FeedbackFailed(_safeCode(data));
    if (data.keys.length != 2 ||
        data['feedback_id'] is! String ||
        !_uuid.hasMatch(data['feedback_id']! as String) ||
        data['triage_status'] != 'awaiting_triage') {
      throw const FeedbackFailed('request_failed');
    }
    return FeedbackSubmitResult(
      data['feedback_id']! as String,
      data['triage_status']! as String,
    );
  }

  Future<RecommendationFeedbackTarget> createRecommendationTarget(
    RecommendationTraceInput input,
  ) async {
    final requestId = _nextRequestId();
    if (!_uuid.hasMatch(requestId)) throw FeedbackInvalidRequest();
    final body = <String, Object?>{
      'action': 'trace-create',
      'feature_key': 'recommendation',
      'safe_input_context': input.safeInputContext,
      'output_snapshot': input.outputSnapshot,
      'card_ids': input.cardIds,
      'benefit_ids': input.benefitIds,
      'engine_version': input.engineVersion,
      'request_id': requestId,
    };
    _ensureBounded(body);
    final response = await _invoke(body);
    final data = _strictMap(response.data);
    if (response.status != 201) throw FeedbackFailed(_safeCode(data));
    if (data.keys.length != 2 ||
        data['trace_id'] is! String ||
        !_uuid.hasMatch(data['trace_id']! as String) ||
        data['expires_at'] is! String ||
        DateTime.tryParse(data['expires_at']! as String) == null) {
      throw const FeedbackFailed('request_failed');
    }
    return RecommendationFeedbackTarget(data['trace_id']! as String);
  }

  Future<FeedbackApiResponse> _invoke(Map<String, Object?> body) async {
    try {
      return await _api.invoke(body);
    } catch (_) {
      throw const FeedbackFailed('request_failed');
    }
  }

  Map<String, Object?> _strictMap(Object? value) {
    if (value is! Map) throw const FeedbackFailed('request_failed');
    try {
      return Map<String, Object?>.from(value);
    } catch (_) {
      throw const FeedbackFailed('request_failed');
    }
  }

  String _safeCode(Map<String, Object?> data) {
    final value = data['error'];
    const safe = {
      'invalid_request',
      'authentication_required',
      'account_inactive',
      'profile_unavailable',
      'not_found',
      'request_id_collision',
      'request_failed',
    };
    return value is String && safe.contains(value) ? value : 'request_failed';
  }

  void _ensureBounded(Map<String, Object?> body) {
    if (utf8.encode(jsonEncode(body)).length > 32768) {
      throw FeedbackInvalidRequest();
    }
  }
}

class FeedbackRepositoryScope extends InheritedWidget {
  const FeedbackRepositoryScope({
    super.key,
    required this.repository,
    required super.child,
  }) : repositoryFactory = null;

  const FeedbackRepositoryScope.lazy({
    super.key,
    required this.repositoryFactory,
    required super.child,
  }) : repository = null;

  final FeedbackRepository? repository;
  final FeedbackRepository Function()? repositoryFactory;

  static FeedbackRepository of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<FeedbackRepositoryScope>();
    assert(scope != null, 'FeedbackRepositoryScope is missing');
    return scope!.repository ?? scope.repositoryFactory!();
  }

  @override
  bool updateShouldNotify(FeedbackRepositoryScope oldWidget) =>
      repository != oldWidget.repository ||
      repositoryFactory != oldWidget.repositoryFactory;
}
