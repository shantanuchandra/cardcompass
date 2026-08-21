import {
  findPriorSubmittedRequestJob,
  versionSubmittedObservationJob,
} from "./index.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

function versionDb() {
  const jobs: Array<Record<string, any>> = [];
  return {
    jobs,
    from(table: string) {
      assert(table === "card_discovery_jobs", `unexpected table ${table}`);
      let action = "select";
      let payload: Record<string, unknown> | null = null;
      const filters: Record<string, unknown> = {};
      const execute = () => {
        if (action === "insert") {
          const duplicate = jobs.find((row) =>
            row.user_id === payload?.user_id &&
            row.dedupe_key === payload?.dedupe_key
          );
          if (duplicate) return { data: null, error: { code: "23505" } };
          const row = { id: `job-${jobs.length + 1}`, ...payload };
          jobs.push(row);
          return { data: row, error: null };
        }
        const row =
          jobs.find((candidate) =>
            Object.entries(filters).every(([key, value]) =>
              candidate[key] === value
            )
          ) ?? null;
        return { data: row, error: null };
      };
      const query = {
        select() {
          return query;
        },
        eq(key: string, value: unknown) {
          filters[key] = value;
          return query;
        },
        insert(value: Record<string, unknown>) {
          action = "insert";
          payload = value;
          return query;
        },
        maybeSingle() {
          return Promise.resolve(execute());
        },
        single() {
          return Promise.resolve(execute());
        },
      };
      return query;
    },
  };
}

function observation(contentHash = "c".repeat(64)) {
  return {
    page: {
      text: "<h1>Axis Privilege Infinite Credit Card</h1>",
      status: 200,
      submittedUrl: "https://www.axis.bank.in/card?variant=infinite",
      finalUrl: "https://www.axis.bank.in/card?variant=infinite",
      canonicalUrl: "https://www.axis.bank.in/card?variant=infinite",
      contentType: "text/html",
      bytes: new Uint8Array(),
      contentHash,
      retrievedAt: "2026-08-20T00:00:00.000Z",
      notModified: false,
    },
    submittedHash: "a".repeat(64),
    finalHash: "b".repeat(64),
    legacySubmittedHash: "a".repeat(64),
    legacyFinalHash: "b".repeat(64),
    publicationEvidence: {
      submitted_url_hash: "a".repeat(64),
      final_url_hash: "b".repeat(64),
      content_hash: contentHash,
      retrieved_at: "2026-08-20T00:00:00.000Z",
      source_status: 200,
    },
  };
}

Deno.test("submitted URL versions are created only after fetch and exact semantic replay creates no anchor orphan", async () => {
  const db = versionDb();
  const context = {
    id: "unpersisted-request-anchor",
    user_id: "user-1",
    discovery_source: "statement",
    issuer: "Axis Bank",
    proposed_product: "Privilege Infinite",
    evidence: { issuer: "Axis Bank" },
  };
  const anchor = "d".repeat(64);
  const semantic = "e".repeat(64);
  const first = await versionSubmittedObservationJob(
    db,
    context,
    observation(),
    anchor,
    semantic,
  );
  const replay = await versionSubmittedObservationJob(
    db,
    context,
    observation("f".repeat(64)),
    anchor,
    semantic,
  );
  assert(first.id === replay.id, "semantic replay created another job");
  assert(db.jobs.length === 1, "per-call queued anchor was orphaned");
  assert(
    db.jobs[0].evidence.content_hash === "c".repeat(64),
    "raw first-observation provenance was overwritten by replay churn",
  );
  const changed = await versionSubmittedObservationJob(
    db,
    context,
    observation("f".repeat(64)),
    anchor,
    "1".repeat(64),
  );
  assert(
    changed.id !== first.id,
    "semantic product change reused terminal work",
  );
  assert(
    Number(db.jobs.length) === 2,
    "changed semantic content was not versioned",
  );
  assert(
    db.jobs.every((job) =>
      job.dedupe_key !== anchor && job.evidence.request_anchor_key === anchor
    ),
    "stable anchor replaced immutable version identity",
  );
});

Deno.test("request anchors prefer retained terminal work over a newer transient failure", async () => {
  const rows = [
    {
      id: "terminal",
      user_id: "user-1",
      status: "resolved",
      updated_at: "2026-08-20T00:00:00.000Z",
      evidence: { request_anchor_key: "anchor-1" },
    },
    {
      id: "transient",
      user_id: "user-1",
      status: "failed",
      updated_at: "2026-08-20T01:00:00.000Z",
      evidence: { request_anchor_key: "anchor-1" },
    },
  ];
  const db = {
    from(table: string) {
      assert(table === "card_discovery_jobs", `unexpected table ${table}`);
      const filters: Array<(row: Record<string, any>) => boolean> = [];
      let descending = false;
      const query: Record<string, any> = {
        select: () => query,
        eq(key: string, value: unknown) {
          filters.push((row) => row[key] === value);
          return query;
        },
        contains(key: string, value: Record<string, unknown>) {
          filters.push((row) =>
            Object.entries(value).every(([nestedKey, nestedValue]) =>
              row[key]?.[nestedKey] === nestedValue
            )
          );
          return query;
        },
        in(key: string, values: unknown[]) {
          filters.push((row) => values.includes(row[key]));
          return query;
        },
        order(_key: string, options: { ascending: boolean }) {
          descending = !options.ascending;
          return query;
        },
        limit: () => query,
        maybeSingle() {
          const matches = rows.filter((row) =>
            filters.every((filter) => filter(row))
          ).sort((left, right) =>
            descending
              ? right.updated_at.localeCompare(left.updated_at)
              : left.updated_at.localeCompare(right.updated_at)
          );
          return Promise.resolve({ data: matches[0] ?? null, error: null });
        },
      };
      return query;
    },
  };
  const prior = await findPriorSubmittedRequestJob(db, "user-1", "anchor-1");
  assert(
    prior?.id === "terminal",
    "transient work hid the retained terminal result",
  );
});
