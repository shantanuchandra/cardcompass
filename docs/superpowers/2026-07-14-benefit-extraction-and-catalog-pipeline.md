# Benefit Extraction & Catalog Approval Pipeline


---
## Sub-Component: 2026-07-12-source-grounded-benefit-extraction.md

# Source-Grounded Benefit Extraction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reject unsupported or contaminated credit-card benefit extractions, retain rejected attempts for audit, and stage only evidence-grounded results.

**Architecture:** Add a pure Dart evidence/semantic validator between scraping and staging, strengthen the Gemini schema so every claim carries source evidence, and persist deterministic validation metadata. Revalidate before approval, expose actual validation state in the PM screen, and provide a controlled revalidation path for historical pending records.

**Tech Stack:** Flutter/Dart, Supabase/Postgres, Gemini JSON extraction, `flutter_test`.

## Global Constraints

- Never infer benefits absent from the scraped source.
- Every accepted claim must cite an excerpt present in the supplied evidence text.
- Invalid attempts are retained with `status = 'rejected'` and structured reasons.
- Batch extraction must not auto-approve results.
- Null fee values must not overwrite catalog fees.
- Existing active benefits remain unchanged until a validated pending extraction is explicitly approved.

---

### Task 1: Pure semantic validator and regression fixtures

**Files:**
- Create: `lib/core/services/benefit_extraction_validator.dart`
- Create: `test/benefit_extraction_validator_test.dart`

**Interfaces:**
- Produces: `BenefitExtractionValidator.validate({required Map<String, dynamic> extractedData, required String evidenceText, required String cardName, required String bankName, String? sourceUrl}) -> BenefitValidationResult`.
- Produces: `BenefitValidationResult.toJson()` with `accepted`, `confidence`, `reasons`, `warnings`, and `normalizedData`.

- [ ] Write failing tests proving that grounded numeric claims pass; evidence-free claims, zero-value placeholders, account/loan contamination, category conflicts, unsupported numbers, duplicate claims, and card identity mismatches fail.
- [ ] Run `flutter test test/benefit_extraction_validator_test.dart` and confirm failure because the validator does not exist.
- [ ] Implement normalization, evidence matching, numeric grounding, contamination detection, category consistency, duplicate detection, and deterministic confidence.
- [ ] Run the focused test and confirm all validator tests pass.

### Task 2: Grounded AI extraction contract

**Files:**
- Modify: `lib/core/services/gemini_transaction_parser.dart`
- Create: `test/gemini_benefit_prompt_test.dart`

**Interfaces:**
- Produces: `GeminiTransactionParser.buildBenefitExtractionPromptForTesting(cardName, bankName)` only if an existing public prompt hook is unavailable; prefer a public immutable prompt builder used by production.
- Output benefit rows include `evidence_excerpt` and omit unsupported category filler.

- [ ] Write a failing prompt-contract test requiring evidence, null-on-missing rules, source-only instructions, and explicit prohibitions against navigation/account/loan text and schema completion.
- [ ] Run the focused test and confirm the missing contract fails.
- [ ] Update the prompt and parsing failure handling so malformed/non-object responses return an extraction failure rather than a superficially successful payload.
- [ ] Run the focused prompt and validator tests.

### Task 3: Staging validation lifecycle and schema

**Files:**
- Create: `supabase/migrations/20260712190000_ground_benefit_extractions.sql`
- Modify: `lib/core/services/advanced_benefit_calculation_service.dart`
- Create: `test/benefit_staging_policy_test.dart`

**Interfaces:**
- Consumes: `BenefitExtractionValidator.validate`.
- Produces: `BenefitStagingPolicy.buildInsertPayload(...)` and `BenefitStagingPolicy.canApprove(...)` as pure helpers testable without Supabase.
- Schema adds `validation_version`, `calculated_confidence`, `validation_reasons`, `validation_warnings`, `source_evidence`, `validated_at`, and `rejected_at`.

- [ ] Write failing policy tests: accepted results stage as pending, rejected results stage as rejected, rejected rows have timestamps/reasons, and only accepted current-version rows can be approved.
- [ ] Run focused tests and confirm failure.
- [ ] Implement the migration and pure staging policy.
- [ ] Integrate validation after extraction and before staging; rejected results return `success: false` plus the created rejected staging ID.
- [ ] Revalidate in `applyApprovedBenefits`; fail closed on missing evidence or obsolete validation.
- [ ] Change fee updates to include only explicitly non-null fields.
- [ ] Run validator, prompt, and staging-policy tests.

### Task 4: Scraped evidence quality and source identity

**Files:**
- Modify: `lib/core/services/enhanced_web_scraper.dart`
- Create: `test/enhanced_web_scraper_benefit_content_test.dart`

