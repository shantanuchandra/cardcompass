# CardCompass Contextual AI Feedback and Evaluations Design

**Date:** 2026-08-19

## Summary

CardCompass will collect free-text feedback on specific AI-assisted outputs, use an LLM to propose a diagnosis and evaluation case, and require the founder-operator to approve the ground truth before that case joins a versioned evaluation dataset.

The first version covers statement parsing and transaction categorization, card identity and benefit extraction, and personalized card or benefit recommendations. Feedback review appears in the `/app/admin2` Action Inbox. Evaluation runs and model or prompt comparisons appear under System.

The loop is human-gated:

`User feedback → LLM triage → admin correction → approved eval case → baseline/candidate run → admin decision`

No feedback, diagnosis, evaluation result, or LLM recommendation changes production prompts, models, catalog data, or application behavior automatically.

## Goals

- Capture the user's explanation of a problem while the relevant output is still identifiable.
- Preserve enough trusted context to reproduce or evaluate the failure.
- Let an LLM reduce triage work without treating its diagnosis as ground truth.
- Turn approved feedback into reusable, versioned evaluation cases.
- Compare baseline and candidate behavior on accuracy, severe regressions, latency, and cost.
- Keep the workflow operable by one founder without external spreadsheets or manual dataset assembly.

## Non-goals

- Generic product, support, authentication, or usability feedback.
- Feedback on deterministic calculators.
- Automatic fine-tuning, prompt rewriting, model switching, deployment, or catalog mutation.
- Public evaluation dashboards or multi-reviewer assignments.
- Full annotation tooling for PDFs, emails, or complete transaction histories.
- Advanced retention automation, anonymization, or semantic duplicate clustering in the MVP.

## Supported output families

| Feature family | Example feedback target | Evaluation emphasis |
|---|---|---|
| Statement processing | Parsed statement, extracted transaction, transaction category | Schema validity and expected fields |
| Card data | Card identity match, catalog proposal, extracted or changed benefit | Correct fields, match decision, and source grounding |
| Recommendations | Recommended card or benefit and its explanation | Correct choice, required facts, and unsupported-claim avoidance |

Each integration uses a stable `feature_key` and a server-resolvable `output_ref`. A global feedback box without a specific output reference is excluded from this evaluation loop.

## User capture

Supported outputs expose a **Give feedback** action. The feedback surface contains:

- required free text asking what was wrong or what should have happened;
- a concise preview of the output being discussed;
- submission, success, and retry states; and
- no requirement for the user to understand models, prompts, or evaluation terminology.

The Flutter client sends only the feedback text, `feature_key`, `output_ref`, and a client-generated request ID to a user-facing `feedback-submit` Edge Function. The client does not supply trusted model metadata or arbitrary context snapshots.

The server authenticates the user, validates that the referenced output belongs to that user where ownership applies, and resolves an allowlisted context projection. It attaches the trace ID, provider, model, prompt or parser version, and minimal input/output fixture needed by that feature.

Persisted outputs such as statements, transactions, and user-card matches are resolved directly from their authoritative rows. Ephemeral recommendations first create a short-lived server-issued output trace: the server validates referenced cards and benefits, stores server-resolved catalog facts, and labels the computed recommendation snapshot as client-reported rather than trusted ground truth.

MVP safeguards are deliberately narrow: store the user's submitted text, but do not copy raw emails, statement PDFs, credentials, tokens, or full statement and transaction histories. Feedback and evaluation tables are available only through server-owned paths.

## Data model

### `public.ai_output_traces`

One bounded reference for an ephemeral feedback target:

- `id uuid primary key`;
- `user_id uuid not null`;
- `feature_key text not null`;
- `safe_input_context jsonb not null default '{}'` containing bounded user inputs;
- `output_snapshot jsonb not null default '{}'` containing the client-reported result;
- `authoritative_context jsonb not null default '{}'` containing server-resolved card and benefit facts;
- `engine_version text`, `model text`, and `prompt_version text`;
- `created_at timestamptz not null default now()` and `expires_at timestamptz not null`; and
- a check that expiry is within seven days of creation.

The user-facing endpoint creates a trace only after validating ownership and active catalog references. A feedback record copies its bounded fixture transactionally; expired, unreferenced traces may then be deleted without affecting accepted feedback.

### `public.ai_feedback`

One record per contextual submission:

- `id uuid primary key`;
- `user_id uuid not null`;
- `feature_key text not null` constrained to the supported families;
- `output_ref_type text not null` and `output_ref_id text not null`;
- `feedback_text text not null` with a bounded length;
- `safe_input_context jsonb not null default '{}'`;
- `output_snapshot jsonb not null default '{}'`;
- `trace_id text`;
- `provider text`, `model text`, `prompt_version text`, and `parser_version text`;
- `request_id uuid not null`;
- `triage_status text not null` constrained to `awaiting_triage`, `triaging`, `triaged`, or `triage_failed`;
- `triage_result jsonb not null default '{}'`;
- `review_status text not null` constrained to `pending`, `eval_created`, `data_issue`, `product_defect`, or `dismissed`;
- `reviewed_by uuid`, `reviewed_at timestamptz`, and `dismissal_reason text`; and
- `created_at timestamptz not null default now()` and `updated_at timestamptz not null default now()`.

