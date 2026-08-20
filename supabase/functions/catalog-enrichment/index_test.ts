import { processCatalogEnrichmentJob, queueConflictReview } from "./index.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

function terminalJobDb(job: Record<string, unknown>) {
  let updates = 0;
  return {
    get updates() {
      return updates;
    },
    from(table: string) {
      assert(
        table === "card_catalog_enrichment_jobs",
        "unexpected table read",
      );
      return {
        select() {
          return this;
        },
        eq() {
          return this;
        },
        async single() {
          return { data: { ...job }, error: null };
        },
        update() {
          updates += 1;
          return this;
        },
      };
    },
  };
}

function reviewDb() {
  const state: {
    jobs: Array<Record<string, unknown>>;
    reviews: Array<Record<string, unknown>>;
  } = { jobs: [], reviews: [] };
  const db = {
    state,
    from(table: string) {
      let action = "select";
      let payload: Record<string, unknown> | null = null;
      const filters: Record<string, unknown> = {};
      let statuses: unknown[] | null = null;
      const execute = () => {
        const rows = table === "card_discovery_jobs"
          ? state.jobs
          : state.reviews;
        const matches = (row: Record<string, unknown>) =>
          Object.entries(filters).every(([key, value]) => row[key] === value) &&
          (statuses === null || statuses.includes(row.status));
        if (action === "insert") {
          if (
            table === "card_discovery_jobs" &&
            state.jobs.some((row) =>
              row.discovery_source === payload?.discovery_source &&
              row.dedupe_key === payload?.dedupe_key && row.user_id === null
            )
          ) return { data: null, error: { code: "23505" } };
          const row = {
            id: `${table === "card_discovery_jobs" ? "job" : "review"}-${
              rows.length + 1
            }`,
            ...payload,
          };
          rows.push(row);
          return { data: row, error: null };
        }
        const row = rows.find(matches) ?? null;
        if (action === "update" && row && payload) Object.assign(row, payload);
        return { data: row, error: null };
      };
      const query = {
        select() {
          return query;
        },
        insert(value: Record<string, unknown>) {
          action = "insert";
          payload = value;
          return query;
        },
        update(value: Record<string, unknown>) {
          action = "update";
          payload = value;
          return query;
        },
        eq(key: string, value: unknown) {
          filters[key] = value;
          return query;
        },
        is(key: string, value: unknown) {
          filters[key] = value;
          return query;
        },
        in(_key: string, values: unknown[]) {
          statuses = values;
          return query;
        },
        maybeSingle() {
          return Promise.resolve(execute());
        },
        single() {
          return Promise.resolve(execute());
        },
        then(
          resolve: (value: unknown) => unknown,
          reject: (reason: unknown) => unknown,
        ) {
          return Promise.resolve(execute()).then(resolve, reject);
        },
      };
      return query;
    },
  };
  return db;
}

Deno.test("catalog conflict reviews version material content while keeping terminal rows immutable", async () => {
  const db = reviewDb();
  const catalogJob = {
    id: "catalog-job",
    card_id: "11111111-1111-4111-8111-111111111111",
    issuer: "Axis Bank",
    card_name: "Privilege Infinite",
    canonical_url: "https://www.axis.bank.in/card?variant=infinite",
  };
  const proposed = {
    annual_fee: 1500,
    catalog_baseline: { card_name: "Privilege Infinite", updated_at: null },
  };
  const observation = (contentHash: string, retrievedAt: string) => ({
    submitted_url_hash: "a".repeat(64),
    final_url_hash: "b".repeat(64),
    content_hash: contentHash,
    retrieved_at: retrievedAt,
    source_observation: { kind: "catalog_enrichment" },
  });

  const first = await queueConflictReview(
    db,
    catalogJob,
    [{ field: "annual_fee" }],
    proposed,
    observation("c".repeat(64), "2026-08-20T00:00:00.000Z"),
  );
  const refreshed = await queueConflictReview(
    db,
    catalogJob,
    [{ field: "annual_fee" }],
    proposed,
    observation("c".repeat(64), "2026-08-20T00:30:00.000Z"),
  );
  assert(
    first === refreshed,
    "transport-only retrieval time created a second review",
  );
  assert(db.state.jobs.length === 1, "same content created a second job");
  assert(
    ((db.state.reviews[0].source_evidence as Record<string, unknown>)
      .observation_history as unknown[]).length === 1,
    "exact semantic refresh duplicated history",
  );
  assert(
    (((db.state.reviews[0].source_evidence as Record<string, unknown>)
      .observation_history as Array<Record<string, unknown>>)[0]
      .observed_at) === "2026-08-20T00:30:00.000Z",
    "pending refresh did not retain the newest retrieval evidence",
  );
  db.state.reviews[0].status = "approved";
  db.state.jobs[0].status = "resolved";
  const next = await queueConflictReview(
    db,
    catalogJob,
    [{ field: "annual_fee" }],
    proposed,
    observation("d".repeat(64), "2026-08-20T01:00:00.000Z"),
  );
  assert(next !== first, "new content reused a terminal decision");
  assert(
    Number(db.state.jobs.length) === 2 && Number(db.state.reviews.length) === 2,
    "new content was not reviewable",
  );
  assert(
    db.state.reviews[0].status === "approved",
    "terminal review was overwritten",
  );
});