**Interfaces:**
- Produces: `EnhancedWebScraper.extractBenefitContent` returning concentrated evidence text.
- Produces: `EnhancedWebScraper.validateCardSource(url, content, bankName, cardName)` returning structured validity and reasons.

- [ ] Write failing tests using small HTML fixtures for valid product evidence, unrelated banking promotions, generic support pages, and wrong-card pages.
- [ ] Run the focused test and confirm failure.
- [ ] Implement block-aware HTML cleanup, contamination filtering, official-domain mapping, source-page classification, and card identity matching.
- [ ] Integrate the source check before AI extraction.
- [ ] Run focused extraction tests.

### Task 5: PM display and batch safety

**Files:**
- Modify: `lib/features/debug/pm_pruning_debug_screen.dart`
- Create: `test/pm_benefit_validation_display_test.dart` if widget isolation is practical; otherwise test extracted formatting helpers in `test/benefit_staging_policy_test.dart`.

**Interfaces:**
- PM catalog query reads validation metadata.
- Batch refresh stages pending/rejected results and never calls approval automatically.

- [ ] Write a failing test for actual confidence/status formatting and rejected reason presentation.
- [ ] Remove fixed `95%` confidence and automatic approval calls.
- [ ] Show pending/approved/rejected state, warnings, reasons, and evidence excerpts.
- [ ] Run focused tests.

### Task 6: Historical rectification command and verification

**Files:**
- Create: `tool/revalidate_benefit_staging.dart`
- Create: `test/revalidate_benefit_staging_test.dart`

**Interfaces:**
- The command reads pending rows, validates stored payload/evidence, marks failures rejected, and emits counts/reasons. It does not approve rows or modify active benefits.

- [ ] Write failing tests for dry-run classification and rejected update payloads.
- [ ] Implement dry-run by default and an explicit `--apply` mode.
- [ ] Run the command in dry-run mode against the configured project and inspect aggregate reasons.
- [ ] Run with `--apply` only after dry-run output confirms updates are limited to pending staging records.
- [ ] Re-extract a bounded representative set, inspect results, and iterate validator fixtures for any newly observed false acceptance.
- [ ] Run `dart format`, focused tests, `flutter test`, and `flutter analyze`.
- [ ] Review `git diff --check` and the final diff against the specification.



---
## Sub-Component: 2026-07-13-benefit-refresh-review-and-mapping.md

# Benefit refresh review and mapping-only implementation plan

## Approved scope

- Keep the `benefits` catalog intact.
- Delete all rows in `card_benefit_mapping` and `card_benefits` only.
- Use `card_benefit_mapping` as the sole card-to-benefit relationship.
- Focus subsequent refresh/review work on AU Small Finance Bank — Zenith; do not rerun it during implementation.

## Delivery slices

1. Create the immutable candidate-decision model and tests.
2. Render the approved checkpoint diagram as the review status rail and provide individual/bulk candidate decisions.
3. Add a database migration which resets only the two approved tables, removes deprecated `card_benefits` columns, records staging decisions, and enforces canonical benefit deduplication with `benefits.dedupe_key`.
4. Convert all active card-benefit reads and writes to `card_benefit_mapping` plus canonical `benefits` configurations.
5. Before applying the destructive migration, verify it against a local Supabase database and retain a row-count backup. Do not use it against the remote project until that verification succeeds.

## Approval data path

| Moment | Data stored | Table |
| --- | --- | --- |
| Product page scraped | Transient page content | none |
| Identity/claim grounding succeeds or fails | Candidate snapshot, evidence, validation result | `card_benefits_staging` |
| Operator accepts/rejects candidates | Per-item decisions and reviewer/timestamp | `card_benefits_staging` |
| Accepted candidate has a known canonical key | Existing benefit reused | `benefits` |
| Accepted candidate is new | New canonical benefit, guarded by unique `dedupe_key` | `benefits` |
| Final approval | Selected card mapped to each accepted canonical benefit | `card_benefit_mapping` |
| All candidates rejected/discarded/revalidation fails | Audit status only; active mappings unchanged | `card_benefits_staging` |

`card_benefits` is not part of this new pipeline.


---
## Sub-Component: 2026-07-14-catalog-entry-approval.md

# Catalog entry approval implementation plan

**Goal:** Close the black hole where user-submitted new-card requests queue into `card_benefits_staging` but never reach `card_catalog`.

**Architecture:** Keep the existing submit path (`request-card-catalog-entry` edge function → `submit_card_catalog_request` RPC). Add service-role RPCs for list/approve/reject, an `admin-catalog-entry` edge function that calls them with the caller's auth token, a small Dart service + policy layer (TDD), and a third tab on `pm_pruning_debug_screen.dart`. On approve, kick off the same benefit extraction pipeline used by the Card Benefits Refresh tab.

**Tech stack:** Supabase Postgres (SECURITY DEFINER RPCs), Supabase Edge Functions, Flutter/Dart unit tests.

