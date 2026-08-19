import assert from "node:assert/strict";
import test from "node:test";
import { readFile } from "node:fs/promises";

import {
  diffCatalogFields,
  normalizeMoney,
  normalizeOfficialCatalogPage,
  requireCatalogPageIdentity,
} from "../../supabase/functions/_shared/card_catalog_enrichment.ts";

const catalogEntrypoint = new URL(
  "../../supabase/functions/catalog-enrichment/index.ts",
  import.meta.url,
);

test("normalizes explicit Indian fee and APR values", () => {
  assert.equal(normalizeMoney("₹ 1,500 + GST"), 1500);
  assert.equal(normalizeMoney("INR 0"), 0);
  assert.equal(normalizeMoney("Not applicable"), null);

  const result = normalizeOfficialCatalogPage(
    `
    <html><head><title>White Reserve Credit Card | Kotak</title></head>
    <body>
      <h1>White Reserve Credit Card</h1>
      <dl>
        <dt>Joining Fee</dt><dd>₹ 12,500 + GST</dd>
        <dt>Annual Fee</dt><dd>₹ 12,500 + GST</dd>
        <dt>Finance Charges</dt><dd>3.5% per month (42% annually)</dd>
        <dt>Network</dt><dd>Visa Infinite</dd>
      </dl>
    </body></html>
  `,
    "https://www.kotak.com/rd/white-reserve",
  );

  assert.equal(result.patch.joining_fee?.value, 12500);
  assert.equal(result.patch.annual_fee?.value, 12500);
  assert.equal(result.patch.apr?.value, 42);
  assert.equal(result.patch.network?.value, "Visa");
});

test("backfills null fields but reports non-null conflicts", () => {
  assert.deepEqual(
    diffCatalogFields(
      { network: null, annual_fee: null },
      {
        network: { value: "Visa", confidence: 0.96, evidence: "Network: Visa" },
        annual_fee: {
          value: 1500,
          confidence: 0.95,
          evidence: "Annual Fee ₹1,500",
        },
      },
    ),
    {
      backfill: { network: "Visa", annual_fee: 1500 },
      conflicts: [],
    },
  );

  const conflict = diffCatalogFields(
    { annual_fee: 1000 },
    {
      annual_fee: {
        value: 1500,
        confidence: 0.95,
        evidence: "Annual Fee ₹1,500",
      },
    },
  );
  assert.deepEqual(conflict.backfill, {});
  assert.equal(conflict.conflicts[0].field, "annual_fee");
  assert.equal(conflict.conflicts[0].existing, 1000);
  assert.equal(conflict.conflicts[0].proposed, 1500);

  const privateConflict = diffCatalogFields(
    { network: "https://user:pass@issuer.example/network?token=secret" },
    { network: { value: "Visa", confidence: 0.96, evidence: "Network Visa" } },
  );
  assert.doesNotMatch(
    JSON.stringify(privateConflict),
    /user:pass|token|secret/i,
  );
});

test("extracts grounded benefits without inventing missing values", () => {
  const result = normalizeOfficialCatalogPage(
    `
    <html><body>
      <h2>Dining benefits</h2>
      <p>Get 10% cashback on dining, capped at ₹500 per statement month.</p>
      <p>Airport lounge access: 2 complimentary visits per quarter.</p>
    </body></html>
  `,
    "https://www.example-bank.test/cards/example",
  );

  assert.equal(result.patch.annual_fee, undefined);
  assert.equal(result.benefits.length, 2);
  assert.match(result.benefits[0].evidence, /10% cashback/i);
  assert.equal(result.benefits[0].confidence >= 0.9, true);
  assert.equal(typeof result.benefits[0].dedupeKey, "string");
  assert.equal(result.benefits[0].cap, 500);
  assert.equal(result.benefits[0].period, "statement month");
  assert.match(result.benefits[0].fieldEvidence.cap, /capped at ₹500/i);
});

test("catalog field excerpts and nested benefit evidence remove visible and encoded URL secrets", () => {
  const result = normalizeOfficialCatalogPage(
    `
    <html><body>
      <h1>Privilege Credit Card</h1>
      <p>Annual Fee ₹1,500; terms https://user:pass@www.axis.bank.in/card?token=secret#private</p>
      <p>Get 10% cashback on dining. https%253A%252F%252Fuser%253Apass%2540www.axis.bank.in%252Fcard%253Fsession%253Dsecret</p>
    </body></html>
  `,
    "https://www.axis.bank.in/cards/credit-card/privilege?session=source-secret",
  );
  const serialized = JSON.stringify(result);
  assert.doesNotMatch(
    serialized,
    /user:pass|token|session|source-secret|secret#private/i,
  );
  assert.match(serialized, /Annual Fee/);
});

test("catalog normalization remains bound to the exact target card after redirects", () => {
  assert.equal(
    requireCatalogPageIdentity(
      "<title>Privilege Credit Card | Axis Bank</title>",
      "Axis Bank",
      "Privilege",
    ).cardName,
    "Privilege",
  );
  for (
    const html of [
      "<title>Regalia Credit Card | HDFC Bank</title>",
      "<title>Credit Cards | Axis Bank</title>",
      "<title>Privilege Credit Card | Axis Bank</title><h1>Regalia Gold Credit Card</h1>",
    ]
  ) {
    assert.throws(
      () => requireCatalogPageIdentity(html, "Axis Bank", "Privilege"),
      /identity_mismatch/,
    );
  }
});

test("catalog enrichment passes an invocation deadline to its official fetch", async () => {
  const source = await readFile(catalogEntrypoint, "utf8");
  const call = source.match(
    /fetchOfficialIssuerResource\(\{([\s\S]*?)\n\s*\}\)/,
  );
  assert.ok(call, "catalog official fetch caller was not found");
  assert.match(call[1], /deadlineAt(?:\s*:|\s*,)/);
  assert.match(call[1], /allowedQueryParameters\s*:/);
  assert.match(call[1], /robotsCache(?:\s*:|\s*,)/);
});

test("catalog lifecycle observations create review evidence without directly changing acquisition state", async () => {
  const source = await readFile(catalogEntrypoint, "utf8");
  assert.match(source, /suggested_action:\s*["']mark_discontinued["']/);
  assert.match(
    source,
    /catalog\.is_discontinued\s*===\s*true[\s\S]*["']reactivate["']/,
  );
  assert.match(source, /suggested_action:\s*lifecycleSuggestion/);
  assert.match(source, /source_status:\s*410/);
  assert.doesNotMatch(source, /is_discontinued\s*:/);
  assert.doesNotMatch(source, /\.update\(\{[\s\S]{0,180}is_discontinued/);
});
