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

export function buildJobKey(
  cardId: string,
  canonicalUrlHash: string,
  parserVersion: string,
): string {
  return `${cardId}:${canonicalUrlHash}:${parserVersion}`;
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
      (job.leaseExpiresAt === null ||
        Date.parse(job.leaseExpiresAt) <= timestamp)
    )
    .map((job) => job.id);
  const recovered = new Set(recoveredIds);
  const eligible = jobs.filter((job) => {
    const status = recovered.has(job.id) ? "queued" : job.status;
    return job.runMode === runMode &&
      (status === "queued" || status === "failed") &&
      (job.nextRetryAt === null || Date.parse(job.nextRetryAt) <= timestamp);
  }).sort((left, right) =>
    left.issuer.localeCompare(right.issuer) ||
    left.cardName.localeCompare(right.cardName) ||
    left.id.localeCompare(right.id)
  );
  const selectedIssuer = eligible[0]?.issuer;
  const maximum = Math.min(MAX_BATCH_SIZE, Math.max(1, requestedMaximum));
  return {
    recoveredIds,
    claimed: selectedIssuer
      ? eligible.filter((job) => job.issuer === selectedIssuer).slice(
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
    row.contentHash === identity.contentHash
  );
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
  const selection: T[] = [];

  for (const profile of profiles) {
    const choices = eligible.filter((candidate) =>
      candidate.profile === profile &&
      !selection.some((item) => item.id === candidate.id)
    );
    if (choices.length === 0) return [];
    const issuerCounts = new Map<string, number>();
    for (const selected of selection) {
      issuerCounts.set(
        selected.issuer,
        (issuerCounts.get(selected.issuer) ?? 0) + 1,
      );
    }
    choices.sort((left, right) =>
      (issuerCounts.get(left.issuer) ?? 0) -
        (issuerCounts.get(right.issuer) ?? 0) ||
      left.id.localeCompare(right.id)
    );
    selection.push(choices[0]);
  }
  return new Set(selection.map((candidate) => candidate.issuer)).size >= 3
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
