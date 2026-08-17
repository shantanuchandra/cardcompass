export const MAX_BATCH_SIZE = 5;
export const LEASE_SECONDS = 15 * 60;
export const RETRY_SCHEDULE_MINUTES = [15, 60, 240] as const;

export type RunMode = "pilot" | "scheduled" | "manual";
export type PilotStatus = "not_started" | "running" | "blocked" | "passed";

export type LeaseJob = {
  id: string;
  issuer: string;
  cardName: string;
  status: string;
  leaseExpiresAt: string | null;
  nextRetryAt: string | null;
  runMode: RunMode;
  parserVersion?: string;
};

export type StagingIdentity = {
  cardId: string;
  sourceUrl: string;
  parserVersion: string;
  contentHash: string;
};

export type StagingCandidate = StagingIdentity & {
  id: string;
  requestType: string;
  status: string;
  evidenceSafe: boolean;
};

export type PilotProfile =
  | "straightforward"
  | "redirect_or_js"
  | "terms_linked"
  | "known_invalid"
  | "additional_valid";

export type PilotCandidate = {
  id: string;
  issuer: string;
  active: boolean;
  approvedUrl: boolean;
  profile: PilotProfile;
};

export type PilotJob = {
  id: string;
  runMode: RunMode;
  status: string;
  quarantineReason: string | null;
  unsafeMutationCount: number;
  idempotencyPassed: boolean;
  evidencePassed: boolean;
  rawBodyStored: boolean;
};

function issuerKey(issuer: string): string {
  return issuer.trim().toLowerCase();
}

export type BenefitEnrichmentQueueInput = {
  cardId: string;
  issuer: string;
  canonicalUrl: string;
  finalUrlHash: string;
  contentHash: string | null;
  parserVersion: string;
  runMode?: RunMode;
  resultSummary?: Record<string, unknown>;
};

type EnrichmentQueueClient = {
  from(table: string): {
    upsert(
      row: Record<string, unknown> | Record<string, unknown>[],
      options: { onConflict: string; ignoreDuplicates: boolean },
    ): PromiseLike<{ error: unknown }>;
  };
};

export function buildJobKey(
  cardId: string,
  canonicalUrlHash: string,
  parserVersion: string,
): string {
  return `${cardId}:${canonicalUrlHash}:${parserVersion}`;
}

export function assertBenefitParserVersion(parserVersion: string): void {
  if (parserVersion.trim().toLowerCase() === "catalog-v1") {
    throw new Error("reserved_parser_version");
  }
}

export async function enqueueBenefitEnrichmentJob(
  db: EnrichmentQueueClient,
  input: BenefitEnrichmentQueueInput,
): Promise<void> {
  await enqueueBenefitEnrichmentJobs(db, [input]);
}

export async function enqueueBenefitEnrichmentJobs(
  db: EnrichmentQueueClient,
  inputs: readonly BenefitEnrichmentQueueInput[],
): Promise<void> {
  if (inputs.length === 0) return;
  const updatedAt = new Date().toISOString();
  const rows = inputs.map((input) => {
    assertBenefitParserVersion(input.parserVersion);
    return {
      card_id: input.cardId,
      issuer: input.issuer,
      canonical_url: input.canonicalUrl,
      final_url_hash: input.finalUrlHash,
      content_hash: input.contentHash,
      parser_version: input.parserVersion,
      job_key: buildJobKey(
        input.cardId,
        input.finalUrlHash,
        input.parserVersion,
      ),
      status: "queued",
      run_mode: input.runMode ?? "scheduled",
      result_summary: input.resultSummary ?? {},
      updated_at: updatedAt,
    };
  });
  const { error } = await db.from("card_catalog_enrichment_jobs").upsert(
    rows,
    { onConflict: "job_key", ignoreDuplicates: true },
  );
  if (error) throw error;
}

