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
      assert(
        table === "card_catalog_enrichment_jobs",
        "list read an unexpected table",
      );
      return {
        select() {
          return this;
        },
        eq() {
          return this;
        },
        order() {
          return this;
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
        in(_column: string, states: string[]) {
          const current = String(jobs.status);
          assert(
            states.includes(current),
            "state action accepted an invalid transition",
          );
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
        in(_column: string, statuses: string[]) {
          assert(
            statuses.includes("failed") && statuses.includes("review_required"),
            "retry allowed a terminal state",
          );
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
