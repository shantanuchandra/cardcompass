# Gmail Sync Fetch-and-List Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a manual "Sync Gmail" button on the Dashboard that searches the
user's inbox for likely credit-card-statement emails and records their
metadata (subject, sender, date, has-attachment) in Supabase's `emails` table.

**Architecture:** A slim `GmailSyncService` authenticates against the Gmail API
using the Google access token Supabase already captured at login
(`session.providerToken`), runs a ported search query, and returns lightweight
result objects. A ported `EmailRepository` (copied verbatim from the `main`
branch checkout at `/Users/shantanuchandra/Downloads/Personal/cardcompass`)
persists new emails, skipping ones already stored. A Riverpod
`AsyncNotifier` orchestrates the two and exposes loading/success/error state
to a new Dashboard button.

**Tech Stack:** Flutter web, `googleapis` (gmail/v1), `supabase_flutter`,
`flutter_riverpod`.

---

## Task 1: Add the `googleapis` dependency

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: Add the dependency**

Open `pubspec.yaml` and add this line inside the `dependencies:` section
(alphabetical position, next to other packages — check the file first to see
where `google_sign_in:` or `google_fonts:` sits and add near there):

```yaml
  googleapis: ^16.0.0
```

- [ ] **Step 2: Fetch packages**

Run: `cd /Users/shantanuchandra/Downloads/Personal/cardcompass-landing-v2 && flutter pub get`
Expected: Output ends with no error, `googleapis` appears in the resolved
package list (visible in `pubspec.lock` diff).

- [ ] **Step 3: Commit**

```bash
cd /Users/shantanuchandra/Downloads/Personal/cardcompass-landing-v2
git add pubspec.yaml pubspec.lock
git commit -m "chore: add googleapis dependency for Gmail sync"
```

---

## Task 2: Port `EmailRepository` and its interface

**Files:**
- Create: `lib/core/repositories/email_repository_interface.dart`
- Create: `lib/core/repositories/email_repository.dart`

- [ ] **Step 1: Create the interface file**

Create `lib/core/repositories/email_repository_interface.dart` with this exact
content (copied from
`/Users/shantanuchandra/Downloads/Personal/cardcompass/lib/core/repositories/email_repository_interface.dart`):

```dart
/// Repository interface for the subset of email-record operations
/// the Gmail sync flow depends on. Lets tests substitute a fake
/// without touching a real Supabase client.
abstract class EmailRepositoryInterface {
  /// Check if email already exists
  Future<bool> emailExists(String userId, String emailId);

  /// Store email record in the database
  Future<String> storeEmail({
    required String userId,
    required String emailId,
    required String subject,
    required String sender,
    required DateTime receivedDate,
    required bool hasAttachments,
    String? bankDetected,
    Map<String, dynamic>? metadata,
  });

  /// Update email processing status
  Future<void> updateEmailStatus({
    required String userId,
    required String emailId,
    required bool processed,
    String? statementId,
  });
}
```

- [ ] **Step 2: Create the repository file**

Create `lib/core/repositories/email_repository.dart` with this exact content
(copied verbatim from
`/Users/shantanuchandra/Downloads/Personal/cardcompass/lib/core/repositories/email_repository.dart`
— the package name `cardcompass` matches this project's `pubspec.yaml` `name:`
field, so the import path is unchanged):

```dart
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cardcompass/core/repositories/email_repository_interface.dart';

/// Repository for managing email records in the database
class EmailRepository implements EmailRepositoryInterface {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Store email record in the database
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
    try {
      final emailData = {
        'user_id': userId,
        'email_id': emailId,
        'subject': subject,
        'sender': sender,
        'received_date': receivedDate.toIso8601String(),
        'has_attachments': hasAttachments,
        'processed': false,
        'bank_detected': bankDetected,
        'metadata': metadata ?? {},
        'created_at': DateTime.now().toIso8601String(),
      };

      final response = await _supabase
          .from('emails')
          .insert(emailData)
          .select('id')
          .single();

      return response['id'] as String;
    } catch (e) {
      throw Exception('Failed to store email: $e');
    }
  }

  /// Update email processing status
  @override
  Future<void> updateEmailStatus({
    required String userId,
    required String emailId,
    required bool processed,
    String? statementId,
  }) async {
    try {
      final updateData = <String, dynamic>{
        'processed': processed,
      };

      if (statementId != null) {
        updateData['statement_id'] = statementId;
      }

      await _supabase
          .from('emails')
          .update(updateData)
          .eq('user_id', userId)
          .eq('email_id', emailId);
    } catch (e) {
      throw Exception('Failed to update email status: $e');
    }
  }

  /// Check if email already exists
  @override
  Future<bool> emailExists(String userId, String emailId) async {
    try {
      final response = await _supabase
          .from('emails')
          .select('id')
          .eq('user_id', userId)
          .eq('email_id', emailId)
          .limit(1);

      return response.isNotEmpty;
    } catch (e) {
      return false;
    }
  }
}
```

