type AdminHandler = (
  request: Request,
  db: Record<string, unknown>,
) => Promise<Response>;

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

async function handler(): Promise<AdminHandler> {
  const module = await import("./index.ts") as {
    handleAdminCatalogEntry?: AdminHandler;
  };
  assert(
    typeof module.handleAdminCatalogEntry === "function",
    "benefit actions are not registered on the protected admin handler",
  );
  return module.handleAdminCatalogEntry;
}

function request(body: Record<string, unknown>, token = "valid-token") {
  return new Request("https://example.test/admin-catalog-entry", {
    method: "POST",
    headers: {
      "authorization": `Bearer ${token}`,
      "content-type": "application/json",
    },
    body: JSON.stringify(body),
  });
}

function authenticatedDb(
  user: Record<string, unknown> | null,
  authError: unknown = null,
) {
  return {
    auth: {
      async getUser() {
        return { data: { user }, error: authError };
      },
    },
  };
}

function withAuthenticatedUser(db: Record<string, unknown>) {
  return {
    ...db,
    auth: authenticatedDb({
      id: "admin-1",
      email: "admin@example.com",
      email_confirmed_at: "2026-08-17T00:00:00.000Z",
    }).auth,
  };
}

Deno.test("protected admin handler returns 401 for missing or expired credentials before queue access", async () => {
  const handle = await handler();
  let queueReads = 0;
  const expiredDb = {
    ...authenticatedDb(null, new Error("JWT expired")),
    from() {
      queueReads += 1;
      throw new Error("queue access must not occur for expired auth");
    },
  };

  const missing = await handle(
    new Request("https://example.test/admin-catalog-entry", { method: "POST" }),
    expiredDb,
  );
  const expired = await handle(request({ action: "benefit-list" }), expiredDb);

  assert(missing.status === 401, "missing credentials were not rejected");
  assert(expired.status === 401, "expired credentials were not rejected");
  assert(queueReads === 0, "expired auth reached a benefit queue operation");
});

Deno.test("protected admin handler requires a verified allowlisted email", async () => {
  const handle = await handler();
  const originalAllowlist = Deno.env.get("CARD_CATALOG_ADMIN_EMAILS");
  Deno.env.set("CARD_CATALOG_ADMIN_EMAILS", "admin@example.com");
  try {
    const unverified = await handle(
      request({ action: "benefit-list" }),
      authenticatedDb({
        id: "admin-1",
        email: "admin@example.com",
        email_confirmed_at: null,
      }),
    );
    const nonAllowlisted = await handle(
      request({ action: "benefit-list" }),
      authenticatedDb({
        id: "admin-1",
        email: "other@example.com",
        email_confirmed_at: "2026-08-17T00:00:00.000Z",
      }),
    );
    const allowlisted = await handle(
      request({ action: "access" }),
      authenticatedDb({
        id: "admin-1",
        email: "admin@example.com",
        email_confirmed_at: "2026-08-17T00:00:00.000Z",
      }),
    );

    assert(unverified.status === 403, "unverified email received admin access");
    assert(
      nonAllowlisted.status === 403,
      "non-allowlisted email received admin access",
    );
    assert(
      allowlisted.status === 200,
      "verified allowlisted email was rejected",
    );
  } finally {
    if (originalAllowlist === undefined) {
      Deno.env.delete("CARD_CATALOG_ADMIN_EMAILS");
    } else Deno.env.set("CARD_CATALOG_ADMIN_EMAILS", originalAllowlist);
  }
});

