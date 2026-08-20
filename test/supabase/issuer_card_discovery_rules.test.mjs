import assert from "node:assert/strict";
import test from "node:test";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";

import {
  persistCrawlerCandidate,
  stageCompleteIssuerDirectoryAbsenceReviews,
} from "../../supabase/functions/_shared/issuer_card_crawl.ts";

const hashUrl = (value) => createHash("sha256").update(value).digest("hex");

test("issuer rotation persists a CAS attempt before background crawl and records failure", async () => {
  const source = await readFile(
    new URL(
      "../../supabase/functions/benefit-enrichment-batch/index.ts",
      import.meta.url,
    ),
    "utf8",
  );
  const load = source.slice(
    source.indexOf("export async function loadDiscoverySeed"),
    source.indexOf("export async function handleBenefitEnrichmentBatch"),
  );
  const run = source.slice(
    source.indexOf("async function runIssuerDiscovery"),
    source.indexOf("export type IssuerDiscoverySeed"),
  );
  assert.match(load, /kind:\s*"issuer_directory_rotation"/);
  assert.match(load, /last_attempt_at:\s*now\.toISOString\(\)/);
  assert.match(
    load,
    /\.eq\("id", previous\.id\)\.eq\("status", previous\.status\)/,
  );
  assert.match(
    run,
    /catch \(error\)[\s\S]*recordIssuerDiscoveryOutcome\(db, job, false/,
  );
  assert.ok(
    source.indexOf("const discoverySeed = await loadDiscoverySeed(db)") <
      source.indexOf("EdgeRuntime.waitUntil("),
    "attempt was not persisted before background work",
  );
});

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
    catalogRows: catalogRows.map((row) => ({
      card_type: "credit",
      is_discontinued: false,
      ...row,
    })),
    aliasRows,
    jobs: [...jobs],
    reviews: [],
    calls: [],
    rpcCalls: [],
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
        const acceptedStatuses = Array.isArray(filters.status)
          ? filters.status
          : filters.status
          ? [filters.status]
          : null;
        if (
          row && (!acceptedStatuses || acceptedStatuses.includes(row.status))
        ) {
          Object.assign(row, payload);
        }
        return { data: row ?? null, error: null };
      }
      const row = state.jobs.find(
        (job) =>
          job.discovery_source === filters.discovery_source &&
          job.dedupe_key === filters.dedupe_key &&
          job.user_id === null,
      ) ?? null;
      return { data: row, error: null };
    }
    if (table === "card_catalog_review_queue") {
      if (action === "select") {
        return {
          data: state.reviews.find((review) =>
            review.discovery_job_id === filters.discovery_job_id
          ) ?? null,
          error: null,
        };
      }
      if (action === "insert") {
        const existing = state.reviews.find((review) =>
          review.discovery_job_id === payload.discovery_job_id
        );
        if (existing) return { data: null, error: { code: "23505" } };
        const row = { id: `review-${state.reviews.length + 1}`, ...payload };
        state.reviews.push(row);
        return { data: row, error: null };
      }
      if (action === "update") {
        const row = state.reviews.find((review) =>
          review.id === filters.id &&
          (!filters.status || review.status === filters.status) &&
          (!("updated_at" in filters) ||
            review.updated_at === filters.updated_at)
        );
        if (row) Object.assign(row, payload);
        return { data: row ?? null, error: null };
      }
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
        is(key, value) {
          filters[key] = value;
          return query;
        },
        in(key, value) {
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
    async rpc(name, args) {
      state.rpcCalls.push({ name, args });
      if (name === "stage_card_catalog_identity_review") {
        let job = args._discovery_job_id
          ? state.jobs.find((row) => row.id === args._discovery_job_id)
          : state.jobs.find((row) =>
            row.discovery_source === args._discovery_source &&
            row.dedupe_key === args._dedupe_key && row.user_id === null
          );
        if (!job) {
          job = {
            id: `job-${state.jobs.length + 1}`,
            user_id: args._user_id,
            discovery_source: args._discovery_source,
            issuer: args._issuer,
            proposed_product: args._proposed_product,
            evidence: {
              ...args._source_evidence,
              semantic_product_hash: args._semantic_hash,
            },
            dedupe_key: args._dedupe_key,
            status: "queued",
            updated_at: "2026-08-20T00:00:00.000Z",
          };
          state.jobs.push(job);
        }
        if (
          args._expected_job_status !== null &&
          (job.status !== args._expected_job_status ||
            job.updated_at !== args._expected_job_updated_at)
        ) {
          return { data: null, error: { message: "catalog_review_job_race" } };
        }
        let review = state.reviews.find((row) =>
          row.discovery_job_id === job.id
        );
        const semantic = args._semantic_hash;
        if (
          review && ["approved", "merged", "rejected"].includes(review.status)
        ) {
          if (review.source_evidence.semantic_product_hash !== semantic) {
            return {
              data: null,
              error: {
                message: "terminal_catalog_review_requires_new_version",
              },
            };
          }
          return {
            data: [{
              job_id: job.id,
              review_item_id: review.id,
              resulting_status: job.status,
              created: false,
            }],
            error: null,
          };
        }
        const historyEntry = {
          observed_at: args._source_evidence.retrieved_at ??
            "2026-08-20T00:00:00.000Z",
          content_hash: args._source_evidence.content_hash ?? null,
          semantic_hash: semantic,
        };
        let created = false;
        if (!review) {
          review = {
            id: `review-${state.reviews.length + 1}`,
            discovery_job_id: job.id,
            proposed_fields: args._proposed_fields,
            source_evidence: {
              ...args._source_evidence,
              semantic_product_hash: semantic,
              observation_history: [historyEntry],
            },
            existing_candidates: args._existing_candidates,
            validation_warnings: args._validation_warnings,
            confidence: args._confidence,
            status: "pending",
            updated_at: "2026-08-20T00:00:00.000Z",
          };
          state.reviews.push(review);
          created = true;
        } else {
          const history = review.source_evidence.observation_history ?? [];
          const withoutReplay = history.filter((entry) =>
            entry.semantic_hash !== semantic
          );
          Object.assign(review, {
            proposed_fields: args._proposed_fields,
            source_evidence: {
              ...args._source_evidence,
              semantic_product_hash: semantic,
              observation_history: [historyEntry, ...withoutReplay].slice(
                0,
                24,
              ),
            },
            existing_candidates: args._existing_candidates,
            validation_warnings: args._validation_warnings,
            confidence: args._confidence,
          });
        }
        job.status = "review_required";
        job.review_item_id = review.id;
        job.evidence = {
          ...job.evidence,
          semantic_product_hash: semantic,
        };
        return {
          data: [{
            job_id: job.id,
            review_item_id: review.id,
            resulting_status: "review_required",
            created,
          }],
          error: null,
        };
      }
      if (name === "publish_card_catalog_identity") {
        const job = state.jobs.find((row) => row.id === args._discovery_job_id);
        if (job) {
          job.status = "resolved";
          job.resolved_card_id = args._reviewed_fields.card_id;
        }
        return {
          data: [{
            card_id: args._reviewed_fields.card_id,
            job_id: args._discovery_job_id,
            resulting_status: "resolved",
          }],
          error: null,
        };
      }
      if (name === "stage_card_catalog_lifecycle_review") {
        if (args._suggested_action === "observe_current") {
          return {
            data: "44444444-4444-4444-8444-444444444444",
            error: null,
          };
        }
        const card = state.catalogRows.find((row) => row.id === args._card_id);
        const review = {
          id: "33333333-3333-4333-8333-333333333333",
          status: "pending",
          proposed_fields: {
            card_id: args._card_id,
            issuer: card?.bank,
            suggested_action: args._suggested_action,
            source_observation: args._source_observation,
            catalog_baseline: { card_id: args._card_id },
          },
          source_evidence: {
            source_observation: args._source_observation,
            source_url: args._source_url,
          },
        };
        state.reviews.push(review);
        return { data: review.id, error: null };
      }
      return { data: null, error: { message: `unexpected RPC ${name}` } };
    },
  };
  return db;
}

