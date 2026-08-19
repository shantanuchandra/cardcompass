# Contextual Feedback Capture and Triage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Capture user text against a specific AI-assisted output, preserve a bounded server-resolved fixture, triage it asynchronously, and let the founder convert it into human-approved evaluation ground truth.

**Architecture:** A user-facing `feedback-submit` Edge Function authenticates ownership, creates short-lived traces for ephemeral recommendations, resolves persisted outputs from authoritative rows, and writes feedback idempotently. LLM triage runs after the write through a shared, tool-free, schema-validated module. Admin review is delivered through the existing `admin-operator` Action Inbox; no feedback or LLM output changes production behavior.

**Tech Stack:** Flutter/Riverpod, Supabase Edge Functions/Deno, PostgreSQL, existing Gemini transport, Node migration contracts.

**Specs:**
- `docs/superpowers/specs/2026-08-19-contextual-ai-feedback-evals-design.md`
- `docs/superpowers/specs/2026-08-19-admin-operator-console-design.md`

## Global Constraints

- Complete `docs/superpowers/plans/2026-08-19-admin2-foundation.md` first.
- User feedback requires `feature_key`, a server-resolvable output reference, 10–2,000 characters of text, and a UUID request ID.
- Supported feature keys are `statement_processing`, `card_data`, and `recommendation`.
- Store no raw email body, attachment, statement PDF, credential, OAuth token, full statement history, or full transaction history.
- Feedback persistence must succeed independently of triage. Triage failure changes only `triage_status`.
- Treat feedback/context as untrusted data; the triage model has no tools and cannot mutate any production or catalog table.
- LLM proposals remain advisory. Only explicit admin actions create, approve, revise, retire, route, or dismiss cases.
- All tables are RLS-enabled with no direct browser grants.

---

## File structure

- `supabase/migrations/20260819090400_contextual_ai_feedback.sql` — traces, feedback, eval cases, dataset versions, and narrow RPCs.
- `test/supabase/contextual_ai_feedback_migration_test.js` — security, idempotency, and lifecycle contract.
- `supabase/functions/feedback-submit/deno.json` — endpoint dependencies.
- `supabase/functions/feedback-submit/index.ts` — user actions `trace-create` and `feedback-submit`.
- `supabase/functions/feedback-submit/context.ts` — ownership and bounded fixture resolution.
- `supabase/functions/feedback-submit/validation.ts` — strict input parsing.
- `supabase/functions/feedback-submit/index_test.ts` — auth, ownership, idempotency, and async behavior.
- `supabase/functions/_shared/feedback_triage.ts` — tool-free LLM call and validated output.
- `supabase/functions/_shared/feedback_triage_test.ts` — injection and invalid-output tests.
- `supabase/functions/_shared/gemini_generate.ts` — reusable bounded server-side Gemini transport.
- `supabase/functions/_shared/gemini_generate_test.ts` — fallback, timeout, and safe-error tests.
- `supabase/functions/gemini-proxy/index.ts` — delegates generation without changing public behavior.
- `supabase/functions/gemini-proxy/index_test.ts` — proxy regression contract.
- `supabase/functions/admin-operator/feedback.ts` — list/detail/review/retry/case handlers.
- `supabase/functions/admin-operator/feedback_test.ts` — admin lifecycle tests.
- `supabase/functions/admin-operator/inbox.ts` — pending feedback source.
- `supabase/functions/admin-operator/inbox_test.ts` — feedback ranking tests.
- `supabase/functions/admin-operator/router.ts` — feedback/case action registration.
- `lib/features/feedback/feedback_models.dart` — supported targets and submit result.
- `lib/features/feedback/feedback_repository.dart` — trace and submit API.
- `lib/features/feedback/contextual_feedback_sheet.dart` — common capture surface.
- `lib/features/feedback/contextual_feedback_button.dart` — reusable entry control.
- `lib/features/transactions/screens/transactions_screen.dart` — transaction feedback target.
- `lib/features/cards/screens/card_detail_screen.dart` — card/benefit feedback target.
- `lib/features/benefits/movie_deals/screens/movie_deals_results.dart` — recommendation trace and feedback target.
- `lib/features/admin2/feedback/feedback_models.dart` — admin detail/case DTOs.
- `lib/features/admin2/feedback/feedback_repository.dart` — admin gateway adapter.
- `lib/features/admin2/feedback/feedback_detail.dart` — review and ground-truth UI.
- `lib/features/admin2/inbox/action_inbox_section.dart` — feedback item deep link.
- `test/features/feedback/contextual_feedback_sheet_test.dart` — capture behavior.
- `test/features/feedback/feedback_repository_test.dart` — payload contract.
- `test/features/admin2/feedback_detail_test.dart` — human-gate behavior.