Deno.test("benefit list returns evidence and confidence without page bodies or secrets", async () => {
  const handle = await handler();
  const row = {
    id: "job-1",
    card_id: "card-1",
    issuer: "Axis Bank",
    canonical_url: "https://axis.example/card",
    status: "staged",
    attempt_count: 1,
    run_mode: "pilot",
    parser_version: "benefits-v1",
    staging_id: "staging-1",
    result_summary: { run_id: "run-1", raw_body_stored: false },
    card_benefits_staging: {
      id: "staging-1",
      calculated_confidence: 0.94,
      source_evidence: [{ source_excerpt: "₹500 dining credit" }],
      extracted_data: {
        diff: { additions: [{ title: "Dining credit" }] },
        rawBody: "private issuer html",
        apiKey: "secret-token",
      },
    },
  };
  const db = withAuthenticatedUser({
    from(table: string) {
      if (table === "card_discovery_jobs") {
        return {
          select() {
            return this;
          },
          eq() {
            return this;
          },
          in() {
            return this;
          },
          then(resolve: (value: unknown) => unknown) {
            return Promise.resolve({
              data: [{ resolved_card_id: "card-1" }],
              error: null,
            }).then(resolve);
          },
        };
      }
      assert(
        table === "card_catalog_enrichment_jobs",
        "list read an unexpected table",
      );
      return {
        select() {
          return this;
        },
        neq() {
          return this;
        },
        in() {
          return this;
        },
        eq() {
          return this;
        },
        order() {
          return this;
        },
        async range() {
          return { data: [row], error: null };
        },
        async limit() {
          return { data: [row], error: null };
        },
      };
    },
  });
  const originalAllowlist = Deno.env.get("CARD_CATALOG_ADMIN_EMAILS");
  Deno.env.set("CARD_CATALOG_ADMIN_EMAILS", "admin@example.com");
  try {
    const response = await handle(request({ action: "benefit-list" }), db);
    const body = await response.json();
    const serialized = JSON.stringify(body);
    assert(response.status === 200, "benefit list was rejected");
    assert(
      serialized.includes("₹500 dining credit"),
      "safe evidence was omitted",
    );
    assert(serialized.includes("0.94"), "confidence was omitted");
    assert(
      body.items[0].crawler_discovered_without_statement_signal === true,
      "linked issuer crawl was omitted",
    );
    assert(
      !serialized.includes("private issuer html"),
      "raw page body was exposed",
    );
    assert(!serialized.includes("secret-token"), "secret was exposed");
  } finally {
    if (originalAllowlist === undefined) {
      Deno.env.delete("CARD_CATALOG_ADMIN_EMAILS");
    } else Deno.env.set("CARD_CATALOG_ADMIN_EMAILS", originalAllowlist);
  }
});

Deno.test("benefit approval accepts only matching pending enrichment staging and approved decision actions", async () => {
  const handle = await handler();
  let rpcCalls = 0;
  const db = withAuthenticatedUser({
    from(table: string) {
      return {
        select() {
          return this;
        },
        neq() {
          return this;
        },
        in() {
          return this;
        },
        eq() {
          return this;
        },
        async single() {
          if (table === "card_catalog_enrichment_jobs") {
            return {
              data: {
                id: "job-1",
                card_id: "card-1",
                staging_id: "staging-1",
                status: "staged",
              },
              error: null,
            };
          }
          return {
            data: {
              id: "staging-1",
              card_id: "card-1",
              status: "pending",
              request_type: "official_benefit_enrichment",
            },
            error: null,
          };
        },
      };
    },
    async rpc(name: string, args: Record<string, unknown>) {
      rpcCalls += 1;
      assert(
        name === "approve_card_benefit_enrichment",
        "approval bypassed the approval RPC",
      );
      assert(
        args._staging_id === "staging-1",
        "approval used an unowned staging row",
      );
      return {
        data: [{ staging_id: "staging-1", resulting_status: "approved" }],
        error: null,
      };
    },
  });
  const originalAllowlist = Deno.env.get("CARD_CATALOG_ADMIN_EMAILS");
  Deno.env.set("CARD_CATALOG_ADMIN_EMAILS", "admin@example.com");
  try {
    const invalid = await handle(
      request({
        action: "benefit-approve",
        job_id: "job-1",
        staging_id: "staging-1",
        decisions: [{ action: "remove" }],
      }),
      db,
    );
    const approved = await handle(
      request({
        action: "benefit-approve",
        job_id: "job-1",
        staging_id: "staging-1",
        decisions: [{ action: "approve", benefit: { title: "Dining credit" } }],
      }),
      db,
    );
    const edited = await handle(
      request({
        action: "benefit-edit-approve",
        job_id: "job-1",
        staging_id: "staging-1",
        decisions: [{
          action: "edit",
          edited_benefit: { title: "Edited dining credit" },
        }],
      }),
      db,
    );

    assert(
      invalid.status === 400,
      "unsupported approval decision was accepted",
    );
    assert(
      approved.status === 200,
      "matching pending staging was not approved",
    );
    assert(
      edited.status === 200,
      "matching pending staging was not edit-approved",
    );
    assert(rpcCalls === 2, "invalid decision reached the approval RPC");
  } finally {
    if (originalAllowlist === undefined) {
      Deno.env.delete("CARD_CATALOG_ADMIN_EMAILS");
    } else Deno.env.set("CARD_CATALOG_ADMIN_EMAILS", originalAllowlist);
  }
});