Note: this port intentionally omits `getUserEmails`, `isEmailProcessed`,
`getUnprocessedEmails`, and `getEmailsByBank` from `main`'s version — those
support later pipeline stages (processing status, bank-specific queries) that
are out of scope for this slice. Add them back when the slice that needs them
is built, per YAGNI.

- [ ] **Step 3: Verify it compiles**

Run: `cd /Users/shantanuchandra/Downloads/Personal/cardcompass-landing-v2 && flutter analyze lib/core/repositories/email_repository.dart lib/core/repositories/email_repository_interface.dart`
Expected: `No issues found!` (or only pre-existing lint infos unrelated to
these new files — there should be zero errors).

- [ ] **Step 4: Commit**

```bash
git add lib/core/repositories/email_repository.dart lib/core/repositories/email_repository_interface.dart
git commit -m "feat: port EmailRepository from main for Gmail sync emails table writes"
```

---

## Task 3: Build `GmailSyncService`

**Files:**
- Create: `lib/core/services/gmail_sync_service.dart`

This service takes an access token (already obtained from Supabase's session
— it does not manage OAuth itself) and returns lightweight search results. It
does not download attachment bytes.

- [ ] **Step 1: Create the service file**

Create `lib/core/services/gmail_sync_service.dart`:

```dart
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
```

- [ ] **Step 2: Verify it compiles**

Run: `cd /Users/shantanuchandra/Downloads/Personal/cardcompass-landing-v2 && flutter analyze lib/core/services/gmail_sync_service.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/core/services/gmail_sync_service.dart
git commit -m "feat: add GmailSyncService to search inbox for statement emails"
```

---

## Task 4: Build the `gmailSyncProvider` orchestration layer

**Files:**
- Create: `lib/features/dashboard/providers/gmail_sync_provider.dart`

- [ ] **Step 1: Create the provider file**

Create `lib/features/dashboard/providers/gmail_sync_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/supabase_provider.dart';
import '../../../core/repositories/email_repository.dart';
import '../../../core/services/gmail_sync_service.dart';

/// Outcome of one Gmail sync run, shown to the user as a summary.
class GmailSyncResult {
  final int foundCount;
  final int newlyStoredCount;
  final int skippedCount;
  final int failedCount;

  const GmailSyncResult({
    required this.foundCount,
    required this.newlyStoredCount,
    required this.skippedCount,
    required this.failedCount,
  });
}

/// Thrown when there is no usable Google access token to call Gmail with.
class NoGmailTokenException implements Exception {
  final String message;
  const NoGmailTokenException(this.message);
  @override
  String toString() => message;
}

class GmailSyncNotifier extends AsyncNotifier<GmailSyncResult?> {
  @override
  Future<GmailSyncResult?> build() async => null;

  Future<void> syncGmail() async {
    state = const AsyncValue.loading();
    try {
      final session =
          ref.read(supabaseClientProvider).auth.currentSession;
      final accessToken = session?.providerToken;
      final userId = session?.user.id;

      if (accessToken == null || userId == null) {
        throw const NoGmailTokenException(
          'No Google session token found. Please sign out and sign back in '
          'to enable Gmail sync.',
        );
      }

      final gmailService = GmailSyncService(accessToken);
      final emailRepo = EmailRepository();

      try {
        final results = await gmailService.searchStatementEmails();

        var newlyStored = 0;
        var skipped = 0;
        var failed = 0;

        for (final result in results) {
          try {
            final exists =
                await emailRepo.emailExists(userId, result.messageId);
            if (exists) {
              skipped++;
              continue;
            }
            await emailRepo.storeEmail(
              userId: userId,
              emailId: result.messageId,
              subject: result.subject,
              sender: result.from,
              receivedDate: result.receivedDate,
              hasAttachments: result.hasAttachment,
            );
            newlyStored++;
          } catch (_) {
            failed++;
          }
        }

        state = AsyncValue.data(GmailSyncResult(
          foundCount: results.length,
          newlyStoredCount: newlyStored,
          skippedCount: skipped,
          failedCount: failed,
        ));
      } finally {
        gmailService.dispose();
      }
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

final gmailSyncProvider =
    AsyncNotifierProvider<GmailSyncNotifier, GmailSyncResult?>(
  GmailSyncNotifier.new,
);
```

