import assert from "node:assert/strict";
import test from "node:test";

import {
  persistCrawlerCandidate,
} from "../../supabase/functions/_shared/issuer_card_crawl.ts";

function candidate(overrides = {}) {
  return {
    kind: "card_product",
    canonicalUrl: "https://www.axis.bank.in/cards/credit-card/neo-credit-card",
    proposedName: "Neo Credit Card",
    aliases: ["Axis Neo Credit Card"],
    network: "Visa",
    confidence: 0.94,
    warnings: [],
    sanitizedEvidence: ["Axis Neo Credit Card"],
    ...overrides,
  };
}

function createDb(
  { urlCardId, provenanceCardId, catalogRows = [], aliasRows = [], jobs = [] } =
    {},
) {
  const state = {
    catalogRows,
    aliasRows,
    jobs: [...jobs],
    reviews: [],
    calls: [],
  };

  const result = (table, action, filters, payload) => {
    if (table === "card_catalog_url_keys") {
      return { data: urlCardId ? { card_id: urlCardId } : null, error: null };
    }
    if (table === "card_catalog_provenance") {
      return {
        data: provenanceCardId ? { card_id: provenanceCardId } : null,
        error: null,
      };
    }
    if (table === "card_catalog") {
      return { data: state.catalogRows, error: null };
    }
    if (table === "card_catalog_aliases") {
      return { data: state.aliasRows, error: null };
    }
    if (table === "card_discovery_jobs") {
      if (action === "insert") {
        const row = { id: `job-${state.jobs.length + 1}`, ...payload };
        state.jobs.push(row);
        return { data: row, error: null };
      }
      if (action === "update") {
        const row = state.jobs.find((job) => job.id === filters.id);
        if (row) Object.assign(row, payload);
        return { data: row ?? null, error: null };
      }
      const row = state.jobs.find((job) =>
        job.discovery_source === filters.discovery_source &&
        job.dedupe_key === filters.dedupe_key &&
        job.user_id === null
      ) ?? null;
      return { data: row, error: null };
    }
    if (table === "card_catalog_review_queue") {
      if (action === "upsert") {
        const existing = state.reviews.find((review) =>
          review.discovery_job_id === payload.discovery_job_id
        );
        const row = existing ?? { id: `review-${state.reviews.length + 1}` };
        Object.assign(row, payload);
        if (!existing) state.reviews.push(row);
        return { data: row, error: null };
      }
    }
    return { data: null, error: null };
  };

  const db = {
    state,
    from(table) {
      let action = "select";
      let payload;
      const filters = {};
      const query = {
        select() {
          return query;
        },
        eq(key, value) {
          filters[key] = value;
          return query;
        },
        ilike(key, value) {
          filters[key] = value;
          return query;
        },
        in(key, value) {
          filters[key] = value;
          return query;
        },
        is(key, value) {
          filters[key] = value;
          return query;
        },
        or(value) {
          filters.or = value;
          return query;
        },
        limit() {
          return query;
        },
        insert(value) {
          action = "insert";
          payload = value;
          state.calls.push({ table, action, payload });
          return query;
        },
        upsert(value) {
          action = "upsert";
          payload = value;
          state.calls.push({ table, action, payload });
          return query;
        },
        update(value) {
          action = "update";
          payload = value;
          state.calls.push({ table, action, payload });
          return query;
        },
        maybeSingle() {
          return Promise.resolve(result(table, action, filters, payload));
        },
        single() {
          return Promise.resolve(result(table, action, filters, payload));
        },
        then(resolve, reject) {
          return Promise.resolve(result(table, action, filters, payload)).then(
            resolve,
            reject,
          );
        },
      };
      return query;
    },
    rpc() {
      throw new Error("crawler persistence must not resolve catalog identity");
    },
  };
  return db;
}

test("returns the catalog card on a canonical URL-hash match without queueing crawler work", async () => {
  const db = createDb({ urlCardId: "card-url" });

  const result = await persistCrawlerCandidate(db, "Axis Bank", candidate());

  assert.deepEqual(result, { outcome: "existing", catalogCardId: "card-url" });
  assert.equal(db.state.jobs.length, 0);
  assert.equal(db.state.reviews.length, 0);
});

