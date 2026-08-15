# PDF Statement Parsing (Slice 2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** After Gmail sync finds statement emails (slice 1, already working),
download each PDF attachment, unlock it, parse its transactions and rewards
via Gemini, and store everything in Supabase — closing the loop from "found
an email" to "real spend data on the dashboard."

**Architecture:** A new `StatementProcessingService` orchestrates, per
unprocessed email: download PDF → resolve password (cached → DB DOB → Google
People API DOB → DOB dialog → generated candidates → manual password dialog)
→ extract text → parse via a trimmed Gemini port (through the already-deployed
`gemini-proxy` Supabase Edge Function) → persist statement + transactions →
mark the email processed. Repository additions follow this project's existing
simple-class pattern (a `SupabaseClient` in the constructor, no interface
layer), not main's heavier DI-seamed repositories.

**Tech Stack:** `syncfusion_flutter_pdf` (new), existing `googleapis` /
`shared_preferences` / `http` / `supabase_flutter`, a `navigatorKey` added to
`MaterialApp.router`.

---

## Task 1: Add `syncfusion_flutter_pdf` dependency and OAuth birthday scope

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/features/auth/providers/auth_provider.dart`

- [ ] **Step 1: Add the PDF package**

Add to `pubspec.yaml`'s `dependencies:` section, near the other content
packages:

```yaml
  syncfusion_flutter_pdf: ^34.1.30
```

- [ ] **Step 2: Fetch packages**

Run: `cd /Users/shantanuchandra/Downloads/Personal/cardcompass-landing-v2 && flutter pub get`
Expected: no error; `syncfusion_flutter_pdf` appears as a new resolved
dependency.

- [ ] **Step 3: Add the birthday OAuth scope**

Open `lib/features/auth/providers/auth_provider.dart`. Find:

```dart
      await ref.read(supabaseClientProvider).auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: Uri.base.origin,
        scopes: 'email profile https://www.googleapis.com/auth/gmail.readonly',
        queryParams: const {'access_type': 'offline', 'prompt': 'consent'},
      );
```

Replace the `scopes` line with:

```dart
        scopes: 'email profile https://www.googleapis.com/auth/gmail.readonly '
            'https://www.googleapis.com/auth/user.birthday.read',
```

- [ ] **Step 4: Verify it compiles**

Run: `cd /Users/shantanuchandra/Downloads/Personal/cardcompass-landing-v2 && flutter analyze lib/features/auth/providers/auth_provider.dart`
Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
cd /Users/shantanuchandra/Downloads/Personal/cardcompass-landing-v2
git add pubspec.yaml pubspec.lock lib/features/auth/providers/auth_provider.dart
git commit -m "chore: add syncfusion_flutter_pdf and user.birthday.read OAuth scope"
```

---

## Task 2: Add `navigatorKey` so dialogs can show mid-sync

**Files:**
- Modify: `lib/app.dart`

- [ ] **Step 1: Read the current file**

Read `lib/app.dart` to confirm the current `MaterialApp.router` call site
before editing (it was last modified in an earlier session; confirm exact
current content matches what's expected below).

- [ ] **Step 2: Add the navigatorKey**

In `lib/app.dart`, add a top-level `navigatorKey` and pass it to
`MaterialApp.router`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';

/// Global navigator key so services (Gmail sync's password/DOB dialogs) can
/// show a dialog mid-async-flow without a BuildContext being threaded through
/// every call site.
final navigatorKey = GlobalKey<NavigatorState>();

class CardCompassApp extends ConsumerWidget {
  const CardCompassApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'CardCompass',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.0)),
        child: child!,
      ),
    );
  }
}
```

(This adds only the `navigatorKey` declaration — everything else in the file
stays as it was. If the actual current file differs from the body shown
above in ways unrelated to this change, keep those differences and just add
the `navigatorKey` line + import if not already present.)

- [ ] **Step 3: Verify it compiles**

Run: `cd /Users/shantanuchandra/Downloads/Personal/cardcompass-landing-v2 && flutter analyze lib/app.dart`
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add lib/app.dart
git commit -m "feat: add navigatorKey for mid-sync dialogs"
```

---

## Task 3: Port `ParsingLogger`, `CardNormalizerService`, `PasswordLearningService`

**Files:**
- Create: `lib/core/services/parsing_logger.dart`
- Create: `lib/core/services/card_normalizer_service.dart`
- Create: `lib/core/services/password_learning_service.dart`

These three are fully self-contained (no dependencies on each other or on
anything not already in this project) — ported verbatim.

- [ ] **Step 1: Create `parsing_logger.dart`**

```dart
class ParsingLogger {
  /// Toggle detailed, verbose debugging logs
  static bool verbose = false;

  static final List<void Function(String)> _listeners = [];

  /// Add a listener to receive real-time log updates
  static void addListener(void Function(String) listener) {
    _listeners.add(listener);
  }

  /// Remove a listener
  static void removeListener(void Function(String) listener) {
    _listeners.remove(listener);
  }

  static void _notifyListeners(String message) {
    for (final listener in List.from(_listeners)) {
      try {
        listener(message);
      } catch (e) {
        // Suppress listener callback errors
      }
    }
  }

  /// Log a detailed error (always printed)
  static void error(String message, [Object? error, StackTrace? stackTrace]) {
    final formatted = '❌ ERROR: $message${error != null ? ' ($error)' : ''}';
    print(formatted);
    _notifyListeners(formatted);
  }

  /// Log a detailed warning (always printed)
  static void warning(String message) {
    final formatted = '⚠️ WARNING: $message';
    print(formatted);
    _notifyListeners(formatted);
  }

  /// Log an extracted transaction in detail (always printed)
  static void transaction(String message) {
    final formatted = '✅ TRANSACTION: $message';
    print(formatted);
    _notifyListeners(formatted);
  }

  /// Log a concise, high-level summary of a stage (always printed)
  static void summary(String message) {
    final formatted = '📋 SUMMARY: $message';
    print(formatted);
    _notifyListeners(formatted);
  }

  /// Log micro-level internal debugging details (muted by default)
  static void debug(String message) {
    final formatted = '🔍 DEBUG: $message';
    if (verbose) {
      print(formatted);
    }
    _notifyListeners(formatted);
  }
}
```

- [ ] **Step 2: Create `card_normalizer_service.dart`**

```dart
/// Shared service for normalizing bank and card names
class CardNormalizerService {
  /// Normalize a bank name to a canonical form to prevent duplicates
  static String normalizeBankName(String rawName) {
    final lower = rawName.toLowerCase();

    if (lower.contains('hdfc')) return 'HDFC Bank';
    if (lower.contains('sbi')) return 'SBI Card';
    if (lower.contains('axis')) return 'Axis Bank';

    if (lower.contains('amazon') && lower.contains('icici')) return 'Amazon ICICI Bank';
    if (lower.contains('icici')) return 'ICICI Bank';

    if (lower.contains('kotak')) return 'Kotak Bank';
    if (lower.contains('idfc')) return 'IDFC FIRST Bank';
    if (lower.contains('yes')) return 'Yes Bank';
    if (lower.contains('au ')) return 'AU Small Finance Bank';
    if (lower.contains('indusind')) return 'IndusInd Bank';
    if (lower.contains('standard chartered')) return 'Standard Chartered';
    if (lower.contains('american express') || lower.contains('amex')) return 'American Express';
    if (lower.contains('citi')) return 'Citibank';
    if (lower.contains('hsbc')) return 'HSBC';
    if (lower.contains('rbl')) return 'RBL Bank';
    if (lower.contains('federal')) return 'Federal Bank';
    if (lower.contains('karur vysya')) return 'Karur Vysya Bank';
    if (lower.contains('bob') || lower.contains('bank of baroda')) return 'Bank of Baroda';
    if (lower.contains('canara')) return 'Canara Bank';
    if (lower.contains('pnb') || lower.contains('punjab national')) return 'Punjab National Bank';
    if (lower.contains('union bank')) return 'Union Bank of India';
    if (lower.contains('indian bank')) return 'Indian Bank';
    if (lower.contains('central bank')) return 'Central Bank of India';
    if (lower.contains('indian overseas')) return 'Indian Overseas Bank';
    if (lower.contains('allahabad') || lower.contains('indian')) return 'Indian Bank';

    return rawName.split(RegExp(r"\s+")).map((w) => w.isEmpty
      ? w
      : w[0].toUpperCase() + w.substring(1).toLowerCase()).join(' ');
  }

  /// Normalize a card name to extract just the variant name
  static String normalizeCardName(String rawName, String bankName) {
    var name = rawName.toLowerCase()
      .replaceAll(RegExp(r'credit card', caseSensitive: false), '')
      .replaceAll(RegExp(r'statement for', caseSensitive: false), '')
      .replaceAll(RegExp(r'bank', caseSensitive: false), '')
      .trim();

    final bankLower = bankName.toLowerCase();
    final bankWords = bankLower.split(' ');

    for (final bankWord in bankWords) {
      if (bankWord.isNotEmpty && bankWord != 'bank') {
        name = name.replaceAll(RegExp(r'^' + RegExp.escape(bankWord) + r'\s*', caseSensitive: false), '');
      }
    }

    name = name
      .replaceAll(RegExp(r'^axis\s*', caseSensitive: false), '')
      .replaceAll(RegExp(r'^hdfc\s*', caseSensitive: false), '')
      .replaceAll(RegExp(r'^sbi\s*', caseSensitive: false), '')
      .replaceAll(RegExp(r'^icici\s*', caseSensitive: false), '')
      .replaceAll(RegExp(r'^kotak\s*', caseSensitive: false), '')
      .replaceAll(RegExp(r'^idfc\s*', caseSensitive: false), '')
      .replaceAll(RegExp(r'^yes\s*', caseSensitive: false), '')
      .replaceAll(RegExp(r'^au\s*', caseSensitive: false), '')
      .replaceAll(RegExp(r'^indusind\s*', caseSensitive: false), '')
      .replaceAll(RegExp(r'^rbl\s*', caseSensitive: false), '')
      .replaceAll(RegExp(r'first\s*', caseSensitive: false), '')
      .replaceAll(RegExp(r'bank\s*', caseSensitive: false), '')
      .replaceAll(RegExp(r'card\s*$', caseSensitive: false), '')
      .replaceAll(RegExp(r'ltd\s*', caseSensitive: false), '')
      .replaceAll(RegExp(r'limited\s*', caseSensitive: false), '')
      .trim();

    if (name.isEmpty) {
      name = rawName.toLowerCase()
        .replaceAll(RegExp(r'credit card', caseSensitive: false), '')
        .replaceAll(RegExp(r'bank', caseSensitive: false), '')
        .trim();
    }

    final result = name.split(RegExp(r"\s+")).map((w) => w.isEmpty
      ? w
      : w[0].toUpperCase() + w.substring(1)).join(' ');

    return result.isNotEmpty ? result : rawName;
  }
}
```

(Trimmed from main's version: dropped `getCardIdentifier`, `isRecognizedBank`,
`getBankInfo` — unused by `parseStatementInfo`/`parseTransactions`, the only
callers in this slice. `normalizeBankName`/`normalizeCardName` are the two
methods actually called.)

- [ ] **Step 3: Create `password_learning_service.dart`**

```dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Service for learning and storing successful password patterns
class PasswordLearningService {
  static const String _passwordPatternsKey = 'successful_password_patterns';
  static const String _bankPasswordsKey = 'bank_specific_passwords';

  /// Store a successful password pattern for future use
  static Future<void> storeSuccessfulPassword({
    required String bankName,
    required String password,
    required String userEmail,
    String? fileName,
    Map<String, dynamic>? userProfile,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final pattern = _analyzePasswordPattern(
        password: password,
        bankName: bankName,
        userProfile: userProfile,
        fileName: fileName,
      );

      await _storeBankPassword(prefs, bankName, userEmail, password, pattern);
      await _storePasswordPattern(prefs, pattern);
    } catch (e) {
      print('Error storing successful password: $e');
    }
  }

  /// Get learned password candidates for a bank and user
  static Future<List<String>> getLearnedPasswordCandidates({
    required String bankName,
    required String userEmail,
    Map<String, dynamic>? userProfile,
    String? fileName,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final candidates = <String>[];

      final bankPasswords = await _getBankPasswords(prefs, bankName, userEmail);
      candidates.addAll(bankPasswords);

      final learnedCandidates = await _generateFromLearnedPatterns(
        prefs: prefs,
        bankName: bankName,
        userProfile: userProfile,
        fileName: fileName,
      );
      candidates.addAll(learnedCandidates);

      return candidates.toSet().toList();
    } catch (e) {
      print('Error getting learned passwords: $e');
      return [];
    }
  }

  static Map<String, dynamic> _analyzePasswordPattern({
    required String password,
    required String bankName,
    Map<String, dynamic>? userProfile,
    String? fileName,
  }) {
    final pattern = <String, dynamic>{
      'bankName': bankName.toLowerCase(),
      'passwordLength': password.length,
      'timestamp': DateTime.now().toIso8601String(),
    };

    if (userProfile != null && userProfile['birthday'] != null) {
      final birthday = userProfile['birthday'] as Map<String, dynamic>;
      final dobFormats = [
        birthday['ddmmyyyy'] as String?,
        birthday['yyyymmdd'] as String?,
        birthday['ddmmyy'] as String?,
        birthday['mmddyyyy'] as String?,
      ].where((d) => d != null).cast<String>();

      for (final dobFormat in dobFormats) {
        if (password.contains(dobFormat)) {
          pattern['containsDOB'] = true;
          pattern['dobFormat'] = dobFormat;
          pattern['dobPosition'] = password.indexOf(dobFormat);

          final remainingAfterDOB = password.substring(password.indexOf(dobFormat) + dobFormat.length);
          if (remainingAfterDOB.length == 4 && RegExp(r'^\d{4}$').hasMatch(remainingAfterDOB)) {
            pattern['type'] = 'dob_plus_4digits';
            pattern['description'] = 'DOB ($dobFormat) + 4 digits ($remainingAfterDOB)';
            pattern['digitsSuffix'] = remainingAfterDOB;
          }
          break;
        }
      }
    }

    if (RegExp(r'^\d+$').hasMatch(password)) {
      pattern['isNumericOnly'] = true;

      if (password.length == 12) {
        pattern['type'] = pattern['type'] ?? 'numeric_12_digit';
        pattern['description'] = pattern['description'] ?? '12-digit numeric pattern';
      }
    }

    if (fileName != null) {
      final cardNumberMatch = RegExp(r'(\d{4})_').firstMatch(fileName);
      if (cardNumberMatch != null && password.contains(cardNumberMatch.group(1)!)) {
        pattern['containsCardDigits'] = true;
        pattern['cardDigits'] = cardNumberMatch.group(1);
      }
    }

    pattern['type'] = pattern['type'] ?? 'unknown';
    pattern['description'] = pattern['description'] ?? 'Unknown pattern';

    return pattern;
  }

  static Future<void> _storeBankPassword(
    SharedPreferences prefs,
    String bankName,
    String userEmail,
    String password,
    Map<String, dynamic> pattern,
  ) async {
    final bankPasswordsJson = prefs.getString(_bankPasswordsKey) ?? '{}';
    final bankPasswords = Map<String, dynamic>.from(json.decode(bankPasswordsJson));

    final bankKey = '${bankName.toLowerCase()}_$userEmail';
    bankPasswords[bankKey] = {
      'password': password,
      'pattern': pattern,
      'successCount': (bankPasswords[bankKey]?['successCount'] ?? 0) + 1,
      'lastUsed': DateTime.now().toIso8601String(),
    };

    await prefs.setString(_bankPasswordsKey, json.encode(bankPasswords));
  }

  static Future<void> _storePasswordPattern(
    SharedPreferences prefs,
    Map<String, dynamic> pattern,
  ) async {
    final patternsJson = prefs.getString(_passwordPatternsKey) ?? '[]';
    final patterns = List<Map<String, dynamic>>.from(
      json.decode(patternsJson).map((p) => Map<String, dynamic>.from(p))
    );

    patterns.add(pattern);

    if (patterns.length > 50) {
      patterns.removeRange(0, patterns.length - 50);
    }

    await prefs.setString(_passwordPatternsKey, json.encode(patterns));
  }

  static Future<List<String>> _getBankPasswords(
    SharedPreferences prefs,
    String bankName,
    String userEmail,
  ) async {
    final bankPasswordsJson = prefs.getString(_bankPasswordsKey) ?? '{}';
    final bankPasswords = Map<String, dynamic>.from(json.decode(bankPasswordsJson));

    final bankKey = '${bankName.toLowerCase()}_$userEmail';
    final bankData = bankPasswords[bankKey];

    if (bankData != null) {
      return [bankData['password'] as String];
    }

    return [];
  }

  static Future<List<String>> _generateFromLearnedPatterns({
    required SharedPreferences prefs,
    required String bankName,
    Map<String, dynamic>? userProfile,
    String? fileName,
  }) async {
    final candidates = <String>[];

    final patternsJson = prefs.getString(_passwordPatternsKey) ?? '[]';
    final patterns = List<Map<String, dynamic>>.from(
      json.decode(patternsJson).map((p) => Map<String, dynamic>.from(p))
    );

    final bankPatterns = patterns.where((p) =>
      p['bankName'] == bankName.toLowerCase()
    ).toList();

    for (final pattern in bankPatterns) {
      if (pattern['type'] == 'dob_plus_4digits' && userProfile != null) {
        final birthday = userProfile['birthday'] as Map<String, dynamic>?;
        if (birthday != null) {
          final dobFormat = pattern['dobFormat'] as String?;
          if (dobFormat != null && birthday.containsValue(dobFormat)) {
            if (fileName != null) {
              final matches = RegExp(r'\d{4}').allMatches(fileName);
              for (final match in matches) {
                candidates.add(dobFormat + match.group(0)!);
              }
            }
          }
        }
      }
    }

    return candidates;
  }
}
```

(Trimmed: dropped `clearAllStoredData` and `getLearnedStatistics` — not
called by anything in this slice's flow.)

- [ ] **Step 4: Verify all three compile**

Run: `cd /Users/shantanuchandra/Downloads/Personal/cardcompass-landing-v2 && flutter analyze lib/core/services/parsing_logger.dart lib/core/services/card_normalizer_service.dart lib/core/services/password_learning_service.dart`
Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add lib/core/services/parsing_logger.dart lib/core/services/card_normalizer_service.dart lib/core/services/password_learning_service.dart
git commit -m "feat: port ParsingLogger, CardNormalizerService, PasswordLearningService from main"
```

---

## Task 4: Port `SimpleBirthdayInputService` and `PasswordInputService` (navigatorKey-based)

**Files:**
- Create: `lib/core/services/simple_birthday_input_service.dart`
- Create: `lib/core/services/password_input_service.dart`

- [ ] **Step 1: Create `simple_birthday_input_service.dart`**

Ported verbatim from main (already takes a nullable `BuildContext` parameter,
so the caller — Task 6's `PdfPasswordResolver` — supplies
`navigatorKey.currentContext` from Task 2):

```dart
import 'package:flutter/material.dart';

/// Service to handle birthday input from users
class SimpleBirthdayInputService {
  /// Request birthday input from user via dialog
  static Future<DateTime?> requestBirthdayInput({
    required BuildContext? context,
    required String userId,
    required String reason,
  }) async {
    if (context == null) {
      print('⚠️  No context provided for birthday input dialog');
      return null;
    }

    final result = await showDialog<DateTime?>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Date of Birth Required'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('We need your date of birth for PDF password detection.'),
              const SizedBox(height: 8),
              Text('Reason: $reason', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              const SizedBox(height: 16),
              const Text('This will be stored securely in your profile for future use.'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(null),
              child: const Text('Skip'),
            ),
            ElevatedButton(
              onPressed: () async {
                final date = await _showDatePicker(dialogContext);
                if (date != null) {
                  Navigator.of(dialogContext).pop(date);
                }
              },
              child: const Text('Select Date'),
            ),
          ],
        );
      },
    );

    return result;
  }

  static Future<DateTime?> _showDatePicker(BuildContext context) async {
    final now = DateTime.now();
    final eighteenYearsAgo = DateTime(now.year - 18, now.month, now.day);

    return await showDatePicker(
      context: context,
      initialDate: eighteenYearsAgo,
      firstDate: DateTime(1900),
      lastDate: now,
      helpText: 'Select your date of birth',
    );
  }

  /// Format birthday for password generation
  static Map<String, String> formatBirthdayForPasswords(DateTime birthday) {
    final year = birthday.year.toString();
    final month = birthday.month.toString().padLeft(2, '0');
    final day = birthday.day.toString().padLeft(2, '0');
    final shortYear = year.substring(2);

    return {
      'ddmm': '$day$month',
      'ddmmyy': '$day$month$shortYear',
      'ddmmyyyy': '$day$month$year',
      'yyyymmdd': '$year$month$day',
      'mmddyyyy': '$month$day$year',
      'raw': '$year-$month-$day',
    };
  }
}
```

(Trimmed: dropped `isValidBirthday` — not called anywhere in this slice's
flow; the date picker's `firstDate`/`lastDate` bounds already constrain input
to a sane range.)

- [ ] **Step 2: Create `password_input_service.dart`**

Ported and adapted: instead of requiring a pre-registered global callback
(main's pattern), this version resolves the `BuildContext` from
`navigatorKey.currentContext` at call time, since this slice controls both
the caller (`PdfPasswordResolver`, Task 6) and doesn't need the extra
indirection main's version has for its different call sites.

```dart
import 'package:flutter/material.dart';
import '../../app.dart' show navigatorKey;

/// Service for handling manual password input when automated detection fails
class PasswordInputService {
  static int _attemptCount = 0;
  static String? _lastFailedPassword;

  /// Reset attempt tracking (call when starting new PDF processing)
  static void resetAttempts() {
    _attemptCount = 0;
    _lastFailedPassword = null;
  }

  /// Ask the user for a PDF password via a dialog on the current navigator
  /// context. Returns null if no context is available or the user cancels.
  static Future<String?> requestPassword(String bankName, {String? hint}) async {
    _attemptCount++;
    final context = navigatorKey.currentContext;
    if (context == null || !context.mounted) {
      print('❌ No valid context available for password dialog');
      return null;
    }

    final password = await _showPasswordInputDialog(context, bankName: bankName, hint: hint);
    if (password != null) {
      _lastFailedPassword = password;
    }
    return password;
  }

