# Contextual AI Evaluation Runner Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Run bounded, resumable baseline-versus-candidate evaluations over approved feedback cases and present accuracy, regression, latency, and cost evidence to the founder without changing production automatically.

**Architecture:** PostgreSQL snapshots an immutable case manifest and enforces run lifecycle/cost limits. A private `ai-eval-runner` Edge Function claims at most five cases per invocation, executes code-allowlisted configurations, records each result, and continues through authenticated self-invocation while remaining manually resumable. Deterministic scorers handle structured outputs; recommendations use a randomized blind A/B judge pinned in code.

**Tech Stack:** Supabase Edge Functions/Deno, PostgreSQL, Gemini REST transport, Flutter/Riverpod Admin2 System UI, Node migration contracts.

**Specs:**
- `docs/superpowers/specs/2026-08-19-contextual-ai-feedback-evals-design.md`
- `docs/superpowers/specs/2026-08-19-admin-operator-console-design.md`

## Global Constraints

- Complete the Contextual Feedback Capture and Triage plan first. Complete Admin2 System Ops before adding the run UI.
- Only `approved` cases inside the selected dataset-version bounds enter a run.
- The client selects code-defined configuration keys; it cannot send provider URLs, API keys, prompt text, executable templates, or arbitrary model names.
- The candidate never receives expected output, operator feedback, scoring rubric, or severe conditions. Those values are scorer/judge inputs only.
- The judge receives randomized labels `A` and `B`, has no tools, and returns an exact schema.
- Claim at most five cases per invocation and check projected cost before every claim.
- Each case result is committed independently. Crashes leave the run resumable without rerunning successful cases.
- No result, aggregate, or recommendation changes production code/configuration.

---

## File structure

- `supabase/migrations/20260819090500_contextual_ai_eval_runs.sql` — run/result tables and lifecycle RPCs.
- `test/supabase/contextual_ai_eval_runs_migration_test.js` — manifest, claim, cost, and immutability contracts.
- `supabase/functions/_shared/gemini_generate.ts` — existing shared transport, extended only for eval metering.
- `supabase/functions/_shared/gemini_generate_test.ts` — existing fallback/timeout coverage plus eval metering.
- `supabase/functions/gemini-proxy/index.ts` — delegates upstream generation without changing client behavior.
- `supabase/functions/gemini-proxy/index_test.ts` — proxy regression tests.
- `supabase/functions/ai-eval-runner/deno.json` — worker dependencies.
- `supabase/functions/ai-eval-runner/index.ts` — private bounded worker.
- `supabase/functions/ai-eval-runner/config_registry.ts` — allowlisted run configurations.
- `supabase/functions/ai-eval-runner/executors.ts` — baseline/candidate execution.
- `supabase/functions/ai-eval-runner/scorers.ts` — deterministic and blind-judge scoring.
- `supabase/functions/ai-eval-runner/types.ts` — exact fixtures/results.
- `supabase/functions/ai-eval-runner/index_test.ts` — lifecycle, resume, and cost tests.
- `supabase/functions/ai-eval-runner/scorers_test.ts` — regression and randomized A/B tests.
- `supabase/functions/admin-operator/evals.ts` — configuration/list/detail/action handlers.
- `supabase/functions/admin-operator/evals_test.ts` — admin gateway tests.
- `supabase/functions/admin-operator/router.ts` — eval action registration.
- `lib/features/admin2/system/eval_models.dart` — typed run, aggregate, and result DTOs.
- `lib/features/admin2/system/eval_repository.dart` — gateway adapter.
- `lib/features/admin2/system/eval_runs_panel.dart` — start/progress/result UI.
- `lib/features/admin2/system/system_section.dart` — panel integration.
- `test/features/admin2/eval_repository_test.dart` — payload and mapping contract.
- `test/features/admin2/eval_runs_panel_test.dart` — human decision-support behavior.
- `supabase/config.toml` — private worker JWT setting.

---