test("returns a URL-hash catalog card only when the fetched candidate identity agrees", async () => {
  const db = createDb({
    urlCardId: "card-url",
    catalogRows: [
      {
        id: "card-url",
        bank: "Axis Bank",
        card_name: "Neo",
        network: "Visa",
      },
    ],
  });

  const result = await persistCrawlerCandidate(db, "Axis Bank", candidate());

  assert.deepEqual(result, { outcome: "existing", catalogCardId: "card-url" });
  assert.equal(db.state.jobs.length, 1);
  assert.equal(db.state.reviews.length, 0);
  assert.equal(db.state.jobs[0].status, "resolved");
  assert.equal(db.state.rpcCalls.length, 1);
  assert.equal(
    db.state.rpcCalls[0].name,
    "publish_card_catalog_identity",
    "existing identity bypassed central publication",
  );
  assert.equal(db.state.rpcCalls[0].args._action, "observe_existing");
});

test("does not let a body match override a mismatched URL hash binding", async () => {
  const db = createDb({
    urlCardId: "card-wrong",
    catalogRows: [
      {
        id: "card-wrong",
        bank: "Axis Bank",
        card_name: "Regalia Gold",
        network: "Visa",
      },
      {
        id: "card-neo",
        bank: "Axis Bank",
        card_name: "Neo",
        network: "Visa",
      },
    ],
  });

  const result = await persistCrawlerCandidate(db, "Axis Bank", candidate());

  assert.deepEqual(result, { outcome: "review", reviewId: "review-1" });
});

