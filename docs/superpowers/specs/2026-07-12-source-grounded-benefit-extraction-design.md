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
