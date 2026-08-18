import {
  currentBenefitProposal,
  initializePilotJobs,
  loadCatalogIdentity,
  readPilotStatus,
  requireExactCatalogIdentity,
  seedScheduledQueueIfAllowed,
} from "./index.ts";
import {
  diffBenefits,
  extractGroundedBenefits,
} from "../_shared/benefit_enrichment.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

Deno.test("pilot API refuses catalog-v1 before selecting or writing jobs", async () => {
  let rpcCalls = 0;
  const db = {
    async rpc() {
      rpcCalls += 1;
      return { data: [], error: null };
    },
  };
  let error: unknown;
  try {
    await initializePilotJobs(db, [], "catalog-v1");
  } catch (caught) {
    error = caught;
  }
  assert(
    error instanceof Error && error.message === "reserved_parser_version",
    "reserved parser was not rejected at the pilot API boundary",
  );
  assert(rpcCalls === 0, "rejected parser reached the pilot RPC");
});

Deno.test("pilot API defaults to the current movie-capable parser lane", async () => {
  let parserVersion: unknown;
  const db = {
    async rpc(_name: string, args: Record<string, unknown>) {
      parserVersion = args._parser_version;
      return {
        data: Array.from({ length: 5 }, (_, index) => ({ id: `job-${index}` })),
        error: null,
      };
    },
  };
  const candidates = [
    "straightforward",
    "redirect_or_js",
    "terms_linked",
    "known_invalid",
    "additional_valid",
  ].map((profile, index) => ({
    id: `card-${index}`,
    issuer: `Issuer ${index}`,
    active: true,
    approvedUrl: true,
    profile: profile as
      | "straightforward"
      | "redirect_or_js"
      | "terms_linked"
      | "known_invalid"
      | "additional_valid",
  }));

  await initializePilotJobs(db, candidates);

  assert(parserVersion === "benefits-v5", "pilot defaulted to a stale parser");
});

Deno.test("pilot API rejects a different benefit parser generation", async () => {
  let rpcCalls = 0;
  const db = {
    async rpc() {
      rpcCalls += 1;
      return { data: [], error: null };
    },
  };
  let error: unknown;
  try {
    await initializePilotJobs(db, [], "benefits-v4");
  } catch (caught) {
    error = caught;
  }
  assert(
    error instanceof Error &&
      error.message === "unsupported_pilot_parser_version",
    "a stale benefit parser reached pilot initialization",
  );
  assert(rpcCalls === 0, "stale parser reached the pilot RPC");
});

Deno.test("approved movie config and partners survive the next enrichment comparison", () => {
  const proposal = currentBenefitProposal({
    benefit: {
      dedupe_key: "benefit-movie-1",
      title: "50% off movie tickets",
      description: "Official issuer terms",
      benefit_category: "entertainment",
      benefit_type: "percent_discount",
      value_config: {
        category: "movie_tickets",
        discount_type: "percent",
        discount_percent: 50,
        max_discount_per_transaction: 600,
      },
      partners: ["BookMyShow"],
      exclusions: [],
      source_url: "https://issuer.example/card",
    },
  });

  assert(
    proposal?.valueConfig?.max_discount_per_transaction === 600,
    "approved value_config was dropped before diffing",
  );
  assert(
    proposal?.partners?.join(",") === "BookMyShow",
    "approved partners were dropped before diffing",
  );
});

