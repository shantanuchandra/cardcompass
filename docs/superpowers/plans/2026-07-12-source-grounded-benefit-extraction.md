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