test("does not bind a crawler candidate across a stored payment network", async () => {
  const db = createDb({
    urlCardId: "card-visa",
    catalogRows: [
      {
        id: "card-visa",
        bank: "Axis Bank",
        card_name: "Neo",
        network: "Visa",
      },
    ],
  });

  const result = await persistCrawlerCandidate(
    db,
    "Axis Bank",
    candidate({
      network: "Mastercard",
    }),
  );

  assert.equal(result.outcome, "review");
  assert.equal(result.catalogCardId, undefined);
});

test("does not bind a crawler candidate when observed network is absent but stored network is authoritative", async () => {
  const db = createDb({
    catalogRows: [{
      id: "card-visa",
      bank: "Axis Bank",
      card_name: "Neo",
      network: "Visa",
    }],
  });

  const result = await persistCrawlerCandidate(
    db,
    "Axis Bank",
    candidate({ network: undefined }),
  );

  assert.deepEqual(result, { outcome: "review", reviewId: "review-1" });
  assert.equal(
    db.state.rpcCalls.filter((call) =>
      call.name === "publish_card_catalog_identity"
    ).length,
    0,
    "weak observation reached publication",
  );
});

test("does not treat a null network column as wildcard when the stored card name encodes a network", async () => {
  const db = createDb({
    catalogRows: [{
      id: "card-mastercard",
      bank: "Axis Bank",
      card_name: "Neo Mastercard World",
      network: null,
    }],
  });

  const result = await persistCrawlerCandidate(
    db,
    "Axis Bank",
    candidate({ proposedName: "Neo Visa World Credit Card", network: "Visa" }),
  );

  assert.deepEqual(result, { outcome: "review", reviewId: "review-1" });
  assert.equal(
    db.state.rpcCalls.filter((call) =>
      call.name === "publish_card_catalog_identity"
    ).length,
    0,
    "name-derived Mastercard was ignored",
  );
  assert.ok(
    db.state.reviews[0].validation_warnings.includes(
      "conflicting_network_identity",
    ),
  );
});

test("generic crawler identity retains the stored tier sibling as a conflict candidate", async () => {
  const db = createDb({
    catalogRows: [{
      id: "privilege-infinite",
      bank: "Axis Bank",
      card_name: "Privilege Infinite",
      network: "Visa",
    }],
  });
  const result = await persistCrawlerCandidate(
    db,
    "Axis Bank",
    candidate({
      proposedName: "Privilege Credit Card",
      aliases: ["Axis Privilege Credit Card"],
      network: undefined,
    }),
  );

  assert.deepEqual(result, { outcome: "review", reviewId: "review-1" });
  assert.deepEqual(
    db.state.reviews[0].existing_candidates.map((row) => row.id),
    [
      "privilege-infinite",
    ],
  );
  assert.ok(
    db.state.reviews[0].validation_warnings.includes(
      "conflicting_strong_identity",
    ),
  );
});