## Approval data path

| Moment | Data stored | Table |
| --- | --- | --- |
| User submits unmatched card URL during sync | `request_type: catalog_entry`, `card_id = NULL`, `status = pending` | `card_benefits_staging` |
| Admin lists pending requests | Read via `admin-catalog-entry` → `list_pending_catalog_entry_requests` | `card_benefits_staging` |
| Admin approves | New or existing catalog row; staging linked with `card_id`, `status = approved` | `card_catalog`, `card_benefits_staging` |
| Admin rejects | `status = rejected`, reviewer metadata | `card_benefits_staging` |
| Post-approve (Flutter) | Benefit extraction staged for PM review | `card_benefits_staging` (benefit workflow) |

## File structure

- `supabase/migrations/20260714130000_catalog_entry_approval.sql` — list/approve/reject RPCs
- `supabase/functions/admin-catalog-entry/index.ts` — authenticated admin proxy
- `lib/core/services/catalog_entry_staging_policy.dart` — row classification + field parsing
- `lib/core/services/catalog_entry_review_service.dart` — edge-function client
- `lib/features/debug/widgets/catalog_entry_requests_panel.dart` — PM tab UI
- `test/catalog_entry_staging_policy_test.dart`
- `test/catalog_entry_review_service_test.dart`

## Tasks

- [x] Confirm approval surface: PM debug screen tab (no new auth gate)
- [x] Confirm post-approval: auto benefit extraction
- [x] Policy + service unit tests (TDD)
- [x] Postgres RPCs (service_role only)
- [x] Edge function
- [x] PM tab UI wired to service + extraction

---
## Sub-Component: 2026-07-14-evidence-repair-pass.md

# Evidence-grounded benefit repair pass

## Objective

After the first LLM extraction, run a narrowly scoped second LLM call only for
material, source-backed claims that were omitted or whose qualifiers were lost.
The second pass must create review candidates only; it must never alter active
benefit mappings or the database schema.

## Guardrails

- Keep `benefits` as the canonical benefit catalogue and
  `card_benefit_mapping` as the only card-to-benefit relationship.
- Do not create tables or change schema.
- Do not auto-approve or apply any repaired candidate.
- Give the repair model only deterministic evidence targets, require verbatim
  evidence, and reject output that cannot be tied to a target.
- Preserve the source text for review and validate repaired candidates through
  the existing grounding validator before staging.

## Tasks

1. Add evidence segmentation tests that retain monetary abbreviations such as
   `Rs.` and preserve the complete source clause used for grounding.
2. Implement the evidence segmenter and use it for source-coverage validation.
3. Add tests for selecting only material missing/incomplete claims as repair
   targets, excluding headings and generic text.
4. Implement a repair service that produces scoped targets, merges only
   grounded repair candidates, and records repair metadata in the staged JSON.
5. Add a typed second-pass LLM prompt and response parser to the existing AI
   provider path, so Gemini/Ollama use the same configured provider.
6. Wire the repair pass after the initial extraction and before staging;
   revalidate the merged data and gracefully retain the first-pass result if
   the repair call fails.
7. Show repaired candidates as clearly labelled items in the existing review
   flow, retaining individual and bulk decisions.
8. Run focused tests, then a web build. Do not use Docker or change database
   schema/data.


---
## Sub-Component: 2026-07-14-claim-complete-benefit-extraction.md

# Claim-Complete Benefit Extraction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preserve every source-backed card-benefit claim and its qualifiers for human review, while clearly flagging source claims that the extraction omitted.

**Architecture:** Keep the existing Gemini extraction and staging tables. Strengthen the prompt to return atomic claims with complete qualifiers, add deterministic coverage auditing to the source-grounding validator, and expose the audit findings as review candidates that cannot be silently omitted. Existing accepted-card mapping writes remain unchanged: canonical rows are deduplicated in `benefits` and relations are written only to `card_benefit_mapping`.

**Tech Stack:** Flutter/Dart, Supabase/Postgres staging, Gemini structured JSON extraction, Flutter tests.

## Global Constraints

- Do not create new database tables or modify the schema.
- Do not write to `card_benefits`; use `benefits` plus `card_benefit_mapping` only.
- Every stored claim must retain a verbatim `evidence_excerpt` from the official source.
- Source claims that are not extracted must be shown for reviewer decision; never auto-apply them.
- Keep the existing PM review route and individual/bulk accept/reject controls.

---

### Task 1: Make extraction claim-complete and qualifier-preserving

**Files:**
- Modify: `lib/core/services/gemini_transaction_parser.dart:455-545`
- Test: `test/gemini_benefit_prompt_test.dart`

**Interfaces:**
- Consumes: official card-page text appended after `CONTENT TO ANALYZE:`.
- Produces: existing `cashback_benefits`, `reward_points`, and `special_benefits` JSON with `evidence_excerpt`; each claim contains all source qualifiers in `conditions`/`excluded_categories`/numeric fields.

