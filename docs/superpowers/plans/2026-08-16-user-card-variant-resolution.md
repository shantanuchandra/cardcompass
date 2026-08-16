# User Card Variant Resolution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users resolve an unidentified statement by selecting a bank-scoped catalog variant or submitting an official issuer product URL that is safely deduplicated, verified, attached to every linked statement, and asynchronously used to backfill normalized catalog and benefit data.

**Architecture:** Extend the existing Confirm card dialog and `card-discovery` Edge Function. Canonical URL identities and catalog creation are deduplicated in PostgreSQL; the Edge Function owns URL validation, safe fetching, identity verification, and review routing, while Flutter owns presentation and assignment retry only.

**Tech Stack:** Flutter/Dart, Riverpod, Supabase Postgres, Supabase Edge Functions, Deno/TypeScript, Node test runner.

**Spec:** `docs/superpowers/specs/2026-08-16-user-card-variant-resolution-design.md`

## Global Constraints

- Accept only HTTPS product URLs on the approved official domains for the statement's detected issuer.
- A pasted URL cannot override the detected issuer.
- Automatic resolution still requires official issuer evidence, one agreeing statement signal, a unique identity, confidence of at least `0.90`, and no conflicts.
- Do not store PDF bytes, full PDF text, full card numbers, customer names, addresses, balances, limits, passwords, or transactions in discovery records.
- URL processing remains asynchronous and must not block Gmail sync.
- Card identity resolution must complete before and independently from catalog/benefit enrichment.
- Missing catalog values may be backfilled from official evidence; conflicting non-null values require admin review and are never overwritten automatically.
- Existing uncommitted card-discovery work must be preserved; stage only files owned by the current task.

---

## File Structure

- `supabase/functions/_shared/card_discovery.ts`: pure URL canonicalization, issuer-domain validation, and safe reason-code helpers.
- `supabase/migrations/20260817030000_card_catalog_url_identity.sql`: canonical URL columns/indexes and the service-role transactional catalog resolver.
- `supabase/functions/card-discovery/index.ts`: authenticated `resolve_url` action, known-URL lookup, official fetch, gate evaluation, provenance persistence, and review routing.
- `supabase/functions/_shared/card_catalog_enrichment.ts`: deterministic normalization of official catalog fields and benefit candidates.
- `supabase/functions/catalog-enrichment/index.ts`: asynchronous enrichment worker, conflict detection, catalog backfill, benefit staging, provenance, and retries.
- `lib/core/services/card_discovery_service.dart`: typed URL-resolution request and response models.
- `lib/features/dashboard/screens/dashboard_screen.dart`: search/URL fallback UI and post-resolution assignment.
- `test/supabase/card_discovery_rules.test.mjs`: pure TypeScript security and canonicalization tests.
- `test/supabase/card_catalog_url_identity_test.dart`: migration contract tests for unique URL identity and RPC privileges.
- `test/supabase/card_catalog_enrichment_rules.test.mjs`: normalization, missing-field backfill, conflict, and benefit-grounding tests.
- `test/core/services/card_discovery_service_test.dart`: typed response and safe error mapping tests.
- `test/features/dashboard/card_variant_resolution_test.dart`: dialog search, URL fallback, and outcome widget tests.

---

### Task 1: Canonical URL Identity and Security Rules

**Files:**
- Modify: `supabase/functions/_shared/card_discovery.ts`
- Modify: `test/supabase/card_discovery_rules.test.mjs`

**Interfaces:**
- Consumes: `officialDomainsForIssuer(issuer: string): string[]`.
- Produces: `canonicalOfficialUrl(issuer: string, rawUrl: string): string` and `CardDiscoveryReasonCode`.

- [ ] **Step 1: Write failing canonicalization and issuer-boundary tests**

Add tests asserting this behavior:

