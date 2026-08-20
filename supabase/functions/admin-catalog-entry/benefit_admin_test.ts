import {
  buildCanonicalPublicationEnvelope,
  handleBenefitAdminAction,
  presentBenefitJob,
  sanitizeAdminDto,
  validateCanonicalPublicationEnvelope,
  validateRetirementDecisionEvidence,
  validateV5ApprovalDecisions,
  validateV6ApprovalDecisions,
} from "./benefit_admin.ts";
import {
  currentBenefitProposal,
  diffBenefits,
  extractGroundedBenefits,
  extractGroundedBenefitsV6,
} from "../_shared/benefit_enrichment.ts";
import {
  canonicalConditionObject,
  stableCanonicalJson,
} from "../_shared/benefit_contract.ts";

type AdminHandler = (
  request: Request,
  db: Record<string, unknown>,
  authDb?: Record<string, unknown>,
) => Promise<Response>;

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

async function sha256(value: unknown): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(stableCanonicalJson(value)),
  );
  return [...new Uint8Array(digest)].map((byte) =>
    byte.toString(16).padStart(2, "0")
  ).join("");
}

async function legacyRewardAliasProposal(
  proposal: Record<string, any>,
  cardId: string,
) {
  const config = { ...proposal.valueConfig };
  delete config.offer_subject;
  delete config.restrictions;
  delete config.exclusions;
  const condition = canonicalConditionObject({
    title: proposal.title,
    category: "points",
    benefitType: proposal.valueType,
    semanticKey: proposal.offerSubject,
    value: proposal.value,
    rate: proposal.rate,
    cap: proposal.cap,
    threshold: proposal.threshold,
    frequency: proposal.frequency,
    period: proposal.period,
    valueConfig: config,
    exclusions: proposal.exclusions,
    restrictions: proposal.restrictions,
    partners: proposal.partners,
    regions: proposal.regions,
    validFrom: proposal.effectiveFrom,
    validUntil: proposal.effectiveTo,
  });
  condition.category = "rewards";
  const conditionHash = await sha256([condition]);
  const dedupeKey = `card-benefit-v2:${cardId.toLowerCase()}:${conditionHash}`;
  return {
    ...proposal,
    category: "rewards",
    conditionHash,
    benefitId: dedupeKey,
    dedupeKey,
  };
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

Deno.test("reviewed page-move conflicts remain explicitly retryable", async () => {
  const module = await import("./index.ts");
  const busy = module.safeError({
    code: "40001",
    message: "reviewed_enrichment_source_busy",
  });
  assert(
    busy.status === 409 && busy.error === "publication_busy",
    "serialization conflict was hidden as a non-retryable request failure",
  );
  const identity = module.safeError({ message: "conflicting_url_identity" });
  assert(
    identity.status === 409 && identity.error === "conflicting_url_identity",
    "reviewed identity conflict lost its stable outcome",
  );
  const stale = module.safeError({ message: "stale_catalog_baseline" });
  assert(
    stale.status === 409 && stale.error === "stale_catalog_baseline",
    "stale reviewed catalog state was not returned as a retryable conflict",
  );
});

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

Deno.test("admin auth uses the caller project key with the bearer token", async () => {
  const module = await import("./index.ts") as {
    createAdminAuthClient?: (
      request: Request,
      supabaseUrl: string,
      fallbackKey: string,
      factory: (...args: unknown[]) => unknown,
    ) => unknown;
  };
  assert(
    typeof module.createAdminAuthClient === "function",
    "request-scoped auth client factory is missing",
  );
  let capturedArgs: unknown[] = [];
  const requestWithCurrentKey = new Request(
    "https://example.test/admin-catalog-entry",
    {
      headers: {
        authorization: "Bearer current-user-token",
        apikey: "current-browser-key",
      },
    },
  );

  module.createAdminAuthClient(
    requestWithCurrentKey,
    "https://project.supabase.co",
    "stale-hosted-key",
    (...args: unknown[]) => {
      capturedArgs = args;
      return {};
    },
  );

  assert(
    capturedArgs[1] === "current-browser-key",
    "stale hosted key was used instead of the caller project key",
  );
  const options = capturedArgs[2] as {
    global?: { headers?: { Authorization?: string } };
  };
  assert(
    options.global?.headers?.Authorization === "Bearer current-user-token",
    "caller bearer token was not forwarded to the auth client",
  );
});

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

Deno.test("protected admin handler authenticates with a request-scoped client", async () => {
  const handle = await handler();
  const originalAllowlist = Deno.env.get("CARD_CATALOG_ADMIN_EMAILS");
  Deno.env.set("CARD_CATALOG_ADMIN_EMAILS", "admin@example.com");
  try {
    const serviceDb = authenticatedDb(null, new Error("service auth rejected"));
    const requestAuthDb = {
      auth: {
        async getUser(token: unknown) {
          if (token !== "valid-token") {
            return {
              data: { user: null },
              error: new Error("request JWT was not provided"),
            };
          }
          return {
            data: {
              user: {
                id: "admin-1",
                email: "admin@example.com",
                email_confirmed_at: "2026-08-17T00:00:00.000Z",
              },
            },
            error: null,
          };
        },
      },
    };

    const response = await handle(
      request({ action: "access" }),
      serviceDb,
      requestAuthDb,
    );

    assert(
      response.status === 200,
      "service-role auth client was used instead of request-scoped auth",
    );
  } finally {
    if (originalAllowlist === undefined) {
      Deno.env.delete("CARD_CATALOG_ADMIN_EMAILS");
    } else Deno.env.set("CARD_CATALOG_ADMIN_EMAILS", originalAllowlist);
  }
});

Deno.test("admin cleanup terminalizes calculator reviews without deleting history", async () => {
  const handle = await handler();
  const originalAllowlist = Deno.env.get("CARD_CATALOG_ADMIN_EMAILS");
  Deno.env.set("CARD_CATALOG_ADMIN_EMAILS", "admin@example.com");
  const calls: Array<{ name: string; args: Record<string, unknown> }> = [];
  const serviceDb = {
    rpc(name: string, args: Record<string, unknown>) {
      calls.push({ name, args });
      return Promise.resolve({ data: 1, error: null });
    },
  };
  try {
    const unconfirmed = await handle(
      request({ action: "purge-calculator-reviews" }),
      serviceDb,
      authenticatedDb({
        id: "admin-1",
        email: "admin@example.com",
        email_confirmed_at: "2026-08-17T00:00:00.000Z",
      }),
    );
    assert(
      unconfirmed.status === 400,
      "unconfirmed cleanup mutated review work",
    );
    assert(calls.length === 0, "unconfirmed cleanup reached SQL");
    const response = await handle(
      request({
        action: "purge-calculator-reviews",
        confirm: "non_product_calculator_resource",
      }),
      serviceDb,
      authenticatedDb({
        id: "admin-1",
        email: "admin@example.com",
        email_confirmed_at: "2026-08-17T00:00:00.000Z",
      }),
    );
    const body = await response.json();
    assert(response.status === 200, "calculator cleanup was rejected");
    assert(
      body.transitioned === 1,
      "cleanup returned the wrong transition count",
    );
    assert(
      Number(calls.length) === 1 &&
        calls[0].name === "terminalize_calculator_review_rows" &&
        calls[0].args._actor_id === "admin-1" &&
        calls[0].args._confirmed === true,
      "cleanup bypassed the retained-history transition boundary",
    );
  } finally {
    if (originalAllowlist === undefined) {
      Deno.env.delete("CARD_CATALOG_ADMIN_EMAILS");
    } else Deno.env.set("CARD_CATALOG_ADMIN_EMAILS", originalAllowlist);
  }
});

Deno.test("listing pending catalog reviews is read-only", async () => {
  const handle = await handler();
  const originalAllowlist = Deno.env.get("CARD_CATALOG_ADMIN_EMAILS");
  Deno.env.set("CARD_CATALOG_ADMIN_EMAILS", "admin@example.com");
  let rpcCalls = 0;
  const query = {
    select() {
      return query;
    },
    order() {
      return query;
    },
    eq() {
      return query;
    },
    async limit() {
      return { data: [], error: null };
    },
  };
  const serviceDb = {
    rpc() {
      rpcCalls += 1;
      return Promise.resolve({ data: 0, error: null });
    },
    from() {
      return query;
    },
  };
  try {
    const response = await handle(
      request({ action: "list", status: "pending" }),
      serviceDb,
      authenticatedDb({
        id: "admin-1",
        email: "admin@example.com",
        email_confirmed_at: "2026-08-17T00:00:00.000Z",
      }),
    );
    assert(response.status === 200, "pending list failed");
    assert(rpcCalls === 0, "read-only listing terminalized review work");
  } finally {
    if (originalAllowlist === undefined) {
      Deno.env.delete("CARD_CATALOG_ADMIN_EMAILS");
    } else Deno.env.set("CARD_CATALOG_ADMIN_EMAILS", originalAllowlist);
  }
});

Deno.test("issuer quarantine listing is newest-first filtered and cursor-paginated", async () => {
  const handle = await handler();
  const originalAllowlist = Deno.env.get("CARD_CATALOG_ADMIN_EMAILS");
  Deno.env.set("CARD_CATALOG_ADMIN_EMAILS", "admin@example.com");
  const rows = [
    {
      id: "33333333-3333-4333-8333-333333333333",
      status: "pending",
      created_at: "2026-08-20T00:00:03+00:00",
      proposed_fields: {
        source_observation: {
          classification: "issuer_discovery_quarantine",
        },
      },
    },
    {
      id: "22222222-2222-4222-8222-222222222222",
      status: "pending",
      created_at: "2026-08-20T00:00:02+00:00",
      proposed_fields: {
        source_observation: {
          classification: "issuer_discovery_quarantine",
        },
      },
    },
    {
      id: "11111111-1111-4111-8111-111111111111",
      status: "pending",
      created_at: "2026-08-20T00:00:01+00:00",
      proposed_fields: {
        source_observation: {
          classification: "issuer_discovery_quarantine",
        },
      },
    },
  ];
  const queryRecords: Array<{
    contains?: Record<string, unknown>;
    cursor?: string;
    limit?: number;
    orders?: Array<{ column: string; ascending: boolean }>;
  }> = [];
  const serviceDb = {
    rpc() {
      throw new Error("quarantine list must remain read-only");
    },
    from() {
      const record: {
        contains?: Record<string, unknown>;
        cursor?: string;
        limit?: number;
        orders?: Array<{ column: string; ascending: boolean }>;
      } = { orders: [] };
      queryRecords.push(record);
      const query = {
        select() {
          return query;
        },
        order(column: string, options?: { ascending?: boolean }) {
          record.orders?.push({
            column,
            ascending: options?.ascending !== false,
          });
          return query;
        },
        eq() {
          return query;
        },
        contains(_column: string, value: Record<string, unknown>) {
          record.contains = value;
          return query;
        },
        or(value: string) {
          record.cursor = value;
          return query;
        },
        async limit(value: number) {
          record.limit = value;
          return {
            data: record.cursor ? rows.slice(2) : rows,
            error: null,
          };
        },
      };
      return query;
    },
  };
  const auth = authenticatedDb({
    id: "admin-1",
    email: "admin@example.com",
    email_confirmed_at: "2026-08-17T00:00:00.000Z",
  });
  try {
    const firstResponse = await handle(
      request({
        action: "issuer-quarantine-list",
        status: "pending",
        limit: 2,
      }),
      serviceDb,
      auth,
    );
    const first = await firstResponse.json();
    assert(firstResponse.status === 200, "quarantine list action failed");
    assert(
      first.items.length === 2 && first.items[0].id === rows[0].id,
      "newest quarantine work was not returned first",
    );
    assert(
      typeof first.next_cursor === "string" && first.next_cursor.length > 0,
      "bounded quarantine page omitted its cursor",
    );
    assert(
      JSON.stringify(queryRecords[0].contains).includes(
        "issuer_discovery_quarantine",
      ) && queryRecords[0].limit === 3 &&
        JSON.stringify(queryRecords[0].orders) === JSON.stringify([
            { column: "created_at", ascending: false },
            { column: "id", ascending: false },
          ]),
      "quarantine classification or bounded lookahead was not applied",
    );

    const secondResponse = await handle(
      request({
        action: "issuer-quarantine-list",
        status: "pending",
        limit: 2,
        cursor: first.next_cursor,
      }),
      serviceDb,
      auth,
    );
    const second = await secondResponse.json();
    assert(
      secondResponse.status === 200 && second.items.length === 1 &&
        second.items[0].id === rows[2].id,
      "cursor did not continue after the prior quarantine page",
    );
    assert(
      typeof queryRecords[1].cursor === "string" &&
        queryRecords[1].cursor.length > 0,
      "cursor was not enforced by the database query",
    );
  } finally {
    if (originalAllowlist === undefined) {
      Deno.env.delete("CARD_CATALOG_ADMIN_EMAILS");
    } else Deno.env.set("CARD_CATALOG_ADMIN_EMAILS", originalAllowlist);
  }
});

Deno.test("identity admin actions reject immutable client overrides and allow only edit catalog fields", async () => {
  const handle = await handler();
  const originalAllowlist = Deno.env.get("CARD_CATALOG_ADMIN_EMAILS");
  Deno.env.set("CARD_CATALOG_ADMIN_EMAILS", "admin@example.com");
  const rpcCalls: Array<{ name: string; args: Record<string, unknown> }> = [];
  const review = {
    discovery_job_id: "11111111-1111-4111-8111-111111111111",
    proposed_fields: {
      issuer: "Axis Bank",
      cardName: "Privilege Infinite",
      final_url: "https://www.axis.bank.in/card?variant=infinite",
      content_hash: "a".repeat(64),
    },
    source_evidence: {
      retrieved_at: "2026-08-20T00:00:00.000Z",
    },
  };
  const query = {
    select() {
      return query;
    },
    eq() {
      return query;
    },
    async single() {
      return { data: review, error: null };
    },
  };
  const serviceDb = {
    from() {
      return query;
    },
    async rpc(name: string, args: Record<string, unknown>) {
      rpcCalls.push({ name, args });
      return {
        data: [{
          card_id: "22222222-2222-4222-8222-222222222222",
          job_id: review.discovery_job_id,
          resulting_status: "approved",
        }],
        error: null,
      };
    },
  };
  const auth = authenticatedDb({
    id: "admin-1",
    email: "admin@example.com",
    email_confirmed_at: "2026-08-17T00:00:00.000Z",
  });
  try {
    const approveOverride = await handle(
      request({
        action: "approve",
        review_item_id: "review-1",
        proposed_fields: { final_url: "https://evil.example/card" },
      }),
      serviceDb,
      auth,
    );
    assert(
      approveOverride.status === 400,
      "approve accepted a client proposal",
    );
    const editImmutable = await handle(
      request({
        action: "edit_approve",
        review_item_id: "review-1",
        proposed_fields: { content_hash: "b".repeat(64) },
      }),
      serviceDb,
      auth,
    );
    assert(editImmutable.status === 400, "edit accepted immutable evidence");
    const editAllowed = await handle(
      request({
        action: "edit_approve",
        review_item_id: "review-1",
        proposed_fields: { card_name: "Privilege Reserve", annual_fee: 2500 },
      }),
      serviceDb,
      auth,
    );
    assert(editAllowed.status === 200, "allowed catalog edit was rejected");
    assert(rpcCalls.length === 1, "rejected override reached publication");
    assert(
      JSON.stringify(rpcCalls[0].args._reviewed_fields) ===
        JSON.stringify({ card_name: "Privilege Reserve", annual_fee: 2500 }),
      "immutable review proposal was copied into client edit overrides",
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
                parser_version: "benefits-v5",
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
              parser_version: "benefits-v5",
              extracted_data: {
                request_type: "official_benefit_enrichment",
                parser_version: "benefits-v5",
                proposals: [{
                  dedupeKey: "legacy:dining-credit",
                  title: "Dining credit",
                  description: "Get 10% cashback on dining spends.",
                  category: "cashback",
                  valueType: "cashback",
                  rate: 10,
                  restrictions: [],
                  exclusions: [],
                  sourceUrl: "https://issuer.example/card",
                  sourceExcerpt: "Get 10% cashback on dining spends.",
                  contentHash: "fixture-content",
                  parserVersion: "benefits-v5",
                  confidence: { rate: 0.9 },
                  evidence: { rate: "10% cashback" },
                  warnings: [],
                }],
              },
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
      const decision = (args._decisions as Record<string, any>[])[0];
      assert(
        decision.canonical_envelope?.version === "benefit-publication-v2" &&
          decision.canonical_envelope?.dedupe_key?.startsWith(
            "card-benefit-v2:card-1:",
          ) &&
          decision.canonical_envelope?.benefit?.benefit_category ===
            "cashback",
        "v5 rollback review did not route through the v2 card-scoped envelope",
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
        decisions: [{
          action: "approve",
          benefit: {
            dedupeKey: "legacy:dining-credit",
            title: "Dining credit",
          },
        }],
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
          edited_benefit: {
            dedupeKey: "legacy:dining-credit",
            title: "Edited dining credit",
            rate: 12,
          },
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

Deno.test("v6 admin presentation and approval preserve canonical replay identity", async () => {
  const [proposal] = await extractGroundedBenefitsV6(
    [{
      ...({ sourceIdentity: "a".repeat(64) } as Record<string, unknown>),
      sourceUrl: "https://issuer.example/card",
      text:
        "Get 10% cashback on dining spends, capped at ₹500 per statement month.",
      contentHash: "a".repeat(64),
    }],
    "benefits-v6",
    "card-1",
  );
  const presented = presentBenefitJob({
    id: "job-1",
    card_id: "card-1",
    parser_version: "benefits-v6",
    status: "staged",
    run_mode: "manual",
    card_benefits_staging: {
      id: "staging-1",
      card_id: "card-1",
      request_type: "official_benefit_enrichment",
      parser_version: "benefits-v6",
      status: "pending",
      extracted_data: {
        request_type: "official_benefit_enrichment",
        parser_version: "benefits-v6",
        proposals: [{
          ...proposal,
          sourceUrl: `${proposal.sourceUrl}?selector=secret-query`,
          sourceUrls: [`${proposal.sourceUrl}?selector=secret-query`],
        }],
        diff: { additions: [proposal] },
      },
    },
  }) as Record<string, any>;
  const presentedProposal = presented.staging.extracted_data.proposals[0];
  assert(
    presentedProposal.benefitId === proposal.benefitId &&
      presentedProposal.offerSubject === proposal.offerSubject,
    "admin presenter stripped v6 identity",
  );
  assert(
    presentedProposal.valueConfig.offer_subject === proposal.offerSubject &&
      presentedProposal.valueConfig.restrictions.join(",") === "dining spends",
    "admin presenter stripped canonical identity terms",
  );
  assert(
    !JSON.stringify(presented).includes("secret-query"),
    "admin presenter exposed a raw source query",
  );

  let submitted: Record<string, any>[] = [];
  const db = {
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
          return table === "card_catalog_enrichment_jobs"
            ? {
              data: {
                id: "job-1",
                card_id: "card-1",
                staging_id: "staging-1",
                status: "staged",
                parser_version: "benefits-v6",
              },
              error: null,
            }
            : {
              data: {
                id: "staging-1",
                card_id: "card-1",
                status: "pending",
                request_type: "official_benefit_enrichment",
                parser_version: "benefits-v6",
                extracted_data: {
                  request_type: "official_benefit_enrichment",
                  parser_version: "benefits-v6",
                  proposals: [proposal],
                },
              },
              error: null,
            };
        },
      };
    },
    async rpc(_name: string, args: Record<string, any>) {
      submitted = args._decisions;
      return {
        data: [{ staging_id: "staging-1", resulting_status: "approved" }],
        error: null,
      };
    },
  };
  await handleBenefitAdminAction(db, {
    action: "benefit-approve",
    job_id: "job-1",
    staging_id: "staging-1",
    decisions: [{
      action: "approve",
      benefit: { ...presentedProposal, client_secret: "must not escape" },
    }],
  }, { id: "admin-1" });
  const approved = submitted[0].benefit;
  assert(
    approved.benefitId === proposal.benefitId,
    "approval stripped benefit ID",
  );
  assert(
    approved.offerSubject === proposal.offerSubject,
    "approval stripped offer subject",
  );
  assert(
    approved.conditionHash === proposal.conditionHash,
    "approval stripped canonical condition hash",
  );
  assert(
    !JSON.stringify(submitted).includes("must not escape"),
    "approval forwarded an arbitrary client field",
  );

  const current = currentBenefitProposal({
    dedupe_key: approved.dedupeKey,
    title: approved.title,
    description: approved.description,
    benefit_category: approved.category,
    benefit_type: approved.valueType,
    value_config: approved.valueConfig,
    partners: approved.partners,
    exclusions: approved.exclusions,
    source_url: approved.sourceUrl,
  });
  assert(current != null, "approved v6 row was not reconstructed");
  const replay = await extractGroundedBenefitsV6(
    [{
      ...({ sourceIdentity: "a".repeat(64) } as Record<string, unknown>),
      sourceUrl: "https://issuer.example/card",
      text:
        "Get 10% cashback on dining spends, capped at ₹500 per statement month.",
      contentHash: "a".repeat(64),
    }],
    "benefits-v6",
    "card-1",
  );
  const diff = diffBenefits([current], replay);
  assert(diff.unchanged.length === 1, "approved v6 offer changed on replay");
  assert(
    diff.conflicts.length === 0,
    "approved v6 identity conflicted on replay",
  );
});

Deno.test("v6 approval is bound to exact server-staged canonical proposals", async () => {
  const [proposal] = await extractGroundedBenefitsV6(
    [{
      sourceUrl: "https://issuer.example/card?variant=official",
      text:
        "Get 10% cashback on dining spends, capped at ₹500 per statement month, excluding cash advances.",
      contentHash: "a".repeat(64),
    }],
    "benefits-v6",
    "card-1",
  );
  const call = async (
    decisions: unknown,
    stagedExtraction: unknown = {
      request_type: "official_benefit_enrichment",
      parser_version: "benefits-v6",
      proposals: [proposal],
    },
  ) => {
    let rpcCalls = 0;
    let submitted: Record<string, any>[] = [];
    const db = {
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
            return table === "card_catalog_enrichment_jobs"
              ? {
                data: {
                  id: "job-1",
                  card_id: "card-1",
                  staging_id: "staging-1",
                  status: "staged",
                  parser_version: "benefits-v6",
                },
                error: null,
              }
              : {
                data: {
                  id: "staging-1",
                  card_id: "card-1",
                  status: "pending",
                  request_type: "official_benefit_enrichment",
                  parser_version: "benefits-v6",
                  extracted_data: stagedExtraction,
                },
                error: null,
              };
          },
        };
      },
      async rpc(_name: string, args: Record<string, any>) {
        rpcCalls += 1;
        submitted = args._decisions;
        return {
          data: [{ staging_id: "staging-1", resulting_status: "approved" }],
          error: null,
        };
      },
    };
    let error: unknown;
    try {
      await handleBenefitAdminAction(db, {
        action: Array.isArray(decisions) &&
            (decisions[0] as Record<string, unknown> | null)?.action === "edit"
          ? "benefit-edit-approve"
          : "benefit-approve",
        job_id: "job-1",
        staging_id: "staging-1",
        decisions,
      }, { id: "admin-1" });
    } catch (caught) {
      error = caught;
    }
    return { error, rpcCalls, submitted };
  };
  const exact = { action: "approve", benefit: proposal };
  const tampered = [
    {
      label: "benefit ID",
      decisions: [{
        action: "approve",
        benefit: { ...proposal, benefitId: `${proposal.benefitId}:tampered` },
      }],
    },
    {
      label: "offer subject",
      decisions: [{
        action: "approve",
        benefit: { ...proposal, offerSubject: "cashback:cashback:fuel" },
      }],
    },
    {
      label: "restrictions",
      decisions: [{
        action: "approve",
        benefit: { ...proposal, restrictions: ["fuel spends"] },
      }],
    },
    {
      label: "exclusions",
      decisions: [{
        action: "approve",
        benefit: {
          ...proposal,
          exclusions: { additional: { source_terms: ["wallet reloads"] } },
        },
      }],
    },
    {
      label: "source identity",
      decisions: [{
        action: "approve",
        benefit: { ...proposal, sourceIdentity: "f".repeat(64) },
      }],
    },
    {
      label: "client canonical envelope injection",
      decisions: [{
        action: "approve",
        benefit: proposal,
        canonical_envelope: { nonce: "client-authority" },
      }],
    },
    {
      label: "unknown proposal",
      decisions: [{
        action: "approve",
        benefit: {
          ...proposal,
          benefitId: `card-benefit-v2:card-1:${"f".repeat(64)}`,
          dedupeKey: `card-benefit-v2:card-1:${"f".repeat(64)}`,
          conditionHash: "f".repeat(64),
        },
      }],
    },
    { label: "duplicate proposal", decisions: [exact, exact] },
  ];
  for (const fixture of tampered) {
    const result = await call(fixture.decisions);
    assert(result.error instanceof Error, `${fixture.label} was accepted`);
    assert(result.rpcCalls === 0, `${fixture.label} reached approval RPC`);
  }

  const malformedStaging = [
    {
      label: "null staged proposal",
      extraction: {
        request_type: "official_benefit_enrichment",
        parser_version: "benefits-v6",
        proposals: [null, proposal],
      },
    },
    {
      label: "scalar staged proposal",
      extraction: {
        request_type: "official_benefit_enrichment",
        parser_version: "benefits-v6",
        proposals: [proposal, "corrupt"],
      },
    },
    {
      label: "numeric staged proposal",
      extraction: {
        request_type: "official_benefit_enrichment",
        parser_version: "benefits-v6",
        proposals: [proposal, 5],
      },
    },
    {
      label: "duplicate staged proposal",
      extraction: {
        request_type: "official_benefit_enrichment",
        parser_version: "benefits-v6",
        proposals: [proposal, proposal],
      },
    },
    {
      label: "malformed proposal root",
      extraction: {
        request_type: "official_benefit_enrichment",
        parser_version: "benefits-v6",
        proposals: { valid: proposal },
      },
    },
    { label: "malformed extraction root", extraction: "corrupt" },
  ];
  for (const fixture of malformedStaging) {
    const result = await call([exact], fixture.extraction);
    assert(result.error instanceof Error, `${fixture.label} was filtered`);
    assert(result.rpcCalls === 0, `${fixture.label} reached approval RPC`);
  }

  const inconsistentStagedIdentity = {
    ...proposal,
    dedupeKey: `card-benefit-v2:card-1:${"b".repeat(64)}`,
  };
  const inconsistent = await call(
    [{ action: "approve", benefit: inconsistentStagedIdentity }],
    {
      request_type: "official_benefit_enrichment",
      parser_version: "benefits-v6",
      proposals: [inconsistentStagedIdentity],
    },
  );
  assert(
    inconsistent.error instanceof Error,
    "inconsistent staged benefit/dedupe identity was accepted",
  );
  assert(inconsistent.rpcCalls === 0, "inconsistent staging reached RPC");

  for (const decisions of [[null], ["corrupt"], [5]]) {
    const result = await call(decisions);
    assert(result.error instanceof Error, "malformed decision was accepted");
    assert(result.rpcCalls === 0, "malformed decision reached approval RPC");
  }

  const valid = await call([exact]);
  assert(!valid.error, "exact staged proposal was rejected");
  assert(valid.rpcCalls === 1, "exact staged proposal missed approval RPC");
  assert(
    valid.submitted[0].benefit.conditionHash === proposal.conditionHash,
    "server canonical identity was not submitted",
  );

  const edited = await call([{
    action: "edit",
    edited_benefit: {
      ...proposal,
      title: "Reviewed dining cashback",
      rate: 12,
    },
  }]);
  assert(!edited.error, "material v6 edit was rejected");
  assert(
    edited.submitted[0].edited_benefit.title === "Reviewed dining cashback" &&
      edited.submitted[0].edited_benefit.conditionHash ===
        proposal.conditionHash,
    "v6 edit did not retain server canonical identity",
  );
});