Deno.test("benefit quarantine state changes are explicit and a pilot uses the service-role pilot RPC", async () => {
  const handle = await handler();
  const jobs: Record<string, unknown> = {
    id: "job-1",
    status: "review_required",
    attempt_count: 3,
    run_mode: "pilot",
    parser_version: "benefits-v1",
    updated_at: "2026-08-17T12:00:00.000Z",
    result_summary: { run_id: "run-1" },
  };
  let pilotCalls = 0;
  const db = withAuthenticatedUser({
    from(table: string) {
      assert(
        table === "card_catalog_enrichment_jobs",
        "state action used an unexpected table",
      );
      let pendingPatch: Record<string, unknown> | null = null;
      return {
        update(patch: Record<string, unknown>) {
          pendingPatch = patch;
          return this;
        },
        eq() {
          return this;
        },
        neq() {
          return this;
        },
        in(column: string, states: string[]) {
          const current = String(jobs.status);
          if (column === "status") {
            assert(
              states.includes(current),
              "state action accepted an invalid transition",
            );
          }
          return this;
        },
        select() {
          return this;
        },
        async single() {
          Object.assign(jobs, pendingPatch);
          return { data: { ...jobs }, error: null };
        },
      };
    },
    async rpc(name: string, args: Record<string, unknown>) {
      pilotCalls += 1;
      assert(
        name === "initialize_card_benefit_enrichment_pilot",
        "pilot bypassed the initialization RPC",
      );
      assert(
        Array.isArray(args._candidates) && args._candidates.length === 5,
        "pilot did not send five candidates",
      );
      return { data: [{ id: "pilot-1", status: "queued" }], error: null };
    },
  });
  const candidates = [
    "straightforward",
    "redirect_or_js",
    "terms_linked",
    "known_invalid",
    "additional_valid",
  ].map((profile, index) => ({ card_id: `card-${index}`, profile }));
  const originalAllowlist = Deno.env.get("CARD_CATALOG_ADMIN_EMAILS");
  Deno.env.set("CARD_CATALOG_ADMIN_EMAILS", "admin@example.com");
  try {
    const quarantined = await handle(
      request({
        action: "benefit-quarantine",
        job_id: "job-1",
        reason: "known invalid issuer page",
      }),
      db,
    );
    const statusAfterQuarantine = String(jobs.status);
    const unquarantined = await handle(
      request({ action: "benefit-unquarantine", job_id: "job-1" }),
      db,
    );
    const invalidPilot = await handle(
      request({
        action: "benefit-start-pilot",
        parser_version: "catalog-v1",
        candidates,
      }),
      db,
    );
    const startedPilot = await handle(
      request({ action: "benefit-start-pilot", candidates }),
      db,
    );

    assert(
      quarantined.status === 200 && statusAfterQuarantine === "quarantined",
      "job was not quarantined",
    );
    assert(
      unquarantined.status === 200 && String(jobs.status) === "queued",
      "quarantined job was not queued",
    );
    assert(invalidPilot.status === 400, "reserved parser started a pilot");
    assert(startedPilot.status === 200, "valid pilot was not initialized");
    assert(
      pilotCalls === 1,
      "invalid pilot input reached the initialization RPC",
    );
  } finally {
    if (originalAllowlist === undefined) {
      Deno.env.delete("CARD_CATALOG_ADMIN_EMAILS");
    } else Deno.env.set("CARD_CATALOG_ADMIN_EMAILS", originalAllowlist);
  }
});

