import {
  buildJobKey,
  enqueueBenefitEnrichmentJob,
  evaluatePilotGate,
  failureDisposition,
  findReusableStaging,
  runSequentially,
  secureSecretEqual,
  selectPilotCandidates,
  simulateLeaseClaim,
} from "./batch_policy.ts";
import type { PilotJob } from "./batch_policy.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

Deno.test("a lease claim recovers expired work and claims exactly one row per invocation", () => {
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
  assert(result.claimed.length === 1, "claim exceeded the one-card maximum");
  assert(
    result.claimed.every((job) => job.issuer === "Axis Bank"),
    "claim mixed issuers",
  );
});

Deno.test("batch claims never take the legacy manual catalog ownership lane", () => {
  const result = simulateLeaseClaim(
    [
      {
        id: "catalog-manual",
        issuer: "Axis Bank",
        cardName: "A Catalog Job",
        status: "processing",
        leaseExpiresAt: null,
        nextRetryAt: null,
        runMode: "manual",
        parserVersion: "catalog-v1",
      },
      {
        id: "benefit-manual",
        issuer: "Axis Bank",
        cardName: "B Benefit Job",
        status: "queued",
        leaseExpiresAt: null,
        nextRetryAt: null,
        runMode: "manual",
        parserVersion: "benefits-v1",
      },
    ],
    new Date("2026-08-17T12:00:00.000Z"),
    "manual",
    1,
  );
  assert(
    result.claimed.map((job) => job.id).join(",") === "benefit-manual",
    "batch worker claimed a legacy catalog-owned row",
  );
  assert(
    result.recoveredIds.length === 0,
    "batch worker recovered a legacy catalog-owned processing row",
  );
});

Deno.test("batch claims reserve catalog-v1 for the legacy worker in every run mode", () => {
  const result = simulateLeaseClaim(
    [
      {
        id: "scheduled-catalog",
        issuer: "Axis Bank",
        cardName: "A Catalog Job",
        status: "queued",
        leaseExpiresAt: null,
        nextRetryAt: null,
        runMode: "scheduled",
        parserVersion: "catalog-v1",
      },
      {
        id: "pilot-catalog",
        issuer: "Axis Bank",
        cardName: "B Catalog Job",
        status: "processing",
        leaseExpiresAt: null,
        nextRetryAt: null,
        runMode: "pilot",
        parserVersion: "catalog-v1",
      },
      {
        id: "scheduled-benefits",
        issuer: "Axis Bank",
        cardName: "C Benefit Job",
        status: "queued",
        leaseExpiresAt: null,
        nextRetryAt: null,
        runMode: "scheduled",
        parserVersion: "benefits-v1",
      },
    ],
    new Date("2026-08-17T12:00:00.000Z"),
    "scheduled",
  );
  assert(
    result.claimed.map((job) => job.id).join(",") === "scheduled-benefits",
    "scheduled catalog-v1 work entered the benefit worker",
  );
  assert(
    result.recoveredIds.length === 0,
    "pilot catalog-v1 work was lease-recovered by the benefit worker",
  );
});