test("queues a review for one canonical issuer/name match with crawler-only provenance", async () => {
  const db = createDb({
    catalogRows: [{
      id: "card-neo",
      bank: "Axis Bank",
      card_name: "Neo",
      network: "Visa",
    }],
  });

  const result = await persistCrawlerCandidate(db, "Axis Bank", candidate());

  assert.deepEqual(result, { outcome: "review", reviewId: "review-1" });
  assert.equal(db.state.jobs.length, 1);
  assert.deepEqual(db.state.jobs[0].user_id, null);
  assert.equal(db.state.jobs[0].discovery_source, "issuer_crawl");
  assert.equal(db.state.jobs[0].proposed_product, "Neo");
  assert.ok(db.state.jobs[0].dedupe_key.match(/^[a-f0-9]{64}$/));
  assert.deepEqual(db.state.reviews[0].existing_candidates, [
    { id: "card-neo", bank: "Axis Bank", card_name: "Neo", network: "Visa" },
  ]);
  assert.ok(
    db.state.reviews[0].validation_warnings.includes(
      "crawler_discovered_without_statement_signal",
    ),
  );
  assert.equal(
    db.state.calls.some(({ table }) => table === "card_catalog"),
    false,
  );
  assert.equal(
    db.state.calls.some(({ table }) => table === "card_catalog_aliases"),
    false,
  );
  assert.equal(
    db.state.calls.some(({ table }) => table === "card_catalog_provenance"),
    false,
  );
});

test("finds an existing issuer card through a normalized alias and still requires review", async () => {
  const db = createDb({
    catalogRows: [{
      id: "card-alt",
      bank: "Axis Bank",
      card_name: "Alt",
      network: null,
    }],
    aliasRows: [{
      card_id: "card-alt",
      alias: "Axis Neo Credit Card",
      normalized_alias: "neo",
    }],
  });

  const result = await persistCrawlerCandidate(db, "Axis Bank", candidate());

  assert.deepEqual(result, { outcome: "review", reviewId: "review-1" });
  assert.deepEqual(db.state.reviews[0].existing_candidates, [
    { id: "card-alt", bank: "Axis Bank", card_name: "Alt", network: null },
  ]);
});

test("queues ambiguous catalog candidates for review instead of selecting one", async () => {
  const db = createDb({
    catalogRows: [
      { id: "card-one", bank: "Axis Bank", card_name: "Neo", network: "Visa" },
      {
        id: "card-two",
        bank: "Axis Bank",
        card_name: "Neo",
        network: "Mastercard",
      },
    ],
  });

  const result = await persistCrawlerCandidate(db, "Axis Bank", candidate());

  assert.deepEqual(result, { outcome: "review", reviewId: "review-1" });
  assert.equal(db.state.reviews[0].existing_candidates.length, 2);
  assert.ok(
    db.state.reviews[0].validation_warnings.includes(
      "ambiguous_catalog_identity",
    ),
  );
});

test("queues a genuinely new crawler product for review and reuses that service job idempotently", async () => {
  const db = createDb();

  const first = await persistCrawlerCandidate(db, "Axis Bank", candidate());
  const repeated = await persistCrawlerCandidate(db, "Axis Bank", candidate());

  assert.deepEqual(first, { outcome: "review", reviewId: "review-1" });
  assert.deepEqual(repeated, { outcome: "duplicate", reviewId: "review-1" });
  assert.equal(db.state.jobs.length, 1);
  assert.equal(db.state.reviews.length, 1);
  assert.deepEqual(db.state.reviews[0].proposed_fields, {
    issuer: "Axis Bank",
    cardName: "Neo",
    network: "Visa",
    aliases: ["Neo Credit Card", "Axis Neo Credit Card"],
    official_url: "https://www.axis.bank.in/cards/credit-card/neo-credit-card",
  });
});

test("repairs a review-less crawler service job without creating a second job", async () => {
  const db = createDb();
  await persistCrawlerCandidate(db, "Axis Bank", candidate());
  db.state.reviews.length = 0;
  db.state.jobs[0].review_item_id = null;

  const result = await persistCrawlerCandidate(db, "Axis Bank", candidate());

  assert.deepEqual(result, { outcome: "duplicate", reviewId: "review-1" });
  assert.equal(db.state.jobs.length, 1);
  assert.equal(db.state.reviews.length, 1);
  assert.equal(db.state.jobs[0].status, "review_required");
});