Deno.test("pure v6 decision validation rejects an unstaged canonical identity", async () => {
  const [proposal] = await extractGroundedBenefitsV6(
    [{
      sourceUrl: "https://issuer.example/card",
      text: "Get 10% cashback on dining spends.",
      contentHash: "a".repeat(64),
    }],
    "benefits-v6",
    "card-1",
  );
  const extraction = {
    request_type: "official_benefit_enrichment",
    parser_version: "benefits-v6",
    proposals: [proposal],
  };
  const valid = await validateV6ApprovalDecisions(
    [{ action: "approve", benefit: proposal }],
    extraction,
    "card-1",
  );
  assert(valid[0].benefit != null, "pure validator rejected exact proposal");
  let error: unknown;
  try {
    await validateV6ApprovalDecisions(
      [{
        action: "approve",
        benefit: { ...proposal, restrictions: ["fuel spends"] },
      }],
      extraction,
      "card-1",
    );
  } catch (caught) {
    error = caught;
  }
  assert(error instanceof Error, "pure validator accepted identity smuggling");
});

Deno.test("reward proposals publish with the shared points category and replay key", async () => {
  const staged = {
    title: "Accelerated rewards",
    category: "rewards",
    valueType: "reward_points",
    offerSubject: "rewards:reward_points:general",
    rate: "5",
    restrictions: ["retail spends"],
    exclusions: [],
    partners: [],
    regions: ["IN"],
  };
  const rewards = await buildCanonicalPublicationEnvelope(
    "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
    staged,
  );
  const points = await buildCanonicalPublicationEnvelope(
    "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
    staged,
    { ...staged, category: "POINTS" },
  );
  assert(
    rewards.condition.category === "points",
    "reward condition was not canonicalized",
  );
  assert(
    JSON.stringify(rewards.staged_proposal_binding) === JSON.stringify(staged),
    "server envelope did not retain its exact staged proposal binding",
  );
  assert(
    rewards.benefit.benefit_category === "points",
    "reward DB category was not canonicalized",
  );
  assert(
    rewards.condition_hash === points.condition_hash,
    "reward alias changed canonical hash",
  );
  assert(
    rewards.dedupe_key === points.dedupe_key,
    "reward alias changed card-scoped replay key",
  );
});