- [ ] **Step 2: Verify it compiles**

Run: `cd /Users/shantanuchandra/Downloads/Personal/cardcompass-landing-v2 && flutter analyze lib/features/dashboard/providers/gmail_sync_provider.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/features/dashboard/providers/gmail_sync_provider.dart
git commit -m "feat: add gmailSyncProvider orchestrating Gmail search and email storage"
```

---

## Task 5: Add the "Sync Gmail" button to the Dashboard

**Files:**
- Modify: `lib/features/dashboard/screens/dashboard_screen.dart`

The Dashboard's app bar currently shows a greeting, "CardCompass" title, and
an avatar (see `_DashboardAppBar` in this file). Add a sync icon button next
to the avatar.

- [ ] **Step 1: Add the import**

At the top of `lib/features/dashboard/screens/dashboard_screen.dart`, add:

```dart
import '../providers/gmail_sync_provider.dart';
```

- [ ] **Step 2: Add the sync button to `_DashboardAppBar`**

Find the `_DashboardAppBar` class. It is currently a `StatelessWidget`. Change
it to a `ConsumerWidget` so it can watch `gmailSyncProvider`, and add a sync
icon button in the `Row` next to the existing `CircleAvatar`.

Locate this existing code (the class declaration and the `Row` in
`flexibleSpace`):

```dart
class _DashboardAppBar extends StatelessWidget {
  final dynamic user;
  const _DashboardAppBar({this.user});

  @override
  Widget build(BuildContext context) {
    final name = (user?.userMetadata?['full_name'] as String?)?.split(' ').first ?? 'there';
    final avatar = user?.userMetadata?['avatar_url'] as String?;
    final hour = DateTime.now().hour;
    final greeting = hour < 12 ? 'Good morning' : hour < 17 ? 'Good afternoon' : 'Good evening';

    return SliverAppBar(
      backgroundColor: AppColors.surfaceVoid,
      floating: true,
      snap: true,
      expandedHeight: 0,
      toolbarHeight: 72,
      flexibleSpace: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, 0),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$greeting, $name',
                    style: GoogleFonts.inter(
                      fontSize: 13, color: AppColors.textSecondary, fontWeight: FontWeight.w400,
                    ),
                  ),
                  Text(
                    'CardCompass',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 22, fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary, letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
            ),
            // Avatar
            CircleAvatar(
              radius: 20,
              backgroundColor: AppColors.surface2,
              backgroundImage: avatar != null ? NetworkImage(avatar) : null,
              child: avatar == null
                  ? Text(name[0].toUpperCase(),
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.neonCyan,
                      ))
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
```

Replace it with:

