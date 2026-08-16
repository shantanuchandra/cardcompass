import {
  buildJobKey,
  evaluatePilotGate,
  failureDisposition,
  findReusableStaging,
  runSequentially,
  selectPilotCandidates,
  simulateLeaseClaim,
} from "./batch_policy.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

Deno.test("a lease claim recovers expired work and claims at most five rows from one issuer", () => {
  const now = new Date("2026-08-17T12:00:00.000Z");
  const jobs = [
    ...Array.from({ length: 6 }, (_, index) => ({
      id: `axis-${index}`,
      issuer: "Axis Bank",
      cardName: `Card ${index}`,
      status: index === 0 ? "processing" : "queued",
      leaseExpiresAt: index === 0 ? "2026-08-17T11:59:00.000Z" : null,
      nextRetryAt: null,
      runMode: "scheduled" as const,
    })),
    {
      id: "hdfc-1",
      issuer: "HDFC Bank",
      cardName: "Card 1",
      status: "queued",
      leaseExpiresAt: null,
      nextRetryAt: null,
      runMode: "scheduled" as const,
    },
  ];

  const result = simulateLeaseClaim(jobs, now, "scheduled", 99);
  assert(
    result.recoveredIds.join(",") === "axis-0",
    "expired lease was not recovered",
  );
  assert(result.claimed.length === 5, "claim exceeded the five-job maximum");
  assert(
    result.claimed.every((job) => job.issuer === "Axis Bank"),
    "claim mixed issuers",
  );
});

Deno.test("batch work is awaited sequentially", async () => {
  let active = 0;
  let maximumActive = 0;
  const order: string[] = [];
  const results = await runSequentially(
    ["one", "two", "three"],
    async (value) => {
      active += 1;
      maximumActive = Math.max(maximumActive, active);
      order.push(`start:${value}`);
      await Promise.resolve();
      order.push(`end:${value}`);
      active -= 1;
      return value.length;
    },
  );

  assert(maximumActive === 1, "jobs overlapped");
  assert(
    order.join(",") ===
      "start:one,end:one,start:two,end:two,start:three,end:three",
    "job order changed",
  );
  assert(results.join(",") === "3,3,5", "results were not retained");
});

Deno.test("job identity is stable for the card, canonical URL hash, and parser", () => {
  const first = buildJobKey("card-a", "a".repeat(64), "benefits-v1");
  const repeated = buildJobKey("card-a", "a".repeat(64), "benefits-v1");
  const nextParser = buildJobKey("card-a", "a".repeat(64), "benefits-v2");
  assert(
    first === "card-a:" + "a".repeat(64) + ":benefits-v1",
    "job key is not canonical",
  );
  assert(first === repeated, "same inputs produced different keys");
  assert(first !== nextParser, "parser version was omitted from identity");
});

Deno.test("same content and parser reuse an existing staging row", () => {
  const rows = [{
    id: "stage-1",
    cardId: "card-a",
    sourceUrl: "https://example.test/card",
    requestType: "official_benefit_enrichment",
    parserVersion: "benefits-v1",
    contentHash: "content-a",
  }];
  assert(
    findReusableStaging(rows, {
      cardId: "card-a",
      sourceUrl: "https://example.test/card",
      parserVersion: "benefits-v1",
      contentHash: "content-a",
    })?.id === "stage-1",
    "matching staging was not reused",
  );
  assert(
    findReusableStaging(rows, {
      cardId: "card-a",
      sourceUrl: "https://example.test/card",
      parserVersion: "benefits-v2",
      contentHash: "content-a",
    }) === undefined,
    "different parser reused stale staging",
  );
});

Deno.test("retry policy exposes 15 minute, one hour, and four hour delays and reviews the third failure", () => {
  const now = new Date("2026-08-17T12:00:00.000Z");
  const first = failureDisposition(1, now);
  const second = failureDisposition(2, now);
  const third = failureDisposition(3, now);
  assert(
    first.status === "failed" &&
      first.nextRetryAt === "2026-08-17T12:15:00.000Z",
    "first retry is not 15 minutes",
  );
  assert(
    second.status === "failed" &&
      second.nextRetryAt === "2026-08-17T13:00:00.000Z",
    "second retry is not one hour",
  );
  assert(
    third.status === "review_required" && third.nextRetryAt === null,
    "third failure was not sent to review",
  );
  assert(
    first.retryScheduleMinutes.join(",") === "15,60,240",
    "retry schedule does not retain the four-hour tier",
  );
});

Deno.test("pilot selector chooses five profiles across at least three issuers", () => {
  const selected = selectPilotCandidates([
    {
      id: "straight",
      issuer: "Axis",
      active: true,
      approvedUrl: true,
      profile: "straightforward",
    },
    {
      id: "heavy",
      issuer: "HDFC",
      active: true,
      approvedUrl: true,
      profile: "redirect_or_js",
    },
    {
      id: "terms",
      issuer: "ICICI",
      active: true,
      approvedUrl: true,
      profile: "terms_linked",
    },
    {
      id: "invalid",
      issuer: "Axis",
      active: true,
      approvedUrl: false,
      profile: "known_invalid",
    },
    {
      id: "extra",
      issuer: "HDFC",
      active: true,
      approvedUrl: true,
      profile: "additional_valid",
    },
    {
      id: "sixth",
      issuer: "Kotak",
      active: true,
      approvedUrl: true,
      profile: "additional_valid",
    },
  ]);
  assert(selected.length === 5, "pilot did not select exactly five rows");
  assert(
    selected.map((candidate) => candidate.profile).join(",") ===
      "straightforward,redirect_or_js,terms_linked,known_invalid,additional_valid",
    "pilot profile coverage changed",
  );
  assert(
    new Set(selected.map((candidate) => candidate.issuer)).size >= 3,
    "pilot has fewer than three issuers",
  );
  assert(
    selected.every((candidate) => candidate.run_mode === "pilot"),
    "selected rows were not marked for the pilot lane",
  );
});

Deno.test("scheduled rollout stays blocked until the exact safe five-job pilot passes", () => {
  const base = Array.from({ length: 5 }, (_, index) => ({
    id: `pilot-${index}`,
    runMode: "pilot" as const,
    status: index === 4 ? "quarantined" : "staged",
    quarantineReason: index === 4 ? "identity_mismatch" : null,
    unsafeMutationCount: 0,
    idempotencyPassed: true,
    evidencePassed: true,
    rawBodyStored: false,
  }));
  assert(
    evaluatePilotGate(base).status === "passed",
    "safe terminal pilot did not pass",
  );
  assert(
    evaluatePilotGate(base.slice(0, 4)).status === "running",
    "partial pilot was not blocked",
  );
  assert(
    evaluatePilotGate(
      base.map((job, index) =>
        index === 0 ? { ...job, status: "processing" } : job
      ),
    ).status === "running",
    "active five-job pilot was not reported as running",
  );
  assert(
    evaluatePilotGate(
      base.map((job, index) =>
        index === 0 ? { ...job, unsafeMutationCount: 1 } : job
      ),
    ).status === "blocked",
    "unsafe mutation did not block rollout",
  );
  assert(
    evaluatePilotGate(
      base.map((job, index) =>
        index === 1 ? { ...job, idempotencyPassed: false } : job
      ),
    ).status === "blocked",
    "failed idempotency did not block rollout",
  );
  assert(
    evaluatePilotGate(
      base.map((job, index) =>
        index === 4 ? { ...job, quarantineReason: null } : job
      ),
    ).status === "blocked",
    "unjustified quarantine did not block rollout",
  );
});