Deno.test("benefit rejection requires a reason and retry resets only retryable job state", async () => {
  const handle = await handler();
  const job = {
    id: "job-1",
    status: "failed",
    attempt_count: 2,
    run_mode: "scheduled",
    parser_version: "benefits-v1",
    result_summary: { run_id: "run-1" },
  };
  const db = withAuthenticatedUser({
    from(table: string) {
      assert(
        table === "card_catalog_enrichment_jobs",
        "retry used an unexpected table",
      );
      return {
        update(patch: Record<string, unknown>) {
          Object.assign(job, patch);
          return this;
        },
        eq() {
          return this;
        },
        neq() {
          return this;
        },
        in(column: string, statuses: string[]) {
          if (column === "status") {
            assert(
              statuses.includes("failed") &&
                statuses.includes("review_required"),
              "retry allowed a terminal state",
            );
          }
          return this;
        },
        select() {
          return this;
        },
        async single() {
          return { data: { ...job }, error: null };
        },
      };
    },
    async rpc() {
      throw new Error(
        "rejection without a reason must not reach the approval RPC",
      );
    },
  });
  const originalAllowlist = Deno.env.get("CARD_CATALOG_ADMIN_EMAILS");
  Deno.env.set("CARD_CATALOG_ADMIN_EMAILS", "admin@example.com");
  try {
    const rejected = await handle(
      request({
        action: "benefit-reject",
        job_id: "job-1",
        staging_id: "staging-1",
        decisions: [{ action: "reject" }],
        reason: "",
      }),
      db,
    );
    const retried = await handle(
      request({ action: "benefit-retry", job_id: "job-1" }),
      db,
    );

    assert(rejected.status === 400, "reasonless rejection was accepted");
    assert(retried.status === 200, "failed job was not reset for retry");
    assert(job.status === "queued", "retry did not queue the failed job");
    assert(job.attempt_count === 2, "retry reset the attempt history");
    assert(job.run_mode === "scheduled", "retry changed the ownership lane");
    assert(
      job.result_summary.run_id === "run-1",
      "retry overwrote run history",
    );
  } finally {
    if (originalAllowlist === undefined) {
      Deno.env.delete("CARD_CATALOG_ADMIN_EMAILS");
    } else Deno.env.set("CARD_CATALOG_ADMIN_EMAILS", originalAllowlist);
  }
});