  static Future<String?> _showPasswordInputDialog(
    BuildContext context, {
    required String bankName,
    String? hint,
  }) async {
    final TextEditingController controller = TextEditingController();
    final isRetry = _attemptCount > 1;

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(isRetry ? 'Password Incorrect - Try Again' : 'PDF Password Required'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isRetry && _lastFailedPassword != null) ...[
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    border: Border.all(color: Colors.red[200]!),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: Colors.red[600], size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Password "$_lastFailedPassword" was incorrect',
                          style: TextStyle(color: Colors.red[700], fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text('Attempt $_attemptCount of 2'),
                const SizedBox(height: 16),
              ],
              Text('The ${bankName.toUpperCase()} statement PDF is password protected.'),
              const SizedBox(height: 16),
              if (hint != null) ...[
                Text(
                  'Hint: $hint',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600], fontStyle: FontStyle.italic),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: controller,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Enter PDF Password',
                  hintText: bankName.toLowerCase() == 'sbi'
                      ? 'DOB(DDMMYYYY) + Last4Digits'
                      : 'Password',
                  border: const OutlineInputBorder(),
                ),
                autofocus: true,
                onSubmitted: (value) => Navigator.of(dialogContext).pop(value.trim()),
              ),
              if (bankName.toLowerCase() == 'sbi') ...[
                const SizedBox(height: 8),
                const Text(
                  'Example: If DOB is 02/12/1990 and card ends in 9329, password would be: 021219909329',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(null),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final password = controller.text.trim();
                Navigator.of(dialogContext).pop(password.isEmpty ? null : password);
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }
}
```

- [ ] **Step 3: Verify both compile**

Run: `cd /Users/shantanuchandra/Downloads/Personal/cardcompass-landing-v2 && flutter analyze lib/core/services/simple_birthday_input_service.dart lib/core/services/password_input_service.dart`
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add lib/core/services/simple_birthday_input_service.dart lib/core/services/password_input_service.dart
git commit -m "feat: port DOB and password input dialogs, wired to navigatorKey"
```

---

## Task 5: Port `PdfPasswordDetectionService` (candidate generation + try-passwords orchestration)

**Files:**
- Create: `lib/core/services/pdf_password_detection_service.dart`

Ported verbatim from main (this is the core password-candidate generation and
try-in-order logic; no changes needed since it already accepts
`onManualPasswordRequired` as an injected callback, which Task 6 will wire to
`PasswordInputService.requestPassword`).

- [ ] **Step 1: Create the file**

```dart
import 'dart:typed_data';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'password_input_service.dart';
import 'password_learning_service.dart';
import 'parsing_logger.dart';

/// Service for detecting and trying common PDF passwords used by banks
class PdfPasswordDetectionService {
  /// Common password patterns used by different banks
  static final Map<String, List<String>> bankPasswordPatterns = {
    'sbi': ['dob_ddmmyyyy', 'dob_yyyymmdd', 'dob_ddmmyy', 'last4_card', 'firstname_lastname', 'lastname_firstname'],
    'hdfc': ['dob_ddmmyyyy', 'dob_yyyymmdd', 'last4_card', 'pan_last4', 'firstname_dob'],
    'icici': ['dob_ddmmyyyy', 'dob_yyyymmdd', 'last4_card', 'mobile_last4'],
    'axis': ['dob_ddmmyyyy', 'dob_yyyymmdd', 'last4_card', 'firstname_lastname'],
    'kotak': ['dob_ddmmyyyy', 'dob_yyyymmdd', 'last4_card'],
  };

  /// Extract password hints and user data from email content
  Map<String, dynamic> extractPasswordHints({
    required String emailSubject,
    required String emailBody,
    required String userEmail,
    String? userName,
    String? fileName,
  }) {
    final hints = <String, dynamic>{};

    hints['userName'] = userName ?? _extractNameFromEmail(userEmail);
    hints['userEmail'] = userEmail;

    final content = '$emailSubject $emailBody';
    final contentLower = content.toLowerCase();

    final explicitPassword = _extractExplicitPasswordFromContent(content, contentLower, hints);
    if (explicitPassword != null) {
      hints['explicitPassword'] = explicitPassword;
    }

    final passwordFormat = _extractPasswordFormatInstruction(contentLower, hints);
    if (passwordFormat != null) {
      hints['passwordFormat'] = passwordFormat;
    }

    if (fileName != null) {
      final cardNumbers = _extractCardNumberFromFilename(fileName);
      if (cardNumbers.isNotEmpty) {
        hints['cardNumbersFromFile'] = cardNumbers;
      }
    }

    _extractDataBasedOnFormat(content, contentLower, hints);

    return hints;
  }

  String? _extractExplicitPasswordFromContent(String content, String contentLower, Map<String, dynamic> hints) {
    final explicitPatterns = [
      RegExp(r'password\s*(?:is|:)\s*([a-zA-Z0-9]{4,12})', caseSensitive: false),
      RegExp(r'the password is\s*([a-zA-Z0-9]{4,12})', caseSensitive: false),
      RegExp(r'password:\s*([a-zA-Z0-9]{4,12})', caseSensitive: false),
      RegExp(r'access password\s*(?:is|:)\s*([a-zA-Z0-9]{4,12})', caseSensitive: false),
      RegExp(r'pin\s*(?:is|:)\s*([0-9]{4,8})', caseSensitive: false),
      RegExp(r'the pin is\s*([0-9]{4,8})', caseSensitive: false),
      RegExp(r'access code\s*(?:is|:)\s*([a-zA-Z0-9]{4,12})', caseSensitive: false),
      RegExp(r'document password\s*(?:is|:)\s*([a-zA-Z0-9]{4,12})', caseSensitive: false),
    ];

    for (final pattern in explicitPatterns) {
      final match = pattern.firstMatch(content);
      if (match != null && match.group(1) != null) {
        return match.group(1)!;
      }
    }

    return null;
  }

  String? _extractPasswordFormatInstruction(String contentLower, Map<String, dynamic> hints) {
    final formatPatterns = [
      RegExp(r'password.*?(?:dob|date\s*of\s*birth).*?(?:ddmmyyyy|dd\s*mm\s*yyyy)', caseSensitive: false),
      RegExp(r'password.*?(?:dob|date\s*of\s*birth).*?(?:yyyymmdd|yyyy\s*mm\s*dd)', caseSensitive: false),
      RegExp(r'password.*?(?:dob|date\s*of\s*birth).*?(?:ddmmyy|dd\s*mm\s*yy)', caseSensitive: false),
      RegExp(r'password.*?(?:dob|date\s*of\s*birth).*?(?:mmddyyyy|mm\s*dd\s*yyyy)', caseSensitive: false),
      RegExp(r'password.*?last\s*4\s*digits.*?(?:card|account)', caseSensitive: false),
      RegExp(r'password.*?last\s*4\s*digits.*?mobile', caseSensitive: false),
      RegExp(r'password.*?last\s*4\s*digits.*?pan', caseSensitive: false),
      RegExp(r'password.*?(?:first\s*name|given\s*name)', caseSensitive: false),
      RegExp(r'password.*?(?:last\s*name|surname)', caseSensitive: false),
      RegExp(r'password.*?full\s*name', caseSensitive: false),
      RegExp(r'password.*?(?:ddmm|dd\s*mm)', caseSensitive: false),
      RegExp(r'password.*?(?:mmyy|mm\s*yy)', caseSensitive: false),
    ];

    for (final pattern in formatPatterns) {
      final match = pattern.firstMatch(contentLower);
      if (match != null) {
        return match.group(0)!;
      }
    }

    if (contentLower.contains('ddmmyyyy') || contentLower.contains('dd mm yyyy')) {
      return 'dob_ddmmyyyy';
    }
    if (contentLower.contains('yyyymmdd') || contentLower.contains('yyyy mm dd')) {
      return 'dob_yyyymmdd';
    }
    if (contentLower.contains('ddmmyy') || contentLower.contains('dd mm yy')) {
      return 'dob_ddmmyy';
    }
    if (contentLower.contains('mmddyyyy') || contentLower.contains('mm dd yyyy')) {
      return 'dob_mmddyyyy';
    }

    return null;
  }

  void _extractDataBasedOnFormat(String content, String contentLower, Map<String, dynamic> hints) {
    final format = hints['passwordFormat'] as String?;

    if (format != null) {
      if (format.contains('name')) {
        hints['nameVariations'] = _extractNameVariations(hints['userName'] as String? ?? '');
      }
    }
  }

  List<String> _extractNameVariations(String fullName) {
    final variations = <String>[];
    final nameParts = fullName.split(' ').where((part) => part.isNotEmpty).toList();

    if (nameParts.isNotEmpty) {
      final firstName = nameParts[0].toLowerCase();
      final lastName = nameParts.length > 1 ? nameParts.last.toLowerCase() : '';

      variations.add(firstName);
      variations.add(lastName);
      variations.add(fullName.toLowerCase().replaceAll(' ', ''));

      if (lastName.isNotEmpty) {
        variations.add('$firstName$lastName');
        variations.add('$lastName$firstName');
        variations.add('$firstName.$lastName');
        variations.add('$lastName.$firstName');
      }
    }
    return variations;
  }

  /// Generate possible passwords based on bank and extracted hints
  List<String> generatePasswordCandidates({
    required String bankName,
    required Map<String, dynamic> hints,
    Map<String, dynamic>? userProfile,
  }) {
    final passwords = <String>[];

    final userName = hints['userName'] as String? ?? '';
    final nameParts = userName.split(' ');
    final firstName = nameParts.isNotEmpty ? nameParts[0].toLowerCase() : '';
    final lastName = nameParts.length > 1 ? nameParts.last.toLowerCase() : '';

    final nameDataCombinations = _generateNameDateCombinations(userName, userProfile);
    passwords.addAll(nameDataCombinations);

    if (hints.containsKey('explicitPassword')) {
      passwords.insert(0, hints['explicitPassword'] as String);
    }

    final shortName = firstName.length >= 4 ? firstName.substring(0, 4) : firstName;
    final commonPasswords = <String>[shortName, lastName];
    passwords.addAll(commonPasswords);

    final uniquePasswords = passwords.where((p) => p.isNotEmpty).toSet().toList();
    return uniquePasswords;
  }

  /// Try to open PDF with different passwords
  Future<Map<String, dynamic>?> tryOpenPdfWithPasswords({
    required Uint8List pdfBytes,
    required List<String> passwords,
    String? bankName,
    String? userEmail,
    String? fileName,
    Map<String, dynamic>? userProfile,
  }) async {
    for (int i = 0; i < passwords.length; i++) {
      final password = passwords[i];

      try {
        final document = PdfDocument(inputBytes: pdfBytes, password: password);
        ParsingLogger.summary('Password: PDF decrypted successfully using candidate ${i + 1}/${passwords.length}');

        if (bankName != null && userEmail != null) {
          await PasswordLearningService.storeSuccessfulPassword(
            bankName: bankName,
            password: password,
            userEmail: userEmail,
            fileName: fileName,
            userProfile: userProfile,
          );
        }
        return {'document': document, 'password': password};
      } catch (e) {
        continue;
      }
    }

    ParsingLogger.warning('Password: None of the ${passwords.length} automatic candidates decrypted the PDF.');
    return null;
  }

  /// Try to open PDF with a manually provided password
  Future<String?> tryManualPassword({
    required Uint8List pdfBytes,
    required String password,
    String? bankName,
    String? userEmail,
    String? fileName,
    Map<String, dynamic>? userProfile,
  }) async {
    try {
      final document = PdfDocument(inputBytes: pdfBytes, password: password);
      final textExtractor = PdfTextExtractor(document);
      final text = textExtractor.extractText();
      document.dispose();
      ParsingLogger.summary('Password: PDF decrypted successfully using manual password input');

      if (bankName != null && userEmail != null) {
        await PasswordLearningService.storeSuccessfulPassword(
          bankName: bankName,
          password: password,
          userEmail: userEmail,
          fileName: fileName,
          userProfile: userProfile,
        );
      }

      return text;
    } catch (e) {
      return null;
    }
  }

  /// Extract password hints from email content and try to unlock PDF
  Future<String?> findPasswordAndExtractText({
    required Uint8List pdfBytes,
    required String emailSubject,
    required String emailBody,
    required String userEmail,
    required String bankName,
    String? userName,
    Map<String, dynamic>? userProfile,
    String? fileName,
    Future<String?> Function()? onManualPasswordRequired,
  }) async {
    try {
      PasswordInputService.resetAttempts();

      try {
        final document = PdfDocument(inputBytes: pdfBytes);
        final textExtractor = PdfTextExtractor(document);
        final text = textExtractor.extractText();
        document.dispose();
        ParsingLogger.summary('Password: PDF opened without password');
        return text;
      } catch (e) {
        // PDF is encrypted, continue with password detection
      }

      final hints = extractPasswordHints(
        emailSubject: emailSubject,
        emailBody: emailBody,
        userEmail: userEmail,
        userName: userName,
        fileName: fileName,
      );

      final learnedPasswords = await PasswordLearningService.getLearnedPasswordCandidates(
        bankName: bankName,
        userEmail: userEmail,
        userProfile: userProfile,
        fileName: fileName,
      );

      final passwords = generatePasswordCandidates(
        bankName: bankName,
        hints: hints,
        userProfile: userProfile,
      );

      final allPasswords = [...learnedPasswords, ...passwords];
      final uniquePasswords = allPasswords.toSet().toList();

      final result = await tryOpenPdfWithPasswords(
        pdfBytes: pdfBytes,
        passwords: uniquePasswords,
        bankName: bankName,
        userEmail: userEmail,
        fileName: fileName,
        userProfile: userProfile,
      );
      if (result != null) {
        final document = result['document'] as PdfDocument;
        try {
          final textExtractor = PdfTextExtractor(document);
          final text = textExtractor.extractText();
          document.dispose();
          return text;
        } catch (textError) {
          ParsingLogger.error('PDF text extraction failed', textError);
          document.dispose();
          return null;
        }
      }

      if (onManualPasswordRequired != null) {
        ParsingLogger.summary('Password: Automatic decryption failed. Requesting manual password input...');

        for (int attempt = 1; attempt <= 2; attempt++) {
          try {
            ParsingLogger.summary('Password: Manual input attempt $attempt/2 for $bankName');
            final manualPassword = await onManualPasswordRequired();

            if (manualPassword != null && manualPassword.isNotEmpty) {
              ParsingLogger.summary('Password: Manual password received, testing decryption...');
              final result = await tryManualPassword(
                pdfBytes: pdfBytes,
                password: manualPassword,
                bankName: bankName,
                userEmail: userEmail,
                fileName: fileName,
                userProfile: userProfile,
              );
              if (result != null) {
                ParsingLogger.summary('Password: Manual password verification succeeded.');
                return result;
              } else {
                ParsingLogger.warning('Password: Manual password attempt $attempt failed');
              }
            } else {
              ParsingLogger.warning('Password: No manual password provided, user cancelled');
              break;
            }
          } catch (e) {
            ParsingLogger.error('Password: Error during manual decryption attempt', e);
            break;
          }
        }

        ParsingLogger.warning('Password: All manual password attempts exhausted');
      } else {
        ParsingLogger.warning('Password: No manual password callback available');
      }

      return null;
    } catch (error) {
      ParsingLogger.error('Password detection error', error);
      return null;
    }
  }

  String _extractNameFromEmail(String email) {
    final localPart = email.split('@')[0];
    return localPart.replaceAll(RegExp(r'[^a-zA-Z\s]'), ' ').trim();
  }

  /// Generate name and date combination passwords
  List<String> _generateNameDateCombinations(String fullName, Map<String, dynamic>? userProfile) {
    final combinations = <String>[];

    if (fullName.isEmpty) return combinations;

    final nameParts = fullName.trim().split(' ').where((part) => part.isNotEmpty).toList();
    if (nameParts.isEmpty) return combinations;
    final firstName = nameParts[0];
    final firstNameLower = firstName.toLowerCase();
    final firstNameUpper = firstName.toUpperCase();

    final shortNameLower = firstName.length >= 4 ? firstName.toLowerCase().substring(0, 4) : firstNameLower;
    final shortNameUpper = firstName.length >= 4 ? firstName.toUpperCase().substring(0, 4) : firstNameUpper;

    if (userProfile != null && userProfile.containsKey('birthday')) {
      final birthday = userProfile['birthday'] as Map<String, dynamic>;

      final ddmm = birthday['ddmm'] ?? '';
      final ddmmyyyy = birthday['ddmmyyyy'] ?? '';
      final yyyymmdd = birthday['yyyymmdd'] ?? '';
      final ddmmyy = birthday['ddmmyy'] ?? '';

      if (ddmm.isNotEmpty) {
        combinations.add('$shortNameLower$ddmm');
        combinations.add('$shortNameUpper$ddmm');
        combinations.add(ddmm);
      }

      if (ddmmyyyy.isNotEmpty) {
        combinations.add('$shortNameLower$ddmmyyyy');
        combinations.add('$shortNameUpper$ddmmyyyy');
        combinations.add(ddmmyyyy);
      }

      if (ddmmyy.isNotEmpty) {
        combinations.add('$shortNameLower$ddmmyy');
        combinations.add('$shortNameUpper$ddmmyy');
        combinations.add(ddmmyy);
      }

      if (yyyymmdd.isNotEmpty) {
        combinations.add('$shortNameLower$yyyymmdd');
        combinations.add('$shortNameUpper$yyyymmdd');
        combinations.add(yyyymmdd);
      }
    }

    return combinations.toSet().toList();
  }

  /// Extract credit card numbers from filename
  List<String> _extractCardNumberFromFilename(String fileName) {
    final cardNumbers = <String>[];

    final sbiPattern = RegExp(r'(\d{12,20})_\d{8}\.pdf$');
    final sbiMatch = sbiPattern.firstMatch(fileName);
    if (sbiMatch != null) {
      final fullCardNumber = sbiMatch.group(1)!;
      final last4 = fullCardNumber.substring(fullCardNumber.length - 4);
      cardNumbers.add(last4);
    }

    final patterns = [
      RegExp(r'[xX]{4}(\d{4})', caseSensitive: false),
      RegExp(r'(?:ending|last|card)[\s\-_]*(\d{4})', caseSensitive: false),
      RegExp(r'(\d{4})\.pdf$', caseSensitive: false),
      RegExp(r'card[\s\-_]*(\d{4})', caseSensitive: false),
      RegExp(r'statement[\s\-_]*(\d{4})', caseSensitive: false),
      RegExp(r'\b(\d{4})\b'),
    ];
    for (final pattern in patterns) {
      final matches = pattern.allMatches(fileName);
      for (final match in matches) {
        if (match.group(1) != null) {
          final last4 = match.group(1)!;
          if (!cardNumbers.contains(last4)) {
            cardNumbers.add(last4);
          }
        }
      }
    }

    return cardNumbers;
  }
}
```

(Trimmed: dropped `testPasswordGeneration` — a debug/dev-only method for
verifying candidate generation manually, not called by the actual sync flow.)

- [ ] **Step 2: Verify it compiles**

Run: `cd /Users/shantanuchandra/Downloads/Personal/cardcompass-landing-v2 && flutter analyze lib/core/services/pdf_password_detection_service.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/core/services/pdf_password_detection_service.dart
git commit -m "feat: port PdfPasswordDetectionService from main"
```

---

## Task 6: `UserProfileService` and `PdfPasswordResolver` (new orchestration)

**Files:**
- Create: `lib/core/services/user_profile_service.dart`
- Create: `lib/core/services/pdf_password_resolver.dart`

- [ ] **Step 1: Create `user_profile_service.dart`**

```dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Reads and writes the current user's date of birth — from Supabase first,
/// falling back to Google's People API (requires the user.birthday.read
/// OAuth scope, requested at login).
class UserProfileService {
  static Future<DateTime?> getDateOfBirth(String userId) async {
    try {
      final response = await Supabase.instance.client
          .from('users')
          .select('date_of_birth')
          .eq('id', userId)
          .maybeSingle();

      if (response != null && response['date_of_birth'] != null) {
        return DateTime.parse(response['date_of_birth']);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> storeDateOfBirth(String userId, DateTime dob) async {
    try {
      await Supabase.instance.client.from('users').update({
        'date_of_birth': dob.toIso8601String().split('T')[0],
      }).eq('id', userId);
    } catch (_) {
      // Non-fatal: password resolution can proceed with the in-memory DOB
      // even if persisting it for next time fails.
    }
  }

  /// Fetches the user's birthday via Google's People API using the given
  /// OAuth access token. Returns null on any failure (missing scope, no
  /// birthday set on the Google account, network error) — this is one step
  /// in a fallback chain, so it must never throw.
  static Future<DateTime?> getGoogleBirthday(String accessToken) async {
    try {
      final response = await http.get(
        Uri.parse('https://people.googleapis.com/v1/people/me?personFields=birthdays'),
        headers: {'Authorization': 'Bearer $accessToken'},
      );

      if (response.statusCode != 200) return null;

      final decoded = json.decode(response.body) as Map<String, dynamic>;
      final birthdays = decoded['birthdays'] as List<dynamic>?;
      if (birthdays == null || birthdays.isEmpty) return null;

      final date = birthdays.first['date'] as Map<String, dynamic>?;
      if (date == null || date['year'] == null || date['month'] == null || date['day'] == null) {
        return null;
      }

      return DateTime(date['year'] as int, date['month'] as int, date['day'] as int);
    } catch (_) {
      return null;
    }
  }
}
```

- [ ] **Step 2: Create `pdf_password_resolver.dart`**

```dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../app.dart' show navigatorKey;
import 'pdf_password_detection_service.dart';
import 'password_input_service.dart';
import 'simple_birthday_input_service.dart';
import 'user_profile_service.dart';
import 'parsing_logger.dart';

/// Orchestrates unlocking a password-protected statement PDF: cached
/// password -> DB date-of-birth -> Google People API date-of-birth ->
/// DOB-entry dialog -> generated bank-pattern candidates -> manual password
/// dialog (2 attempts). Returns the extracted text, or null if every step
/// fails.
class PdfPasswordResolver {
  final PdfPasswordDetectionService _detectionService = PdfPasswordDetectionService();

  Future<String?> extractText({
    required Uint8List pdfBytes,
    required String bankName,
    required String userId,
    required String userEmail,
    required String userName,
    String? fileName,
    String emailSubject = '',
    String emailBody = '',
  }) async {
    Map<String, dynamic>? userProfile;

    var dob = await UserProfileService.getDateOfBirth(userId);

    if (dob == null) {
      dob = await UserProfileService.getGoogleBirthday(userEmail);
      if (dob != null) {
        await UserProfileService.storeDateOfBirth(userId, dob);
      }
    }

    if (dob == null) {
      final context = navigatorKey.currentContext;
      dob = await SimpleBirthdayInputService.requestBirthdayInput(
        context: context,
        userId: userId,
        reason: 'Unlocking your $bankName statement PDF',
      );
      if (dob != null) {
        await UserProfileService.storeDateOfBirth(userId, dob);
      }
    }

    if (dob != null) {
      userProfile = {'birthday': SimpleBirthdayInputService.formatBirthdayForPasswords(dob)};
    }

    return _detectionService.findPasswordAndExtractText(
      pdfBytes: pdfBytes,
      emailSubject: emailSubject,
      emailBody: emailBody,
      userEmail: userEmail,
      bankName: bankName,
      userName: userName,
      userProfile: userProfile,
      fileName: fileName,
      onManualPasswordRequired: PasswordInputService.createSimpleCallback(bankName),
    );
  }
}

extension on PasswordInputService {
  static Future<String?> Function() createSimpleCallback(String bankName) {
    return () => PasswordInputService.requestPassword(bankName);
  }
}
```

Note: `UserProfileService.getGoogleBirthday` takes an access token, not an
email — the call above passes `userEmail` incorrectly as a placeholder.
Fix this before moving on: `PdfPasswordResolver.extractText` needs the
Google access token too. Update the signature and call site:

```dart
  Future<String?> extractText({
    required Uint8List pdfBytes,
    required String bankName,
    required String userId,
    required String userEmail,
    required String userName,
    required String googleAccessToken,
    String? fileName,
    String emailSubject = '',
    String emailBody = '',
  }) async {
    Map<String, dynamic>? userProfile;

    var dob = await UserProfileService.getDateOfBirth(userId);

    if (dob == null) {
      dob = await UserProfileService.getGoogleBirthday(googleAccessToken);
      if (dob != null) {
        await UserProfileService.storeDateOfBirth(userId, dob);
      }
    }
```

(Keep the rest of the method body as shown above — only the signature and
the `getGoogleBirthday` call argument change.)

Also fix the extension syntax error above (Dart doesn't allow `static` methods
inside an `extension on` block used this way) — replace the whole
`createSimpleCallback` usage with a plain closure inline instead of an
extension:

```dart
      onManualPasswordRequired: () => PasswordInputService.requestPassword(bankName),
```

and delete the `extension on PasswordInputService { ... }` block entirely —
it's not needed.

- [ ] **Step 3: Verify both compile**

Run: `cd /Users/shantanuchandra/Downloads/Personal/cardcompass-landing-v2 && flutter analyze lib/core/services/user_profile_service.dart lib/core/services/pdf_password_resolver.dart`
Expected: `No issues found!` — if you see an error about the extension
syntax, confirm you applied the fix above (deleted the extension, used the
inline closure for `onManualPasswordRequired`).

- [ ] **Step 4: Commit**

```bash
git add lib/core/services/user_profile_service.dart lib/core/services/pdf_password_resolver.dart
git commit -m "feat: add UserProfileService and PdfPasswordResolver orchestration"
```

---

## Task 7: Minimal `AIConfig` and `sendGeminiRequest`

**Files:**
- Create: `lib/core/config/ai_config.dart`
- Create: `lib/core/services/gemini_request_service.dart`

- [ ] **Step 1: Create the minimal `ai_config.dart`**

Only what `gemini_request_service.dart` and the trimmed parser (Task 8)
actually read — no Ollama/Groq provider switching, no persisted runtime
settings, since this project only ever calls Gemini through the
already-deployed `gemini-proxy` Edge Function.

```dart
/// Minimal Gemini configuration — this project always routes through the
/// gemini-proxy Supabase Edge Function (see gemini_request_service.dart),
/// so no API key or multi-provider fallback logic is needed here.
class AIConfig {
  static const String geminiModel = 'gemini-2.0-flash';

  /// True if the response indicates a rate-limit (429) error.
  static bool isRateLimitError(int statusCode, String body) {
    return statusCode == 429;
  }
}
```

- [ ] **Step 2: Create `gemini_request_service.dart`**

Ported as-is (this is the file that calls the already-deployed `gemini-proxy`
Edge Function on web — same Supabase project this worktree already points
at, no new deployment needed):

```dart
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/ai_config.dart';

/// Sends Gemini requests through the authenticated backend on web so provider
/// credentials are never compiled into the public JavaScript bundle.
Future<http.Response> sendGeminiRequest(Map<String, dynamic> payload) async {
  if (kIsWeb) {
    final response = await Supabase.instance.client.functions.invoke(
      'gemini-proxy',
      body: {'model': AIConfig.geminiModel, 'payload': payload},
    );
    return http.Response(
      response.data is String
          ? response.data as String
          : jsonEncode(response.data),
      response.status,
    );
  }

  throw UnsupportedError(
      'sendGeminiRequest is only implemented for web in this project.');
}
```

(This project is web-only, so the non-web branch — which main implements as
a direct API call with a client-side key — is replaced with a clear
`UnsupportedError` rather than porting unreachable code.)

- [ ] **Step 3: Verify both compile**

Run: `cd /Users/shantanuchandra/Downloads/Personal/cardcompass-landing-v2 && flutter analyze lib/core/config/ai_config.dart lib/core/services/gemini_request_service.dart`
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add lib/core/config/ai_config.dart lib/core/services/gemini_request_service.dart
git commit -m "feat: add minimal AIConfig and gemini_request_service routing through gemini-proxy"
```

---

## Task 8: `GeminiStatementParser` (trimmed port)

**Files:**
- Create: `lib/core/services/gemini_statement_parser.dart`

- [ ] **Step 1: Create the file**

```dart
import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'card_normalizer_service.dart';
import 'parsing_logger.dart';
import 'gemini_request_service.dart';
import '../config/ai_config.dart';

/// Parses credit card statement PDF text into structured statement info and
/// transactions via Gemini (through gemini_request_service's proxy call).
/// Trimmed from main's gemini_transaction_parser.dart: drops the
/// Ollama/Groq fallback branches (never configured in this project) and the
/// unrelated card-benefit extraction/repair methods.
class GeminiStatementParser {
  static Future<Map<String, dynamic>> parseStatementInfo({
    required String pdfText,
    required String bankName,
  }) async {
    try {
      final prompt =
          '''You are an expert financial statement analyzer. Extract key information from this credit card statement.

BANK: $bankName
TASK: Extract essential statement details into JSON format.

WHAT TO LOOK FOR:
- Statement/billing period dates
- Payment due dates
- Outstanding/total amount due
- Minimum payment required
- Closing/outstanding balance
- Credit limit information
- Card details (last 4 digits, product name)
- Currency (usually INR for Indian banks)
- Reward/loyalty points earned
- Payments received/credits applied during the statement period

COMMON PATTERNS:
- "Statement Date", "Bill Date", "Statement Period"
- "Due Date", "Payment Due", "Last Date for Payment"
- "Total Amount Due", "Outstanding Amount", "Current Balance"
- "Minimum Payment", "Minimum Amount Due"
- "Credit Limit", "Available Credit"
- Card numbers like "XXXX-XXXX-XXXX-1234"
- "Reward Points", "Points Earned", "Loyalty Points"

JSON OUTPUT (return ONLY this object, no markdown or code blocks):
{
  "statement_date": "YYYY-MM-DD or null",
  "due_date": "YYYY-MM-DD or null",
  "total_amount": number or null,
  "minimum_payment": number or null,
  "closing_balance": number or null,
  "credit_limit": number or null,
  "available_credit": number or null,
  "rewards_earned": number or null,
  "payments_received": number or null,
  "currency": "INR",
  "card_last4": "last 4 digits or null",
  "card_name": "card product name or null",
  "card_type": "credit"
}

ANALYZE THE STATEMENT:''';

      final cleanedText = _pruneAndCleanText(pdfText);
      final requestBody = {
        'contents': [
          {
            'parts': [
              {'text': '$prompt\n\n$cleanedText'}
            ]
          }
        ],
        'generationConfig': {'temperature': 0.1, 'maxOutputTokens': 512}
      };

      final response = await _callGemini(requestBody, maxRetries: 3);

      if (response != null && response.statusCode == 200) {
        final decoded = json.decode(response.body);
        final content = decoded['candidates']?[0]?['content']?['parts']?[0]?['text'];

        if (content != null) {
          try {
            final cleanContent = _extractJsonPayload(content);
            final Map<String, dynamic> result = json.decode(cleanContent);

            final normBank = CardNormalizerService.normalizeBankName(bankName);
            result['bank_name'] = normBank;
            if (result['card_name'] != null) {
              result['card_name'] = CardNormalizerService.normalizeCardName(
                  result['card_name'].toString(), normBank);
            } else {
              result['card_name'] = CardNormalizerService.normalizeCardName(
                  '$normBank Credit Card', normBank);
            }

            ParsingLogger.summary('Gemini Parser: Successfully parsed statement info');
            return result;
          } catch (e) {
            ParsingLogger.error('Gemini Parser: Failed to parse JSON response', e);
          }
        }
      }

      return _fallbackStatementParsing(pdfText, bankName);
    } catch (e) {
      ParsingLogger.error('Gemini Parser: Error parsing statement info', e);
      return _fallbackStatementParsing(pdfText, bankName);
    }
  }

