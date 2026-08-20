import test from "node:test";
import assert from "node:assert/strict";
import { readdir, readFile } from "node:fs/promises";

const migrations = new URL("../../supabase/migrations/", import.meta.url);

async function lifecycleMigration() {
  const names = (await readdir(migrations)).filter((name) =>
    name.endsWith("_card_ingestion_lifecycle_hardening.sql")
  );
  assert.equal(names.length, 1, "expected one lifecycle migration");
  return readFile(new URL(names[0], migrations), "utf8");
}

function activeAt({ retiredAt, validFrom, validUntil }, now) {
  const utcDate = now.toISOString().slice(0, 10);
  return (retiredAt === null || retiredAt > now.toISOString()) &&
    (validFrom === null || validFrom <= utcDate) &&
    (validUntil === null || validUntil >= utcDate);
}

test("active view owns retirement and PostgreSQL UTC-date eligibility", async () => {
  const sql = await lifecycleMigration();
  const view = sql.match(
    /CREATE OR REPLACE VIEW public\.active_card_benefits[\s\S]*?;\n/i,
  )?.[0] ?? "";

  assert.match(view, /WITH \(security_invoker = true\)/i);
  assert.match(
    view,
    /mapping\.retired_at IS NULL OR mapping\.retired_at > now\(\)/i,
  );
  assert.match(
    view,
    /timezone\('UTC', statement_timestamp\(\)\)::date AS utc_date/i,
  );
  assert.match(
    view,
    /benefit\.valid_from IS NULL[\s\S]*benefit\.valid_from <= database_clock\.utc_date/i,
  );
  assert.match(
    view,
    /benefit\.valid_until IS NULL[\s\S]*benefit\.valid_until >= database_clock\.utc_date/i,
  );
});

test("eligibility boundary matrix keeps future retirement and null validity active", () => {
  const now = new Date("2026-08-20T12:00:00.000Z");
  const cases = [
    [
      "null validity",
      { retiredAt: null, validFrom: null, validUntil: null },
      true,
    ],
    [
      "expired",
      { retiredAt: null, validFrom: null, validUntil: "2026-08-19" },
      false,
    ],
    ["future validity", {
      retiredAt: null,
      validFrom: "2026-08-21",
      validUntil: null,
    }, false],
    ["retired mapping", {
      retiredAt: "2026-08-20T11:59:59.999Z",
      validFrom: null,
      validUntil: null,
    }, false],
    ["future retirement", {
      retiredAt: "2026-08-20T12:00:00.001Z",
      validFrom: null,
      validUntil: null,
    }, true],
    ["valid-until inclusive UTC day", {
      retiredAt: null,
      validFrom: null,
      validUntil: "2026-08-20",
    }, true],
  ];
  for (const [label, input, expected] of cases) {
    assert.equal(activeAt(input, now), expected, label);
  }
});
