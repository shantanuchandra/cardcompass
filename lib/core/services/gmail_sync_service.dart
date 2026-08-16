import 'dart:convert';
import 'dart:typed_data';
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
  final String? attachmentId;
  final String? attachmentFilename;

  const GmailSearchResult({
    required this.messageId,
    required this.subject,
    required this.from,
    required this.receivedDate,
    required this.hasAttachment,
    this.attachmentId,
    this.attachmentFilename,
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

typedef GmailMessagePageLoader =
    Future<gmail.ListMessagesResponse> Function({
      required String query,
      String? pageToken,
    });
typedef GmailMessageLoader = Future<gmail.Message> Function(String messageId);

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
  late final gmail.GmailApi _api;
  late final _BearerTokenClient _client;
  final GmailMessagePageLoader? _listMessages;
  final GmailMessageLoader? _getMessage;

  GmailSyncService(
    String accessToken, {
    GmailMessagePageLoader? listMessages,
    GmailMessageLoader? getMessage,
  }) : _listMessages = listMessages,
       _getMessage = getMessage {
    _client = _BearerTokenClient(accessToken);
    _api = gmail.GmailApi(_client);
  }

  Future<gmail.ListMessagesResponse> _loadMessagePage({
    required String query,
    String? pageToken,
  }) {
    final loader = _listMessages;
    if (loader != null) {
      return loader(query: query, pageToken: pageToken);
    }
    return _api.users.messages.list(
      'me',
      q: query,
      maxResults: 50,
      pageToken: pageToken,
    );
  }

  Future<gmail.Message> _loadMessage(String messageId) {
    final loader = _getMessage;
    return loader != null
        ? loader(messageId)
        : _api.users.messages.get('me', messageId);
  }

  /// Loads the readable message body for transient password-hint detection.
  /// The caller must not persist this value. Plain text is preferred over
  /// HTML and attachment payloads are deliberately ignored.
  Future<String> loadMessageBodyText(String messageId) async {
    final message = await _loadMessage(messageId);
    return extractReadableBodyText(message.payload);
  }

  String extractReadableBodyText(gmail.MessagePart? payload) {
    if (payload == null) return '';

    final plainParts = <String>[];
    final htmlParts = <String>[];

    void collect(gmail.MessagePart part) {
      final mimeType = part.mimeType?.toLowerCase();
      final isInlineText = part.filename == null || part.filename!.isEmpty;
      final encoded = part.body?.data;
      if (isInlineText && encoded != null && encoded.isNotEmpty) {
        final decoded = _decodeBodyData(encoded);
        if (decoded.isNotEmpty) {
          if (mimeType == 'text/plain') {
            plainParts.add(decoded);
          } else if (mimeType == 'text/html') {
            htmlParts.add(_htmlToText(decoded));
          }
        }
      }
      for (final child in part.parts ?? const <gmail.MessagePart>[]) {
        collect(child);
      }
    }

    collect(payload);
    final selected = plainParts.isNotEmpty ? plainParts : htmlParts;
    return selected.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _decodeBodyData(String encoded) {
    try {
      final bytes = base64Url.decode(base64Url.normalize(encoded));
      return utf8.decode(bytes, allowMalformed: true);
    } on FormatException {
      return '';
    }
  }

  String _htmlToText(String html) {
    var text = html
        .replaceAll(
          RegExp(r'<(?:br\s*/?|/p|/div|/li)>', caseSensitive: false),
          ' ',
        )
        .replaceAll(RegExp(r'<[^>]+>'), ' ');
    const entities = {
      '&nbsp;': ' ',
      '&amp;': '&',
      '&lt;': '<',
      '&gt;': '>',
      '&quot;': '"',
      '&#39;': "'",
      '&apos;': "'",
    };
    for (final entry in entities.entries) {
      text = text.replaceAll(entry.key, entry.value);
    }
    return text;
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
    final subjectPart = subjectKeywords.map((k) => 'subject:"$k"').join(' OR ');
    query += ' ($subjectPart)';
    if (after != null) {
      query += ' after:${after.year}/${after.month}/${after.day}';
    }

    try {
      final results = <GmailSearchResult>[];
      final seenPageTokens = <String>{};
      String? pageToken;
      do {
        final listResponse = await _loadMessagePage(
          query: query,
          pageToken: pageToken,
        );
        for (final message
            in listResponse.messages ?? const <gmail.Message>[]) {
          final id = message.id;
          if (id == null) continue;
          final full = await _loadMessage(id);
          final parsed = _parseMessage(id, full);
          if (parsed != null) results.add(parsed);
        }

        final nextPageToken = listResponse.nextPageToken;
        if (nextPageToken == null || nextPageToken.isEmpty) break;
        if (!seenPageTokens.add(nextPageToken)) break;
        pageToken = nextPageToken;
      } while (true);

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

    final attachment = findPdfAttachment(message.payload?.parts);

    return GmailSearchResult(
      messageId: id,
      subject: subject,
      from: from,
      receivedDate: receivedDate,
      hasAttachment: attachment.found,
      attachmentId: attachment.attachmentId,
      attachmentFilename: attachment.filename,
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

  /// Filename substrings (case-insensitive) that mark a PDF as an ancillary
  /// document rather than the statement itself — e.g. HSBC attaches both
  /// "Most Important Terms & Conditions.pdf" and the real, password-protected
  /// statement PDF to the same email.
  static const _ancillaryDocumentKeywords = [
    'terms',
    'condition',
    'mitc',
    'disclosure',
  ];

  /// Picks which PDF attachment on an email is the actual statement, when a
  /// message carries more than one (see [_ancillaryDocumentKeywords] above).
  /// With zero or one PDF candidate there's nothing to disambiguate, so this
  /// matches every bank's email format that attaches just the statement.
  ({bool found, String? attachmentId, String? filename}) findPdfAttachment(
    List<gmail.MessagePart>? parts,
  ) {
    final candidates = _collectPdfAttachments(parts);
    if (candidates.isEmpty) {
      return (found: false, attachmentId: null, filename: null);
    }
    if (candidates.length == 1) {
      final only = candidates.first;
      return (
        found: true,
        attachmentId: only.body?.attachmentId,
        filename: only.filename,
      );
    }

    final likelyStatements = candidates.where((part) {
      final name = part.filename!.toLowerCase();
      return !_ancillaryDocumentKeywords.any(name.contains);
    }).toList();

    final chosen = likelyStatements.length == 1
        ? likelyStatements.first
        : candidates.first;
    return (
      found: true,
      attachmentId: chosen.body?.attachmentId,
      filename: chosen.filename,
    );
  }

  /// Recursively gathers every PDF attachment part under [parts], however
  /// deeply nested (e.g. inside a `multipart/related` sub-container).
  List<gmail.MessagePart> _collectPdfAttachments(
    List<gmail.MessagePart>? parts,
  ) {
    if (parts == null) return [];
    final found = <gmail.MessagePart>[];
    for (final part in parts) {
      if (part.filename != null &&
          part.filename!.isNotEmpty &&
          part.filename!.toLowerCase().endsWith('.pdf')) {
        found.add(part);
      }
      found.addAll(_collectPdfAttachments(part.parts));
    }
    return found;
  }

  /// Downloads and base64url-decodes a Gmail attachment's raw bytes.
  Future<Uint8List> downloadAttachment(
    String messageId,
    String attachmentId,
  ) async {
    final attachment = await _api.users.messages.attachments.get(
      'me',
      messageId,
      attachmentId,
    );

    if (attachment.data == null) {
      throw Exception('No attachment data found');
    }

    return base64Url.decode(base64Url.normalize(attachment.data!));
  }

  void dispose() {
    _client.close();
  }
}