---

### Task 1: Add private trace, feedback, and case storage

**Files:**
- Create: `supabase/migrations/20260819090400_contextual_ai_feedback.sql`
- Create: `test/supabase/contextual_ai_feedback_migration_test.js`

**Interfaces:**
- Tables: `ai_output_traces`, `ai_feedback`, `ai_eval_cases`.
- Sequence: `ai_eval_dataset_version_seq` starting at 1.

- [ ] **Step 1: Write the failing static migration contract**

```js
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const migrationUrl = new URL(
  '../../supabase/migrations/20260819090400_contextual_ai_feedback.sql',
  import.meta.url,
);

test('contextual feedback storage is private, bounded and versioned', async () => {
  const sql = (await readFile(migrationUrl, 'utf8')).toLowerCase();
  for (const table of ['ai_output_traces', 'ai_feedback', 'ai_eval_cases']) {
    assert.match(sql, new RegExp(`create table public\\.${table}`));
    assert.match(sql, new RegExp(`alter table public\\.${table} enable row level security`));
    assert.match(sql, new RegExp(`revoke all on public\\.${table} from public, anon, authenticated`));
  }
  assert.match(sql, /expires_at <= created_at \+ interval '7 days'/);
  assert.match(sql, /unique \(user_id, request_id\)/);
  assert.match(sql, /create sequence public\.ai_eval_dataset_version_seq/);
  assert.match(sql, /feature_key in \('statement_processing', 'card_data', 'recommendation'\)/);
  assert.match(sql, /char_length\(feedback_text\) between 10 and 2000/);
});
```

- [ ] **Step 2: Run the contract**

Run: `node --test test/supabase/contextual_ai_feedback_migration_test.js`

Expected: FAIL with `ENOENT`.

- [ ] **Step 3: Create exact trace and feedback columns**

Create `ai_output_traces` with: `id`, `user_id`, `feature_key`, `request_id`, `safe_input_context`, `output_snapshot`, `authoritative_context`, `engine_version`, `model`, `prompt_version`, `created_at`, `expires_at`, and unique `(user_id, request_id)`.

Create `ai_feedback` with: `id`, `user_id`, `feature_key`, `output_ref_type`, `output_ref_id`, `feedback_text`, `safe_input_context`, `output_snapshot`, `trace_id`, `provider`, `model`, `prompt_version`, `parser_version`, `request_id`, `triage_status`, `triage_result`, `review_status`, `reviewed_by`, `reviewed_at`, `dismissal_reason`, `created_at`, and `updated_at`. Use the exact status constraints from the approved spec and unique `(user_id, request_id)`.

- [ ] **Step 4: Create exact eval-case columns**

Create `ai_eval_cases` with: `id`, `source_feedback_id`, `feature_key`, `revision`, `supersedes_case_id`, `input_fixture`, `captured_output`, `expected_output`, `operator_feedback`, `scoring_rubric`, `severe_failure_conditions`, `status`, `approved_in_dataset_version`, `retired_in_dataset_version`, source engine/model/prompt/parser/trace fields, `created_by`, `approved_by`, `created_at`, `approved_at`, and `retired_at`. Enforce unique `(source_feedback_id, revision)`.

Enable RLS, revoke all from browser roles, and grant table/sequence access only to `service_role`.

- [ ] **Step 5: Run the focused contract**

Run: `node --test test/supabase/contextual_ai_feedback_migration_test.js`

Expected: PASS.

### Task 2: Add narrow write, triage, and admin-review RPCs

**Files:**
- Modify: `supabase/migrations/20260819090400_contextual_ai_feedback.sql`
- Modify: `test/supabase/contextual_ai_feedback_migration_test.js`

