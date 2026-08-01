import 'package:googleapis/gmail/v1.dart' as gmail;
import 'package:http/http.dart' as http;

/// One matching email found by [GmailSyncService.searchStatementEmails].
/// Deliberately lightweight — no attachment bytes, no body content.
class GmailSearchResult {
  final String messageId;
  final String subject;
  final String from;
  final DateTime receivedDate;
  final bool hasAttachment;

  const GmailSearchResult({
    required this.messageId,
    required this.subject,
    required this.from,
    required this.receivedDate,
    required this.hasAttachment,
  });
}

/// Thrown when the Gmail API rejects the request due to an expired or
/// insufficiently-scoped access token (HTTP 401/403).
class GmailAuthException implements Exception {
  final String message;
  const GmailAuthException(this.message);
  @override
  String toString() => message;
}

/// Authenticated HTTP client that attaches a bearer token to every request.
/// The Gmail API client needs an [http.Client], not a raw token string.
class _BearerTokenClient extends http.BaseClient {
  final String _accessToken;
  final http.Client _inner = http.Client();

  _BearerTokenClient(this._accessToken);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Authorization'] = 'Bearer $_accessToken';
    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}

/// Searches Gmail for likely credit-card-statement emails using a Google
/// OAuth access token obtained elsewhere (this class does not perform
/// sign-in itself).
class GmailSyncService {
  final String _accessToken;
  late final gmail.GmailApi _api;
  late final _BearerTokenClient _client;

  GmailSyncService(this._accessToken) {
    _client = _BearerTokenClient(_accessToken);
    _api = gmail.GmailApi(_client);
  }

  /// Searches for likely credit-card-statement emails. Ported from
  /// enhanced_gmail_service.dart's searchStatements query construction
  /// (main branch), narrowed to PDF attachments and statement-like subjects.
  ///
  /// [after] optionally restricts results to messages received on or after
  /// that date (useful for paging through history beyond Gmail's 50-result
  /// cap per call).
  Future<List<GmailSearchResult>> searchStatementEmails({
    DateTime? after,
  }) async {
    var query = 'has:attachment filename:pdf';
    const subjectKeywords = [
      'credit card statement',
      'card statement',
      'credit card',
    ];
    final subjectPart =
        subjectKeywords.map((k) => 'subject:"$k"').join(' OR ');
    query += ' ($subjectPart)';
    if (after != null) {
      query += ' after:${after.year}/${after.month}/${after.day}';
    }

    try {
      final listResponse = await _api.users.messages.list(
        'me',
        q: query,
        maxResults: 50,
      );

      final messages = listResponse.messages;
      if (messages == null || messages.isEmpty) return [];

      final results = <GmailSearchResult>[];
      for (final message in messages) {
        final id = message.id;
        if (id == null) continue;
        final full = await _api.users.messages.get('me', id);
        final parsed = _parseMessage(id, full);
        if (parsed != null) results.add(parsed);
      }
      return results;
    } on gmail.DetailedApiRequestError catch (e) {
      if (e.status == 401 || e.status == 403) {
        throw GmailAuthException(
          'Gmail access expired or was denied (HTTP ${e.status}). '
          'Please sign out and sign back in.',
        );
      }
      rethrow;
    }
  }

  GmailSearchResult? _parseMessage(String id, gmail.Message message) {
    final headers = message.payload?.headers;
    if (headers == null) return null;

    String? headerValue(String name) {
      for (final h in headers) {
        if (h.name?.toLowerCase() == name.toLowerCase()) return h.value;
      }
      return null;
    }

    final subject = headerValue('Subject') ?? '(no subject)';
    final from = headerValue('From') ?? '(unknown sender)';
    final dateHeader = headerValue('Date');
    final receivedDate = dateHeader != null
        ? (DateTime.tryParse(dateHeader) ?? _fromInternalDate(message))
        : _fromInternalDate(message);

    final hasAttachment = _hasPdfAttachment(message.payload?.parts);

    return GmailSearchResult(
      messageId: id,
      subject: subject,
      from: from,
      receivedDate: receivedDate,
      hasAttachment: hasAttachment,
    );
  }

  DateTime _fromInternalDate(gmail.Message message) {
    final internal = message.internalDate;
    if (internal == null) return DateTime.now();
    final millis = int.tryParse(internal);
    return millis != null
        ? DateTime.fromMillisecondsSinceEpoch(millis)
        : DateTime.now();
  }

  bool _hasPdfAttachment(List<gmail.MessagePart>? parts) {
    if (parts == null) return false;
    for (final part in parts) {
      if (part.filename != null &&
          part.filename!.isNotEmpty &&
          part.filename!.toLowerCase().endsWith('.pdf')) {
        return true;
      }
      if (_hasPdfAttachment(part.parts)) return true;
    }
    return false;
  }

  void dispose() {
    _client.close();
  }
}
