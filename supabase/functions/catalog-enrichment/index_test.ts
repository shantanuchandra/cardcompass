import { processCatalogEnrichmentJob } from "./index.ts";

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
