# Gmail Sync Cross-Route Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ensure a successful Gmail statement sync immediately refreshes Dashboard, Cards, and Transactions from persisted Supabase data, including after navigation and reload.

**Architecture:** Keep the existing repositories and sync pipeline unchanged. Add one feature-level refresh coordinator that owns invalidation of every provider backed by imported statement data, then call it from each successful import/card-resolution path so the persistent `IndexedStack` cannot retain pre-sync empty results.

**Tech Stack:** Flutter, Dart, Riverpod 2, GoRouter, Supabase, `flutter_test`

**Spec:** Live QA observation on 2026-08-18: seven-day Gmail sync found 6 new statement emails and processed 6/6 successfully; Dashboard showed six cards and imported transactions, while Cards and Transactions retained their pre-sync empty states.

## Global Constraints

- Preserve existing account scoping and Supabase RLS; do not alter database rows or migrations for this UI cache defect.
- Preserve the successful Gmail OAuth, discovery, PDF parsing, persistence, and dashboard aggregation paths.
- Do not expose Gmail tokens, statement contents, card numbers, or other private data in logs or tests.
- Use test-driven development: demonstrate stale provider state first, then implement the smallest shared invalidation fix.
- Preserve unrelated working-tree changes in card detail and dashboard presentation files.

---

## File Structure

- Create `lib/features/dashboard/providers/imported_data_refresh_provider.dart`: one coordinator responsible only for invalidating imported-data projections.
- Create `test/features/dashboard/imported_data_refresh_provider_test.dart`: provider-container regression tests proving all projections reload together.
- Modify `lib/features/dashboard/screens/dashboard_screen.dart`: invoke the coordinator after successful Gmail sync and successful manual card resolution.
- Modify `lib/features/settings/screens/settings_screen.dart`: reuse the coordinator after account-scoped reset, retaining Gmail sync-state invalidation separately.
- Modify `test/features/dashboard/dashboard_brand_test.dart`: widget-level assertion that a terminal sync result calls the shared refresh boundary once.

### Task 1: Capture the Stale-Provider Regression

**Files:**
- Create: `test/features/dashboard/imported_data_refresh_provider_test.dart`

**Interfaces:**
- Consumes: `dashboardProvider`, `userCardsProvider`, `txnsNotifierProvider`, and `pendingCardAssignmentsProvider`.
- Produces: a failing contract requiring one callable refresh boundary to invalidate all four providers.

- [ ] **Step 1: Write a failing provider-container test**

Define load counters and overrides for all four providers. Read each provider once to simulate `_AppShell` eagerly building its persistent `IndexedStack`, call the not-yet-created `importedDataRefreshProvider`, read each provider again, and assert every counter advances from `1` to `2`.

```dart
final container = ProviderContainer(overrides: [
  dashboardProvider.overrideWith((ref) async {
    dashboardLoads++;
    return emptyDashboardData;
  }),
  userCardsProvider.overrideWith((ref) async {
    cardsLoads++;
    return const [];
  }),
  txnsNotifierProvider.overrideWith(CountingTxnsNotifier.new),
  pendingCardAssignmentsProvider.overrideWith((ref) async {
    pendingLoads++;
    return const [];
  }),
]);

await Future.wait([
  container.read(dashboardProvider.future),
  container.read(userCardsProvider.future),
  container.read(txnsNotifierProvider.future),
  container.read(pendingCardAssignmentsProvider.future),
]);

container.read(importedDataRefreshProvider)();

await Future.wait([
  container.read(dashboardProvider.future),
  container.read(userCardsProvider.future),
  container.read(txnsNotifierProvider.future),
  container.read(pendingCardAssignmentsProvider.future),
]);

expect((dashboardLoads, cardsLoads, txnLoads, pendingLoads), (2, 2, 2, 2));
```

- [ ] **Step 2: Run the test and verify the missing coordinator fails compilation**

Run: `flutter test test/features/dashboard/imported_data_refresh_provider_test.dart`

Expected: FAIL because `importedDataRefreshProvider` does not exist.

- [ ] **Step 3: Commit the red test**

```bash
git add test/features/dashboard/imported_data_refresh_provider_test.dart
git commit -m "test: capture stale views after statement sync"
```

### Task 2: Add One Imported-Data Refresh Boundary

**Files:**
- Create: `lib/features/dashboard/providers/imported_data_refresh_provider.dart`
- Test: `test/features/dashboard/imported_data_refresh_provider_test.dart`

**Interfaces:**
- Consumes: Riverpod `Ref.invalidate` for the four imported-data projections.
- Produces: `typedef ImportedDataRefresh = void Function();` and `final importedDataRefreshProvider = Provider<ImportedDataRefresh>(...)`.

- [ ] **Step 1: Implement the minimal coordinator**

```dart
typedef ImportedDataRefresh = void Function();

final importedDataRefreshProvider = Provider<ImportedDataRefresh>((ref) {
  return () {
    ref.invalidate(dashboardProvider);
    ref.invalidate(userCardsProvider);
    ref.invalidate(txnsNotifierProvider);
    ref.invalidate(pendingCardAssignmentsProvider);
  };
});
```

Keep this in the dashboard feature because it coordinates dashboard-owned Gmail import results with downstream feature projections; do not move feature imports into `lib/core`.

- [ ] **Step 2: Run the focused provider test**

Run: `flutter test test/features/dashboard/imported_data_refresh_provider_test.dart`

Expected: PASS with all four provider load counters equal to `2`.

- [ ] **Step 3: Commit the coordinator**