### Task 1: Add immutable evaluation runs and results

**Files:**
- Create: `supabase/migrations/20260819090500_contextual_ai_eval_runs.sql`
- Create: `test/supabase/contextual_ai_eval_runs_migration_test.js`

**Interfaces:**
- Tables: `public.ai_eval_runs`, `public.ai_eval_results`.
- Admin RPCs: `admin_create_ai_eval_run(...)`, `admin_ai_eval_run_action(...)`.
- Worker RPCs: `claim_ai_eval_run_batch(...)`, `record_ai_eval_result(...)`, `finish_ai_eval_run(...)`.

- [ ] **Step 1: Write the failing table contract**

```js
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const migrationUrl = new URL(
  '../../supabase/migrations/20260819090500_contextual_ai_eval_runs.sql',
  import.meta.url,
);

test('eval runs are private, bounded and immutable after completion', async () => {
  const sql = (await readFile(migrationUrl, 'utf8')).toLowerCase();
  for (const table of ['ai_eval_runs', 'ai_eval_results']) {
    assert.match(sql, new RegExp(`create table public\\.${table}`));
    assert.match(sql, new RegExp(`alter table public\\.${table} enable row level security`));
    assert.match(sql, new RegExp(`revoke all on public\\.${table} from public, anon, authenticated`));
  }
  assert.match(sql, /maximum_case_count between 1 and 100/);
  assert.match(sql, /cost_ceiling_usd > 0/);
  assert.match(sql, /unique \(run_id, case_id, case_revision\)/);
  assert.match(sql, /create trigger protect_completed_ai_eval/);
});
```

- [ ] **Step 2: Run the focused contract**

Run: `node --test test/supabase/contextual_ai_eval_runs_migration_test.js`

Expected: FAIL with `ENOENT`.

- [ ] **Step 3: Create exact run columns**

Create `ai_eval_runs` with: `id`, `dataset_version`, `case_manifest`, `baseline_config_key`, `candidate_config_key`, `judge_config_key`, `status`, `maximum_case_count`, `cost_ceiling_usd`, `latency_ceiling_ms`, `aggregate_metrics`, `token_usage`, `estimated_cost_usd`, `initiated_by`, `request_id`, `lease_token`, `lease_expires_at`, `created_at`, `started_at`, `completed_at`, and `updated_at`. Enforce unique `(initiated_by, request_id)` and the approved status constraint.

`case_manifest` is an array of `{case_id, revision, feature_key}` built server-side at run creation and never accepted from the client.

- [ ] **Step 4: Create exact result columns**

Create `ai_eval_results` with: `id`, `run_id`, `case_id`, `case_revision`, `feature_key`, `baseline_output`, `candidate_output`, `deterministic_assertions`, `judge_verdict`, `regression`, `severe_regression`, baseline/candidate latency, tokens, cost, `execution_status`, `safe_failure_category`, `attempt_count`, `created_at`, and `updated_at`. Enforce unique `(run_id, case_id, case_revision)`.

Enable RLS, revoke browser access, grant service-role access, and add triggers denying manifest/config changes after insertion and result changes after the run becomes terminal.

- [ ] **Step 5: Run the table contract**

Run: `node --test test/supabase/contextual_ai_eval_runs_migration_test.js`

Expected: PASS.

### Task 2: Add atomic creation, bounded claim, result, and resume RPCs

**Files:**
- Modify: `supabase/migrations/20260819090500_contextual_ai_eval_runs.sql`
- Modify: `test/supabase/contextual_ai_eval_runs_migration_test.js`

- [ ] **Step 1: Add failing lifecycle assertions**

Assert all RPCs use `SECURITY DEFINER SET search_path = ''`, are service-only, and include: approved/version-bounded case selection; maximum 100; `FOR UPDATE SKIP LOCKED`; batch limit clamped to 5; completed-result exclusion; projected-cost ceiling; request idempotency; cancel/resume allowlists; and atomic admin audit receipts.