  static Map<String, dynamic> _fallbackStatementParsing(String pdfText, String bankName) {
    final Map<String, dynamic> statementInfo = {};
    statementInfo['bank_name'] = CardNormalizerService.normalizeBankName(bankName);

    final dateMatch = RegExp(r'statement date[:\s]*(\d{2}[-/]\d{2}[-/]\d{4})', caseSensitive: false)
        .firstMatch(pdfText);
    if (dateMatch != null) {
      statementInfo['statement_date'] = _convertDateFormat(dateMatch.group(1)!);
    }

    final dueDateMatch = RegExp(r'due date[:\s]*(\d{2}[-/]\d{2}[-/]\d{4})', caseSensitive: false)
        .firstMatch(pdfText);
    if (dueDateMatch != null) {
      statementInfo['due_date'] = _convertDateFormat(dueDateMatch.group(1)!);
    }

    final amountMatch = RegExp(
            r'total[:\s]*(?:amount|outstanding)[:\s]*(?:rs\.?|₹)?\s*([\d,]+\.?\d*)',
            caseSensitive: false)
        .firstMatch(pdfText);
    if (amountMatch != null) {
      statementInfo['total_amount'] = double.tryParse(amountMatch.group(1)!.replaceAll(',', '')) ?? 0.0;
    }

    statementInfo['currency'] = 'INR';
    statementInfo['card_type'] = 'credit';
    statementInfo['card_name'] =
        CardNormalizerService.normalizeCardName('$bankName Credit Card', statementInfo['bank_name']);

    return statementInfo;
  }