Deno.test("benefit reads exclude legacy catalog jobs in the query and response", async () => {
  const handle = await handler();
  const rows = [
    {
      id: "catalog-job",
      parser_version: "catalog-v1",
      run_mode: "manual",
      status: "failed",
    },
    {
      id: "benefit-job",
      parser_version: "benefits-v1",
      run_mode: "scheduled",
      status: "failed",
    },
  ];
  const db = withAuthenticatedUser({
    from(table: string) {
      assert(
        table === "card_catalog_enrichment_jobs",
        "read used an unexpected table",
      );
      let excludeCatalog = false;
      let allowedModes: string[] = [];
      return {
        select() {
          return this;
        },
        neq(column: string, value: string) {
          if (column === "parser_version" && value === "catalog-v1") {
            excludeCatalog = true;
          }
          return this;
        },
        in(column: string, values: string[]) {
          if (column === "run_mode") allowedModes = values;
          return this;
        },
        eq() {
          return this;
        },
        order() {
          return this;
        },
        async range() {
          const data = rows.filter((row) =>
            (!excludeCatalog || row.parser_version !== "catalog-v1") &&
            (allowedModes.length === 0 || allowedModes.includes(row.run_mode))
          );
          return { data, error: null };
        },
        async limit() {
          const data = rows.filter((row) =>
            (!excludeCatalog || row.parser_version !== "catalog-v1") &&
            (allowedModes.length === 0 || allowedModes.includes(row.run_mode))
          );
          return { data, error: null };
        },
      };
    },
  });
  const originalAllowlist = Deno.env.get("CARD_CATALOG_ADMIN_EMAILS");
  Deno.env.set("CARD_CATALOG_ADMIN_EMAILS", "admin@example.com");
  try {
    const response = await handle(request({ action: "benefit-list" }), db);
    const body = await response.json();
    assert(response.status === 200, "benefit list was rejected");
    assert(
      body.items.length === 1,
      "legacy catalog job appeared in benefit list",
    );
    assert(
      body.items[0].id === "benefit-job",
      "benefit list returned the wrong lane",
    );
  } finally {
    if (originalAllowlist === undefined) {
      Deno.env.delete("CARD_CATALOG_ADMIN_EMAILS");
    } else Deno.env.set("CARD_CATALOG_ADMIN_EMAILS", originalAllowlist);
  }
});

Deno.test("benefit mutations cannot update catalog-v1 jobs", async () => {
  const handle = await handler();
  const originalAllowlist = Deno.env.get("CARD_CATALOG_ADMIN_EMAILS");
  Deno.env.set("CARD_CATALOG_ADMIN_EMAILS", "admin@example.com");
  try {
    for (
      const [action, status] of [
        ["benefit-retry", "failed"],
        ["benefit-quarantine", "failed"],
        ["benefit-unquarantine", "quarantined"],
      ]
    ) {
      const job = {
        id: "catalog-job",
        parser_version: "catalog-v1",
        run_mode: "manual",
        status,
      };
      const db = withAuthenticatedUser({
        from(table: string) {
          assert(
            table === "card_catalog_enrichment_jobs",
            "mutation used an unexpected table",
          );
          let patch: Record<string, unknown> | null = null;
          let benefitLaneOnly = false;
          let approvedRunModes: string[] = [];
          return {
            update(next: Record<string, unknown>) {
              patch = next;
              return this;
            },
            eq() {
              return this;
            },
            neq(column: string, value: string) {
              if (column === "parser_version" && value === "catalog-v1") {
                benefitLaneOnly = true;
              }
              return this;
            },
            in(column: string, values: string[]) {
              if (column === "run_mode") approvedRunModes = values;
              return this;
            },
            select() {
              return this;
            },
            async single() {
              const eligible =
                (!benefitLaneOnly || job.parser_version !== "catalog-v1") &&
                (approvedRunModes.length === 0 ||
                  approvedRunModes.includes(job.run_mode));
              if (eligible && patch) Object.assign(job, patch);
              return { data: eligible ? job : null, error: null };
            },
          };
        },
      });
      const response = await handle(
        request({ action, job_id: "catalog-job", reason: "legacy lane" }),
        db,
      );
      assert(response.status === 409, `${action} mutated a catalog-v1 job`);
      assert(job.status === status, `${action} changed a catalog-v1 job state`);
    }
  } finally {
    if (originalAllowlist === undefined) {
      Deno.env.delete("CARD_CATALOG_ADMIN_EMAILS");
    } else Deno.env.set("CARD_CATALOG_ADMIN_EMAILS", originalAllowlist);
  }
});

