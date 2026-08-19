import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../data/admin_operator_repository.dart';
import 'system_models.dart';

typedef SystemRequestIdFactory = String Function();
typedef SystemClock = DateTime Function();

final class SystemRepository {
  SystemRepository(
    this._operator, {
    SystemRequestIdFactory? requestIds,
    SystemClock? now,
  }) : _requestIds = requestIds ?? const Uuid().v4,
       _now = now ?? DateTime.now;
  final AdminOperatorRepository _operator;
  final SystemRequestIdFactory _requestIds;
  final SystemClock _now;

  Future<SystemStatusSnapshot> status() async {
    try {
      final json = await _operator.invoke('system-status');
      _exactResponse(json, const {
        'pipelines',
        'controls',
        'control_source_error',
      });
      return SystemStatusSnapshot(
        pipelines: strictSystemList(
          json['pipelines'],
        ).map((e) => PipelineSummary.fromJson(strictSystemMap(e))).toList(),
        controls: strictSystemList(
          json['controls'],
        ).map((e) => RuntimeControl.fromJson(strictSystemMap(e))).toList(),
        controlSourceError: SystemSourceError.parse(
          json['control_source_error'],
        ),
        refreshedAt: _now().toUtc(),
      );
    } on FormatException {
      throw const AdminRequestFailed('request_failed');
    } on TypeError {
      throw const AdminRequestFailed('request_failed');
    }
  }

  Future<SystemJobsPage> jobs(
    SystemJobFamily family, {
    int page = 1,
    int limit = 25,
    String? status,
  }) async {
    try {
      final json = await _operator.invoke('system-jobs', {
        'family': family.wireValue,
        'page': page,
        'limit': limit,
        'status': ?status,
      });
      _exactResponse(json, const {'items', 'page', 'limit', 'has_more'});
      if (json['page'] is! int ||
          json['limit'] is! int ||
          json['has_more'] is! bool ||
          json['page'] != page ||
          json['limit'] != limit) {
        throw const FormatException('Invalid pagination');
      }
      final items = strictSystemList(
        json['items'],
      ).map((e) => SystemJob.fromJson(strictSystemMap(e))).toList();
      if (items.any((item) => item.family != family)) {
        throw const FormatException('Family mismatch');
      }
      return SystemJobsPage(
        items: items,
        page: page,
        limit: limit,
        hasMore: json['has_more'] as bool,
      );
    } on FormatException {
      throw const AdminRequestFailed('request_failed');
    } on TypeError {
      throw const AdminRequestFailed('request_failed');
    }
  }

  Future<void> mutate(SystemMutation mutation) async {
    final requestId = _requestIds();
    if (!_uuid.hasMatch(requestId)) {
      throw const AdminRequestFailed('invalid_request');
    }
    final (action, body) = _mutationBody(mutation, requestId);
    if (utf8.encode(jsonEncode({'action': action, ...body})).length > 32768) {
      throw const AdminRequestFailed('invalid_request');
    }
    final response = await _operator.invoke(action, body);
    try {
      _exactResponse(response, const {'result'});
      final result = strictSystemMap(response['result']);
      if (mutation case final SystemJobMutation job) {
        _exactResponse(result, const {'job_id', 'resulting_status'});
        final expected = mutation is QuarantineSystemJob
            ? 'quarantined'
            : 'queued';
        if (result['job_id'] != job.targetId ||
            result['resulting_status'] != expected) {
          throw const FormatException('Mismatched job receipt');
        }
      } else {
        final control = RuntimeControl.fromJson(result);
        final requested = mutation as SystemControlMutation;
        if (control.isPaused != (mutation is PauseSystemControl) ||
            control.reason != requested.reason.trim() ||
            !control.updatedAt.isAfter(
              DateTime.parse(requested.observedUpdatedAt),
            )) {
          throw const FormatException('Mismatched control receipt');
        }
      }
    } on FormatException {
      throw const AdminRequestFailed('request_failed');
    } on TypeError {
      throw const AdminRequestFailed('request_failed');
    }
  }

  (String, Map<String, dynamic>) _mutationBody(
    SystemMutation mutation,
    String requestId,
  ) {
    String requireReason(String value) {
      final reason = value.trim();
      if (reason.length < 2 || reason.length > 500) {
        throw const AdminRequestFailed('invalid_request');
      }
      return reason;
    }

    void validVersion(String value) {
      if (value.length > 100 ||
          DateTime.tryParse(value) == null ||
          !value.toLowerCase().contains('t')) {
        throw const AdminRequestFailed('invalid_request');
      }
    }

    if (mutation case final SystemJobMutation job) {
      if (!_uuid.hasMatch(job.targetId) ||
          job.family != SystemJobFamily.benefitEnrichment) {
        throw const AdminRequestFailed('invalid_request');
      }
      validVersion(job.observedUpdatedAt);
      final operation = switch (mutation) {
        RetrySystemJob() => 'retry',
        QuarantineSystemJob() => 'quarantine',
        UnquarantineSystemJob() => 'unquarantine',
      };
      final action = operation == 'retry'
          ? 'system-retry'
          : 'system-quarantine';
      return (
        action,
        {
          'operation': operation,
          'family': job.family.wireValue,
          'target_id': job.targetId,
          'status': job.status,
          'request_id': requestId,
          'observed_updated_at': job.observedUpdatedAt,
          if (mutation case QuarantineSystemJob(:final reason))
            'reason': requireReason(reason),
        },
      );
    }
    final control = mutation as SystemControlMutation;
    validVersion(control.observedUpdatedAt);
    return (
      'system-control',
      {
        'control_key': RuntimeControl.key,
        'is_paused': mutation is PauseSystemControl,
        'request_id': requestId,
        'observed_updated_at': control.observedUpdatedAt,
        'reason': requireReason(control.reason),
      },
    );
  }
}

final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  caseSensitive: false,
);
void _exactResponse(Map<String, dynamic> json, Set<String> keys) {
  if (json.length != keys.length || !json.keys.toSet().containsAll(keys)) {
    throw const FormatException('Invalid response');
  }
}