for (
  const fixture of [
    {
      label: "percent",
      text:
        "Get 50% off movie tickets on BookMyShow, capped at Rs. 600 per transaction.",
    },
    {
      label: "BOGO",
      text:
        "Buy 1 movie ticket and get 1 free on BookMyShow, capped at Rs. 500 per booking, twice per quarter.",
    },
  ]
) {
  Deno.test(`an identical approved ${fixture.label} proposal is unchanged`, () => {
    const [proposed] = extractGroundedBenefits([{
      sourceUrl: "https://issuer.example/card",
      text: fixture.text,
      contentHash: "fixture-content",
    }], "benefits-v5");
    assert(proposed != null, "fixture did not produce a proposal");
    const current = currentBenefitProposal({
      benefit: {
        dedupe_key: proposed.dedupeKey,
        title: proposed.title,
        description: proposed.description,
        benefit_category: proposed.category,
        benefit_type: proposed.valueType,
        value_config: proposed.valueConfig,
        partners: proposed.partners,
        exclusions: proposed.exclusions,
        source_url: proposed.sourceUrl,
      },
    });
    assert(current != null, "approved proposal was not reconstructed");

    const diff = diffBenefits([current], [proposed]);
    assert(diff.conflicts.length === 0, "identical terms produced a conflict");
    assert(diff.unchanged.length === 1, "identical terms were not unchanged");
    assert(diff.additions.length === 0, "identical terms became an addition");
    assert(
      diff.modifications.length === 0,
      "identical terms became a modification",
    );
  });
}

Deno.test("pilot gate evaluates only the current parser lane", async () => {
  const filters = new Map<string, unknown>();
  const rows = [
    "benefits-v1",
    "benefits-v2",
    "benefits-v3",
    "benefits-v4",
    "benefits-v5",
  ]
    .flatMap((parserVersion) =>
      Array.from({ length: 5 }, (_, index) => ({
        id: `${parserVersion}-${index}`,
        run_mode: "pilot",
        parser_version: parserVersion,
        status: "staged",
        failure_category: null,
        result_summary: {
          unsafe_mutation_count: 0,
          idempotency_passed: true,
          evidence_passed: true,
          raw_body_stored: false,
        },
      }))
    );
  const query = {
    select() {
      return this;
    },
    eq(column: string, value: unknown) {
      filters.set(column, value);
      return this;
    },
    then<TResult1 = unknown>(
      onfulfilled?:
        | ((value: unknown) => TResult1 | PromiseLike<TResult1>)
        | null,
    ) {
      const data = rows.filter((row) =>
        [...filters].every(([column, value]) =>
          row[column as keyof typeof row] === value
        )
      );
      return Promise.resolve({ data, error: null }).then(onfulfilled);
    },
  };
  const db = { from: () => query };

  const gate = await readPilotStatus(db);

  assert(
    filters.get("parser_version") === "benefits-v5",
    "pilot gate mixed parser generations",
  );
  assert(
    gate.status === "passed",
    "safe current-generation pilot did not pass",
  );
});

Deno.test("catalog identity requires an exact target match instead of a product-name substring", () => {
  const catalog = [
    { id: "regalia", card_name: "Regalia" },
    { id: "regalia-gold", card_name: "Regalia Gold" },
  ];
  let wrongVariant: unknown;
  try {
    requireExactCatalogIdentity(
      "regalia-gold",
      "HDFC Bank",
      "Regalia",
      catalog,
      [],
    );
  } catch (error) {
    wrongVariant = error;
  }
  assert(
    wrongVariant instanceof Error &&
      wrongVariant.message === "identity_mismatch",
    "Regalia evidence was accepted for Regalia Gold",
  );
  requireExactCatalogIdentity(
    "regalia-gold",
    "HDFC Bank",
    "Regalia Gold",
    catalog,
    [],
  );
});

Deno.test("catalog identity rejects an alias shared by active issuer variants", () => {
  let error: unknown;
  try {
    requireExactCatalogIdentity(
      "regalia",
      "HDFC Bank",
      "Regalia Premium",
      [
        { id: "regalia", card_name: "Regalia" },
        { id: "regalia-gold", card_name: "Regalia Gold" },
      ],
      [
        { card_id: "regalia", alias: "Regalia Premium" },
        { card_id: "regalia-gold", alias: "Regalia Premium" },
      ],
    );
  } catch (caught) {
    error = caught;
  }
  assert(
    error instanceof Error && error.message === "ambiguous_product",
    "shared alias did not block ambiguous identity",
  );
});