Deno.test("benefit DTOs allow only documented nested output fields", async () => {
  const handle = await handler();
  const db = withAuthenticatedUser({
    from() {
      return {
        select() {
          return this;
        },
        neq() {
          return this;
        },
        in() {
          return this;
        },
        eq() {
          return this;
        },
        order() {
          return this;
        },
        async range() {
          return {
            data: [{
              id: "job-1",
              parser_version: "benefits-v1",
              run_mode: "scheduled",
              status: "staged",
              clientSecret: "must not escape",
              result_summary: {
                run_id: "run-1",
                accessToken: "must not escape",
                debug_trace: "unknown field",
              },
              card_catalog: {
                id: "card-1",
                bank: "Axis",
                card_name: "Ace",
                internal: "unknown",
              },
              card_benefits_staging: {
                id: "staging-1",
                request_type: "official_benefit_enrichment",
                source_evidence: [{
                  source_excerpt: "₹500 dining credit",
                  authorizationHeader: "must not escape",
                  proof: "unknown field",
                }],
                extracted_data: {
                  diff: {
                    additions: [{
                      title: "Dining credit",
                      warnings: ["low_confidence"],
                      responseBody: "must not escape",
                    }],
                  },
                  unknown_nested: "must not escape",
                },
                benefit_decisions: [{
                  action: "approve",
                  decision_note: "unknown field",
                }],
              },
            }],
            error: null,
          };
        },
        async limit() {
          return {
            data: [{
              id: "job-1",
              parser_version: "benefits-v1",
              run_mode: "scheduled",
              status: "staged",
              clientSecret: "must not escape",
              result_summary: {
                run_id: "run-1",
                accessToken: "must not escape",
                debug_trace: "unknown field",
              },
              card_catalog: {
                id: "card-1",
                bank: "Axis",
                card_name: "Ace",
                internal: "unknown",
              },
              card_benefits_staging: {
                id: "staging-1",
                request_type: "official_benefit_enrichment",
                source_evidence: [{
                  source_excerpt: "₹500 dining credit",
                  authorizationHeader: "must not escape",
                  proof: "unknown field",
                }],
                extracted_data: {
                  diff: {
                    additions: [{
                      title: "Dining credit",
                      responseBody: "must not escape",
                    }],
                  },
                  unknown_nested: "must not escape",
                },
                benefit_decisions: [{
                  action: "approve",
                  decision_note: "unknown field",
                }],
              },
            }],
            error: null,
          };
        },
      };
    },
  });
  const originalAllowlist = Deno.env.get("CARD_CATALOG_ADMIN_EMAILS");
  Deno.env.set("CARD_CATALOG_ADMIN_EMAILS", "admin@example.com");
  try {
    const response = await handle(request({ action: "benefit-list" }), db);
    const serialized = JSON.stringify(await response.json());
    assert(response.status === 200, "benefit DTO response was rejected");
    for (
      const prohibited of [
        "must not escape",
        "unknown field",
        "unknown_nested",
        "debug_trace",
        "clientSecret",
        "accessToken",
        "responseBody",
        "authorizationHeader",
      ]
    ) {
      assert(!serialized.includes(prohibited), `DTO exposed ${prohibited}`);
    }
    assert(
      serialized.includes("₹500 dining credit"),
      "allowlisted evidence was omitted",
    );
    assert(
      serialized.includes("low_confidence"),
      "allowlisted warning was omitted",
    );
  } finally {
    if (originalAllowlist === undefined) {
      Deno.env.delete("CARD_CATALOG_ADMIN_EMAILS");
    } else Deno.env.set("CARD_CATALOG_ADMIN_EMAILS", originalAllowlist);
  }
});

