import {
  applyRemovalPolicy,
  buildCrawlObservation,
  claimLimitForInvocation,
  computeSourceManifestHash,
  crawlProposalDisposition,
  currentBenefitProposal,
  initializePilotJobs,
  loadCatalogIdentity,
  networkWorkMayStart,
  newestValidCrawlObservations,
  observationValidatedAt,
  previousFetchValidators,
  processJob,
  promoteQualifiedPilotJobs,
  readCompleteAbsenceHistory,
  readCurrentBenefits,
  readPilotStatus,
  refreshEligibleCard,
  requeueDueJobs,
  requireExactCatalogIdentity,
  seedScheduledQueueIfAllowed,
  shouldStageMaterialProposal,
  sourceObservationReviewSummary,
  sourceObservationSummary,
  stagingContentHashForObservation,
} from "./index.ts";
import * as batchModule from "./index.ts";
import {
  diffBenefits,
  extractGroundedBenefits,
  extractGroundedBenefitsV6,
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

Deno.test("every scheduled, pilot, and manual invocation claims only one card", () => {
  for (const mode of ["scheduled", "pilot", "manual"] as const) {
    assert(
      claimLimitForInvocation(mode) === 1,
      `${mode} invocation claimed a batch`,
    );
  }
});

Deno.test("new network work stops at the 180-second invocation deadline", () => {
  assert(networkWorkMayStart(1_000, 180_999), "work stopped before deadline");
  assert(
    !networkWorkMayStart(1_000, 181_000),
    "work started at the deadline",
  );
});

Deno.test("every invocation requeues only bounded due v6 work before other queue work", async () => {
  const calls: Array<{ name: string; args: Record<string, unknown> }> = [];
  const db = {
    async rpc(name: string, args: Record<string, unknown>) {
      calls.push({ name, args });
      return { data: [{ id: "job-1" }], error: null };
    },
  };
  const now = new Date("2026-08-20T00:00:00.000Z");
  const count = await requeueDueJobs(db, now);
  assert(count === 1, "requeue result count was lost");
  assert(
    JSON.stringify(calls) === JSON.stringify([{
      name: "requeue_due_card_catalog_enrichment_jobs",
      args: {
        _parser_version: "benefits-v6",
        _limit: 1,
        _now: "2026-08-20T00:00:00.000Z",
      },
    }]),
    "worker did not invoke the bounded explicit-v6 requeue contract",
  );
});

Deno.test("failed primary observations reach the finalizer with bounded retry and retained attempts", async () => {
  for (
    const failureCode of [
      "deadline_exceeded",
      "timeout",
      "http_5xx",
      "unreachable",
    ]
  ) {
    const finalizations: Record<string, unknown>[] = [];
    const card = {
      id: "00000000-0000-4000-8000-000000000001",
      card_name: "Issuer Test Card",
      bank: "Issuer",
      network: "Visa",
      card_type: "credit",
      card_url: "https://issuer.example/card",
      is_discontinued: false,
    };
    const tableRows: Record<string, Record<string, unknown>[]> = {
      card_catalog: [card],
      card_catalog_aliases: [],
      active_card_benefits: [],
    };
    const db = {
      from(table: string) {
        const query = {
          select() {
            return this;
          },
          eq() {
            return this;
          },
          ilike() {
            return this;
          },
          in() {
            return this;
          },
          async single() {
            return { data: card, error: null };
          },
          then<TResult1 = unknown>(
            onfulfilled?:
              | ((value: unknown) => TResult1 | PromiseLike<TResult1>)
              | null,
          ) {
            return Promise.resolve({
              data: tableRows[table] ?? [],
              error: null,
            }).then(onfulfilled);
          },
        };
        return query;
      },
      async rpc(name: string, args: Record<string, unknown>) {
        assert(
          name === "finalize_card_catalog_enrichment_job",
          "failed primary observation called an unrelated RPC",
        );
        finalizations.push(args);
        return { data: "job-1", error: null };
      },
    };
    const attemptedAt = new Date().toISOString();
    const before = Date.now();
    const result = await processJob(
      db,
      {
        id: "job-1",
        card_id: card.id,
        issuer: card.bank,
        canonical_url: card.card_url,
        parser_version: "benefits-v6",
        attempt_count: 1,
        run_mode: "scheduled",
        lease_token: "lease-1",
        staging_id: null,
        result_summary: {},
      },
      "run-1",
      before,
      {
        fetchObservation: async () => ({
          disposition: "failed",
          attempts: [{ code: failureCode, attemptedAt }],
          reviewReason: failureCode,
        }),
      },
    );
    const finalized = finalizations[0];
    const retryAt = Date.parse(String(finalized?._next_retry_at));
    assert(
      result.outcome === "failed" && result.retried,
      `${failureCode} was not retried`,
    );
    assert(
      finalized?._status === "failed",
      `${failureCode} did not finalize as failed`,
    );
    assert(
      retryAt >= before + 15 * 60_000 && retryAt <= Date.now() + 15 * 60_000,
      `${failureCode} received an unbounded retry time`,
    );
    const observation = (finalized?._result_summary as Record<string, unknown>)
      ?.observation as Record<string, unknown>;
    const attempts = observation?.source_attempts as Record<string, unknown>[];
    assert(
      attempts?.some((attempt) => attempt.errorCode === failureCode),
      `${failureCode} attempts were lost before finalization`,
    );
  }
});

Deno.test("only a recurring 410 stages a bounded catalog discontinuation review", async () => {
  for (const status of [404, 410]) {
    const lifecycleCalls: Record<string, unknown>[] = [];
    const finalizations: Record<string, unknown>[] = [];
    const card = {
      id: "00000000-0000-4000-8000-000000000001",
      card_name: "Issuer Test Card",
      bank: "Issuer",
      network: "Visa",
      card_type: "credit",
      card_url: "https://issuer.example/card",
      is_discontinued: false,
    };
    const db = {
      from(table: string) {
        const query = {
          select() {
            return this;
          },
          eq() {
            return this;
          },
          ilike() {
            return this;
          },
          in() {
            return this;
          },
          async single() {
            return { data: card, error: null };
          },
          then<TResult1 = unknown>(
            onfulfilled?:
              | ((value: unknown) => TResult1 | PromiseLike<TResult1>)
              | null,
          ) {
            return Promise.resolve({
              data: table === "card_catalog" ? [card] : [],
              error: null,
            }).then(onfulfilled);
          },
        };
        return query;
      },
      async rpc(name: string, args: Record<string, unknown>) {
        if (name === "stage_card_catalog_lifecycle_review") {
          lifecycleCalls.push(args);
          return {
            data: "00000000-0000-4000-8000-000000000099",
            error: null,
          };
        }
        assert(
          name === "finalize_card_catalog_enrichment_job",
          `unexpected RPC ${name}`,
        );
        finalizations.push(args);
        return { data: "job-1", error: null };
      },
    };
    const attemptedAt = new Date().toISOString();
    await processJob(
      db,
      {
        id: "job-1",
        card_id: card.id,
        issuer: card.bank,
        canonical_url: card.card_url,
        parser_version: "benefits-v6",
        attempt_count: 1,
        run_mode: "scheduled",
        lease_token: "lease-1",
        staging_id: null,
        result_summary: {},
      },
      "run-1",
      Date.now(),
      {
        fetchObservation: async () => ({
          disposition: "review_required",
          reviewReason: `http_${status}`,
          attempts: [{ status, attemptedAt }],
        }),
      },
    );
    assert(finalizations.length === 1, `${status} was not finalized once`);
    assert(
      lifecycleCalls.length === (status === 410 ? 1 : 0),
      `${status} received the wrong lifecycle-review outcome`,
    );
    if (status === 410) {
      const call = lifecycleCalls[0];
      assert(
        call._card_id === card.id &&
          call._suggested_action === "mark_discontinued" &&
          call._source_url === card.card_url &&
          /^[0-9a-f]{64}$/.test(String(call._source_url_hash)),
        "410 lifecycle proposal was not bound to the exact catalog resource",
      );
      const observation = call._source_observation as Record<string, unknown>;
      assert(
        observation.kind === "strong_gone_observation" &&
          observation.source_status === 410 &&
          observation.identity_validated === false,
        "410 lifecycle proposal lost its decisive source observation",
      );
    }
  }
});

async function stableCanonicalProcessFixture(
  stagingStatusAtFinalize: "pending" | "approved" | "rejected" | null,
  materialChange = false,
  isDiscontinued = false,
) {
  const cardId = "00000000-0000-4000-8000-000000000001";
  const card = {
    id: cardId,
    card_name: "Issuer Test Card",
    bank: "Issuer",
    network: "Visa",
    card_type: "credit",
    card_url: "https://issuer.example/credit-cards/issuer-test-card",
    is_discontinued: isDiscontinued,
  };
  const text =
    "<html><title>Issuer Test Visa Credit Card</title><h1>Issuer Test Visa Credit Card</h1><p>Get 10% cashback on dining spends.</p></html>";
  const [proposed] = await extractGroundedBenefitsV6(
    [{ sourceUrl: card.card_url, text, contentHash: "b".repeat(64) }],
    "benefits-v6",
    cardId,
  );
  const currentText = materialChange
    ? "Get 5% cashback on dining spends."
    : text;
  const [currentProposal] = await extractGroundedBenefitsV6(
    [{
      sourceUrl: card.card_url,
      text: currentText,
      contentHash: "a".repeat(64),
    }],
    "benefits-v6",
    cardId,
  );
  const canonicalBytes = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(currentProposal.conditionHash),
  );
  const canonicalHash = [...new Uint8Array(canonicalBytes)].map((byte) =>
    byte.toString(16).padStart(2, "0")
  ).join("");
  const active = [{
    benefit: {
      benefit_id: "11111111-1111-4111-8111-111111111111",
      dedupe_key: currentProposal.dedupeKey,
      title: currentProposal.title,
      description: currentProposal.description,
      benefit_category: currentProposal.category,
      benefit_type: currentProposal.valueType,
      value_config: currentProposal.valueConfig,
      partners: currentProposal.partners,
      exclusions: currentProposal.exclusions,
      source_url: currentProposal.sourceUrl,
    },
  }];
  const finalizations: Record<string, unknown>[] = [];
  const stageCalls: Record<string, unknown>[] = [];
  const lifecycleCalls: Record<string, unknown>[] = [];
  let stagingReads = 0;
  let effectiveFinalStatus: string | null = null;
  const tableRows: Record<string, Record<string, unknown>[]> = {
    card_catalog: [card],
    card_catalog_aliases: [],
    active_card_benefits: active,
    card_benefits_staging: stagingStatusAtFinalize === null ? [] : [{
      id: "stage-old",
      card_id: cardId,
      parser_version: "benefits-v6",
      request_type: "official_benefit_enrichment",
      status: "pending",
    }],
  };
  const db = {
    from(table: string) {
      const filters = new Map<string, unknown>();
      const query = {
        select() {
          return this;
        },
        eq(column: string, value: unknown) {
          filters.set(column, value);
          return this;
        },
        ilike() {
          return this;
        },
        in() {
          return this;
        },
        async single() {
          return { data: card, error: null };
        },
        async maybeSingle() {
          if (table === "card_benefits_staging") stagingReads += 1;
          const rows = (tableRows[table] ?? []).filter((row) =>
            [...filters].every(([column, value]) => row[column] === value)
          );
          return { data: rows[0] ?? null, error: null };
        },
        then<TResult1 = unknown>(
          onfulfilled?:
            | ((value: unknown) => TResult1 | PromiseLike<TResult1>)
            | null,
        ) {
          return Promise.resolve({
            data: tableRows[table] ?? [],
            error: null,
          }).then(onfulfilled);
        },
      };
      return query;
    },
    async rpc(name: string, args: Record<string, unknown>) {
      if (name === "stage_card_catalog_lifecycle_review") {
        lifecycleCalls.push(args);
        return {
          data: "00000000-0000-4000-8000-000000000099",
          error: null,
        };
      }
      if (name === "stage_card_benefit_enrichment") {
        stageCalls.push(args);
        return {
          data: [{ staging_id: "stage-new", reused: false }],
          error: null,
        };
      }
      assert(
        name === "finalize_card_catalog_enrichment_job",
        `unexpected RPC ${name}`,
      );
      finalizations.push(args);
      const requestedStatus = String(args._status);
      const requestedStaging = args._staging_id;
      if (requestedStatus === "staged" && requestedStaging !== null) {
        effectiveFinalStatus = stagingStatusAtFinalize === "pending"
          ? "staged"
          : stagingStatusAtFinalize === "approved" ||
              stagingStatusAtFinalize === "rejected"
          ? "completed"
          : "review_required";
      } else {
        effectiveFinalStatus = stagingStatusAtFinalize === "pending"
          ? "staged"
          : requestedStatus;
      }
      return { data: "job-1", error: null };
    },
  };
  const observedAt = new Date().toISOString();
  const result = await processJob(
    db,
    {
      id: "job-1",
      card_id: cardId,
      issuer: card.bank,
      canonical_url: card.card_url,
      parser_version: "benefits-v6",
      attempt_count: 1,
      run_mode: "scheduled",
      lease_token: "lease-1",
      staging_id: stagingStatusAtFinalize === null ? null : "stage-old",
      result_summary: {
        observation: {
          observed_at: "2026-08-19T00:00:00.000Z",
          crawl_complete: true,
          crawl_reason: "complete",
          source_manifest_hash: "a".repeat(64),
          canonical_benefit_hash: canonicalHash,
          absent_benefit_ids: [],
          absent_legacy_benefit_ids: [],
          source_attempts: [],
        },
      },
    },
    "run-1",
    Date.now(),
    {
      fetchObservation: async () => ({
        disposition: "success",
        result: {
          status: 200,
          submittedUrl: card.card_url,
          finalUrl: card.card_url,
          canonicalUrl: card.card_url,
          contentType: "text/html",
          text,
          contentHash: "b".repeat(64),
          retrievedAt: observedAt,
          notModified: false,
        },
        attempts: [{ status: 200, attemptedAt: observedAt }],
      }),
    },
  );
  return {
    result,
    finalization: finalizations[0],
    stageCalls,
    lifecycleCalls,
    stagingReads,
    effectiveFinalStatus,
  };
}

