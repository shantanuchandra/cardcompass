import 'dart:convert';

import 'package:cardcompass/core/services/gmail_sync_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis/gmail/v1.dart' as gmail;

gmail.MessagePart _pdfPart(String filename, {String? attachmentId}) {
  return gmail.MessagePart(
    mimeType: 'application/pdf',
    filename: filename,
    body: gmail.MessagePartBody(attachmentId: attachmentId ?? filename),
  );
}

void main() {
  final service = GmailSyncService('fake-token');

  test('searchStatementEmails follows every Gmail result page', () async {
    final requestedTokens = <String?>[];
    final pagedService = GmailSyncService(
      'fake-token',
      listMessages: ({required query, pageToken}) async {
        requestedTokens.add(pageToken);
        return pageToken == null
            ? gmail.ListMessagesResponse(
                messages: [gmail.Message(id: 'message-1')],
                nextPageToken: 'page-2',
              )
            : gmail.ListMessagesResponse(
                messages: [gmail.Message(id: 'message-2')],
              );
      },
      getMessage: (id) async => gmail.Message(
        id: id,
        internalDate: '1786780800000',
        payload: gmail.MessagePart(
          headers: [
            gmail.MessagePartHeader(name: 'Subject', value: 'Card statement'),
            gmail.MessagePartHeader(name: 'From', value: 'bank@example.com'),
          ],
          parts: [_pdfPart('$id.pdf', attachmentId: 'attachment-$id')],
        ),
      ),
    );

    final results = await pagedService.searchStatementEmails();

    expect(requestedTokens, [null, 'page-2']);
    expect(results.map((result) => result.messageId), [
      'message-1',
      'message-2',
    ]);
    pagedService.dispose();
  });

  group('GmailSyncService.findPdfAttachment', () {
    test(
      'prefers the real statement PDF over an accompanying Terms & Conditions PDF',
      () {
        // Mirrors the actual MIME structure of an HSBC TravelOne statement
        // email: multipart/mixed with the T&C PDF ordered before the real,
        // password-protected statement PDF.
        final htmlBody = gmail.MessagePart(mimeType: 'text/html', filename: '');
        final termsAndConditions = _pdfPart(
          'Most Important Terms & Conditions.pdf',
        );
        final statement = _pdfPart('20260805.pdf');

        final result = service.findPdfAttachment([
          htmlBody,
          termsAndConditions,
          statement,
        ]);

        expect(result.found, true);
        expect(result.filename, '20260805.pdf');
        expect(result.attachmentId, '20260805.pdf');
      },
    );

    test('returns the only PDF attachment when just one is present', () {
      final htmlBody = gmail.MessagePart(mimeType: 'text/html', filename: '');
      final statement = _pdfPart(
        '4315XXXXXXXX6006_140741_Retail_Amazon_NORM.pdf',
      );

      final result = service.findPdfAttachment([htmlBody, statement]);

      expect(result.found, true);
      expect(result.filename, '4315XXXXXXXX6006_140741_Retail_Amazon_NORM.pdf');
    });

    test('returns not found when there is no PDF attachment', () {
      final htmlBody = gmail.MessagePart(mimeType: 'text/html', filename: '');

      final result = service.findPdfAttachment([htmlBody]);

      expect(result.found, false);
      expect(result.attachmentId, null);
      expect(result.filename, null);
    });

    test(
      'falls back to the first PDF when every candidate looks like an ancillary document',
      () {
        final termsAndConditions = _pdfPart('Terms and Conditions.pdf');
        final disclosure = _pdfPart('Key Fact Disclosure.pdf');

        final result = service.findPdfAttachment([
          termsAndConditions,
          disclosure,
        ]);

        expect(result.found, true);
        expect(result.filename, 'Terms and Conditions.pdf');
      },
    );

    test('finds a PDF nested inside a sub-container part', () {
      final statement = _pdfPart('statement.pdf');
      final container = gmail.MessagePart(
        mimeType: 'multipart/related',
        parts: [statement],
      );

      final result = service.findPdfAttachment([container]);

      expect(result.found, true);
      expect(result.filename, 'statement.pdf');
    });
  });

  group('GmailSyncService.loadMessageBodyText', () {
    test(
      'prefers the plain-text body and does not include attachments',
      () async {
        final bodyService = GmailSyncService(
          'fake-token',
          getMessage: (_) async => gmail.Message(
            payload: gmail.MessagePart(
              mimeType: 'multipart/mixed',
              parts: [
                gmail.MessagePart(
                  mimeType: 'text/html',
                  body: gmail.MessagePartBody(
                    data: base64Url.encode(utf8.encode('<p>HTML fallback</p>')),
                  ),
                ),
                gmail.MessagePart(
                  mimeType: 'text/plain',
                  body: gmail.MessagePartBody(
                    data: base64Url.encode(
                      utf8.encode(
                        'Use the first four letters of your name followed by DDMM.',
                      ),
                    ),
                  ),
                ),
                gmail.MessagePart(
                  mimeType: 'application/pdf',
                  filename: 'statement.pdf',
                  body: gmail.MessagePartBody(
                    data: base64Url.encode(utf8.encode('private PDF bytes')),
                  ),
                ),
              ],
            ),
          ),
        );

        final body = await bodyService.loadMessageBodyText('message-1');

        expect(
          body,
          'Use the first four letters of your name followed by DDMM.',
        );
        expect(body, isNot(contains('private PDF bytes')));
        bodyService.dispose();
      },
    );

    test('converts an HTML-only body into readable text', () async {
      final bodyService = GmailSyncService(
        'fake-token',
        getMessage: (_) async => gmail.Message(
          payload: gmail.MessagePart(
            mimeType: 'text/html',
            body: gmail.MessagePartBody(
              data: base64Url.encode(
                utf8.encode(
                  '<p>Your password is the first 4 letters of your name</p>'
                  '<p>followed by your DOB in DDMM format.</p>',
                ),
              ),
            ),
          ),
        ),
      );

      final body = await bodyService.loadMessageBodyText('message-2');

      expect(
        body,
        'Your password is the first 4 letters of your name '
        'followed by your DOB in DDMM format.',
      );
      bodyService.dispose();
    });
  });
}