```js
assert.equal(
  canonicalOfficialUrl(
    'Kotak Bank',
    'https://WWW.KOTAK.COM:443/rd//white-reserve/?utm_source=gmail&b=2&a=1#fees',
  ),
  'https://www.kotak.com/rd/white-reserve?a=1&b=2',
);
assert.throws(
  () => canonicalOfficialUrl('Kotak Bank', 'https://kotak.com.evil.test/rd/white-reserve'),
  /unapproved_domain/,
);
assert.throws(
  () => canonicalOfficialUrl('Kotak Bank', 'https://user:pass@kotak.com/rd/white-reserve'),
  /invalid_url/,
);
assert.throws(
  () => canonicalOfficialUrl('Kotak Bank', 'http://kotak.com/rd/white-reserve'),
  /invalid_url/,
);
```

Also cover fragments, trailing slashes, default ports, sorted functional parameters, `utm_*`, `gclid`, `fbclid`, deceptive subdomains, and cross-issuer URLs.

- [ ] **Step 2: Run the focused test and verify failure**

Run: `node --test --experimental-strip-types test/supabase/card_discovery_rules.test.mjs`

Expected: FAIL because `canonicalOfficialUrl` is not exported.

- [ ] **Step 3: Implement the pure canonicalizer**

Add the exported type and function:

```ts
export type CardDiscoveryReasonCode =
  | "invalid_url"
  | "unapproved_domain"
  | "issuer_mismatch"
  | "not_product_page"
  | "unsafe_redirect"
  | "fetch_timeout"
  | "unsupported_content"
  | "identity_conflict"
  | "review_required";

export function canonicalOfficialUrl(issuer: string, rawUrl: string): string {
  let url: URL;
  try {
    url = new URL(rawUrl.trim());
  } catch {
    throw new Error("invalid_url");
  }
  if (url.protocol !== "https:" || url.username || url.password) {
    throw new Error("invalid_url");
  }
  if (!allowedOfficialUrl(issuer, url.toString())) {
    throw new Error("unapproved_domain");
  }
  url.hash = "";
  url.port = "";
  url.pathname = url.pathname.replace(/\/{2,}/g, "/").replace(/\/$/, "") || "/";
  const kept = [...url.searchParams.entries()]
    .filter(([key]) => !/^utm_/i.test(key) && !["gclid", "fbclid"].includes(key.toLowerCase()))
    .sort(([ak, av], [bk, bv]) => ak.localeCompare(bk) || av.localeCompare(bv));
  url.search = "";
  for (const [key, value] of kept) url.searchParams.append(key, value);
  return url.toString();
}
```

- [ ] **Step 4: Run the focused test and verify success**

Run: `node --test --experimental-strip-types test/supabase/card_discovery_rules.test.mjs`

Expected: all card-discovery rule tests PASS.

- [ ] **Step 5: Commit the isolated unit**

```bash
git add supabase/functions/_shared/card_discovery.ts test/supabase/card_discovery_rules.test.mjs
git commit -m "feat: canonicalize official card URLs"
```

---

### Task 2: PostgreSQL URL Dedupe and Transactional Catalog Resolution

**Files:**
- Create: `supabase/migrations/20260817030000_card_catalog_url_identity.sql`
- Create: `test/supabase/card_catalog_url_identity_test.dart`

**Interfaces:**
- Consumes: canonical submitted/final URL strings and SHA-256 hashes produced by the Edge Function.
- Produces: service-role RPC `resolve_card_catalog_identity(_issuer text, _card_name text, _network text, _source_url text, _submitted_url_hash text, _final_url_hash text) returns uuid`.
- Produces: service-role table `card_catalog_enrichment_jobs`, unique on `(card_id, final_url_hash, content_hash)`.

- [ ] **Step 1: Write a failing migration contract test**

Create a test that reads the migration and asserts it contains:

```dart
expect(sql, contains('canonical_submitted_url text'));
expect(sql, contains('canonical_final_url text'));
expect(sql, contains('submitted_url_hash text'));
expect(sql, contains('final_url_hash text'));
expect(sql, contains('create unique index'));
expect(sql, contains('resolve_card_catalog_identity'));
expect(sql, contains('pg_advisory_xact_lock'));
expect(sql, contains('revoke all on function'));
expect(sql, contains('grant execute on function'));
```

Also assert the function normalizes issuer/product identity inside its transaction and is executable by `service_role` only.

- [ ] **Step 2: Verify that the contract test fails**