  static String _convertDateFormat(String dateStr) {
    try {
      final parts = dateStr.split(RegExp(r'[-/]'));
      if (parts.length == 3) {
        final day = int.parse(parts[0]);
        final month = int.parse(parts[1]);
        final year = int.parse(parts[2]);
        return DateTime(year, month, day).toIso8601String();
      }
    } catch (e) {
      ParsingLogger.warning('Gemini Parser: Error parsing date $dateStr');
    }
    return DateTime.now().toIso8601String();
  }

  static Future<List<Map<String, dynamic>>> parseTransactions({
    required String pdfText,
    required String bankName,
  }) async {
    try {
      final prompt =
          '''You are an expert at extracting transactions from Indian credit card statements. Analyze this ${bankName.toUpperCase()} statement and extract ALL transactions.

BANK: $bankName

EXTRACTION STRATEGY:
1. Find transaction table sections (look for headers like "Date", "Transaction", "Amount")
2. Extract each row that contains: Date + Description + Amount
3. Skip summary rows, balance rows, and headers
4. Parse amounts carefully - "CR" = credit (+), "D"/"Dr" = debit (-)
5. Clean merchant names (remove codes, URLs, extra numbers)
6. Convert all dates to YYYY-MM-DD format

JSON OUTPUT (return ONLY this array, no markdown blocks):
[
  {
    "date": "YYYY-MM-DD",
    "description": "Clean merchant name without codes",
    "amount": number (positive for credits, negative for debits),
    "currency": "INR",
    "merchantName": "Primary merchant name",
    "category": "shopping|dining|travel|fuel|entertainment|bills|transfer|fee|payment|cash|other",
    "type": "debit|credit",
    "reward_points": number or null (reward/loyalty points earned for this transaction, 0 if none),
    "reference": "transaction reference if clearly visible"
  }
]

ANALYZE THIS STATEMENT:''';

      final cleanedText = _pruneAndCleanText(pdfText);
      final requestBody = {
        'contents': [
          {
            'parts': [
              {'text': '$prompt\n\n$cleanedText'}
            ]
          }
        ],
        'generationConfig': {'temperature': 0.1, 'maxOutputTokens': 8192}
      };

      final response = await _callGemini(requestBody, maxRetries: 3);

      if (response != null && response.statusCode == 200) {
        final decoded = json.decode(response.body);
        final content = decoded['candidates']?[0]?['content']?['parts']?[0]?['text'];

        if (content != null) {
          try {
            final cleanContent = _extractJsonPayload(content);
            final List<dynamic> list = json.decode(cleanContent);

            const uuid = Uuid();
            final transactions = list.map<Map<String, dynamic>>((item) {
              final m = Map<String, dynamic>.from(item);
              m['id'] = m['id'] ?? uuid.v4();
              return m;
            }).toList();

            ParsingLogger.summary('Gemini Parser: Successfully parsed ${transactions.length} transactions');
            return transactions;
          } catch (e) {
            ParsingLogger.error('Gemini Parser: Failed to parse JSON response', e);
          }
        }
      }
      return [];
    } catch (e) {
      ParsingLogger.error('Gemini Parser: Error parsing transactions', e);
      return [];
    }
  }

