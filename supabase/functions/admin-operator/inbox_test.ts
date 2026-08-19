import { assertEquals, assertRejects } from "@std/assert";
import {
  handleInboxList,
  type InboxItem,
  loadBenefitInbox,
  loadIdentityInbox,
  rankInboxItems,
} from "./inbox.ts";
import { type AdminActionContext, AdminHttpError } from "./types.ts";
import { actionHandlers } from "./router.ts";

const NOW = Date.parse("2026-08-19T12:00:00Z");

function item(id: string, severity: InboxItem["severity"], age: number): InboxItem {
  return {
    id,
    type: "card_identity_review",
    severity,
    title: "Review card identity proposal",
    explanation: "A pending card identity proposal needs review.",
    source_status: "pending",
    age_seconds: age,
    destination: { section: "cardData", lane: "identity", target_id: id },
  };
}

function queryResult(rows: unknown[], error: { message: string } | null = null) {
  const query = {
    select: () => query,
    eq: () => query,
    neq: () => query,
    in: () => query,
    order: () => query,
    range: () => Promise.resolve({ data: rows, error }),
  };
  return query;
}

function context(options: {
  identity?: unknown[];
  benefit?: unknown[];
  identityError?: { message: string } | null;
  benefitError?: { message: string } | null;
} = {}): AdminActionContext {
  return {
    actor: { id: "admin" },
    requestId: null,
    db: {
      from(table: string) {
        return queryResult(
          table === "card_catalog_review_queue"
            ? options.identity ?? []
            : options.benefit ?? [],
          table === "card_catalog_review_queue"
            ? options.identityError ?? null
            : options.benefitError ?? null,
        ) as never;
      },
      rpc: () => Promise.resolve({ data: null, error: null }),
    },
  };
}

Deno.test("inbox ranks severity, then oldest age, then stable id without mutating input", () => {
  const input = [
    item("pending-benefit", "normal", 100),
    item("failed-job", "high", 20),
    item("blocked", "critical", 5),
    item("b", "high", 60),
    item("a", "high", 60),
    item("c", "high", 120),
  ];

  assertEquals(rankInboxItems(input).map((entry) => entry.id), [
    "blocked",
    "c",
    "a",
    "b",
    "failed-job",
    "pending-benefit",
  ]);
  assertEquals(input.map((entry) => entry.id), [
    "pending-benefit",
    "failed-job",
    "blocked",
    "b",
    "a",
    "c",
  ]);
});

Deno.test("identity adapter returns exact safe pending-review DTOs and safe ages", async () => {
  const output = await loadIdentityInbox(context({
    identity: [{
      id: "identity-1",
      status: "pending",
      created_at: "2026-08-19T11:59:00Z",
      source_evidence: { raw_body: "secret" },
      proposed_fields: { card_name: "must not leak" },
    }, {
      id: "identity-2",
      status: "pending",
      created_at: "malformed",
      provider_response: "secret",
    }],
  }), 100, NOW);

  assertEquals(output, [{
    id: "card-identity:identity-1",
    type: "card_identity_review",
    severity: "normal",
    title: "Review card identity proposal",
    explanation: "A pending card identity proposal needs review.",
    source_status: "pending",
    age_seconds: 60,
    destination: {
      section: "cardData",
      lane: "identity",
      target_id: "identity-1",
    },
  }, {
    id: "card-identity:identity-2",
    type: "card_identity_review",
    severity: "normal",
    title: "Review card identity proposal",
    explanation: "A pending card identity proposal needs review.",
    source_status: "pending",
    age_seconds: 0,
    destination: {
      section: "cardData",
      lane: "identity",
      target_id: "identity-2",
    },
  }]);
});