Deno.test("an exact recurring reappearance stages reviewed reactivation", async () => {
  const { lifecycleCalls, finalization } = await stableCanonicalProcessFixture(
    null,
    false,
    true,
  );
  assert(lifecycleCalls.length === 1, "reappearance did not stage one review");
  const call = lifecycleCalls[0];
  assert(
    call._card_id === "00000000-0000-4000-8000-000000000001" &&
      call._suggested_action === "reactivate" &&
      call._source_url ===
        "https://issuer.example/credit-cards/issuer-test-card" &&
      call._content_hash === "b".repeat(64),
    "reactivation proposal was not bound to exact validated evidence",
  );
  const observation = call._source_observation as Record<string, unknown>;
  assert(
    observation.kind === "exact_card_reappearance" &&
      observation.source_status === 200 &&
      observation.identity_validated === true,
    "reactivation proposal lost its exact identity evidence",
  );
  assert(
    finalization?._status === "completed",
    "reactivation review incorrectly blocked recurring benefit completion",
  );
});

Deno.test("an exact active-card observation advances current lifecycle evidence without mutation", async () => {
  const { lifecycleCalls, finalization } = await stableCanonicalProcessFixture(
    null,
    false,
    false,
  );
  assert(
    lifecycleCalls.length === 1,
    "active exact observation did not advance the lifecycle evidence clock",
  );
  const call = lifecycleCalls[0];
  assert(
    call._suggested_action === "observe_current",
    "active exact observation created a mutable lifecycle action",
  );
  const observation = call._source_observation as Record<string, unknown>;
  assert(
    observation.kind === "exact_card_reappearance" &&
      observation.identity_validated === true &&
      observation.explicit_discontinuation === false,
    "current-state observation lost exact positive evidence",
  );
  assert(
    finalization?._status === "completed",
    "current-state evidence blocked ordinary benefit finalization",
  );
});

Deno.test("stable canonical 200 delegates pending reviewability to the locked finalizer", async () => {
  for (
    const [statusAtFinalize, expectedEffectiveStatus] of [
      ["pending", "staged"],
      ["approved", "completed"],
      ["rejected", "completed"],
      [null, "completed"],
    ] as const
  ) {
    const label = statusAtFinalize ?? "no-link";
    const fixture = await stableCanonicalProcessFixture(statusAtFinalize);
    assert(
      fixture.result.outcome === "completed",
      label + " was decided before finalization",
    );
    assert(
      fixture.finalization._status === "completed" &&
        fixture.finalization._staging_id === null,
      label + " client-side requested old staging",
    );
    assert(fixture.stagingReads === 0, label + " used a racy staging pre-read");
    assert(
      fixture.effectiveFinalStatus === expectedEffectiveStatus,
      label + " locked finalizer decision was lost",
    );
    assert(
      fixture.stageCalls.length === 0,
      label + " raw-only update created a new proposal",
    );
    const summary = fixture.finalization._result_summary as Record<
      string,
      unknown
    >;
    assert(
      summary.material_proposal === false &&
        summary.proposal_disposition === "no_change" &&
        summary.successful_no_change === true,
      label + " stable observation was not finalized as no-change",
    );
  }
});

Deno.test("material canonical 200 delegates supersession to the ordered staging RPC", async () => {
  const fixture = await stableCanonicalProcessFixture("pending", true);
  assert(fixture.result.outcome === "staged", "material update did not stage");
  assert(
    fixture.stageCalls.length === 1 &&
      fixture.finalization._staging_id === "stage-new",
    "material update bypassed Task 3 supersession",
  );
  const summary = fixture.finalization._result_summary as Record<
    string,
    unknown
  >;
  assert(
    summary.material_proposal === true &&
      summary.proposal_disposition === "material" &&
      summary.successful_no_change === false,
    "material update was collapsed into no-change",
  );
});

