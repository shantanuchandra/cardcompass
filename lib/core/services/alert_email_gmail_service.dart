import 'dart:convert';
import 'package:googleapis/gmail/v1.dart' as gmail;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

/// A lightweight Gmail email message carrying only the fields
/// needed for alert-email parsing.
class AlertEmail {
  final String id;
  final String subject;
  final String from;
  final DateTime date;
  final String bodyHtml;
  final String bodyText;

  const AlertEmail({
    required this.id,
    required this.subject,
    required this.from,
    required this.date,
    required this.bodyHtml,
    required this.bodyText,
  });
}

/// Fetches instant transaction-alert emails from bank senders.
///
/// These are the real-time spend/debit/credit notifications banks send
/// within seconds of a transaction — NOT the monthly PDF statements.
/// This service uses the SAME Gmail OAuth access already granted to the
/// existing [EnhancedGmailService] and requires no extra permissions.
class AlertEmailGmailService {
  final GoogleSignInAccount _account;

  // Gmail scopes needed (same as EnhancedGmailService)
  static const List<String> _scopes = [
    'https://www.googleapis.com/auth/gmail.readonly',
  ];

  // Known bank alert email domains (superset of statement domains)
  static const List<String> _alertSenderDomains = [
    // HDFC
    'hdfcbank.com', 'alerts.hdfcbank.com',
    // ICICI
    'icicibank.com', 'alerts.icicibank.com',
    // SBI / SBI Card
    'sbicard.com', 'sbicards.com', 'onlinesbi.com',
    // Axis
    'axisbank.com', 'alerts.axisbank.com',
    // Kotak
    'kotak.com', 'kotakbank.com',
    // IndusInd
    'indusind.com',
    // Amex
    'americanexpress.com',
    // IDFC First
    'idfcfirstbank.com',
    // Yes Bank
    'yesbank.in',
    // RBL
    'rblbank.com',
    // AU Small Finance
    'aubank.in',
    // HSBC
    'hsbc.co.in',
  ];

  // Subject patterns that identify alert emails (NOT statements)
  static const List<String> _alertSubjectKeywords = [
    'transaction alert',
    'spend alert',
    'debit alert',
    'credit alert',
    'transaction notification',
    'spent on your',
    'used at',
    'transaction on card',
    'amount debited',
    'amount credited',
    'purchase alert',
    'card used',
    'card transaction',
    'payment alert',
    'your card ending',
    'txn alert',
    'account debited',
    'account credited',
  ];

  AlertEmailGmailService(this._account);

  /// Build an authenticated Gmail API client using the same auth pattern
  /// as [EnhancedGmailService].
  Future<gmail.GmailApi> _buildGmailApi() async {
    final authz = await _account.authorizationClient.authorizeScopes(_scopes);
    final accessToken = authz.accessToken;
    final client = _AlertAuthClient(
      <String, String>{'Authorization': 'Bearer $accessToken'},
    );
    return gmail.GmailApi(client);
  }

  /// Fetch alert emails received since [since].
  /// Returns at most [maxResults] emails (default 100).
  Future<List<AlertEmail>> fetchAlertEmails({
    required DateTime since,
    int maxResults = 100,
  }) async {
    final gmailApi = await _buildGmailApi();

    final fromPart =
        _alertSenderDomains.map((d) => 'from:$d').join(' OR ');
    final subjectPart =
        _alertSubjectKeywords.map((kw) => 'subject:"$kw"').join(' OR ');

    // epoch seconds for the Gmail after: filter
    final afterSec = since.millisecondsSinceEpoch ~/ 1000;

    // NO has:attachment — we want the plain text/HTML body alerts only
    final query = [
      '-has:attachment',
      '(($fromPart) OR ($subjectPart))',
      '-label:spam',
      'after:$afterSec',
    ].join(' ');

    print('📧 Alert email query: $query');

    final listResponse = await gmailApi.users.messages.list(
      'me',
      q: query,
      maxResults: maxResults,
    );

    if (listResponse.messages == null || listResponse.messages!.isEmpty) {
      print('📭 No alert emails found.');
      return [];
    }

    print('📩 Found ${listResponse.messages!.length} candidate alert emails.');

    final emails = <AlertEmail>[];
    for (final msg in listResponse.messages!) {
      try {
        final full = await gmailApi.users.messages.get(
          'me',
          msg.id!,
          format: 'full',
        );
        final parsed = _parseMessage(full);
        if (parsed != null) emails.add(parsed);
      } catch (e) {
        print('⚠️  Failed to fetch alert email ${msg.id}: $e');
      }
    }

    return emails;
  }

  AlertEmail? _parseMessage(gmail.Message message) {
    String subject = '';
    String from = '';
    DateTime date = DateTime.now();

    final headers = message.payload?.headers ?? [];
    for (final h in headers) {
      switch (h.name?.toLowerCase()) {
        case 'subject':
          subject = h.value ?? '';
          break;
        case 'from':
          from = h.value ?? '';
          break;
        case 'date':
          if (h.value != null) {
            try {
              date = _parseRfc2822Date(h.value!);
            } catch (_) {}
          }
          break;
      }
    }

    final bodyHtml = _extractBody(message.payload, 'text/html');
    final bodyText = _extractBody(message.payload, 'text/plain');

    // Skip if there's no useful body
    if (bodyHtml.isEmpty && bodyText.isEmpty) return null;

    return AlertEmail(
      id: message.id!,
      subject: subject,
      from: from,
      date: date,
      bodyHtml: bodyHtml,
      bodyText: bodyText,
    );
  }

  String _extractBody(gmail.MessagePart? part, String mimeType) {
    if (part == null) return '';

    if (part.mimeType == mimeType && part.body?.data != null) {
      try {
        final bytes = base64Decode(
            part.body!.data!.replaceAll('-', '+').replaceAll('_', '/'));
        return utf8.decode(bytes);
      } catch (_) {}
    }

    if (part.parts != null) {
      for (final child in part.parts!) {
        final result = _extractBody(child, mimeType);
        if (result.isNotEmpty) return result;
      }
    }

    return '';
  }

  DateTime _parseRfc2822Date(String raw) {
    try {
      return DateTime.parse(raw);
    } catch (_) {
      // Strip timezone abbreviation and try again
      final cleaned =
          raw.replaceAll(RegExp(r'\s+\([A-Z]+\)\s*$'), '').trim();
      return DateTime.parse(cleaned);
    }
  }
}

/// Minimal HTTP client that injects the Bearer token header.
class _AlertAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _inner = http.Client();

  _AlertAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _inner.send(request);
  }
}