test("fails closed when one opaque resource hash has conflicting DB bindings", async () => {
  const hash = "d".repeat(64);
  const db = createDb({
    urlCardId: "card-gold",
    provenanceCardId: "card-platinum",
  });
  await assert.rejects(
    persistCrawlerCandidate(
      db,
      "Axis Bank",
      candidate({
        submittedResourceIdentityHash: hash,
        finalResourceIdentityHash: hash,
      }),
    ),
    /identity_conflict/,
  );
  assert.equal(db.state.jobs.length, 0);
  assert.equal(db.state.reviews.length, 0);
});

test("observes one canonical issuer/name catalog candidate through publication", async () => {
  const db = createDb({
    catalogRows: [
      {
        id: "card-neo",
        bank: "Axis Bank",
        card_name: "Neo",
        network: "Visa",
      },
    ],
  });

  const result = await persistCrawlerCandidate(db, "Axis Bank", candidate());

  assert.deepEqual(result, { outcome: "existing", catalogCardId: "card-neo" });
  assert.equal(db.state.jobs.length, 1);
  assert.equal(db.state.reviews.length, 0);
  assert.equal(db.state.rpcCalls.length, 1);
  assert.equal(db.state.rpcCalls[0].args._action, "observe_existing");
  assert.equal(db.state.rpcCalls[0].args._reviewed_fields.card_id, "card-neo");
});

test("replays an existing-card observation through publication without creating review work", async () => {
  const db = createDb({
    catalogRows: [
      {
        id: "card-neo",
        bank: "Axis Bank",
        card_name: "Neo",
        network: "Visa",
      },
    ],
  });

  const first = await persistCrawlerCandidate(db, "Axis Bank", candidate());
  const repeated = await persistCrawlerCandidate(db, "Axis Bank", candidate());

  assert.deepEqual(first, { outcome: "existing", catalogCardId: "card-neo" });
  assert.deepEqual(repeated, {
    outcome: "existing",
    catalogCardId: "card-neo",
  });
  assert.equal(db.state.jobs.length, 1);
  assert.equal(db.state.reviews.length, 0);
  assert.equal(db.state.rpcCalls.length, 2);
  assert.ok(
    db.state.rpcCalls.every((call) =>
      call.name === "publish_card_catalog_identity" &&
      call.args._action === "observe_existing"
    ),
  );
});

test("accepts a strong historical alias without requiring equality to the current name", async () => {
  const db = createDb({
    catalogRows: [
      {
        id: "card-alt",
        bank: "Axis Bank",
        card_name: "Alt",
        network: null,
      },
    ],
    aliasRows: [
      {
        card_id: "card-alt",
        alias: "Axis Neo Credit Card",
        normalized_alias: "neo",
      },
    ],
  });

  const result = await persistCrawlerCandidate(db, "Axis Bank", candidate());

  assert.deepEqual(result, { outcome: "existing", catalogCardId: "card-alt" });
  assert.equal(db.state.jobs.length, 1);
  assert.equal(db.state.reviews.length, 0);
  assert.equal(db.state.rpcCalls.length, 1);
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
  const proposed = db.state.reviews[0].proposed_fields;
  assert.equal(proposed.issuer, "Axis Bank");
  assert.equal(proposed.cardName, "Neo");
  assert.equal(proposed.network, "Visa");
  assert.deepEqual(proposed.aliases, [
    "Neo Credit Card",
    "Axis Neo Credit Card",
  ]);
  assert.equal(
    proposed.submitted_url,
    "https://www.axis.bank.in/cards/credit-card/neo-credit-card",
  );
  assert.equal(proposed.final_url, proposed.submitted_url);
  assert.match(proposed.submitted_url_hash, /^[0-9a-f]{64}$/);
  assert.equal(proposed.final_url_hash, proposed.submitted_url_hash);
});