```dart
class _DashboardAppBar extends ConsumerWidget {
  final dynamic user;
  const _DashboardAppBar({this.user});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = (user?.userMetadata?['full_name'] as String?)?.split(' ').first ?? 'there';
    final avatar = user?.userMetadata?['avatar_url'] as String?;
    final hour = DateTime.now().hour;
    final greeting = hour < 12 ? 'Good morning' : hour < 17 ? 'Good afternoon' : 'Good evening';
    final syncState = ref.watch(gmailSyncProvider);

    ref.listen(gmailSyncProvider, (previous, next) {
      next.whenOrNull(
        data: (result) {
          if (result == null) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Found ${result.foundCount} statement emails, '
                '${result.newlyStoredCount} new'
                '${result.failedCount > 0 ? ', ${result.failedCount} failed' : ''}.',
              ),
            ),
          );
        },
        error: (error, _) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gmail sync failed: $error')),
          );
        },
      );
    });

    return SliverAppBar(
      backgroundColor: AppColors.surfaceVoid,
      floating: true,
      snap: true,
      expandedHeight: 0,
      toolbarHeight: 72,
      flexibleSpace: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, 0),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$greeting, $name',
                    style: GoogleFonts.inter(
                      fontSize: 13, color: AppColors.textSecondary, fontWeight: FontWeight.w400,
                    ),
                  ),
                  Text(
                    'CardCompass',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 22, fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary, letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
            ),
            // Sync Gmail button
            IconButton(
              tooltip: 'Sync Gmail',
              onPressed: syncState.isLoading
                  ? null
                  : () => ref.read(gmailSyncProvider.notifier).syncGmail(),
              icon: syncState.isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.neonCyan,
                      ),
                    )
                  : const Icon(Icons.sync_rounded, color: AppColors.neonCyan),
            ),
            const SizedBox(width: AppSpacing.sm),
            // Avatar
            CircleAvatar(
              radius: 20,
              backgroundColor: AppColors.surface2,
              backgroundImage: avatar != null ? NetworkImage(avatar) : null,
              child: avatar == null
                  ? Text(name[0].toUpperCase(),
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.neonCyan,
                      ))
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: Verify it compiles**

Run: `cd /Users/shantanuchandra/Downloads/Personal/cardcompass-landing-v2 && flutter analyze lib/features/dashboard/screens/dashboard_screen.dart`
Expected: `No issues found!` (or only the one pre-existing
`unnecessary_underscores` info at line ~762 that predates this change).

- [ ] **Step 4: Commit**

```bash
git add lib/features/dashboard/screens/dashboard_screen.dart
git commit -m "feat: add Sync Gmail button to dashboard app bar"
```

---

## Task 6: Manual verification in Comet

This slice has no automated tests (consistent with the rest of this project,
which has no Flutter widget/unit test suite yet). Verification is manual,
against the live Supabase project and a real Gmail inbox.

**Files:** None (verification only).

- [ ] **Step 1: Rebuild**

```bash
cd /Users/shantanuchandra/Downloads/Personal/cardcompass-landing-v2
flutter build web --dart-define-from-file=dart_defines.json --no-tree-shake-icons
```

Expected: `✓ Built build/web`

- [ ] **Step 2: Restart the static server**

```bash
lsof -ti :54321 | xargs kill -9 2>/dev/null
cd build/web && python3 /tmp/serve_flutter.py &
```

- [ ] **Step 3: Test in Comet**

Using the `mcp__claude-in-chrome__*` tools (per this project's testing
convention), navigate to `http://localhost:54321`, sign in with Google (the
consent screen will now also request Gmail read access — this was already
part of the scope requested at login), land on the Dashboard, and tap the new
sync icon in the app bar.

Expected: a snackbar appears reporting a found/new/skipped count. Tapping
sync again immediately after should report the same found count but 0 newly
stored (all skipped as duplicates), proving idempotency.

- [ ] **Step 4: Verify in Supabase**

Check the `emails` table in the Supabase dashboard (or via a query) for the
signed-in user's `user_id` — confirm new rows exist with `subject`, `sender`,
`received_date`, `has_attachments` populated and `processed: false`,
`bank_detected: null`.

- [ ] **Step 5: Test the no-token error path**

If possible, wait for the `providerToken` to go stale (or manually clear it
via `localStorage` in the browser console, deleting the
`sb-<project>-auth-token` entry's `provider_token` field) and tap sync again.
Expected: a snackbar with the "No Google session token found... sign out and
sign back in" message, not a silent failure or crash.

---

## Self-Review Notes

- **Spec coverage:** All four components from the design spec (`GmailSyncService`,
  ported `EmailRepository`, `gmailSyncProvider`, Dashboard button) have a task.
  The known-gaps section of the spec (no token refresh, no PDF download, no
  bank detection, no pagination beyond 50) is intentionally not implemented
  here — matches spec's explicit scope boundary.
- **Placeholder scan:** No TBD/TODO markers; every code step has complete,
  runnable code.
- **Type consistency:** `GmailSearchResult` (Task 3) fields (`messageId`,
  `subject`, `from`, `receivedDate`, `hasAttachment`) are consumed with
  matching names in `gmailSyncProvider` (Task 4). `EmailRepository.storeEmail`
  parameter names (Task 2) match the call site in Task 4
  (`userId`, `emailId`, `subject`, `sender`, `receivedDate`, `hasAttachments`).
  `GmailAuthException` (Task 3) is a subtype of `Exception`, so it propagates
  naturally to the `catch (e, st)` in Task 4's `syncGmail()` and renders via
  `$error` in Task 5's snackbar — no special-casing needed, verified this
  produces a readable message rather than `Instance of 'GmailAuthException'`
  since it has a `toString()` override.