  /// Call Gemini via the proxy, retrying on 429 with a fixed backoff. Trimmed
  /// from main's _callGeminiWithFallback: no Ollama/Groq branches, no
  /// multi-model fallback chain (this project always uses AIConfig.geminiModel).
  static Future<http.Response?> _callGemini(
    Map<String, dynamic> requestBody, {
    int maxRetries = 3,
  }) async {
    int attempt = 0;

    while (attempt < maxRetries) {
      attempt++;
      try {
        ParsingLogger.summary('Gemini Parser: API call attempt $attempt/$maxRetries');
        final response = await sendGeminiRequest(requestBody);

        if (AIConfig.isRateLimitError(response.statusCode, response.body)) {
          ParsingLogger.warning('Gemini Parser: Rate limit detected (Status: ${response.statusCode})');
          if (attempt < maxRetries) {
            await Future.delayed(const Duration(seconds: 15));
            continue;
          }
          return response;
        }

        return response;
      } catch (e) {
        ParsingLogger.error('Gemini Parser: API call error on attempt $attempt', e);
        if (attempt < maxRetries) {
          await Future.delayed(const Duration(seconds: 10));
        }
      }
    }

    ParsingLogger.error('Gemini Parser: All API attempts exhausted');
    return null;
  }

  /// Trims trailing boilerplate (T&Cs, grievance redressal, branch lists)
  /// from statement text before sending to Gemini, to stay under token
  /// limits, without cutting into the transaction table itself.
  static String _pruneAndCleanText(String text) {
    if (text.isEmpty) return text;

    String cleaned = text.replaceAll(RegExp(r'\n+'), '\n');
    cleaned = cleaned.replaceAll(RegExp(r' {2,}'), ' ');
    cleaned = cleaned.trim();

    final lowerText = cleaned.toLowerCase();
    final markers = [
      'most important terms & conditions',
      'most important terms and conditions',
      'mitc',
      'important information for cardholders',
      'important information',
      'rights of cardholder',
      'cardholder agreement',
      'dispute redressal',
      'grievance redressal',
      'branch addresses',
      'list of branches',
    ];

    final candidateIndexes = <int>[];
    for (final marker in markers) {
      var searchFrom = 0;
      while (true) {
        final idx = lowerText.indexOf(marker, searchFrom);
        if (idx == -1) break;
        candidateIndexes.add(idx);
        searchFrom = idx + marker.length;
      }
    }
    candidateIndexes.sort();

    int bestCutIndex = -1;
    for (final idx in candidateIndexes) {
      if (idx <= 3500) continue;
      final tail = cleaned.substring(idx);
      final leaks = _detectPotentialLeaks(tail);
      if (leaks.isEmpty) {
        bestCutIndex = idx;
        break;
      }
    }

    if (bestCutIndex > 3500) {
      ParsingLogger.summary(
          'Text Pruning: PDF statement text reduced from ${cleaned.length} to $bestCutIndex characters');
      cleaned = cleaned.substring(0, bestCutIndex);
    }

    return cleaned;
  }

  /// Checks whether a candidate boilerplate cut-point's tail still contains
  /// transaction-shaped content (date+amount / merchant+amount lines) — if
  /// so, it's not safe to cut there. Ported from main's
  /// PruningAuditService.detectPotentialLeaks, dropping the Hive-backed
  /// audit-log persistence (not needed here — only the leak check itself).
  static List<Map<String, dynamic>> _detectPotentialLeaks(String removedText) {
    final lines = removedText.split('\n');
    final leaks = <Map<String, dynamic>>[];

    final dateRegex = RegExp(
        r'\b\d{2}[-/.]\d{2}[-/.]\d{2,4}\b|\b\d{2}\s+(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\s+\d{2,4}\b',
        caseSensitive: false);
    final currencyRegex = RegExp(
        r'(?:Rs\.?|₹|INR)\s*[\d,]+\.?\d*|\b[\d,]+\.\d{2}\s*(?:CR|DR|Cr|Dr|C|D)\b',
        caseSensitive: false);
    final merchantRegex = RegExp(
        r'swiggy|zomato|amazon|flipkart|uber|ola|petrol|payment received|paytm|gpay|phonepe|netflix|spotify|interest charged|finance charge',
        caseSensitive: false);

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.length < 15 || line.length > 200) continue;

      final hasDate = dateRegex.hasMatch(line);
      final hasCurrency = currencyRegex.hasMatch(line);
      final hasMerchant = merchantRegex.hasMatch(line);

      if ((hasDate && hasCurrency) || (hasMerchant && hasCurrency)) {
        leaks.add({'lineNumber': i + 1, 'lineContent': line});
      }
    }
    return leaks;
  }

  static String _extractJsonPayload(String text) {
    var trimmed = text.trim();

    // Strip markdown code fences if present (```json ... ``` or ``` ... ```)
    final fenceMatch = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(trimmed);
    if (fenceMatch != null) {
      trimmed = fenceMatch.group(1)!.trim();
    }

    return trimmed;
  }
}
```

Note: `_extractJsonPayload` above is a simplified port — main's version
(`gemini_transaction_parser.dart:1101+`) has more elaborate bracket-matching
logic for edge cases where Gemini's output isn't cleanly fenced. Check
main's actual `_extractJsonPayload` implementation before finalizing this
step (read
`/Users/shantanuchandra/Downloads/Personal/cardcompass/lib/core/services/gemini_transaction_parser.dart`
starting at line 1101 to its end) and port the full version verbatim in
place of the simplified one above, adjusting only the class/method
visibility (`static` on a class method, not a top-level function) to match
this file's structure.

Also add the missing `import 'package:http/http.dart' as http;` at the top
of the file (needed for the `http.Response?` return type in `_callGemini`).

- [ ] **Step 2: Verify it compiles**

Run: `cd /Users/shantanuchandra/Downloads/Personal/cardcompass-landing-v2 && flutter analyze lib/core/services/gemini_statement_parser.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/core/services/gemini_statement_parser.dart
git commit -m "feat: add trimmed GeminiStatementParser calling gemini-proxy"
```

---

## Task 9: Extend `TransactionsRepository`, `StatementsRepository`, `EmailRepository` with insert/upsert methods

**Files:**
- Modify: `lib/core/repositories/transactions_repository.dart`
- Modify: `lib/core/repositories/statements_repository.dart`
- Modify: `lib/core/repositories/email_repository.dart`

Following this project's existing simple-class repository pattern (no
interface layer, `SupabaseClient` passed to constructor) rather than main's
heavier DI-seamed classes.

- [ ] **Step 1: Add `addTransaction` to `TransactionsRepository`**

Read `lib/core/repositories/transactions_repository.dart` first to confirm
current content, then add this method inside the `TransactionsRepository`
class (after the existing methods):

```dart
  /// Insert one transaction. Silently skips if a row with the same
  /// (user_id, user_card_id, transaction_date, description, amount) already
  /// exists — this project's dedup key, matching main's
  /// idx_transactions_dedup unique index.
  Future<void> addTransaction({
    required String userId,
    required String userCardId,
    required double amount,
    required String description,
    required DateTime transactionDate,
    String currency = 'INR',
    String? merchantName,
    String? category,
    String transactionType = 'debit',
    String? location,
    double? rewardEarned,
    String? rewardType,
    String? statementId,
    Map<String, dynamic>? metadata,
  }) async {
    await _db.from('transactions').upsert(
      {
        'user_id': userId,
        'user_card_id': userCardId,
        'amount': amount,
        'description': description,
        'transaction_date': transactionDate.toIso8601String(),
        'currency': currency,
        'merchant_name': merchantName,
        'category': category,
        'transaction_type': transactionType,
        'location': location,
        'reward_earned': rewardEarned,
        'reward_type': rewardType,
        'statement_id': statementId,
        'metadata': metadata,
      },
      onConflict: 'user_id,user_card_id,transaction_date,description,amount',
      ignoreDuplicates: true,
    );
  }
```

- [ ] **Step 2: Add `upsertStatement` to `StatementsRepository`**

Read `lib/core/repositories/statements_repository.dart` first, then add:

```dart
  /// Create or update a statement for one card + statement period. Upserts
  /// on (user_card_id, statement_date) so re-processing the same email is
  /// idempotent, matching this project's statements_user_card_statement_date_key
  /// constraint (see main's SupabaseStatementRepository, same schema).
  Future<Statement> upsertStatement({
    required String userId,
    required String cardId,
    required String userCardId,
    required DateTime statementDate,
    required DateTime dueDate,
    double totalAmount = 0,
    double minimumPayment = 0,
    double closingBalance = 0,
    double availableCredit = 0,
    double rewardsEarned = 0,
    Map<String, dynamic>? metadata,
    int? transactionCount,
  }) async {
    final data = await _db.from('statements').upsert(
      {
        'user_id': userId,
        'card_id': cardId,
        'user_card_id': userCardId,
        'statement_date': statementDate.toIso8601String(),
        'due_date': dueDate.toIso8601String(),
        'total_amount': totalAmount,
        'minimum_payment': minimumPayment,
        'closing_balance': closingBalance,
        'available_credit': availableCredit,
        'rewards_earned': rewardsEarned,
        'payment_status': 'pending',
        'processed': true,
        'metadata': metadata ?? {},
        if (transactionCount != null) 'transaction_count': transactionCount,
      },
      onConflict: 'user_card_id,statement_date',
    ).select().single();
    return Statement.fromJson(data as Map<String, dynamic>);
  }
