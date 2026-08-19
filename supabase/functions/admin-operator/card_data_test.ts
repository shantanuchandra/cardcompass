import { assertEquals, assertRejects } from "@std/assert";
import {
  cardDataActionHandlers,
  handleCardReviewAction,
  handleCardReviewList,
} from "./card_data.ts";
import { type AdminActionContext, AdminHttpError } from "./types.ts";

const IDENTITY_ID = "11111111-1111-4111-8111-111111111111";
const STAGING_ID = "22222222-2222-4222-8222-222222222222";
const MERGE_ID = "33333333-3333-4333-8333-333333333333";
const REQUEST_ID = "44444444-4444-4444-8444-444444444444";
const UPDATED_AT = "2026-08-19T09:00:00Z";

type QueryCall = { method: string; args: unknown[] };

function createReadQueryForRows(
  rows: unknown[],
  calls: QueryCall[],
  error: { message: string } | null = null,
) {
  const query = {
    select(...args: unknown[]) {
      calls.push({ method: "select", args });
      return query;
    },
    eq(...args: unknown[]) {
      calls.push({ method: "eq", args });
      return query;
    },
    neq(...args: unknown[]) {
      calls.push({ method: "neq", args });
      return query;
    },
    in(...args: unknown[]) {
      calls.push({ method: "in", args });
      return query;
    },
    order(...args: unknown[]) {
      calls.push({ method: "order", args });
      return query;
    },
    range(...args: unknown[]) {
      calls.push({ method: "range", args });
      return Promise.resolve({ data: rows, error });
    },
  };
  return query;
}