Deno.test("canonical publication envelopes reject unknown keys and unsafe numeric domains", async () => {
  const staged = {
    title: "Dining cashback",
    category: "cashback",
    valueType: "cashback",
    offerSubject: "cashback:cashback:dining",
    rate: 10,
    restrictions: ["dining spends"],
    exclusions: [],
    partners: [],
    regions: ["IN"],
  };
  const accepted = await buildCanonicalPublicationEnvelope(
    "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
    staged,
    { ...staged, rate: 0.000001, cap: Number.MAX_SAFE_INTEGER },
  );
  validateCanonicalPublicationEnvelope(accepted);

  const invalid: Array<
    { label: string; mutate: (value: Record<string, any>) => void }
  > = [
    { label: "root nonce", mutate: (value) => value.nonce = "hash-only" },
    {
      label: "condition nonce",
      mutate: (value) => value.condition.nonce = "hash-only",
    },
    {
      label: "nested config nonce",
      mutate: (value) => value.condition.value_config.nonce = "hash-only",
    },
    {
      label: "tiny number",
      mutate: (value) => value.condition.value_config.rate = 1e-7,
    },
    {
      label: "huge number",
      mutate: (value) => value.condition.value_config.rate = 1e21,
    },
    {
      label: "nested exclusion number",
      mutate: (value) =>
        value.condition.exclusions.additional.source_terms = [1e-7],
    },
  ];
  for (const fixture of invalid) {
    const envelope = structuredClone(accepted) as Record<string, any>;
    fixture.mutate(envelope);
    let error: unknown;
    try {
      validateCanonicalPublicationEnvelope(envelope);
    } catch (caught) {
      error = caught;
    }
    assert(error instanceof Error, `${fixture.label} envelope was accepted`);
  }
});