Deno.test("benefit counts remain complete while list and history use explicit pages", async () => {
  const handle = await handler();
  const rows = Array.from({ length: 130 }, (_, index) => ({
    id: `benefit-${index + 1}`,
    parser_version: "benefits-v1",
    run_mode: "scheduled",
    status: index < 100 ? "queued" : "staged",
    result_summary: { run_id: `run-${index + 1}` },
  }));
  let countQueries = 0;
  const db = withAuthenticatedUser({
    async rpc(name: string) {
      assert(
        name === "get_movie_benefit_mapping_health",
        "status used an unexpected RPC",
      );
      return {
        data: [
          { metric: "active_movie_benefits", value: 49 },
          { metric: "mapped_active_movie_benefits", value: 8 },
          { metric: "orphaned_active_movie_benefits", value: 41 },
        ],
        error: null,
      };
    },
    from(table: string) {
      assert(
        table === "card_catalog_enrichment_jobs",
        "coverage used an unexpected table",
      );
      let countOnly = false;
      let offset = 0;
      let end = rows.length - 1;
      return {
        select(_columns: string, options?: { count?: string; head?: boolean }) {
          countOnly = options?.count === "exact" && options.head === true;
          return this;
        },
        neq() {
          return this;
        },
        in() {
          return this;
        },
        eq() {
          return this;
        },
        order() {
          return this;
        },
        range(start: number, stop: number) {
          offset = start;
          end = stop;
          return this;
        },
        async limit(limit: number) {
          return { data: rows.slice(0, limit), error: null };
        },
        then(onfulfilled: (value: unknown) => unknown) {
          if (countOnly) {
            countQueries += 1;
            return Promise.resolve({
              data: null,
              count: rows.length,
              error: null,
            }).then(onfulfilled);
          }
          return Promise.resolve({
            data: rows.slice(offset, end + 1),
            error: null,
          }).then(onfulfilled);
        },
      };
    },
  });
  const originalAllowlist = Deno.env.get("CARD_CATALOG_ADMIN_EMAILS");
  Deno.env.set("CARD_CATALOG_ADMIN_EMAILS", "admin@example.com");
  try {
    const response = await handle(
      request({ action: "benefit-status", page: 2, limit: 25 }),
      db,
    );
    const body = await response.json();
    assert(response.status === 200, "paginated benefit status was rejected");
    assert(body.items.length === 25, "status page did not honor its limit");
    assert(
      body.items[0].id === "benefit-26",
      "status page did not honor its offset",
    );
    assert(
      body.page === 2 && body.limit === 25 && body.has_more === true,
      "page metadata was missing",
    );
    assert(
      body.run_counts.total === 130,
      "run counts were derived from the page",
    );
    assert(
      countQueries > 0,
      "run counts did not use an independent aggregate query",
    );
    assert(
      body.movie_mapping_health[2].value === 41,
      "movie mapping health was omitted from admin status",
    );
  } finally {
    if (originalAllowlist === undefined) {
      Deno.env.delete("CARD_CATALOG_ADMIN_EMAILS");
    } else Deno.env.set("CARD_CATALOG_ADMIN_EMAILS", originalAllowlist);
  }
});

function quarantineStateDb(
  job: Record<string, unknown>,
  raceAfterRead = false,
) {
  return withAuthenticatedUser({
    from(table: string) {
      assert(
        table === "card_catalog_enrichment_jobs",
        "quarantine used an unexpected table",
      );
      let patch: Record<string, unknown> | null = null;
      const equals = new Map<string, unknown>();
      const allowed = new Map<string, unknown[]>();
      let excludesCatalog = false;
      return {
        select() {
          return this;
        },
        update(next: Record<string, unknown>) {
          patch = next;
          return this;
        },
        eq(column: string, value: unknown) {
          equals.set(column, value);
          return this;
        },
        neq(column: string, value: unknown) {
          if (column === "parser_version" && value === "catalog-v1") {
            excludesCatalog = true;
          }
          return this;
        },
        in(column: string, values: unknown[]) {
          allowed.set(column, values);
          return this;
        },
        async single() {
          const eligible =
            (!excludesCatalog || job.parser_version !== "catalog-v1") &&
            [...equals].every(([column, value]) => job[column] === value) &&
            [...allowed].every(([column, values]) =>
              values.includes(job[column])
            );
          if (!patch) {
            const snapshot = eligible ? structuredClone(job) : null;
            if (snapshot && raceAfterRead) {
              job.updated_at = "2026-08-17T12:01:00.000Z";
            }
            return { data: snapshot, error: null };
          }
          if (eligible) Object.assign(job, patch);
          return { data: eligible ? structuredClone(job) : null, error: null };
        },
      };
    },
  });
}