- [ ] **Step 1: Write failing prompt-contract tests**

```dart
test('benefit prompt requires atomic claims and source coverage', () {
  final prompt = GeminiTransactionParser.buildBenefitExtractionPrompt(
    'Zenith',
    'AU Small Finance Bank',
  ).toLowerCase();

  expect(prompt, contains('atomic claim'));
  expect(prompt, contains('one card benefit may produce multiple claims'));
  expect(prompt, contains('all qualifying conditions'));
  expect(prompt, contains('do not omit a source-backed entitlement'));
  expect(prompt, contains('exclusions'));
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/gemini_benefit_prompt_test.dart`

Expected: FAIL because the current prompt has no atomic-claim or completeness instructions.

- [ ] **Step 3: Extend the extraction contract**

Add these rules immediately after the existing grounding rules:

```text
- Return atomic claims. When one paragraph contains an entitlement plus an eligibility rule, cap, exclusion, or redemption condition, preserve every part in that claim's structured fields.
- A source sentence may produce more than one claim when it describes genuinely different card entitlements; do not merge them merely because they share a section.
- Do not omit a source-backed entitlement because it lacks a numeric value. Extract card-specific hotel, dining, insurance, concierge, forex, and travel offers when supported.
- For lounge, fuel, rewards, insurance, and travel offers, preserve thresholds, date/quarter rules, caps, transaction ranges, exclusions, request requirements, and geographic restrictions verbatim in `conditions`.
- After extracting, scan every benefit-like source sentence once more. If it supports a card-specific entitlement, it must appear in the returned JSON with its exact `evidence_excerpt`.
```

Clarify the JSON comments so `conditions` is required whenever the evidence includes a qualifier and `special_benefits.value` may be a nonnumeric entitlement label.

- [ ] **Step 4: Run the prompt tests**

Run: `flutter test test/gemini_benefit_prompt_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit the prompt contract**

```bash
git add lib/core/services/gemini_transaction_parser.dart test/gemini_benefit_prompt_test.dart
git commit -m "feat: require complete grounded benefit claims"
```

### Task 2: Audit source coverage and preserve reviewer-only omissions

**Files:**
- Modify: `lib/core/services/benefit_extraction_validator.dart:1-280`
- Test: `test/benefit_extraction_validator_test.dart`

**Interfaces:**
- Produces `BenefitValidationResult.warnings` entries with code `unextracted_source_claim` and JSON fields `message`, `source_excerpt`, and `suggested_kind`.
- Does not make a grounded extraction unsafe solely because coverage warnings exist; warnings are review candidates and remain non-auto-applied.

- [ ] **Step 1: Write failing validator tests for source coverage**

```dart
test('warns when a source-backed hotel offer has no extracted claim', () {
  const hotelEvidence =
      'Experience luxury stay at ITC Hotels. Stay for 3, Pay for 2.';
  final result = BenefitExtractionValidator.validate(
    extractedData: extraction(),
    evidenceText: '$evidence\n$hotelEvidence',
    cardName: 'Airtel',
    bankName: 'Axis Bank',
  );

  expect(
    result.warnings.map((warning) => warning.code),
    contains('unextracted_source_claim'),
  );
  expect(
    result.warnings.single.message,
    contains('ITC Hotels'),
  );
});