Deno.test("pending pre-alias rewards v6 proposals migrate only from the exact legacy identity", async () => {
  const cardId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
  const [current] = await extractGroundedBenefitsV6(
    [{
      sourceUrl: "https://issuer.example/card",
      text: "Earn 5 reward points for every ₹150 spent on eligible purchases.",
      contentHash: "a".repeat(64),
    }],
    "benefits-v6",
    cardId,
  );
  const legacy = await legacyRewardAliasProposal(current, cardId);
  const extraction = {
    request_type: "official_benefit_enrichment",
    parser_version: "benefits-v6",
    proposals: [legacy],
  };
  const decisions = [{ action: "approve", benefit: legacy }];
  const first = await validateV6ApprovalDecisions(
    decisions,
    extraction,
    cardId,
  );
  const replay = await validateV6ApprovalDecisions(
    decisions,
    extraction,
    cardId,
  );
  const envelope = first[0].canonical_envelope as Record<string, any>;
  assert(
    first[0].change_type === "category_alias_identity_migration" &&
      envelope.condition.category === "points" &&
      envelope.dedupe_key === current.dedupeKey &&
      envelope.identity_migration?.legacy_dedupe_key === legacy.dedupeKey,
    "exact pre-alias reward was not audited into the points identity",
  );
  assert(
    stableCanonicalJson(first) === stableCanonicalJson(replay),
    "legacy reward compatibility was not replay deterministic",
  );

  let tampered: unknown;
  try {
    await validateV6ApprovalDecisions(
      decisions,
      {
        ...extraction,
        proposals: [{ ...legacy, conditionHash: "f".repeat(64) }],
      },
      cardId,
    );
  } catch (caught) {
    tampered = caught;
  }
  assert(
    tampered instanceof Error,
    "tampered pre-alias reward identity was accepted",
  );
});