`(user_id, request_id)` is unique so a retried submission cannot create duplicates.

### `public.ai_eval_cases`

One founder-approved ground-truth fixture:

- source feedback ID and feature key;
- immutable input fixture and captured production output;
- expected output;
- operator-authored feedback describing what should happen;
- an explicit scoring rubric and severe-failure conditions;
- status constrained to `draft`, `approved`, or `retired`;
- case revision, `approved_in_dataset_version`, and optional `retired_in_dataset_version`;
- creator and approver IDs with timestamps; and
- immutable source model, prompt, parser, and trace metadata.

Only approved cases enter an evaluation run. Approving or retiring a case creates the next dataset version. A run selects cases whose approved and retired version bounds include that version, then stores the exact case IDs and revisions in its immutable manifest. Updating approved ground truth creates a new case revision rather than silently changing historical runs.

### `public.ai_eval_runs`

One bounded baseline-versus-candidate execution:

- immutable dataset version;
- immutable case ID and revision manifest;
- baseline and candidate provider, model, prompt, and parser configuration;
- status constrained to `queued`, `running`, `completed`, `completed_with_failures`, `failed`, or `cancelled`;
- maximum case count and cost ceiling;
- aggregate metrics, token usage, estimated cost, and latency; and
- initiating admin, request ID, and lifecycle timestamps.

### `public.ai_eval_results`

One result per run and case:

- captured baseline and candidate outputs;
- deterministic assertion results;
- LLM-judge verdict, confidence, and bounded explanation where applicable;
- regression and severe-regression flags;
- latency, token usage, and estimated cost per side; and
- execution status and safe failure category.

`(run_id, case_id)` is unique. Results are append-only for a completed run.

All five tables have RLS enabled and no direct browser grants. The user-facing endpoint performs trace creation and the user-owned feedback insert. The database-backed admin gateway performs review and evaluation operations.

## LLM-assisted triage

Submission and triage are separate. A successful feedback write is never rolled back because an LLM is unavailable.

The triage worker receives the submitted text and safe contextual fixture. It returns a validated structured response containing:

- classification: `model_error`, `data_issue`, `product_defect`, `unclear`, `duplicate_candidate`, or `not_actionable`;
- severity and confidence;
- concise diagnosis;
- proposed expected result;
- proposed evaluation rubric; and
- safe explanation of why the case may or may not suit evaluation.

The triage result is advisory. It cannot create an approved case, mutate customer or catalog data, change production configuration, or dismiss feedback. Invalid output sets `triage_failed` and preserves the original feedback for manual review or retry.

Feedback text and captured context are treated as untrusted data, never as model instructions. The triage model has no tools, receives a fixed system instruction with delimited data fields, and must return a validated bounded schema.

## Admin operator workflow

Pending feedback is derived into the Action Inbox as a distinct item type. The list supports feature, review status, severity, and model or prompt version filters.

The detail view shows the user's text, captured output, safe context, model metadata, and LLM proposal. The operator chooses one action:

| Action | Required input | Result |
|---|---|---|
| Create eval case | Admin text describing the expected behavior; reviewed expected output and rubric | Creates a draft, then explicitly approved eval case |
| Route as data issue | Reason and destination | Links the issue to the relevant Card Data workflow without adding it to the eval dataset |
| Mark product defect | Reason | Excludes the case from model evaluation while preserving the diagnosis |
| Dismiss | Reason such as unclear, duplicate, or not actionable | Closes the inbox item without creating an eval case |
| Retry triage | None when the prior triage failed | Requeues advisory LLM processing |

The admin's text and approved expected result are the human ground truth. LLM-generated text is visually identified and remains editable before approval.

## Evaluation execution

An admin starts a run from System by selecting an approved dataset version and a bounded baseline and candidate configuration. The server resolves allowlisted model and prompt configurations; it never accepts arbitrary provider URLs, credentials, or executable prompt templates from the client.

Scoring uses the strongest available method:

| Output type | Primary scoring |
|---|---|
| Parsed statements and categories | Deterministic schema and expected-field assertions |
| Card identity and benefits | Exact field and match checks plus source-grounding requirements |
| Recommendations and explanations | Blind baseline-versus-candidate comparison using a pinned LLM judge and approved rubric |

The judge receives outputs labelled only `A` and `B`; their baseline/candidate assignment is randomized per case. Ties, low-confidence judgments, invalid judge output, and severe regressions require operator review.

Candidate outputs and fixture text are untrusted judge inputs. The judge has no tools, cannot alter run state, and returns a schema-validated verdict before the server records a result.

A severe regression includes a schema failure, materially wrong financial value, incorrect card identity, unsupported benefit or recommendation claim, or violation of a case's explicit must-not condition.

Every run reports:

- overall and feature-level pass rate;
- improvements, unchanged cases, and new regressions versus baseline;
- severe-regression count;
- latency distribution;
- token usage and estimated cost; and
- dataset, model, prompt, parser, and judge versions.