Deno.test("catalog identity keeps payment-network words when sibling variants would otherwise collide", () => {
  const catalog = [
    { id: "hpcl-coral", card_name: "Hpcl Coral" },
    {
      id: "hpcl-coral-amex",
      card_name: "Hpcl Coral American Express",
    },
  ];

  requireExactCatalogIdentity(
    "hpcl-coral",
    "ICICI Bank",
    "HPCL Coral Credit Card",
    catalog,
    [],
  );
});

Deno.test("catalog identity loading includes active same-issuer variants and aliases", async () => {
  const catalog = [
    {
      id: "regalia",
      card_name: "Regalia",
      bank: "HDFC Bank",
      is_discontinued: false,
    },
    {
      id: "regalia-gold",
      card_name: "Regalia Gold",
      bank: "HDFC Bank",
      is_discontinued: false,
    },
    {
      id: "axis",
      card_name: "Select",
      bank: "Axis Bank",
      is_discontinued: false,
    },
  ];
  const aliases = [
    { card_id: "regalia", alias: "HDFC Regalia" },
    { card_id: "regalia-gold", alias: "HDFC Regalia Gold" },
  ];
  const db = {
    from(table: string) {
      const filters = new Map<string, unknown>();
      let includedIds: string[] = [];
      const builder = {
        select() {
          return this;
        },
        eq(column: string, value: unknown) {
          filters.set(column, value);
          return this;
        },
        ilike(column: string, value: unknown) {
          filters.set(column, value);
          return this;
        },
        in(_column: string, values: string[]) {
          includedIds = values;
          return this;
        },
        async single() {
          return {
            data: catalog.find((row) => row.id === filters.get("id")),
            error: null,
          };
        },
        then<TResult1 = unknown, TResult2 = never>(
          onfulfilled?:
            | ((value: unknown) => TResult1 | PromiseLike<TResult1>)
            | null,
          onrejected?:
            | ((reason: unknown) => TResult2 | PromiseLike<TResult2>)
            | null,
        ) {
          const data = table === "card_catalog"
            ? catalog.filter((row) =>
              row.bank.toLowerCase() ===
                String(filters.get("bank")).toLowerCase() &&
              row.is_discontinued === filters.get("is_discontinued")
            )
            : aliases.filter((row) => includedIds.includes(row.card_id));
          return Promise.resolve({ data, error: null }).then(
            onfulfilled,
            onrejected,
          );
        },
      };
      return builder;
    },
  };

  const identity = await loadCatalogIdentity(db, "regalia-gold");

  assert(identity.catalog.length === 2, "same-issuer variant was not loaded");
  assert(identity.aliases.length === 2, "variant aliases were not loaded");
  assert(
    identity.catalog.every((row: Record<string, unknown>) =>
      row.bank === "HDFC Bank"
    ),
    "cross-issuer identity entered matching evidence",
  );
});

type CatalogFixture = {
  id: string;
  bank: string;
  card_url: string | null;
  card_type: string;
  is_discontinued: boolean;
};