export async function runSequentially<T, R>(
  values: readonly T[],
  operation: (value: T, index: number) => Promise<R>,
): Promise<R[]> {
  const results: R[] = [];
  for (let index = 0; index < values.length; index++) {
    results.push(await operation(values[index], index));
  }
  return results;
}

/**
 * Mirrors the database lease RPC for pure policy tests. The RPC remains the
 * authoritative concurrent claim implementation in production.
 */
export function simulateLeaseClaim(
  jobs: readonly LeaseJob[],
  now: Date,
  runMode: RunMode,
  requestedMaximum = MAX_BATCH_SIZE,
): { recoveredIds: string[]; claimed: LeaseJob[] } {
  const timestamp = now.getTime();
  const recoveredIds = jobs
    .filter((job) =>
      job.status === "processing" &&
      job.parserVersion?.trim().toLowerCase() !== "catalog-v1" &&
      (job.leaseExpiresAt === null ||
        Date.parse(job.leaseExpiresAt) <= timestamp)
    )
    .map((job) => job.id);
  const recovered = new Set(recoveredIds);
  const eligible = jobs.filter((job) => {
    const status = recovered.has(job.id) ? "queued" : job.status;
    return job.runMode === runMode &&
      job.parserVersion?.trim().toLowerCase() !== "catalog-v1" &&
      (status === "queued" || status === "failed") &&
      (job.nextRetryAt === null || Date.parse(job.nextRetryAt) <= timestamp);
  }).sort((left, right) =>
    issuerKey(left.issuer).localeCompare(issuerKey(right.issuer)) ||
    left.cardName.localeCompare(right.cardName) ||
    left.id.localeCompare(right.id)
  );
  const selectedIssuer = eligible[0] && issuerKey(eligible[0].issuer);
  const maximum = Math.min(MAX_BATCH_SIZE, Math.max(1, requestedMaximum));
  return {
    recoveredIds,
    claimed: selectedIssuer
      ? eligible.filter((job) => issuerKey(job.issuer) === selectedIssuer)
        .slice(
          0,
          maximum,
        )
      : [],
  };
}

export function findReusableStaging<T extends StagingCandidate>(
  rows: readonly T[],
  identity: StagingIdentity,
): T | undefined {
  return rows.find((row) =>
    row.requestType === "official_benefit_enrichment" &&
    row.cardId === identity.cardId &&
    row.sourceUrl === identity.sourceUrl &&
    row.parserVersion === identity.parserVersion &&
    row.contentHash === identity.contentHash &&
    (row.status === "pending" || row.status === "approved") &&
    row.evidenceSafe
  );
}

async function secretDigest(value: string): Promise<Uint8Array> {
  return new Uint8Array(
    await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value)),
  );
}

export async function secureSecretEqual(
  actual: string | null,
  expected: string,
): Promise<boolean> {
  if (!actual || !expected) return false;
  const [left, right] = await Promise.all([
    secretDigest(actual),
    secretDigest(expected),
  ]);
  let difference = 0;
  for (let index = 0; index < left.length; index++) {
    difference |= left[index] ^ right[index];
  }
  return difference === 0;
}

export function failureDisposition(
  attemptCount: number,
  now = new Date(),
): {
  status: "failed" | "review_required";
  nextRetryAt: string | null;
  retried: boolean;
  retryScheduleMinutes: readonly number[];
} {
  const normalizedAttempt = Math.max(1, Math.trunc(attemptCount));
  if (normalizedAttempt >= 3) {
    return {
      status: "review_required",
      nextRetryAt: null,
      retried: false,
      retryScheduleMinutes: RETRY_SCHEDULE_MINUTES,
    };
  }
  const delay = RETRY_SCHEDULE_MINUTES[normalizedAttempt - 1];
  return {
    status: "failed",
    nextRetryAt: new Date(now.getTime() + delay * 60_000).toISOString(),
    retried: true,
    retryScheduleMinutes: RETRY_SCHEDULE_MINUTES,
  };
}