test('does not warn when an evidence excerpt covers the source claim', () {
  const lounge =
      '8 complimentary domestic lounge access annually, subject to ₹50,000 prior-quarter spend.';
  final data = extraction(benefits: [
    {
      'category': 'LOUNGE',
      'description': '8 complimentary domestic lounge access annually',
      'conditions': 'subject to ₹50,000 prior-quarter spend',
      'evidence_excerpt': lounge,
    },
  ]);
  final result = BenefitExtractionValidator.validate(
    extractedData: data,
    evidenceText: '$evidence\n$lounge',
    cardName: 'Airtel',
    bankName: 'Axis Bank',
  );

  expect(result.warnings, isEmpty);
});
```

- [ ] **Step 2: Run the new tests to verify they fail**

Run: `flutter test test/benefit_extraction_validator_test.dart`

Expected: FAIL because no source-coverage audit exists.

- [ ] **Step 3: Implement conservative deterministic coverage audit**

Add `sourceExcerpt` and `suggestedKind` optional fields to `BenefitValidationIssue`; include them in `toJson()`. Add a private `_findUnextractedSourceClaims` method that:

```dart
const markers = <String, String>{
  'foreign mark-up': 'FOREX',
  'concierge': 'CONCIERGE',
  'lounge': 'LOUNGE',
  'reward point': 'REWARDS',
  'fuel surcharge waiver': 'FUEL',
  'air accident': 'INSURANCE',
  'purchase protection': 'INSURANCE',
  'stay for 3': 'TRAVEL',
  'meet & greet': 'TRAVEL',
  'dine with visa': 'DINING',
};
```

Split the evidence into sentences, ignore page-chrome/non-benefit sentences using `_nonBenefitPattern`, and create a warning only when no normalized extracted `evidence_excerpt` contains that source sentence. Invoke this method after claim validation and append warnings; do not change `accepted` or confidence because warnings require an explicit reviewer decision.

- [ ] **Step 4: Run validator tests**

Run: `flutter test test/benefit_extraction_validator_test.dart`

Expected: PASS, including existing evidence, duplicate, and reward tests.

- [ ] **Step 5: Commit the coverage audit**

```bash
git add lib/core/services/benefit_extraction_validator.dart test/benefit_extraction_validator_test.dart
git commit -m "feat: flag source-backed benefits omitted by extraction"
```

### Task 3: Make coverage warnings visible and explicitly reviewable

**Files:**
- Modify: `lib/features/debug/models/benefit_review_candidate.dart:1-180`
- Modify: `lib/features/debug/pm_pruning_debug_screen.dart:1870-2010`
- Test: `test/features/debug/benefit_review_candidate_test.dart`

**Interfaces:**
- `BenefitReviewState.fromExtractedData(Map<String, dynamic> data, {List<dynamic> coverageWarnings = const []})` returns normal extracted candidates plus one reviewer-only candidate for each `unextracted_source_claim` warning.
- Reviewer-only candidate source includes `requires_manual_completion: true`, `evidence_excerpt`, and `suggested_kind`; it is never included in `applyApprovedBenefits` until the reviewer has supplied/approved a complete benefit payload in the existing edit/review path.

- [ ] **Step 1: Write failing model tests for coverage candidates**

```dart
test('adds an unresolved coverage candidate from an omitted source claim', () {
  final state = BenefitReviewState.fromExtractedData(
    const {'special_benefits': []},
    coverageWarnings: const [
      {
        'code': 'unextracted_source_claim',
        'message': 'Source benefit was not extracted: ITC Hotels offer.',
        'source_excerpt': 'Stay for 3, Pay for 2 at ITC Hotels.',
        'suggested_kind': 'TRAVEL',
      },
    ],
  );

  final item = state.items.single;
  expect(item.kind, 'TRAVEL');
  expect(item.source['requires_manual_completion'], isTrue);
  expect(item.source['evidence_excerpt'], contains('ITC Hotels'));
});
```

- [ ] **Step 2: Run the model test to verify it fails**

Run: `flutter test test/features/debug/benefit_review_candidate_test.dart`

Expected: FAIL because the factory accepts no coverage warnings.

- [ ] **Step 3: Add coverage candidates and wire staging warnings into the dialog**

In `BenefitReviewState.fromExtractedData`, add a unique candidate for each warning where `code == 'unextracted_source_claim'`. Its description is the warning message and its source preserves the exact excerpt and `requires_manual_completion: true`.

In `_openBenefitReview`, select `validation_warnings` alongside `extracted_data`; pass it to `_showReviewDialog`. Change `_showReviewDialog` to accept `List<dynamic> coverageWarnings` and construct state with:

```dart
var reviewState = BenefitReviewState.fromExtractedData(
  candidateData,
  coverageWarnings: coverageWarnings,
);
```

Render `requires_manual_completion` candidates with a visible `SOURCE COVERAGE GAP` label and their exact source excerpt. Keep them unresolved until explicitly rejected or completed; do not let “Accept all” auto-apply an incomplete candidate.

- [ ] **Step 4: Protect application from incomplete coverage candidates**

Before building accepted candidates in `applyApprovedBenefits`, reject an accepted decision whose `source.requires_manual_completion == true` with a clear error: `Complete the source-coverage candidate before applying it.` This preserves the current no-unsafe-write guarantee.

- [ ] **Step 5: Run focused tests and static analysis**

Run:

```bash
flutter test test/features/debug/benefit_review_candidate_test.dart test/benefit_extraction_validator_test.dart test/gemini_benefit_prompt_test.dart
flutter analyze lib/core/services/benefit_extraction_validator.dart lib/core/services/gemini_transaction_parser.dart lib/features/debug/models/benefit_review_candidate.dart lib/features/debug/pm_pruning_debug_screen.dart
```

Expected: all tests PASS and analyzer reports no issues.

- [ ] **Step 6: Commit reviewer coverage controls**

```bash
git add lib/features/debug/models/benefit_review_candidate.dart lib/features/debug/pm_pruning_debug_screen.dart test/features/debug/benefit_review_candidate_test.dart
git commit -m "feat: surface omitted source benefits for review"
```

### Task 4: Verify the AU Zenith lifecycle in the live non-Docker app

**Files:**
- Modify: none unless a verification defect is found.
- Test: `test/app_test.dart`, the focused tests from Task 3, and a release web build.

**Interfaces:**
- Uses the existing static release host at `http://localhost:54321/#/admin/pm`.
- Writes only reviewer-accepted, complete candidates to `benefits` and `card_benefit_mapping`; never writes to `card_benefits`.