Deno.test("legacy catalog enrichment refuses scheduled and pilot benefit jobs", async () => {
  for (const runMode of ["scheduled", "pilot"]) {
    const db = terminalJobDb({
      id: `job-${runMode}`,
      status: "completed",
      run_mode: runMode,
      parser_version: "benefits-v1",
    });
    let error: unknown;
    try {
      await processCatalogEnrichmentJob(db, `job-${runMode}`);
    } catch (caught) {
      error = caught;
    }
    assert(
      error instanceof Error && error.message === "job_not_owned",
      `${runMode} benefit job bypassed legacy ownership`,
    );
    assert(db.updates === 0, "refused benefit job was updated");
  }

  const manualDb = terminalJobDb({
    id: "manual-job",
    status: "completed",
    run_mode: "manual",
    parser_version: "catalog-v1",
  });
  assert(
    await processCatalogEnrichmentJob(manualDb, "manual-job") === "completed",
    "legitimate manual catalog job was refused",
  );
  assert(manualDb.updates === 0, "terminal manual job was rewritten");
});

Deno.test("legacy claim loses ownership safely if a manual job changes lanes", async () => {
  const stored: Record<string, unknown> = {
    id: "manual-race",
    card_id: "card-1",
    issuer: "Axis Bank",
    canonical_url: "https://www.axis.bank.in/card",
    status: "queued",
    attempt_count: 0,
    run_mode: "manual",
    parser_version: "catalog-v1",
  };
  let readCompleted = false;
  const db = {
    from(table: string) {
      assert(
        table === "card_catalog_enrichment_jobs",
        "race test left the queue table",
      );
      let patch: Record<string, unknown> | null = null;
      const equalFilters = new Map<string, unknown>();
      let allowedStatuses: unknown[] | null = null;
      return {
        select() {
          return this;
        },
        update(value: Record<string, unknown>) {
          patch = value;
          return this;
        },
        eq(column: string, value: unknown) {
          equalFilters.set(column, value);
          return this;
        },
        in(column: string, values: unknown[]) {
          if (column === "status") allowedStatuses = values;
          return this;
        },
        async single() {
          const snapshot = { ...stored };
          readCompleted = true;
          stored.run_mode = "scheduled";
          stored.parser_version = "benefits-v1";
          return { data: snapshot, error: null };
        },
        async maybeSingle() {
          assert(readCompleted, "claim happened before ownership read");
          const equalMatch = [...equalFilters].every(([column, value]) =>
            stored[column] === value
          );
          const statusMatch = allowedStatuses === null ||
            allowedStatuses.includes(stored.status);
          if (!equalMatch || !statusMatch || !patch) {
            return { data: null, error: null };
          }
          Object.assign(stored, patch);
          return { data: { ...stored }, error: null };
        },
      };
    },
  };

  const result = await processCatalogEnrichmentJob(db, "manual-race");
  assert(result === "already_processing", "ownership race was not refused");
  assert(
    stored.status === "queued",
    "raced benefit job was claimed or rewritten",
  );
});

Deno.test("legacy finalization cannot overwrite a post-claim lane change", async () => {
  const stored: Record<string, unknown> = {
    id: "post-claim-race",
    card_id: "card-1",
    issuer: "Axis Bank",
    canonical_url: "not-an-official-url",
    status: "queued",
    attempt_count: 0,
    run_mode: "manual",
    parser_version: "catalog-v1",
  };
  let claimReturned = false;
  const db = {
    from(table: string) {
      assert(
        table === "card_catalog_enrichment_jobs",
        "failure path escaped the queue table",
      );
      let patch: Record<string, unknown> | null = null;
      const equalFilters = new Map<string, unknown>();
      let allowedStatuses: unknown[] | null = null;
      const executeUpdate = () => {
        const equalMatch = [...equalFilters].every(([column, value]) =>
          stored[column] === value
        );
        const statusMatch = allowedStatuses === null ||
          allowedStatuses.includes(stored.status);
        if (!equalMatch || !statusMatch || !patch) {
          return { data: null, error: null };
        }
        Object.assign(stored, patch);
        return { data: { ...stored }, error: null };
      };
      return {
        select() {
          return this;
        },
        update(value: Record<string, unknown>) {
          patch = value;
          return this;
        },
        eq(column: string, value: unknown) {
          equalFilters.set(column, value);
          return this;
        },
        in(column: string, values: unknown[]) {
          if (column === "status") allowedStatuses = values;
          return this;
        },
        async single() {
          return { data: { ...stored }, error: null };
        },
        async maybeSingle() {
          const result = executeUpdate();
          if (!claimReturned && result.data) {
            claimReturned = true;
            queueMicrotask(() => {
              stored.run_mode = "scheduled";
              stored.parser_version = "benefits-v1";
            });
          }
          return result;
        },
        then<TResult1 = unknown, TResult2 = never>(
          onfulfilled?:
            | ((value: unknown) => TResult1 | PromiseLike<TResult1>)
            | null,
          onrejected?:
            | ((reason: unknown) => TResult2 | PromiseLike<TResult2>)
            | null,
        ) {
          return Promise.resolve(executeUpdate()).then(onfulfilled, onrejected);
        },
      };
    },
  };

  let error: unknown;
  try {
    await processCatalogEnrichmentJob(db, "post-claim-race");
  } catch (caught) {
    error = caught;
  }
  assert(
    error instanceof Error && error.message === "job_not_owned",
    "lost finalization ownership was not reported",
  );
  assert(stored.status === "processing", "lost job status was overwritten");
  assert(stored.run_mode === "scheduled", "lost job lane was overwritten");
  assert(
    stored.parser_version === "benefits-v1",
    "lost job parser was overwritten",
  );
});