Deno.test("v6 edits reject display-only changes and preserve explicit date clears", async () => {
  const cardId = "card-1";
  const [extracted] = await extractGroundedBenefitsV6(
    [{
      sourceUrl: "https://issuer.example/card",
      text: "Get 10% cashback on dining spends, capped at ₹500 per month.",
      contentHash: "a".repeat(64),
    }],
    "benefits-v6",
    cardId,
  );
  const dated = {
    ...extracted,
    effectiveFrom: "2026-01-01",
    effectiveTo: "2026-12-31",
  };
  const datedEnvelope = await buildCanonicalPublicationEnvelope(cardId, dated);
  const proposal = {
    ...dated,
    conditionHash: datedEnvelope.condition_hash,
    benefitId: datedEnvelope.dedupe_key,
    dedupeKey: datedEnvelope.dedupe_key,
  };
  const extraction = {
    request_type: "official_benefit_enrichment",
    parser_version: "benefits-v6",
    proposals: [proposal],
  };
  for (
    const edited of [
      { ...proposal, title: "New marketing title" },
      { ...proposal, description: "New marketing description" },
    ]
  ) {
    let error: unknown;
    try {
      await validateV6ApprovalDecisions(
        [{ action: "edit", edited_benefit: edited }],
        extraction,
        cardId,
      );
    } catch (caught) {
      error = caught;
    }
    assert(
      error instanceof Error &&
        (error as { code?: string }).code === "non_material_edit",
      "display-only edit was accepted",
    );
  }

  for (
    const taxonomyEdit of [
      { ...proposal, category: "points", rate: 12 },
      { ...proposal, valueType: "reward_points", rate: 12 },
    ]
  ) {
    let error: unknown;
    try {
      await validateV6ApprovalDecisions(
        [{ action: "edit", edited_benefit: taxonomyEdit }],
        extraction,
        cardId,
      );
    } catch (caught) {
      error = caught;
    }
    assert(
      error instanceof Error &&
        (error as { code?: string }).code === "immutable_benefit_taxonomy",
      "contradictory taxonomy edit was accepted",
    );
  }

  const clearStart = await validateV6ApprovalDecisions(
    [{ action: "edit", edited_benefit: { ...proposal, effectiveFrom: null } }],
    extraction,
    cardId,
  );
  const clearEnd = await validateV6ApprovalDecisions(
    [{ action: "edit", edited_benefit: { ...proposal, effectiveTo: null } }],
    extraction,
    cardId,
  );
  assert(
    (clearStart[0].canonical_envelope as Record<string, any>).benefit
      .valid_from === null,
    "explicit valid-from clear was discarded",
  );
  assert(
    (clearEnd[0].canonical_envelope as Record<string, any>).benefit
      .valid_until === null,
    "explicit valid-until clear was discarded",
  );

  let invalidRange: unknown;
  try {
    await validateV6ApprovalDecisions(
      [{
        action: "edit",
        edited_benefit: {
          ...proposal,
          effectiveFrom: "2027-01-01",
          effectiveTo: "2026-01-01",
        },
      }],
      extraction,
      cardId,
    );
  } catch (caught) {
    invalidRange = caught;
  }
  assert(invalidRange instanceof Error, "invalid effective range was accepted");

  const material = await validateV6ApprovalDecisions(
    [{
      action: "edit",
      edited_benefit: { ...proposal, title: "Reviewed title", rate: 12 },
    }],
    extraction,
    cardId,
  );
  assert(
    (material[0].edited_benefit as Record<string, unknown>).title ===
      "Reviewed title",
    "material edit discarded its display change",
  );
});

Deno.test("v6 decisions reject duplicate proposal and live identities across every action family", async () => {
  const [proposal] = await extractGroundedBenefitsV6(
    [{
      sourceUrl: "https://issuer.example/card",
      text: "Get 10% cashback on dining spends.",
      contentHash: "a".repeat(64),
    }],
    "benefits-v6",
    "card-1",
  );
  const liveBenefitId = "11111111-1111-4111-8111-111111111111";
  const current = { ...proposal, liveBenefitId };
  const extraction: Record<string, any> = {
    request_type: "official_benefit_enrichment",
    parser_version: "benefits-v6",
    proposals: [proposal],
    crawl_observation: {
      crawl_complete: true,
      observed_at: "2026-08-19T00:00:00.000Z",
      absent_benefit_ids: [proposal.benefitId],
      absent_legacy_benefit_ids: [],
    },
    diff: {
      unchanged: [{ current, proposed: proposal }],
      possibleRemovals: [{
        benefit: current,
        retirementEligible: true,
        retirementReason: "two_complete_observations",
        completeAbsenceObservedAt: [
          "2026-08-12T00:00:00.000Z",
          "2026-08-19T00:00:00.000Z",
        ],
      }],
    },
  };
  const fixtures = [
    [
      { action: "approve", benefit: proposal },
      { action: "approve", benefit: proposal },
    ],
    [
      { action: "retire", benefit_id: liveBenefitId },
      { action: "retire", benefit_id: liveBenefitId },
    ],
    [
      { action: "keep_existing", benefit_id: liveBenefitId },
      { action: "keep_existing", benefit_id: liveBenefitId },
    ],
    [
      { action: "reject", benefit: proposal },
      { action: "reject", benefit: proposal },
    ],
    [
      { action: "approve", benefit: proposal },
      { action: "reject", benefit: proposal },
    ],
  ];
  for (const decisions of fixtures) {
    let error: unknown;
    try {
      await validateV6ApprovalDecisions(decisions, extraction, "card-1");
    } catch (caught) {
      error = caught;
    }
    assert(
      error instanceof Error &&
        (error as { code?: string }).code === "duplicate_benefit_decision",
      "duplicate decision identity was accepted",
    );
  }
});

Deno.test("v6 decision validation bounds one review payload before identity work", async () => {
  let error: unknown;
  try {
    await validateV6ApprovalDecisions(
      Array.from({ length: 65 }, (_, index) => ({
        action: "reject",
        reason: `reason-${index}`,
      })),
      {
        request_type: "official_benefit_enrichment",
        parser_version: "benefits-v6",
        proposals: [],
      },
      "card-1",
    );
  } catch (caught) {
    error = caught;
  }
  assert(
    error instanceof Error &&
      (error as { code?: string }).code === "benefit_decisions_limit",
    "oversized review decisions were not rejected at the boundary",
  );
});

Deno.test("v6 admin identity terms remain explicitly bounded", () => {
  const terms = Array.from({ length: 40 }, (_, index) => `term-${index}`);
  const structured = {
    additional: { source_terms: terms },
    categories: ["fuel"],
    days: ["sunday"],
    mcc_codes: ["5541"],
    merchants: ["example merchant"],
    transaction_types: ["wallet reload"],
  };
  const presented = presentBenefitJob({
    parser_version: "benefits-v6",
    card_benefits_staging: {
      parser_version: "benefits-v6",
      extracted_data: {
        parser_version: "benefits-v6",
        proposals: [{
          benefitId: `card-benefit-v2:card-1:${"a".repeat(64)}`,
          dedupeKey: `card-benefit-v2:card-1:${"a".repeat(64)}`,
          conditionHash: "a".repeat(64),
          offerSubject: "cashback:cashback:dining",
          sourceIdentity: "b".repeat(64),
          title: "Dining cashback",
          description: "Get cashback on dining spends.",
          category: "cashback",
          valueType: "cashback",
          parserVersion: "benefits-v6",
          sourceUrl: "https://issuer.example/card",
          sourceExcerpt: "Get cashback on dining spends.",
          contentHash: "c".repeat(64),
          restrictions: terms,
          confidence: { category: 0.9 },
          evidence: { category: "cashback" },
          warnings: [],
          valueConfig: { restrictions: terms, exclusions: structured },
          exclusions: structured,
        }],
      },
    },
  }) as Record<string, any>;
  const proposal = presented.staging.extracted_data.proposals[0];

  assert(
    proposal.valueConfig.restrictions.length === 32,
    "admin restrictions exceeded the v6 bound",
  );
  assert(
    proposal.exclusions.additional.source_terms.length === 32,
    "admin exclusions exceeded the v6 bound",
  );
  assert(
    proposal.valueConfig.exclusions.mcc_codes.join(",") === "5541" &&
      proposal.valueConfig.exclusions.transaction_types.join(",") ===
        "wallet reload",
    "admin value_config stripped structured exclusion dimensions",
  );
});

Deno.test("admin DTO privacy recursively redacts URL secrets in values and object keys", () => {
  const secret =
    "https://user:password@issuer.example/terms?token=private#fragment";
  const sanitized = sanitizeAdminDto({
    description: `Read ${secret}`,
    partners: [`Partner ${secret}`],
    nested: {
      [`evidence-${secret}`]: {
        list: [`See ${secret}`],
      },
    },
  });
  const serialized = JSON.stringify(sanitized);
  for (const leaked of ["user:", "password", "token=", "#fragment"]) {
    assert(!serialized.includes(leaked), `admin DTO leaked ${leaked}`);
  }
  assert(
    serialized.includes("https://issuer.example/terms"),
    "privacy boundary discarded safe issuer provenance",
  );
});