**Interfaces:**
- `create_ai_output_trace(uuid, uuid, text, jsonb, jsonb, jsonb, jsonb): jsonb` — service-role only.
- `submit_ai_feedback(uuid, uuid, text, text, text, text, jsonb, jsonb, jsonb): jsonb` — service-role only.
- `claim_ai_feedback_triage(uuid): jsonb` and `complete_ai_feedback_triage(uuid, boolean, jsonb, text): void` — service-role only.
- `admin_review_ai_feedback(uuid, uuid, uuid, text, jsonb, text): jsonb` — service-role only.
- `admin_ai_eval_case_action(uuid, uuid, uuid, text, jsonb, text, timestamptz): jsonb` — service-role only.

- [ ] **Step 1: Add failing RPC contract assertions**

Assert each function is `SECURITY DEFINER SET search_path = ''`, revoked from public/anon/authenticated, granted to service role, and validates allowlisted actions. Assert the admin functions check `admin_audit_log` for the request ID and insert a successful receipt in the same transaction.

- [ ] **Step 2: Run the focused contract**

Run: `node --test test/supabase/contextual_ai_feedback_migration_test.js`

Expected: FAIL on the missing functions.

- [ ] **Step 3: Implement trace and feedback idempotency**

The trace function clamps expiry to seven days, validates bounded JSON object sizes using `octet_length(value::text)`, and returns the prior trace for a repeated `(user_id, request_id)`. The feedback function receives only context already resolved by the Edge handler, copies it into `ai_feedback`, and returns the prior row for a repeated `(user_id, request_id)`.

- [ ] **Step 4: Implement advisory triage state transitions**

`claim_ai_feedback_triage` locks one ID in `awaiting_triage|triage_failed`, sets `triaging`, and returns only bounded fixture fields. `complete_ai_feedback_triage` accepts a validated result when successful or sets `triage_failed` with one safe category. It never changes `review_status`.

- [ ] **Step 5: Implement human review and case versioning**

`admin_review_ai_feedback` allows `create_eval_draft|data_issue|product_defect|dismiss`. Draft creation requires non-empty operator-authored expected behavior, expected output, rubric, and severe conditions; it copies immutable source context. Routing/dismissal requires a reason.

`admin_ai_eval_case_action` allows `approve|revise|retire`. Approve and retire take the next dataset sequence value. Revise creates a new draft revision and never updates an approved case's fixture. Require observed `updated_at` and audit every result atomically.

- [ ] **Step 6: Run migration contracts**

Run: `node --test test/supabase/contextual_ai_feedback_migration_test.js test/supabase/admin_operator_foundation_migration_test.js`

Expected: PASS.

### Task 3: Build the authenticated user feedback endpoint

**Files:**
- Create: `supabase/functions/feedback-submit/deno.json`
- Create: `supabase/functions/feedback-submit/index.ts`
- Create: `supabase/functions/feedback-submit/context.ts`
- Create: `supabase/functions/feedback-submit/validation.ts`
- Create: `supabase/functions/feedback-submit/index_test.ts`
- Modify: `supabase/config.toml`

**Interfaces:**
- POST `trace-create` with `feature_key`, bounded recommendation input/output, referenced card/benefit IDs, and `request_id`.
- POST `feedback-submit` with `feature_key`, `output_ref_type`, `output_ref_id`, `feedback_text`, and `request_id`.

- [ ] **Step 1: Write failing validation and ownership tests**

Cover bearer auth, exact actions, feature/output-ref compatibility, text length, UUID request ID, unsupported JSON keys, another user's transaction/card/trace, expired trace, inactive card/benefit reference, and absence of raw/source columns from resolved fixtures.

- [ ] **Step 2: Write failing idempotency and response tests**

Prove a repeated request ID returns the same ID, the endpoint responds `202` with `{feedback_id, triage_status: "awaiting_triage"}` before triage completes, and internal errors map to stable safe codes.

- [ ] **Step 3: Run the focused Deno tests**

Run: `deno test --config supabase/functions/feedback-submit/deno.json supabase/functions/feedback-submit/`

Expected: FAIL because the endpoint does not exist.