- [ ] **Step 2: Run the contract**

Run: `node --test test/supabase/contextual_ai_eval_runs_migration_test.js`

Expected: FAIL on missing RPCs.

- [ ] **Step 3: Implement run creation**

`admin_create_ai_eval_run` accepts actor ID, request ID, dataset version, baseline key, candidate key, judge key, maximum case count, cost ceiling, and latency ceiling. It selects approved cases where `approved_in_dataset_version <= selected_version` and `retired_in_dataset_version IS NULL OR retired_in_dataset_version > selected_version`, orders by case ID/revision, and builds the immutable bounded manifest. Empty manifests return `invalid_request`. It records `eval.run.create` in `admin_audit_log` atomically.

- [ ] **Step 4: Implement bounded claims and results**

`claim_ai_eval_run_batch` locks one queued/running run and returns at most five manifest entries that have no successful result. It checks cancellation, expired leases, current cost plus supplied per-case maximum projected cost, and changes `queued` to `running`. Cost exhaustion returns no cases and marks the run `completed_with_failures` with safe category `cost_ceiling_reached`.

`record_ai_eval_result` requires the worker lease, the exact manifest revision, and an exact structured result. It inserts once; retries may replace only `execution_status = 'failed'` while the run is nonterminal. `finish_ai_eval_run` aggregates counts/tokens/cost/latency from stored results and assigns `completed`, `completed_with_failures`, or `failed`.

- [ ] **Step 5: Implement admin cancel and resume**

`admin_ai_eval_run_action` allows `cancel|resume_failed`. Cancel is terminal. Resume changes only `failed|completed_with_failures` runs with failed/missing cases back to `queued`; it never deletes successful results. Both are idempotent and audited.

- [ ] **Step 6: Run migration contracts**

Run: `node --test test/supabase/contextual_ai_eval_runs_migration_test.js test/supabase/contextual_ai_feedback_migration_test.js test/supabase/admin_operator_foundation_migration_test.js`

Expected: PASS.

### Task 3: Verify and extend the reusable Gemini transport for eval metering

**Files:**
- Modify: `supabase/functions/_shared/gemini_generate.ts`
- Modify: `supabase/functions/_shared/gemini_generate_test.ts`
- Modify: `supabase/functions/gemini-proxy/index.ts`
- Create or modify: `supabase/functions/gemini-proxy/index_test.ts`

**Interfaces:**
- `generateGemini(input, dependencies): Promise<GeminiGenerationResult>`.

- [ ] **Step 1: Write failing transport tests**

Cover model allowlist, 100 KB request limit, 25-second per-attempt timeout, key fallback on `429`, model fallback on supported `404`, immediate stop on other errors, parsed usage metadata, latency measurement, and safe error categories without keys or response bodies.

- [ ] **Step 2: Write a proxy regression test**

Inject the transport and prove the current proxy retains method/auth/quota validation, allowed model behavior, response status/body, and CORS contract.

- [ ] **Step 3: Run focused tests**

Run: `deno test supabase/functions/_shared/gemini_generate_test.ts supabase/functions/gemini-proxy/model_policy_test.ts supabase/functions/gemini-proxy/index_test.ts`

Expected: the feedback-era fallback and proxy tests PASS; the new exact usage/latency assertions FAIL until metering is complete.

- [ ] **Step 4: Complete the transport's metering contract**

Return this exact type:

```ts
export type GeminiGenerationResult = Readonly<{
  model: string;
  response: Record<string, unknown>;
  inputTokens: number;
  outputTokens: number;
  latencyMs: number;
}>;
```

Keep server keys behind the injected `env(name)` function, use the existing `modelCandidates`, `preparePayloadForModel`, and `shouldTryAnotherModel`, normalize missing usage fields to zero, and never include a key/upstream body in thrown errors.

- [ ] **Step 5: Reconfirm proxy delegation is behavior-preserving**

