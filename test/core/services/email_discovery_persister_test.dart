import 'package:cardcompass/core/repositories/email_repository_interface.dart';
import 'package:cardcompass/core/services/email_discovery_persister.dart';
import 'package:cardcompass/core/services/gmail_sync_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeEmailRepository implements EmailRepositoryInterface {
  _FakeEmailRepository(this.rows);

  final Map<String, Map<String, dynamic>> rows;

  @override
  Future<Map<String, dynamic>?> getEmailById({
    required String userId,
    required String emailId,
  }) async => rows[emailId];

  @override
  Future<void> updateEmailMetadata({
    required String userId,
    required String emailId,
    required Map<String, dynamic> metadata,
  }) async {
    rows[emailId] = {...rows[emailId]!, 'metadata': metadata};
  }

  @override
  Future<String> storeEmail({
    required String userId,
    required String emailId,
    required String subject,
    required String sender,
    required DateTime receivedDate,
    required bool hasAttachments,
    String? bankDetected,
    Map<String, dynamic>? metadata,
  }) async {
    rows[emailId] = {'metadata': metadata ?? <String, dynamic>{}};
    return emailId;
  }

  @override
  Future<bool> emailExists(String userId, String emailId) async =>
      rows.containsKey(emailId);

  @override
  Future<List<Map<String, dynamic>>> getUnprocessedEmails(
    String userId,
  ) async => rows.values.toList();

  @override
  Future<void> updateEmailStatus({
    required String userId,
    required String emailId,
    required bool processed,
    String? statementId,
    String? bankDetected,
  }) async {}
}

void main() {
  test('rediscovered email repairs missing attachment metadata', () async {
    final repo = _FakeEmailRepository({
      'message-1': {
        'metadata': <String, dynamic>{
          'legacy': true,
          'attachmentFilename': 'original-statement.pdf',
        },
      },
    });
    final result = await EmailDiscoveryPersister(repo).persist(
      userId: 'user-1',
      results: [
        GmailSearchResult(
          messageId: 'message-1',
          subject: 'Credit card statement',
          from: 'bank@example.com',
          receivedDate: DateTime(2026, 8, 1),
          hasAttachment: true,
          attachmentId: 'attachment-1',
          attachmentFilename: 'statement.pdf',
        ),
      ],
    );

    expect(result.repairedCount, 1);
    expect(result.newlyStoredCount, 0);
    expect(result.skippedCount, 0);
    expect(repo.rows['message-1']!['metadata'], {
      'legacy': true,
      'attachmentId': 'attachment-1',
      'attachmentFilename': 'original-statement.pdf',
    });
  });
}