```bash
git add lib/features/dashboard/providers/imported_data_refresh_provider.dart test/features/dashboard/imported_data_refresh_provider_test.dart
git commit -m "fix: refresh imported data across app routes"
```

### Task 3: Wire Every Successful Import Mutation to the Coordinator

**Files:**
- Modify: `lib/features/dashboard/screens/dashboard_screen.dart:164-190`
- Modify: `lib/features/dashboard/screens/dashboard_screen.dart:1748-1770`
- Modify: `lib/features/settings/screens/settings_screen.dart:34-46`
- Modify: `test/features/dashboard/dashboard_brand_test.dart`

**Interfaces:**
- Consumes: `ImportedDataRefresh` from Task 2.
- Produces: consistent refresh behavior after Gmail sync, manual statement-to-card resolution, and account reset.

- [ ] **Step 1: Add a widget regression test for terminal sync completion**

Add a controllable `GmailSyncNotifier` test double whose `complete` method publishes a successful `GmailSyncResult`. Override `importedDataRefreshProvider` with a callback counter, pump `DashboardScreen`, publish the result, and assert the callback is invoked once.

```dart
class CompletingGmailSyncNotifier extends GmailSyncNotifier {
  @override
  Future<GmailSyncResult?> build() async => null;

  void complete() {
    state = const AsyncData(
      GmailSyncResult(
        foundCount: 1,
        newlyStoredCount: 1,
        skippedCount: 0,
        failedCount: 0,
        processedAttempted: 1,
        processedSucceeded: 1,
      ),
    );
  }
}
```

Run: `flutter test test/features/dashboard/dashboard_brand_test.dart --plain-name "successful sync refreshes every imported-data projection once"`

Expected: FAIL because the screen still invalidates only dashboard and pending-assignment providers directly.

- [ ] **Step 2: Replace the sync listener’s partial invalidations**

In the non-null success branch of `ref.listen(gmailSyncProvider, ...)`, replace the two direct invalidations with:

```dart
ref.read(importedDataRefreshProvider)();
```

Do not call it for `result == null` or error states.

- [ ] **Step 3: Refresh all projections after manual card resolution**

Capture or read the same callback after `await resolveCard(...)` succeeds and replace `container.invalidate(dashboardProvider)` with the shared callback. This covers newly created `user_cards`, the reprocessed statement, and inserted transactions.

- [ ] **Step 4: Reuse the coordinator after reset**

After `UserDataRepository.resetAll()` succeeds, call `ref.read(importedDataRefreshProvider)()` and retain `ref.invalidate(gmailSyncProvider)` to clear the last sync result. Remove the now-duplicated direct invalidations for dashboard, cards, transactions, and pending assignments.

- [ ] **Step 5: Run focused UI and provider tests**

Run:

```bash
flutter test test/features/dashboard/imported_data_refresh_provider_test.dart
flutter test test/features/dashboard/dashboard_brand_test.dart
flutter test test/features/cards/cards_brand_test.dart test/features/transactions/transactions_ux_test.dart
```

Expected: all pass; the successful-sync test records exactly one coordinator call.

- [ ] **Step 6: Commit the wiring**

```bash
git add lib/features/dashboard/screens/dashboard_screen.dart lib/features/settings/screens/settings_screen.dart test/features/dashboard/dashboard_brand_test.dart
git commit -m "fix: reload cards and transactions after Gmail sync"
```

### Task 4: Verify the Complete Seven-Day Flow

**Files:**
- No production file changes expected.

**Interfaces:**
- Consumes: completed implementation from Tasks 1-3 and the existing authenticated internal-browser session.
- Produces: automated and live evidence that persisted imports appear consistently across routes.

- [ ] **Step 1: Run static and automated verification**

Run:

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build web --release --base-href /app/
```

Expected: formatting clean, analyzer clean, full suite passes, and release web build succeeds.

- [ ] **Step 2: Start or refresh the local release server safely**

Serve the newly built `build/web` through the existing local app workflow on port `8080`; do not deploy, push, or create a PR.

- [ ] **Step 3: Establish an empty baseline without deleting data**

Use a test fixture/account reset only if separately authorized. For the current account, do not clear or re-import again merely to test invalidation; first verify the already imported six-statement dataset after loading the rebuilt app.

- [ ] **Step 4: Verify all projections on the existing dataset**

Freshly load Dashboard, Cards, and Transactions and record:

- Dashboard card count equals Cards page count.
- Dashboard recent transactions are present in the Transactions ledger.
- Dashboard spend/reward aggregates equal the ledger’s active-period totals under existing debit/credit/refund rules.
- Reloading each route preserves the same records.

- [ ] **Step 5: Run one additional seven-day sync only if needed**

If the existing data cannot exercise transition from cached empty state, use the supported account reset only with renewed user authorization; otherwise test idempotent re-sync and expect `0 new` with no duplicate cards, statements, or transactions.

- [ ] **Step 6: Keep the browser persistent and report evidence**

Leave the internal browser open on the Cards page showing the imported cards. Report sync outcome, route counts, aggregate reconciliation, automated verification, and any remaining blocker without exposing financial details beyond user-visible aggregate values.

## Self-Review

- Spec coverage: the plan addresses the proven cache invalidation gap, all mutation entry points, provider-level regression, widget integration, route persistence, and full live verification.
- Placeholder scan: no deferred implementation items or unspecified error-handling steps remain.
- Type consistency: the coordinator is consistently named `ImportedDataRefresh` / `importedDataRefreshProvider`; every consumer invokes the zero-argument callback once after successful mutation.