Deno.test("admin DTO privacy covers encoded, relative, protocol-relative, and bare-host secrets", () => {
  const fixtures = [
    "//issuer.example/path?token=secret#fragment",
    "issuer.example/path?api_key=secret#fragment",
    "issuer.example?token=secret#fragment",
    "user:pass@issuer.example?token=secret#fragment",
    "/terms?session=secret#fragment",
    "https%3A%2F%2Fuser%3Apass%40issuer.example%2Fterms%3Ftoken%3Dsecret%23fragment",
    "https%253A%252F%252Fuser%253Apass%2540issuer.example%252Fterms%253Ftoken%253Dsecret%2523fragment",
    "https%25253A%25252F%25252Fuser%25253Apass%252540issuer.example%25252Fterms%25253Ftoken%25253Dsecret%252523fragment",
    "https://issuer.example/terms&#63;token=secret&#35;fragment",
    "https&amp;#58;//user&amp;#58;pass&amp;#64;issuer.example/terms&amp;#63;token=secret&amp;#35;fragment",
    "https%3A%2F%2Fuser%26%2358%3Bpass%26%2364%3Bissuer.example%2Fterms%26%2363%3Btoken=secret%26%2335%3Bfragment",
    "Save 20% today and keep literal 100%25 notation",
  ];
  const sanitized = sanitizeAdminDto({
    partners: ["BookMyShow", ...fixtures],
    nested: Object.fromEntries(fixtures.map((fixture) => [fixture, fixture])),
  });
  const serialized = JSON.stringify(sanitized);
  for (
    const secret of [
      "token",
      "api_key",
      "session",
      "secret",
      "fragment",
      "user:",
      "pass@",
      "%3F",
      "&#63;",
    ]
  ) {
    assert(
      !serialized.toLowerCase().includes(secret.toLowerCase()),
      `encoded DTO leaked ${secret}`,
    );
  }
  assert(
    serialized.includes("BookMyShow"),
    "ordinary partner label was redacted",
  );
  assert(
    serialized.includes("Save 20% today") &&
      serialized.includes("100%25 notation"),
    "ordinary percent text was corrupted",
  );
});

Deno.test("real benefit presentation strips structured userinfo without treating email prose as credentials", () => {
  const credentials = [
    "alice@issuer.example:443/terms?token=secret#fragment",
    "alice:password@issuer.example:443/terms?token=secret#fragment",
    "alice@127.0.0.1:8080/terms?token=secret",
    "alice:password@127.0.0.1:8080/terms?token=secret",
    "alice@[2001:db8::1]:8443/terms#secret",
    "alice:password@[2001:db8::1]:8443/terms#secret",
    "alice@localhost:8000/terms?token=secret",
    "alice:password@localhost:8000/terms?token=secret",
    "alice@internal/terms?token=secret",
    "alice:password@internal/terms?token=secret",
    "alice%3Apassword%40localhost%3A8000%2Fterms%3Ftoken=secret",
    "alice%253Apassword%2540%255B2001%253Adb8%253A%253A1%255D%253A8443%252Fterms%253Ftoken=secret",
    "alice&amp;#58;password&amp;#64;internal/terms&amp;#63;token=secret",
  ];
  for (const credential of credentials) {
    const presented = presentBenefitJob({
      id: "job-1",
      issuer: `Issuer ${credential}`,
      parser_version: "benefits-v6",
      card_catalog: { id: "card-1", bank: credential, card_name: credential },
    });
    const serialized = JSON.stringify(presented).toLowerCase();
    for (const leaked of ["alice", "password", "token=", "#secret"]) {
      assert(!serialized.includes(leaked), `presented DTO leaked ${leaked}`);
    }
  }

  const keyPresentation = sanitizeAdminDto(
    Object.fromEntries(
      credentials.map((credential) => [credential, credential]),
    ),
  );
  const keyJson = JSON.stringify(keyPresentation).toLowerCase();
  for (const leaked of ["alice", "password", "token=", "#secret"]) {
    assert(!keyJson.includes(leaked), `presented DTO key leaked ${leaked}`);
  }

  const ordinary = sanitizeAdminDto({
    "support@example.com": "Email support@example.com or save 25% today",
  });
  const ordinaryJson = JSON.stringify(ordinary);
  assert(
    ordinaryJson.includes("support@example.com") &&
      ordinaryJson.includes("25%"),
    "ordinary email or percent prose was treated as URL userinfo",
  );
});

Deno.test("admin privacy strips no-tail credentials but preserves ordinary percent and email prose", () => {
  const secrets = [
    "alice:secret@issuer.example",
    "alice@issuer.example:8443",
    "alice:secret@192.0.2.1",
    "alice@[2001:db8::1]",
    "alice@localhost",
    "alice@internal",
    "alice%3Asecret%40issuer.example",
    "alice&#x3a;secret%40%5b2001:db8::1%5d",
  ];
  for (const secret of secrets) {
    const value = sanitizeAdminDto({ [secret]: secret }) as Record<
      string,
      unknown
    >;
    const rendered = JSON.stringify(value);
    assert(!rendered.includes("alice"), `userinfo leaked for ${secret}`);
  }
  for (
    const ordinary of [
      "alice@issuer.example",
      "100% of ₹500 is ₹500",
      "modulo 10%40 remains ordinary text",
      "encoded math 25%2F5 is prose",
    ]
  ) {
    assert(
      sanitizeAdminDto({ value: ordinary }).value === ordinary,
      `ordinary text changed: ${ordinary}`,
    );
  }
  const encodedSecret = "https%3A%2F%2Fissuer.example%2Fcard%3Ftoken%3Dsecret";
  assert(
    !String(sanitizeAdminDto({ value: encodedSecret }).value).includes("token"),
    "encoded URL secret survived structural probing",
  );
});

Deno.test("admin privacy scans punctuation-delimited userinfo in real keys and values", () => {
  const credentials = [
    "[alice:secret@issuer.example]",
    "{alice:secret@issuer.example}",
    "/alice:secret@issuer.example,",
    "(alice:secret@issuer.example).",
    "alice@issuer.example:8443",
    "alice:secret@192.0.2.1;",
    "alice:secret@[2001:db8::1],",
    "alice@localhost/path",
    "alice@internal/path",
    "%255Balice%253Asecret%2540%255B2001%253Adb8%253A%253A1%255D%255D",
  ];
  const payload = sanitizeAdminDto(Object.fromEntries(
    credentials.map((credential) => [credential, credential]),
  ));
  const rendered = JSON.stringify(payload).toLowerCase();
  for (const leaked of ["alice", "secret"]) {
    assert(!rendered.includes(leaked), `punctuation DTO leaked ${leaked}`);
  }
  for (
    const ordinary of [
      "alice@issuer.example",
      "Save 100% of ₹500",
      "modulo 10%40 remains ordinary text",
      "25%2F5 is prose",
    ]
  ) {
    assert(
      sanitizeAdminDto({ value: ordinary }).value === ordinary,
      `candidate scanner changed ordinary text: ${ordinary}`,
    );
  }
});

Deno.test("admin presentation rejects oversized or cyclic input before traversing a displayed subset", () => {
  const oversizedLanes = [
    {
      extracted_data: { proposals: Array.from({ length: 10_000 }, () => ({})) },
    },
    { source_evidence: Array.from({ length: 10_000 }, () => ({})) },
    { benefit_decisions: Array.from({ length: 10_000 }, () => ({})) },
    { source_evidence: Array.from({ length: 33 }, () => ({})) },
    { benefit_decisions: Array.from({ length: 65 }, () => ({})) },
    { extracted_data: { proposals: Array.from({ length: 65 }, () => ({})) } },
  ];
  for (const staging of oversizedLanes) {
    const presented = presentBenefitJob({
      id: "job-oversized",
      status: "staged",
      parser_version: "benefits-v6",
      card_benefits_staging: staging,
    }) as Record<string, unknown>;
    assert(
      presented.presentation_truncated === true &&
        presented.presentation_invalid === true &&
        JSON.stringify(presented).length < 2_000,
      "oversized staging was partially displayed without an invalid marker",
    );
  }

  const cyclic: Record<string, unknown> = { safe: "value" };
  cyclic.self = cyclic;
  const cyclicResult = sanitizeAdminDto(cyclic) as Record<string, unknown>;
  assert(
    cyclicResult.presentation_truncated === true &&
      cyclicResult.presentation_invalid === true,
    "runtime cycle was traversed or silently omitted",
  );
  const largeKeyResult = sanitizeAdminDto({
    ["k".repeat(9_000)]: "value",
  }) as Record<string, unknown>;
  assert(
    largeKeyResult.presentation_truncated === true,
    "oversized object key was silently truncated",
  );
  const byteResult = sanitizeAdminDto({ value: "x".repeat(200_000) }) as Record<
    string,
    unknown
  >;
  assert(
    byteResult.presentation_truncated === true &&
      JSON.stringify(byteResult).length < 2_000,
    "aggregate DTO byte budget was not enforced",
  );
  assert(
    JSON.stringify(sanitizeAdminDto({ partner: "BookMyShow", rate: 5 })) ===
      '{"partner":"BookMyShow","rate":5}',
    "ordinary bounded presentation changed",
  );
});