Keep `handleGeminiProxy(request, dependencies)` and `serve(...)` separated. The proxy still performs user quota consumption; the private eval worker performs run-level cost enforcement instead.

- [ ] **Step 6: Run tests and commit the transport plus migration**

Run: `deno test supabase/functions/_shared/gemini_generate_test.ts supabase/functions/gemini-proxy/ && node --test test/supabase/contextual_ai_eval_runs_migration_test.js`

Expected: PASS.

```bash
git add supabase/migrations/20260819090500_contextual_ai_eval_runs.sql test/supabase/contextual_ai_eval_runs_migration_test.js supabase/functions/_shared/gemini_generate.ts supabase/functions/_shared/gemini_generate_test.ts supabase/functions/gemini-proxy docs/superpowers/plans/2026-08-19-contextual-ai-eval-runner.md
git commit -m "feat(evals): add bounded run storage and model transport"
```

### Task 4: Define allowlisted configurations and executors

**Files:**
- Create: `supabase/functions/ai-eval-runner/deno.json`
- Create: `supabase/functions/ai-eval-runner/types.ts`
- Create: `supabase/functions/ai-eval-runner/config_registry.ts`
- Create: `supabase/functions/ai-eval-runner/executors.ts`
- Create: `supabase/functions/ai-eval-runner/index_test.ts`

- [ ] **Step 1: Write failing registry tests**

Define initial keys:

```ts
export type EvalConfigKey =
  | "captured-production-v1"
  | "gemini-3.6-flash-statement-v1"
  | "gemini-3.6-flash-card-data-v1"
  | "gemini-3.6-flash-recommendation-v1";

export type JudgeConfigKey = "gemini-3.6-flash-blind-judge-v1";
```

Assert unknown keys fail before database claims or model calls. Assert each candidate supports only its matching feature and receives `input_fixture` but not expected/rubric/operator/severe-condition fields.

- [ ] **Step 2: Run focused tests**

Run: `deno test --config supabase/functions/ai-eval-runner/deno.json supabase/functions/ai-eval-runner/index_test.ts`

Expected: FAIL because the worker modules do not exist.

- [ ] **Step 3: Implement the registry**

Each code-owned entry contains `key`, `featureKey`, `provider`, `model`, `promptVersion`, `maxInputTokens`, `maxOutputTokens`, and `estimatedMaximumCostUsd`. `captured-production-v1` returns the case's immutable captured output and costs zero; candidate entries build fixed prompts from safe fixtures only. Add new experiments through code review, never database/client templates.

- [ ] **Step 4: Implement feature executors**

Statement executor requests structured parsed/category JSON. Card Data executor requests structured identity/benefit JSON with grounded source fields already present in the safe fixture. Recommendation executor requests ranked card/benefit IDs and bounded explanation. Validate each response before returning it; invalid output becomes a safe failed result.

- [ ] **Step 5: Run registry tests and commit**

Run: `deno test --config supabase/functions/ai-eval-runner/deno.json supabase/functions/ai-eval-runner/index_test.ts`

Expected: registry/executor tests PASS.

```bash
git add supabase/functions/ai-eval-runner/deno.json supabase/functions/ai-eval-runner/types.ts supabase/functions/ai-eval-runner/config_registry.ts supabase/functions/ai-eval-runner/executors.ts supabase/functions/ai-eval-runner/index_test.ts
git commit -m "feat(evals): add code-owned evaluation configs"
```

### Task 5: Add deterministic and blind A/B scoring

**Files:**
- Create: `supabase/functions/ai-eval-runner/scorers.ts`
- Create: `supabase/functions/ai-eval-runner/scorers_test.ts`

**Interfaces:**
- `scoreStructuredCase(caseFixture, baseline, candidate): ScoreResult`.
- `scoreRecommendationCase(caseFixture, baseline, candidate, judge): Promise<ScoreResult>`.

- [ ] **Step 1: Write failing structured-scorer tests**