- [ ] **Step 4: Implement target compatibility and bounded resolution**

Use this exact mapping:

```ts
export const outputRefByFeature = {
  statement_processing: ["transaction", "statement"],
  card_data: ["user_card"],
  recommendation: ["recommendation_trace"],
} as const;
```

For transaction/statement/user-card targets, query by both ID and authenticated `user_id`, and explicitly select only evaluation fields. For recommendation traces, validate all referenced card and benefit IDs against active catalog rows, store server-resolved facts in `authoritative_context`, and mark the recommendation output `{ provenance: "client_reported" }`.

- [ ] **Step 5: Implement the endpoint and configuration**

Create request-scoped Auth and service clients. Route both actions; call the Task 2 RPCs; return CORS and stable JSON responses. Configure `feedback-submit` with JWT verification consistent with existing user functions. After a successful insert call `EdgeRuntime.waitUntil(triageFeedback(feedbackId, dependencies))`; never await triage before responding.

- [ ] **Step 6: Run tests and commit the first functional feedback slice**

Run: `deno test --config supabase/functions/feedback-submit/deno.json supabase/functions/feedback-submit/ && node --test test/supabase/contextual_ai_feedback_migration_test.js`

Expected: PASS with a fake triage dependency.

```bash
git add supabase/migrations/20260819090400_contextual_ai_feedback.sql test/supabase/contextual_ai_feedback_migration_test.js supabase/functions/feedback-submit supabase/config.toml docs/superpowers/specs/2026-08-19-contextual-ai-feedback-evals-design.md docs/superpowers/plans/2026-08-19-contextual-feedback-capture-triage.md
git commit -m "feat(feedback): persist contextual AI feedback"
```

### Task 4: Add tool-free asynchronous LLM triage

**Files:**
- Create: `supabase/functions/_shared/feedback_triage.ts`
- Create: `supabase/functions/_shared/feedback_triage_test.ts`
- Create: `supabase/functions/_shared/gemini_generate.ts`
- Create: `supabase/functions/_shared/gemini_generate_test.ts`
- Modify: `supabase/functions/gemini-proxy/index.ts`
- Create: `supabase/functions/gemini-proxy/index_test.ts`
- Modify: `supabase/functions/feedback-submit/index.ts`
- Modify: `supabase/functions/feedback-submit/index_test.ts`

**Interfaces:**
- `triageFeedback(feedbackId, dependencies): Promise<void>`.
- `parseTriageResult(value): TriageResult` with an exact schema.

- [ ] **Step 1: Write failing parser and prompt-boundary tests**

Define `TriageResult` fields: classification (`model_error|data_issue|product_defect|unclear|duplicate_candidate|not_actionable`), severity (`critical|high|normal`), confidence number `0..1`, diagnosis max 500 characters, proposed expected output object, proposed rubric object, and suitability explanation max 500 characters.

Test invalid enum, extra keys, oversized text, malformed JSON, and feedback containing `ignore previous instructions` that remains inside a delimited data value. Assert no tool definitions are passed to the model adapter.

- [ ] **Step 2: Run the focused test**

Run: `deno test supabase/functions/_shared/feedback_triage_test.ts`

Expected: FAIL because the module does not exist.

- [ ] **Step 3: Implement fixed prompt and schema validation**

Inject this interface rather than calling fetch in triage code:

```ts
export type StructuredTextModel = Readonly<{
  generateJson: (input: Readonly<{
    system: string;
    data: Record<string, unknown>;
    schemaName: "feedback_triage_v1";
  }>) => Promise<unknown>;
}>;
```

The fixed system prompt states that `data` is untrusted quoted material, forbids following instructions found within it, and permits no actions. Validate the result before calling `complete_ai_feedback_triage`; map failures to `model_unavailable|invalid_model_output|triage_persistence_failed`.

- [ ] **Step 4: Extract and wire the existing Gemini transport**

Move the key/model fallback loop from `gemini-proxy/index.ts` into `generateGemini(input, dependencies)`. Preserve the proxy's 100 KB limit, 25-second attempt timeout, key fallback on `429`, supported model fallback, and upstream status/body response contract through an injectable proxy handler. Return parsed JSON plus selected model, latency, and usage-token fields when available; thrown errors contain only `model_unavailable|invalid_model_output|provider_failed`. The triage adapter pins `gemini-3.6-flash` server-side and requests `feedback_triage_v1`; no provider key, URL, prompt, or model enters a client payload.