- [ ] **Step 1: Run the complete focused test suite**

Run:

```bash
flutter test test/app_test.dart test/gemini_benefit_prompt_test.dart test/benefit_extraction_validator_test.dart test/features/debug/benefit_review_candidate_test.dart test/features/debug/benefit_candidate_review_test.dart
```

Expected: PASS.

- [ ] **Step 2: Build the release web app**

Run: `flutter build web --release --dart-define-from-file=dart_defines.json`

Expected: build completes successfully.

- [ ] **Step 3: Confirm direct PM navigation in Comet**

Open `http://localhost:54321/#/admin/pm`, wait at least four seconds, and confirm the PM route remains visible rather than redirecting to the dashboard.

- [ ] **Step 4: Exercise AU Zenith refresh/review safely**

Refresh only AU Zenith. Confirm the review displays: extracted candidates, any `SOURCE COVERAGE GAP` candidates, and individual/bulk decisions. Reject or complete every gap before applying. Verify the resulting row counts and mappings in the live database: `card_benefits` remains unchanged; only `benefits`, `card_benefit_mapping`, and `card_benefits_staging` change.

- [ ] **Step 5: Commit any verification fix, if needed**

```bash
git add <only-files-changed-by-a-verification-fix>
git commit -m "fix: complete claim coverage verification"
```


---
## Sub-Component: 2026-07-12-source-grounded-benefit-extraction-design.md

# Source-Grounded Benefit Extraction Design

## Goal

Ensure credit-card benefits extracted from bank pages are card-specific, supported by scraped evidence, internally coherent, and safe to stage or apply. Invalid historical and new extractions remain available for audit with a `rejected` status and explicit validation reasons.

## Current Failure Mode

The existing pipeline passes broad page content to an AI prompt that enumerates every benefit category. The model consequently fills categories even when the page does not support them. Navigation, savings-account promotions, loan advertisements, customer-support copy, and unrelated card marketing are interpreted as benefits. Confidence is based mostly on field presence and the model's own score rather than source evidence. The PM screen also presents pending records with a fixed 95% confidence.

## Selected Approach

Use layered source-grounded extraction:

1. Verify the source URL and card-page identity.
2. Reduce scraped HTML to card-relevant evidence while excluding common page chrome and unrelated product promotions.
3. Instruct the model to extract only explicitly supported claims and attach a verbatim evidence excerpt to each claim.
4. Apply deterministic semantic validation to the model output.
5. Stage only accepted results. Persist rejected attempts with reasons and diagnostics.
6. Revalidate a staged result immediately before approval.

Prompt changes alone are insufficient because malformed or contaminated model output must be rejected outside the model. Deterministic validation alone is insufficient because it cannot reliably interpret varied bank-page wording. The layered approach provides both semantic flexibility and enforceable safety boundaries.

## Components

### Source Page Validator

The source-page validator checks that:

- the URL uses HTTPS;
- the host belongs to the expected bank's configured official domains;
- the URL and visible page content resemble a credit-card product page rather than an article, support page, card listing, account page, or unrelated product;
- the target card name, or an accepted normalized alias, occurs in the page title, headings, canonical URL, or concentrated card content.

A source that cannot be tied to the target variant is rejected before AI extraction. Search-engine result pages and generic category pages are never treated as evidence sources.

### Evidence Content Builder

The content builder converts HTML to normalized text blocks and retains blocks containing concrete benefit evidence such as rates, points, currency amounts, caps, thresholds, fees, lounge quantities, named merchants, exclusions, or waiver conditions. It removes scripts, styles, navigation, repeated footer content, calls to action, customer support, savings/current account promotions, loans, wealth-management promotions, generic concierge copy, and unrelated card sections.

The builder preserves enough surrounding text to interpret conditions and produces stable evidence block identifiers for validation and PM display.

### Grounded AI Extractor

The extraction schema contains only claims actually found in the source; it does not request one row per category. Each benefit and fee claim must include:

- normalized category and benefit type;
- description;
- numeric value and unit when explicitly present;
- merchants, thresholds, caps, exclusions, and conditions when explicitly present;
- an exact evidence excerpt;
- the evidence block identifier;
- an ambiguity note when the source is incomplete.

The prompt explicitly prohibits inference from card reputation, model knowledge, nearby products, navigation labels, and the output schema. Missing information must remain null or absent. A benefit without evidence must not be emitted.

### Deterministic Semantic Validator

The validator is a pure Dart component so it can be regression-tested without Supabase or an AI call. It validates:

- card and bank identity after normalization;
- evidence excerpt presence and occurrence in the supplied evidence content;
- exact occurrence of numeric claims in their evidence, including rate, cap, threshold, fee, and lounge count;
- allowed category/value-unit combinations;
- category/description consistency;
- rejection of zero-value placeholders and vague rows such as `Travel benefits`;
- rejection of non-benefits including customer support, EMI conversion availability, savings-account interest, loan advertisements, account promotions, and generic application copy;
- duplicate or near-duplicate claims across categories;
- source contamination indicators;
- minimum evidence coverage for the overall extraction.

The validator returns an accepted/rejected decision, a calculated confidence score, normalized accepted data, warnings, and structured rejection reasons. It never invents missing values.

Confidence is calculated from evidence coverage, source identity strength, numeric support, and completeness of conditions. AI self-confidence is diagnostic only and does not affect acceptance.

### Staging Lifecycle

Every extraction attempt that reaches semantic validation is recorded:

- `pending`: passed validation and awaits PM approval;
- `approved`: passed validation again and was applied;
- `rejected`: failed validation or was explicitly rejected.

Rejected rows retain extracted data, source URL, calculated confidence, validation version, rejection reasons, warnings, and timestamps. Existing pending rows are evaluated with the new validator. Rows that fail become `rejected`; passing rows remain pending but are not automatically approved.

If scraping or source-page identity fails before meaningful extraction data exists, the service returns a failure without creating an empty staging row.

### Approval Safety

`applyApprovedBenefits` reloads the source evidence stored with the staging record and reruns the same validator. Approval fails closed if the validation version is obsolete, evidence is missing, or the result no longer passes. Existing active benefits are not deleted until the replacement has passed validation and database writes can proceed.

Null fee values never overwrite catalog fees with zero. Only explicitly evidenced fee fields update the catalog.

### PM Screen

The PM screen displays the calculated confidence, validation status, warnings, rejection reasons, and evidence excerpts. It does not substitute a fixed confidence for staged data. Rejected records are visibly distinct from pending records, and only validated pending records expose approval actions.

Batch extraction does not auto-approve results. It may create validated pending rows and reject failed attempts, but PM approval remains explicit.

## Data Changes

Extend `card_benefits_staging` with:

- `validation_version` text;
- `calculated_confidence` numeric constrained to 0 through 1;
- `validation_reasons` JSONB array;
- `validation_warnings` JSONB array;
- `source_evidence` JSONB;
- `validated_at` timestamp;
- `rejected_at` timestamp.

The status constraint includes `pending`, `approved`, and `rejected`. Existing data is migrated without losing extracted payloads.

## Error Handling

- Invalid or mismatched sources fail closed.
- Malformed AI output becomes a rejected result with a schema reason.
- Unsupported claims are removed only when remaining supported claims still meet the minimum acceptance threshold; otherwise the entire extraction is rejected.
- Network and AI failures do not change an existing valid active configuration.
- Reprocessing creates a new staging attempt and never mutates an approved historical payload.
- Batch processing continues after card-level failures and reports counts by failure reason.

## Testing

Unit tests cover URL/domain identity, evidence matching, numeric grounding, category consistency, duplicate detection, placeholder rejection, contamination rejection, confidence calculation, and normalization.

Regression fixtures reproduce the observed failures for Airtel Axis, HDFC Swiggy, Amazon Pay ICICI, IDFC Power Plus, HDFC Infinia, SBI Cashback, Axis Cashback, Kotak Indian Oil, and a valid compact extraction. Service tests verify that rejected output is staged as rejected, accepted output is staged as pending, approval revalidates, and null fees do not overwrite catalog data.

Database migration tests verify the status constraint and validation metadata. UI/widget tests verify real confidence and rejection details are rendered without the fixed 95% fallback.

## Rollout and Rectification

1. Deploy the schema migration and validation code.
2. Run the validator over all existing pending records.
3. Mark failures rejected with reasons; do not auto-approve passes.
4. Re-extract rejected and missing card variants from their catalog URLs.
5. Leave variants without trustworthy source evidence unresolved rather than fabricating benefits.
6. Review aggregate rejection reasons, add narrowly scoped regression cases, and repeat re-extraction until remaining failures are source limitations rather than parser defects.

No active benefit configuration is replaced solely because a new extraction exists. Replacement requires a validated pending record and explicit approval.

## Success Criteria

- No staged benefit lacks source evidence.
- No numeric value is accepted unless supported by its evidence excerpt.
- Known placeholder, category-conflict, and page-contamination fixtures are rejected.
- Valid grounded fixtures are accepted without adding unsupported categories.
- Confidence shown in the PM screen equals the deterministic calculated value.
- Existing invalid pending rows are marked rejected with actionable reasons.
- Reprocessing never auto-approves or overwrites active data.


---
## Sub-Component: 2026-07-13-benefit-refresh-review-and-mapping-design.md