test("a semantic crawler product change creates a new immutable review version after a terminal decision", async () => {
  const db = createDb();
  const first = await persistCrawlerCandidate(
    db,
    "Axis Bank",
    candidate({
      contentHash: "a".repeat(64),
      retrievedAt: "2026-08-20T00:00:00.000Z",
    }),
  );
  db.state.reviews[0].status = "approved";
  db.state.jobs[0].status = "resolved";
  const second = await persistCrawlerCandidate(
    db,
    "Axis Bank",
    candidate({
      proposedName: "Neo Gold Credit Card",
      aliases: ["Axis Neo Gold Credit Card"],
      contentHash: "b".repeat(64),
      retrievedAt: "2026-08-20T01:00:00.000Z",
    }),
  );

  assert.deepEqual(first, { outcome: "review", reviewId: "review-1" });
  assert.deepEqual(second, { outcome: "review", reviewId: "review-2" });
  assert.equal(db.state.jobs.length, 2, "new content reused a terminal job");
  assert.equal(
    db.state.reviews.length,
    2,
    "new content overwrote a terminal review",
  );
  assert.equal(db.state.reviews[0].status, "approved");
});

test("same-content pending crawler refresh deduplicates history under the review CAS", async () => {
  const db = createDb();
  const observed = candidate({
    contentHash: "e".repeat(64),
    retrievedAt: "2026-08-20T00:00:00.000Z",
  });
  await persistCrawlerCandidate(db, "Axis Bank", observed);
  await persistCrawlerCandidate(db, "Axis Bank", {
    ...observed,
    retrievedAt: "2026-08-20T01:00:00.000Z",
  });

  assert.equal(db.state.jobs.length, 1);
  assert.equal(db.state.reviews.length, 1);
  assert.equal(db.state.reviews[0].status, "pending");
  assert.equal(
    db.state.reviews[0].source_evidence.observation_history.length,
    1,
    "retrieval timestamp duplicated one semantic observation",
  );
  assert.equal(
    db.state.reviews[0].source_evidence.observation_history[0].observed_at,
    "2026-08-20T01:00:00.000Z",
    "newest replay timestamp was not retained",
  );
  assert.equal(
    db.state.rpcCalls.filter((call) =>
      call.name === "stage_card_catalog_identity_review"
    ).length,
    2,
    "pending evidence was returned without transactional CAS refresh",
  );
});

test("crawler proposal keeps exact queryful submitted/final URLs paired with their hashes", async () => {
  const submitted =
    "https://www.axis.bank.in/cards/credit-card/neo-credit-card?variant=gold&lang=en";
  const final =
    "https://www.axis.bank.in/cards/credit-card/neo-credit-card?variant=gold&lang=en&version=2";
  const submittedHash = hashUrl(submitted);
  const finalHash = hashUrl(final);
  const db = createDb();

  await persistCrawlerCandidate(
    db,
    "Axis Bank",
    candidate({
      submittedUrl: submitted,
      finalUrl: final,
      submittedResourceIdentityHash: submittedHash,
      finalResourceIdentityHash: finalHash,
      contentHash: "c".repeat(64),
      retrievedAt: "2026-08-20T00:00:00.000Z",
      sourceStatus: 200,
    }),
  );

  const proposal = db.state.reviews[0].proposed_fields;
  assert.equal(proposal.submitted_url, submitted);
  assert.equal(proposal.final_url, final);
  assert.equal(proposal.submitted_url_hash, submittedHash);
  assert.equal(proposal.final_url_hash, finalHash);
  assert.notEqual(
    proposal.official_url,
    proposal.final_url,
    "display URL replaced exact final resource identity",
  );
});