Deno.test("material finalization tolerates a sibling review completed after staging", async () => {
  for (
    const [statusAtFinalize, expectedEffectiveStatus] of [
      ["pending", "staged"],
      ["approved", "completed"],
      ["rejected", "completed"],
    ] as const
  ) {
    const fixture = await stableCanonicalProcessFixture(
      statusAtFinalize,
      true,
    );
    assert(
      fixture.finalization._status === "staged" &&
        fixture.finalization._staging_id === "stage-new",
      `${statusAtFinalize} sibling review changed the material client contract`,
    );
    assert(
      fixture.effectiveFinalStatus === expectedEffectiveStatus,
      `${statusAtFinalize} sibling review marooned or reattached the lease`,
    );
  }
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

  assert(parserVersion === "benefits-v6", "pilot defaulted to a stale parser");
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

Deno.test("qualified pilot handoff promotes the same exact five jobs idempotently", async () => {
  const jobs = Array.from({ length: 5 }, (_, index) => ({
    id: `pilot-${index}`,
    card_id: `card-${index}`,
    parser_version: "benefits-v6",
    run_mode: "scheduled",
    status: "staged",
    job_key: `card-${index}:hash-${index}:benefits-v6`,
    result_summary: { pilot_qualified: true },
  }));
  const calls: Array<{ name: string; args: Record<string, unknown> }> = [];
  const db = {
    async rpc(name: string, args: Record<string, unknown>) {
      calls.push({ name, args });
      return { data: jobs.map((job) => ({ ...job })), error: null };
    },
  };

  const first = await promoteQualifiedPilotJobs(db);
  const repeated = await promoteQualifiedPilotJobs(db);

  assert(first.length === 5 && repeated.length === 5, "handoff lost a card");
  assert(
    first.map((job) => job.id).join(",") ===
      repeated.map((job) => job.id).join(","),
    "repeated handoff created different job identities",
  );
  assert(
    calls.every((call) =>
      call.name === "promote_qualified_card_benefit_enrichment_pilot" &&
      call.args._parser_version === "benefits-v6"
    ),
    "handoff bypassed the atomic current-parser promotion RPC",
  );
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

Deno.test("approved v6 identifiers and canonical exclusion terms survive comparison", () => {
  const dedupeKey = "card-benefit-v2:card-1:cashback";
  const proposal = currentBenefitProposal({
    benefit_id: "11111111-1111-4111-8111-111111111111",
    dedupe_key: dedupeKey,
    title: "10% cashback",
    exclusions: {
      additional: { source_terms: ["fuel", "wallet reloads"] },
      categories: [],
    },
  });

  assert(proposal?.benefitId === dedupeKey, "card-scoped identifier was lost");
  assert(
    proposal?.liveBenefitId === "11111111-1111-4111-8111-111111111111",
    "existing live benefit row ID was lost",
  );
  assert(
    !Array.isArray(proposal?.exclusions) &&
      (proposal?.exclusions.additional as Record<string, string[]>).source_terms
          .join(",") === "fuel,wallet reloads",
    "canonical exclusion source terms were lost",
  );
});

Deno.test("approved-row reconstruction redacts legacy URL secrets before staging diffs", () => {
  const secretUrl =
    "https://user:secret@issuer.example/private?token=private#fragment";
  const proposal = currentBenefitProposal({
    dedupe_key: `card-benefit-v2:card-1:${"a".repeat(64)}`,
    title: `Dining cashback ${secretUrl}`,
    description: `Get 10% cashback. Details: ${secretUrl}`,
    benefit_category: "cashback",
    benefit_type: "cashback",
    value_config: {
      rate: 10,
      offer_subject: "cashback:cashback:dining",
      restrictions: [`See ${secretUrl}`],
      exclusions: {
        additional: { source_terms: [`Not valid at ${secretUrl}`] },
      },
    },
    partners: [`Partner ${secretUrl}`],
    source_url: secretUrl,
  });
  assert(proposal != null, "approved row did not reconstruct");
  const serialized = JSON.stringify(proposal);
  for (const secret of ["user:", "secret", "token=", "#fragment"]) {
    assert(!serialized.includes(secret), `approved row leaked ${secret}`);
  }
  assert(
    serialized.includes("https://issuer.example/private"),
    "safe host/path provenance was discarded",
  );
});

Deno.test("an identical approved v6 exclusion object remains unchanged", async () => {
  const [proposed] = await extractGroundedBenefitsV6(
    [{
      sourceUrl: "https://issuer.example/card",
      text: "Get 10% cashback, excluding fuel.",
      contentHash: "a".repeat(64),
    }],
    "benefits-v6",
    "card-1",
  );
  const current = currentBenefitProposal({
    dedupe_key: proposed.dedupeKey,
    title: proposed.title,
    description: proposed.description,
    benefit_category: proposed.category,
    benefit_type: proposed.valueType,
    value_config: proposed.valueConfig,
    partners: proposed.partners,
    exclusions: proposed.exclusions,
    source_url: proposed.sourceUrl,
  });
  assert(current != null, "approved v6 proposal was not reconstructed");

  const diff = diffBenefits([current], [proposed]);
  assert(diff.unchanged.length === 1, "identical v6 exclusions looked changed");
  assert(diff.conflicts.length === 0, "identical v6 exclusions conflicted");
});

Deno.test("DB category codes replay through the shared canonical category contract", async () => {
  const fixtures = [
    "Get 10% cashback on dining spends.",
    "Earn 5 reward points for every ₹150 spent on eligible purchases.",
    "Get 2 lounge visits per quarter at domestic airports.",
  ];
  for (const [index, text] of fixtures.entries()) {
    const [proposed] = await extractGroundedBenefitsV6(
      [{
        sourceUrl: "https://issuer.example/card",
        text,
        contentHash: String(index + 1).repeat(64),
      }],
      "benefits-v6",
      "card-1",
    );
    const current = currentBenefitProposal({
      benefit_id: `${index + 1}`.repeat(8) + "-1111-4111-8111-111111111111",
      dedupe_key: proposed.dedupeKey,
      title: proposed.title,
      description: proposed.description,
      benefit_category: proposed.category.toUpperCase(),
      benefit_type: proposed.valueType,
      value_config: proposed.valueConfig,
      partners: proposed.partners,
      exclusions: proposed.exclusions,
      valid_from: proposed.effectiveFrom,
      valid_until: proposed.effectiveTo,
    });
    assert(current != null, "DB-shaped benefit did not reconstruct");
    const diff = diffBenefits([current], [proposed]);
    assert(
      diff.unchanged.length === 1 && diff.conflicts.length === 0,
      `${proposed.category.toUpperCase()} DB category did not replay unchanged`,
    );
  }
});

Deno.test("scheduled enrichment requests the lifecycle view and retains its returned live UUID", async () => {
  const [old] = await extractGroundedBenefitsV6(
    [{
      sourceUrl: "https://issuer.example/card",
      text: "Get 5% cashback on dining spends.",
      contentHash: "a".repeat(64),
    }],
    "benefits-v6",
    "card-1",
  );
  const oldLiveId = "11111111-1111-4111-8111-111111111111";
  let selectedTable = "";
  const db = {
    from(table: string) {
      selectedTable = table;
      return {
        select() {
          return this;
        },
        eq() {
          return Promise.resolve({
            data: [{
              benefit_id: oldLiveId,
              dedupe_key: old.dedupeKey,
              title: old.title,
              description: old.description,
              benefit_category: "CASHBACK",
              benefit_type: old.valueType,
              value_config: old.valueConfig,
              partners: old.partners,
              exclusions: old.exclusions,
            }],
            error: null,
          });
        },
      };
    },
  };
  const current = await readCurrentBenefits(db, "card-1");
  assert(
    selectedTable === "active_card_benefits",
    "scheduled enrichment bypassed the lifecycle-aware active view",
  );
  assert(
    current.length === 1 && current[0].liveBenefitId === oldLiveId,
    "active view reconstruction lost the live benefit UUID",
  );
  const futureReplacement = {
    ...old,
    rate: 10,
    valueConfig: { ...old.valueConfig, rate: 10 },
    effectiveFrom: "2026-09-01",
  };
  const diff = diffBenefits(current, [futureReplacement]);
  assert(
    diff.possibleRemovals.length === 0,
    "old scheduled mapping became a possible removal before its boundary",
  );
});

Deno.test("legacy v5 DB category codes replay semantically without changing legacy identifiers", () => {
  const fixtures = [
    "Get 10% cashback on dining spends.",
    "Earn 5 reward points for every Rs. 150 spent on eligible purchases.",
    "Get 2 lounge visits per quarter at domestic airports.",
  ];
  const databaseCategories = [
    ["CASHBACK", "Cashback Rewards"],
    ["POINTS", "Reward Points"],
    ["LOUNGE", "Airport Lounge Access"],
  ];
  for (const [index, sourceText] of fixtures.entries()) {
    const [proposed] = extractGroundedBenefits([{
      sourceUrl: "https://issuer.example/card",
      text: sourceText,
      contentHash: String(index + 4).repeat(64),
    }], "benefits-v5");
    assert(proposed != null, "v5 fixture did not extract");
    const legacyId = `legacy:${index}:${proposed.dedupeKey}`;
    for (const databaseCategory of databaseCategories[index]) {
      const current = currentBenefitProposal({
        benefit_id: `${index + 4}`.repeat(8) +
          "-1111-4111-8111-111111111111",
        dedupe_key: legacyId,
        title: proposed.title,
        description: proposed.description,
        benefit_category: databaseCategory,
        benefit_type: proposed.valueType,
        value_config: {
          ...proposed.valueConfig,
          ...(proposed.value === undefined ? {} : { value: proposed.value }),
          ...(proposed.rate === undefined ? {} : { rate: proposed.rate }),
          ...(proposed.cap === undefined ? {} : { cap: proposed.cap }),
          ...(proposed.threshold === undefined
            ? {}
            : { threshold: proposed.threshold }),
          ...(proposed.frequency === undefined
            ? {}
            : { frequency: proposed.frequency }),
          ...(proposed.period === undefined ? {} : { period: proposed.period }),
          restrictions: proposed.restrictions,
        },
        exclusions: proposed.exclusions,
        partners: proposed.partners,
        valid_from: proposed.effectiveFrom,
        valid_until: proposed.effectiveTo,
      });
      assert(current != null, "legacy DB row did not reconstruct");
      assert(
        current.dedupeKey === legacyId && !("benefitId" in current),
        "legacy identifier was rewritten into the v2 identity lane",
      );
      const diff = diffBenefits([current], [{
        ...proposed,
        dedupeKey: legacyId,
      }]);
      assert(
        diff.unchanged.length === 1 && diff.conflicts.length === 0,
        `${databaseCategory} did not replay as unchanged v5 semantics`,
      );
    }
  }
});

Deno.test("legacy live rows become one explicit card-scoped identity migration", async () => {
  const fixtures = [
    {
      text: "Get 10% cashback on dining spends.",
      category: "CASHBACK",
    },
    {
      text: "Earn 5 reward points for every Rs. 150 spent on dining.",
      category: "POINTS",
    },
  ];
  for (const [index, fixture] of fixtures.entries()) {
    const [proposed] = await extractGroundedBenefitsV6(
      [{
        sourceUrl: "https://issuer.example/card",
        text: fixture.text,
        contentHash: String(index + 6).repeat(64),
      }],
      "benefits-v6",
      "card-1",
    );
    assert(proposed != null, "v6 migration fixture did not extract");
    const liveBenefitId = `${index + 6}`.repeat(8) +
      "-1111-4111-8111-111111111111";
    const current = currentBenefitProposal({
      benefit_id: liveBenefitId,
      dedupe_key: `legacy:${index}:offer`,
      title: proposed.title,
      description: proposed.description,
      benefit_category: fixture.category,
      benefit_type: proposed.valueType,
      value_config: proposed.valueConfig,
      partners: proposed.partners,
      exclusions: proposed.exclusions,
      source_url: proposed.sourceUrl,
    });
    assert(current != null, "legacy live row did not reconstruct");
    const diff = diffBenefits([current], [proposed]);
    assert(
      diff.modifications.length === 1 &&
        diff.modifications[0].changeType === "identity_migration",
      `${fixture.category} was not classified as identity migration`,
    );
    assert(
      diff.modifications[0].current.liveBenefitId === liveBenefitId &&
        diff.additions.length === 0 && diff.possibleRemovals.length === 0 &&
        diff.conflicts.length === 0,
      "legacy migration lost the live UUID or emitted add/remove tails",
    );
    const changed = diffBenefits([current], [{
      ...proposed,
      rate: (proposed.rate ?? 0) + 1,
      valueConfig: {
        ...proposed.valueConfig,
        rate: (proposed.rate ?? 0) + 1,
      },
    }]);
    assert(
      changed.modifications.length === 1 &&
        changed.modifications[0].changeType === undefined,
      "real commercial term change was mislabeled as identity migration",
    );
  }

  const [legacyProposal] = extractGroundedBenefits([{
    sourceUrl: "https://issuer.example/card",
    text: "Get 10% cashback on dining spends.",
    contentHash: "8".repeat(64),
  }], "benefits-v5");
  assert(legacyProposal != null, "v5 rollback fixture did not extract");
  const current = currentBenefitProposal({
    benefit_id: "88888888-1111-4111-8111-111111111111",
    dedupe_key: "legacy:approved:dining",
    title: legacyProposal.title,
    description: legacyProposal.description,
    benefit_category: "CASHBACK",
    benefit_type: legacyProposal.valueType,
    value_config: {
      ...legacyProposal.valueConfig,
      rate: legacyProposal.rate,
      restrictions: legacyProposal.restrictions,
    },
    exclusions: legacyProposal.exclusions,
    source_url: legacyProposal.sourceUrl,
  });
  assert(current != null, "v5 current migration fixture did not reconstruct");
  const rollback = diffBenefits([current], [legacyProposal]);
  assert(
    rollback.modifications.length === 1 &&
      rollback.modifications[0].changeType === "identity_migration" &&
      rollback.additions.length === 0 && rollback.possibleRemovals.length === 0,
    "v5 rollback proposal did not retain the explicit legacy migration path",
  );
});

Deno.test("legacy identity migration uses one canonical condition projection and fails closed on ambiguity", async () => {
  const [dining] = extractGroundedBenefits([{
    sourceUrl: "https://issuer.example/card",
    text:
      "Get 10% cashback on dining spends, excluding wallet reload transactions.",
    contentHash: "9".repeat(64),
  }], "benefits-v5");
  assert(dining != null, "v5 dining fixture did not extract");
  const proposed = {
    ...dining,
    exclusions: ["wallet reload transactions"],
    restrictions: ["dining"],
  };
  const legacyRow = (id: string, rate = proposed.rate) =>
    currentBenefitProposal({
      benefit_id: id,
      dedupe_key: `legacy:${id}:dining`,
      title: proposed.title,
      // Generic legacy display copy must not override structured conditions.
      description: "Earn 10% cashback",
      benefit_category: "CASHBACK",
      benefit_type: proposed.valueType,
      value_config: {
        ...proposed.valueConfig,
        rate,
        restrictions: ["dining"],
      },
      exclusions: {
        additional: { source_terms: ["wallet reload transactions"] },
        categories: [],
        days: [],
        mcc_codes: [],
        merchants: [],
        transaction_types: [],
      },
      source_url: proposed.sourceUrl,
    });
  const liveId = "99999999-1111-4111-8111-111111111111";
  const current = legacyRow(liveId);
  assert(current != null, "structured legacy fixture did not reconstruct");
  const exact = diffBenefits([current], [proposed]);
  assert(
    exact.modifications.length === 1 &&
      exact.modifications[0].changeType === "identity_migration" &&
      exact.modifications[0].current.liveBenefitId === liveId &&
      exact.additions.length === 0 && exact.possibleRemovals.length === 0 &&
      exact.conflicts.length === 0,
    "exact canonical conditions did not produce one live-UUID migration",
  );

  const second = legacyRow("99999999-2222-4222-8222-222222222222");
  assert(second != null, "ambiguous legacy fixture did not reconstruct");
  const ambiguous = diffBenefits([current, second], [proposed]);
  assert(
    ambiguous.modifications.every((item) =>
      item.changeType !== "identity_migration"
    ),
    "ambiguous same-condition legacy rows were auto-migrated",
  );

  const changed = legacyRow(
    "99999999-3333-4333-8333-333333333333",
    (proposed.rate ?? 10) + 1,
  );
  assert(changed != null, "changed legacy fixture did not reconstruct");
  assert(
    diffBenefits([changed], [proposed]).modifications.every((item) =>
      item.changeType !== "identity_migration"
    ),
    "real condition change was classified as identity migration",
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
  let orFilter = "";
  const rows = [
    "benefits-v1",
    "benefits-v2",
    "benefits-v3",
    "benefits-v4",
    "benefits-v5",
    "benefits-v6",
  ]
    .flatMap((parserVersion) =>
      Array.from({ length: 5 }, (_, index) => ({
        id: `${parserVersion}-${index}`,
        run_mode: parserVersion === "benefits-v6" ? "scheduled" : "pilot",
        parser_version: parserVersion,
        status: "staged",
        failure_category: null,
        result_summary: {
          unsafe_mutation_count: 0,
          idempotency_passed: true,
          evidence_passed: true,
          raw_body_stored: false,
          pilot_qualified: parserVersion === "benefits-v6",
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
    or(expression: string) {
      orFilter = expression;
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
        ) && (row.run_mode === "pilot" || row.result_summary.pilot_qualified)
      );
      return Promise.resolve({ data, error: null }).then(onfulfilled);
    },
  };
  const db = { from: () => query };

  const gate = await readPilotStatus(db);

  assert(
    filters.get("parser_version") === "benefits-v6",
    "pilot gate mixed parser generations",
  );
  assert(
    orFilter.includes("run_mode.eq.pilot") &&
      orFilter.includes("pilot_qualified"),
    "pilot gate forgot the persisted qualified handoff",
  );
  assert(
    gate.status === "passed",
    "safe current-generation pilot did not pass",
  );
});

Deno.test("pilot projection conservatively carries Task 4 review evidence", async () => {
  const rows = Array.from({ length: 5 }, (_, index) => ({
    id: `pilot-${index}`,
    run_mode: "pilot",
    parser_version: "benefits-v6",
    status: index === 0 ? "completed" : "staged",
    failure_category: null,
    result_summary: {
      unsafe_mutation_count: 0,
      idempotency_passed: true,
      evidence_passed: true,
      raw_body_stored: false,
      successful_no_change: false,
      review_status: index === 0 ? "rejected" : undefined,
      approved_count: index === 0 ? 0 : undefined,
      retained_count: index === 0 ? 0 : undefined,
      retired_count: index === 0 ? 0 : undefined,
      rejected_count: index === 0 ? 2 : undefined,
    },
  }));
  const query = {
    select() {
      return this;
    },
    eq() {
      return this;
    },
    or() {
      return this;
    },
    then<TResult1 = unknown>(
      onfulfilled?:
        | ((value: unknown) => TResult1 | PromiseLike<TResult1>)
        | null,
    ) {
      return Promise.resolve({ data: rows, error: null }).then(onfulfilled);
    },
  };
  const gate = await readPilotStatus({ from: () => query });
  assert(
    gate.blockers.includes("pilot_review_rejected"),
    "Task 4 rejection evidence disappeared at the pilot projection",
  );
  rows[0].result_summary.review_status = "unexpected";
  const malformed = await readPilotStatus({ from: () => query });
  assert(
    malformed.blockers.includes("pilot_review_metadata_invalid"),
    "malformed review metadata was normalized into a passing review",
  );
});

Deno.test("pilot review projection enforces exact bounded metadata parity", async () => {
  const baseReview: Record<string, unknown> = {
    unsafe_mutation_count: 0,
    idempotency_passed: true,
    evidence_passed: true,
    raw_body_stored: false,
    successful_no_change: false,
    review_status: "approved",
    approved_count: 1,
    retained_count: 0,
    retired_count: 0,
    rejected_count: 0,
  };
  const gateFor = async (summary: Record<string, unknown>) => {
    const rows = Array.from({ length: 5 }, (_, index) => ({
      id: "pilot-" + index,
      run_mode: "pilot",
      parser_version: "benefits-v6",
      status: index === 0 ? "completed" : "staged",
      failure_category: null,
      result_summary: index === 0 ? summary : {
        unsafe_mutation_count: 0,
        idempotency_passed: true,
        evidence_passed: true,
        raw_body_stored: false,
      },
    }));
    const query = {
      select() {
        return this;
      },
      eq() {
        return this;
      },
      or() {
        return this;
      },
      then<TResult1 = unknown>(
        onfulfilled?:
          | ((value: unknown) => TResult1 | PromiseLike<TResult1>)
          | null,
      ) {
        return Promise.resolve({ data: rows, error: null }).then(onfulfilled);
      },
    };
    return await readPilotStatus({ from: () => query });
  };
  const invalidCases: Array<[
    string,
    (summary: Record<string, unknown>) => void,
  ]> = [
    ["missing", (summary) => delete summary.retained_count],
    ["missing status", (summary) => delete summary.review_status],
    ["null", (summary) => summary.review_status = null],
    ["status casing", (summary) => summary.review_status = "Approved"],
    ["ten digit", (summary) => summary.approved_count = 1_000_000_000],
    ["overflow", (summary) => summary.approved_count = Number.MAX_SAFE_INTEGER],
    ["negative", (summary) => summary.approved_count = -1],
    ["fractional", (summary) => summary.approved_count = 0.5],
    ["string", (summary) => summary.approved_count = "1"],
  ];
  for (const [label, mutate] of invalidCases) {
    const summary = { ...baseReview };
    mutate(summary);
    const gate = await gateFor(summary);
    assert(
      gate.blockers.includes("pilot_review_metadata_invalid"),
      label + " review metadata unlocked rollout",
    );
  }
  const boundary = await gateFor({
    ...baseReview,
    approved_count: 999_999_999,
    retained_count: 999_999_999,
    retired_count: 999_999_999,
  });
  assert(boundary.status === "passed", "bounded safe review sum was rejected");
});

Deno.test("pilot projection fails closed on missing or malformed safety metadata", async () => {
  const invalidSummaries: Array<Record<string, unknown>> = [
    { raw_body_stored: false },
    { unsafe_mutation_count: null, raw_body_stored: false },
    { unsafe_mutation_count: "0", raw_body_stored: false },
    { unsafe_mutation_count: -1, raw_body_stored: false },
    { unsafe_mutation_count: 0.5, raw_body_stored: false },
    { unsafe_mutation_count: 0 },
    { unsafe_mutation_count: 0, raw_body_stored: null },
    { unsafe_mutation_count: 0, raw_body_stored: "false" },
  ];
  const safeSummary = {
    unsafe_mutation_count: 0,
    idempotency_passed: true,
    evidence_passed: true,
    raw_body_stored: false,
  };
  for (const invalid of invalidSummaries) {
    const invalidSummary: Record<string, unknown> = {
      ...safeSummary,
      ...invalid,
    };
    if (!Object.hasOwn(invalid, "unsafe_mutation_count")) {
      delete invalidSummary.unsafe_mutation_count;
    }
    if (!Object.hasOwn(invalid, "raw_body_stored")) {
      delete invalidSummary.raw_body_stored;
    }
    const rows = Array.from({ length: 5 }, (_, index) => ({
      id: `pilot-${index}`,
      run_mode: "pilot",
      parser_version: "benefits-v6",
      status: "staged",
      failure_category: null,
      result_summary: index === 0 ? invalidSummary : safeSummary,
    }));
    const query = {
      select() {
        return this;
      },
      eq() {
        return this;
      },
      or() {
        return this;
      },
      then<TResult1 = unknown>(
        onfulfilled?:
          | ((value: unknown) => TResult1 | PromiseLike<TResult1>)
          | null,
      ) {
        return Promise.resolve({ data: rows, error: null }).then(onfulfilled);
      },
    };
    const gate = await readPilotStatus({ from: () => query });
    assert(
      gate.blockers.includes("pilot_safety_metadata_invalid"),
      `unsafe pilot metadata passed: ${JSON.stringify(invalid)}`,
    );
  }

  for (
    const [unsafeMutationCount, rawBodyStored, expected] of [
      [1, false, "unsafe_mutation"],
      [0, true, "raw_body_stored"],
    ] as const
  ) {
    const rows = Array.from({ length: 5 }, (_, index) => ({
      id: `pilot-${index}`,
      run_mode: "pilot",
      parser_version: "benefits-v6",
      status: "staged",
      failure_category: null,
      result_summary: {
        ...safeSummary,
        unsafe_mutation_count: index === 0 ? unsafeMutationCount : 0,
        raw_body_stored: index === 0 ? rawBodyStored : false,
      },
    }));
    const query = {
      select() {
        return this;
      },
      eq() {
        return this;
      },
      or() {
        return this;
      },
      then<TResult1 = unknown>(
        onfulfilled?:
          | ((value: unknown) => TResult1 | PromiseLike<TResult1>)
          | null,
      ) {
        return Promise.resolve({ data: rows, error: null }).then(onfulfilled);
      },
    };
    const gate = await readPilotStatus({ from: () => query });
    assert(gate.blockers.includes(expected), `${expected} was not blocked`);
  }
});

Deno.test("catalog identity requires an exact target match instead of a product-name substring", () => {
  const catalog = [
    { id: "regalia", card_name: "Regalia", card_type: "credit" },
    {
      id: "regalia-gold",
      card_name: "Regalia Gold",
      card_type: "credit",
    },
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

Deno.test("a shared generic alias cannot claim the more specific active tier", () => {
  const catalog = [
    { id: "regalia", card_name: "Regalia", card_type: "credit" },
    {
      id: "regalia-gold",
      card_name: "Regalia Gold",
      card_type: "credit",
    },
  ];
  const aliases = [
    { card_id: "regalia", alias: "Regalia Premium" },
    { card_id: "regalia-gold", alias: "Regalia Premium" },
  ];
  requireExactCatalogIdentity(
    "regalia",
    "HDFC Bank",
    "Regalia Premium",
    catalog,
    aliases,
  );
  let error: unknown;
  try {
    requireExactCatalogIdentity(
      "regalia-gold",
      "HDFC Bank",
      "Regalia Premium",
      catalog,
      aliases,
    );
  } catch (caught) {
    error = caught;
  }
  assert(
    error instanceof Error && error.message === "identity_mismatch",
    "generic shared alias claimed the more specific Gold tier",
  );
});

Deno.test("catalog identity keeps payment-network words when sibling variants would otherwise collide", () => {
  const catalog = [
    { id: "hpcl-coral", card_name: "Hpcl Coral", card_type: "credit" },
    {
      id: "hpcl-coral-amex",
      card_name: "Hpcl Coral American Express",
      card_type: "credit",
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

Deno.test("catalog identity never accepts an absent or non-credit card type", () => {
  for (const cardType of [undefined, "debit"]) {
    let error: unknown;
    try {
      requireExactCatalogIdentity(
        "regalia",
        "HDFC Bank",
        "Regalia",
        [{ id: "regalia", card_name: "Regalia", card_type: cardType }],
        [],
      );
    } catch (caught) {
      error = caught;
    }
    assert(
      error instanceof Error && error.message === "identity_mismatch",
      `${cardType ?? "missing"} card type reached recurring extraction`,
    );
  }
});

Deno.test("recurring identity cannot use a generic historical alias to erase stored network or tier", () => {
  const catalog = [{
    id: "privilege-infinite",
    card_name: "Privilege Infinite",
    network: "Visa",
    card_type: "credit",
  }];
  const aliases = [{
    card_id: "privilege-infinite",
    alias: "Legacy Privilege",
  }];
  for (
    const [name, network] of [
      ["Legacy Privilege", null],
      ["Legacy Privilege", "Visa"],
      ["Legacy Privilege Infinite", null],
      ["Legacy Privilege Infinite", "Mastercard"],
    ] as const
  ) {
    let error: unknown;
    try {
      requireExactCatalogIdentity(
        "privilege-infinite",
        "Axis Bank",
        name,
        catalog,
        aliases,
        network,
      );
    } catch (caught) {
      error = caught;
    }
    assert(
      error instanceof Error && error.message === "identity_mismatch",
      `${name}/${network ?? "missing network"} weakened the stored variant`,
    );
  }
  requireExactCatalogIdentity(
    "privilege-infinite",
    "Axis Bank",
    "Legacy Privilege Infinite",
    catalog,
    [{ card_id: "privilege-infinite", alias: "Legacy Privilege Infinite" }],
    "Visa",
  );
});

Deno.test("catalog identity loading includes an actively held discontinued target with active variants", async () => {
  const catalog = [
    {
      id: "regalia",
      card_name: "Regalia",
      bank: "HDFC Bank",
      network: "Visa",
      card_type: "credit",
      is_discontinued: false,
    },
    {
      id: "regalia-gold",
      card_name: "Regalia Gold",
      bank: "HDFC Bank",
      network: "Visa",
      card_type: "credit",
      is_discontinued: true,
    },
    {
      id: "axis",
      card_name: "Select",
      bank: "Axis Bank",
      network: "RuPay",
      card_type: "credit",
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
              (!filters.has("is_discontinued") ||
                row.is_discontinued === filters.get("is_discontinued"))
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
  is_discontinued: boolean | null;
};

function scheduledSeederDb(
  catalog: CatalogFixture[],
  initialJobs: Record<string, unknown>[] = [],
  activeHeldCardIds: string[] = [],
  pendingIdentityReviews: Record<string, unknown>[] = [],
  maximumInsertedPerRpc = Number.POSITIVE_INFINITY,
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
    async rpc(name: string, args: Record<string, unknown>) {
      assert(
        name === "enqueue_card_benefit_enrichment_jobs",
        "seeder bypassed the atomic enqueue RPC",
      );
      const rows = args._jobs as Record<string, unknown>[];
      let inserted = 0;
      for (const row of rows) {
        if (inserted >= maximumInsertedPerRpc) break;
        const conflict = [...jobs.values()].some((existing) =>
          existing.card_id === row.card_id &&
          existing.parser_version === row.parser_version
        );
        if (conflict) continue;
        jobs.set(String(row.job_key), { ...row });
        inserted += 1;
      }
      return { data: inserted, error: null };
    },
    from(table: string) {
      if (table === "card_catalog_review_queue") {
        let from = 0;
        let to = pendingIdentityReviews.length - 1;
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
          async range(nextFrom: number, nextTo: number) {
            from = nextFrom;
            to = nextTo;
            return {
              data: pendingIdentityReviews.slice(from, to + 1),
              error: null,
            };
          },
        };
      }
      if (table === "user_cards") {
        let selectedIds: string[] = [];
        let activeOnly = false;
        return {
          select() {
            return this;
          },
          in(_column: string, values: string[]) {
            selectedIds = values;
            return this;
          },
          async eq(column: string, value: unknown) {
            activeOnly = column === "is_active" && value === true;
            return {
              data: activeOnly
                ? activeHeldCardIds.filter((id) => selectedIds.includes(id))
                  .map((catalog_card_id) => ({ catalog_card_id }))
                : [],
              error: null,
            };
          },
        };
      }
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
      let includePilotHandoff = false;
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
        or(expression: string) {
          includePilotHandoff = expression.includes("run_mode.eq.pilot") &&
            expression.includes("pilot_qualified");
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
              [...filters].every(([column, value]) => row[column] === value) &&
              (!includePilotHandoff || row.run_mode === "pilot" ||
                (row.result_summary as Record<string, unknown> | undefined)
                    ?.pilot_qualified === true)
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
    !db.catalogFilters.has("eq:is_discontinued") &&
      db.catalogFilters.get("ilike:card_type") === "credit" &&
      db.catalogFilters.get("like:card_url") === "https://%",
    "catalog query did not constrain active HTTPS credit-card inventory",
  );
  assert(db.jobs.size === 3, "empty scheduled lane was not populated");
  const row = db.jobs.get(
    "card-valid:a9681b52e7105d3d3540076b1705c9d446e1171de165973e833940f671eedadf:benefits-v6",
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
  assert(row?.parser_version === "benefits-v6", "wrong parser lane");
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

Deno.test("scheduled seeding reports the database insertion count instead of candidates", async () => {
  const db = scheduledSeederDb(
    [
      validCatalogCard,
      { ...validCatalogCard, id: "card-two" },
      { ...validCatalogCard, id: "card-three" },
    ],
    [],
    [],
    [],
    1,
  );

  const seeded = await seedScheduledQueueIfAllowed(db, "scheduled", true, 10);

  assert(
    seeded === 1,
    "partial database insertion was silently counted as full",
  );
  assert(db.jobs.size === 1, "fixture did not exercise a partial insertion");
});

Deno.test("scheduled seeding keeps only held discontinued, credit, and safe catalog URLs", async () => {
  const db = scheduledSeederDb(
    [
      validCatalogCard,
      { ...validCatalogCard, id: "discontinued", is_discontinued: true },
      { ...validCatalogCard, id: "held-discontinued", is_discontinued: true },
      { ...validCatalogCard, id: "historical-null", is_discontinued: null },
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
    ],
    [],
    ["held-discontinued"],
  );

  const seeded = await seedScheduledQueueIfAllowed(db, "scheduled", true);

  assert(
    seeded === 3,
    "held discontinued or historical-null card was not refresh eligible",
  );
  assert(db.jobs.size === 3, "filtered inventory reached the queue");
});

Deno.test("scheduled seeding excludes cards named by an unresolved official-URL review", async () => {
  const db = scheduledSeederDb(
    [validCatalogCard, { ...validCatalogCard, id: "safe-card" }],
    [],
    [],
    [{
      id: "pending-review",
      status: "pending",
      existing_candidates: [],
      proposed_fields: {
        official_url:
          "https://www.axis.bank.in/cards/credit-card/privilege/?review=1",
      },
      source_evidence: {},
    }],
  );

  const seeded = await seedScheduledQueueIfAllowed(db, "scheduled", true);

  assert(seeded === 0, "unresolved URL identity reached recurring seeding");
  assert(db.jobs.size === 0, "unresolved URL identity created a job");
});

Deno.test("acquisition discontinuation never suppresses refresh for an actively held card", () => {
  assert(
    refreshEligibleCard({
      isDiscontinued: false,
      hasActiveCardholder: false,
    }),
    "available card was not refresh eligible",
  );
  assert(
    refreshEligibleCard({
      isDiscontinued: true,
      hasActiveCardholder: true,
    }),
    "actively held discontinued card lost refresh eligibility",
  );
  assert(
    !refreshEligibleCard({
      isDiscontinued: true,
      hasActiveCardholder: false,
    }),
    "unheld discontinued card entered recurring refresh",
  );
});

Deno.test("source observation summary is bounded, sanitized, and contains no body or lifecycle mutation", () => {
  const summary = sourceObservationSummary({
    parserVersion: "benefits-v6",
    disposition: "review_required",
    reviewReason: "persistent_404",
    crawlComplete: false,
    result: {
      status: 404,
      submittedUrl:
        "https://www.axis.bank.in/card?session=private-secret#fragment",
      finalUrl: "https://www.axis.bank.in/card?session=private-secret",
      canonicalUrl: "https://www.axis.bank.in/card",
      retrievedAt: "2026-08-19T00:00:00.000Z",
      etag: `\"${"a".repeat(700)}\"`,
      lastModified: "Wed, 19 Aug 2026 00:00:00 GMT",
      notModified: false,
    },
    attempts: [
      {
        status: 404,
        code: "http_404",
        attemptedAt: "2026-08-19T00:00:00.000Z",
      },
    ],
  });
  const serialized = JSON.stringify(summary);
  assert(!serialized.includes("private-secret"), "source secret persisted");
  assert(!serialized.includes("body"), "raw body field was admitted");
  assert(
    !serialized.includes("is_discontinued"),
    "fetch mutated acquisition state",
  );
  assert(
    typeof summary.etag === "string" && summary.etag.length === 512,
    "validator was not bounded",
  );
  assert(summary.http_status === 404, "terminal status was lost");
  assert(summary.parser_version === "benefits-v6", "parser version was lost");
});

Deno.test("identity review preserves the HTTP observation while marking it incomplete", () => {
  const reviewed = sourceObservationReviewSummary({
    terminal_disposition: "success",
    crawl_complete: true,
    http_status: 200,
    submitted_url: "https://www.axis.bank.in/card",
    attempts: [{ status: 200 }],
  }, "identity_mismatch");

  assert(
    reviewed.terminal_disposition === "review_required" &&
      reviewed.review_reason === "identity_mismatch" &&
      reviewed.crawl_complete === false && reviewed.http_status === 200,
    "identity review discarded or misrepresented the HTTP observation",
  );
  assert(
    Array.isArray(reviewed.attempts) && reviewed.attempts.length === 1,
    "identity review discarded the retained attempt evidence",
  );
});

Deno.test("conditional cache reuse requires prior complete canonical and content evidence", () => {
  const job = (
    sourceObservation: Record<string, unknown>,
    observation: Record<string, unknown>,
  ) => ({
    result_summary: {
      observation: {
        ...observation,
        source_observation: sourceObservation,
      },
    },
  });
  const complete = previousFetchValidators(job({
    parser_version: "benefits-v6",
    etag: '"v1"',
    content_hash: "a".repeat(64),
    submitted_identity_hash: "c".repeat(64),
    final_resource_url: "https://issuer.example/card",
    final_resource_identity_hash: "d".repeat(64),
    card_identity_validated: true,
  }, {
    crawl_complete: true,
    canonical_benefit_hash: "b".repeat(64),
  }) as never);
  assert(complete?.reusableExtraction === true, "complete cache was rejected");
  assert(complete?.contentHash === "a".repeat(64), "content evidence was lost");
  assert(
    complete?.sourceIdentityHash === "c".repeat(64) &&
      complete?.finalResourceIdentityHash === "d".repeat(64) &&
      complete?.finalResourceUrl === "https://issuer.example/card" &&
      complete?.cardIdentityValidated === true,
    "resource/card identity cache binding was lost",
  );

  for (
    const invalid of [
      job({ parser_version: "benefits-v6", etag: '"v1"' }, {
        crawl_complete: true,
        canonical_benefit_hash: "b".repeat(64),
      }),
      job({
        parser_version: "benefits-v6",
        etag: '"v1"',
        content_hash: "a".repeat(64),
      }, { crawl_complete: false, canonical_benefit_hash: "b".repeat(64) }),
      job({
        parser_version: "benefits-v6",
        etag: '"v1"',
        content_hash: "a".repeat(64),
        submitted_identity_hash: "c".repeat(64),
        final_resource_url: "https://issuer.example/card",
        final_resource_identity_hash: "d".repeat(64),
        card_identity_validated: false,
      }, { crawl_complete: true, canonical_benefit_hash: "b".repeat(64) }),
    ]
  ) {
    assert(
      previousFetchValidators(invalid as never)?.reusableExtraction === false,
      "incomplete cache sent conditional validators",
    );
  }
});

Deno.test("conditional cache reuse reads the newest recurring observation rather than the oldest retained history", () => {
  const source = (observedAt: string, etag: string) => ({
    observed_at: observedAt,
    crawl_complete: true,
    crawl_reason: "complete",
    source_manifest_hash: "a".repeat(64),
    canonical_benefit_hash: "b".repeat(64),
    absent_benefit_ids: [],
    absent_legacy_benefit_ids: [],
    source_attempts: [],
    source_observation: {
      parser_version: "benefits-v6",
      terminal_disposition: "success",
      crawl_complete: true,
      etag,
      content_hash: "a".repeat(64),
      submitted_identity_hash: "c".repeat(64),
      final_resource_identity_hash: "d".repeat(64),
      final_resource_url: "https://issuer.example/card",
      card_identity_validated: true,
    },
  });
  const newest = source("2026-08-19T18:00:00.000Z", '"newest"');
  const older = source("2026-07-20T00:00:00.000Z", '"oldest"');
  const validators = previousFetchValidators({
    id: "job-1",
    card_id: "card-1",
    issuer: "Issuer",
    canonical_url: "https://issuer.example/card",
    parser_version: "benefits-v6",
    attempt_count: 0,
    run_mode: "scheduled",
    lease_token: "lease-1",
    result_summary: {
      observation: newest,
      observations: [newest, older],
    },
  });
  assert(validators?.etag === '"newest"', "oldest history supplied validators");
});

Deno.test("crawl observation preserves compacted retry history and manifest hashes ignore nested timestamps", async () => {
  const base = {
    url: "https://issuer.example/card",
    logicalSourceKey: "f".repeat(64),
    role: "primary" as const,
    status: "success" as const,
    httpStatus: 200,
    contentHash: "a".repeat(64),
    attemptedAt: "2026-08-19T00:00:02.000Z",
    attemptHistory: [
      {
        status: "failed" as const,
        httpStatus: 503,
        errorCode: "http_5xx",
        attemptedAt: "2026-08-19T00:00:00.000Z",
      },
      {
        status: "failed" as const,
        httpStatus: 503,
        errorCode: "http_5xx",
        attemptedAt: "2026-08-19T00:00:01.000Z",
      },
      {
        status: "success" as const,
        httpStatus: 200,
        attemptedAt: "2026-08-19T00:00:02.000Z",
      },
    ],
  };
  const observation = buildCrawlObservation({
    observedAt: "2026-08-19T00:01:00.000Z",
    assessmentTime: "2026-08-19T00:01:00.000Z",
    crawlComplete: true,
    crawlReason: "complete",
    sourceManifestHash: "b".repeat(64),
    canonicalBenefitHash: "c".repeat(64),
    absentBenefitIds: [],
    absentLegacyBenefitIds: [],
    attempts: [base],
  });
  assert(
    observation.source_attempts[0].attemptHistory?.map((entry) =>
      entry.httpStatus
    ).join(",") === "503,503,200",
    "buildCrawlObservation erased existing retry history",
  );

  const shifted = {
    ...base,
    attemptedAt: "2026-08-20T00:00:02.000Z",
    attemptHistory: base.attemptHistory.map((entry, index) => ({
      ...entry,
      attemptedAt: `2026-08-20T00:00:0${index}.000Z`,
    })),
  };
  assert(
    await computeSourceManifestHash([base]) ===
      await computeSourceManifestHash([shifted]),
    "nested retry timestamps changed the stable manifest hash",
  );
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
      job_key: `card-valid:${urlHash}:benefits-v6`,
      card_id: "card-valid",
      parser_version: "benefits-v6",
      run_mode: "pilot",
      status: "completed",
      result_summary: { pilot: true },
    },
    {
      id: "processing-job",
      job_key: `card-processing:${urlHash}:benefits-v6`,
      card_id: "card-processing",
      parser_version: "benefits-v6",
      run_mode: "scheduled",
      status: "processing",
      lease_token: "lease-1",
    },
    {
      id: "terminal-job",
      job_key: `card-terminal:${urlHash}:benefits-v6`,
      card_id: "card-terminal",
      parser_version: "benefits-v6",
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

Deno.test("scheduled seeding excludes promoted pilot identity despite cosmetic URL hashes", async () => {
  const pilot = {
    id: "pilot-cosmetic-url",
    card_id: "card-valid",
    parser_version: "benefits-v6",
    job_key: `card-valid:${"f".repeat(64)}:benefits-v6`,
    run_mode: "scheduled",
    status: "completed",
    result_summary: { pilot_qualified: true },
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

Deno.test("incomplete observations suppress every possible removal and preserve sorted absence IDs", () => {
  const removals = [
    {
      benefit: {
        ...currentBenefitProposal({
          dedupe_key: "legacy:zeta",
          title: "Zeta cashback",
        })!,
        benefitId: "card-benefit-v2:card-1:zeta",
      },
      informational: true as const,
    },
    {
      benefit: {
        ...currentBenefitProposal({
          dedupe_key: "legacy:alpha",
          title: "Alpha cashback",
        })!,
        benefitId: "card-benefit-v2:card-1:alpha",
      },
      informational: true as const,
    },
  ];
  const result = applyRemovalPolicy({
    possibleRemovals: removals,
    crawlComplete: false,
    observedAt: "2026-08-19T00:00:00.000Z",
    completeAbsenceHistory: {},
  });

  assert(result.possibleRemovals.length === 0, "incomplete removals survived");
  assert(result.suppressedRemovalCount === 2, "suppressed count was lost");
  assert(
    result.absentBenefitIds.join(",") ===
      "card-benefit-v2:card-1:alpha,card-benefit-v2:card-1:zeta",
    "card-scoped absence IDs were not sorted",
  );
  assert(
    result.absentLegacyBenefitIds.join(",") === "legacy:alpha,legacy:zeta",
    "legacy absence IDs were not sorted",
  );
});

Deno.test("a removal becomes eligible only after a prior complete observation seven days earlier", () => {
  const removal = {
    benefit: {
      ...currentBenefitProposal({ dedupe_key: "legacy:cashback" })!,
      benefitId: "card-benefit-v2:card-1:cashback",
    },
    informational: true as const,
  };
  const first = applyRemovalPolicy({
    possibleRemovals: [removal],
    crawlComplete: true,
    observedAt: "2026-08-19T00:00:00.000Z",
    completeAbsenceHistory: {},
  });
  const corroborated = applyRemovalPolicy({
    possibleRemovals: [removal],
    crawlComplete: true,
    observedAt: "2026-08-19T00:00:00.000Z",
    completeAbsenceHistory: {
      "card-benefit-v2:card-1:cashback": ["2026-08-12T00:00:00.000Z"],
    },
  });

  assert(
    first.possibleRemovals[0].retirementEligible === false,
    "first complete absence became retirement eligible",
  );
  assert(
    corroborated.possibleRemovals[0].retirementEligible === true,
    "seven-day corroborated absence stayed ineligible",
  );
});

Deno.test("same-card v6 observation history is bounded and ignores other identifiers", async () => {
  const filters = new Map<string, unknown>();
  let limit = 0;
  let stagingLimit = 0;
  let stagingIds: string[] = [];
  const rows = [{
    id: "prior",
    card_id: "card-1",
    parser_version: "benefits-v6",
    staging_id: "stage-1",
    result_summary: {
      observation: {
        observed_at: "2026-08-12T00:00:00.000Z",
        crawl_complete: true,
        absent_benefit_ids: ["card-benefit-v2:card-1:cashback", "other"],
        absent_legacy_benefit_ids: ["legacy:cashback"],
      },
    },
  }];
  const db = {
    from(table: string) {
      if (table === "card_benefits_staging") {
        return {
          select() {
            return this;
          },
          eq(column: string, value: unknown) {
            filters.set(`staging:${column}`, value);
            return this;
          },
          in(_column: string, values: string[]) {
            stagingIds = values;
            return this;
          },
          limit(value: number) {
            stagingLimit = value;
            return Promise.resolve({
              data: [{
                id: "stage-1",
                card_id: "card-1",
                parser_version: "benefits-v6",
                status: "pending",
                extracted_data: {
                  request_type: "official_benefit_enrichment",
                  parser_version: "benefits-v6",
                },
              }],
              error: null,
            });
          },
        };
      }
      assert(
        table === "card_catalog_enrichment_jobs",
        "unexpected history table",
      );
      return {
        select() {
          return this;
        },
        eq(column: string, value: unknown) {
          filters.set(column, value);
          return this;
        },
        order() {
          return this;
        },
        limit(value: number) {
          limit = value;
          return Promise.resolve({ data: rows, error: null });
        },
      };
    },
  };

  const history = await readCompleteAbsenceHistory(db, "card-1", [
    "card-benefit-v2:card-1:cashback",
    "legacy:cashback",
  ], "2026-08-19T00:00:00.000Z");

  assert(filters.get("card_id") === "card-1", "history crossed cards");
  assert(
    filters.get("parser_version") === "benefits-v6",
    "history crossed parser lanes",
  );
  assert(limit === 24, "history query was not bounded to 24 observations");
  assert(
    filters.get("staging:card_id") === "card-1",
    "staging audit crossed cards",
  );
  assert(
    filters.get("staging:parser_version") === "benefits-v6",
    "staging audit crossed parser lanes",
  );
  assert(
    stagingIds.join(",") === "stage-1",
    "unbounded staging identities were queried",
  );
  assert(stagingLimit === 24, "staging corroboration was not bounded");
  assert(
    history["card-benefit-v2:card-1:cashback"]?.length === 1,
    "card-scoped history was lost",
  );
  assert(history["legacy:cashback"]?.length === 1, "legacy history was lost");
  assert(
    history.other === undefined,
    "unrequested absence identifier leaked in",
  );
});

Deno.test("history is globally deduplicated and limited to the newest 24 valid observations", () => {
  const base = Date.parse("2026-01-01T00:00:00.000Z");
  const summaries = Array.from({ length: 24 }, (_, row) => ({
    observations: Array.from({ length: 24 }, (_, item) => ({
      observed_at: new Date(base + (row * 24 + item) * 3_600_000).toISOString(),
      crawl_complete: true,
      absent_benefit_ids: [`benefit-${row}-${item}`],
    })),
  }));
  summaries[0].observations.push({
    observed_at: "not-a-date",
    crawl_complete: true,
    absent_benefit_ids: ["invalid"],
  });
  summaries[23].observations.push({
    ...summaries[23].observations[23],
  });

  const observations = newestValidCrawlObservations(
    summaries,
    "2026-08-19T00:00:00.000Z",
  );
  assert(observations.length === 24, "history exceeded the global bound");
  assert(
    observations[0].observed_at ===
      new Date(base + 575 * 3_600_000).toISOString(),
    "history was not sorted newest first",
  );
  assert(
    !JSON.stringify(observations).includes("invalid"),
    "invalid history timestamp survived",
  );
});

Deno.test("future observations cannot crowd out valid retirement history", () => {
  const observations = newestValidCrawlObservations([{
    observations: [{
      observed_at: "2026-08-18T00:00:00.000Z",
      crawl_complete: true,
      absent_benefit_ids: ["valid"],
    }, {
      observed_at: "9999-12-31T23:59:59.999Z",
      crawl_complete: true,
      absent_benefit_ids: ["future"],
    }],
  }], "2026-08-19T00:00:00.000Z");

  assert(observations.length === 1, "future observation survived validation");
  assert(
    observations[0].observed_at === "2026-08-18T00:00:00.000Z",
    "valid observation was crowded out",
  );
});

Deno.test("same-time observations dedupe only when timestamp and evidence identity all match", () => {
  const observedAt = "2026-08-20T00:00:00.000Z";
  const first = {
    observed_at: observedAt,
    source_manifest_hash: "a".repeat(64),
    canonical_benefit_hash: "b".repeat(64),
  };
  const distinctEvidence = {
    ...first,
    source_manifest_hash: "c".repeat(64),
  };
  const observations = newestValidCrawlObservations([{
    observation: first,
    observations: [{ ...first }, distinctEvidence],
  }], observedAt);
  assert(
    observations.length === 2,
    "distinct same-time evidence was collapsed",
  );
  assert(
    observations.some((item) => item.source_manifest_hash === "a".repeat(64)) &&
      observations.some((item) => item.source_manifest_hash === "c".repeat(64)),
    "read-side history identity diverged from SQL",
  );
});

Deno.test("crawl observation retains bounded attempts and both hashes without raw bodies", () => {
  const observation = buildCrawlObservation({
    observedAt: "2026-08-19T00:00:00.000Z",
    assessmentTime: "2026-08-19T00:00:00.000Z",
    crawlComplete: true,
    crawlReason: "complete",
    sourceManifestHash: "a".repeat(64),
    canonicalBenefitHash: "b".repeat(64),
    absentBenefitIds: ["z", "a"],
    absentLegacyBenefitIds: ["legacy-z", "legacy-a"],
    attempts: [{
      url: "https://issuer.example/card",
      role: "primary",
      status: "success",
      httpStatus: 200,
      contentHash: "c".repeat(64),
      attemptedAt: "2026-08-19T00:00:00.000Z",
    }],
  });

  assert(
    observation.absent_benefit_ids.join(",") === "a,z",
    "absence IDs were not sorted",
  );
  assert(
    observation.absent_legacy_benefit_ids.join(",") === "legacy-a,legacy-z",
    "legacy IDs were not sorted",
  );
  assert(
    observation.source_manifest_hash === "a".repeat(64),
    "raw manifest hash was lost",
  );
  assert(
    observation.canonical_benefit_hash === "b".repeat(64),
    "canonical hash was lost",
  );
  assert(
    !JSON.stringify(observation).includes("body"),
    "raw body field was persisted",
  );
});

Deno.test("crawl observation compaction retains a decisive final required retry", () => {
  const optional = Array.from({ length: 8 }, (_, index) => ({
    url: `https://issuer.example/card/benefits-${index}`,
    role: "supporting" as const,
    status: "success" as const,
    httpStatus: 200,
    contentHash: String(index).padStart(64, "0"),
    attemptedAt: `2026-08-19T00:0${index}:00.000Z`,
  }));
  const requiredUrl = "https://issuer.example/card/terms";
  const observation = buildCrawlObservation({
    observedAt: "2026-08-19T00:20:00.000Z",
    assessmentTime: "2026-08-19T00:20:00.000Z",
    crawlComplete: true,
    crawlReason: "complete",
    sourceManifestHash: "a".repeat(64),
    canonicalBenefitHash: "b".repeat(64),
    absentBenefitIds: [],
    absentLegacyBenefitIds: [],
    attempts: [
      {
        url: "https://issuer.example/card",
        role: "primary",
        status: "success",
        httpStatus: 200,
        contentHash: "c".repeat(64),
        attemptedAt: "2026-08-19T00:00:00.000Z",
      },
      ...optional,
      {
        url: requiredUrl,
        logicalSourceKey: "d".repeat(64),
        role: "required_supporting",
        status: "failed",
        errorCode: "http_404",
        attemptedAt: "2026-08-19T00:10:00.000Z",
      },
      {
        url: requiredUrl,
        logicalSourceKey: "d".repeat(64),
        role: "required_supporting",
        status: "success",
        httpStatus: 200,
        contentHash: "e".repeat(64),
        attemptedAt: "2026-08-19T00:11:00.000Z",
      },
    ],
  });

  assert(observation.source_attempts.length <= 9, "attempt bound was exceeded");
  assert(
    observation.crawl_complete === true,
    "compacted decisive evidence no longer reconstructed completeness",
  );
  assert(
    observation.source_attempts.some((item) =>
      item.role === "required_supporting" && item.status === "success" &&
      item.attemptedAt === "2026-08-19T00:11:00.000Z"
    ),
    "decisive final required retry was compacted away",
  );
});

Deno.test("too many decisive required sources force bounded incomplete evidence", () => {
  const observation = buildCrawlObservation({
    observedAt: "2026-08-19T00:20:00.000Z",
    assessmentTime: "2026-08-19T00:20:00.000Z",
    crawlComplete: true,
    crawlReason: "complete",
    sourceManifestHash: "a".repeat(64),
    canonicalBenefitHash: "b".repeat(64),
    absentBenefitIds: [],
    absentLegacyBenefitIds: [],
    attempts: [
      {
        url: "https://issuer.example/card",
        role: "primary",
        status: "success",
        httpStatus: 200,
        contentHash: "c".repeat(64),
        attemptedAt: "2026-08-19T00:00:00.000Z",
      },
      ...Array.from({ length: 9 }, (_, index) => ({
        url: `https://issuer.example/card/terms-${index}`,
        logicalSourceKey: String(index).padStart(64, "0"),
        role: "required_supporting" as const,
        status: "success" as const,
        httpStatus: 200,
        contentHash: String(index + 1).padStart(64, "0"),
        attemptedAt: `2026-08-19T00:${
          String(index + 1).padStart(2, "0")
        }:00.000Z`,
      })),
    ],
  });

  assert(observation.source_attempts.length === 9, "hard bound changed");
  assert(
    observation.crawl_complete === false,
    "decisive overflow stayed complete",
  );
  assert(
    observation.crawl_reason === "decisive_attempt_overflow",
    "decisive overflow lacked an explicit bounded reason",
  );
});

Deno.test("source manifest hash covers bounded success and failure outcomes", async () => {
  const baseline = await computeSourceManifestHash([{
    url: "https://issuer.example/card?credential=secret",
    role: "primary",
    status: "success",
    httpStatus: 200,
    contentHash: "a".repeat(64),
    attemptedAt: "2026-08-19T00:00:00.000Z",
  }, {
    url: "https://issuer.example/terms.pdf",
    role: "required_supporting",
    status: "failed",
    errorCode: "http_404",
    attemptedAt: "2026-08-19T00:00:00.000Z",
  }]);
  const laterTimestamp = await computeSourceManifestHash([{
    url: "https://issuer.example/card?credential=secret",
    role: "primary",
    status: "success",
    httpStatus: 200,
    contentHash: "a".repeat(64),
    attemptedAt: "2026-08-20T00:00:00.000Z",
  }, {
    url: "https://issuer.example/terms.pdf",
    role: "required_supporting",
    status: "failed",
    errorCode: "http_404",
    attemptedAt: "2026-08-20T00:00:00.000Z",
  }]);
  const recovered = await computeSourceManifestHash([{
    url: "https://issuer.example/card",
    role: "primary",
    status: "success",
    httpStatus: 200,
    contentHash: "a".repeat(64),
    attemptedAt: "2026-08-20T00:00:00.000Z",
  }, {
    url: "https://issuer.example/terms.pdf",
    role: "required_supporting",
    status: "success",
    httpStatus: 200,
    contentHash: "b".repeat(64),
    attemptedAt: "2026-08-20T00:00:00.000Z",
  }]);

  assert(
    baseline === laterTimestamp,
    "retrieval time destabilized the manifest",
  );
  assert(baseline !== recovered, "a supporting-source outcome was omitted");
});

Deno.test("a raw-only source change does not create a material proposal", () => {
  assert(
    !shouldStageMaterialProposal("canonical-1", "canonical-1", "stage-1"),
    "same canonical benefits created a new proposal",
  );
  assert(
    shouldStageMaterialProposal("canonical-1", "canonical-2", "stage-1"),
    "canonical benefit change was not material",
  );
  assert(
    !shouldStageMaterialProposal("canonical-1", "canonical-1", null),
    "stable canonical benefits were restaged only because the link was absent",
  );
});

Deno.test("source-complete zero extraction distinguishes removal review from no change", () => {
  assert(
    crawlProposalDisposition({
      crawlComplete: true,
      currentCount: 2,
      proposedCount: 0,
    }) === "removal_review",
    "complete absence did not produce removal review",
  );
  assert(
    crawlProposalDisposition({
      crawlComplete: true,
      currentCount: 0,
      proposedCount: 0,
    }) === "no_change",
    "empty catalog did not produce successful no-change",
  );
  assert(
    crawlProposalDisposition({
      crawlComplete: false,
      currentCount: 2,
      proposedCount: 0,
    }) === "incomplete",
    "incomplete absence became a removal review",
  );
});

Deno.test("later complete absence gets a distinct removal-review staging identity", async () => {
  const first = await stagingContentHashForObservation({
    disposition: "removal_review",
    sourceManifestHash: "a".repeat(64),
    observedAt: "2026-08-12T00:00:00.000Z",
    removals: [{ benefitId: "benefit-1", retirementEligible: false }],
  });
  const second = await stagingContentHashForObservation({
    disposition: "removal_review",
    sourceManifestHash: "a".repeat(64),
    observedAt: "2026-08-19T00:00:00.000Z",
    removals: [{ benefitId: "benefit-1", retirementEligible: true }],
  });

  assert(first !== second, "retirement policy reused stale staging evidence");
});

Deno.test("staging validation time is the issuer retrieval observation time", () => {
  assert(
    observationValidatedAt(
      "2026-08-19T00:00:00.000Z",
      "2026-08-19T00:05:00.000Z",
    ) === "2026-08-19T00:00:00.000Z",
    "completion time replaced the observation time",
  );
});

Deno.test("v5 keeps divergent source terms as separate legacy additions", () => {
  const shared = {
    title: "Dining cashback",
    description: "Dining cashback",
    category: "dining",
    valueType: "percentage",
    value: 10,
    rate: 10,
    cap: 500,
    frequency: "monthly",
    period: "statement_month",
    valueConfig: {},
    partners: [],
    restrictions: [],
    effectiveFrom: undefined,
    effectiveTo: undefined,
    confidence: { value: 1 },
    evidence: { value: "10%" },
    warnings: [],
  };
  const diff = diffBenefits([], [{
    ...shared,
    dedupeKey: "legacy:fuel",
    exclusions: ["fuel"],
    sourceUrl: "https://issuer.example/card",
    sourceExcerpt: "10% cashback excluding fuel",
    contentHash: "a".repeat(64),
    parserVersion: "benefits-v5",
  }, {
    ...shared,
    dedupeKey: "legacy:wallets",
    exclusions: ["wallet reloads"],
    sourceUrl: "https://issuer.example/terms.pdf",
    sourceExcerpt: "10% cashback excluding wallet reloads",
    contentHash: "b".repeat(64),
    parserVersion: "benefits-v5",
  }]);

  assert(diff.additions.length === 2, "v5 additions changed semantics");
  assert(diff.conflicts.length === 0, "v5 gained a v6 conflict rule");
});

Deno.test("v6 keeps independent dining and fuel cashback offers separate", async () => {
  const proposals = await extractGroundedBenefitsV6(
    [{
      sourceUrl: "https://issuer.example/card",
      text: "Get 10% cashback on dining spends.",
      contentHash: "a".repeat(64),
    }, {
      sourceUrl: "https://issuer.example/benefits",
      text: "Get 5% cashback on fuel spends.",
      contentHash: "b".repeat(64),
    }],
    "benefits-v6",
    "card-1",
  );
  const diff = diffBenefits([], proposals);

  assert(diff.additions.length === 2, "independent offers were collapsed");
  assert(diff.conflicts.length === 0, "independent offers conflicted");
});

Deno.test("v6 treats partner changes within the same movie BOGO as a conflict", async () => {
  const proposals = await extractGroundedBenefitsV6(
    [{
      sourceUrl: "https://issuer.example/card",
      text:
        "Buy 1 movie ticket and get the second ticket free on BookMyShow, capped at Rs. 500 once per month.",
      contentHash: "a".repeat(64),
    }, {
      sourceUrl: "https://issuer.example/terms",
      text:
        "Buy 1 movie ticket and get the second ticket free on District, capped at Rs. 500 once per month.",
      contentHash: "b".repeat(64),
    }],
    "benefits-v6",
    "card-1",
  );
  const diff = diffBenefits([], proposals);

  assert(diff.additions.length === 0, "partner conflict became additions");
  assert(diff.conflicts.length === 1, "partner conflict was not reviewed");
});

Deno.test("query-selected official documents remain distinct conflict sources", async () => {
  const proposals = await extractGroundedBenefitsV6(
    [{
      ...({ sourceIdentity: "a".repeat(64) } as Record<string, unknown>),
      sourceUrl: "https://issuer.example/offers?partner=bookmyshow",
      text:
        "Buy 1 movie ticket and get the second ticket free on BookMyShow, capped at Rs. 500 once per month.",
      contentHash: "a".repeat(64),
    }, {
      ...({ sourceIdentity: "b".repeat(64) } as Record<string, unknown>),
      sourceUrl: "https://issuer.example/offers?partner=district",
      text:
        "Buy 1 movie ticket and get the second ticket free on District, capped at Rs. 500 once per month.",
      contentHash: "b".repeat(64),
    }],
    "benefits-v6",
    "card-1",
  );
  const diff = diffBenefits([], proposals);

  assert(diff.conflicts.length === 1, "query-selected sources bypassed review");
  assert(diff.additions.length === 0, "query conflict became additions");
  const serialized = JSON.stringify(proposals);
  assert(!serialized.includes("?"), "raw source query entered proposal JSON");
});

Deno.test("v6 ignores a caller digest when deriving conflict source identity", async () => {
  const attackerDigest = "f".repeat(64);
  const proposals = await extractGroundedBenefitsV6(
    [{
      ...({ sourceIdentity: attackerDigest } as Record<string, unknown>),
      sourceUrl: "https://issuer.example/offers?partner=bookmyshow",
      text:
        "Buy 1 movie ticket and get the second ticket free on BookMyShow, capped at Rs. 500 once per month.",
      contentHash: "a".repeat(64),
    }, {
      ...({ sourceIdentity: attackerDigest } as Record<string, unknown>),
      sourceUrl: "https://issuer.example/offers?partner=district",
      text:
        "Buy 1 movie ticket and get the second ticket free on District, capped at Rs. 500 once per month.",
      contentHash: "b".repeat(64),
    }],
    "benefits-v6",
    "card-1",
  );
  const diff = diffBenefits([], proposals);

  assert(diff.conflicts.length === 1, "caller digest merged distinct sources");
  assert(
    proposals.every((proposal) => proposal.sourceIdentity !== attackerDigest),
    "caller digest survived internal source derivation",
  );
  assert(!JSON.stringify(proposals).includes("partner="), "query persisted");
});

Deno.test("embedded URL secrets are redacted before v6 identity and evidence", async () => {
  const project = async (token: string) =>
    await extractGroundedBenefitsV6(
      [{
        sourceUrl: `https://issuer.example/card?session=${token}`,
        finalUrl: `https://issuer.example/landing?redirect=${token}`,
        text: `
          <p>Get 50% off movie tickets on
            <a href="https://user:${token}@bookmyshow.com/offers?token=${token}#private">BookMyShow</a>,
            capped at Rs. 600 per transaction.</p>
          <p>Details: https://user:${token}@issuer.example/private?token=${token}#fragment</p>
        `,
        contentHash: "a".repeat(64),
      }],
      "benefits-v6",
      "card-1",
    );
  const first = await project("alpha-secret");
  const replay = await project("rotated-secret");

  assert(first.length === 1 && replay.length === 1, "offer was not parsed");
  const serialized = JSON.stringify(first);
  for (const secret of ["alpha-secret", "user:", "token=", "#private"]) {
    assert(!serialized.includes(secret), `proposal leaked ${secret}`);
  }
  assert(
    first[0].sourceUrl === "https://issuer.example/landing",
    "final provenance was not safely redacted",
  );
  assert(
    first[0].benefitId === replay[0].benefitId &&
      first[0].conditionHash === replay[0].conditionHash,
    "rotating URL tokens changed canonical benefit identity",
  );
});

Deno.test("staging source metadata contains only a validated display URL", async () => {
  const boundary = (batchModule as Record<string, unknown>)
    .stagingSourceMetadata;
  assert(typeof boundary === "function", "staging source boundary is absent");
  const metadata = await (boundary as (url: string) => Promise<{
    sourceUrl: string;
    sourceUrlHash: string;
  }>)(
    "https://user:secret@issuer.example/card?session=private#fragment",
  );
  assert(
    metadata.sourceUrl === "https://issuer.example/card",
    "staging source URL retained private components",
  );
  assert(
    /^[0-9a-f]{64}$/.test(metadata.sourceUrlHash),
    "staging source hash is not bounded",
  );
  assert(
    !JSON.stringify(metadata).includes("secret") &&
      !JSON.stringify(metadata).includes("private"),
    "staging metadata leaked URL secrets",
  );
  const rotated = await (boundary as (url: string) => Promise<{
    sourceUrl: string;
    sourceUrlHash: string;
  }>)(
    "https://issuer.example/card?session=another-private-token#ignored",
  );
  assert(
    rotated.sourceUrl === metadata.sourceUrl,
    "token rotation changed persisted URL display",
  );
  assert(
    rotated.sourceUrlHash !== metadata.sourceUrlHash,
    "exact transient source identity was not digested before redaction",
  );
  const transientDigest = "f".repeat(64);
  const fromFetcher = await (boundary as (
    url: string,
    digest?: string,
  ) => Promise<{ sourceUrl: string; sourceUrlHash: string }>)(
    "https://issuer.example/card",
    transientDigest,
  );
  assert(
    fromFetcher.sourceUrlHash === transientDigest,
    "fetcher transient identity digest was discarded after URL redaction",
  );
});

Deno.test("v6 separates domestic and international lounge offer subjects", async () => {
  const proposals = await extractGroundedBenefitsV6(
    [{
      sourceUrl: "https://issuer.example/card",
      text: "Get 2 lounge visits per quarter at domestic airports.",
      contentHash: "a".repeat(64),
    }, {
      sourceUrl: "https://issuer.example/benefits",
      text: "Get 4 lounge visits per quarter at international airports.",
      contentHash: "b".repeat(64),
    }],
    "benefits-v6",
    "card-1",
  );
  const diff = diffBenefits([], proposals);

  assert(diff.additions.length === 2, "lounge families were collapsed");
  assert(diff.conflicts.length === 0, "distinct lounge families conflicted");
});

Deno.test("equal-term domestic and international lounge offers retain durable identities", async () => {
  const documents = [{
    sourceUrl: "https://issuer.example/card",
    text:
      "Get 2 lounge visits per quarter at domestic airports. Get 2 lounge visits per quarter at international airports.",
    contentHash: "a".repeat(64),
  }];
  const first = await extractGroundedBenefitsV6(
    documents,
    "benefits-v6",
    "card-1",
  );
  const replay = await extractGroundedBenefitsV6(
    documents,
    "benefits-v6",
    "card-1",
  );

  assert(first.length === 2, "equal commercial terms collapsed offer families");
  assert(
    new Set(first.map((item) => item.offerSubject)).size === 2,
    "offer subjects did not distinguish lounge geography",
  );
  assert(
    new Set(first.map((item) => item.benefitId)).size === 2,
    "stable v6 identifiers omitted the offer subject",
  );
  assert(
    first.every((item) => item.valueConfig.offer_subject === item.offerSubject),
    "offer subject was not persisted in schema-preserving JSON",
  );
  assert(
    first.map((item) => item.benefitId).sort().join(",") ===
      replay.map((item) => item.benefitId).sort().join(","),
    "offer identities changed on replay",
  );
  const reconstructed = first.map((item) =>
    currentBenefitProposal({
      dedupe_key: item.dedupeKey,
      title: item.title,
      description: "mutable approved description",
      benefit_category: item.category,
      benefit_type: item.valueType,
      value_config: item.valueConfig,
      exclusions: item.exclusions,
      source_url: item.sourceUrl,
    })
  );
  assert(
    reconstructed.every((item, index) =>
      item?.offerSubject === first[index].offerSubject
    ),
    "approved reconciliation reconstructed subject from mutable description",
  );
});

Deno.test("legitimate same-source lounge tiers do not conflict", async () => {
  const proposals = await extractGroundedBenefitsV6(
    [{
      sourceUrl: "https://issuer.example/card",
      text:
        "Get 2 lounge visits per quarter at domestic airports. Get 4 lounge visits per year at domestic airports.",
      contentHash: "a".repeat(64),
    }],
    "benefits-v6",
    "card-1",
  );
  const diff = diffBenefits([], proposals);

  assert(proposals.length === 2, "same-source tiers collapsed");
  assert(diff.conflicts.length === 0, "same-source tiers falsely conflicted");
  assert(diff.additions.length === 2, "same-source tiers were not additions");
});

Deno.test("approved dining restrictions reconstruct an unchanged v6 condition", async () => {
  const [proposed] = await extractGroundedBenefitsV6(
    [{
      sourceUrl: "https://issuer.example/card",
      text:
        "Get 10% cashback on dining spends, capped at ₹500 per statement month.",
      contentHash: "a".repeat(64),
    }],
    "benefits-v6",
    "card-1",
  );
  const current = currentBenefitProposal({
    dedupe_key: proposed.dedupeKey,
    title: proposed.title,
    description: proposed.description,
    benefit_category: proposed.category,
    benefit_type: proposed.valueType,
    value_config: proposed.valueConfig,
    partners: proposed.partners,
    exclusions: proposed.exclusions,
    source_url: proposed.sourceUrl,
  });
  assert(current != null, "approved proposal was not reconstructed");
  const diff = diffBenefits([current], [proposed]);

  assert(
    diff.unchanged.length === 1,
    "approved dining proposal changed on replay",
  );
  assert(diff.conflicts.length === 0, "approved restrictions mismatched");
});

Deno.test("v6 persists and reconstructs every structured exclusion dimension", async () => {
  const structured = {
    additional: { source_terms: ["cash advances"] },
    categories: ["fuel"],
    days: ["sunday"],
    mcc_codes: ["5541"],
    merchants: ["example merchant"],
    transaction_types: ["wallet reload"],
  };
  const [parsed] = await extractGroundedBenefitsV6(
    [{
      sourceUrl: "https://issuer.example/card",
      text: "Get 10% cashback on dining spends excluding cash advances.",
      contentHash: "a".repeat(64),
    }],
    "benefits-v6",
    "card-1",
  );
  assert(
    JSON.stringify(parsed.valueConfig.exclusions) ===
      JSON.stringify(parsed.exclusions),
    "exclusions were not persisted in canonical value_config",
  );
  const proposal = {
    ...parsed,
    valueConfig: { ...parsed.valueConfig, exclusions: structured },
    exclusions: structured,
  };
  const current = currentBenefitProposal({
    dedupe_key: proposal.dedupeKey,
    title: proposal.title,
    description: proposal.description,
    benefit_category: proposal.category,
    benefit_type: proposal.valueType,
    value_config: proposal.valueConfig,
    partners: proposal.partners,
    exclusions: {},
    source_url: proposal.sourceUrl,
  });
  assert(current != null, "structured current proposal was not reconstructed");
  const replay = diffBenefits([current], [proposal]);
  assert(
    replay.unchanged.length === 1,
    "structured exclusions changed on replay",
  );
  const changed = diffBenefits([current], [{
    ...proposal,
    exclusions: { ...structured, merchants: ["different merchant"] },
    valueConfig: {
      ...proposal.valueConfig,
      exclusions: { ...structured, merchants: ["different merchant"] },
    },
  }]);
  assert(
    changed.conflicts.length === 1 || changed.modifications.length === 1,
    "real structured exclusion change was ignored",
  );
});

Deno.test("observation timestamps beyond the evidence skew are rejected", () => {
  let error: unknown;
  try {
    observationValidatedAt(
      "2026-08-19T00:05:00.001Z",
      "2026-08-19T00:00:00.000Z",
    );
  } catch (caught) {
    error = caught;
  }
  assert(
    error instanceof Error && error.message === "invalid_observation_timestamp",
    "future observation timestamp reached staging projection",
  );
  assert(
    observationValidatedAt(
      "2026-08-19T00:04:59.999Z",
      "2026-08-19T00:00:00.000Z",
    ) === "2026-08-19T00:04:59.999Z",
    "allowed clock skew was rejected",
  );
});

for (
  const fixture of [
    { singular: "Grocery", plural: "Groceries" },
    { singular: "Movie", plural: "Movies" },
  ]
) {
  Deno.test(`v6 ${fixture.singular.toLowerCase()} editorial aliases keep one identity`, async () => {
    const extract = (label: string) =>
      extractGroundedBenefitsV6(
        [{
          sourceUrl: "https://issuer.example/card",
          text: `${label} offer: Get 10% cashback on eligible spends.`,
          contentHash: "a".repeat(64),
        }],
        "benefits-v6",
        "card-1",
      );
    const [singular] = await extract(fixture.singular);
    const [plural] = await extract(fixture.plural);

    assert(
      singular.offerSubject === plural.offerSubject,
      "alias changed subject",
    );
    assert(singular.benefitId === plural.benefitId, "alias changed stable ID");
    assert(
      singular.conditionHash === plural.conditionHash,
      "alias changed canonical hash",
    );
    const different = (await extract("Fuel"))[0];
    assert(
      different.offerSubject !== singular.offerSubject,
      "different commercial subject was collapsed",
    );
  });
}

Deno.test("v6 reviews changed terms within one domestic lounge subject", async () => {
  const proposals = await extractGroundedBenefitsV6(
    [{
      sourceUrl: "https://issuer.example/card",
      text: "Get 2 lounge visits per quarter at domestic airports.",
      contentHash: "a".repeat(64),
    }, {
      sourceUrl: "https://issuer.example/terms",
      text: "Get 4 lounge visits per quarter at domestic airports.",
      contentHash: "b".repeat(64),
    }],
    "benefits-v6",
    "card-1",
  );
  const diff = diffBenefits([], proposals);

  assert(
    diff.additions.length === 0,
    "domestic lounge conflict became additions",
  );
  assert(
    diff.conflicts.length === 1,
    "domestic lounge terms were auto-selected",
  );
});

for (
  const fixture of [
    {
      label: "cap",
      first:
        "Get 10% cashback on dining spends, capped at ₹500 per statement month.",
      second:
        "Get 10% cashback on dining spends, capped at ₹600 per statement month.",
    },
    {
      label: "rate",
      first:
        "Get 10% cashback on dining spends, capped at ₹500 per statement month.",
      second:
        "Get 15% cashback on dining spends, capped at ₹500 per statement month.",
    },
    {
      label: "threshold",
      first: "Earn 10 reward points for every Rs. 100 spent on dining.",
      second: "Earn 10 reward points for every Rs. 200 spent on dining.",
    },
    {
      label: "validity",
      first: "Get 2 lounge visits per quarter, valid until 31 December 2026.",
      second: "Get 2 lounge visits per quarter, valid until 31 January 2027.",
    },
    {
      label: "eligibility",
      first: "Earn 10 reward points for every Rs. 100 spent on dining.",
      second:
        "Earn 10 reward points for every Rs. 100 spent on dining and movies.",
    },
    {
      label: "exclusions",
      first: "Get 10% cashback on dining spends, excluding fuel.",
      second: "Get 10% cashback on dining spends, excluding wallet reloads.",
    },
  ]
) {
  Deno.test(`contradictory official ${fixture.label} terms require review with bounded evidence`, async () => {
    const proposals = await extractGroundedBenefitsV6(
      [
        {
          sourceUrl: "https://issuer.example/card",
          text: fixture.first,
          contentHash: "a".repeat(64),
        },
        {
          sourceUrl: "https://issuer.example/card/terms.pdf",
          text: fixture.second,
          contentHash: "b".repeat(64),
        },
      ],
      "benefits-v6",
      "card-1",
    );
    const diff = diffBenefits([], proposals);

    assert(
      diff.additions.length === 0,
      `${fixture.label} conflict auto-selected a favorable term`,
    );
    assert(
      diff.conflicts.length === 1,
      `${fixture.label} disagreement did not require review`,
    );
    assert(
      diff.conflicts[0].proposed.length === 2,
      `${fixture.label} conflict lost one official source`,
    );
    assert(
      diff.conflicts[0].proposed.every((proposal) =>
        proposal.sourceExcerpt.length <= 500 &&
        proposal.contentHash.length <= 128
      ),
      `${fixture.label} conflict evidence was unbounded`,
    );
  });
}
