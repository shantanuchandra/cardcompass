import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const directory = path.dirname(fileURLToPath(import.meta.url));
const migration = fs.readFileSync(
  path.join(
    directory,
    "../../supabase/migrations/20260818123000_add_verified_au_and_psb_movie_benefits.sql",
  ),
  "utf8",
);

test("adds the missing AU Zenith+ variant without assigning its offer to Zenith", () => {
  assert.match(migration, /'AU Small Finance Bank',\s*'Zenith\+'/);
  assert.match(
    migration,
    /https:\/\/www\.au\.bank\.in\/premium-banking\/credit-cards\/zenith-plus-credit-card/,
  );
  assert.match(migration, /'max_usage_per_period', 4/);
  assert.match(migration, /'usage_period', 'quarter'/);
  assert.match(migration, /'max_discount_per_transaction', 500/);
  assert.doesNotMatch(
    migration,
    /c\.card_name ILIKE 'Zenith'(?!\+)/,
  );
});

test("maps exact PSB SBI ELITE official terms to PSB Elite only", () => {
  assert.match(
    migration,
    /https:\/\/www\.sbicard\.com\/sbi-card-en\/assets\/docs\/pdf\/banking-tnc\/psb-elite-tnc\.pdf/,
  );
  assert.match(migration, /'annual_cap', 6000/);
  assert.match(migration, /jsonb_build_array\('BookMyShow'\)/);
  assert.match(migration, /\w+\.bank = 'SBI Card'/);
  assert.match(migration, /\w+\.card_name ILIKE 'Psb Elite'/);
});