Deno.test("one-card claims keep deterministic issuer ordering across casing variants", () => {
  const result = simulateLeaseClaim(
    [
      {
        id: "axis-a",
        issuer: "Axis Bank",
        cardName: "A Card",
        status: "queued",
        leaseExpiresAt: null,
        nextRetryAt: null,
        runMode: "scheduled",
      },
      {
        id: "axis-b",
        issuer: " axis bank ",
        cardName: "B Card",
        status: "queued",
        leaseExpiresAt: null,
        nextRetryAt: null,
        runMode: "scheduled",
      },
      {
        id: "hdfc-a",
        issuer: "HDFC Bank",
        cardName: "A Card",
        status: "queued",
        leaseExpiresAt: null,
        nextRetryAt: null,
        runMode: "scheduled",
      },
    ],
    new Date("2026-08-17T12:00:00.000Z"),
    "scheduled",
  );
  assert(
    result.claimed.map((job) => job.id).join(",") === "axis-a",
    "one-card claim lost deterministic normalized-issuer ordering",
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

Deno.test("re-enqueueing a leased job preserves its processing state and lease", async () => {
  const original = {
    id: "job-1",
    job_key: `card-a:${"a".repeat(64)}:benefits-v1`,
    status: "processing",
    lease_token: "lease-1",
    lease_expires_at: "2026-08-17T12:15:00.000Z",
    attempt_count: 2,
  };
  let stored = { ...original };
  let upserts = 0;
  const db = {
    from(table: string) {
      assert(
        table === "card_catalog_enrichment_jobs",
        "enqueue targeted the wrong table",
      );
      return {
        async upsert(
          input: Record<string, unknown> | Record<string, unknown>[],
          options: { onConflict?: string; ignoreDuplicates?: boolean },
        ) {
          upserts += 1;
          const [row] = Array.isArray(input) ? input : [input];
          const conflicts = row.job_key === stored.job_key;
          if (!conflicts || !options.ignoreDuplicates) {
            stored = { ...stored, ...row } as typeof stored;
          }
          return { error: null };
        },
      };
    },
  };

  await enqueueBenefitEnrichmentJob(db, {
    cardId: "card-a",
    issuer: "Axis Bank",
    canonicalUrl: "https://axis.example/card-a",
    finalUrlHash: "a".repeat(64),
    contentHash: "b".repeat(64),
    parserVersion: "benefits-v1",
  });

  assert(
    JSON.stringify(stored) === JSON.stringify(original),
    "duplicate enqueue rewound or mutated an active lease",
  );
  assert(upserts === 1, "enqueue skipped its database boundary");
});

Deno.test("benefit enqueue refuses the reserved catalog-v1 parser", async () => {
  let writes = 0;
  const db = {
    from() {
      writes += 1;
      return {
        async upsert() {
          return { error: null };
        },
      };
    },
  };
  let error: unknown;
  try {
    await enqueueBenefitEnrichmentJob(db, {
      cardId: "card-a",
      issuer: "Axis Bank",
      canonicalUrl: "https://axis.example/card-a",
      finalUrlHash: "a".repeat(64),
      contentHash: "b".repeat(64),
      parserVersion: "catalog-v1",
    });
  } catch (caught) {
    error = caught;
  }
  assert(
    error instanceof Error && error.message === "reserved_parser_version",
    "reserved parser was accepted by benefit enqueue",
  );
  assert(writes === 0, "rejected parser reached the queue");
});

Deno.test("same content and parser reuse an existing staging row", () => {
  const rows = [{
    id: "stage-1",
    cardId: "card-a",
    sourceUrl: "https://example.test/card",
    requestType: "official_benefit_enrichment",
    parserVersion: "benefits-v1",
    contentHash: "content-a",
    status: "pending",
    evidenceSafe: true,
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
  assert(
    findReusableStaging([{ ...rows[0], status: "rejected" }], {
      cardId: "card-a",
      sourceUrl: "https://example.test/card",
      parserVersion: "benefits-v1",
      contentHash: "content-a",
    }) === undefined,
    "rejected staging was reused",
  );
  assert(
    findReusableStaging([{ ...rows[0], evidenceSafe: false }], {
      cardId: "card-a",
      sourceUrl: "https://example.test/card",
      parserVersion: "benefits-v1",
      contentHash: "content-a",
    }) === undefined,
    "staging without safe evidence was reused",
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

Deno.test("pilot selector backtracks when the first profile must preserve a scarce issuer", () => {
  const candidates = [
    {
      id: "a-first",
      issuer: "Axis",
      active: true,
      approvedUrl: true,
      profile: "straightforward" as const,
    },
    {
      id: "c-first",
      issuer: "ICICI",
      active: true,
      approvedUrl: true,
      profile: "straightforward" as const,
    },
    {
      id: "a-heavy",
      issuer: "Axis",
      active: true,
      approvedUrl: true,
      profile: "redirect_or_js" as const,
    },
    {
      id: "b-heavy",
      issuer: "HDFC",
      active: true,
      approvedUrl: true,
      profile: "redirect_or_js" as const,
    },
    {
      id: "a-terms",
      issuer: "Axis",
      active: true,
      approvedUrl: true,
      profile: "terms_linked" as const,
    },
    {
      id: "b-terms",
      issuer: "HDFC",
      active: true,
      approvedUrl: true,
      profile: "terms_linked" as const,
    },
    {
      id: "a-invalid",
      issuer: "Axis",
      active: true,
      approvedUrl: false,
      profile: "known_invalid" as const,
    },
    {
      id: "b-invalid",
      issuer: "HDFC",
      active: true,
      approvedUrl: false,
      profile: "known_invalid" as const,
    },
    {
      id: "a-extra",
      issuer: "Axis",
      active: true,
      approvedUrl: true,
      profile: "additional_valid" as const,
    },
    {
      id: "b-extra",
      issuer: "HDFC",
      active: true,
      approvedUrl: true,
      profile: "additional_valid" as const,
    },
  ];
  const selected = selectPilotCandidates(candidates);
  assert(
    selected.length === 5,
    "selector returned empty despite a valid combination",
  );
  assert(
    new Set(selected.map((candidate) => candidate.issuer)).size === 3,
    "selector did not backtrack to three issuers",
  );
  assert(
    selected.some((candidate) => candidate.id === "c-first"),
    "scarce issuer candidate was not selected",
  );
});

Deno.test("pilot issuer diversity ignores bank casing and surrounding spaces", () => {
  const issuers = [
    "Axis Bank",
    " axis bank ",
    "AXIS BANK",
    "HDFC Bank",
    " hdfc bank ",
  ];
  const profiles = [
    "straightforward",
    "redirect_or_js",
    "terms_linked",
    "known_invalid",
    "additional_valid",
  ] as const;
  const selected = selectPilotCandidates(profiles.map((profile, index) => ({
    id: `candidate-${index}`,
    issuer: issuers[index],
    active: true,
    approvedUrl: profile !== "known_invalid",
    profile,
  })));
  assert(
    selected.length === 0,
    "issuer spelling variants were counted as distinct banks",
  );
});

Deno.test("secret comparison hashes unequal-length inputs before fixed-length comparison", async () => {
  assert(
    await secureSecretEqual("cron-secret", "cron-secret"),
    "matching secret was rejected",
  );
  assert(
    !await secureSecretEqual("x", "much-longer-secret"),
    "unequal secrets matched",
  );
  assert(!await secureSecretEqual("", ""), "empty secrets were accepted");
});

Deno.test("scheduled rollout stays blocked until the exact safe five-job pilot passes", () => {
  const base: PilotJob[] = Array.from({ length: 5 }, (_, index) => ({
    id: `pilot-${index}`,
    runMode: "pilot" as const,
    status: index === 4 ? "quarantined" : "staged",
    quarantineReason: index === 4 ? "identity_mismatch" : null,
    unsafeMutationCount: 0,
    idempotencyPassed: true,
    evidencePassed: true,
    rawBodyStored: false,
    pilotQualified: false,
    successfulNoChange: false,
    reviewMetadataPresent: false,
    reviewMetadataMalformed: false,
    reviewStatus: null,
    approvedCount: null,
    retainedCount: null,
    retiredCount: null,
    rejectedCount: null,
  }));
  assert(
    evaluatePilotGate(base).status === "passed",
    "safe terminal pilot did not pass",
  );
  const completedNoChange: PilotJob[] = base.map((job, index) =>
    index === 0
      ? { ...job, status: "completed", successfulNoChange: true }
      : job
  );
  assert(
    evaluatePilotGate(completedNoChange).status === "passed",
    "successful no-change completion did not finish the pilot",
  );
  const completedApproval: PilotJob[] = base.map((job, index) =>
    index === 1
      ? {
        ...job,
        status: "completed",
        reviewMetadataPresent: true,
        reviewStatus: "approved",
        approvedCount: 1,
        retainedCount: 0,
        retiredCount: 0,
        rejectedCount: 0,
      }
      : job
  );
  assert(
    evaluatePilotGate(completedApproval).scheduledClaimAllowed,
    "admin-approved completion self-deadlocked scheduled claims",
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
  const failed = base.map((job, index) =>
    index === 0
      ? { ...job, status: "failed", quarantineReason: "timeout" }
      : job
  );
  const failedGate = evaluatePilotGate(failed);
  assert(
    failedGate.status === "blocked",
    "failed pilot was treated as running",
  );
  assert(
    failedGate.blockers.includes("pilot_failed"),
    "failed pilot omitted its blocker",
  );
  const review = base.map((job, index) =>
    index === 0
      ? { ...job, status: "review_required", quarantineReason: "timeout" }
      : job
  );
  assert(
    evaluatePilotGate(review).blockers.includes("pilot_review_required"),
    "review-required pilot omitted its blocker",
  );
  const recovered = failed.map((job, index) =>
    index === 0
      ? { ...job, status: "quarantined", quarantineReason: "timeout" }
      : job
  );
  assert(
    evaluatePilotGate(recovered).status === "passed",
    "recovered pilot could not pass",
  );

  const fullyRejected: PilotJob[] = base.map((job, index) =>
    index === 0
      ? {
        ...job,
        status: "completed",
        reviewMetadataPresent: true,
        reviewStatus: "rejected",
        approvedCount: 0,
        retainedCount: 0,
        retiredCount: 0,
        rejectedCount: 2,
      }
      : job
  );
  assert(
    evaluatePilotGate(fullyRejected).blockers.includes(
      "pilot_review_rejected",
    ),
    "fully rejected review unlocked rollout",
  );

  const partiallyRejected: PilotJob[] = base.map((job, index) =>
    index === 0
      ? {
        ...job,
        status: "completed",
        reviewMetadataPresent: true,
        reviewStatus: "approved",
        approvedCount: 1,
        retainedCount: 0,
        retiredCount: 0,
        rejectedCount: 1,
      }
      : job
  );
  assert(
    evaluatePilotGate(partiallyRejected).blockers.includes(
      "pilot_review_partially_rejected",
    ),
    "mixed approval/rejection unlocked rollout",
  );

  for (
    const malformed of [
      {
        reviewMetadataPresent: true,
        reviewMetadataMalformed: true,
        reviewStatus: "approved",
        approvedCount: null,
        rejectedCount: 0,
      },
      {
        reviewMetadataPresent: true,
        reviewMetadataMalformed: true,
        reviewStatus: "approved",
        approvedCount: -1,
        rejectedCount: 0,
      },
      {
        reviewMetadataPresent: false,
        reviewMetadataMalformed: false,
        reviewStatus: null,
        approvedCount: null,
        rejectedCount: null,
      },
    ] satisfies Array<Partial<PilotJob>>
  ) {
    const jobs: PilotJob[] = base.map((job, index) =>
      index === 0 ? { ...job, status: "completed", ...malformed } : job
    );
    assert(
      evaluatePilotGate(jobs).blockers.includes(
        "pilot_review_metadata_invalid",
      ),
      "missing or malformed completed-review metadata unlocked rollout",
    );
  }

  const promoted: PilotJob[] = completedApproval.map((job) => ({
    ...job,
    runMode: "scheduled" as const,
    pilotQualified: true,
  }));
  assert(
    evaluatePilotGate(promoted).status === "passed",
    "qualified pilot handoff forgot the completed gate",
  );
  assert(
    evaluatePilotGate(promoted.slice(0, 4)).status === "running",
    "partial qualified handoff unlocked rollout",
  );
  const recurring = promoted.map((job, index) => ({
    ...job,
    status: ["queued", "processing", "failed", "staged", "completed"][index],
    successfulNoChange: index === 4,
  }));
  assert(
    evaluatePilotGate(recurring).status === "passed",
    "a qualified scheduled recurrence self-deadlocked its own claim",
  );
  const rejectedAfterHandoff: PilotJob[] = promoted.map((job, index) =>
    index === 0
      ? {
        ...job,
        status: "completed",
        successfulNoChange: false,
        reviewMetadataPresent: true,
        reviewStatus: "rejected",
        approvedCount: 0,
        retainedCount: 0,
        retiredCount: 0,
        rejectedCount: 1,
      }
      : job
  );
  assert(
    evaluatePilotGate(rejectedAfterHandoff).blockers.includes(
      "pilot_review_rejected",
    ),
    "a post-handoff full rejection left rollout unlocked",
  );
});