Deno.test("benefit adapter maps actionable statuses to exact safe DTOs", async () => {
  const output = await loadBenefitInbox(context({ benefit: [
    { id: "review", status: "review_required", created_at: "2026-08-19T11:58:00Z", raw_body: "secret" },
    { id: "failed", status: "failed", created_at: "2026-08-19T11:57:00Z" },
    { id: "quarantined", status: "quarantined", created_at: "2026-08-19T11:56:00Z" },
    { id: "staged", status: "staged", created_at: "2026-08-19T11:55:00Z" },
  ] }), 100, NOW);

  assertEquals(output.map(({ id, source_status, severity, title, explanation }) => ({
    id, source_status, severity, title, explanation,
  })), [{
    id: "benefit-enrichment:review", source_status: "review_required", severity: "high",
    title: "Review benefit enrichment", explanation: "A benefit proposal needs operator review.",
  }, {
    id: "benefit-enrichment:failed", source_status: "failed", severity: "high",
    title: "Recover failed benefit enrichment", explanation: "Benefit enrichment failed and needs recovery.",
  }, {
    id: "benefit-enrichment:quarantined", source_status: "quarantined", severity: "high",
    title: "Review quarantined benefit enrichment", explanation: "A quarantined benefit job needs operator review.",
  }, {
    id: "benefit-enrichment:staged", source_status: "staged", severity: "normal",
    title: "Review staged benefits", explanation: "A staged benefit proposal is ready for review.",
  }]);
  assertEquals(output.every((entry) =>
    entry.destination.section === "cardData" &&
    entry.destination.lane === "benefit" &&
    Object.keys(entry).length === 8
  ), true);
});

Deno.test("inbox caps the merged ranked result at 100 items", async () => {
  const identity = Array.from({ length: 100 }, (_, index) => ({
    id: `identity-${index.toString().padStart(3, "0")}`,
    status: "pending",
    created_at: "2026-08-19T11:59:00Z",
  }));
  const benefit = Array.from({ length: 100 }, (_, index) => ({
    id: `benefit-${index.toString().padStart(3, "0")}`,
    status: "failed",
    created_at: "2026-08-19T11:59:00Z",
  }));
  const output = await handleInboxList({ action: "inbox-list" }, context({ identity, benefit }));

  assertEquals(output.items.length, 100);
  assertEquals(output.items.every((entry) => entry.severity === "high"), true);
  assertEquals(output.partial_failures, []);
});

Deno.test("inbox isolates each failed source and reports stable public names", async () => {
  const identityFailure = await handleInboxList({ action: "inbox-list" }, context({
    identityError: { message: "password=secret" },
    benefit: [{ id: "benefit", status: "staged", created_at: "bad" }],
  }));
  assertEquals(identityFailure.items.length, 1);
  assertEquals(identityFailure.partial_failures, ["card_identity"]);

  const benefitFailure = await handleInboxList({ action: "inbox-list" }, context({
    identity: [{ id: "identity", status: "pending", created_at: "bad" }],
    benefitError: { message: "raw query detail" },
  }));
  assertEquals(benefitFailure.items.length, 1);
  assertEquals(benefitFailure.partial_failures, ["benefit_enrichment"]);

  const both = await handleInboxList({ action: "inbox-list" }, context({
    identityError: { message: "identity secret" },
    benefitError: { message: "benefit secret" },
  }));
  assertEquals(both.items, []);
  assertEquals(both.partial_failures, ["card_identity", "benefit_enrichment"]);
  assertEquals(JSON.stringify(both).includes("secret"), false);
});

Deno.test("inbox rejects non-allowlisted input and router registration is immutable and prototype-safe", async () => {
  await assertRejects(
    () => handleInboxList({ action: "inbox-list", table: "users" }, context()),
    AdminHttpError,
    "invalid_request",
  );
  assertEquals(Object.isFrozen(actionHandlers), true);
  assertEquals(Object.hasOwn(actionHandlers, "inbox-list"), true);
  assertEquals(Object.hasOwn(actionHandlers, "constructor"), false);
  assertEquals(Object.getPrototypeOf(actionHandlers), null);
});