test("query-selected crawler variants keep distinct opaque review identities", async () => {
  const db = createDb();
  const display = "https://www.axis.bank.in/cards/credit-card/regalia";
  const goldUrl = `${display}?variant=gold`;
  const platinumUrl = `${display}?variant=platinum`;
  const goldHash = hashUrl(goldUrl);
  const platinumHash = hashUrl(platinumUrl);

  const gold = await persistCrawlerCandidate(
    db,
    "Axis Bank",
    candidate({
      canonicalUrl: display,
      submittedUrl: goldUrl,
      finalUrl: goldUrl,
      proposedName: "Regalia Gold Credit Card",
      aliases: ["Regalia Gold"],
      submittedResourceIdentityHash: goldHash,
      finalResourceIdentityHash: goldHash,
    }),
  );
  const platinum = await persistCrawlerCandidate(
    db,
    "Axis Bank",
    candidate({
      canonicalUrl: display,
      submittedUrl: platinumUrl,
      finalUrl: platinumUrl,
      proposedName: "Regalia Platinum Credit Card",
      aliases: ["Regalia Platinum"],
      submittedResourceIdentityHash: platinumHash,
      finalResourceIdentityHash: platinumHash,
    }),
  );

  assert.deepEqual(gold, { outcome: "review", reviewId: "review-1" });
  assert.deepEqual(platinum, { outcome: "review", reviewId: "review-2" });
  assert.equal(db.state.jobs.length, 2, "query variants suppressed each other");
  assert.deepEqual(
    db.state.jobs.map((job) => job.evidence.url_hash),
    [goldHash, platinumHash],
    "opaque final identities were replaced by display hashes",
  );
});

test("different submitted selectors stay distinct when they share one final redirect", async () => {
  const db = createDb();
  const display = "https://www.axis.bank.in/cards/credit-card/neo-credit-card";
  const final = `${display}?lang=en`;
  const finalHash = hashUrl(final);
  const gold = `${display}?variant=gold`;
  const platinum = `${display}?variant=platinum`;

  const first = await persistCrawlerCandidate(
    db,
    "Axis Bank",
    candidate({
      submittedUrl: gold,
      finalUrl: final,
      submittedResourceIdentityHash: hashUrl(gold),
      finalResourceIdentityHash: finalHash,
    }),
  );
  const second = await persistCrawlerCandidate(
    db,
    "Axis Bank",
    candidate({
      submittedUrl: platinum,
      finalUrl: final,
      submittedResourceIdentityHash: hashUrl(platinum),
      finalResourceIdentityHash: finalHash,
    }),
  );

  assert.deepEqual(first, { outcome: "review", reviewId: "review-1" });
  assert.deepEqual(second, { outcome: "review", reviewId: "review-2" });
  assert.equal(db.state.jobs.length, 2, "final redirect collapsed selectors");
  assert.notEqual(
    db.state.jobs[0].dedupe_key,
    db.state.jobs[1].dedupe_key,
    "submitted resource identity was absent from dedupe",
  );
});

test("discontinued exact identity is staged as reviewed reactivation", async () => {
  const cardId = "11111111-1111-4111-8111-111111111111";
  const db = createDb({
    catalogRows: [{
      id: cardId,
      bank: "Axis Bank",
      card_name: "Neo",
      network: "Visa",
      is_discontinued: true,
      updated_at: "2026-08-19T00:00:00.000Z",
    }],
  });

  const reappearanceUrl =
    "https://www.axis.bank.in/cards/credit-card/neo-credit-card?variant=standard";

  const result = await persistCrawlerCandidate(
    db,
    "Axis Bank",
    candidate({
      submittedUrl: reappearanceUrl,
      finalUrl: reappearanceUrl,
      submittedResourceIdentityHash: hashUrl(reappearanceUrl),
      finalResourceIdentityHash: hashUrl(reappearanceUrl),
      contentHash: "b".repeat(64),
      retrievedAt: "2026-08-20T00:00:00.000Z",
      sourceStatus: 200,
    }),
  );

  assert.deepEqual(result, {
    outcome: "review",
    reviewId: "33333333-3333-4333-8333-333333333333",
  });
  assert.equal(db.state.rpcCalls.length, 1);
  assert.equal(
    db.state.rpcCalls[0].name,
    "stage_card_catalog_lifecycle_review",
  );
  assert.equal(db.state.rpcCalls[0].args._suggested_action, "reactivate");
  assert.equal(db.state.rpcCalls[0].args._card_id, cardId);
  assert.equal(db.state.reviews[0].proposed_fields.card_id, cardId);
  assert.equal(
    db.state.reviews[0].proposed_fields.suggested_action,
    "reactivate",
  );
});