function fakeContext(options: {
  rows?: unknown[];
  readError?: { message: string } | null;
  rpcData?: unknown;
  rpcError?: { message: string } | null;
} = {}) {
  const calls: QueryCall[] = [];
  const rpcCalls: Array<{ name: string; args: Record<string, unknown> }> = [];
  const query = createReadQueryForRows(
    options.rows ?? [],
    calls,
    options.readError ?? null,
  );
  const db = {
    from(table: string) {
      calls.push({ method: "from", args: [table] });
      return query;
    },
    rpc(name: string, args: Record<string, unknown>) {
      rpcCalls.push({ name, args });
      return Promise.resolve({
        data: options.rpcData ?? {},
        error: options.rpcError ?? null,
      });
    },
  };
  return {
    context: {
      actor: { id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa" },
      requestId: null,
      db: db as AdminActionContext["db"],
    },
    calls,
    rpcCalls,
  };
}

Deno.test("identity list uses a bounded queue query and excludes raw evidence", async () => {
  const rows = [{
    id: IDENTITY_ID,
    status: "pending",
    proposed_fields: {
      card_name: "Issuer Premier",
      issuer: "Issuer",
      network: "Visa",
      official_url: "https://issuer.example/card",
      raw_html: "excluded",
    },
    source_evidence: {
      official_url: "https://issuer.example/card",
      source_excerpt: "x".repeat(700),
      raw_body: "excluded",
      authorization: "excluded",
    },
    existing_candidates: [{ id: MERGE_ID, card_name: "Premier", secret: "x" }],
    validation_warnings: [{ code: "ambiguous_match", raw: "excluded" }],
    confidence: 0.81,
    review_reason: "possible duplicate",
    created_at: "2026-08-18T09:00:00Z",
    updated_at: UPDATED_AT,
    reviewed_at: null,
    card_discovery_jobs: {
      id: STAGING_ID,
      issuer: "Issuer",
      proposed_product: "Premier",
      evidence: { source_url: "javascript:alert(1)", raw_body: "excluded" },
      status: "review_required",
      attempt_count: 2,
      failure_category: "ambiguous_identity",
      resolved_card_id: null,
      created_at: "2026-08-18T09:00:00Z",
      updated_at: UPDATED_AT,
      provider_response: "excluded",
    },
  }, { id: "extra-row" }];
  const fake = fakeContext({ rows });

  const output = await handleCardReviewList(
    { lane: "identity", page: -20, limit: 500, status: "pending" },
    fake.context,
  );

  assertEquals(output.page, 1);
  assertEquals(output.limit, 50);
  assertEquals(output.has_more, false);
  assertEquals(output.items.length, 2);
  assertEquals(output.items[0].source_evidence, {
    official_url: "https://issuer.example/card",
    source_excerpt: "x".repeat(500),
  });
  assertEquals(output.items[0].proposed_fields, {
    card_name: "Issuer Premier",
    issuer: "Issuer",
    network: "Visa",
    official_url: "https://issuer.example/card",
  });
  assertEquals(output.items[0].existing_candidates, [{
    id: MERGE_ID,
    card_name: "Premier",
  }]);
  assertEquals(output.items[0].discovery_job.evidence, { source_url: null });
  assertEquals(fake.calls.at(-1), { method: "range", args: [0, 50] });
});

Deno.test("identity pagination clamps the page and detects one lookahead row", async () => {
  const fake = fakeContext({
    rows: Array.from({ length: 3 }, () => ({ id: IDENTITY_ID })),
  });
  const output = await handleCardReviewList(
    { lane: "identity", page: 20_000, limit: 2 },
    fake.context,
  );
  assertEquals({
    page: output.page,
    limit: output.limit,
    has_more: output.has_more,
  }, {
    page: 10_000,
    limit: 2,
    has_more: true,
  });
  assertEquals(output.items.length, 2);
  assertEquals(fake.calls.at(-1), { method: "range", args: [19_998, 20_000] });
});

Deno.test("benefit list reuses the locked presenter and bounds unsafe URLs and arrays", async () => {
  const fake = fakeContext({
    rows: [{
      id: IDENTITY_ID,
      card_id: MERGE_ID,
      canonical_url: "https://issuer.example/card",
      parser_version: "benefit-v2",
      status: "review_required",
      updated_at: UPDATED_AT,
      result_summary: { raw_body_stored: false, provider_response: "excluded" },
      card_catalog: {
        id: MERGE_ID,
        bank: "Issuer",
        card_name: "Premier",
        secret: "x",
      },
      card_benefits_staging: {
        id: STAGING_ID,
        source_url: "file:///etc/passwd",
        source_evidence: Array.from({ length: 55 }, (_, index) => ({
          dedupe_key: `benefit-${index}`,
          source_url: index === 0
            ? "https://issuer.example/benefits"
            : "data:text/plain,secret",
          source_excerpt: "e".repeat(700),
          raw_body: "excluded",
        })),
        extracted_data: { raw_body: "excluded", proposals: [] },
      },
    }],
  });

  const output = await handleCardReviewList(
    { lane: "benefit", page: 1, limit: 25, status: "review_required" },
    fake.context,
  );

  assertEquals(output.items[0].staging.source_url, null);
  assertEquals(output.items[0].staging.source_evidence.length, 50);
  assertEquals(
    output.items[0].staging.source_evidence[0].source_url,
    "https://issuer.example/benefits",
  );
  assertEquals(output.items[0].staging.source_evidence[1].source_url, null);
  assertEquals(
    output.items[0].staging.source_evidence[0].source_excerpt,
    "e".repeat(500),
  );
  assertEquals(output.items[0].result_summary.provider_response, undefined);
  assertEquals(
    fake.calls.some((call) =>
      call.method === "neq" && call.args[0] === "parser_version"
    ),
    true,
  );
  assertEquals(fake.calls.at(-1), { method: "range", args: [0, 25] });
});

Deno.test("list rejects unsupported keys, lane, status, and database errors safely", async () => {
  const cases = [
    { lane: "customer" },
    { lane: "identity", status: { arbitrary: true } },
    { lane: "identity", status: "queued" },
    { lane: "benefit", status: "pending" },
    { lane: "identity", secret: "query-anything" },
  ];
  for (const body of cases) {
    await assertRejects(
      () => handleCardReviewList(body, fakeContext().context),
      AdminHttpError,
      "invalid_request",
    );
  }
  await assertRejects(
    () =>
      handleCardReviewList(
        { lane: "identity" },
        fakeContext({ readError: { message: "password leaked in SQL" } })
          .context,
      ),
    AdminHttpError,
    "request_failed",
  );
});

const validCommon = {
  target_id: IDENTITY_ID,
  request_id: REQUEST_ID,
  observed_updated_at: UPDATED_AT,
};

Deno.test("identity mutations enforce exact operation payloads", async () => {
  const valid = [
    { operation: "approve" },
    { operation: "edit_approve", proposed_fields: { card_name: "Premier" } },
    { operation: "merge", merge_card_id: MERGE_ID },
    { operation: "reject", reason: "not a product page" },
    { operation: "retry" },
  ];
  for (const input of valid) {
    const fake = fakeContext({ rpcData: { resulting_status: "approved" } });
    await handleCardReviewAction(
      { lane: "identity", ...validCommon, ...input },
      fake.context,
    );
    assertEquals(fake.rpcCalls.length, 1);
  }

  const invalid = [
    { operation: "quarantine", reason: "bad" },
    { operation: "approve", decisions: [] },
    { operation: "edit_approve", proposed_fields: [] },
    {
      operation: "edit_approve",
      proposed_fields: { card_name: "Premier", raw_body: "secret" },
    },
    {
      operation: "edit_approve",
      proposed_fields: { official_url: "file:///etc/passwd" },
    },
    { operation: "merge", merge_card_id: "not-a-uuid" },
    { operation: "reject", reason: " " },
    { operation: "retry", proposed_fields: {} },
  ];
  for (const input of invalid) {
    await assertRejects(
      () =>
        handleCardReviewAction(
          { lane: "identity", ...validCommon, ...input },
          fakeContext().context,
        ),
      AdminHttpError,
      "invalid_request",
    );
  }
});

Deno.test("benefit decisions enforce operation-specific actions and reject reasons", async () => {
  const valid = [
    {
      operation: "approve",
      staging_id: STAGING_ID,
      decisions: [{ action: "approve" }, { action: "keep_existing" }],
    },
    {
      operation: "edit_approve",
      staging_id: STAGING_ID,
      decisions: [{ action: "edit" }],
    },
    {
      operation: "reject",
      staging_id: STAGING_ID,
      reason: "unsupported claim",
      decisions: [{ action: "reject" }],
    },
    { operation: "retry" },
    { operation: "quarantine", reason: "malformed proposal" },
    { operation: "unquarantine" },
  ];
  for (const input of valid) {
    const fake = fakeContext();
    await handleCardReviewAction(
      { lane: "benefit", ...validCommon, ...input },
      fake.context,
    );
    assertEquals(fake.rpcCalls.length, 1);
    if (input.operation === "reject") {
      assertEquals(
        (fake.rpcCalls[0].args._payload as { decisions: unknown[] }).decisions,
        [
          { action: "reject", reason: "unsupported claim" },
        ],
      );
    }
  }

  const invalid = [
    { operation: "merge", merge_card_id: MERGE_ID },
    {
      operation: "approve",
      staging_id: STAGING_ID,
      decisions: [{ action: "edit" }],
    },
    {
      operation: "approve",
      staging_id: STAGING_ID,
      decisions: [{
        action: "approve",
        benefit: { title: "Dining", raw_body: "secret" },
      }],
    },
    {
      operation: "approve",
      staging_id: STAGING_ID,
      decisions: [{
        action: "approve",
        benefit: { title: "Dining", source_url: "javascript:alert(1)" },
      }],
    },
    {
      operation: "edit_approve",
      staging_id: STAGING_ID,
      decisions: [{ action: "approve" }],
    },
    {
      operation: "reject",
      staging_id: STAGING_ID,
      reason: "valid reason",
      decisions: [{ action: "keep_existing" }],
    },
    {
      operation: "reject",
      staging_id: STAGING_ID,
      decisions: [{ action: "reject" }],
    },
    { operation: "retry", staging_id: STAGING_ID },
    { operation: "quarantine", reason: "x" },
  ];
  for (const input of invalid) {
    await assertRejects(
      () =>
        handleCardReviewAction(
          { lane: "benefit", ...validCommon, ...input },
          fakeContext().context,
        ),
      AdminHttpError,
      "invalid_request",
    );
  }
});

Deno.test("mutation validates UUIDs, timestamps, keys, and 32 KiB UTF-8 payloads", async () => {
  const invalid = [
    { ...validCommon, request_id: undefined },
    { ...validCommon, request_id: "not-uuid" },
    { ...validCommon, observed_updated_at: "yesterday" },
    { ...validCommon, extra: "arbitrary" },
    {
      ...validCommon,
      operation: "edit_approve",
      proposed_fields: { card_name: "é".repeat(17_000) },
    },
  ];
  for (const body of invalid) {
    await assertRejects(
      () =>
        handleCardReviewAction({
          lane: "identity",
          operation: "approve",
          ...body,
        }, fakeContext().context),
      AdminHttpError,
      "invalid_request",
    );
  }
});

Deno.test("mutation calls only the audited RPC with a sanitized payload", async () => {
  const fake = fakeContext({ rpcData: { resulting_status: "merged" } });
  const result = await handleCardReviewAction({
    lane: "identity",
    operation: "merge",
    ...validCommon,
    merge_card_id: MERGE_ID,
  }, fake.context);

  assertEquals(result, { result: { resulting_status: "merged" } });
  assertEquals(fake.rpcCalls, [{
    name: "admin_card_data_action",
    args: {
      _actor_id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
      _request_id: REQUEST_ID,
      _lane: "identity",
      _operation: "merge",
      _target_id: IDENTITY_ID,
      _staging_id: null,
      _payload: { merge_card_id: MERGE_ID },
      _reason: null,
      _observed_updated_at: UPDATED_AT,
    },
  }]);
});

Deno.test("mutation maps database failures to stable codes without leaking details", async () => {
  const cases: Array<[string, string, number]> = [
    ["invalid_request internal detail", "invalid_request", 400],
    ["reason_required", "reason_required", 400],
    ["not_found relation detail", "not_found", 404],
    ["state_conflict row detail", "state_conflict", 409],
    ["request_id_collision receipt detail", "state_conflict", 409],
    ["database password secret", "request_failed", 500],
  ];
  for (const [message, code, status] of cases) {
    const error = await assertRejects(
      () =>
        handleCardReviewAction(
          { lane: "identity", operation: "retry", ...validCommon },
          fakeContext({ rpcError: { message } }).context,
        ),
      AdminHttpError,
      code,
    );
    assertEquals((error as AdminHttpError).status, status);
  }
});

Deno.test("card data registry is frozen and owns only the two card actions", () => {
  assertEquals(Object.isFrozen(cardDataActionHandlers), true);
  assertEquals(Object.keys(cardDataActionHandlers).sort(), [
    "card-review-action",
    "card-review-list",
  ]);
  assertEquals(Object.hasOwn(cardDataActionHandlers, "constructor"), false);
});