Deno.test("canonical envelope limits reject Edge-SQL drift boundaries before hashing", async () => {
  const cardId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
  const base = {
    title: "Dining cashback",
    category: "cashback",
    valueType: "cashback",
    offerSubject: "cashback:cashback:dining",
    rate: 10,
    restrictions: ["x".repeat(500)],
    exclusions: [],
    partners: [],
    regions: ["IN"],
  };
  await buildCanonicalPublicationEnvelope(cardId, base);
  await buildCanonicalPublicationEnvelope(cardId, {
    ...base,
    restrictions: Array.from({ length: 64 }, () => "term"),
  });
  const withExtraKeys = (count: number) => ({
    ...base,
    ...Object.fromEntries(
      Array.from({ length: count }, (_, index) => [`extra_${index}`, index]),
    ),
  });
  await buildCanonicalPublicationEnvelope(cardId, withExtraKeys(247));
  const nested = (objectCount: number) => {
    let value: unknown = "leaf";
    for (let index = 0; index < objectCount; index += 1) {
      value = { next: value };
    }
    return value;
  };
  await buildCanonicalPublicationEnvelope(cardId, {
    ...base,
    nested: nested(7),
  });

  for (
    const invalid of [
      { ...base, restrictions: ["x".repeat(501)] },
      { ...base, restrictions: Array.from({ length: 65 }, () => "term") },
      {
        ...base,
        valueConfig: { platform: "x".repeat(48 * 1024) },
      },
      { ...base, padding: "x".repeat(132 * 1024) },
      withExtraKeys(248),
      { ...base, nested: nested(8) },
    ]
  ) {
    let error: unknown;
    try {
      await buildCanonicalPublicationEnvelope(cardId, invalid);
    } catch (caught) {
      error = caught;
    }
    assert(error instanceof Error, "out-of-domain Edge envelope was accepted");
  }
});

Deno.test("canonical publication parity requires nonempty terms and bounded recursive keys", async () => {
  const base = {
    title: "Dining cashback",
    category: "cashback",
    valueType: "cashback",
    offerSubject: "cashback:cashback:dining",
    rate: 10,
    restrictions: [],
    exclusions: [],
    partners: [],
  };
  await buildCanonicalPublicationEnvelope("card-1", {
    ...base,
    valueConfig: { ["k".repeat(500)]: "value" },
  });
  for (
    const invalid of [
      { ...base, title: "" },
      { ...base, valueType: "" },
      Object.fromEntries(
        Object.entries(base).filter(([key]) => key !== "title"),
      ),
      Object.fromEntries(
        Object.entries(base).filter(([key]) => key !== "valueType"),
      ),
      { ...base, valueConfig: { ["k".repeat(501)]: "value" } },
    ]
  ) {
    let error: unknown;
    try {
      await buildCanonicalPublicationEnvelope("card-1", invalid);
    } catch (caught) {
      error = caught;
    }
    assert(error instanceof Error, "Edge accepted a SQL-invalid envelope");
  }
});

Deno.test("every locked proposal is bounded and shaped before subset approval", async () => {
  const proposals = await extractGroundedBenefitsV6(
    [{
      sourceUrl: "https://issuer.example/card",
      text:
        "Get 10% cashback on dining spends. Get 5% cashback on fuel spends.",
      contentHash: "a".repeat(64),
    }],
    "benefits-v6",
    "card-1",
  );
  assert(proposals.length === 2, "multi-proposal fixture did not extract");
  const extraction = (items: unknown[]) => ({
    request_type: "official_benefit_enrichment",
    parser_version: "benefits-v6",
    proposals: items,
  });
  const valid = await validateV6ApprovalDecisions(
    [{ action: "approve", benefit: proposals[0] }],
    extraction(proposals),
    "card-1",
  );
  assert(valid.length === 1, "valid multi-proposal staging was rejected");

  let deep: unknown = "leaf";
  for (let index = 0; index < 9; index += 1) deep = { next: deep };
  const corrupt = [
    { ...proposals[1], unknown: "x".repeat(200_000) },
    { ...proposals[1], unknown: "small" },
    proposals[0],
    { ...proposals[1], valueConfig: { deep } },
    {
      ...proposals[1],
      valueConfig: Object.fromEntries(
        Array.from({ length: 257 }, (_, index) => [`key_${index}`, index]),
      ),
    },
    { ...proposals[1], partners: [1] },
    { ...proposals[1], confidence: { extraction: "high" } },
    { ...proposals[1], sourceUrls: [proposals[1].sourceUrl, 42] },
    { ...proposals[1], description: 4 },
    { ...proposals[1], valueConfig: [] },
    { ...proposals[1], warnings: [false] },
  ];
  for (const item of corrupt) {
    let error: unknown;
    try {
      await validateV6ApprovalDecisions(
        [{ action: "approve", benefit: proposals[0] }],
        extraction([proposals[0], item]),
        "card-1",
      );
    } catch (caught) {
      error = caught;
    }
    assert(error instanceof Error, "corrupt unselected proposal was accepted");
    const presented = presentBenefitJob({
      card_benefits_staging: [{
        extracted_data: extraction([proposals[0], item]),
      }],
    }) as Record<string, unknown>;
    assert(
      presented.presentation_invalid === true,
      "corrupt unselected proposal was presented as approvable",
    );
  }
});

Deno.test("all staged proposals are canonicalized before approval and duplicate targets never reach RPC", async () => {
  const [proposal] = extractGroundedBenefits([{
    sourceUrl: "https://issuer.example/card",
    text: "Get 10% cashback on dining spends.",
    contentHash: "d".repeat(64),
  }], "benefits-v5");
  assert(proposal != null, "v5 duplicate target fixture did not extract");
  const duplicate = { ...proposal, dedupeKey: `${proposal.dedupeKey}:other` };
  const extraction = {
    request_type: "official_benefit_enrichment",
    parser_version: "benefits-v5",
    proposals: [proposal, duplicate],
  };
  let error: unknown;
  try {
    await validateV5ApprovalDecisions(
      [{ action: "approve", benefit: proposal }],
      extraction,
      "card-1",
    );
  } catch (caught) {
    error = caught;
  }
  assert(
    error instanceof Error,
    "duplicate canonical publication target passed",
  );

  let rpcCalls = 0;
  let handlerError: unknown;
  try {
    await handleBenefitAdminAction({
      from() {
        return {
          select() {
            return {
              eq() {
                return {
                  single: async () => ({
                    data: {
                      id: "staging-1",
                      card_id: "card-1",
                      status: "pending",
                      parser_version: "benefits-v5",
                      extracted_data: extraction,
                    },
                    error: null,
                  }),
                };
              },
            };
          },
        };
      },
      async rpc() {
        rpcCalls += 1;
        return { data: [], error: null };
      },
    } as never, {
      action: "benefit-approve",
      job_id: "job-1",
      staging_id: "staging-1",
      decisions: [{ action: "approve", benefit: proposal }],
    }, { id: "admin-1" });
  } catch (caught) {
    handlerError = caught;
  }
  assert(handlerError instanceof Error, "duplicate target did not fail closed");
  assert(rpcCalls === 0, "invalid whole proposal set reached publication RPC");
});