Run: `flutter test test/supabase/card_catalog_url_identity_test.dart`

Expected: FAIL because the migration does not exist.

- [ ] **Step 3: Add URL identity columns and indexes**

The migration must add nullable canonical URL and hash columns to `card_catalog_provenance`, backfill existing HTTPS `source_url` values conservatively, then add partial unique indexes:

```sql
CREATE UNIQUE INDEX ... ON public.card_catalog_provenance(submitted_url_hash)
WHERE submitted_url_hash IS NOT NULL;

CREATE UNIQUE INDEX ... ON public.card_catalog_provenance(final_url_hash)
WHERE final_url_hash IS NOT NULL;
```

Use `NULLS NOT DISTINCT` only if the live PostgreSQL version supports it; otherwise keep the two partial indexes above.

- [ ] **Step 4: Add the transactional resolver RPC**

The function must:

1. Reject blank issuer/card names and non-HTTPS source URLs.
2. Acquire `pg_advisory_xact_lock(hashtextextended(lower(trim(_issuer)) || ':' || lower(regexp_replace(_card_name, '[^a-zA-Z0-9]+', '', 'g')), 0))`.
3. Return a card already referenced by either URL hash.
4. Otherwise find exactly one active same-issuer card by normalized canonical name or alias.
5. Insert one `card_catalog` record only when no identity exists.
6. Return the resolved UUID without modifying user-owned data.
7. Revoke public/anonymous/authenticated execution and grant only `service_role`.

Create `card_catalog_enrichment_jobs` with card ID, canonical URL, final URL hash, content hash, status (`queued`, `processing`, `completed`, `review_required`, `failed`), attempt count, next retry time, normalized fields, warnings, and timestamps. Enable RLS, revoke client access, grant service-role access, and enforce uniqueness on `(card_id, final_url_hash, content_hash)`.

- [ ] **Step 5: Run contract and database tests**

Run:

```bash
flutter test test/supabase/card_catalog_url_identity_test.dart
npm run test:supabase
```

Expected: PASS, including existing migration security tests.

- [ ] **Step 6: Commit the database unit**

```bash
git add supabase/migrations/20260817030000_card_catalog_url_identity.sql test/supabase/card_catalog_url_identity_test.dart
git commit -m "feat: deduplicate card catalog source URLs"
```

---

### Task 3: Authenticated `resolve_url` Discovery Operation

**Files:**
- Modify: `supabase/functions/card-discovery/index.ts`
- Modify: `test/supabase/card_discovery_rules.test.mjs`

**Interfaces:**
- Consumes: `{ action: "resolve_url", evidence: SafeEvidence, source_url: string }`.
- Produces: `{ job_id, status, resolved_card_id, reason_code, retry_after }` with status `resolved`, `review_required`, or `failed`.
- Calls: `resolve_card_catalog_identity(...)` from Task 2.

- [ ] **Step 1: Add failing request-contract and reason-code tests**

Extract and test `publicDiscoveryResult`, `findCatalogCardByUrlHashes`, and `publicReasonCode`:

```ts
assert.deepEqual(
  publicDiscoveryResult({id: 'j1', status: 'resolved', resolved_card_id: 'c1'}),
  {job_id: 'j1', status: 'resolved', resolved_card_id: 'c1', reason_code: null, retry_after: null},
);
```

Add tests proving a known submitted/final URL resolves before fetching, an issuer mismatch returns `issuer_mismatch`, generic issuer roots return `not_product_page`, and internal exception text is mapped to one of the public reason codes.

- [ ] **Step 2: Run tests and verify failure**

Run: `node --test --experimental-strip-types test/supabase/card_discovery_rules.test.mjs`

Expected: FAIL because the public result and URL-resolution helpers do not exist.

- [ ] **Step 3: Implement known-URL lookup and safe fetching**

Canonicalize the submitted URL, hash it, and query provenance by either URL hash before calling `fetchOfficial`. For a fetch:

- Continue using manual redirects and the 12-second timeout.
- Canonicalize and validate every redirect target before the next request.
- Revalidate the final URL and hash both canonical forms.
- Preserve the two-megabyte response cap and content-type allowlist.
- Map timeout, redirect, and content failures to stable reason codes.