```

- [ ] **Step 3: Add `getUnprocessedEmails` and confirm `emailExists`/`updateEmailStatus` signatures on `EmailRepository`**

Read `lib/core/repositories/email_repository.dart` (created in slice 1) to
confirm its current content, then add:

```dart
  /// Get emails with attachments that haven't been processed into a
  /// statement yet, for the given user.
  Future<List<Map<String, dynamic>>> getUnprocessedEmails(String userId) async {
    try {
      final response = await _supabase
          .from('emails')
          .select('*')
          .eq('user_id', userId)
          .eq('processed', false)
          .eq('has_attachments', true)
          .order('received_date', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      throw Exception('Failed to fetch unprocessed emails: $e');
    }
  }
```

Also add the matching interface method to
`lib/core/repositories/email_repository_interface.dart`:

```dart
  /// Get emails with attachments that haven't been processed yet
  Future<List<Map<String, dynamic>>> getUnprocessedEmails(String userId);
```

And mark the new `EmailRepository.getUnprocessedEmails` method with
`@override`.

- [ ] **Step 4: Verify everything compiles**

Run: `cd /Users/shantanuchandra/Downloads/Personal/cardcompass-landing-v2 && flutter analyze lib/core/repositories/transactions_repository.dart lib/core/repositories/statements_repository.dart lib/core/repositories/email_repository.dart lib/core/repositories/email_repository_interface.dart`
Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add lib/core/repositories/transactions_repository.dart lib/core/repositories/statements_repository.dart lib/core/repositories/email_repository.dart lib/core/repositories/email_repository_interface.dart
git commit -m "feat: add insert/upsert methods to transactions, statements, email repositories"
```

---

## Task 10: `StatementProcessingService` orchestrator

**Files:**
- Create: `lib/core/services/statement_processing_service.dart`

- [ ] **Step 1: Create the file**

```dart
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../repositories/email_repository.dart';
import '../repositories/statements_repository.dart';
import '../repositories/transactions_repository.dart';
import '../repositories/cards_repository.dart';
import 'gmail_sync_service.dart';
import 'pdf_password_resolver.dart';
import 'gemini_statement_parser.dart';
import 'card_normalizer_service.dart';
import 'parsing_logger.dart';

enum EmailOutcome { succeeded, needsPassword, failed }

class StatementProcessingResult {
  final int totalAttempted;
  final int succeeded;
  final int needsPassword;
  final int failed;

  const StatementProcessingResult({
    required this.totalAttempted,
    required this.succeeded,
    required this.needsPassword,
    required this.failed,
  });
}

/// Processes every unprocessed statement email for a user: downloads the PDF,
/// resolves its password, parses statement info + transactions via Gemini,
/// persists them, and marks the email processed.
class StatementProcessingService {
  final GmailSyncService _gmailService;
  final EmailRepository _emailRepo;
  final StatementsRepository _statementsRepo;
  final TransactionsRepository _transactionsRepo;
  final CardsRepository _cardsRepo;
  final String _userId;
  final String _userEmail;
  final String _userName;

  StatementProcessingService({
    required GmailSyncService gmailService,
    required SupabaseClient supabaseClient,
    required String userId,
    required String userEmail,
    required String userName,
  })  : _gmailService = gmailService,
        _emailRepo = EmailRepository(),
        _statementsRepo = StatementsRepository(supabaseClient),
        _transactionsRepo = TransactionsRepository(supabaseClient),
        _cardsRepo = CardsRepository(supabaseClient),
        _userId = userId,
        _userEmail = userEmail,
        _userName = userName;

  Future<StatementProcessingResult> processUnprocessedEmails() async {
    final emails = await _emailRepo.getUnprocessedEmails(_userId);
    final userCards = await _cardsRepo.getUserCards(_userId);

    var succeeded = 0;
    var needsPassword = 0;
    var failed = 0;

    for (final email in emails) {
      final outcome = await _processOne(email, userCards);
      switch (outcome) {
        case EmailOutcome.succeeded:
          succeeded++;
          break;
        case EmailOutcome.needsPassword:
          needsPassword++;
          break;
        case EmailOutcome.failed:
          failed++;
          break;
      }
    }

    return StatementProcessingResult(
      totalAttempted: emails.length,
      succeeded: succeeded,
      needsPassword: needsPassword,
      failed: failed,
    );
  }

  Future<EmailOutcome> _processOne(
    Map<String, dynamic> email,
    List<dynamic> userCards,
  ) async {
    final emailId = email['email_id'] as String;
    final subject = email['subject'] as String? ?? '';
    final sender = email['sender'] as String? ?? '';
    final metadata = email['metadata'] as Map<String, dynamic>? ?? {};
    final attachmentId = metadata['attachmentId'] as String?;
    final fileName = metadata['attachmentFilename'] as String?;

    if (attachmentId == null) {
      ParsingLogger.warning('Statement Processing: No attachment id for email $emailId, skipping');
      return EmailOutcome.failed;
    }

    final bankName = CardNormalizerService.normalizeBankName(sender.isNotEmpty ? sender : subject);

    dynamic matchedCard;
    for (final card in userCards) {
      if (bankName.toLowerCase().contains(card.bankCode as String) ||
          (card.bankCode as String).contains(bankName.toLowerCase().split(' ').first)) {
        matchedCard = card;
        break;
      }
    }

    Uint8List pdfBytes;
    try {
      pdfBytes = await _gmailService.downloadAttachment(emailId, attachmentId);
    } catch (e) {
      ParsingLogger.error('Statement Processing: Failed to download attachment for $emailId', e);
      return EmailOutcome.failed;
    }

    final resolver = PdfPasswordResolver();
    final googleAccessToken =
        Supabase.instance.client.auth.currentSession?.providerToken ?? '';

    final text = await resolver.extractText(
      pdfBytes: pdfBytes,
      bankName: bankName,
      userId: _userId,
      userEmail: _userEmail,
      userName: _userName,
      googleAccessToken: googleAccessToken,
      fileName: fileName,
      emailSubject: subject,
    );

    if (text == null) {
      await _emailRepo.updateEmailStatus(
        userId: _userId,
        emailId: emailId,
        processed: false,
      );
      return EmailOutcome.needsPassword;
    }

    try {
      final statementInfo = await GeminiStatementParser.parseStatementInfo(
        pdfText: text,
        bankName: bankName,
      );
      final transactions = await GeminiStatementParser.parseTransactions(
        pdfText: text,
        bankName: bankName,
      );

      final userCardId = matchedCard?.id as String? ?? userCards.first.id as String;
      final catalogCardId = matchedCard?.catalogCardId as String? ?? userCards.first.catalogCardId as String;

      final statementDate = statementInfo['statement_date'] != null
          ? DateTime.parse(statementInfo['statement_date'] as String)
          : DateTime.now();
      final dueDate = statementInfo['due_date'] != null
          ? DateTime.parse(statementInfo['due_date'] as String)
          : statementDate.add(const Duration(days: 20));

      final statement = await _statementsRepo.upsertStatement(
        userId: _userId,
        cardId: catalogCardId,
        userCardId: userCardId,
        statementDate: statementDate,
        dueDate: dueDate,
        totalAmount: (statementInfo['total_amount'] as num?)?.toDouble() ?? 0,
        minimumPayment: (statementInfo['minimum_payment'] as num?)?.toDouble() ?? 0,
        closingBalance: (statementInfo['closing_balance'] as num?)?.toDouble() ?? 0,
        availableCredit: (statementInfo['available_credit'] as num?)?.toDouble() ?? 0,
        rewardsEarned: (statementInfo['rewards_earned'] as num?)?.toDouble() ?? 0,
        transactionCount: transactions.length,
      );

      for (final txn in transactions) {
        final amount = (txn['amount'] as num?)?.toDouble() ?? 0;
        final type = txn['type'] as String? ?? 'debit';
        await _transactionsRepo.addTransaction(
          userId: _userId,
          userCardId: userCardId,
          amount: amount.abs(),
          description: txn['description'] as String? ?? 'Unknown transaction',
          transactionDate:
              txn['date'] != null ? DateTime.parse(txn['date'] as String) : statementDate,
          merchantName: txn['merchantName'] as String?,
          category: txn['category'] as String?,
          transactionType: type,
          rewardEarned: (txn['reward_points'] as num?)?.toDouble(),
          statementId: statement.id,
        );
      }

      await _emailRepo.updateEmailStatus(
        userId: _userId,
        emailId: emailId,
        processed: true,
        statementId: statement.id,
      );

      return EmailOutcome.succeeded;
    } catch (e) {
      ParsingLogger.error('Statement Processing: Failed to parse/store statement for $emailId', e);
      return EmailOutcome.failed;
    }
  }
}
```

Note: `email['bank_detected']` is intentionally not written by this method
directly — it's implied by `statement.cardId`'s bank, and
`updateEmailStatus` (from Task 9 / slice 1) only accepts `processed` and
`statementId`. If you want `bank_detected` populated on the `emails` row too,
extend `EmailRepository.updateEmailStatus` to accept an optional
`bankDetected` parameter and pass `bankName` through from `_processOne` —
this is a small addition; do it now for completeness:

In `lib/core/repositories/email_repository.dart`, update the existing
`updateEmailStatus` method signature and body to:

```dart
  Future<void> updateEmailStatus({
    required String userId,
    required String emailId,
    required bool processed,
    String? statementId,
    String? bankDetected,
  }) async {
    try {
      final updateData = <String, dynamic>{'processed': processed};
      if (statementId != null) updateData['statement_id'] = statementId;
      if (bankDetected != null) updateData['bank_detected'] = bankDetected;

      await _supabase
          .from('emails')
          .update(updateData)
          .eq('user_id', userId)
          .eq('email_id', emailId);
    } catch (e) {
      throw Exception('Failed to update email status: $e');
    }
  }
```

And update the matching interface method in `email_repository_interface.dart`:

```dart
  Future<void> updateEmailStatus({
    required String userId,
    required String emailId,
    required bool processed,
    String? statementId,
    String? bankDetected,
  });
```

Then in `statement_processing_service.dart`'s `_processOne`, pass
`bankDetected: bankName` in both `updateEmailStatus` calls (the
`needsPassword` early-return one, and the success one).

- [ ] **Step 2: Verify it compiles**

Run: `cd /Users/shantanuchandra/Downloads/Personal/cardcompass-landing-v2 && flutter analyze lib/core/services/statement_processing_service.dart lib/core/repositories/email_repository.dart lib/core/repositories/email_repository_interface.dart`
Expected: `No issues found!`

If you see an error about `GmailSyncService.downloadAttachment` or
`GmailSearchResult` not having `attachmentId`/`attachmentFilename`, that
means Task 11 (below) hasn't been done yet — do Task 11 first, then come
back and re-verify this task.

- [ ] **Step 3: Commit**

```bash
git add lib/core/services/statement_processing_service.dart lib/core/repositories/email_repository.dart lib/core/repositories/email_repository_interface.dart
git commit -m "feat: add StatementProcessingService orchestrating download, unlock, parse, store"
```

---

## Task 11: Extend `GmailSyncService` with attachment download + metadata capture

**Files:**
- Modify: `lib/core/services/gmail_sync_service.dart`

- [ ] **Step 1: Read the current file**

Read `lib/core/services/gmail_sync_service.dart` (from slice 1) to confirm
its current `GmailSearchResult` class and `_parseMessage`/`_hasPdfAttachment`
methods before editing.

- [ ] **Step 2: Extend `GmailSearchResult` with attachment fields**

Find:

```dart
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
```

Replace with:

```dart
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
```

- [ ] **Step 3: Capture the attachment id/filename in `_parseMessage`/`_hasPdfAttachment`**

Find the `_hasPdfAttachment` method:

```dart
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
```

Replace it with a version that also returns the id/filename it found:

```dart
  ({bool found, String? attachmentId, String? filename}) _findPdfAttachment(
    List<gmail.MessagePart>? parts,
  ) {
    if (parts == null) return (found: false, attachmentId: null, filename: null);
    for (final part in parts) {
      if (part.filename != null &&
          part.filename!.isNotEmpty &&
          part.filename!.toLowerCase().endsWith('.pdf')) {
        return (found: true, attachmentId: part.body?.attachmentId, filename: part.filename);
      }
      final nested = _findPdfAttachment(part.parts);
      if (nested.found) return nested;
    }
    return (found: false, attachmentId: null, filename: null);
  }
```

Then find `_parseMessage`:

```dart
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
```

Replace with:

```dart
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

    final attachment = _findPdfAttachment(message.payload?.parts);

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
```

- [ ] **Step 4: Add `downloadAttachment` to `GmailSyncService`**

Add this method to the `GmailSyncService` class (near `searchStatementEmails`):

```dart
  /// Downloads and base64url-decodes a Gmail attachment's raw bytes.
  Future<Uint8List> downloadAttachment(String messageId, String attachmentId) async {
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
```

Add the needed imports at the top of the file:

```dart
import 'dart:convert';
import 'dart:typed_data';
```

- [ ] **Step 5: Update the `emails` table write to include attachment metadata**

Find where `gmailSyncProvider` (in
`lib/features/dashboard/providers/gmail_sync_provider.dart`) calls
`emailRepo.storeEmail(...)` — currently it doesn't pass `metadata`. Update
that call site to pass the attachment id/filename so
`StatementProcessingService` (Task 10) can read them back later:

```dart
            await emailRepo.storeEmail(
              userId: userId,
              emailId: result.messageId,
              subject: result.subject,
              sender: result.from,
              receivedDate: result.receivedDate,
              hasAttachments: result.hasAttachment,
              metadata: {
                if (result.attachmentId != null) 'attachmentId': result.attachmentId,
                if (result.attachmentFilename != null) 'attachmentFilename': result.attachmentFilename,
              },
            );
```

- [ ] **Step 6: Verify everything compiles**

Run: `cd /Users/shantanuchandra/Downloads/Personal/cardcompass-landing-v2 && flutter analyze lib/core/services/gmail_sync_service.dart lib/features/dashboard/providers/gmail_sync_provider.dart`
Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add lib/core/services/gmail_sync_service.dart lib/features/dashboard/providers/gmail_sync_provider.dart
git commit -m "feat: capture attachment id/filename in Gmail search, add downloadAttachment"
```

---

## Task 12: Wire `StatementProcessingService` into `gmailSyncProvider` and Dashboard

**Files:**
- Modify: `lib/features/dashboard/providers/gmail_sync_provider.dart`
- Modify: `lib/features/dashboard/screens/dashboard_screen.dart`

- [ ] **Step 1: Read the current provider file**

Read `lib/features/dashboard/providers/gmail_sync_provider.dart` (from
slice 1) in full before editing.

- [ ] **Step 2: Extend `GmailSyncResult` with processing counts**

Find:

```dart
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
```

Replace with:

```dart
class GmailSyncResult {
  final int foundCount;
  final int newlyStoredCount;
  final int skippedCount;
  final int failedCount;
  final int processedAttempted;
  final int processedSucceeded;
  final int processedNeedsPassword;
  final int processedFailed;

  const GmailSyncResult({
    required this.foundCount,
    required this.newlyStoredCount,
    required this.skippedCount,
    required this.failedCount,
    this.processedAttempted = 0,
    this.processedSucceeded = 0,
    this.processedNeedsPassword = 0,
    this.processedFailed = 0,
  });
}
```

- [ ] **Step 3: Call `StatementProcessingService` after the email-fetch step**

Add the import at the top:

```dart
import '../../../core/services/statement_processing_service.dart';
import '../../../core/services/gmail_sync_service.dart';
```

Find the end of `syncGmail()`'s try block, where it currently sets:

```dart
        state = AsyncValue.data(GmailSyncResult(
          foundCount: results.length,
          newlyStoredCount: newlyStored,
          skippedCount: skipped,
          failedCount: failed,
        ));
      } finally {
        gmailService.dispose();
      }