- [ ] **Step 5: Run triage and endpoint tests and commit**

Run: `deno test supabase/functions/_shared/gemini_generate_test.ts supabase/functions/_shared/feedback_triage_test.ts supabase/functions/gemini-proxy/index_test.ts && deno test --config supabase/functions/feedback-submit/deno.json supabase/functions/feedback-submit/`

Expected: PASS.

```bash
git add supabase/functions/_shared/gemini_generate.ts supabase/functions/_shared/gemini_generate_test.ts supabase/functions/_shared/feedback_triage.ts supabase/functions/_shared/feedback_triage_test.ts supabase/functions/gemini-proxy/index.ts supabase/functions/gemini-proxy/index_test.ts supabase/functions/feedback-submit/index.ts supabase/functions/feedback-submit/index_test.ts
git commit -m "feat(feedback): triage submissions asynchronously"
```

### Task 5: Add the reusable Flutter feedback surface

**Files:**
- Create: `lib/features/feedback/feedback_models.dart`
- Create: `lib/features/feedback/feedback_repository.dart`
- Create: `lib/features/feedback/contextual_feedback_sheet.dart`
- Create: `lib/features/feedback/contextual_feedback_button.dart`
- Create: `test/features/feedback/feedback_repository_test.dart`
- Create: `test/features/feedback/contextual_feedback_sheet_test.dart`

- [ ] **Step 1: Write failing repository and widget tests**

Cover strict request shape, UUID reuse only for retrying one submission, required 10-character text, output preview, submitting/success/retry states, keyboard focus, semantic label, and no generic/global target mode.

- [ ] **Step 2: Run focused tests**

Run: `flutter test test/features/feedback/feedback_repository_test.dart test/features/feedback/contextual_feedback_sheet_test.dart`

Expected: FAIL because the shared feature does not exist.

- [ ] **Step 3: Implement typed targets and repository**

Use sealed targets `TransactionFeedbackTarget`, `StatementFeedbackTarget`, `UserCardFeedbackTarget`, and `RecommendationFeedbackTarget`. Only the recommendation target carries a trace ID, which the repository obtains from `trace-create` before opening submission.

- [ ] **Step 4: Implement the shared sheet/button**

Render a concise output preview supplied by the caller, one multiline text field, character count, and one submit action. Do not display model terminology to the user. Preserve entered text on retry.

- [ ] **Step 5: Run focused tests and commit**

Run: `flutter test test/features/feedback`

Expected: PASS.

```bash
git add lib/features/feedback test/features/feedback
git commit -m "feat(feedback): add contextual capture surface"
```

### Task 6: Attach feedback to the three supported product families

**Files:**
- Modify: `lib/features/transactions/screens/transactions_screen.dart`
- Modify: `lib/features/cards/screens/card_detail_screen.dart`
- Modify: `lib/features/benefits/movie_deals/screens/movie_deals_results.dart`
- Modify or create focused tests adjacent to each existing feature test suite.

- [ ] **Step 1: Write failing integration widget tests**

Assert a transaction row submits its transaction ID; Card Detail submits the user's `user_card` ID; and Movie Deals creates a recommendation trace from bounded request fields plus selected candidate/card/benefit IDs before allowing feedback. Assert no full list/history or provider token enters the payload.

- [ ] **Step 2: Run focused feature tests**

Run the three exact test files selected from `rg -l "TransactionsScreen|CardDetailScreen|MovieDealsResults" test` after adding the new cases.

Expected: FAIL on missing feedback controls.

- [ ] **Step 3: Add contextual actions**

Use secondary “Give feedback” actions that do not disturb primary navigation. Provide short previews from already-rendered values. For recommendation traces, call the repository only when feedback opens; handle trace expiry by recreating once.

- [ ] **Step 4: Re-run focused tests and commit**

Expected: all selected tests PASS.