Do not return response bodies or raw database errors.

- [ ] **Step 4: Implement identity verification and persistence**

Use the existing safe evidence, normalizer, gate, and review helpers. A verified URL must call:

```ts
const { data: cardId, error } = await db.rpc("resolve_card_catalog_identity", {
  _issuer: evidence.issuer,
  _card_name: canonical.cardName,
  _network: canonical.network ?? evidence.network ?? null,
  _source_url: finalCanonicalUrl,
  _submitted_url_hash: submittedHash,
  _final_url_hash: finalHash,
});
```

Then upsert aliases and provenance with both canonical URLs/hashes, mark the discovery job `resolved`, and return the safe public result. Conflicts and insufficient evidence call `putInReview`; retryable network failures keep bounded backoff.

After identity resolution, upsert one `card_catalog_enrichment_jobs` row and start `catalog-enrichment` with `EdgeRuntime.waitUntil`. Do not await enrichment before returning the resolved card ID.

- [ ] **Step 5: Add the authenticated action branch**

Validate `body.source_url` as a bounded string, reuse the user/evidence discovery job, and await user-submitted URL resolution so the dialog receives a definitive immediate result. Automatic sitemap discovery remains asynchronous via `EdgeRuntime.waitUntil`.

- [ ] **Step 6: Run Edge Function and rule tests**

Run:

```bash
node --test --experimental-strip-types test/supabase/card_discovery_rules.test.mjs
deno check supabase/functions/card-discovery/index.ts
```

Expected: PASS with no TypeScript errors.

- [ ] **Step 7: Commit the server unit**

```bash
git add supabase/functions/card-discovery/index.ts supabase/functions/_shared/card_discovery.ts test/supabase/card_discovery_rules.test.mjs
git commit -m "feat: resolve missing cards from official URLs"
```

---

### Task 4: Asynchronous Catalog and Benefit Enrichment

**Files:**
- Create: `supabase/functions/_shared/card_catalog_enrichment.ts`
- Create: `supabase/functions/catalog-enrichment/index.ts`
- Create: `test/supabase/card_catalog_enrichment_rules.test.mjs`

**Interfaces:**
- Consumes: one `card_catalog_enrichment_jobs` row and the already approved official product URL.
- Produces: normalized `CatalogPatch`, `BenefitCandidate[]`, provenance records, and either `completed`, `review_required`, or retryable `failed` job status.

- [ ] **Step 1: Write failing normalization and conflict tests**

Test a pure normalizer with official-page fixtures:

```ts
assert.deepEqual(normalizeMoney("₹ 1,500 + GST"), 1500);
assert.deepEqual(diffCatalogFields(
  {network: null, annual_fee: null},
  {network: "Visa", annual_fee: 1500},
), {
  backfill: {network: "Visa", annual_fee: 1500},
  conflicts: [],
});
assert.equal(diffCatalogFields(
  {annual_fee: 1000},
  {annual_fee: 1500},
).conflicts[0].field, "annual_fee");
```

Also test joining fee, APR, card type, eligibility, rewards, spend thresholds, fee-waiver conditions, benefit caps, validity text, missing evidence, and deduplication of semantically identical benefits.

- [ ] **Step 2: Run the enrichment rules and verify failure**

Run: `node --test --experimental-strip-types test/supabase/card_catalog_enrichment_rules.test.mjs`

Expected: FAIL because the enrichment helpers do not exist.

- [ ] **Step 3: Implement deterministic catalog normalization**

Export focused pure functions and types:

```ts
export type CatalogPatch = {
  network?: string;
  card_type?: "credit";
  joining_fee?: number;
  annual_fee?: number;
  apr?: number;
};

export type FieldConflict = {
  field: keyof CatalogPatch;
  existing: unknown;
  proposed: unknown;
  confidence: number;
};

export function normalizeOfficialCatalogPage(html: string, sourceUrl: string): {
  patch: CatalogPatch;
  benefits: BenefitCandidate[];
  evidence: Record<string, string>;
};
```