export function selectPilotCandidates<T extends PilotCandidate>(
  candidates: readonly T[],
): Array<T & { run_mode: "pilot" }> {
  const profiles: PilotProfile[] = [
    "straightforward",
    "redirect_or_js",
    "terms_linked",
    "known_invalid",
    "additional_valid",
  ];
  const eligible = candidates.filter((candidate) =>
    candidate.active &&
    (candidate.profile === "known_invalid" || candidate.approvedUrl)
  );
  const choicesByProfile = profiles.map((profile) =>
    eligible.filter((candidate) => candidate.profile === profile)
      .sort((left, right) => left.id.localeCompare(right.id))
  );
  if (choicesByProfile.some((choices) => choices.length === 0)) return [];

  const search = (profileIndex: number, selected: T[]): T[] | null => {
    if (profileIndex === profiles.length) {
      return new Set(
          selected.map((candidate) => issuerKey(candidate.issuer)),
        ).size >= 3
        ? selected
        : null;
    }
    for (const candidate of choicesByProfile[profileIndex]) {
      if (selected.some((item) => item.id === candidate.id)) continue;
      const result = search(profileIndex + 1, [...selected, candidate]);
      if (result) return result;
    }
    return null;
  };
  const selection = search(0, []);
  return selection
    ? selection.map((candidate) => ({ ...candidate, run_mode: "pilot" }))
    : [];
}

export function evaluatePilotGate(jobs: readonly PilotJob[]): {
  status: PilotStatus;
  scheduledClaimAllowed: boolean;
  blockers: string[];
} {
  const pilot = jobs.filter((job) => job.runMode === "pilot");
  if (pilot.length === 0) {
    return {
      status: "not_started",
      scheduledClaimAllowed: false,
      blockers: ["pilot_not_started"],
    };
  }
  if (pilot.length < 5) {
    return {
      status: "running",
      scheduledClaimAllowed: false,
      blockers: ["pilot_incomplete"],
    };
  }
  const blockers: string[] = [];
  if (pilot.length !== 5) blockers.push("pilot_job_count");
  const hasNonTerminal = pilot.some((job) =>
    job.status !== "staged" && job.status !== "quarantined"
  );
  for (const job of pilot) {
    const terminal = job.status === "staged" || job.status === "quarantined";
    if (job.status === "quarantined" && !job.quarantineReason) {
      blockers.push("unjustified_quarantine");
    }
    if (job.status === "failed") blockers.push("pilot_failed");
    if (job.status === "review_required") {
      blockers.push("pilot_review_required");
    }
    if (job.unsafeMutationCount !== 0) blockers.push("unsafe_mutation");
    if (terminal && !job.idempotencyPassed) blockers.push("idempotency_failed");
    if (job.status === "staged" && !job.evidencePassed) {
      blockers.push("evidence_failed");
    }
    if (job.rawBodyStored) blockers.push("raw_body_stored");
  }
  const uniqueBlockers = [...new Set(blockers)];
  if (hasNonTerminal && uniqueBlockers.length === 0) {
    return {
      status: "running",
      scheduledClaimAllowed: false,
      blockers: ["pilot_incomplete"],
    };
  }
  const status: PilotStatus = uniqueBlockers.length === 0
    ? "passed"
    : "blocked";
  return {
    status,
    scheduledClaimAllowed: status === "passed",
    blockers: uniqueBlockers,
  };
}

export function safeFailureCategory(error: unknown): string {
  const value = error instanceof Error ? error.message : "enrichment_failed";
  const allowed = new Set([
    "not_a_card",
    "ambiguous_product",
    "identity_mismatch",
    "unapproved_domain",
    "unsupported_content",
    "unreachable",
    "insufficient_evidence",
    "redirect_rejected",
    "private_address",
    "oversized",
    "timeout",
  ]);
  return allowed.has(value) ? value : "enrichment_failed";
}