test("active exact identity with explicit discontinuation stages mark-discontinued review", async () => {
  const cardId = "11111111-1111-4111-8111-111111111111";
  const db = createDb({
    catalogRows: [{
      id: cardId,
      bank: "Axis Bank",
      card_name: "Neo",
      network: "Visa",
      is_discontinued: false,
      updated_at: "2026-08-19T00:00:00.000Z",
    }],
  });

  const result = await persistCrawlerCandidate(
    db,
    "Axis Bank",
    candidate({
      explicitDiscontinuation: true,
      contentHash: "f".repeat(64),
      retrievedAt: "2026-08-20T00:00:00.000Z",
      sourceStatus: 200,
    }),
  );

  assert.deepEqual(result, {
    outcome: "review",
    reviewId: "33333333-3333-4333-8333-333333333333",
  });
  assert.equal(db.state.rpcCalls.length, 1);
  assert.equal(
    db.state.rpcCalls[0].args._suggested_action,
    "mark_discontinued",
  );
  assert.equal(db.state.rpcCalls[0].args._card_id, cardId);
});

test("current explicit discontinuation blocks crawler reactivation despite a matching 200 page", async () => {
  const cardId = "11111111-1111-4111-8111-111111111111";
  const db = createDb({
    catalogRows: [{
      id: cardId,
      bank: "Axis Bank",
      card_name: "Neo",
      network: "Visa",
      is_discontinued: true,
      updated_at: "2026-08-19T00:00:00.000Z",
    }],
  });

  const result = await persistCrawlerCandidate(
    db,
    "Axis Bank",
    candidate({
      explicitDiscontinuation: true,
      contentHash: "d".repeat(64),
      retrievedAt: "2026-08-20T00:00:00.000Z",
      sourceStatus: 200,
    }),
  );

  assert.notEqual(
    db.state.rpcCalls[0]?.args?._suggested_action,
    "reactivate",
    "explicit current discontinuation was proposed as reappearance",
  );
  assert.notEqual(
    result.outcome,
    "existing",
    "discontinued card was published active",
  );
  assert.equal(
    db.state.rpcCalls[0]?.args?._suggested_action,
    "observe_current",
    "explicit current-state evidence did not supersede stale reactivation work",
  );
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

for (
  const [reviewStatus, jobStatus] of [
    ["approved", "resolved"],
    ["merged", "resolved"],
    ["rejected", "rejected"],
  ]
) {
  test(`does not reopen a ${reviewStatus} crawler review on a repeated candidate`, async () => {
    const db = createDb();
    await persistCrawlerCandidate(db, "Axis Bank", candidate());
    db.state.reviews[0].status = reviewStatus;
    db.state.reviews[0].proposed_fields = { locked: reviewStatus };
    db.state.jobs[0].status = jobStatus;
    const callCount = db.state.calls.length;

    const result = await persistCrawlerCandidate(db, "Axis Bank", candidate());

    assert.deepEqual(result, { outcome: "duplicate", reviewId: "review-1" });
    assert.equal(db.state.reviews[0].status, reviewStatus);
    assert.deepEqual(db.state.reviews[0].proposed_fields, {
      locked: reviewStatus,
    });
    assert.equal(db.state.jobs[0].status, jobStatus);
    assert.equal(db.state.calls.length, callCount);
  });
}

test("does not reopen a terminal crawler review when its job status is stale", async () => {
  const db = createDb();
  await persistCrawlerCandidate(db, "Axis Bank", candidate());
  db.state.reviews[0].status = "approved";
  db.state.reviews[0].proposed_fields = { locked: "approved" };
  const callCount = db.state.calls.length;

  const result = await persistCrawlerCandidate(db, "Axis Bank", candidate());

  assert.deepEqual(result, { outcome: "duplicate", reviewId: "review-1" });
  assert.equal(db.state.reviews[0].status, "approved");
  assert.deepEqual(db.state.reviews[0].proposed_fields, { locked: "approved" });
  assert.equal(db.state.jobs[0].status, "review_required");
  assert.equal(db.state.calls.length, callCount);
});

test("complete issuer directory absence is bounded review evidence and incomplete crawls do nothing", async () => {
  const cardId = "11111111-1111-4111-8111-111111111111";
  const knownCards = [{
    id: cardId,
    bank: "Axis Bank",
    card_name: "Legacy Privilege",
    network: "Visa",
    card_type: "credit",
    is_discontinued: true,
  }];
  const db = createDb({ catalogRows: knownCards });
  const incomplete = await stageCompleteIssuerDirectoryAbsenceReviews(
    db,
    "Axis Bank",
    {
      candidates: [candidate()],
      quarantined: [],
      consideredCount: 40,
      fetchedCount: 39,
      complete: false,
      incompleteReasons: ["candidate_fetch_failed"],
    },
    knownCards,
  );
  assert.deepEqual(incomplete, []);
  assert.equal(db.state.rpcCalls.length, 0, "partial crawl staged absence");
  const inconsistent = await stageCompleteIssuerDirectoryAbsenceReviews(
    db,
    "Axis Bank",
    {
      candidates: [candidate()],
      quarantined: [],
      consideredCount: 1,
      fetchedCount: 1,
      complete: true,
      incompleteReasons: ["candidate_not_positive"],
    },
    knownCards,
  );
  assert.deepEqual(inconsistent, []);
  assert.equal(
    db.state.rpcCalls.length,
    0,
    "incomplete reasons staged absence",
  );
  const staged = await stageCompleteIssuerDirectoryAbsenceReviews(
    db,
    "Axis Bank",
    {
      candidates: [candidate()],
      quarantined: [],
      consideredCount: 1,
      fetchedCount: 1,
      complete: true,
      incompleteReasons: [],
    },
    knownCards,
  );
  assert.deepEqual(staged, ["review-1"]);
  const call = db.state.rpcCalls[0];
  assert.equal(call.name, "stage_card_catalog_identity_review");
  assert.equal(
    call.args._source_evidence.source_observation.kind,
    "complete_issuer_directory_absence",
  );
  assert.equal(
    call.args._validation_warnings[0],
    "complete_directory_absence_requires_review",
  );
});

test("directory absence distinguishes family siblings by tier and effective network", async () => {
  const visaId = "11111111-1111-4111-8111-111111111111";
  const mastercardId = "22222222-2222-4222-8222-222222222222";
  const knownCards = [
    {
      id: visaId,
      bank: "Axis Bank",
      card_name: "Privilege Visa Infinite Credit Card",
      network: null,
      card_type: "credit",
    },
    {
      id: mastercardId,
      bank: "Axis Bank",
      card_name: "Privilege Mastercard World Credit Card",
      network: "Mastercard",
      card_type: "credit",
    },
  ];
  const db = createDb({ catalogRows: knownCards });
  const staged = await stageCompleteIssuerDirectoryAbsenceReviews(
    db,
    "Axis Bank",
    {
      candidates: [candidate({
        proposedName: "Privilege Visa Infinite Credit Card",
        aliases: ["Axis Privilege Visa Infinite Credit Card"],
        network: "Visa",
      })],
      quarantined: [],
      consideredCount: 1,
      fetchedCount: 1,
      complete: true,
      incompleteReasons: [],
    },
    knownCards,
  );

  assert.deepEqual(staged, ["review-1"]);
  assert.equal(
    db.state.rpcCalls[0].args._proposed_fields.card_id,
    mastercardId,
    "present Visa Infinite masked the absent Mastercard World sibling",
  );
  assert.equal(
    db.state.rpcCalls[0].args._existing_candidates[0].network,
    "Mastercard",
  );
});