# Benefit Refresh Review and Mapping-Only Design

## Purpose

Make the benefit-refresh review understandable at a glance, let an operator accept or reject each candidate benefit or a selected group, and return card-to-benefit ownership to `card_benefit_mapping`.

## Scope

This work changes the admin refresh-review experience and the persistence path used when an approved extraction is applied. It does not rerun AU Zenith or alter staging data as part of the schema migration.

## Review experience

The refresh dialog has two persistent regions on desktop and stacks on narrow screens.

- **Pipeline trace rail:** Shows the exact, ordered checkpoint flow below. Completed stages are teal, the active stage is cyan, future stages are muted, and terminal failure branches are visible but inactive. The active checkpoint is derived from the extraction/staging state.
- **Candidate benefits:** Shows the current active mappings beside the candidate benefits. Every candidate has an explicit Accept or Reject action. Operators can also select unresolved candidates and accept or reject the selected set in one action.

The exact checkpoint sequence is:

1. Select only the requested card.
2. Load official URL from `card_catalog`.
3. Scrape the bank product page.
4. Validate page identity: bank and card.
5. On valid identity, Gemini extracts fees, rewards, cashback, and special benefits. On invalid identity, stop and record the failure.
6. Ground every extracted claim against scraped evidence.
7. On rejected grounding, save a rejected staging record and leave active benefits unchanged. On accepted grounding, save a pending `card_benefits_staging` record.
8. Show current active data versus candidate data.
9. Operator review: discard leaves active data unchanged. Approval revalidates stored evidence. A passing revalidation applies only accepted candidate items for the selected card and marks the staging record approved; a failing revalidation marks it rejected and leaves active data unchanged.

Decision controls provide visible labels, 44px minimum hit areas, keyboard focus states, disabled/loading feedback during persistence, and text labels in addition to color.

## Candidate decisions

`card_benefits_staging.extracted_data` remains the immutable candidate snapshot. The review UI maintains decision state per normalized candidate item:

- `accepted`: eligible for application.
- `rejected`: retained in the staging audit record but excluded from application.
- `unresolved`: blocks final approval until resolved or explicitly bulk-accepted/rejected.

Bulk actions apply only to selected unresolved items. The final approval action remains disabled until all candidate items are resolved. A rejection-only review can finish the staging record without changing active mappings.

The stored staging record must retain per-item decisions and decision timestamps so a future audit can distinguish source extraction from operator judgment.

## Data model

`benefits` is the canonical benefit definition table.

`card_benefit_mapping` is the sole relationship between a catalog card and a canonical benefit. It owns `card_id`, `benefit_id`, display priority, and primary status.

`card_benefits` becomes a historical generic benefit-value/configuration table. It retains exactly:

- `id`
- `benefit_id`
- `value`
- `spending_categories`
- `monthly_cap`
- `annual_cap`
- `valid_from`
- `valid_to`
- `configuration`
- `is_active`
- `created_at`
- `updated_at`

The migration removes `card_id` and all AI/extraction/source-tracking fields from `card_benefits`. Any display or recommendation query that needs a card association must join through `card_benefit_mapping`, not `card_benefits`.

## Confirmed reset boundary

The migration deletes every row from `card_benefit_mapping` and `card_benefits`, in that order. It does **not** delete, rewrite, or attempt to infer historical rows in `benefits`. This is the approved clean start for the single AU Zenith workflow.

`benefits` receives a non-null unique `dedupe_key`, calculated from normalized `benefit_category | benefit_type | title`. Existing duplicate catalog rows are retained: the oldest row receives the canonical key and later duplicate rows receive a unique `legacy:<benefit_id>` key. New approvals look up the canonical key first; the unique index is the final concurrency guard against duplicate creation.

## Approval persistence

For each accepted candidate item:

1. Revalidate its evidence against the stored source evidence.
2. Find or create the canonical `benefits` row using its normalized category, type, and title dedupe key.
3. Upsert `card_benefit_mapping(card_id, benefit_id)` for the selected catalog card.
4. Store card-specific calculation limits in the canonical benefit configuration only when they are part of the accepted benefit definition; do not create a card-linked `card_benefits` row.

For rejected candidate items, persist only the review decision in staging. Do not create a mapping or change active mappings.

## Safety and verification

Before applying the migration:

1. Verify all affected code paths use `card_benefit_mapping` for card associations.
2. Back up the pre-migration row counts and relationship counts.

After applying it:

1. Confirm the retained `card_benefits` columns match this specification exactly.
2. Confirm active card benefits resolve through `card_benefit_mapping`.
3. Confirm a duplicate accepted candidate reuses the canonical `benefits` row.
4. Exercise per-item accept, per-item reject, bulk acceptance, bulk rejection, and approval-time validation failure without rerunning AU Zenith.
5. Run focused Flutter tests and static analysis for changed code.