```bash
git add lib/features/transactions/screens/transactions_screen.dart lib/features/cards/screens/card_detail_screen.dart lib/features/benefits/movie_deals/screens/movie_deals_results.dart test
git commit -m "feat(feedback): attach output-specific feedback targets"
```

### Task 7: Add admin feedback review and Action Inbox integration

**Files:**
- Create: `supabase/functions/admin-operator/feedback.ts`
- Create: `supabase/functions/admin-operator/feedback_test.ts`
- Modify: `supabase/functions/admin-operator/inbox.ts`
- Modify: `supabase/functions/admin-operator/inbox_test.ts`
- Modify: `supabase/functions/admin-operator/router.ts`
- Create: `lib/features/admin2/feedback/feedback_models.dart`
- Create: `lib/features/admin2/feedback/feedback_repository.dart`
- Create: `lib/features/admin2/feedback/feedback_detail.dart`
- Modify: `lib/features/admin2/inbox/action_inbox_section.dart`
- Create: `test/features/admin2/feedback_detail_test.dart`

- [ ] **Step 1: Write failing gateway tests**

Cover bounded/paginated list, sanitized detail, audit-before-detail, triage retry only from failed state, required admin-authored text for draft creation, required reasons for routing/dismissal, separate case approval, and stable conflict errors.

- [ ] **Step 2: Write failing inbox and Flutter tests**

Assert pending feedback becomes a ranked inbox item; critical/high triage severity ranks accordingly but never auto-closes; LLM text is labelled advisory and editable; approving a case requires a second explicit confirmation.

- [ ] **Step 3: Run focused tests**

Run: `deno test --config supabase/functions/admin-operator/deno.json supabase/functions/admin-operator/feedback_test.ts supabase/functions/admin-operator/inbox_test.ts && flutter test test/features/admin2/feedback_detail_test.dart`

Expected: FAIL on missing review workflow.

- [ ] **Step 4: Implement safe gateway actions**

Register immutable handlers for `feedback-list`, `feedback-detail`, `feedback-review`, `feedback-triage-retry`, and `eval-case-action`. Detail calls `record_admin_read` before response. Retry sets `awaiting_triage` and uses `EdgeRuntime.waitUntil`; a scheduling failure leaves it retryable.

- [ ] **Step 5: Implement the admin detail UI**

Show user feedback, captured output, safe context, version metadata, and visually distinct advisory proposal. Require the operator to author/confirm expected output, rubric, and severe conditions. Deep-link from Inbox and refresh after each server-confirmed action.

- [ ] **Step 6: Run focused tests and commit**

Run: `deno test --config supabase/functions/admin-operator/deno.json supabase/functions/admin-operator/ && flutter test test/features/admin2`

Expected: PASS.

```bash
git add supabase/functions/admin-operator lib/features/admin2/feedback lib/features/admin2/inbox test/features/admin2
git commit -m "feat(admin2): review feedback into eval cases"
```

### Task 8: Verify capture and triage

- [ ] **Step 1: Format and check**

Run: `dart format lib/features/feedback lib/features/admin2 test/features && deno fmt supabase/functions/feedback-submit supabase/functions/_shared supabase/functions/admin-operator && flutter analyze`

Expected: format/analyze clean.

- [ ] **Step 2: Run all suites**

Run: `flutter test && node --test test/supabase/*.js && deno test --allow-env --allow-net --allow-read supabase/functions`

Expected: all tests pass; opt-in integrations remain explicit.

- [ ] **Step 3: Perform the privacy fixture scan**

Run: `rg -n -i "raw_email|email_body|pdf_bytes|provider_token|access_token|refresh_token|authorization" supabase/functions/feedback-submit supabase/functions/admin-operator/feedback.ts lib/features/feedback`

Expected: no persisted or returned sensitive field; matches, if any, are only explicit rejection tests.

- [ ] **Step 4: Perform a local failure-recovery smoke test**

Submit feedback with the model adapter unavailable, verify `202` and preserved text with `triage_failed`, retry from Admin, correct the proposal, create a draft, approve it, and verify the dataset version increments once.

- [ ] **Step 5: Inspect the final diff**

Run: `git diff --check && git status --short`

Expected: no whitespace errors and only intentional feedback-phase changes remain.