Deno.test("manual quarantine preserves safety history and records a justified terminal summary", async () => {
  const handle = await handler();
  const job: Record<string, unknown> = {
    id: "pilot-job-1",
    parser_version: "benefits-v1",
    run_mode: "pilot",
    status: "review_required",
    updated_at: "2026-08-17T12:00:00.000Z",
    result_summary: {
      run_id: "run-1",
      unsafe_mutation_count: 2,
      raw_body_stored: true,
      evidence_passed: false,
      idempotency_passed: false,
    },
  };
  const originalAllowlist = Deno.env.get("CARD_CATALOG_ADMIN_EMAILS");
  Deno.env.set("CARD_CATALOG_ADMIN_EMAILS", "admin@example.com");
  try {
    const response = await handle(
      request({
        action: "benefit-quarantine",
        job_id: "pilot-job-1",
        reason: "identity mismatch confirmed",
      }),
      quarantineStateDb(job),
    );
    const summary = job.result_summary as Record<string, unknown>;
    assert(
      response.status === 200,
      "review-required pilot job was not quarantined",
    );
    assert(
      job.status === "quarantined",
      "quarantine did not reach a terminal state",
    );
    assert(summary.run_id === "run-1", "quarantine erased run history");
    assert(
      summary.unsafe_mutation_count === 2,
      "quarantine falsified unsafe mutation history",
    );
    assert(
      summary.raw_body_stored === true,
      "quarantine falsified raw-body history",
    );
    assert(
      summary.evidence_passed === false,
      "quarantine falsified evidence history",
    );
    assert(
      summary.quarantine_reason === "identity mismatch confirmed",
      "quarantine reason was not recorded",
    );
    assert(
      summary.idempotency_passed === true,
      "justified quarantine was not marked idempotent",
    );
  } finally {
    if (originalAllowlist === undefined) {
      Deno.env.delete("CARD_CATALOG_ADMIN_EMAILS");
    } else Deno.env.set("CARD_CATALOG_ADMIN_EMAILS", originalAllowlist);
  }
});

Deno.test("manual quarantine loses an optimistic race instead of overwriting newer job state", async () => {
  const handle = await handler();
  const job: Record<string, unknown> = {
    id: "pilot-job-race",
    parser_version: "benefits-v1",
    run_mode: "pilot",
    status: "review_required",
    updated_at: "2026-08-17T12:00:00.000Z",
    result_summary: {
      run_id: "run-race",
      unsafe_mutation_count: 0,
      raw_body_stored: false,
      evidence_passed: true,
    },
  };
  const originalAllowlist = Deno.env.get("CARD_CATALOG_ADMIN_EMAILS");
  Deno.env.set("CARD_CATALOG_ADMIN_EMAILS", "admin@example.com");
  try {
    const response = await handle(
      request({
        action: "benefit-quarantine",
        job_id: "pilot-job-race",
        reason: "issuer page confirmed invalid",
      }),
      quarantineStateDb(job, true),
    );
    assert(
      response.status === 409,
      "stale quarantine overwrote newer job state",
    );
    assert(
      job.status === "review_required",
      "stale quarantine changed the job status",
    );
    assert(
      (job.result_summary as Record<string, unknown>).quarantine_reason ===
        undefined,
      "stale quarantine changed the result summary",
    );
  } finally {
    if (originalAllowlist === undefined) {
      Deno.env.delete("CARD_CATALOG_ADMIN_EMAILS");
    } else Deno.env.set("CARD_CATALOG_ADMIN_EMAILS", originalAllowlist);
  }
});