Prefer JSON-LD and explicitly labelled issuer-page fields, then bounded visible text patterns. Do not infer absent fees as zero. Every proposed field must carry a sanitized evidence excerpt and confidence.

- [ ] **Step 4: Implement the authenticated service-role worker**

The worker must claim one queued job atomically, fetch through the same approved issuer redirect/size/content controls, verify the content hash, normalize fields, and compare them with current `card_catalog` values.

- Backfill only null catalog columns whose field confidence is at least `0.90`.
- Persist field-level official provenance.
- Never overwrite a disagreeing non-null value; create an admin-review conflict instead.
- Normalize grounded benefits into `card_benefits_staging` using the resolved card ID, official URL, extraction data, confidence, and content hash.
- Publish benefits automatically only where the existing grounded-benefit approval rules permit it; otherwise leave them pending for admin review.
- Mark the job completed only after catalog and benefit persistence succeeds.
- Retry timeouts/network failures with the existing bounded backoff; after three attempts require review.

- [ ] **Step 5: Run enrichment tests and type checking**

Run:

```bash
node --test --experimental-strip-types test/supabase/card_catalog_enrichment_rules.test.mjs
deno check supabase/functions/catalog-enrichment/index.ts
```

Expected: PASS with no TypeScript errors.

- [ ] **Step 6: Commit the enrichment unit**

```bash
git add supabase/functions/_shared/card_catalog_enrichment.ts supabase/functions/catalog-enrichment/index.ts test/supabase/card_catalog_enrichment_rules.test.mjs
git commit -m "feat: backfill card catalog data from official sources"
```

---

### Task 5: Typed Flutter Service and Confirm-Card URL Fallback

**Files:**
- Modify: `lib/core/services/card_discovery_service.dart`
- Modify: `lib/features/dashboard/screens/dashboard_screen.dart`
- Modify: `test/core/services/card_discovery_service_test.dart`
- Create: `test/features/dashboard/card_variant_resolution_test.dart`

**Interfaces:**
- Consumes: `CardIdentityEvidence.toSafeJson()` and the Task 3 response.
- Produces: `Future<CardUrlResolution> resolveUrl(CardIdentityEvidence evidence, String sourceUrl)`.

- [ ] **Step 1: Write failing response-model tests**

Define expected parsing first:

```dart
final result = CardUrlResolution.fromJson(const {
  'job_id': 'job-1',
  'status': 'resolved',
  'resolved_card_id': 'card-1',
  'reason_code': null,
  'retry_after': null,
});
expect(result.isResolved, isTrue);
expect(result.resolvedCardId, 'card-1');
```

Cover resolved, review-required, retryable failure, invalid URL, and unknown reason codes. Unknown codes must map to a generic safe message.

- [ ] **Step 2: Run service tests and verify failure**

Run: `flutter test test/core/services/card_discovery_service_test.dart`

Expected: FAIL because `CardUrlResolution` and `resolveUrl` are absent.

- [ ] **Step 3: Implement the typed client operation**

Add immutable fields `jobId`, `status`, `resolvedCardId`, `reasonCode`, and `retryAfter`, plus `isResolved` and `requiresReview`. Invoke:

```dart
final response = await _db.functions.invoke(
  'card-discovery',
  body: {
    'action': 'resolve_url',
    'evidence': evidence.toSafeJson(),
    'source_url': sourceUrl.trim(),
  },
);
```

Convert non-2xx responses to a typed safe exception using only known reason codes.

- [ ] **Step 4: Write failing dialog tests**

Override the existing bank-search and card-resolution providers plus a new URL-resolution provider. Assert:

- Alias-aware bank results render and other issuers do not.
- Empty results display **Can't find it? Paste official card page**.
- URL input rejects malformed/non-HTTPS text before submission.
- Resolved response invokes the existing assignment with `resolved_card_id`.
- Review-required response displays that review continues in the background.
- Cancel remains available during queued/review state.

- [ ] **Step 5: Run dialog tests and verify failure**

Run: `flutter test test/features/dashboard/card_variant_resolution_test.dart`

Expected: FAIL because the URL fallback is absent.

- [ ] **Step 6: Implement the dialog state and UI**