function scheduledSeederDb(
  catalog: CatalogFixture[],
  initialJobs: Record<string, unknown>[] = [],
) {
  const jobs = new Map(
    initialJobs.map((job) => [String(job.job_key), { ...job }]),
  );
  let catalogReads = 0;
  const catalogFilters = new Map<string, unknown>();
  return {
    jobs,
    catalogFilters,
    get catalogReads() {
      return catalogReads;
    },
    from(table: string) {
      if (table === "card_catalog") {
        let from = 0;
        let to = catalog.length - 1;
        return {
          select() {
            return this;
          },
          eq(column: string, value: unknown) {
            catalogFilters.set(`eq:${column}`, value);
            return this;
          },
          ilike(column: string, value: string) {
            catalogFilters.set(`ilike:${column}`, value);
            return this;
          },
          like(column: string, value: string) {
            catalogFilters.set(`like:${column}`, value);
            return this;
          },
          order() {
            return this;
          },
          async range(nextFrom: number, nextTo: number) {
            catalogReads += 1;
            from = nextFrom;
            to = nextTo;
            return {
              data: catalog.slice(from, to + 1).map((row) => ({ ...row })),
              error: null,
            };
          },
        };
      }
      assert(
        table === "card_catalog_enrichment_jobs",
        "seeder wrote an unexpected table",
      );
      let selecting = false;
      const filters = new Map<string, unknown>();
      return {
        select() {
          selecting = true;
          return this;
        },
        eq(column: string, value: unknown) {
          filters.set(column, value);
          return this;
        },
        async upsert(
          input: Record<string, unknown> | Record<string, unknown>[],
          options: { onConflict?: string; ignoreDuplicates?: boolean },
        ) {
          assert(options.onConflict === "job_key", "wrong queue identity");
          assert(options.ignoreDuplicates === true, "conflicts can overwrite");
          for (const row of Array.isArray(input) ? input : [input]) {
            const key = String(row.job_key);
            if (!jobs.has(key)) jobs.set(key, { ...row });
          }
          return { error: null };
        },
        then<TResult1 = unknown, TResult2 = never>(
          onfulfilled?:
            | ((value: unknown) => TResult1 | PromiseLike<TResult1>)
            | null,
          onrejected?:
            | ((reason: unknown) => TResult2 | PromiseLike<TResult2>)
            | null,
        ) {
          const data = selecting
            ? [...jobs.values()].filter((row) =>
              [...filters].every(([column, value]) => row[column] === value)
            )
            : [];
          return Promise.resolve({ data, error: null }).then(
            onfulfilled,
            onrejected,
          );
        },
      };
    },
  };
}

const validCatalogCard: CatalogFixture = {
  id: "card-valid",
  bank: "Axis Bank",
  card_url:
    "https://www.axis.bank.in/cards/credit-card/privilege/?utm_source=seed#top",
  card_type: " Credit ",
  is_discontinued: false,
};

Deno.test("passed scheduled orchestration seeds an empty queue across bounded catalog pages", async () => {
  const db = scheduledSeederDb([
    validCatalogCard,
    { ...validCatalogCard, id: "card-two" },
    { ...validCatalogCard, id: "card-three" },
  ]);

  const seeded = await seedScheduledQueueIfAllowed(
    db,
    "scheduled",
    true,
    2,
  );

  assert(seeded === 3, "not all paged catalog cards were seeded");
  assert(db.catalogReads === 2, "catalog inventory was not read in pages");
  assert(
    db.catalogFilters.get("eq:is_discontinued") === false &&
      db.catalogFilters.get("ilike:card_type") === "credit" &&
      db.catalogFilters.get("like:card_url") === "https://%",
    "catalog query did not constrain active HTTPS credit-card inventory",
  );
  assert(db.jobs.size === 3, "empty scheduled lane was not populated");
  const row = db.jobs.get(
    "card-valid:a9681b52e7105d3d3540076b1705c9d446e1171de165973e833940f671eedadf:benefits-v5",
  );
  assert(
    row?.canonical_url ===
      "https://www.axis.bank.in/cards/credit-card/privilege",
    "URL was not canonicalized",
  );
  assert(
    row?.final_url_hash ===
      "a9681b52e7105d3d3540076b1705c9d446e1171de165973e833940f671eedadf",
    "URL hash changed",
  );
  assert(row?.parser_version === "benefits-v5", "wrong parser lane");
  assert(row?.run_mode === "scheduled", "wrong run mode");
  assert(row?.status === "queued", "new inventory was not queued");
  assert(row?.content_hash === null, "unfetched content was fabricated");
  assert(
    JSON.stringify(row?.result_summary) === JSON.stringify({
      queue_source: "catalog_seed",
      unsafe_mutation_count: 0,
      raw_body_stored: false,
      evidence_passed: false,
      idempotency_passed: false,
    }),
    "initial result summary was not safe",
  );
});