```

Replace with (this now runs statement processing using the same
`gmailService` and access token before disposing):

```dart
        final userName =
            session?.user.userMetadata?['full_name'] as String? ?? 'there';

        final processingService = StatementProcessingService(
          gmailService: gmailService,
          supabaseClient: ref.read(supabaseClientProvider),
          userId: userId,
          userEmail: session!.user.email ?? '',
          userName: userName,
        );
        final processingResult = await processingService.processUnprocessedEmails();

        state = AsyncValue.data(GmailSyncResult(
          foundCount: results.length,
          newlyStoredCount: newlyStored,
          skippedCount: skipped,
          failedCount: failed,
          processedAttempted: processingResult.totalAttempted,
          processedSucceeded: processingResult.succeeded,
          processedNeedsPassword: processingResult.needsPassword,
          processedFailed: processingResult.failed,
        ));
      } finally {
        gmailService.dispose();
      }
```

- [ ] **Step 4: Update the Dashboard snackbar to show both stages**

Read `lib/features/dashboard/screens/dashboard_screen.dart`'s
`ref.listen(gmailSyncProvider, ...)` block (added in slice 1) and update the
`data:` case:

Find:

```dart
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
```

Replace with:

```dart
        data: (result) {
          if (result == null) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Found ${result.foundCount} statement emails, ${result.newlyStoredCount} new. '
                'Processed ${result.processedAttempted}: ${result.processedSucceeded} succeeded'
                '${result.processedNeedsPassword > 0 ? ', ${result.processedNeedsPassword} need a password' : ''}'
                '${result.processedFailed > 0 ? ', ${result.processedFailed} failed' : ''}.',
              ),
              duration: const Duration(seconds: 8),
            ),
          );
          ref.invalidate(dashboardProvider);
        },
```

- [ ] **Step 5: Verify everything compiles**

Run: `cd /Users/shantanuchandra/Downloads/Personal/cardcompass-landing-v2 && flutter analyze lib/features/dashboard/providers/gmail_sync_provider.dart lib/features/dashboard/screens/dashboard_screen.dart`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/features/dashboard/providers/gmail_sync_provider.dart lib/features/dashboard/screens/dashboard_screen.dart
git commit -m "feat: wire statement processing into Gmail sync flow and dashboard summary"
```

---

## Task 13: Manual verification in Comet

**Files:** None (verification only).

- [ ] **Step 1: Full analyze pass**

Run: `cd /Users/shantanuchandra/Downloads/Personal/cardcompass-landing-v2 && flutter analyze lib/`
Expected: no errors (pre-existing lint infos/warnings from before this slice
are fine; zero new errors).

- [ ] **Step 2: Rebuild**

```bash
cd /Users/shantanuchandra/Downloads/Personal/cardcompass-landing-v2
flutter build web --dart-define-from-file=dart_defines.json --no-tree-shake-icons
```

Expected: `✓ Built build/web`

- [ ] **Step 3: Restart the static server**

```bash
lsof -ti :54321 | xargs kill -9 2>/dev/null
cd build/web && python3 /tmp/serve_flutter.py &
```

- [ ] **Step 4: Test in Comet**

Using the `mcp__claude-in-chrome__*` tools, navigate to
`http://localhost:54321`, sign out if already signed in (to force a fresh
OAuth consent that includes the new `user.birthday.read` scope), sign back
in with Google, land on the Dashboard, and tap the Sync Gmail icon.

Expected sequence:
1. Email-fetch summary appears first (as in slice 1).
2. Statement processing begins — if no `date_of_birth` is stored yet, a "Date
   of Birth Required" dialog should appear at some point (from
   `SimpleBirthdayInputService`, now properly wired). Provide a real DOB or
   tap Skip to test the degraded path.
3. If auto-generated passwords fail for a bank, a "PDF Password Required"
   dialog should appear (from `PasswordInputService`). Provide the real
   statement password if known, or Cancel to test the `needsPassword` path.
4. Final snackbar reports both fetch and processing summaries.
5. If any statements were processed successfully, the Dashboard should
   refresh (via `ref.invalidate(dashboardProvider)`) and show real KPI
   values, card utilization, and transactions that weren't there before.

- [ ] **Step 5: Verify in Supabase**

Check the `statements` and `transactions` tables for new rows linked to the
signed-in user, and confirm the `emails` table rows that were processed now
have `processed=true`, `bank_detected` populated, and `statement_id` set.

- [ ] **Step 6: Test idempotency**

Tap Sync Gmail again. Expected: the email-fetch stage reports the same
found count with 0 new (already covered by slice 1's dedup). The processing
stage should report 0 attempted (since `getUnprocessedEmails` now excludes
everything marked `processed=true` from the first run) — confirming
re-running sync doesn't re-parse or duplicate any statements/transactions.

---

## Self-Review Notes

- **Spec coverage:** All 8 components from the design spec have a
  corresponding task (Tasks 3–4 cover component 2/3's dialogs, Task 5 covers
  component 3's detection service, Task 6 covers components 2's DOB
  resolution + a new orchestrator not explicitly numbered in the spec but
  implied by "PdfPasswordResolver" in the design's component list, Task 7–8
  cover component 4, Task 9 covers component 5 adapted to this project's
  simpler repository pattern, Task 10 covers component 6, Task 11 extends
  slice 1's `GmailSyncService` for attachment download per component 1,
  Task 12 covers component 7, Task 2 covers component 8). The known gaps
  section of the spec (no retry UI, no progress indicator, no audit trail,
  token expiry) is intentionally left unimplemented, matching the spec's
  explicit scope boundary.
- **Placeholder scan:** No TBD/TODO markers. Task 8's note about
  `_extractJsonPayload` needing the full version ported from main (rather
  than the simplified one shown) is a real, actionable instruction with a
  specific file:line pointer — not a placeholder, since it tells the
  implementer exactly what to do and why.
- **Type consistency:** `GmailSearchResult`'s new `attachmentId`/
  `attachmentFilename` fields (Task 11) are read by name in
  `StatementProcessingService._processOne` via the `emails.metadata` map
  (Task 10) — verified the key names (`attachmentId`, `attachmentFilename`)
  match between where they're written (Task 11 Step 5) and read (Task 10).
  `PdfPasswordResolver.extractText`'s parameter list (Task 6, after the
  fix) matches its call site in `StatementProcessingService` (Task 10) —
  both use `googleAccessToken` as the parameter name.
  `EmailRepository.updateEmailStatus`'s `bankDetected` parameter (added in
  Task 10's note) is consistently passed at both call sites in
  `_processOne`. `StatementsRepository.upsertStatement`'s return type
  (`Statement`) matches how it's used in `_processOne`
  (`statement.id` passed to `addTransaction`'s `statementId` and to
  `updateEmailStatus`'s `statementId`).