Cover exact expected paths, numeric values/currency, transaction presence exactly once, card catalog ID, benefit limit/period/eligibility, must-not paths/claims, schema invalidity, and all approved severe-failure definitions.

- [ ] **Step 2: Write failing judge tests**

Use a SHA-256 digest of `run_id:case_id:revision` to assign baseline/candidate to A/B. Assert both orientations, correct decoding, ties/low confidence/invalid output requiring review, prompt-injection text remaining delimited data, no tools, and pinned judge key/model.

- [ ] **Step 3: Run scorer tests**

Run: `deno test --config supabase/functions/ai-eval-runner/deno.json supabase/functions/ai-eval-runner/scorers_test.ts`

Expected: FAIL because scorers do not exist.

- [ ] **Step 4: Implement exact result types and thresholds**

```ts
export type ScoreResult = Readonly<{
  passed: boolean;
  regression: boolean;
  severeRegression: boolean;
  requiresReview: boolean;
  assertions: readonly Readonly<{
    key: string;
    baselinePassed: boolean;
    candidatePassed: boolean;
    severity: "normal" | "severe";
  }>[];
  judge: Readonly<{
    winner: "baseline" | "candidate" | "tie";
    confidence: number;
    explanation: string;
    assignment: "baseline_is_a" | "baseline_is_b";
  }> | null;
}>;
```

Confidence below `0.70` requires review. Any schema failure, materially wrong financial value, incorrect identity, unsupported claim, or explicit must-not violation is severe.

- [ ] **Step 5: Run and commit**

Run: `deno test --config supabase/functions/ai-eval-runner/deno.json supabase/functions/ai-eval-runner/scorers_test.ts`

Expected: PASS.

```bash
git add supabase/functions/ai-eval-runner/scorers.ts supabase/functions/ai-eval-runner/scorers_test.ts
git commit -m "feat(evals): score regressions and blind comparisons"
```

### Task 6: Build the private bounded and resumable worker

**Files:**
- Create: `supabase/functions/ai-eval-runner/index.ts`
- Modify: `supabase/functions/ai-eval-runner/index_test.ts`
- Modify: `supabase/config.toml`

- [ ] **Step 1: Add failing worker lifecycle tests**

Cover service-role-only request auth, maximum five claims, per-result persistence, no rerun of successes, failed-result retry, cost stop before a call, cancellation between cases, partial failure, terminal aggregate, and sanitized error categories.

- [ ] **Step 2: Add failing continuation tests**

Inject `scheduleContinuation(runId)` and prove it is called only when cases remain and the run is below limits. A scheduling failure leaves status `running` with completed results intact so an admin resume can continue.

- [ ] **Step 3: Run focused worker tests**

Run: `deno test --config supabase/functions/ai-eval-runner/deno.json supabase/functions/ai-eval-runner/index_test.ts`

Expected: FAIL until `index.ts` exists.

- [ ] **Step 4: Implement the private handler**

Verify the bearer token against `SUPABASE_SERVICE_ROLE_KEY` using a timing-safe digest comparison before reading a run ID. Resolve configuration keys from the database row through the code registry. Claim at most five cases, execute/score/record sequentially, then finish or schedule the next invocation with `EdgeRuntime.waitUntil`.

The continuation POSTs only `{run_id}` to the deployed `ai-eval-runner` URL with the server role bearer token. Configure the function consistently with this explicit internal authentication; it must not accept user/admin JWTs.

- [ ] **Step 5: Run all worker tests**

Run: `deno test --config supabase/functions/ai-eval-runner/deno.json supabase/functions/ai-eval-runner/`

Expected: PASS.

- [ ] **Step 6: Commit the worker**

```bash
git add supabase/functions/ai-eval-runner/index.ts supabase/functions/ai-eval-runner/index_test.ts supabase/config.toml
git commit -m "feat(evals): run bounded resumable comparisons"
```

### Task 7: Add admin run controls and decision support

