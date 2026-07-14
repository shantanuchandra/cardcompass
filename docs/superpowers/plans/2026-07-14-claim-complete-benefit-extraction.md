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