Deno.test("scheduled seeding skips discontinued, non-credit, and unsafe catalog URLs", async () => {
  const db = scheduledSeederDb([
    validCatalogCard,
    { ...validCatalogCard, id: "discontinued", is_discontinued: true },
    { ...validCatalogCard, id: "debit", card_type: "debit" },
    {
      ...validCatalogCard,
      id: "http",
      card_url: "http://www.axis.bank.in/card",
    },
    {
      ...validCatalogCard,
      id: "off-domain",
      card_url: "https://evil.example/card",
    },
    { ...validCatalogCard, id: "missing-url", card_url: null },
  ]);

  const seeded = await seedScheduledQueueIfAllowed(db, "scheduled", true);

  assert(seeded === 1, "unsafe or inactive inventory was seeded");
  assert(db.jobs.size === 1, "filtered inventory reached the queue");
});

Deno.test("scheduled seeding skips pilot conflicts and preserves processing and terminal jobs on repeats", async () => {
  const urlHash =
    "a9681b52e7105d3d3540076b1705c9d446e1171de165973e833940f671eedadf";
  const catalog = [
    validCatalogCard,
    { ...validCatalogCard, id: "card-processing" },
    { ...validCatalogCard, id: "card-terminal" },
  ];
  const initial = [
    {
      id: "pilot-job",
      job_key: `card-valid:${urlHash}:benefits-v5`,
      card_id: "card-valid",
      parser_version: "benefits-v5",
      run_mode: "pilot",
      status: "completed",
      result_summary: { pilot: true },
    },
    {
      id: "processing-job",
      job_key: `card-processing:${urlHash}:benefits-v5`,
      card_id: "card-processing",
      parser_version: "benefits-v5",
      run_mode: "scheduled",
      status: "processing",
      lease_token: "lease-1",
    },
    {
      id: "terminal-job",
      job_key: `card-terminal:${urlHash}:benefits-v5`,
      card_id: "card-terminal",
      parser_version: "benefits-v5",
      run_mode: "scheduled",
      status: "review_required",
      failure_category: "manual_review",
    },
  ];
  const db = scheduledSeederDb(catalog, initial);

  await seedScheduledQueueIfAllowed(db, "scheduled", true);
  await seedScheduledQueueIfAllowed(db, "scheduled", true);

  assert(db.jobs.size === 3, "repeat seeding duplicated queue identities");
  for (const original of initial) {
    assert(
      JSON.stringify(db.jobs.get(String(original.job_key))) ===
        JSON.stringify(original),
      `${original.id} was rewound or changed lanes`,
    );
  }
});

Deno.test("scheduled seeding excludes pilot card and parser identity despite cosmetic URL hashes", async () => {
  const pilot = {
    id: "pilot-cosmetic-url",
    card_id: "card-valid",
    parser_version: "benefits-v5",
    job_key: `card-valid:${"f".repeat(64)}:benefits-v5`,
    run_mode: "pilot",
    status: "completed",
  };
  const db = scheduledSeederDb([validCatalogCard], [pilot]);

  const seeded = await seedScheduledQueueIfAllowed(db, "scheduled", true);

  assert(seeded === 0, "pilot card/parser identity was scheduled again");
  assert(db.jobs.size === 1, "cosmetic URL difference duplicated pilot work");
});

Deno.test("scheduled inventory is not read until the pilot gate passes", async () => {
  const db = scheduledSeederDb([validCatalogCard]);

  assert(
    await seedScheduledQueueIfAllowed(db, "scheduled", false) === 0,
    "blocked scheduled call reported seeded jobs",
  );
  assert(
    await seedScheduledQueueIfAllowed(db, "pilot", true) === 0,
    "pilot call seeded the scheduled lane",
  );
  assert(db.catalogReads === 0, "catalog was read before the scheduled gate");
  assert(db.jobs.size === 0, "queue was written before the scheduled gate");
});