A candidate is recommended only when it improves the configured target metric, introduces no severe regression, and remains within the run's cost and latency ceilings. Recommendation is decision support; production rollout remains a separate, admin-approved engineering change.

## Example feedback-to-eval cases

| User feedback text | Admin ground truth | Evaluation case |
|---|---|---|
| “This ₹1,249 payment is groceries, not shopping.” | The expected category is `grocery` for this merchant evidence. | Assert the normalized category and preserve the amount and currency. |
| “One transaction from the statement is missing.” | The identified transaction must be present exactly once. | Assert transaction count and the expected date, merchant, amount, and type. |
| “This is the Regalia Gold card, not the older Regalia.” | Match the distinct Regalia Gold catalog record. | Assert the catalog card ID and reject the legacy-card match. |
| “The lounge benefit is four visits per quarter now.” | Use the current official entitlement and its applicability conditions. | Assert the structured limit, period, eligibility, and grounding evidence. |
| “This recommendation ignores the card I already own.” | Owned-card eligibility must affect the ranked recommendation. | Require the owned-card constraint and compare the expected winner or explanation. |
| “The explanation promises a discount that is not in the terms.” | The recommendation must omit unsupported savings claims. | Apply a must-not-claim rubric and mark unsupported claims as severe. |

## Failure handling and controls

- Feedback writes are idempotent and independent of triage availability.
- Triage failures remain visible and retryable without losing user text.
- Evaluation runs enforce a case-count limit, concurrency limit, and estimated cost ceiling before and during execution.
- A single failed model call produces a safe per-case failure and does not discard completed results.
- Retrying a run executes only eligible failed cases or creates a new run revision; it never overwrites completed evidence.
- Invalid or unparseable judge output cannot select a winner.
- Partial source outages are visible by provider and do not masquerade as model-quality regressions.
- All admin mutations and customer-linked feedback reads use the existing admin audit requirements.

## API integration

### User-facing endpoint

`feedback-submit` supports `trace-create` for ephemeral recommendations and `submit` for every approved output family. It returns a trace or feedback ID and stable status without exposing triage or admin data.

### Admin gateway actions

The `admin-operator` gateway adds narrowly validated actions for:

- feedback list and detail;
- triage retry;
- data-issue routing, product-defect marking, and dismissal;
- eval-case draft, approval, and retirement;
- eval-run creation, status, cancellation, and result detail; and
- reviewed result and candidate recommendation status.

All list actions are paginated. Mutations use client-generated request IDs and stable error codes.

## Rollout

### Phase 1: Capture

Add the data foundation, server-issued traces for ephemeral recommendations, `feedback-submit`, and contextual text entry on the three approved output families. Exit when ownership, authoritative context resolution, explicit client-reported context labels, idempotency, and failure recovery are verified.

### Phase 2: Triage and approval

Add asynchronous LLM triage and the Action Inbox review flow. Exit when the operator can correct a proposal and approve a reproducible eval case.

### Phase 3: Evaluation runner

Add bounded baseline/candidate runs, deterministic scoring, the pinned judge, cost controls, and System results. Exit when a versioned dataset produces reproducible comparisons and preserves partial failures.

### Phase 4: Decision support

Add regression summaries and candidate recommendations. Exit when no candidate can be recommended with a severe regression or breached cost or latency ceiling.

## Testing

### Database and authorization

- Browser roles cannot read or write feedback and evaluation tables directly.
- The submit endpoint can create feedback only for the authenticated user's eligible output reference.
- Duplicate request IDs create one feedback record.
- Only database-authorized admins can review feedback or operate evals.
- Approved case revisions and completed run results remain immutable.

### Server and LLM boundaries

- Unsupported features and spoofed or foreign output references are rejected.
- Model, prompt, parser, trace, and context metadata are resolved server-side.
- Prohibited raw fields are absent from stored context and function responses.
- Invalid, timed-out, and unavailable triage results preserve the submission.
- Prompt-injection text in feedback, fixtures, or candidate output cannot escape the fixed triage or judge schema or invoke tools.
- Eval inputs, judge outputs, token usage, cost, and latency conform to bounded schemas.
- Randomized A/B assignment is recorded and decoded correctly.
- Severe regressions, cost ceilings, and partial failures block a recommendation as designed.

### Flutter and admin workflow

- Supported outputs show a contextual feedback action with the correct preview.
- Submission handles loading, retry, duplicate, authentication, and success states.
- Action Inbox filters and detail presentation distinguish user, LLM, and admin text.
- Creating an eval requires admin-authored expected behavior and explicit approval.
- System renders queued, running, partial, failed, and completed runs with drill-down.

## Success criteria

- At least 80% of actionable feedback can be triaged without engineering investigation.
- Every approved eval case has admin-authored ground truth and reproducible feature/version context.
- A failed triage or single eval call never loses the original feedback or completed results.
- Baseline and candidate comparisons expose accuracy, severe regressions, latency, and cost in one operator workflow.
- No production behavior changes without a separate human-approved rollout.