Deno.test("legacy identity migration is server-derived and client change type is rejected", async () => {
  const [proposal] = await extractGroundedBenefitsV6(
    [{
      sourceUrl: "https://issuer.example/card",
      text: "Get 10% cashback on dining spends.",
      contentHash: "b".repeat(64),
    }],
    "benefits-v6",
    "card-1",
  );
  const liveBenefitId = "11111111-1111-4111-8111-111111111111";
  const current = currentBenefitProposal({
    benefit_id: liveBenefitId,
    dedupe_key: "legacy:dining",
    title: proposal.title,
    description: proposal.description,
    benefit_category: "CASHBACK",
    benefit_type: proposal.valueType,
    value_config: proposal.valueConfig,
    exclusions: proposal.exclusions,
    source_url: proposal.sourceUrl,
  });
  assert(current != null, "legacy approval fixture did not reconstruct");
  const diff = diffBenefits([current], [proposal]);
  const staged = {
    request_type: "official_benefit_enrichment",
    parser_version: "benefits-v6",
    proposals: [proposal],
    diff,
  };
  const validated = await validateV6ApprovalDecisions(
    [{ action: "approve", benefit: proposal }],
    staged,
    "card-1",
  );
  assert(
    validated[0].change_type === "identity_migration" &&
      validated[0].existing_benefit_id === liveBenefitId,
    "server did not bind the exact legacy replacement",
  );
  const replay = await validateV6ApprovalDecisions(
    [{ action: "approve", benefit: proposal }],
    staged,
    "card-1",
  );
  assert(
    stableCanonicalJson(replay) === stableCanonicalJson(validated),
    "legacy identity migration replay changed its publication decision",
  );
  for (const change_type of ["identity_migration", "term_change"]) {
    let error: unknown;
    try {
      await validateV6ApprovalDecisions(
        [{ action: "approve", benefit: proposal, change_type }],
        staged,
        "card-1",
      );
    } catch (caught) {
      error = caught;
    }
    assert(error instanceof Error, "client change_type became authoritative");
  }
});

Deno.test("pending v5 rollback approval uses the locked legacy identity migration", async () => {
  const [proposal] = extractGroundedBenefits([{
    sourceUrl: "https://issuer.example/card",
    text: "Get 10% cashback on dining spends.",
    contentHash: "c".repeat(64),
  }], "benefits-v5");
  assert(proposal != null, "v5 rollback approval fixture did not extract");
  const liveBenefitId = "22222222-2222-4222-8222-222222222222";
  const current = currentBenefitProposal({
    benefit_id: liveBenefitId,
    dedupe_key: "legacy:approved:dining",
    title: proposal.title,
    description: proposal.description,
    benefit_category: "CASHBACK",
    benefit_type: proposal.valueType,
    value_config: {
      ...proposal.valueConfig,
      rate: proposal.rate,
      restrictions: proposal.restrictions,
    },
    exclusions: proposal.exclusions,
    source_url: proposal.sourceUrl,
  });
  assert(current != null, "v5 rollback current row did not reconstruct");
  const staged = {
    request_type: "official_benefit_enrichment",
    parser_version: "benefits-v5",
    proposals: [proposal],
    diff: diffBenefits([current], [proposal]),
  };
  const validated = await validateV5ApprovalDecisions(
    [{ action: "approve", benefit: proposal }],
    staged,
    "card-1",
  );
  assert(
    validated[0].change_type === "identity_migration" &&
      validated[0].existing_benefit_id === liveBenefitId,
    "v5 approval did not bind the locked legacy replacement",
  );
  let error: unknown;
  try {
    await validateV5ApprovalDecisions(
      [{ action: "approve", benefit: proposal, change_type: "term_change" }],
      staged,
      "card-1",
    );
  } catch (caught) {
    error = caught;
  }
  assert(error instanceof Error, "v5 client change_type became authoritative");
});

Deno.test("oversized locked proposal sets cannot approve a displayed subset", async () => {
  let error: unknown;
  try {
    await validateV6ApprovalDecisions(
      [{ action: "reject", reason: "not valid" }],
      {
        request_type: "official_benefit_enrichment",
        parser_version: "benefits-v6",
        proposals: Array.from({ length: 10_000 }, () => ({})),
      },
      "card-1",
    );
  } catch (caught) {
    error = caught;
  }
  assert(
    error instanceof Error &&
      (error as { code?: string }).code ===
        "invalid_staged_presentation_bounds",
    "approval accepted an oversized raw proposal set hidden by presentation bounds",
  );
});

Deno.test("retirement proof is recomputed from locked complete absence evidence", () => {
  const base: Record<string, any> = {
    crawl_observation: {
      crawl_complete: true,
      observed_at: "2026-08-19T00:00:00.000Z",
      absent_benefit_ids: ["card-benefit-v2:card-a:cashback"],
      absent_legacy_benefit_ids: ["legacy:cashback"],
    },
    diff: {
      possibleRemovals: [{
        benefit: {
          liveBenefitId: "11111111-1111-4111-8111-111111111111",
          benefitId: "card-benefit-v2:card-a:cashback",
          dedupeKey: "legacy:cashback",
        },
        retirementEligible: true,
        retirementReason: "two_complete_observations",
        completeAbsenceObservedAt: [
          "2026-08-12T00:00:00.000Z",
          "2026-08-19T00:00:00.000Z",
        ],
      }],
    },
  };
  assert(
    validateRetirementDecisionEvidence(
      base,
      "11111111-1111-4111-8111-111111111111",
    ).reason ===
      "two_complete_observations",
    "exact corroborated retirement was rejected",
  );
  const invalid = [
    {
      label: "incomplete",
      patch: {
        crawl_observation: { ...base.crawl_observation, crawl_complete: false },
      },
    },
    {
      label: "absent mismatch",
      patch: {
        crawl_observation: {
          ...base.crawl_observation,
          absent_benefit_ids: ["other"],
          absent_legacy_benefit_ids: [],
        },
      },
    },
    {
      label: "one observation",
      patch: {
        diff: {
          possibleRemovals: [{
            ...base.diff.possibleRemovals[0],
            completeAbsenceObservedAt: ["2026-08-19T00:00:00.000Z"],
          }],
        },
      },
    },
    {
      label: "less than seven days",
      patch: {
        diff: {
          possibleRemovals: [{
            ...base.diff.possibleRemovals[0],
            completeAbsenceObservedAt: [
              "2026-08-13T00:00:00.000Z",
              "2026-08-19T00:00:00.000Z",
            ],
          }],
        },
      },
    },
    {
      label: "current observation missing from history",
      patch: {
        diff: {
          possibleRemovals: [{
            ...base.diff.possibleRemovals[0],
            completeAbsenceObservedAt: [
              "2026-08-11T00:00:00.000Z",
              "2026-08-18T00:00:00.000Z",
            ],
          }],
        },
      },
    },
  ];
  for (const fixture of invalid) {
    let error: unknown;
    try {
      validateRetirementDecisionEvidence(
        { ...base, ...fixture.patch },
        "11111111-1111-4111-8111-111111111111",
      );
    } catch (caught) {
      error = caught;
    }
    assert(error instanceof Error, `${fixture.label} retirement was accepted`);
  }
  const explicit = structuredClone(base);
  explicit.diff.possibleRemovals[0].benefit.effectiveTo = "2026-08-18";
  explicit.diff.possibleRemovals[0].retirementReason = "explicit_past_end_date";
  explicit.diff.possibleRemovals[0].completeAbsenceObservedAt = [
    "2026-08-19T00:00:00.000Z",
  ];
  assert(
    validateRetirementDecisionEvidence(
      explicit,
      "11111111-1111-4111-8111-111111111111",
    ).reason ===
      "explicit_past_end_date",
    "official past end date was rejected",
  );
});

Deno.test("v6 approval recomputes staged identity for the locked card", async () => {
  const [foreignCardProposal] = await extractGroundedBenefitsV6(
    [{
      sourceUrl: "https://issuer.example/card",
      text: "Get 10% cashback on dining spends.",
      contentHash: "a".repeat(64),
    }],
    "benefits-v6",
    "card-b",
  );
  let error: unknown;
  try {
    await validateV6ApprovalDecisions(
      [{ action: "approve", benefit: foreignCardProposal }],
      {
        request_type: "official_benefit_enrichment",
        parser_version: "benefits-v6",
        proposals: [foreignCardProposal],
      },
      "card-a",
    );
  } catch (caught) {
    error = caught;
  }
  assert(
    error instanceof Error &&
      (error as { code?: string }).code === "invalid_staged_benefit_identity",
    "foreign-card staged identity was accepted",
  );
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
  let pilotParserVersion: unknown;
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
      pilotParserVersion = args._parser_version;
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
    const stalePilot = await handle(
      request({
        action: "benefit-start-pilot",
        parser_version: "benefits-v4",
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
    assert(stalePilot.status === 400, "stale parser started a pilot");
    assert(startedPilot.status === 200, "valid pilot was not initialized");
    assert(
      pilotParserVersion === "benefits-v5",
      "admin pilot defaulted to the stale parser lane",
    );
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
                      valueConfig: {
                        category: "movie_tickets",
                        discount_type: "percent",
                        discount_percent: 25,
                        max_discount_per_transaction: 100,
                        internal_note: "must not escape",
                      },
                      partners: ["BookMyShow"],
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
    assert(
      serialized.includes("max_discount_per_transaction") &&
        serialized.includes("BookMyShow"),
      "movie value config or partners were omitted from review",
    );
    assert(
      !serialized.includes("internal_note"),
      "unknown value-config fields escaped the review DTO",
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