**Files:**
- Create: `supabase/functions/admin-operator/evals.ts`
- Create: `supabase/functions/admin-operator/evals_test.ts`
- Modify: `supabase/functions/admin-operator/router.ts`
- Create: `lib/features/admin2/system/eval_models.dart`
- Create: `lib/features/admin2/system/eval_repository.dart`
- Create: `lib/features/admin2/system/eval_runs_panel.dart`
- Modify: `lib/features/admin2/system/system_section.dart`
- Create: `test/features/admin2/eval_repository_test.dart`
- Create: `test/features/admin2/eval_runs_panel_test.dart`

- [ ] **Step 1: Write failing gateway tests**

Cover code-owned config listing, bounded dataset/run creation, request idempotency, runner kickoff after the run row commits, paginated run/results, sanitized output, cancellation, resume-failed, and audit-before-detail.

- [ ] **Step 2: Implement gateway handlers**

Register `eval-config-list`, `eval-run-list`, `eval-run-detail`, and `eval-run-action`. Start calls `admin_create_ai_eval_run`, then schedules the private worker with `EdgeRuntime.waitUntil`. Return the durable run ID even if scheduling fails so the operator can resume.

- [ ] **Step 3: Write failing Flutter tests**

Cover configuration selection, maximum/cost/latency inputs, progress after refresh, feature metrics, improvements/regressions/severe regressions, token/cost/latency display, failed-case drilldown, cancel/resume confirmation, and no “deploy” or automatic rollout action.

- [ ] **Step 4: Implement the System panel**

The summary recommendation is `candidate_supported` only when target pass rate improves, severe regressions equal zero, actual cost is within the ceiling, p95 candidate latency is within the ceiling, and no case requires review. Otherwise show `review_required` with concrete blockers. This is UI decision support, not a production mutation.

- [ ] **Step 5: Run focused tests**

Run: `deno test --config supabase/functions/admin-operator/deno.json supabase/functions/admin-operator/evals_test.ts && flutter test test/features/admin2/eval_repository_test.dart test/features/admin2/eval_runs_panel_test.dart`

Expected: PASS.

- [ ] **Step 6: Commit admin controls**

```bash
git add supabase/functions/admin-operator/evals.ts supabase/functions/admin-operator/evals_test.ts supabase/functions/admin-operator/router.ts lib/features/admin2/system test/features/admin2/eval_repository_test.dart test/features/admin2/eval_runs_panel_test.dart
git commit -m "feat(admin2): operate contextual AI evaluations"
```

### Task 8: Verify the evaluation loop

- [ ] **Step 1: Format and type-check**

Run: `dart format lib/features/admin2/system test/features/admin2 && deno fmt supabase/functions/_shared supabase/functions/gemini-proxy supabase/functions/ai-eval-runner supabase/functions/admin-operator && flutter analyze && deno check --config supabase/functions/ai-eval-runner/deno.json supabase/functions/ai-eval-runner/index.ts`

Expected: format/analyze/check clean.

- [ ] **Step 2: Run all suites**

Run: `flutter test && node --test test/supabase/*.js && deno test --allow-env --allow-net --allow-read supabase/functions`

Expected: all tests pass; opt-in integrations remain explicit.

- [ ] **Step 3: Run a deterministic local smoke fixture**

Seed at least one approved case in each feature family, use fake deterministic candidate/judge adapters, start a run with a maximum above five, and verify continuation completes every case exactly once, aggregates match stored results, and severe regression blocks `candidate_supported`.

- [ ] **Step 4: Run an opt-in live-provider pilot**

With an explicit low cost ceiling, run no more than three approved sanitized cases. Verify model versions, token usage, cost, latency, blind assignment, and bounded explanations are recorded. Do not paste prompts, keys, or customer-sensitive fixtures into logs.

- [ ] **Step 5: Inspect the final diff and stop at release boundary**

Run: `git diff --check && git status --short`

Expected: no whitespace errors and only intentional eval-runner changes remain. Report artifacts and results; do not deploy, push, or change production configurations without explicit authorization.