Keep the existing search as the primary path. Add an expandable URL fallback below results with:

- `TextEditingController` disposed by the state.
- Client-side HTTPS syntax validation for immediate feedback only.
- Disabled submit while resolving.
- Safe messages for invalid URL, issuer mismatch, review required, fetch timeout, and generic failure.
- On resolved result, call the existing `cardResolutionProvider` with the returned catalog ID, invalidate `dashboardProvider`, and close.
- On review-required result, keep the dialog closable and do not block sync.

Move no scraping or issuer-domain trust logic into Flutter.

- [ ] **Step 7: Run focused Flutter tests**

Run:

```bash
flutter test test/core/services/card_discovery_service_test.dart
flutter test test/features/dashboard/card_variant_resolution_test.dart
flutter analyze lib/core/services/card_discovery_service.dart lib/features/dashboard/screens/dashboard_screen.dart
```

Expected: PASS with no analyzer findings.

- [ ] **Step 8: Commit the client unit**

```bash
git add lib/core/services/card_discovery_service.dart lib/features/dashboard/screens/dashboard_screen.dart test/core/services/card_discovery_service_test.dart test/features/dashboard/card_variant_resolution_test.dart
git commit -m "feat: add official URL fallback for card resolution"
```

---

### Task 6: Live Supabase Integration and Regression Verification

**Files:**
- Modify only when a failing verification identifies a defect in files owned by Tasks 1-5; record the failing command before editing.

**Interfaces:**
- Consumes: deployed migration and `card-discovery` Edge Function.
- Produces: verified localhost resolution against live Supabase without duplicate catalog/user-card records.

- [ ] **Step 1: Run the complete automated suite before deployment**

Run:

```bash
flutter test
npm test
node --test --experimental-strip-types test/supabase/card_discovery_rules.test.mjs
deno check supabase/functions/card-discovery/index.ts
flutter analyze
```

Expected: all commands PASS. If unrelated pre-existing failures remain, record their exact test names and confirm focused feature tests pass before proceeding.

- [ ] **Step 2: Apply the migration and deploy the Edge Function**

Use the repository's linked Supabase project:

```bash
supabase db push
supabase functions deploy card-discovery
supabase functions deploy catalog-enrichment
```

Expected: migration applies once and function deployment succeeds. Do not use destructive database reset commands.

- [ ] **Step 3: Build and serve the localhost app**

Run:

```bash
flutter build web --release --base-href /app/
```

Serve using the existing port `54321` process/configuration and reload `http://127.0.0.1:54321/app/#/app` with a cache-busting query parameter.

- [ ] **Step 4: Verify existing-catalog search live**

For an unknown card, open **Confirm card**, search within its bank, select an existing variant, and verify:

- No other bank's variants appear.
- The card is assigned once.
- Linked June/July statements retry.
- No duplicate `user_cards` row appears.

- [ ] **Step 5: Verify official URL resolution and dedupe live**

Submit one official issuer product URL with tracking parameters, then submit its clean canonical form for the same unresolved identity. Verify:

- Both resolve to the same catalog card ID.
- Exactly one canonical/final URL identity exists.
- Exactly one user card exists for the user/catalog identity.
- Cross-issuer and deceptive-domain URLs fail with safe messages.
- Ambiguous evidence enters the admin queue without interrupting Gmail sync.
- The resolved card immediately becomes usable before enrichment completes.
- Missing network/fee fields are backfilled after enrichment.
- Existing conflicting values remain unchanged and appear in admin review.
- Grounded benefits are staged or published according to existing approval rules without duplicates.

- [ ] **Step 6: Re-run focused tests after live verification**

Run:

```bash
flutter test test/core/services/card_discovery_service_test.dart test/features/dashboard/card_variant_resolution_test.dart
node --test --experimental-strip-types test/supabase/card_discovery_rules.test.mjs
git diff --check
```

Expected: PASS and no whitespace errors.

- [ ] **Step 7: Commit any verified corrective changes**

If no corrections were needed, do not create an empty commit. Otherwise stage only the corrected Task 1-5 files and run:

```bash
git commit -m "fix: harden card URL resolution integration"
```
