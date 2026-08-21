import {
  applyRemovalPolicy,
  authorizedSchedulerRequest,
  buildCrawlObservation,
  claimIssuerDiscoveryRun,
  claimLimitForInvocation,
  computeSourceManifestHash,
  crawlProposalDisposition,
  currentBenefitProposal,
  initializePilotJobs,
  issuerDiscoveryRunMode,
  loadApprovedIssuerCatalog,
  loadCatalogIdentity,
  loadDiscoverySeed,
  loadIssuerDiscoveryBacklog,
  networkWorkMayStart,
  newestValidCrawlObservations,
  observationValidatedAt,
  persistIssuerRunProgress,
  persistNonProductIssuerOutcome,
  previousFetchValidators,
  processJob,
  promoteQualifiedPilotJobs,
  readCompleteAbsenceHistory,
  readCurrentBenefits,
  readPilotStatus,
  recordIssuerDiscoveryOutcome,
  refreshEligibleCard,
  requeueDueJobs,
  requireExactCatalogIdentity,
  runIssuerDiscovery,
  seedScheduledQueueIfAllowed,
  selectIssuerDiscoveryCandidate,
  shouldStageMaterialProposal,
  sourceObservationReviewSummary,
  sourceObservationSummary,
  stagingContentHashForObservation,
  upsertBoundedIssuerOutcomeSummary,
} from "./index.ts";
import * as batchModule from "./index.ts";
import {
  canonicalBenefitReplayFactEnvelope,
  canonicalBenefitReplayText,
  containsPrivateBenefitData,
  diffBenefits,
  extractGroundedBenefits,
  extractGroundedBenefitsV6,
} from "../_shared/benefit_enrichment.ts";
import { stableCanonicalJson } from "../_shared/benefit_contract.ts";
import { sourceIdentityDigest } from "./crawl_policy.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

async function sha256Fixture(value: unknown): Promise<string> {
  const bytes = new TextEncoder().encode(stableCanonicalJson(value));
  return Array.from(
    new Uint8Array(await crypto.subtle.digest("SHA-256", bytes)),
  )
    .map((part) => part.toString(16).padStart(2, "0")).join("");
}

async function sha256TextFixture(value: string): Promise<string> {
  const bytes = new TextEncoder().encode(value);
  return Array.from(
    new Uint8Array(await crypto.subtle.digest("SHA-256", bytes)),
  )
    .map((part) => part.toString(16).padStart(2, "0")).join("");
}

Deno.test("pilot replay canonicalizes the same immutable documents twice without a second fetch", async () => {
  const compute = task10BatchModule.computePilotReplayEvidence;
  assert(typeof compute === "function", "computed pilot replay is missing");
  const attempts = [{
    url: "https://issuer.example/card",
    role: "primary",
    status: "success",
    httpStatus: 200,
    contentHash: "a".repeat(64),
    finalResourceIdentityHash: sourceIdentityDigest(
      "https://issuer.example/card",
    ),
    attemptedAt: "2026-08-20T00:00:00.000Z",
    logicalSourceKey: sourceIdentityDigest("https://issuer.example/card"),
  }];
  const sourceManifestHash = await computeSourceManifestHash(attempts as never);
  let extractionCount = 0;
  const replay = await compute({
    jobId: "11111111-1111-4111-8111-111111111111",
    cardId: "22222222-2222-4222-8222-222222222222",
    parserVersion: "benefits-v6",
    runMode: "pilot",
    sourceManifestHash,
    expectedRequiredSourceKeys: [],
    requiredSourceSelectionOverflow: false,
    attempts,
    documents: [{
      sourceUrl: "https://issuer.example/card",
      finalUrl: "https://issuer.example/card",
      text: "Get 10% cashback on dining spends.",
      contentHash: "a".repeat(64),
    }],
    extract: async (documents: unknown) => {
      extractionCount += 1;
      return await extractGroundedBenefitsV6(
        structuredClone(documents) as never,
        "benefits-v6",
        "22222222-2222-4222-8222-222222222222",
      );
    },
  });
  assert(extractionCount === 2, "pilot did not run two independent parses");
  assert(
    replay.canonicalHash === replay.repeatCanonicalHash &&
      replay.deterministicReplayPassed,
    "identical retained documents did not replay deterministically",
  );
  assert(
    replay.sourceManifestHash === sourceManifestHash &&
      replay.proposals.length === 1,
    "replay lost its exact source manifest or canonical proposal",
  );
  assert(
    replay.requiredSourceSelectionOverflow === false &&
      replay.verificationEnvelope.required_source_selection_overflow === false,
    "replay omitted the independently computed required-source overflow fact",
  );
  assert(
    replay.verificationEnvelope && replay.repeatVerificationEnvelope &&
      replay.verificationEnvelope !== replay.repeatVerificationEnvelope,
    "pilot replay did not retain two independently recomputable envelopes",
  );
});

Deno.test("pilot replay hash is bound to the exact retained document bytes and resource identities", async () => {
  const compute = task10BatchModule.computePilotReplayEvidence;
  assert(typeof compute === "function", "computed pilot replay is missing");
  const run = async (text: string, finalUrl: string) => {
    const attempts = [{
      url: finalUrl,
      role: "primary",
      status: "success",
      httpStatus: 200,
      contentHash: "a".repeat(64),
      finalResourceIdentityHash: sourceIdentityDigest(finalUrl),
      attemptedAt: "2026-08-20T00:00:00.000Z",
      logicalSourceKey: sourceIdentityDigest("https://issuer.example/card"),
    }];
    return await compute({
      jobId: "11111111-1111-4111-8111-111111111111",
      cardId: "22222222-2222-4222-8222-222222222222",
      parserVersion: "benefits-v6",
      runMode: "pilot",
      sourceManifestHash: await computeSourceManifestHash(attempts as never),
      expectedRequiredSourceKeys: [],
      requiredSourceSelectionOverflow: false,
      attempts,
      documents: [{
        sourceUrl: "https://issuer.example/card",
        finalUrl,
        text,
        contentHash: "a".repeat(64),
      }],
      extract: async () => [{ fixture: "same-proposal" }],
    });
  };
  const first = await run(
    "Get 10% cashback on original issuer spends.",
    "https://issuer.example/card",
  );
  const changedBytes = await run(
    "Get 11% cashback on changed issuer spends.",
    "https://issuer.example/card",
  );
  const changedIdentity = await run(
    "Get 10% cashback on original issuer spends.",
    "https://issuer.example/card/redirected",
  );
  assert(
    first.canonicalHash !== changedBytes.canonicalHash,
    "changed retained bytes reused replay proof",
  );
  assert(
    first.canonicalHash !== changedIdentity.canonicalHash,
    "changed final resource identity reused replay proof",
  );
  assert(
    Array.isArray(first.verificationEnvelope.retained_documents),
    "bounded retained document envelope is absent",
  );
  assert(
    !JSON.stringify(first.verificationEnvelope).includes(
      "Get 10% cashback on original issuer spends.",
    ),
    "raw retained document bytes entered evidence",
  );
});

Deno.test("pilot safety validation is an explicit pre-write boundary", () => {
  const assertSafe = task10BatchModule.assertSafePersistedEvidence;
  assert(
    typeof assertSafe === "function",
    "pre-write safety boundary is missing",
  );
  assertSafe!({ source_excerpt: "fee waiver applies" });
  for (
    const unsafe of [
      { source_excerpt: "Authorization: Bearer abcdefgh.secret" },
      { evidence: { customer_email: "person@example.com" } },
      { source_excerpt: encodeURIComponent("access_token=abcdefgh-secret") },
      {
        replay_input: {
          public_text: encodeURIComponent(
            "customer_email=person@example.com",
          ),
        },
      },
      { proposal: { description: "Email john.doe@example.com for approval" } },
      { proposal: { description: "Pay with 4111-1111-1111-1111" } },
      { proposal: { description: "Call +91 98765 43210" } },
      { proposal: { description: "Account ID: 1234567890123456" } },
      { proposal: { description: "Customer Name: Rahul Sharma" } },
      { proposal: { description: "Rahul Sharma gets 10% cashback" } },
      { proposal: { description: "Name: John gets 10% cashback" } },
      { proposal: { description: "john gets 10% cashback" } },
      { proposal: { description: "JOHN gets 10% cashback" } },
      { proposal: { description: "JOhN receives rewards" } },
      { proposal: { description: "Phone 123.456.7890" } },
      { proposal: { description: "PAN ABCDE1234F" } },
      {
        proposal: {
          description: "Reference 12345678901234567890 gets 10% cashback",
        },
      },
      {
        replay_input: {
          hyperlinks: [{ anchor_text: "John Doe", href: "terms" }],
        },
      },
    ]
  ) {
    let error: unknown;
    try {
      assertSafe!(unsafe);
    } catch (caught) {
      error = caught;
    }
    assert(
      error instanceof Error,
      "unsafe persisted evidence passed the pre-write boundary",
    );
  }
});

Deno.test("pilot replay fails closed when the independent second parse mutates order or terms", async () => {
  const compute = task10BatchModule.computePilotReplayEvidence;
  assert(typeof compute === "function", "computed pilot replay is missing");
  const attempts = [{
    url: "https://issuer.example/card",
    role: "primary",
    status: "success",
    httpStatus: 200,
    contentHash: "a".repeat(64),
    finalResourceIdentityHash: sourceIdentityDigest(
      "https://issuer.example/card",
    ),
    attemptedAt: "2026-08-20T00:00:00.000Z",
    logicalSourceKey: sourceIdentityDigest("https://issuer.example/card"),
  }];
  const sourceManifestHash = await computeSourceManifestHash(attempts as never);
  let pass = 0;
  const replay = await compute({
    jobId: "11111111-1111-4111-8111-111111111111",
    cardId: "22222222-2222-4222-8222-222222222222",
    parserVersion: "benefits-v6",
    runMode: "pilot",
    sourceManifestHash,
    expectedRequiredSourceKeys: [],
    requiredSourceSelectionOverflow: false,
    attempts,
    documents: [{
      sourceUrl: "https://issuer.example/card",
      text:
        "Get 10% cashback on dining spends. Get 5% cashback on fuel spends.",
      contentHash: "a".repeat(64),
    }],
    extract: async (documents: unknown) => {
      const proposals = await extractGroundedBenefitsV6(
        structuredClone(documents) as never,
        "benefits-v6",
        "22222222-2222-4222-8222-222222222222",
      );
      pass += 1;
      return pass === 1
        ? proposals
        : proposals.toReversed().map((proposal, index) =>
          index === 0 ? { ...proposal, rate: 99 } : proposal
        );
    },
  });
  assert(
    replay.canonicalHash !== replay.repeatCanonicalHash &&
      !replay.deterministicReplayPassed,
    "nondeterministic replay was accepted",
  );
});

Deno.test("pilot replay rejects retained input overflow instead of silently truncating evidence", async () => {
  const compute = task10BatchModule.computePilotReplayEvidence;
  assert(typeof compute === "function", "computed pilot replay is missing");
  const attempts = [{
    url: "https://issuer.example/card",
    role: "primary",
    status: "success",
    httpStatus: 200,
    contentHash: "a".repeat(64),
    finalResourceIdentityHash: "b".repeat(64),
    attemptedAt: "2026-08-20T00:00:00.000Z",
    logicalSourceKey: sourceIdentityDigest("https://issuer.example/card"),
  }];
  let error: unknown;
  try {
    await compute({
      jobId: "11111111-1111-4111-8111-111111111111",
      cardId: "22222222-2222-4222-8222-222222222222",
      parserVersion: "benefits-v6",
      runMode: "pilot",
      sourceManifestHash: await computeSourceManifestHash(attempts as never),
      expectedRequiredSourceKeys: [],
      requiredSourceSelectionOverflow: false,
      attempts,
      documents: Array.from({ length: 10 }, (_, index) => ({
        sourceUrl: `https://issuer.example/card/${index}`,
        text: "Get 10% cashback on dining spends.",
        contentHash: "a".repeat(64),
      })),
    });
  } catch (caught) {
    error = caught;
  }
  assert(
    error instanceof Error && error.message === "pilot_evidence_unbounded",
    "pilot replay silently truncated its retained evidence",
  );
});

Deno.test("pilot replay scans every relevant source fact and never qualifies a sliced tail", async () => {
  const compute = task10BatchModule.computePilotReplayEvidence;
  assert(typeof compute === "function", "computed pilot replay is missing");
  const sourceUrl = "https://issuer.example/card";
  const sourceKey = sourceIdentityDigest(sourceUrl);
  const attempts = [{
    url: sourceUrl,
    role: "primary",
    status: "success",
    httpStatus: 200,
    contentHash: "a".repeat(64),
    finalResourceIdentityHash: sourceKey,
    attemptedAt: "2026-08-20T00:00:00.000Z",
    logicalSourceKey: sourceKey,
  }];
  const earlyFacts = Array.from(
    { length: 30 },
    (_, index) =>
      `Benefit ${index}: Earn ${
        index + 1
      }% cashback on dining spends after a qualifying monthly purchase of INR ${
        index + 100
      }.`,
  ).join(" ");
  const lateFact = "Late benefit: Earn 17% cashback on international travel.";
  const seenReplayText: string[] = [];
  await compute({
    jobId: "11111111-1111-4111-8111-111111111111",
    cardId: "22222222-2222-4222-8222-222222222222",
    parserVersion: "benefits-v6",
    runMode: "pilot",
    sourceManifestHash: await computeSourceManifestHash(attempts as never),
    expectedRequiredSourceKeys: [],
    requiredSourceSelectionOverflow: false,
    attempts,
    documents: [{
      sourceUrl,
      finalUrl: sourceUrl,
      text: `${earlyFacts} ${lateFact}`,
      contentHash: "a".repeat(64),
    }],
    extract: async (documents: Array<{ text: string }>) => {
      seenReplayText.push(documents[0].text);
      return [{ fixture: "all-facts" }];
    },
  });
  assert(
    seenReplayText.length === 2 &&
      seenReplayText.every((text) => text.includes(lateFact)),
    "a late benefit-relevant sentence was silently sliced from replay",
  );
});

Deno.test("pilot replay retains late rival-card ambiguity", async () => {
  const compute = task10BatchModule.computePilotReplayEvidence;
  assert(typeof compute === "function", "computed pilot replay is missing");
  const sourceUrl = "https://issuer.example/card";
  const sourceKey = sourceIdentityDigest(sourceUrl);
  const attempts = [{
    url: sourceUrl,
    role: "primary",
    status: "success",
    httpStatus: 200,
    contentHash: "a".repeat(64),
    finalResourceIdentityHash: sourceKey,
    attemptedAt: "2026-08-20T00:00:00.000Z",
    logicalSourceKey: sourceKey,
  }];
  const binding = {
    jobId: "11111111-1111-4111-8111-111111111111",
    cardId: "22222222-2222-4222-8222-222222222222",
    parserVersion: "benefits-v6",
    runMode: "pilot",
    sourceManifestHash: await computeSourceManifestHash(attempts as never),
    expectedRequiredSourceKeys: [],
    requiredSourceSelectionOverflow: false,
    issuer: "Issuer Example",
    identityLabels: ["Issuer Example Card"],
    primarySourceUrl: sourceUrl,
    attempts,
  };
  const filler = Array.from(
    { length: 14 },
    (_, index) =>
      `Issuer Example Card benefit ${index}: Earn ${
        index + 1
      }% cashback on qualifying dining and travel spends.`,
  ).join(" ");
  let ambiguityError: unknown;
  try {
    await compute({
      ...binding,
      documents: [{
        sourceUrl,
        text: `${filler} Rival Bank Other Card.`,
        contentHash: "a".repeat(64),
      }],
      extract: async () => [{ fixture: "ambiguity" }],
    });
  } catch (error) {
    ambiguityError = error;
  }
  assert(
    ambiguityError instanceof Error &&
      ambiguityError.message === "pilot_card_identity_mismatch",
    "late rival-card ambiguity disappeared from the replay classifier",
  );
});

Deno.test("pilot replay fails explicit fact overflow instead of slicing a relevant fragment", async () => {
  const compute = task10BatchModule.computePilotReplayEvidence;
  assert(typeof compute === "function", "computed pilot replay is missing");
  const sourceUrl = "https://issuer.example/card";
  const sourceKey = sourceIdentityDigest(sourceUrl);
  const attempts = [{
    url: sourceUrl,
    role: "primary",
    status: "success",
    httpStatus: 200,
    contentHash: "a".repeat(64),
    finalResourceIdentityHash: sourceKey,
    attemptedAt: "2026-08-20T00:00:00.000Z",
    logicalSourceKey: sourceKey,
  }];
  let overflowError: unknown;
  try {
    await compute({
      jobId: "11111111-1111-4111-8111-111111111111",
      cardId: "22222222-2222-4222-8222-222222222222",
      parserVersion: "benefits-v6",
      runMode: "pilot",
      sourceManifestHash: await computeSourceManifestHash(attempts as never),
      expectedRequiredSourceKeys: [],
      requiredSourceSelectionOverflow: false,
      issuer: "Issuer Example",
      identityLabels: ["Issuer Example Card"],
      primarySourceUrl: sourceUrl,
      attempts,
      documents: [{
        sourceUrl,
        text: `Issuer Example Card. Earn 10% cashback ${"x".repeat(9_000)}.`,
        contentHash: "a".repeat(64),
      }],
      extract: async () => [{ fixture: "overflow" }],
    });
  } catch (error) {
    overflowError = error;
  }
  assert(
    overflowError instanceof Error &&
      overflowError.message === "pilot_replay_fact_overflow",
    "an oversized relevant fact was sliced and qualified without overflow",
  );
});

Deno.test("pilot replay retains only bounded privacy-safe classifier facts", async () => {
  const compute = task10BatchModule.computePilotReplayEvidence;
  assert(typeof compute === "function", "computed pilot replay is missing");
  const attempts = [{
    url: "https://issuer.example/card",
    role: "primary",
    status: "success",
    httpStatus: 200,
    contentHash: "a".repeat(64),
    finalResourceIdentityHash: sourceIdentityDigest(
      "https://issuer.example/card",
    ),
    attemptedAt: "2026-08-20T00:00:00.000Z",
    logicalSourceKey: sourceIdentityDigest("https://issuer.example/card"),
  }];
  const longPublicText = `${"Unrelated issuer boilerplate. ".repeat(400)}
Issuer Example Card. Get 10% cashback on dining spends.
Email john.doe@example.com. Pay with 4111 1111 1111 1111.
Call +91 98765 43210. Customer ID: 1234567890123456.
Relationship manager Amit Kumar Sharma will call.`;
  const replay = await compute({
    jobId: "11111111-1111-4111-8111-111111111111",
    cardId: "22222222-2222-4222-8222-222222222222",
    parserVersion: "benefits-v6",
    runMode: "pilot",
    sourceManifestHash: await computeSourceManifestHash(attempts as never),
    expectedRequiredSourceKeys: [],
    requiredSourceSelectionOverflow: false,
    issuer: "Issuer Example",
    identityLabels: ["Issuer Example Card"],
    primarySourceUrl: "https://issuer.example/card",
    attempts,
    documents: [{
      sourceUrl: "https://issuer.example/card",
      text: longPublicText,
      contentHash: "a".repeat(64),
    }],
  });
  assert(
    replay.proposals.length === 1 &&
      new TextEncoder().encode(
          (replay as any).replayInput.documents[0]
            .public_text,
        ).byteLength < 2_000,
    "pilot replay retained arbitrary page prose instead of minimal facts",
  );
  const retained = String(
    (replay as any).replayInput.documents[0].public_text,
  );
  for (
    const unsafe of [
      "john.doe@example.com",
      "4111 1111 1111 1111",
      "+91 98765 43210",
      "1234567890123456",
      "Amit Kumar Sharma",
      "Unrelated issuer boilerplate",
    ]
  ) {
    assert(
      !retained.includes(unsafe),
      `replay retained unsafe prose: ${unsafe}`,
    );
  }
  assert(
    retained.includes("Issuer Example Card") &&
      retained.includes("10% cashback"),
    "privacy minimization removed known card identity or benefit facts",
  );
});

Deno.test("pilot replay reruns required-link and card-identity classifiers from retained inputs", async () => {
  const compute = task10BatchModule.computePilotReplayEvidence;
  assert(typeof compute === "function", "computed pilot replay is missing");
  const primaryUrl = "https://issuer.example/card";
  const termsUrl = "https://issuer.example/support/card-terms.pdf?locale=en";
  const primaryKey = sourceIdentityDigest(primaryUrl);
  const termsKey = sourceIdentityDigest(termsUrl);
  const attempts = [{
    url: primaryUrl,
    role: "primary",
    status: "success",
    httpStatus: 200,
    contentHash: "a".repeat(64),
    finalResourceIdentityHash: primaryKey,
    attemptedAt: "2026-08-20T00:00:00.000Z",
    logicalSourceKey: primaryKey,
  }, {
    url: "https://issuer.example/support/card-terms.pdf",
    role: "required_supporting",
    status: "success",
    httpStatus: 200,
    contentHash: "b".repeat(64),
    finalResourceIdentityHash: termsKey,
    attemptedAt: "2026-08-20T00:00:01.000Z",
    logicalSourceKey: termsKey,
  }];
  const documents = [{
    sourceUrl: primaryUrl,
    finalUrl: primaryUrl,
    text: "Issuer Example Card. Get 10% cashback on dining spends.",
    contentHash: "a".repeat(64),
    replayLinks: [{
      href: termsUrl,
      anchorText: "Terms John Doe",
    }],
  }, {
    sourceUrl: termsUrl,
    finalUrl: termsUrl,
    text: "Issuer Example Card MITC. Dining cashback is 10%.",
    contentHash: "b".repeat(64),
  }];
  const binding = {
    jobId: "11111111-1111-4111-8111-111111111111",
    cardId: "22222222-2222-4222-8222-222222222222",
    parserVersion: "benefits-v6",
    runMode: "pilot",
    issuer: "Issuer Example",
    identityLabels: ["Issuer Example Card"],
    primarySourceUrl: primaryUrl,
    requiredSourceSelectionOverflow: false,
  };
  const replay = await compute({
    ...binding,
    sourceManifestHash: await computeSourceManifestHash(attempts as never),
    expectedRequiredSourceKeys: [termsKey],
    attempts,
    documents,
  });
  const replayInput = (replay as any).replayInput;
  assert(replayInput?.version === 3, "classifier-capable replay v3 is absent");
  assert(
    !("required_resources" in replayInput),
    "replay copied classifier output instead of retaining classifier input",
  );
  assert(
    replayInput.context?.issuer === "Issuer Example" &&
      replayInput.context?.identity_labels?.[0] === "Issuer Example Card",
    "replay lost known issuer/card identity context",
  );
  const retainedLink = replayInput.documents[0].hyperlinks[0];
  assert(
    retainedLink.href === "https://issuer.example/support/card-terms.pdf" &&
      !retainedLink.href.includes("?") &&
      retainedLink.resource_identity_hash === termsKey &&
      retainedLink.anchor_text === "terms",
    "replay retained query/anchor PII or lost the opaque required-link identity",
  );

  const redirectedTermsUrl =
    "https://issuer.example/support/current-card-terms.pdf";
  const redirectedAttempts = structuredClone(attempts);
  redirectedAttempts[1].url = redirectedTermsUrl;
  redirectedAttempts[1].finalResourceIdentityHash = sourceIdentityDigest(
    redirectedTermsUrl,
  );
  const redirectedDocuments: any[] = structuredClone(documents);
  redirectedDocuments[1].finalUrl = redirectedTermsUrl;
  redirectedDocuments[1].finalResourceIdentityHash = sourceIdentityDigest(
    redirectedTermsUrl,
  );
  const redirected = await compute({
    ...binding,
    sourceManifestHash: await computeSourceManifestHash(
      redirectedAttempts as never,
    ),
    expectedRequiredSourceKeys: [termsKey],
    attempts: redirectedAttempts,
    documents: redirectedDocuments,
  });
  assert(
    redirected.deterministicReplayPassed === true,
    "exact requested/final resource bindings rejected a legitimate redirect",
  );

  let omittedError: unknown;
  try {
    const omittedAttempts = attempts.slice(0, 1);
    await compute({
      ...binding,
      sourceManifestHash: await computeSourceManifestHash(
        omittedAttempts as never,
      ),
      expectedRequiredSourceKeys: [],
      attempts: omittedAttempts,
      documents: documents.slice(0, 1),
    });
  } catch (error) {
    omittedError = error;
  }
  assert(
    omittedError instanceof Error &&
      omittedError.message === "pilot_required_source_classification_mismatch",
    "a consistently omitted required link passed replay classification",
  );

  let borrowedIdentityError: unknown;
  try {
    await compute({
      ...binding,
      sourceManifestHash: await computeSourceManifestHash(attempts as never),
      expectedRequiredSourceKeys: [termsKey],
      attempts,
      documents: [{
        ...documents[0],
        replayLinks: [{
          href: "https://issuer.example/support/other-terms.pdf",
          anchorText: "Terms and Conditions",
          resourceIdentityHash: termsKey,
        }],
      }, documents[1]],
    });
  } catch (error) {
    borrowedIdentityError = error;
  }
  assert(
    borrowedIdentityError instanceof Error &&
      [
        "pilot_required_source_classification_mismatch",
        "pilot_replay_source_binding_mismatch",
      ].includes(borrowedIdentityError.message),
    "a replay hyperlink borrowed another required attempt's opaque identity",
  );

  let identityError: unknown;
  try {
    await compute({
      ...binding,
      sourceManifestHash: await computeSourceManifestHash(attempts as never),
      expectedRequiredSourceKeys: [termsKey],
      attempts,
      documents: documents.map((document) => ({
        ...document,
        text: "Rival Bank Other Card. Get 10% cashback on dining spends.",
      })),
    });
  } catch (error) {
    identityError = error;
  }
  assert(
    identityError instanceof Error &&
      identityError.message === "pilot_card_identity_mismatch",
    "replay did not rerun the actual card identity classifier",
  );
});

Deno.test("pilot replay persists canonical functional resources and recomputes every opaque identity", async () => {
  const compute = task10BatchModule.computePilotReplayEvidence;
  assert(typeof compute === "function", "computed pilot replay is missing");
  const primaryUrl = "https://issuer.example/card";
  const rawTermsUrl =
    "https://issuer.example/terms.pdf?document=mitc.pdf&locale=en&version=2&locale=hi&utm_source=campaign";
  const canonicalTermsUrl =
    "https://issuer.example/terms.pdf?document=mitc.pdf&locale=en&version=2&locale=hi";
  const primaryKey = sourceIdentityDigest(primaryUrl);
  const termsKey = sourceIdentityDigest(canonicalTermsUrl);
  const attempts = [{
    url: primaryUrl,
    role: "primary",
    status: "success",
    httpStatus: 200,
    contentHash: "a".repeat(64),
    finalResourceIdentityHash: primaryKey,
    attemptedAt: "2026-08-20T00:00:00.000Z",
    logicalSourceKey: primaryKey,
  }, {
    url: "https://issuer.example/terms.pdf",
    role: "required_supporting",
    status: "success",
    httpStatus: 200,
    contentHash: "b".repeat(64),
    finalResourceIdentityHash: termsKey,
    attemptedAt: "2026-08-20T00:00:01.000Z",
    logicalSourceKey: termsKey,
  }];
  const replay = await compute({
    jobId: "11111111-1111-4111-8111-111111111111",
    cardId: "22222222-2222-4222-8222-222222222222",
    parserVersion: "benefits-v6",
    runMode: "pilot",
    sourceManifestHash: await computeSourceManifestHash(attempts as never),
    expectedRequiredSourceKeys: [termsKey],
    requiredSourceSelectionOverflow: false,
    issuer: "Issuer Example",
    identityLabels: ["Issuer Example Card"],
    primarySourceUrl: primaryUrl,
    attempts,
    documents: [{
      sourceUrl: primaryUrl,
      requestedResourceIdentityHash: "c".repeat(64),
      finalResourceIdentityHash: "d".repeat(64),
      text: "Issuer Example Card. Earn 10% cashback.",
      contentHash: "a".repeat(64),
      replayLinks: [{
        href: rawTermsUrl,
        anchorText: "Terms",
        resourceIdentityHash: "f".repeat(64),
      }],
    }, {
      sourceUrl: canonicalTermsUrl,
      finalUrl: canonicalTermsUrl,
      requestedResourceIdentityHash: "e".repeat(64),
      finalResourceIdentityHash: "f".repeat(64),
      text: "Issuer Example Card terms. Earn 10% cashback.",
      contentHash: "b".repeat(64),
    }],
    extract: async () => [{ fixture: "functional-query" }],
  });
  const replayInput = (replay as any).replayInput;
  const link = replayInput.documents[0].hyperlinks[0];
  const termsDocument = replayInput.documents[1];
  assert(
    replayInput.version === 3 &&
      link.href === "https://issuer.example/terms.pdf" &&
      link.resource_url === canonicalTermsUrl &&
      link.resource_identity_hash === termsKey &&
      link.query_policy === "functional_only" &&
      termsDocument.requested_resource_url === canonicalTermsUrl &&
      termsDocument.requested_resource_identity_hash === termsKey &&
      termsDocument.final_resource_identity_hash === termsKey &&
      termsDocument.privacy_normalized === true,
    "replay trusted supplied digests or lost the exact approved functional resource",
  );
});

Deno.test("pilot replay rejects sensitive or unknown functional query keys", async () => {
  const compute = task10BatchModule.computePilotReplayEvidence;
  assert(typeof compute === "function", "computed pilot replay is missing");
  const primaryUrl = "https://issuer.example/card";
  const primaryKey = sourceIdentityDigest(primaryUrl);
  for (
    const rejectedUrl of [
      "https://issuer.example/terms.pdf?token=secret",
      "https://issuer.example/terms.pdf?product=platinum",
      "https://issuer.example/terms.pdf?variant=platinum",
      "https://issuer.example/terms.pdf?lo%63ale=en",
      "https://issuer.example/terms.pdf?document=secret",
      "https://issuer.example/terms.pdf?file=access_token%3Dsecret",
      "https://issuer.example/terms.pdf?version=1234567890123456",
    ]
  ) {
    const rejectedKey = sourceIdentityDigest(rejectedUrl);
    const attempts = [{
      url: primaryUrl,
      role: "primary",
      status: "success",
      httpStatus: 200,
      contentHash: "a".repeat(64),
      finalResourceIdentityHash: primaryKey,
      attemptedAt: "2026-08-20T00:00:00.000Z",
      logicalSourceKey: primaryKey,
    }, {
      url: "https://issuer.example/terms.pdf",
      role: "required_supporting",
      status: "failed",
      errorCode: "unapproved_query",
      attemptedAt: "2026-08-20T00:00:01.000Z",
      logicalSourceKey: rejectedKey,
    }];
    let error: unknown;
    try {
      await compute({
        jobId: "11111111-1111-4111-8111-111111111111",
        cardId: "22222222-2222-4222-8222-222222222222",
        parserVersion: "benefits-v6",
        runMode: "pilot",
        sourceManifestHash: await computeSourceManifestHash(attempts as never),
        expectedRequiredSourceKeys: [rejectedKey],
        requiredSourceSelectionOverflow: false,
        attempts,
        documents: [{
          sourceUrl: primaryUrl,
          text: "Issuer Example Card. Earn 10% cashback.",
          contentHash: "a".repeat(64),
          replayLinks: [{ href: rejectedUrl, anchorText: "Terms" }],
        }],
        extract: async () => [{ fixture: "unsafe-query" }],
      });
    } catch (caught) {
      error = caught;
    }
    assert(
      error instanceof Error && error.message === "unapproved_query",
      `replay accepted an unapproved resource query: ${rejectedUrl}`,
    );
  }
});

Deno.test("canonical pilot replay text removes direct official-source PII probes", () => {
  const sanitize = canonicalBenefitReplayText as unknown as (
    value: string,
    context: { issuer: string; identityLabels: string[] },
  ) => string;
  const safe = sanitize(
    `Issuer Example Card. Get 10% cashback on dining spends.
Email: jane.smith@example.com
PAN 4111-1111-1111-1111; phone +91 98765 43210.
Account number 1234567890123456. Customer Name: Priya Sharma.
Relationship manager Arjun Kumar Singh will call.
Rahul Sharma gets this cashback.
Name: John gets 10% cashback. Phone 123.456.7890.
PAN ABCDE1234F receives rewards. john gets 10% cashback.
Reference 12345678901234567890 gets rewards.
JOHN gets 10% cashback. JOhN receives rewards.`,
    { issuer: "Issuer Example", identityLabels: ["Issuer Example Card"] },
  );
  assert(
    safe.includes("Issuer Example Card") && safe.includes("10% cashback"),
    "privacy minimization removed known identity or benefit facts",
  );
  for (
    const unsafe of [
      "jane.smith@example.com",
      "4111-1111-1111-1111",
      "+91 98765 43210",
      "1234567890123456",
      "Priya Sharma",
      "Arjun Kumar Singh",
      "Rahul Sharma",
      "Name: John",
      "123.456.7890",
      "ABCDE1234F",
      "john gets",
      "12345678901234567890",
      "JOHN gets",
      "JOhN receives",
    ]
  ) assert(!safe.includes(unsafe), `official-source replay leaked ${unsafe}`);
});

Deno.test("pilot privacy normalizes nested encodings Unicode digits and confusable person spans", () => {
  const assertSafe = task10BatchModule
    .assertSafePersistedEvidence as unknown as (
      value: unknown,
      context?: { issuer?: string; identityLabels?: string[] },
    ) => void;
  const nested = Array.from({ length: 6 }).reduce<string>(
    (value) => encodeURIComponent(value),
    "ALICE gets 10% cashback",
  );
  for (
    const unsafe of [
      nested,
      "&#x41;&#x4c;&#x49;&#x43;&#x45; gets 10% cashback",
      "AL\u200BICE receives rewards",
      "Ｒａｈｕｌ Ｓｈａｒｍａ gets 10% cashback",
      "Rаhul Šarma receives rewards",
      "Email ａｌｉｃｅ＠example.com",
      "Phone ＋９１ ９８７６５ ４３２１０",
      "Account ID १२३४५६७८९०१२३४५६",
    ]
  ) {
    let error: unknown;
    try {
      assertSafe({ proposal: { description: unsafe } });
    } catch (caught) {
      error = caught;
    }
    assert(
      error instanceof Error,
      `normalized privacy probe survived: ${unsafe}`,
    );
  }
  assertSafe(
    {
      proposal: {
        description:
          "American Express Platinum Card. American Express gets 10% cashback.",
      },
    },
    {
      issuer: "American Express",
      identityLabels: ["American Express Platinum Card"],
    },
  );
});

Deno.test("replay facts fail closed on private relevant prose without dropping safe headings", () => {
  const privateFacts = canonicalBenefitReplayFactEnvelope(
    "Alice gets 10% cashback. Cardholders get 5% cashback.",
    { issuer: "Issuer Example", identityLabels: ["Issuer Example Card"] },
  );
  assert(
    privateFacts.factOverflow,
    "a private benefit fact was silently omitted without blocking replay",
  );
  assert(
    privateFacts.publicText.includes("Cardholders get 5% cashback"),
    "a safe fact disappeared with the private fact",
  );

  const headings = canonicalBenefitReplayFactEnvelope(
    [
      "Get Complimentary Lounge Access.",
      "Earn Reward Points on Dining.",
      "Welcome Bonus Rewards.",
      "Exclusive Dining Offers.",
      "Reward Points Program.",
      "Zero Fuel Surcharge.",
      "Travel Insurance Cover.",
      "Discount Miles and Movie Tickets.",
      "APR Interest and Forex Markup.",
      "Milestone Spend Threshold and Renewal Waiver.",
    ].join(" "),
  );
  assert(!headings.factOverflow, "safe commercial headings looked private");
  assert(
    headings.publicText.includes("Get Complimentary Lounge Access") &&
      headings.publicText.includes("Earn Reward Points on Dining"),
    "safe commercial headings were silently omitted",
  );

  const footer = canonicalBenefitReplayFactEnvelope(
    "<main>Get 10% cashback on dining.</main><footer>&copy; 2026 Issuer Example</footer>",
  );
  assert(!footer.factOverflow, "an irrelevant copyright footer blocked replay");
  assert(
    footer.publicText.includes("10% cashback"),
    "a benign HTML footer erased the relevant benefit fact",
  );
});

Deno.test("an all-private relevant document reports explicit replay overflow", async () => {
  const compute = task10BatchModule.computePilotReplayEvidence;
  assert(typeof compute === "function", "computed pilot replay is missing");
  const sourceUrl = "https://issuer.example/card";
  const sourceKey = sourceIdentityDigest(sourceUrl);
  const attempts = [{
    url: sourceUrl,
    role: "primary",
    status: "success",
    httpStatus: 200,
    contentHash: "a".repeat(64),
    finalResourceIdentityHash: sourceKey,
    attemptedAt: "2026-08-20T00:00:00.000Z",
    logicalSourceKey: sourceKey,
  }];
  let overflowError: unknown;
  try {
    await compute({
      jobId: "11111111-1111-4111-8111-111111111111",
      cardId: "22222222-2222-4222-8222-222222222222",
      parserVersion: "benefits-v6",
      runMode: "pilot",
      sourceManifestHash: await computeSourceManifestHash(attempts as never),
      expectedRequiredSourceKeys: [],
      requiredSourceSelectionOverflow: false,
      issuer: "Issuer Example",
      identityLabels: ["Issuer Example Card"],
      primarySourceUrl: sourceUrl,
      attempts,
      documents: [{
        sourceUrl,
        text: "Alice gets 10% cashback.",
        contentHash: "a".repeat(64),
      }],
      extract: async () => [],
    });
  } catch (error) {
    overflowError = error;
  }
  assert(
    overflowError instanceof Error &&
      overflowError.message === "pilot_replay_fact_overflow",
    "all-private replay failed with an unrelated persistence error",
  );
});

Deno.test("privacy allowlists only exact issuer and product phrases", () => {
  const context = {
    issuer: "State Bank of India",
    identityLabels: ["State Bank of India Card"],
  };
  assert(
    !containsPrivateBenefitData(
      "State Bank of India gets 10% cashback",
      context,
    ),
    "the exact public issuer phrase was rejected",
  );
  assert(
    containsPrivateBenefitData("India gets 10% cashback", context),
    "an arbitrary identity substring was allowlisted",
  );
  assert(
    containsPrivateBenefitData("АLІСЕ gets 10% cashback", context),
    "a Ukrainian-I confusable person name bypassed privacy",
  );
  for (
    const unsafe of [
      "Rahul शर्मा gets 10% cashback",
      "राहुल शर्मा gets 10% cashback",
      "Cashback for Alice is 10%",
      "Alic&eacute; gets 10% cashback",
      "Phone \u{1E951}\u{1E952}\u{1E953}\u{1E954}\u{1E955}\u{1E956}\u{1E957}\u{1E958}\u{1E959}\u{1E950}",
    ]
  ) {
    assert(
      containsPrivateBenefitData(unsafe, context),
      `a Unicode or contextual person span bypassed privacy: ${unsafe}`,
    );
  }
});

Deno.test("contextual person spans are case-insensitive while exact catalog identities remain public", () => {
  const issuerExample = {
    issuer: "Issuer Example",
    identityLabels: ["Issuer Example Card"],
  };
  const americanExpress = {
    issuer: "American Express",
    identityLabels: ["American Express Platinum Card"],
  };
  for (
    const [safe, context] of [
      ["Issuer Example Card gets 10% cashback", issuerExample],
      [
        "American Express Platinum Card gets 10% cashback",
        americanExpress,
      ],
    ] as const
  ) {
    assert(
      !containsPrivateBenefitData(safe, context),
      `an exact catalog identity was split into a private person span: ${safe}`,
    );
    assert(
      !canonicalBenefitReplayFactEnvelope(safe, context).factOverflow,
      `an exact catalog identity overflowed replay: ${safe}`,
    );
  }
  assert(
    containsPrivateBenefitData(
      "NotAmerican Express Platinum Card gets 10% cashback",
      americanExpress,
    ),
    "a known identity substring was masked without exact word boundaries",
  );

  const assertSafe = task10BatchModule.assertSafePersistedEvidence as (
    value: unknown,
    context?: { issuer?: string; identityLabels?: readonly string[] },
  ) => void;
  for (
    const unsafe of [
      "Cashback for alice smith is 10%",
      "Reward points to rAhUl shArMa",
      "10% cashback for ALICE SMITH",
      "Miles to राहुल शर्मा",
      "Cashback for অর্ণব সেন is 10%",
    ]
  ) {
    assert(
      containsPrivateBenefitData(unsafe, issuerExample),
      `a lower, mixed, all-caps, or Unicode contextual name survived: ${unsafe}`,
    );
    assert(
      canonicalBenefitReplayFactEnvelope(unsafe, issuerExample).factOverflow,
      `a contextual person span entered replay: ${unsafe}`,
    );
    let persistedError: unknown;
    try {
      assertSafe({ proposal: { description: unsafe } }, issuerExample);
    } catch (error) {
      persistedError = error;
    }
    assert(
      persistedError instanceof Error &&
        persistedError.message === "unsafe_persisted_evidence",
      `generic persistence accepted a contextual person span: ${unsafe}`,
    );
  }
  assert(
    !containsPrivateBenefitData(
      "Cashback for airport access is 10%",
      issuerExample,
    ),
    "commercial contextual words were misclassified as a person",
  );
  for (
    const safe of [
      "Offer valid for 12 months.",
      "Earn 5 points for ₹150 spent.",
    ]
  ) {
    assert(
      !containsPrivateBenefitData(safe, issuerExample),
      `a numeric commercial span was misclassified as a person: ${safe}`,
    );
  }
});

Deno.test("pilot source binding preserves exact requested and redirected resource identities", async () => {
  const compute = task10BatchModule.computePilotReplayEvidence;
  assert(typeof compute === "function", "computed pilot replay is missing");
  const primaryUrl = "https://issuer.example/card";
  const requestedTermsUrl = "https://issuer.example/terms.pdf";
  const finalTermsUrl = "https://issuer.example/current-terms.pdf";
  const requestedTermsKey = sourceIdentityDigest(requestedTermsUrl);
  const attempts = [{
    url: primaryUrl,
    role: "primary",
    status: "success",
    httpStatus: 200,
    contentHash: "a".repeat(64),
    logicalSourceKey: sourceIdentityDigest(primaryUrl),
    finalResourceIdentityHash: sourceIdentityDigest(primaryUrl),
    attemptedAt: "2026-08-20T00:00:00.000Z",
  }, {
    url: finalTermsUrl,
    role: "required_supporting",
    status: "success",
    httpStatus: 200,
    contentHash: "b".repeat(64),
    logicalSourceKey: requestedTermsKey,
    finalResourceIdentityHash: sourceIdentityDigest(finalTermsUrl),
    attemptedAt: "2026-08-20T00:00:01.000Z",
  }];
  const replay = await compute({
    jobId: "11111111-1111-4111-8111-111111111111",
    cardId: "22222222-2222-4222-8222-222222222222",
    parserVersion: "benefits-v6",
    runMode: "pilot",
    sourceManifestHash: await computeSourceManifestHash(attempts as never),
    expectedRequiredSourceKeys: [requestedTermsKey],
    requiredSourceSelectionOverflow: false,
    issuer: "Issuer Example",
    identityLabels: ["Issuer Example Card"],
    primarySourceUrl: primaryUrl,
    attempts,
    documents: [{
      sourceUrl: primaryUrl,
      finalUrl: primaryUrl,
      text: "Issuer Example Card. Get 10% cashback.",
      contentHash: "a".repeat(64),
      replayLinks: [{
        href: requestedTermsUrl,
        anchorText: "Terms",
        resourceIdentityHash: requestedTermsKey,
      }],
    }, {
      sourceUrl: requestedTermsUrl,
      finalUrl: finalTermsUrl,
      requestedResourceIdentityHash: requestedTermsKey,
      finalResourceIdentityHash: sourceIdentityDigest(finalTermsUrl),
      text: "Issuer Example Card terms. Get 10% cashback.",
      contentHash: "b".repeat(64),
    }],
  });
  assert(
    replay.deterministicReplayPassed === true,
    "redirected requested/final replay identities were rejected",
  );
});

type Task10BatchModule = typeof batchModule & {
  computePilotReplayEvidence?: (input: Record<string, unknown>) => Promise<{
    proposals: Array<Record<string, unknown>>;
    canonicalHash: string;
    repeatCanonicalHash: string;
    deterministicReplayPassed: boolean;
    sourceManifestHash: string;
    verificationEnvelope: Record<string, unknown>;
    repeatVerificationEnvelope: Record<string, unknown>;
    expectedRequiredSourceKeys: string[];
    requiredSourceSelectionOverflow: boolean;
    sourceAttempts: Array<Record<string, unknown>>;
  }>;
  capturePilotLiveStateSnapshot?: (
    db: Record<string, unknown>,
    cardId: string,
  ) => Promise<Record<string, { count: number; row_hash: string }>>;
  liveStateMutationCount?: (
    before: Record<string, unknown>,
    after: Record<string, unknown>,
  ) => number;
  buildOperationalMetrics?: (
    input: Record<string, unknown>,
  ) => Record<string, unknown>;
  operationalLogEntry?: (
    input: Record<string, unknown>,
  ) => Record<string, unknown>;
  projectPilotJobEvidence?: (
    row: Record<string, unknown>,
    boundary?: Record<string, unknown>,
  ) => Promise<Record<string, unknown>>;
};

const task10BatchModule = batchModule as Task10BatchModule;

async function withComputedPilotEvidence<T extends Record<string, any>>(
  row: T,
  options: {
    proposalCount?: 0 | 1;
    replayIdentityLabel?: string;
    authoritativeCardName?: string;
  } | number = {},
): Promise<T> {
  const fixtureIndex = Number(String(row.id).match(/(\d+)$/)?.[1] ?? 0);
  const fixtureIssuer = row.issuer ?? ["Issuer A", "Issuer B", "Issuer C"][
    fixtureIndex % 3
  ];
  const fixtureIdentityLabel = typeof options === "object" &&
      options.replayIdentityLabel
    ? options.replayIdentityLabel
    : `${fixtureIssuer} Example Card`;
  const authoritativeCardName = typeof options === "object" &&
      options.authoritativeCardName
    ? options.authoritativeCardName
    : fixtureIdentityLabel;
  const observedAt = "2026-08-20T00:00:00.000Z";
  const attempts = [{
    url: "https://issuer.example/card",
    role: "primary",
    status: "success",
    httpStatus: 200,
    contentHash: "9".repeat(64),
    finalResourceIdentityHash: sourceIdentityDigest(
      "https://issuer.example/card",
    ),
    attemptedAt: observedAt,
    logicalSourceKey: sourceIdentityDigest("https://issuer.example/card"),
  }];
  const sourceManifestHash = await computeSourceManifestHash(attempts as never);
  const suppliedSummary = row.result_summary ?? {};
  const reviewed = Object.hasOwn(suppliedSummary, "review_status");
  const disposition = reviewed || row.status === "staged"
    ? "material"
    : "no_change";
  const proposalCount =
    (typeof options === "object" ? options.proposalCount : undefined) ??
      (disposition === "material" ? 1 : 0);
  const stagingId = disposition === "material"
    ? `33333333-3333-4333-8333-${String(fixtureIndex + 1).padStart(12, "0")}`
    : null;
  const stagingContentHash = disposition === "material" ? "f".repeat(64) : null;
  const retainedText = proposalCount === 0
    ? `${fixtureIdentityLabel}. No qualifying benefits are listed.`
    : `${fixtureIdentityLabel}. Get 10% cashback on dining spends.`;
  const replay = await task10BatchModule.computePilotReplayEvidence!({
    jobId: String(row.id),
    cardId: row.card_id ?? `card-${row.id}`,
    parserVersion: "benefits-v6",
    runMode: "pilot",
    sourceManifestHash,
    expectedRequiredSourceKeys: [],
    requiredSourceSelectionOverflow: false,
    issuer: fixtureIssuer,
    identityLabels: [fixtureIdentityLabel],
    primarySourceUrl: "https://issuer.example/card",
    attempts,
    documents: [{
      sourceUrl: "https://issuer.example/card",
      finalUrl: "https://issuer.example/card",
      text: retainedText,
      contentHash: "9".repeat(64),
    }],
    ...(proposalCount === 0 ? { extract: async () => [] } : {}),
  });
  const canonicalBenefitHash = await sha256TextFixture(
    replay.proposals.map((proposal) =>
      "conditionHash" in proposal ? proposal.conditionHash : proposal.dedupeKey
    ).sort().join("\n"),
  );
  const replayInput = (replay as Record<string, any>).replayInput ?? {
    version: 1,
    documents: [{
      requested_source_url: "https://issuer.example/card",
      final_source_url: "https://issuer.example/card",
      requested_resource_identity_hash: sourceIdentityDigest(
        "https://issuer.example/card",
      ),
      final_resource_identity_hash: sourceIdentityDigest(
        "https://issuer.example/card",
      ),
      content_hash: "9".repeat(64),
      public_text: retainedText,
    }],
    required_resources: [],
  };
  const summary = {
    unsafe_mutation_count: 0,
    idempotency_passed: true,
    evidence_passed: true,
    raw_body_stored: false,
    proposals: proposalCount,
    proposal_disposition: disposition,
    successful_no_change: disposition === "no_change",
    ...suppliedSummary,
  };
  const runMode = row.run_mode === "scheduled" &&
      summary.pilot_qualified === true
    ? "pilot"
    : row.run_mode;
  const snapshot = {
    card_catalog: { count: 1, row_hash: "c".repeat(64) },
    benefits: { count: 0, row_hash: "d".repeat(64) },
    card_benefit_mapping: { count: 0, row_hash: "e".repeat(64) },
  };
  return {
    ...row,
    card_catalog: {
      card_name: authoritativeCardName,
      network: null,
      card_catalog_aliases: [],
    },
    issuer: fixtureIssuer,
    card_id: row.card_id ?? `card-${row.id}`,
    canonical_url: row.canonical_url ?? "https://issuer.example/card",
    staging_id: row.staging_id === undefined ? stagingId : row.staging_id,
    result_summary: summary,
    normalized_fields: {
      ...(row.normalized_fields ?? {}),
      pilot_profile: row.normalized_fields?.pilot_profile ?? [
        "straightforward",
        "redirect_or_js",
        "terms_linked",
        "known_invalid",
        "additional_valid",
      ][fixtureIndex % 5],
      pilot_evidence: {
        parser_version: row.parser_version,
        job_id: row.id,
        card_id: row.card_id ?? `card-${row.id}`,
        run_mode: runMode,
        canonical_hash: replay.canonicalHash,
        repeat_canonical_hash: replay.repeatCanonicalHash,
        deterministic_replay_passed: replay.deterministicReplayPassed,
        source_manifest_hash: replay.sourceManifestHash,
        source_attempts: replay.sourceAttempts,
        expected_required_source_keys: replay.expectedRequiredSourceKeys,
        required_source_selection_overflow:
          replay.requiredSourceSelectionOverflow,
        verification_envelope: replay.verificationEnvelope,
        repeat_verification_envelope: replay.repeatVerificationEnvelope,
        replay_input: replayInput,
        crawl_complete: true,
        suppressed_removal_count: 0,
        unsafe_mutation_count: 0,
        raw_body_stored: false,
        side_effect_proof_passed: true,
        observed_at: observedAt,
        live_state_before: snapshot,
        live_state_after: snapshot,
        conflict_count: 0,
        catalog_identity_conflict_count: 0,
        proposal_count: proposalCount,
        proposal_disposition: disposition,
        canonical_benefit_hash: canonicalBenefitHash,
        previous_canonical_benefit_hash: disposition === "no_change"
          ? canonicalBenefitHash
          : null,
        staging_id: stagingId,
        staging_content_hash: stagingContentHash,
      },
    },
  };
}

Deno.test("pilot replay identity labels are bound to authoritative catalog identity", async () => {
  const project = task10BatchModule.projectPilotJobEvidence;
  assert(typeof project === "function", "pilot evidence boundary is missing");
  const row = await withComputedPilotEvidence({
    id: "pilot-authoritative-identity-0",
    card_id: "22222222-2222-4222-8222-222222222222",
    run_mode: "pilot",
    parser_version: "benefits-v6",
    status: "completed",
  }, {
    proposalCount: 1,
    replayIdentityLabel: "Issuer A Rival Card",
    authoritativeCardName: "Issuer A Example Card",
  }) as Record<string, any>;
  const projected = await project(row, {
    currentLiveState: row.normalized_fields.pilot_evidence.live_state_after,
  });
  assert(
    projected.computedEvidenceValid === false &&
      projected.sourceBindingValid === false,
    "self-consistent rival identity labels were not bound to card_catalog",
  );
});

function pilotStagingRows(
  rows: Array<Record<string, any>>,
): Array<Record<string, any>> {
  return rows.flatMap((row) => {
    const evidence = row.normalized_fields?.pilot_evidence;
    if (typeof evidence?.staging_id !== "string") return [];
    const summary = row.result_summary ?? {};
    let proposalIndex = 0;
    let removalIndex = 0;
    const proposals = evidence.verification_envelope.canonical_proposals;
    const decisionsFor = (action: string, value: unknown) =>
      Number.isInteger(value) && Number(value) >= 0 && Number(value) <= 64
        ? Array.from({ length: Number(value) }, () => {
          if (action === "approve" || action === "edit") {
            const index = proposalIndex++;
            const proposal = proposals[index];
            return {
              action,
              proposal_index: index,
              benefit_id: `44444444-4444-4444-8444-${
                String(index + 1).padStart(12, "0")
              }`,
              dedupe_key: proposal?.dedupeKey,
              condition_hash: proposal?.conditionHash,
              reviewed_at: "2026-08-20 00:01:00.123456+00",
            };
          }
          if (action === "reject") {
            const index = proposalIndex++;
            const proposal = proposals[index];
            return {
              action,
              proposal_index: index,
              dedupe_key: proposal?.dedupeKey,
              condition_hash: proposal?.conditionHash,
              reviewed_at: "2026-08-20 00:01:00.123456+00",
            };
          }
          return {
            action,
            benefit_id: `55555555-5555-4555-8555-${
              String(++removalIndex).padStart(12, "0")
            }`,
            reviewed_at: "2026-08-20 00:01:00.123456+00",
          };
        })
        : [];
    const decisions = [
      ...decisionsFor("approve", summary.approved_count ?? 0),
      ...decisionsFor("keep_existing", summary.retained_count ?? 0),
      ...decisionsFor("retire", summary.retired_count ?? 0),
      ...decisionsFor("reject", summary.rejected_count ?? 0),
    ];
    return [{
      id: evidence.staging_id,
      card_id: row.card_id,
      parser_version: row.parser_version,
      content_hash: evidence.staging_content_hash,
      status: row.status === "completed" ? summary.review_status : "pending",
      benefit_decisions: decisions,
      extracted_data: {
        proposals: structuredClone(
          proposals,
        ),
        retained_documents: structuredClone(
          evidence.verification_envelope.retained_documents,
        ),
        ...(row.status === "completed"
          ? {
            review_pre_live_state: structuredClone(
              evidence.live_state_after,
            ),
            published_live_state: structuredClone(
              evidence.live_state_after,
            ),
          }
          : {}),
        diff: {
          possibleRemovals: Array.from(
            { length: removalIndex },
            (_, index) => ({
              benefit: {
                benefitId: `55555555-5555-4555-8555-${
                  String(index + 1).padStart(12, "0")
                }`,
              },
            }),
          ),
        },
      },
    }];
  });
}

function pilotSnapshotCapture(rows: Array<Record<string, any>>) {
  return async (_db: unknown, cardId: string) => {
    const row = rows.find((candidate) => String(candidate.card_id) === cardId);
    return structuredClone(
      row?.normalized_fields?.pilot_evidence
        ?.live_state_after ?? {
        card_catalog: { count: 1, row_hash: "c".repeat(64) },
        benefits: { count: 0, row_hash: "d".repeat(64) },
        card_benefit_mapping: { count: 0, row_hash: "e".repeat(64) },
      },
    );
  };
}

Deno.test("pilot live-state proof hashes the exact card, mapping, and mapped benefit rows", async () => {
  const capture = task10BatchModule.capturePilotLiveStateSnapshot;
  const mutations = task10BatchModule.liveStateMutationCount;
  assert(typeof capture === "function", "pilot live-state snapshot is missing");
  assert(
    typeof mutations === "function",
    "pilot mutation comparison is missing",
  );
  const state: Record<string, Array<Record<string, unknown>>> = {
    card_catalog: [{
      id: "22222222-2222-4222-8222-222222222222",
      card_name: "Fixture Card",
      bank: "Fixture Bank",
      network: "Visa",
      annual_fee: 500,
      updated_at: "2026-08-20 00:00:00.1234+00",
    }],
    card_benefit_mapping: [{
      mapping_id: "33333333-3333-4333-8333-333333333333",
      card_id: "22222222-2222-4222-8222-222222222222",
      benefit_id: "44444444-4444-4444-8444-444444444444",
      display_priority: 1,
      is_primary: true,
      category_codes: ["DINING"],
      retired_at: null,
    }],
    benefits: [{
      benefit_id: "44444444-4444-4444-8444-444444444444",
      dedupe_key: "legacy:dining",
      title: "Dining",
      value_config: { rate: 10 },
      is_active: true,
    }],
  };
  const db = {
    from(table: string) {
      let rows = structuredClone(state[table] ?? []);
      const query = {
        select() {
          return this;
        },
        eq(column: string, value: unknown) {
          rows = rows.filter((row) => row[column] === value);
          return this;
        },
        in(column: string, values: unknown[]) {
          rows = rows.filter((row) => values.includes(row[column]));
          return this;
        },
        order() {
          return this;
        },
        limit(limit: number) {
          return Promise.resolve({ data: rows.slice(0, limit), error: null });
        },
        then(onfulfilled: (value: unknown) => unknown) {
          return Promise.resolve({ data: rows, error: null }).then(onfulfilled);
        },
      };
      return query;
    },
  };
  const before = await capture(db, "22222222-2222-4222-8222-222222222222");
  assert(
    before.card_catalog.row_hash === await sha256Fixture([{
      ...state.card_catalog[0],
      updated_at: "2026-08-20T00:00:00.123400Z",
    }]),
    "Postgres timestamptz text did not hash like SQL UTC microseconds",
  );
  const unchanged = await capture(
    db,
    "22222222-2222-4222-8222-222222222222",
  );
  assert(mutations(before, unchanged) === 0, "unchanged live state failed");
  for (
    const equivalentOffset of [
      "2026-08-20T05:30:00.123400+05:30",
      "2026-08-19T20:00:00.123400-04:00",
    ]
  ) {
    state.card_catalog[0].updated_at = equivalentOffset;
    const offsetSnapshot = await capture(
      db,
      "22222222-2222-4222-8222-222222222222",
    );
    assert(
      offsetSnapshot.card_catalog.row_hash === before.card_catalog.row_hash,
      `equal offset instant changed the live hash: ${equivalentOffset}`,
    );
  }
  state.card_catalog[0].updated_at = "2026-08-20 00:00:00.1235+00";
  const timestampMutation = await capture(
    db,
    "22222222-2222-4222-8222-222222222222",
  );
  assert(
    before.card_catalog.row_hash !== timestampMutation.card_catalog.row_hash,
    "microsecond timestamp mutation was erased",
  );
  state.card_catalog[0].updated_at = "2026-08-20 00:00:00.1234+00";
  state.benefits[0].value_config = { rate: 12 };
  const after = await capture(db, "22222222-2222-4222-8222-222222222222");
  assert(
    mutations(before, after) === 1 &&
      before.benefits.row_hash !== after.benefits.row_hash,
    "mapped benefit mutation was not detected",
  );
});

Deno.test("operational metrics derive exact attempts, diffs, actions, and safe bounded logs", () => {
  const build = task10BatchModule.buildOperationalMetrics;
  const logEntry = task10BatchModule.operationalLogEntry;
  assert(
    typeof build === "function",
    "operational metric computation is missing",
  );
  assert(typeof logEntry === "function", "bounded operational log is missing");
  const metrics = build({
    attempts: [
      {
        role: "primary",
        status: "success",
        httpStatus: 200,
        attemptHistory: [
          {
            status: "failed",
            httpStatus: 429,
            errorCode: "http_429",
            attemptedAt: "2026-08-20T00:00:00.000Z",
          },
          {
            status: "success",
            httpStatus: 200,
            attemptedAt: "2026-08-20T00:00:01.000Z",
          },
        ],
      },
      {
        role: "required_supporting",
        status: "failed",
        httpStatus: 404,
        errorCode: "http_404",
      },
      {
        role: "supporting",
        status: "failed",
        httpStatus: 403,
        errorCode: "http_403",
      },
    ],
    crawlComplete: false,
    additions: [{ id: "add" }],
    modifications: [{ changeType: "identity_migration" }, { id: "change" }],
    removals: [],
    suppressedRemovals: [{ reason: "incomplete_crawl" }],
    conflicts: [{ code: "proposal_conflict" }],
    catalogIdentityConflicts: [{ code: "conflicting_url_identity" }],
    decisions: [
      { action: "approve" },
      { action: "edit" },
      { action: "reject", proposal_index: 0 },
      { action: "reject" },
      { action: "retire" },
      { action: "retry" },
    ],
    deterministicReplayPassed: false,
    sideEffectProofPassed: true,
    startedAt: "2026-08-20T00:00:00.000Z",
    completedAt: "2026-08-20T00:00:03.000Z",
    spoofedTotals: { fetch_success: 999, approvals: 999 },
  });
  assert(
    metrics.fetch_attempts === 4 && metrics.fetch_success === 1 &&
      metrics.fetch_missing === 1 && metrics.fetch_blocked === 2 &&
      metrics.fetch_incomplete === 1,
    "source attempt metrics trusted spoofed totals or lost outcomes",
  );
  assert(
    metrics.required_supporting_attempted === 1 &&
      metrics.required_supporting_failed === 1 &&
      metrics.staged_additions === 1 && metrics.staged_modifications === 1 &&
      metrics.identity_migrations === 1 && metrics.suppressed_removals === 1 &&
      JSON.stringify(metrics.suppressed_removal_reason_codes) ===
        JSON.stringify(["incomplete_crawl"]),
    "proposal and supporting-source metrics were not derived",
  );
  assert(
    metrics.approvals === 1 && metrics.edits === 1 &&
      metrics.targeted_rejects === 1 && metrics.global_rejects === 1 &&
      metrics.retirements === 1 && metrics.retries === 1 &&
      metrics.processing_duration_ms === 3000,
    "review or duration metrics were not derived",
  );
  const log = logEntry({
    jobId: "11111111-1111-4111-8111-111111111111",
    cardId: "22222222-2222-4222-8222-222222222222",
    outcome: "review_required",
    reasonCodes: [
      "required_supporting_incomplete",
      "http_404",
      "Authorization: Bearer secret-token",
    ],
    metrics: {
      ...metrics,
      customer_email: "person@example.com",
      arbitrary_timestamp: "2026-08-20T00:00:00.000Z",
      encoded_nested_secret: encodeURIComponent(JSON.stringify({
        access_token: "abcdefgh-secret",
      })),
    },
    raw_body: "<html>customer 4242</html>",
    signed_url: "https://issuer.example/card?token=secret-token",
    lease_token: "lease-secret",
  });
  const serialized = JSON.stringify(log);
  for (
    const forbidden of [
      "secret-token",
      "customer 4242",
      "lease-secret",
      "signed_url",
      "raw_body",
      "person@example.com",
      "arbitrary_timestamp",
      "abcdefgh-secret",
    ]
  ) {
    assert(
      !serialized.includes(forbidden),
      `operational log leaked ${forbidden}`,
    );
  }
  assert(
    serialized.includes("required_supporting_incomplete") &&
      serialized.includes("http_404") &&
      serialized.includes("incomplete_crawl") &&
      serialized.length < 4096,
    "operational log lost its allowlisted reason or became unbounded",
  );
  for (
    const [label, input] of [
      [
        "array overflow",
        {
          additions: Array.from({ length: 513 }, () => ({ id: "x" })),
          startedAt: "2026-08-20T00:00:00.000Z",
          completedAt: "2026-08-20T00:00:01.000Z",
        },
      ],
      [
        "future processing time",
        {
          startedAt: "3026-08-20T00:00:00.000Z",
          completedAt: "3026-08-20T00:00:01.000Z",
        },
      ],
    ] as const
  ) {
    let error: unknown;
    try {
      build(input);
    } catch (caught) {
      error = caught;
    }
    assert(
      error instanceof Error &&
        error.message === "invalid_operational_metric_input",
      `${label} was silently normalized into exact metrics`,
    );
  }
});

Deno.test("pilot boundary rejects self-attested, malformed, cross-card, and inconsistent evidence", async () => {
  const project = task10BatchModule.projectPilotJobEvidence;
  assert(typeof project === "function", "pilot evidence boundary is missing");
  const selfAttested = await project({
    id: "11111111-1111-4111-8111-111111111111",
    card_id: "22222222-2222-4222-8222-222222222222",
    canonical_url: "https://issuer.example/card",
    parser_version: "benefits-v6",
    run_mode: "pilot",
    status: "staged",
    result_summary: {
      idempotency_passed: true,
      evidence_passed: true,
      unsafe_mutation_count: 0,
      raw_body_stored: false,
    },
    normalized_fields: {},
  });
  assert(
    selfAttested.computedEvidenceValid === false,
    "legacy caller booleans qualified without computed evidence",
  );

  const sourceAttempts = [{
    url: "https://issuer.example/card",
    role: "primary",
    status: "success",
    httpStatus: 200,
    contentHash: "9".repeat(64),
    finalResourceIdentityHash: "8".repeat(64),
    attemptedAt: "2026-08-20T00:00:00.000Z",
    logicalSourceKey: sourceIdentityDigest("https://issuer.example/card"),
  }];
  const computedManifest = await computeSourceManifestHash(
    sourceAttempts as never,
  );
  const baseEvidence = {
    parser_version: "benefits-v6",
    job_id: "11111111-1111-4111-8111-111111111111",
    card_id: "22222222-2222-4222-8222-222222222222",
    run_mode: "pilot",
    canonical_hash: "a".repeat(64),
    repeat_canonical_hash: "a".repeat(64),
    deterministic_replay_passed: true,
    source_manifest_hash: computedManifest,
    source_attempts: sourceAttempts,
    crawl_complete: true,
    suppressed_removal_count: 0,
    unsafe_mutation_count: 0,
    raw_body_stored: false,
    side_effect_proof_passed: true,
    observed_at: "2026-08-20T00:00:00.000Z",
    live_state_before: {
      card_catalog: { count: 1, row_hash: "c".repeat(64) },
      benefits: { count: 0, row_hash: "d".repeat(64) },
      card_benefit_mapping: { count: 0, row_hash: "e".repeat(64) },
    },
    live_state_after: {
      card_catalog: { count: 1, row_hash: "c".repeat(64) },
      benefits: { count: 0, row_hash: "d".repeat(64) },
      card_benefit_mapping: { count: 0, row_hash: "e".repeat(64) },
    },
    conflict_count: 0,
    catalog_identity_conflict_count: 0,
  };
  const fabricatedEqualHashes = await project({
    id: "11111111-1111-4111-8111-111111111111",
    card_id: "22222222-2222-4222-8222-222222222222",
    canonical_url: "https://issuer.example/card",
    parser_version: "benefits-v6",
    run_mode: "pilot",
    status: "staged",
    normalized_fields: { pilot_evidence: baseEvidence },
    result_summary: {},
  });
  assert(
    fabricatedEqualHashes.computedEvidenceValid === false,
    "equal caller-written hashes qualified without a retained envelope",
  );
  const foreignSourceAttempts = [{
    ...sourceAttempts[0],
    url: "https://other-issuer.example/card",
    logicalSourceKey: sourceIdentityDigest(
      "https://other-issuer.example/card",
    ),
  }];
  const foreignSource = await project({
    id: "11111111-1111-4111-8111-111111111111",
    card_id: "22222222-2222-4222-8222-222222222222",
    canonical_url: "https://issuer.example/card",
    parser_version: "benefits-v6",
    run_mode: "pilot",
    status: "staged",
    normalized_fields: {
      pilot_evidence: {
        ...baseEvidence,
        source_attempts: foreignSourceAttempts,
        source_manifest_hash: await computeSourceManifestHash(
          foreignSourceAttempts as never,
        ),
      },
    },
    result_summary: {},
  });
  assert(
    foreignSource.computedEvidenceValid === false,
    "internally consistent evidence from another source qualified",
  );
  const { conflict_count: _omittedConflictCount, ...missingConflictProof } =
    baseEvidence;
  const missingConflict = await project({
    id: "11111111-1111-4111-8111-111111111111",
    card_id: "22222222-2222-4222-8222-222222222222",
    canonical_url: "https://issuer.example/card",
    parser_version: "benefits-v6",
    run_mode: "pilot",
    status: "staged",
    normalized_fields: { pilot_evidence: missingConflictProof },
    result_summary: {},
  });
  assert(
    missingConflict.computedEvidenceValid === false,
    "missing computed conflict proof defaulted to zero",
  );
  for (
    const [label, unsafeAttempt] of [
      [
        "signed query",
        { ...sourceAttempts[0], url: "https://issuer.example/card?token=x" },
      ],
      [
        "nested credential",
        { ...sourceAttempts[0], access_token: "secret" },
      ],
      [
        "future attempt",
        { ...sourceAttempts[0], attemptedAt: "3026-08-20T00:00:00.000Z" },
      ],
      [
        "attempt history overflow",
        { ...sourceAttempts[0], attemptHistoryOverflow: true },
      ],
      [
        "credential-bearing validator",
        { ...sourceAttempts[0], etag: '"Bearer secret-token"' },
      ],
    ] as const
  ) {
    const attempts = [unsafeAttempt];
    const result = await project({
      id: "11111111-1111-4111-8111-111111111111",
      card_id: "22222222-2222-4222-8222-222222222222",
      canonical_url: "https://issuer.example/card",
      parser_version: "benefits-v6",
      run_mode: "pilot",
      status: "staged",
      normalized_fields: {
        pilot_evidence: {
          ...baseEvidence,
          source_attempts: attempts,
          source_manifest_hash: await computeSourceManifestHash(
            attempts as never,
          ),
        },
      },
      result_summary: {},
    });
    assert(
      result.computedEvidenceValid === false,
      `${label} survived the computed evidence boundary`,
    );
  }
  for (
    const [label, patch] of [
      ["cross-card", { card_id: "33333333-3333-4333-8333-333333333333" }],
      ["uppercase hash", { canonical_hash: "A".repeat(64) }],
      ["boolean string", { crawl_complete: "true" }],
      ["fractional count", { suppressed_removal_count: 0.5 }],
      ["replay mismatch", { repeat_canonical_hash: "f".repeat(64) }],
      ["future timestamp", { observed_at: "3026-08-20T00:00:00.000Z" }],
      ["manifest mismatch", { source_manifest_hash: "6".repeat(64) }],
    ] as const
  ) {
    const result = await project({
      id: "11111111-1111-4111-8111-111111111111",
      card_id: "22222222-2222-4222-8222-222222222222",
      canonical_url: "https://issuer.example/card",
      parser_version: "benefits-v6",
      run_mode: "pilot",
      status: "staged",
      normalized_fields: { pilot_evidence: { ...baseEvidence, ...patch } },
      result_summary: {},
    });
    assert(
      result.computedEvidenceValid === false,
      `${label} pilot evidence qualified`,
    );
  }
});

Deno.test("pilot no-change proof is bound to proposal disposition and absence of staging", async () => {
  const project = task10BatchModule.projectPilotJobEvidence;
  assert(typeof project === "function", "pilot evidence boundary is missing");
  const row = await withComputedPilotEvidence({
    id: "pilot-no-change-binding-0",
    card_id: "22222222-2222-4222-8222-222222222222",
    run_mode: "pilot",
    parser_version: "benefits-v6",
    status: "completed",
    staging_id: "33333333-3333-4333-8333-333333333333",
    result_summary: {
      unsafe_mutation_count: 0,
      raw_body_stored: false,
      successful_no_change: true,
      proposals: 0,
      proposal_disposition: "no_change",
    },
  }) as Record<string, any>;
  const projected = await project(row);
  assert(
    projected.computedEvidenceValid === false &&
      projected.successfulNoChange === false,
    "summary-only no-change bypassed an attached staging row",
  );
});

Deno.test("pilot no-change is recomputed from canonical equality for nonempty and complete-zero sets", async () => {
  const project = task10BatchModule.projectPilotJobEvidence;
  assert(typeof project === "function", "pilot evidence boundary is missing");
  const nonempty = await withComputedPilotEvidence({
    id: "pilot-canonical-no-change-0",
    card_id: "22222222-2222-4222-8222-222222222222",
    run_mode: "pilot",
    parser_version: "benefits-v6",
    status: "completed",
  }, { proposalCount: 1 }) as Record<string, any>;
  const nonemptySnapshot = nonempty.normalized_fields.pilot_evidence
    .live_state_after;
  const validNonempty = await project(nonempty, {
    currentLiveState: nonemptySnapshot,
  });
  assert(
    validNonempty.computedEvidenceValid === true &&
      validNonempty.successfulNoChange === true,
    "unchanged nonempty canonical proposal set did not qualify as no-change",
  );
  const mismatched = structuredClone(nonempty);
  mismatched.normalized_fields.pilot_evidence
    .previous_canonical_benefit_hash = "0".repeat(64);
  const forgedDisposition = await project(mismatched, {
    currentLiveState: nonemptySnapshot,
  });
  assert(
    forgedDisposition.computedEvidenceValid === false,
    "caller-supplied no-change disposition bypassed canonical inequality",
  );

  const zero = await withComputedPilotEvidence({
    id: "pilot-canonical-no-change-1",
    card_id: "33333333-3333-4333-8333-333333333333",
    run_mode: "pilot",
    parser_version: "benefits-v6",
    status: "completed",
  }, { proposalCount: 0 }) as Record<string, any>;
  zero.normalized_fields.pilot_evidence.previous_canonical_benefit_hash = null;
  const validZero = await project(zero, {
    currentLiveState: zero.normalized_fields.pilot_evidence.live_state_after,
  });
  assert(
    validZero.computedEvidenceValid === true &&
      validZero.successfulNoChange === true,
    "complete canonical zero set did not qualify as no-change",
  );
});

Deno.test("pilot qualification reruns the actual v6 extractor from bounded replay input", async () => {
  const project = task10BatchModule.projectPilotJobEvidence;
  assert(typeof project === "function", "pilot evidence boundary is missing");
  const row = await withComputedPilotEvidence({
    id: "pilot-rerun-input-0",
    card_id: "22222222-2222-4222-8222-222222222222",
    run_mode: "pilot",
    parser_version: "benefits-v6",
    status: "completed",
  }, { proposalCount: 1 }) as Record<string, any>;
  const currentLiveState =
    row.normalized_fields.pilot_evidence.live_state_after;
  const valid = await project(row, { currentLiveState });
  assert(
    valid.computedEvidenceValid === true,
    "bounded canonical replay input could not reproduce authoritative proposals",
  );

  const changedInput = structuredClone(row);
  changedInput.normalized_fields.pilot_evidence.replay_input.documents[0]
    .public_text = "Get 1% cashback on fuel spends.";
  const forgedEnvelope = await project(changedInput, { currentLiveState });
  assert(
    forgedEnvelope.computedEvidenceValid === false,
    "equal self-attested envelope hashes bypassed the actual extractor rerun",
  );

  const omittedRequired = structuredClone(row);
  omittedRequired.normalized_fields.pilot_evidence.replay_input
    .required_resources = [{ logical_source_key: "7".repeat(64) }];
  const omitted = await project(omittedRequired, { currentLiveState });
  assert(
    omitted.computedEvidenceValid === false,
    "required replay resource omitted from attempts still qualified",
  );
});

Deno.test("pilot retained envelope rejects an entirely omitted required source and validator secrets", async () => {
  const project = task10BatchModule.projectPilotJobEvidence;
  assert(typeof project === "function", "pilot evidence boundary is missing");
  const row = await withComputedPilotEvidence({
    id: "pilot-required-source-0",
    card_id: "22222222-2222-4222-8222-222222222222",
    run_mode: "pilot",
    parser_version: "benefits-v6",
    status: "completed",
  }) as Record<string, any>;
  const unverifiedLiveState = await project(row);
  assert(
    unverifiedLiveState.computedEvidenceValid === false,
    "historical live-state hashes qualified without a current DB read",
  );
  const currentLiveState =
    row.normalized_fields.pilot_evidence.live_state_after;
  const valid = await project(row, { currentLiveState });
  assert(valid.computedEvidenceValid === true, "valid retained proof failed");
  const overflow = structuredClone(row.normalized_fields.pilot_evidence);
  overflow.required_source_selection_overflow = true;
  overflow.verification_envelope.required_source_selection_overflow = true;
  overflow.repeat_verification_envelope.required_source_selection_overflow =
    true;
  overflow.canonical_hash = await sha256Fixture(
    overflow.verification_envelope,
  );
  overflow.repeat_canonical_hash = await sha256Fixture(
    overflow.repeat_verification_envelope,
  );
  const overflowed = await project({
    ...row,
    normalized_fields: { ...row.normalized_fields, pilot_evidence: overflow },
  }, { currentLiveState });
  assert(
    overflowed.computedEvidenceValid === false,
    "required-source selection overflow qualified a bounded manifest",
  );
  const changedLiveState = structuredClone(currentLiveState);
  changedLiveState.card_catalog.row_hash = "0".repeat(64);
  const mutatedCurrent = await project(row, {
    currentLiveState: changedLiveState,
  });
  assert(
    mutatedCurrent.computedEvidenceValid === false,
    "current live mutation was hidden behind historical equal snapshots",
  );
  const evidence = structuredClone(row.normalized_fields.pilot_evidence);
  const requiredKey = sourceIdentityDigest(
    "https://issuer.example/card/terms",
  );
  evidence.expected_required_source_keys = [requiredKey];
  evidence.verification_envelope.expected_required_source_keys = [requiredKey];
  evidence.repeat_verification_envelope.expected_required_source_keys = [
    requiredKey,
  ];
  evidence.canonical_hash = await sha256Fixture(
    evidence.verification_envelope,
  );
  evidence.repeat_canonical_hash = await sha256Fixture(
    evidence.repeat_verification_envelope,
  );
  const omitted = await project({
    ...row,
    normalized_fields: { ...row.normalized_fields, pilot_evidence: evidence },
  }, { currentLiveState });
  assert(
    omitted.computedEvidenceValid === false,
    "required source disappeared entirely while crawl_complete stayed true",
  );

  const secretValidator = structuredClone(
    row.normalized_fields.pilot_evidence,
  );
  secretValidator.source_attempts[0].etag = '"Bearer secret-token"';
  const unsafe = await project({
    ...row,
    normalized_fields: {
      ...row.normalized_fields,
      pilot_evidence: secretValidator,
    },
  }, { currentLiveState });
  assert(
    unsafe.computedEvidenceValid === false,
    "credential-bearing source validator survived pilot evidence",
  );

  const staged = await withComputedPilotEvidence({
    id: "pilot-secret-envelope-1",
    card_id: "22222222-2222-4222-8222-222222222222",
    run_mode: "pilot",
    parser_version: "benefits-v6",
    status: "staged",
  }) as Record<string, any>;
  const staging = pilotStagingRows([staged])[0];
  const validMaterial = await project(staged, {
    staging,
    currentLiveState: staged.normalized_fields.pilot_evidence.live_state_after,
  });
  assert(
    validMaterial.computedEvidenceValid === true,
    "valid material evidence failed authoritative staging binding",
  );
  const mismatchedStaging = structuredClone(staging);
  mismatchedStaging.extracted_data.proposals[0].fixture = "different-proposal";
  const foreignProposal = await project(staged, {
    staging: mismatchedStaging,
    currentLiveState: staged.normalized_fields.pilot_evidence.live_state_after,
  });
  assert(
    foreignProposal.computedEvidenceValid === false,
    "retained envelope proposals did not bind to authoritative staging",
  );
  const stagedEvidence = structuredClone(
    staged.normalized_fields.pilot_evidence,
  );
  stagedEvidence.verification_envelope.canonical_proposals[0].fixture =
    "access_token=secret-value";
  stagedEvidence.repeat_verification_envelope.canonical_proposals[0].fixture =
    "access_token=secret-value";
  stagedEvidence.canonical_hash = await sha256Fixture(
    stagedEvidence.verification_envelope,
  );
  stagedEvidence.repeat_canonical_hash = await sha256Fixture(
    stagedEvidence.repeat_verification_envelope,
  );
  const credentialEnvelope = await project({
    ...staged,
    normalized_fields: {
      ...staged.normalized_fields,
      pilot_evidence: stagedEvidence,
    },
  }, {
    staging,
    currentLiveState: stagedEvidence.live_state_after,
  });
  assert(
    credentialEnvelope.computedEvidenceValid === false,
    "credential text survived a recomputed retained proposal envelope",
  );
});

function issuerSchedulerStore(input: {
  jobs?: Array<Record<string, any>>;
  catalog?: Array<Record<string, any>>;
  afterJobRange?: (input: {
    rangeIndex: number;
    rows: Array<Record<string, any>>;
    jobs: Array<Record<string, any>>;
  }) => void;
  failUpdate?: (
    payload: Record<string, any>,
    matchingRows: Array<Record<string, any>>,
  ) => unknown;
  failRpc?: (
    name: string,
    args: Record<string, unknown>,
  ) => unknown;
}) {
  const jobs = input.jobs ?? [];
  const catalog = input.catalog ?? [];
  const backlogRanges: Array<[number, number]> = [];
  const pageReadIds: string[] = [];
  const orCalls: string[] = [];
  const rpcCalls: Array<{ name: string; args: Record<string, unknown> }> = [];
  let sequence = jobs.length;
  let jobRangeCount = 0;
  const matches = (
    row: Record<string, any>,
    filters: Array<(row: Record<string, any>) => boolean>,
  ) => filters.every((filter) => filter(row));
  const containsValue = (actual: unknown, expected: unknown): boolean => {
    if (
      expected === null || typeof expected !== "object" ||
      Array.isArray(expected)
    ) return actual === expected;
    if (
      actual === null || typeof actual !== "object" || Array.isArray(actual)
    ) {
      return false;
    }
    return Object.entries(expected).every(([key, value]) =>
      containsValue((actual as Record<string, unknown>)[key], value)
    );
  };
  const db = {
    async rpc(name: string, args: Record<string, unknown>) {
      rpcCalls.push({ name, args });
      const rpcError = input.failRpc?.(name, args);
      if (rpcError) return { data: null, error: rpcError };
      let job = args._discovery_job_id
        ? jobs.find((row) => row.id === args._discovery_job_id)
        : jobs.find((row) =>
          row.user_id === null &&
          row.discovery_source === args._discovery_source &&
          row.dedupe_key === args._dedupe_key
        );
      if (!job && args._discovery_job_id === null) {
        job = {
          id: `quarantine-${++sequence}`,
          user_id: null,
          discovery_source: args._discovery_source,
          issuer: args._issuer,
          proposed_product: args._proposed_product,
          evidence: args._source_evidence,
          dedupe_key: args._dedupe_key,
          status: "queued",
          attempt_count: 0,
          next_retry_at: null,
          failure_category: null,
          review_item_id: null,
          created_at: "2026-08-20T00:00:01.000Z",
          updated_at: "2026-08-20T00:00:01.000Z",
        };
        jobs.push(job);
      }
      if (!job) return { data: null, error: new Error("missing_review_job") };
      const created = !job.review_item_id;
      const reviewItemId = job.review_item_id ?? `review-${job.id}`;
      Object.assign(job, {
        status: "review_required",
        review_item_id: reviewItemId,
        next_retry_at: null,
        updated_at: "2026-08-20T00:00:01.000Z",
      });
      return {
        data: [{
          job_id: job.id,
          review_item_id: reviewItemId,
          resulting_status: "review_required",
          created,
        }],
        error: null,
      };
    },
    from(table: string) {
      if (table === "card_catalog") {
        const query = {
          select() {
            return this;
          },
          order() {
            return this;
          },
          range(from: number, to: number) {
            return Promise.resolve({
              data: catalog.slice(from, to + 1),
              error: null,
            });
          },
        };
        return query;
      }
      assert(
        table === "card_discovery_jobs",
        `unexpected issuer scheduler table ${table}`,
      );
      let operation: "select" | "update" | "insert" = "select";
      let payload: Record<string, any> = {};
      let projection = "*";
      const filters: Array<(row: Record<string, any>) => boolean> = [];
      const orders: Array<{ column: string; ascending: boolean }> = [];
      const query = {
        select(columns = "*") {
          projection = columns;
          return this;
        },
        eq(column: string, value: unknown) {
          filters.push((row) => row[column] === value);
          return this;
        },
        ilike(column: string, value: string) {
          const pattern = value.replace(
            /\\([%_\\])/g,
            (_, literal) => `\u0000${literal.charCodeAt(0).toString(16)}\u0000`,
          ).replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
            .replace(/%/g, "[\\s\\S]*").replace(/_/g, "[\\s\\S]")
            .replace(
              /\u0000([0-9a-f]+)\u0000/g,
              (_, code) =>
                `\\${String.fromCharCode(Number.parseInt(code, 16))}`,
            );
          const matcher = new RegExp(`^${pattern}$`, "i");
          filters.push((row) => matcher.test(String(row[column] ?? "")));
          return this;
        },
        or(expression: string) {
          orCalls.push(expression);
          const clauses = expression.split(",").map((clause) => clause.trim());
          const wildcardMatcher = (value: string) => {
            const unquoted = value.startsWith('"') && value.endsWith('"')
              ? value.slice(1, -1)
              : value;
            const pattern = unquoted.replace(
              /\\([%_\\])/g,
              (_, literal) =>
                `\u0000${literal.charCodeAt(0).toString(16)}\u0000`,
            ).replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
              .replace(/%/g, "[\\s\\S]*").replace(/_/g, "[\\s\\S]")
              .replace(
                /\u0000([0-9a-f]+)\u0000/g,
                (_, code) =>
                  `\\${String.fromCharCode(Number.parseInt(code, 16))}`,
              );
            return new RegExp(`^${pattern}$`, "i");
          };
          filters.push((row) =>
            clauses.some((clause) => {
              const issuer = clause.match(/^issuer\.ilike\.(.+)$/);
              if (issuer) {
                return wildcardMatcher(issuer[1]).test(
                  String(row.issuer ?? ""),
                );
              }
              const evidenceIssuer = clause.match(
                /^evidence->>issuer\.ilike\.(.+)$/,
              );
              if (evidenceIssuer) {
                return wildcardMatcher(evidenceIssuer[1]).test(
                  String(row.evidence?.issuer ?? ""),
                );
              }
              const dedupe = clause.match(/^dedupe_key\.eq\.(.+)$/);
              return dedupe
                ? String(row.dedupe_key ?? "") ===
                  dedupe[1].replace(/^"|"$/g, "")
                : false;
            })
          );
          return this;
        },
        is(column: string, value: unknown) {
          filters.push((row) => row[column] === value);
          return this;
        },
        in(column: string, values: unknown[]) {
          filters.push((row) => {
            const jsonField = column.match(/^evidence->>([a-z_]+)$/);
            const actual = jsonField
              ? row.evidence?.[jsonField[1]]
              : row[column];
            return values.includes(actual);
          });
          return this;
        },
        gt(column: string, value: string) {
          filters.push((row) =>
            typeof row[column] === "string" && row[column] > value
          );
          return this;
        },
        lte(column: string, value: string) {
          filters.push((row) =>
            typeof row[column] === "string" && row[column] <= value
          );
          return this;
        },
        contains(column: string, value: Record<string, unknown>) {
          filters.push((row) => containsValue(row[column], value));
          return this;
        },
        order(column: string, options?: { ascending?: boolean }) {
          orders.push({ column, ascending: options?.ascending !== false });
          return this;
        },
        update(value: Record<string, any>) {
          operation = "update";
          payload = value;
          return this;
        },
        insert(value: Record<string, any>) {
          operation = "insert";
          payload = value;
          return this;
        },
        range(from: number, to: number) {
          backlogRanges.push([from, to]);
          const selected = jobs.filter((row) => matches(row, filters)).sort(
            (left, right) => {
              for (const order of orders) {
                const comparison = String(left[order.column] ?? "")
                  .localeCompare(String(right[order.column] ?? ""));
                if (comparison !== 0) {
                  return order.ascending ? comparison : -comparison;
                }
              }
              return 0;
            },
          );
          const page = selected.slice(from, to + 1);
          pageReadIds.push(...page.map((row) => String(row.id)));
          input.afterJobRange?.({
            rangeIndex: jobRangeCount++,
            rows: page,
            jobs,
          });
          return Promise.resolve({
            data: page.map((row) => projectIssuerSchedulerRow(row, projection)),
            error: null,
          });
        },
        async maybeSingle() {
          if (operation === "insert") {
            const duplicate = jobs.some((row) =>
              row.discovery_source === payload.discovery_source &&
              row.dedupe_key === payload.dedupe_key && row.user_id === null
            );
            if (duplicate) return { data: null, error: { code: "23505" } };
            const row = {
              ...payload,
              id: `run-${++sequence}`,
              created_at: payload.created_at ?? payload.updated_at,
            };
            jobs.push(row);
            return {
              data: projectIssuerSchedulerRow(row, projection),
              error: null,
            };
          }
          const row = jobs.find((candidate) => matches(candidate, filters));
          if (!row) return { data: null, error: null };
          if (operation === "update") {
            const error = input.failUpdate?.(
              payload,
              jobs.filter((candidate) => matches(candidate, filters)),
            );
            if (error) return { data: null, error };
            Object.assign(row, payload);
          }
          return {
            data: projectIssuerSchedulerRow(row, projection),
            error: null,
          };
        },
      };
      return query;
    },
  };
  return { db, jobs, backlogRanges, pageReadIds, orCalls, rpcCalls };
}

function projectIssuerSchedulerRow(
  row: Record<string, any>,
  projection: string,
): Record<string, any> {
  if (projection.trim() === "*") return structuredClone(row);
  return Object.fromEntries(
    projection.split(",").map((column) => column.trim()).filter(Boolean).map(
      (column) => [column, structuredClone(row[column])],
    ),
  );
}

function completeIssuerCrawl(overrides: Record<string, unknown> = {}) {
  return {
    candidates: [],
    quarantined: [],
    complete: true,
    budgetExhausted: false,
    incompleteReasons: [],
    consideredCount: 0,
    fetchedCount: 0,
    resumedCount: 0,
    ...overrides,
  };
}

function persistedIssuerOutcomes(count: number) {
  return Array.from({ length: count }, (_, index) => ({
    candidate_key: index.toString(16).padStart(64, "0"),
    disposition: "candidate",
    attempted: true,
    persistence_outcome: "existing",
    classification: {
      kind: "card_product",
      canonicalUrl:
        `https://www.axis.bank.in/cards/credit-card/product-${index}`,
      proposedName: `Product ${index}`,
      aliases: [`Axis Product ${index} Credit Card`],
      confidence: 0.95,
      warnings: [],
      sanitizedEvidence: [`Axis Product ${index} Credit Card`],
    },
  }));
}

Deno.test("issuer discovery includes all-discontinued approved issuers and excludes disabled or unapproved rows", () => {
  const rows = [{
    bank: "Axis Bank",
    card_url: "https://www.axis.bank.in/cards/credit-card/neo-credit-card",
    card_type: "credit",
    is_discontinued: true,
  }, {
    bank: "HDFC Bank",
    card_url:
      "https://www.hdfcbank.com/personal/pay/cards/credit-cards/regalia",
    card_type: "credit",
    enabled: false,
  }, {
    bank: "ICICI Bank",
    card_url:
      "https://www.icicibank.com/personal-banking/cards/credit-card/coral",
    card_type: "credit",
    approved: false,
  }, {
    bank: "Unknown Issuer",
    card_url: "https://unknown.example/credit-card",
    card_type: "credit",
  }];
  const seed = selectIssuerDiscoveryCandidate(
    rows,
    new Date("2026-08-20T12:00:00.000Z"),
  );
  assert(
    seed?.issuer === "Axis Bank",
    "approved all-discontinued issuer disappeared from discovery",
  );
});

Deno.test("issuer discovery rotates a sorted issuer set by UTC day with restart stability", () => {
  const catalog = [{
    bank: "ICICI Bank",
    card_url:
      "https://www.icicibank.com/personal-banking/cards/credit-card/coral",
    card_type: "credit",
  }, {
    bank: "Axis Bank",
    card_url: "https://www.axis.bank.in/cards/credit-card/neo-credit-card",
    card_type: "credit",
  }, {
    bank: "HDFC Bank",
    card_url:
      "https://www.hdfcbank.com/personal/pay/cards/credit-cards/regalia",
    card_type: "credit",
  }];
  const expected = ["Axis Bank", "HDFC Bank", "ICICI Bank", "Axis Bank"];
  for (let offset = 0; offset < expected.length; offset += 1) {
    const now = new Date(Date.UTC(2026, 7, 20 + offset, 23, 59));
    const first = selectIssuerDiscoveryCandidate(catalog, now);
    const restarted = selectIssuerDiscoveryCandidate([...catalog], now);
    assert(first?.issuer === expected[offset], `wrong UTC slot ${offset}`);
    assert(
      restarted?.issuer === expected[offset],
      `restart changed UTC slot ${offset}`,
    );
  }
  assert(
    selectIssuerDiscoveryCandidate([], new Date("2026-08-20T00:00:00Z")) ===
      null,
    "empty approved issuer set did not become no-work",
  );
  const changed = [catalog[1], catalog[2]];
  assert(
    selectIssuerDiscoveryCandidate(
      changed,
      new Date("2026-08-20T12:00:00Z"),
    )?.issuer === "HDFC Bank",
    "changed issuer set was not deterministically re-slotted",
  );
});

Deno.test("issuer run progress replaces a retried candidate without evicting another completed key", () => {
  const existing = Array.from({ length: 200 }, (_, index) => ({
    candidate_key: index.toString(16).padStart(64, "0"),
    disposition: index === 42 ? "quarantined" : "candidate",
  }));
  const retriedKey = existing[42].candidate_key;
  const updated = upsertBoundedIssuerOutcomeSummary(existing, {
    candidate_key: retriedKey,
    disposition: "candidate",
  });

  assert(
    updated.length === 200,
    "retry grew or truncated the unique summary set",
  );
  assert(
    new Set(updated.map((item) => item.candidate_key)).size === 200,
    "retry left duplicate candidate progress",
  );
  assert(
    updated.at(-1)?.candidate_key === retriedKey &&
      updated.at(-1)?.disposition === "candidate",
    "latest terminal outcome did not replace the older candidate failure",
  );
  assert(
    updated.some((item) => item.candidate_key === existing[0].candidate_key),
    "replacing one candidate evicted unrelated resumable progress",
  );
});

Deno.test("approved issuer loading explicitly paginates beyond the Data API default window", async () => {
  const rows = Array.from({ length: 1_205 }, (_, index) => ({
    id: `card-${String(index).padStart(4, "0")}`,
    bank: index < 1_204 ? "Axis Bank" : "ICICI Bank",
    card_url: index < 1_204
      ? `https://www.axis.bank.in/cards/credit-card/card-${index}`
      : "https://www.icicibank.com/personal-banking/cards/credit-card/coral",
    card_type: "credit",
    is_discontinued: true,
  }));
  const ranges: Array<[number, number]> = [];
  const db = {
    from(table: string) {
      assert(table === "card_catalog", "issuer loader read the wrong table");
      const query = {
        select() {
          return this;
        },
        order() {
          return this;
        },
        range(from: number, to: number) {
          ranges.push([from, to]);
          return Promise.resolve({
            data: rows.slice(from, to + 1),
            error: null,
          });
        },
      };
      return query;
    },
  };
  const loaded = await loadApprovedIssuerCatalog(db, 200);
  assert(loaded.length === 1_205, "later catalog pages were truncated");
  assert(
    JSON.stringify(ranges) === JSON.stringify([
      [0, 199],
      [200, 399],
      [400, 599],
      [600, 799],
      [800, 999],
      [1000, 1199],
      [1200, 1399],
    ]),
    "issuer catalog pagination was not explicit and exhaustive",
  );
  assert(
    selectIssuerDiscoveryCandidate(
      loaded,
      new Date("2026-08-20T00:00:00Z"),
    )?.issuer === "ICICI Bank",
    "an early issuer's 1,000+ cards hid a later issuer",
  );
});

Deno.test("a final short approved-catalog page that crosses the deadline cannot select an issuer", async () => {
  let nowMs = 0;
  const db = {
    from(table: string) {
      assert(table === "card_catalog", "catalog deadline read wrong table");
      return {
        select() {
          return this;
        },
        order() {
          return this;
        },
        range() {
          nowMs = 100;
          return Promise.resolve({ data: [], error: null });
        },
      };
    },
  };
  let failedClosed = false;
  try {
    await loadApprovedIssuerCatalog(db, 200, {
      limit: 20,
      used: 0,
      deadlineAt: 50,
      nowMs: () => nowMs,
    });
  } catch (error) {
    failedClosed = String(error).includes(
      "issuer_discovery_catalog_scan_exhausted",
    );
  }
  assert(failedClosed, "deadline-crossing catalog page completed selection");
});

Deno.test("issuer discovery action accepts only bounded scheduled or manual modes", () => {
  assert(
    issuerDiscoveryRunMode({
      action: "issuer_discovery",
      runMode: "scheduled",
    }) === "scheduled",
    "scheduled issuer action was rejected",
  );
  assert(
    issuerDiscoveryRunMode({
      action: "issuer_discovery",
      runMode: "manual",
    }) ===
      "manual",
    "manual issuer action was rejected",
  );
  for (
    const body of [
      { action: "issuer_discovery", runMode: "pilot" },
      { action: "other", runMode: "scheduled" },
      { runMode: "scheduled" },
    ]
  ) {
    assert(
      issuerDiscoveryRunMode(body) === null,
      "invalid action was accepted",
    );
  }
});

Deno.test("issuer discovery scheduler requests reuse the constant-time cron or service credential boundary", async () => {
  const request = (headers: HeadersInit) =>
    new Request("https://edge.example/benefit-enrichment-batch", {
      method: "POST",
      headers,
    });
  assert(
    await authorizedSchedulerRequest(
      request({ "x-cardcompass-cron-secret": "cron-secret" }),
      "service-secret",
      "cron-secret",
    ),
    "existing cron credential was rejected",
  );
  assert(
    await authorizedSchedulerRequest(
      request({ authorization: "Bearer service-secret" }),
      "service-secret",
      "cron-secret",
    ),
    "bounded manual service credential was rejected",
  );
  assert(
    !await authorizedSchedulerRequest(
      request({ "x-cardcompass-cron-secret": "wrong" }),
      "service-secret",
      "cron-secret",
    ),
    "wrong issuer scheduler credential was accepted",
  );
});

Deno.test("same-day issuer discovery claims are idempotent under a unique-insert race", async () => {
  const store = issuerSchedulerStore({});
  const selected = {
    issuer: "Axis Bank",
    canonical_url: "https://www.axis.bank.in/cards/credit-card/neo-credit-card",
  };
  const now = new Date("2026-08-20T00:00:00.000Z");
  const [left, right] = await Promise.all([
    claimIssuerDiscoveryRun(store.db, selected, now),
    claimIssuerDiscoveryRun(store.db, selected, now),
  ]);
  assert(store.jobs.length === 1, "same UTC-day run inserted duplicate rows");
  assert(
    [left.status, right.status].sort().join(",") ===
      "already_running,claimed",
    "concurrent same-day claim did not become claimed plus no-work",
  );
});

Deno.test("stable issuer anchor hashing uses the same whitespace-normalized identity", async () => {
  const store = issuerSchedulerStore({});
  const selected = {
    issuer: "Axis   Bank",
    canonical_url: "https://www.axis.bank.in/cards/credit-card/neo-credit-card",
  };
  const first = await claimIssuerDiscoveryRun(
    store.db,
    selected,
    new Date("2026-08-20T00:00:00.000Z"),
  );
  assert(first.seed, "normalized issuer anchor was not created");
  const second = await claimIssuerDiscoveryRun(
    store.db,
    selected,
    new Date("2026-08-20T00:01:00.000Z"),
  );
  assert(
    second.status === "already_running",
    `stable anchor rejected its own key: ${JSON.stringify(second)}`,
  );
  assert(
    store.jobs.length === 1,
    "normalized issuer created another service job",
  );
});

Deno.test("failed issuer anchors honor retry backoff on an immediate workflow invocation", async () => {
  const selected = {
    issuer: "Axis Bank",
    canonical_url: "https://www.axis.bank.in/cards/credit-card/neo-credit-card",
  };
  const store = issuerSchedulerStore({
    catalog: [{
      bank: selected.issuer,
      card_url: selected.canonical_url,
      card_type: "credit",
    }],
  });
  const first = await claimIssuerDiscoveryRun(
    store.db,
    selected,
    new Date("2026-08-20T00:00:00.000Z"),
  );
  assert(first.seed, "initial issuer anchor was not created");
  const anchor = store.jobs[0];
  Object.assign(anchor, {
    status: "failed",
    attempt_count: 2,
    next_retry_at: "2026-08-21T06:00:00.000Z",
    updated_at: "2026-08-20T00:01:00.000Z",
  });

  const immediate = await loadDiscoverySeed(
    store.db,
    new Date("2026-08-21T00:00:00.000Z"),
    200,
  );
  assert(
    String(immediate.status) === "backoff",
    "future retry anchor was reclaimed",
  );
  assert(immediate.seed === null, "backoff returned a crawl seed");
  assert(anchor.attempt_count === 2, "backoff incremented the attempt counter");
  assert(
    anchor.status === "failed" &&
      anchor.next_retry_at === "2026-08-21T06:00:00.000Z",
    "backoff mutated producer state",
  );
});

Deno.test("every stable claim sees a late mixed-case active legacy lease", async () => {
  const selected = {
    issuer: "Axis Bank",
    canonical_url: "https://www.axis.bank.in/cards/credit-card/neo-credit-card",
  };
  const store = issuerSchedulerStore({});
  const first = await claimIssuerDiscoveryRun(
    store.db,
    selected,
    new Date("2026-08-20T00:00:00.000Z"),
  );
  assert(first.seed, "stable anchor was not created");
  Object.assign(store.jobs[0], {
    status: "resolved",
    next_retry_at: null,
    updated_at: "2026-08-20T00:10:00.000Z",
    evidence: {
      ...store.jobs[0].evidence,
      last_outcome: "complete",
      legacy_reconciliation_complete: true,
    },
  });
  store.jobs.push({
    id: "late-legacy-active",
    user_id: null,
    discovery_source: "issuer_crawl",
    issuer: "aXiS bAnK",
    dedupe_key: "late-date-key",
    status: "discovering",
    attempt_count: 1,
    next_retry_at: "2026-08-21T00:05:00.000Z",
    created_at: "2026-08-20T23:59:00.000Z",
    updated_at: "2026-08-20T23:59:00.000Z",
    evidence: {
      kind: "issuer_directory_run",
      issuer: "AXIS BANK",
      canonical_url: selected.canonical_url,
      run_date: "2026-08-20",
      lease_token: "11111111-1111-4111-8111-111111111111",
    },
  });

  const claim = await claimIssuerDiscoveryRun(
    store.db,
    selected,
    new Date("2026-08-21T00:00:00.000Z"),
  );
  assert(claim.status === "already_running", "late legacy lease was bypassed");
  assert(claim.seed === null, "stable crawl overlapped a legacy holder");
  assert(
    store.jobs[0].status === "resolved",
    "blocked stable anchor was mutated",
  );
});

Deno.test("legacy lease scan tolerates arbitrary surrounding and collapsed issuer whitespace", async () => {
  const selected = {
    issuer: "Axis Bank",
    canonical_url: "https://www.axis.bank.in/cards/credit-card/neo-credit-card",
  };
  const store = issuerSchedulerStore({
    jobs: [{
      id: "whitespace-legacy-active",
      user_id: null,
      discovery_source: "issuer_crawl",
      issuer: " \t aXiS   bAnK \n ",
      dedupe_key: "legacy-date-key",
      status: "discovering",
      attempt_count: 1,
      next_retry_at: "2026-08-21T00:05:00.000Z",
      created_at: "2026-08-20T00:00:00.000Z",
      updated_at: "2026-08-20T00:00:00.000Z",
      evidence: {
        kind: "issuer_directory_run",
        issuer: "Axis Bank",
        canonical_url: selected.canonical_url,
        run_date: "2026-08-20",
        lease_token: "11111111-1111-4111-8111-111111111111",
      },
    }],
  });
  const claim = await claimIssuerDiscoveryRun(
    store.db,
    selected,
    new Date("2026-08-21T00:00:00.000Z"),
  );
  assert(claim.status === "already_running", "whitespace lease was bypassed");
  assert(store.jobs.length === 1, "whitespace lease allowed a new anchor");
});

Deno.test("stable anchor identity disagreements quarantine without cross-issuer routing", async () => {
  const selected = {
    issuer: "Axis Bank",
    canonical_url: "https://www.axis.bank.in/cards/credit-card/neo-credit-card",
  };
  for (
    const mutation of [
      "row_issuer",
      "evidence_issuer",
      "official_url",
      "run_date",
    ] as const
  ) {
    const store = issuerSchedulerStore({});
    const first = await claimIssuerDiscoveryRun(
      store.db,
      selected,
      new Date("2026-08-20T00:00:00.000Z"),
    );
    assert(first.seed, "stable anchor was not created");
    const anchor = store.jobs[0];
    Object.assign(anchor, {
      status: "failed",
      next_retry_at: "2026-08-20T00:00:00.000Z",
      updated_at: "2026-08-20T00:01:00.000Z",
    });
    if (mutation === "row_issuer") anchor.issuer = "HDFC Bank";
    if (mutation === "evidence_issuer") {
      anchor.evidence = { ...anchor.evidence, issuer: "HDFC Bank" };
    }
    if (mutation === "official_url") {
      anchor.evidence = {
        ...anchor.evidence,
        canonical_url:
          "https://www.hdfcbank.com/personal/pay/cards/credit-cards/regalia",
      };
    }
    if (mutation === "run_date") {
      anchor.evidence = { ...anchor.evidence, run_date: "2026-02-30" };
    }

    const claim = await claimIssuerDiscoveryRun(
      store.db,
      selected,
      new Date("2026-08-20T00:02:00.000Z"),
    );
    assert(
      String(claim.status) === "quarantined",
      `${mutation} mismatch was claimed`,
    );
    assert(claim.seed === null, `${mutation} mismatch routed a crawl seed`);
    assert(
      anchor.status === "failed" &&
        anchor.failure_category === "issuer_discovery_quarantined",
      `${mutation} mismatch did not quarantine the producer`,
    );
    const observation = (store.rpcCalls[0].args._source_evidence as any)
      .source_observation;
    assert(
      observation.anchor_job_id === anchor.id &&
        observation.issuer === anchor.issuer &&
        observation.retryable === false &&
        observation.retryability_reason === "manual_repair_required",
      `${mutation} mismatch review was routed as another issuer`,
    );
  }
});

Deno.test("a backlog anchor with a noncanonical stable dedupe key is quarantined in place", async () => {
  const store = issuerSchedulerStore({
    jobs: [{
      id: "tampered-anchor",
      user_id: null,
      discovery_source: "issuer_crawl",
      issuer: "Axis Bank",
      dedupe_key: "f".repeat(64),
      status: "failed",
      attempt_count: 1,
      next_retry_at: "2026-08-20T00:00:00.000Z",
      created_at: "2026-08-20T00:00:00.000Z",
      updated_at: "2026-08-20T00:00:00.000Z",
      evidence: {
        kind: "issuer_directory_anchor",
        issuer: "Axis Bank",
        canonical_url:
          "https://www.axis.bank.in/cards/credit-card/neo-credit-card",
        run_date: "2026-08-20",
        lease_token: "11111111-1111-4111-8111-111111111111",
      },
    }],
    catalog: [{
      bank: "Axis Bank",
      card_url: "https://www.axis.bank.in/cards/credit-card/neo-credit-card",
      card_type: "credit",
    }],
  });
  const claim = await loadDiscoverySeed(
    store.db,
    new Date("2026-08-20T00:01:00.000Z"),
    200,
  );
  assert(claim.status === "quarantined", "tampered anchor spawned a new run");
  assert(claim.seed === null, "tampered anchor returned a crawl seed");
  assert(
    store.jobs.find((row) => row.id === "tampered-anchor")
      ?.failure_category === "issuer_discovery_quarantined",
    "tampered anchor was not quarantined in place",
  );
  assert(
    !store.jobs.some((row) => row.status === "discovering"),
    "a second stable issuer anchor bypassed the tampered producer",
  );
});

Deno.test("every claim quarantines same-issuer stable anchors with corrupt keys even when future or resolved", async () => {
  const selected = {
    issuer: "Axis Bank",
    canonical_url: "https://www.axis.bank.in/cards/credit-card/neo-credit-card",
  };
  for (const status of ["resolved", "failed"] as const) {
    const store = issuerSchedulerStore({});
    const initial = await claimIssuerDiscoveryRun(
      store.db,
      selected,
      new Date("2026-08-20T00:00:00.000Z"),
    );
    assert(initial.seed, "stable anchor fixture was not created");
    Object.assign(store.jobs[0], {
      status,
      dedupe_key: `${status}-corrupt-key`,
      failure_category: status === "failed" ? "transient_fetch" : null,
      next_retry_at: status === "failed" ? "2026-08-22T00:00:00.000Z" : null,
      updated_at: "2026-08-20T00:01:00.000Z",
    });

    const claim = await claimIssuerDiscoveryRun(
      store.db,
      selected,
      new Date("2026-08-21T00:00:00.000Z"),
    );
    assert(claim.status === "quarantined", `${status} corrupt anchor escaped`);
    assert(claim.seed === null, `${status} corrupt anchor returned a seed`);
    assert(
      store.jobs.filter((row) =>
        row.evidence?.kind === "issuer_directory_anchor"
      ).length === 1,
      `${status} corrupt anchor allowed a second stable anchor`,
    );
  }
});

Deno.test("quarantine fences before staging and reuses one semantic review after staging failure", async () => {
  let failOnce = true;
  const store = issuerSchedulerStore({
    jobs: [{
      id: "corrupt-anchor",
      user_id: null,
      discovery_source: "issuer_crawl",
      issuer: "Axis Bank",
      dedupe_key: "corrupt-key",
      status: "failed",
      failure_category: null,
      attempt_count: "invalid",
      next_retry_at: "2026-08-19T00:00:00.000Z",
      created_at: "2026-08-19T00:00:00.000Z",
      updated_at: "2026-08-19T00:00:00.000Z",
      evidence: {
        kind: "issuer_directory_anchor",
        issuer: "Axis Bank",
        canonical_url:
          "https://www.axis.bank.in/cards/credit-card/neo-credit-card",
        run_date: "2026-08-19",
      },
    }],
    failRpc: () => {
      if (!failOnce) return null;
      failOnce = false;
      return new Error("injected_stage_failure");
    },
  });
  const selected = {
    issuer: "Axis Bank",
    canonical_url: "https://www.axis.bank.in/cards/credit-card/neo-credit-card",
  };
  let failed = false;
  try {
    await claimIssuerDiscoveryRun(
      store.db,
      selected,
      new Date("2026-08-20T00:00:00.000Z"),
    );
  } catch (error) {
    failed = String(error).includes("injected_stage_failure");
  }
  assert(failed, "injected staging failure was swallowed");
  assert(
    store.jobs[0].status === "failed" &&
      store.jobs[0].failure_category === "issuer_discovery_quarantined" &&
      store.jobs[0].next_retry_at !== null,
    "staging failure reopened or failed to persist the producer fence",
  );
  const retried = await claimIssuerDiscoveryRun(
    store.db,
    selected,
    new Date("2026-08-20T00:00:01.000Z"),
  );
  assert(retried.status === "quarantined", "fenced producer was reclaimed");
  assert(
    store.rpcCalls.length === 2,
    "staging retry did not occur exactly once",
  );
  assert(
    store.rpcCalls[0].args._dedupe_key ===
      store.rpcCalls[1].args._dedupe_key,
    "mutable producer time changed quarantine review identity",
  );
  assert(
    store.jobs.filter((row) => row.status === "review_required").length === 1,
    "staging retry created duplicate operator reviews",
  );
});

Deno.test("quarantine clear failure remains self-fenced and reuses the staged review", async () => {
  let failClearOnce = true;
  const store = issuerSchedulerStore({
    jobs: [{
      id: "invalid-run",
      user_id: null,
      discovery_source: "issuer_crawl",
      issuer: "Axis Bank",
      dedupe_key: "invalid-run-key",
      status: "failed",
      failure_category: null,
      attempt_count: "invalid",
      next_retry_at: "2026-08-19T00:00:00.000Z",
      created_at: "2026-08-19T00:00:00.000Z",
      updated_at: "2026-08-19T00:00:00.000Z",
      evidence: { kind: "issuer_directory_run", issuer: "Axis Bank" },
    }],
    failUpdate: (payload) => {
      if (payload.next_retry_at !== null || !failClearOnce) return null;
      failClearOnce = false;
      return new Error("injected_clear_failure");
    },
  });
  let failed = false;
  try {
    await loadDiscoverySeed(
      store.db,
      new Date("2026-08-20T00:00:00.000Z"),
      200,
    );
  } catch (error) {
    failed = String(error).includes("injected_clear_failure");
  }
  assert(failed, "injected quarantine clear failure was swallowed");
  assert(
    store.jobs[0].failure_category === "issuer_discovery_quarantined" &&
      store.jobs[0].next_retry_at !== null,
    "clear failure removed the persistent producer fence",
  );
  const firstObservation = structuredClone(
    store.rpcCalls[0].args._source_evidence,
  );
  Object.assign(store.jobs[0].evidence, {
    kind: "issuer_directory_anchor",
    canonical_url: "https://www.axis.bank.in/cards/credit-card/neo-credit-card",
    run_date: "2026-08-19",
  });
  await claimIssuerDiscoveryRun(
    store.db,
    {
      issuer: "Axis Bank",
      canonical_url:
        "https://www.axis.bank.in/cards/credit-card/neo-credit-card",
    },
    new Date("2026-08-20T00:00:01.000Z"),
  );
  assert(
    store.rpcCalls.length === 2 &&
      store.rpcCalls[0].args._dedupe_key ===
        store.rpcCalls[1].args._dedupe_key,
    "caller reclassification changed the producer-stable review identity",
  );
  assert(
    JSON.stringify(store.rpcCalls[1].args._source_evidence) ===
      JSON.stringify(firstObservation),
    "caller reclassification overrode the immutable persisted fence",
  );
  assert(
    store.jobs.filter((row) => row.status === "review_required").length === 1,
    "clear retry duplicated the operator review",
  );
});

Deno.test("operator quarantine retry resets a fresh attempt while reject remains unclaimable", async () => {
  const selected = {
    issuer: "Axis Bank",
    canonical_url: "https://www.axis.bank.in/cards/credit-card/neo-credit-card",
  };
  const retryStore = issuerSchedulerStore({});
  const initial = await claimIssuerDiscoveryRun(
    retryStore.db,
    selected,
    new Date("2026-08-20T00:00:00.000Z"),
  );
  assert(initial.seed, "retry fixture anchor was not created");
  Object.assign(retryStore.jobs[0], {
    status: "failed",
    attempt_count: 0,
    next_retry_at: "2026-08-20T01:00:00.000Z",
    failure_category: "issuer_discovery_operator_retry",
    updated_at: "2026-08-20T01:00:00.000Z",
  });
  const retried = await claimIssuerDiscoveryRun(
    retryStore.db,
    selected,
    new Date("2026-08-20T01:00:01.000Z"),
  );
  assert(retried.seed, "operator retry did not make the anchor resumable");
  assert(
    retryStore.jobs[0].attempt_count === 1,
    "operator retry did not start its explicit fresh attempt policy",
  );

  const rejectStore = issuerSchedulerStore({});
  const rejectInitial = await claimIssuerDiscoveryRun(
    rejectStore.db,
    selected,
    new Date("2026-08-20T00:00:00.000Z"),
  );
  assert(rejectInitial.seed, "reject fixture anchor was not created");
  Object.assign(rejectStore.jobs[0], {
    status: "failed",
    attempt_count: 5,
    next_retry_at: "2026-08-20T00:00:00.000Z",
    updated_at: "2026-08-20T00:01:00.000Z",
  });
  const quarantined = await claimIssuerDiscoveryRun(
    rejectStore.db,
    selected,
    new Date("2026-08-20T00:02:00.000Z"),
  );
  assert(
    quarantined.status === "resume_exhausted",
    "fixture did not quarantine",
  );
  const quarantineReview = rejectStore.jobs.find((row) =>
    row.id !== rejectStore.jobs[0].id && row.status === "review_required"
  );
  assert(quarantineReview, "quarantine review was not staged");
  Object.assign(quarantineReview, { status: "rejected" });
  const callsBeforeRejectReplay = rejectStore.rpcCalls.length;
  const rejected = await claimIssuerDiscoveryRun(
    rejectStore.db,
    selected,
    new Date("2026-08-21T00:00:00.000Z"),
  );
  assert(rejected.status === "quarantined", "rejected anchor became claimable");
  assert(rejected.seed === null, "rejected anchor returned a crawl seed");
  assert(
    rejectStore.rpcCalls.length === callsBeforeRejectReplay,
    "rejected quarantine was reopened into operator review",
  );
});

Deno.test("quarantine retry preserves the terminal episode and a later concurrent failure creates one new review", async () => {
  const selected = {
    issuer: "Axis Bank",
    canonical_url: "https://www.axis.bank.in/cards/credit-card/neo-credit-card",
  };
  const store = issuerSchedulerStore({});
  const initial = await claimIssuerDiscoveryRun(
    store.db,
    selected,
    new Date("2026-08-20T00:00:00.000Z"),
  );
  assert(initial.seed, "episode fixture did not create an anchor");
  const producer = store.jobs[0];
  Object.assign(producer, {
    status: "failed",
    attempt_count: 5,
    next_retry_at: "2026-08-20T01:00:00.000Z",
    failure_category: "attempts_exhausted",
    updated_at: "2026-08-20T01:00:00.000Z",
  });
  await claimIssuerDiscoveryRun(
    store.db,
    selected,
    new Date("2026-08-20T01:00:01.000Z"),
  );
  const firstReview = store.jobs.find((row) => row.id !== producer.id);
  assert(firstReview, "first quarantine episode was not staged");
  assert(
    producer.evidence.quarantine_fence.episode === 1,
    "first quarantine episode was not a durable integer",
  );
  const firstObservation = structuredClone(
    firstReview.evidence.source_observation,
  );
  Object.assign(firstReview, {
    status: "resolved",
    failure_category: null,
    updated_at: "2026-08-20T01:05:00.000Z",
  });
  const terminalFirstReview = structuredClone(firstReview);

  // Mirrors the reviewed SQL Retry transition on the private producer.
  Object.assign(producer, {
    status: "failed",
    attempt_count: 0,
    next_retry_at: "2026-08-20T01:05:00.000Z",
    failure_category: "issuer_discovery_operator_retry",
    updated_at: "2026-08-20T01:05:00.000Z",
  });
  const retried = await claimIssuerDiscoveryRun(
    store.db,
    selected,
    new Date("2026-08-20T01:05:01.000Z"),
  );
  assert(retried.seed, "operator retry was not claimable");
  Object.assign(producer, {
    status: "failed",
    attempt_count: 5,
    next_retry_at: "2026-08-20T02:00:00.000Z",
    failure_category: "attempts_exhausted",
    updated_at: "2026-08-20T02:00:00.000Z",
  });

  await Promise.all([
    claimIssuerDiscoveryRun(
      store.db,
      selected,
      new Date("2026-08-20T02:00:01.000Z"),
    ),
    claimIssuerDiscoveryRun(
      store.db,
      selected,
      new Date("2026-08-20T02:00:01.000Z"),
    ),
  ]);

  const reviews = store.jobs.filter((row) => row.id !== producer.id);
  assert(
    reviews.length === 2,
    `expected two episodes, found ${reviews.length}`,
  );
  assert(
    JSON.stringify(reviews.find((row) => row.id === firstReview.id)) ===
      JSON.stringify(terminalFirstReview),
    "later quarantine rewrote the terminal first review",
  );
  const secondReview = reviews.find((row) => row.id !== firstReview.id);
  assert(
    secondReview?.status === "review_required",
    "later failure did not create one new pending review",
  );
  assert(
    secondReview.evidence.source_observation.episode_identity !==
      firstObservation.episode_identity,
    "later failure reused the prior quarantine episode identity",
  );
  assert(
    producer.evidence.quarantine_fence.episode === 2,
    "later quarantine did not advance the durable episode integer",
  );
});

Deno.test("a recoverable pre-episode quarantine stays SQL-actionable and replays idempotently", async () => {
  const selected = {
    issuer: "Axis Bank",
    canonical_url: "https://www.axis.bank.in/cards/credit-card/neo-credit-card",
  };
  const producerId = "11111111-1111-4111-8111-111111111111";
  const legacyIdentity = `issuer-discovery-quarantine-v1:${producerId}`;
  const legacyReviewKey = await sha256TextFixture(
    `issuer-discovery-quarantine:${producerId}:issuer_discovery_quarantine`,
  );
  const stableKey = await sha256TextFixture(
    "issuer-directory-anchor:axis bank",
  );
  const producer = {
    id: producerId,
    user_id: null,
    discovery_source: "issuer_crawl",
    issuer: "Axis Bank",
    dedupe_key: stableKey,
    status: "failed",
    failure_category: "issuer_discovery_quarantined",
    attempt_count: 1,
    next_retry_at: "2026-08-20T00:00:00.000Z",
    created_at: "2026-08-19T00:00:00.000Z",
    updated_at: "2026-08-19T00:00:00.000Z",
    evidence: {
      kind: "issuer_directory_anchor",
      issuer: "Axis Bank",
      canonical_url: selected.canonical_url,
      run_date: "2026-08-19",
      quarantine_reason: "transient_producer_state",
      quarantine_fence: {
        version: 1,
        classification: "issuer_discovery_quarantine",
        semantic_identity: legacyIdentity,
        anchor_job_id: producerId,
        issuer: "Axis Bank",
        reason: "transient_producer_state",
        retryable: true,
        retryability_reason: "attempt_budget_reset_allowed",
      },
    },
  };
  const store = issuerSchedulerStore({
    jobs: [producer, {
      id: "22222222-2222-4222-8222-222222222222",
      user_id: null,
      discovery_source: "issuer_crawl",
      issuer: "Axis Bank",
      dedupe_key: legacyReviewKey,
      status: "review_required",
      review_item_id: "33333333-3333-4333-8333-333333333333",
      failure_category: null,
      attempt_count: 0,
      next_retry_at: null,
      created_at: "2026-08-19T00:00:01.000Z",
      updated_at: "2026-08-19T00:00:01.000Z",
      evidence: {
        source_observation: { kind: "issuer_discovery_quarantine" },
      },
    }],
  });
  const claim = await claimIssuerDiscoveryRun(
    store.db,
    selected,
    new Date("2026-08-20T00:00:01.000Z"),
  );

  assert(claim.status === "quarantined", "persisted conflict was not fenced");
  assert(store.rpcCalls.length === 1, "legacy quarantine was not staged once");
  assert(
    store.jobs.length === 2 &&
      store.rpcCalls[0].args._dedupe_key === legacyReviewKey,
    "pre-episode recovery abandoned or duplicated its existing review job",
  );
  const fence = producer.evidence.quarantine_fence as Record<string, unknown>;
  const proposedObservation = (store.rpcCalls[0].args._proposed_fields as any)
    .source_observation;
  const evidenceObservation = (store.rpcCalls[0].args._source_evidence as any)
    .source_observation;
  assert(
    fence.episode === null &&
      fence.semantic_identity === legacyIdentity &&
      proposedObservation.episode_identity === null &&
      evidenceObservation.episode_identity === null &&
      JSON.stringify(proposedObservation) ===
        JSON.stringify(evidenceObservation),
    "pre-episode recovery produced a fence/review shape rejected by the Task 7 legacy action branch",
  );
  assert(
    proposedObservation.anchor_job_id === producerId &&
      proposedObservation.reason === "transient_producer_state" &&
      proposedObservation.retryable === true &&
      proposedObservation.retryability_reason ===
        "attempt_budget_reset_allowed",
    "pre-episode recovery lost the exact Retry authority bound by Task 7",
  );

  const completedState = JSON.stringify(store.jobs);
  const replay = await claimIssuerDiscoveryRun(
    store.db,
    selected,
    new Date("2026-08-20T00:00:02.000Z"),
  );
  assert(replay.status === "quarantined", "legacy quarantine replay reopened");
  assert(
    store.rpcCalls.length === 1 &&
      JSON.stringify(store.jobs) === completedState,
    "legacy quarantine replay restaged or rewrote completed recovery state",
  );
});

Deno.test("quarantine conflict counts use the persisted fence reason instead of caller reclassification", async () => {
  const selected = {
    issuer: "Axis Bank",
    canonical_url: "https://www.axis.bank.in/cards/credit-card/neo-credit-card",
  };
  const stableKey = await sha256TextFixture(
    "issuer-directory-anchor:axis bank",
  );
  const producer = {
    id: "persisted-conflict-anchor",
    user_id: null,
    discovery_source: "issuer_crawl",
    issuer: "Axis Bank",
    dedupe_key: stableKey,
    status: "failed",
    failure_category: "issuer_discovery_quarantined",
    attempt_count: 1,
    next_retry_at: "2026-08-20T00:00:00.000Z",
    created_at: "2026-08-19T00:00:00.000Z",
    updated_at: "2026-08-19T00:00:00.000Z",
    evidence: {
      kind: "issuer_directory_anchor",
      issuer: "Axis Bank",
      canonical_url: selected.canonical_url,
      run_date: "2026-08-19",
      quarantine_reason: "invalid_run_evidence",
      quarantine_fence: {
        version: 1,
        classification: "issuer_discovery_quarantine",
        semantic_identity:
          "issuer-discovery-quarantine-v1:persisted-conflict-anchor",
        anchor_job_id: "persisted-conflict-anchor",
        issuer: "Axis Bank",
        reason: "anchor_identity_conflict",
        retryable: false,
        retryability_reason: "manual_repair_required",
      },
    },
  };
  const store = issuerSchedulerStore({ jobs: [producer] });
  const claim = await claimIssuerDiscoveryRun(
    store.db,
    selected,
    new Date("2026-08-20T00:00:01.000Z"),
  );

  assert(claim.status === "quarantined", "persisted conflict was not fenced");
  assert(
    claim.reviewSummary?.conflicts === 1,
    "caller reason hid the persisted conflict count",
  );
});

Deno.test("a terminal pre-episode pending quarantine remains one admin item", async () => {
  const selected = {
    issuer: "Axis Bank",
    canonical_url: "https://www.axis.bank.in/cards/credit-card/neo-credit-card",
  };
  const producerId = "legacy-episode-anchor";
  const stableKey = await sha256TextFixture(
    "issuer-directory-anchor:axis bank",
  );
  const legacyReviewKey = await sha256TextFixture(
    `issuer-discovery-quarantine:${producerId}:issuer_discovery_quarantine`,
  );
  const store = issuerSchedulerStore({
    jobs: [{
      id: producerId,
      user_id: null,
      discovery_source: "issuer_crawl",
      issuer: "Axis Bank",
      dedupe_key: stableKey,
      status: "failed",
      failure_category: "issuer_discovery_quarantined",
      attempt_count: 1,
      next_retry_at: null,
      created_at: "2026-08-19T00:00:00.000Z",
      updated_at: "2026-08-19T00:00:00.000Z",
      evidence: {
        kind: "issuer_directory_anchor",
        issuer: "Axis Bank",
        canonical_url: selected.canonical_url,
        run_date: "2026-08-19",
        quarantine_reason: "anchor_identity_conflict",
        quarantine_fence: {
          version: 1,
          classification: "issuer_discovery_quarantine",
          semantic_identity: `issuer-discovery-quarantine-v1:${producerId}`,
          anchor_job_id: producerId,
          issuer: "Axis Bank",
          reason: "anchor_identity_conflict",
          retryable: false,
          retryability_reason: "manual_repair_required",
        },
      },
    }, {
      id: "legacy-pending-review-job",
      user_id: null,
      discovery_source: "issuer_crawl",
      issuer: "Axis Bank",
      dedupe_key: legacyReviewKey,
      status: "review_required",
      review_item_id: "legacy-pending-review-item",
      failure_category: null,
      attempt_count: 0,
      next_retry_at: null,
      created_at: "2026-08-19T00:00:01.000Z",
      updated_at: "2026-08-19T00:00:01.000Z",
      evidence: {
        source_observation: { kind: "issuer_discovery_quarantine" },
      },
    }],
  });

  const claim = await claimIssuerDiscoveryRun(
    store.db,
    selected,
    new Date("2026-08-20T00:00:01.000Z"),
  );

  assert(claim.status === "quarantined", "terminal legacy fence was reopened");
  assert(store.jobs.length === 2, "legacy pending review was duplicated");
  assert(
    store.rpcCalls.length === 0,
    "terminal legacy review was restaged instead of remaining admin-actionable",
  );
});

Deno.test("unfinished issuer backlog is paginated, resumed oldest-first across UTC days, then releases fresh rotation", async () => {
  const now = new Date("2026-08-22T00:00:00.000Z");
  const oldOutcomes = persistedIssuerOutcomes(41);
  const jobs = [{
    id: "old-axis",
    user_id: null,
    discovery_source: "issuer_crawl",
    issuer: "Axis Bank",
    dedupe_key: "old-axis-key",
    status: "failed",
    attempt_count: 1,
    next_retry_at: "2026-08-20T00:05:00.000Z",
    created_at: "2026-08-20T00:00:00.000Z",
    updated_at: "2026-08-20T00:05:00.000Z",
    evidence: {
      kind: "issuer_directory_run",
      issuer: "Axis Bank",
      canonical_url:
        "https://www.axis.bank.in/cards/credit-card/neo-credit-card",
      run_date: "2026-08-20",
      lease_token: "11111111-1111-4111-8111-111111111111",
      outcome_summaries: oldOutcomes,
    },
  }, {
    id: "later-hdfc",
    user_id: null,
    discovery_source: "issuer_crawl",
    issuer: "HDFC Bank",
    dedupe_key: "later-hdfc-key",
    status: "failed",
    attempt_count: 1,
    next_retry_at: "2026-08-21T00:05:00.000Z",
    created_at: "2026-08-21T00:00:00.000Z",
    updated_at: "2026-08-21T00:05:00.000Z",
    evidence: {
      kind: "issuer_directory_run",
      issuer: "HDFC Bank",
      canonical_url:
        "https://www.hdfcbank.com/personal/pay/cards/credit-cards/regalia",
      run_date: "2026-08-21",
      lease_token: "22222222-2222-4222-8222-222222222222",
      outcome_summaries: [],
    },
  }];
  const catalog = [{
    id: "card-1",
    bank: "ICICI Bank",
    card_url:
      "https://www.icicibank.com/personal-banking/cards/credit-card/coral",
    card_type: "credit",
    is_discontinued: false,
  }];
  const store = issuerSchedulerStore({ jobs, catalog });

  const backlog = await loadIssuerDiscoveryBacklog(store.db, now, 1, 4);
  assert(backlog.length === 2, "bounded backlog pagination lost a later run");
  assert(
    JSON.stringify(store.backlogRanges) ===
      JSON.stringify([[0, 0], [1, 1], [2, 2]]),
    "backlog query did not paginate to its short terminal page",
  );

  const first = await loadDiscoverySeed(store.db, now, 200);
  assert(first.status === "claimed", "oldest failed run was not reclaimed");
  assert(first.seed?.rotationJobId === "old-axis", "newer backlog won");
  assert(first.seed?.runDate === "2026-08-20", "restart changed run date");
  assert(
    (first.seed?.rotationEvidence.outcome_summaries as unknown[]).length === 41,
    "next-day restart lost progress beyond one 40-request budget",
  );
  await recordIssuerDiscoveryOutcome(store.db, first.seed!, {
    complete: true,
    budgetExhausted: false,
    reasons: [],
    counts: { existing: 41 },
    summaries: oldOutcomes,
    considered: 41,
    fetched: 0,
    resumed: 41,
  });

  const second = await loadDiscoverySeed(store.db, now, 200);
  assert(
    second.seed?.rotationJobId === "later-hdfc",
    "multiple unfinished runs were not resumed oldest-first",
  );
  await recordIssuerDiscoveryOutcome(store.db, second.seed!, {
    complete: true,
    budgetExhausted: false,
    reasons: [],
    counts: {},
    summaries: [],
    considered: 0,
    fetched: 0,
    resumed: 0,
  });

  const fresh = await loadDiscoverySeed(store.db, now, 200);
  assert(fresh.status === "claimed", "fresh UTC rotation stayed starved");
  assert(fresh.seed?.runDate === "2026-08-22", "fresh day slot was not used");
  assert(
    fresh.seed?.rotationJobId !== "old-axis" &&
      fresh.seed?.rotationJobId !== "later-hdfc",
    "completed backlog was reclaimed again",
  );
});

Deno.test("a final short issuer-backlog page that crosses the deadline cannot advance selection", async () => {
  let nowMs = 0;
  const store = issuerSchedulerStore({
    jobs: [],
    afterJobRange: () => {
      nowMs = 100;
    },
  });
  let failedClosed = false;
  try {
    await loadIssuerDiscoveryBacklog(
      store.db,
      new Date("2026-08-20T00:00:00.000Z"),
      100,
      20,
      { limit: 20, used: 0, deadlineAt: 50, nowMs: () => nowMs },
    );
  } catch (error) {
    failedClosed = String(error).includes(
      "issuer_discovery_backlog_scan_exhausted",
    );
  }
  assert(failedClosed, "deadline-crossing backlog page completed selection");
  assert(
    store.rpcCalls.length === 0,
    "deadline-crossing backlog mutated state",
  );
});

Deno.test("exhausted oldest backlog is terminally quarantined so the next run can progress", async () => {
  const now = new Date("2026-08-22T00:00:00.000Z");
  const jobs = ["exhausted", "resumable"].map((id, index) => ({
    id,
    user_id: null,
    discovery_source: "issuer_crawl",
    issuer: index === 0 ? "Axis Bank" : "HDFC Bank",
    dedupe_key: `${id}-key`,
    status: "failed",
    attempt_count: index === 0 ? 5 : 1,
    next_retry_at: `2026-08-${20 + index}T00:05:00.000Z`,
    created_at: `2026-08-${20 + index}T00:00:00.000Z`,
    updated_at: `2026-08-${20 + index}T00:05:00.000Z`,
    evidence: {
      kind: "issuer_directory_run",
      issuer: index === 0 ? "Axis Bank" : "HDFC Bank",
      canonical_url: index === 0
        ? "https://www.axis.bank.in/cards/credit-card/neo-credit-card"
        : "https://www.hdfcbank.com/personal/pay/cards/credit-cards/regalia",
      run_date: `2026-08-${20 + index}`,
      lease_token: index === 0
        ? "11111111-1111-4111-8111-111111111111"
        : "22222222-2222-4222-8222-222222222222",
      outcome_summaries: [],
    },
  }));
  const store = issuerSchedulerStore({ jobs });
  const claim = await loadDiscoverySeed(store.db, now, 200);

  assert(
    claim.seed?.rotationJobId === "resumable",
    "exhausted oldest work starved another eligible backlog run",
  );
  const exhausted = store.jobs.find((row) => row.id === "exhausted")!;
  assert(
    exhausted.status === "failed" &&
      exhausted.failure_category === "issuer_discovery_quarantined" &&
      exhausted.next_retry_at === null && !exhausted.review_item_id,
    "resume-attempt ceiling exposed or left the producer claimable",
  );
  const quarantine = store.jobs.find((row) =>
    row !== exhausted && row.status === "review_required"
  );
  assert(
    store.rpcCalls.length === 1 &&
      store.rpcCalls[0].name === "stage_card_catalog_identity_review" &&
      store.rpcCalls[0].args._discovery_job_id === null &&
      typeof quarantine?.review_item_id === "string" &&
      (store.rpcCalls[0].args._validation_warnings as string[]).includes(
        "issuer_discovery_quarantine",
      ),
    "attempt ceiling did not create a separate transactional Task7 review",
  );
  const stagedPayload = JSON.stringify(store.rpcCalls[0].args);
  assert(
    stagedPayload.length < 16_384 &&
      !/lease|token|secret|outcome_summaries/i.test(
        stagedPayload,
      ),
    "quarantine review leaked unbounded or sensitive evidence",
  );
  const observation = (store.rpcCalls[0].args._source_evidence as any)
    .source_observation;
  assert(
    observation.anchor_job_id === "exhausted" &&
      observation.issuer === "Axis Bank" &&
      Object.keys(observation).sort().join(",") ===
        "anchor_job_id,classification,episode_identity,issuer,kind,reason,retryability_reason,retryable" &&
      observation.episode_identity ===
        "issuer-discovery-quarantine-v1:exhausted:1" &&
      observation.retryable === true &&
      observation.retryability_reason === "attempt_budget_reset_allowed",
    "operator review did not expose the exact bounded anchor reference",
  );
});

Deno.test("invalid retained issuer evidence is quarantined once and linked to its exact job", async () => {
  const store = issuerSchedulerStore({
    jobs: [{
      id: "invalid-run",
      user_id: null,
      discovery_source: "issuer_crawl",
      issuer: "Axis Bank",
      dedupe_key: "invalid-run-key",
      status: "failed",
      attempt_count: "malformed",
      next_retry_at: "2026-08-19T00:00:00.000Z",
      created_at: "2026-08-19T00:00:00.000Z",
      updated_at: "2026-08-19T00:00:00.000Z",
      evidence: {
        kind: "issuer_directory_run",
        issuer: "Axis Bank",
        canonical_url: "https://evil.example/cards",
        run_date: "2026-08-19",
        lease_token: "private-lease-token-must-not-be-staged",
      },
    }],
    catalog: [],
  });
  await loadDiscoverySeed(
    store.db,
    new Date("2026-08-20T00:00:00.000Z"),
    200,
  );
  await loadDiscoverySeed(
    store.db,
    new Date("2026-08-20T00:00:01.000Z"),
    200,
  );

  assert(
    store.rpcCalls.length === 1,
    "invalid evidence review was not idempotent",
  );
  const args = store.rpcCalls[0].args;
  assert(
    args._discovery_job_id === null &&
      (args._source_evidence as any).source_observation.anchor_job_id ===
        "invalid-run" &&
      (args._source_evidence as any).source_observation.retryable === false &&
      (args._source_evidence as any).source_observation.retryability_reason ===
        "manual_repair_required" &&
      (args._validation_warnings as string[]).join(",") ===
        "issuer_discovery_quarantine,invalid_run_evidence",
    "invalid evidence review lost its separate anchor reference or classification",
  );
  assert(
    !JSON.stringify(args).includes("private-lease-token-must-not-be-staged"),
    "invalid retained evidence leaked into operator review",
  );
});

Deno.test("issuer quarantine review identity is stable across retry time", async () => {
  const invalidJob = {
    id: "invalid-run",
    user_id: null,
    discovery_source: "issuer_crawl",
    issuer: "Axis Bank",
    dedupe_key: "invalid-run-key",
    status: "failed",
    attempt_count: 1,
    next_retry_at: "2026-08-19T00:00:00.000Z",
    created_at: "2026-08-19T00:00:00.000Z",
    updated_at: "2026-08-19T00:00:00.000Z",
    evidence: {
      kind: "issuer_directory_run",
      issuer: "Axis Bank",
      canonical_url: "https://evil.example/cards",
      run_date: "2026-08-19",
    },
  };
  const hashes: string[] = [];
  for (
    const now of [
      "2026-08-20T00:00:00.000Z",
      "2026-08-20T06:00:00.000Z",
    ]
  ) {
    const store = issuerSchedulerStore({
      jobs: [structuredClone(invalidJob)],
      catalog: [],
    });
    await loadDiscoverySeed(store.db, new Date(now), 200);
    hashes.push(String(store.rpcCalls[0].args._semantic_hash));
  }
  assert(
    hashes[0] === hashes[1],
    "retry time changed the idempotent quarantine review identity",
  );
});

Deno.test("malformed retained attempt state is quarantined before claim", async () => {
  const store = issuerSchedulerStore({
    jobs: [{
      id: "invalid-attempt",
      user_id: null,
      discovery_source: "issuer_crawl",
      issuer: "Axis Bank",
      dedupe_key: "invalid-attempt-key",
      status: "failed",
      attempt_count: "not-a-number",
      next_retry_at: "2026-08-19T00:00:00.000Z",
      created_at: "2026-08-19T00:00:00.000Z",
      updated_at: "2026-08-19T00:00:00.000Z",
      evidence: {
        kind: "issuer_directory_run",
        issuer: "Axis Bank",
        canonical_url:
          "https://www.axis.bank.in/cards/credit-card/neo-credit-card",
        run_date: "2026-08-19",
      },
    }],
    catalog: [],
  });
  const claim = await loadDiscoverySeed(
    store.db,
    new Date("2026-08-20T00:00:00.000Z"),
    200,
  );
  assert(claim.status === "empty", "malformed attempt state was claimed");
  assert(
    store.jobs[0].status === "failed" &&
      store.jobs[0].failure_category === "issuer_discovery_quarantined" &&
      store.rpcCalls[0].args._discovery_job_id === null &&
      (store.rpcCalls[0].args._source_evidence as any).source_observation
          .anchor_job_id === "invalid-attempt",
    "malformed attempt state did not create a separate bounded review",
  );
});

Deno.test("issuer lease token fences expired holders from progress and final writes", async () => {
  const selected = {
    issuer: "Axis Bank",
    canonical_url: "https://www.axis.bank.in/cards/credit-card/neo-credit-card",
  };
  const store = issuerSchedulerStore({});
  const holderA = await claimIssuerDiscoveryRun(
    store.db,
    selected,
    new Date("2026-08-20T00:00:00.000Z"),
  );
  assert(holderA.seed, "holder A did not acquire the run");
  const tokenA = holderA.seed.rotationLeaseToken;
  const holderB = await claimIssuerDiscoveryRun(
    store.db,
    selected,
    new Date("2026-08-20T00:06:00.000Z"),
  );
  assert(holderB.seed, "holder B did not reclaim the expired lease");
  assert(
    holderB.seed.rotationLeaseToken !== tokenA,
    "reclaim reused the stale holder token",
  );
  const tokenB = await persistIssuerRunProgress(
    store.db,
    holderB.seed,
    [{ candidate_key: "b".repeat(64) }],
    { existing: 1 },
  );
  assert(
    tokenB === holderB.seed.rotationLeaseToken && tokenB !== tokenA,
    "progress did not return and install its next lease token",
  );

  for (
    const action of [
      () =>
        persistIssuerRunProgress(
          store.db,
          holderA.seed!,
          [{ candidate_key: "a".repeat(64) }],
          { review: 1 },
        ),
      () =>
        recordIssuerDiscoveryOutcome(store.db, holderA.seed!, {
          complete: true,
          budgetExhausted: false,
          reasons: [],
          counts: {},
          summaries: [],
          considered: 0,
          fetched: 0,
          resumed: 0,
        }),
    ]
  ) {
    let error: unknown;
    try {
      await action();
    } catch (caught) {
      error = caught;
    }
    assert(
      error instanceof Error && error.message === "issuer_discovery_lease_lost",
      "stale holder did not fail with the harmless lease-loss result",
    );
  }
  const live = store.jobs[0];
  assert(live.status === "discovering", "stale holder finalized B's run");
  assert(
    live.evidence.lease_token === tokenB,
    "stale holder overwrote B's progress token",
  );
  assert(
    live.evidence.last_processed_candidate_identity === "b".repeat(64),
    "stale holder overwrote B's durable candidate position",
  );
});

Deno.test("only a positively complete issuer run resolves; incomplete work backs off with evidence", async () => {
  const store = issuerSchedulerStore({});
  const claim = await claimIssuerDiscoveryRun(store.db, {
    issuer: "Axis Bank",
    canonical_url: "https://www.axis.bank.in/cards/credit-card/neo-credit-card",
  });
  assert(claim.seed, "issuer run was not claimed");
  await recordIssuerDiscoveryOutcome(store.db, claim.seed, {
    complete: false,
    budgetExhausted: false,
    reasons: ["product_inventory_unproven"],
    counts: { supporting: 1 },
    summaries: [{ candidate_key: "a".repeat(64) }],
    considered: 1,
    fetched: 1,
    resumed: 0,
  });

  const row = store.jobs[0];
  assert(row.status === "failed", "an incomplete run incorrectly resolved");
  assert(
    Date.parse(row.next_retry_at) > Date.parse(row.updated_at),
    "failed run did not receive bounded retry backoff",
  );
  assert(
    row.evidence.outcome_summaries[0].candidate_key === "a".repeat(64),
    "failed finalization discarded persisted evidence",
  );
});

Deno.test("a nominally complete issuer result with reasons or budget exhaustion stays resumable", async () => {
  for (
    const outcome of [{
      complete: true,
      budgetExhausted: false,
      reasons: ["product_directory_scope_mismatch"],
    }, {
      complete: true,
      budgetExhausted: true,
      reasons: [],
    }]
  ) {
    const store = issuerSchedulerStore({});
    const claim = await claimIssuerDiscoveryRun(store.db, {
      issuer: "Axis Bank",
      canonical_url:
        "https://www.axis.bank.in/cards/credit-card/neo-credit-card",
    });
    assert(claim.seed, "issuer run was not claimed");
    await recordIssuerDiscoveryOutcome(store.db, claim.seed, {
      ...outcome,
      counts: {},
      summaries: [],
      considered: 0,
      fetched: 0,
      resumed: 0,
    });
    assert(
      store.jobs[0].status === "failed",
      "non-positive complete result incorrectly resolved",
    );
  }
});

Deno.test("candidate persistence, progress, publication, and final-write exceptions remain resumable", async () => {
  const selected = {
    issuer: "Axis Bank",
    canonical_url: "https://www.axis.bank.in/cards/credit-card/neo-credit-card",
  };
  const candidate = {
    candidateKey: "c".repeat(64),
    disposition: "candidate",
    attempted: true,
    classification: {
      kind: "card_product",
      canonicalUrl:
        "https://www.axis.bank.in/cards/credit-card/privilege-credit-card",
      proposedName: "Privilege",
      aliases: ["Axis Privilege Credit Card"],
      confidence: 0.95,
      warnings: [],
      sanitizedEvidence: ["Axis Privilege Credit Card"],
    },
  };
  const cases = [
    {
      name: "candidate persistence",
      failUpdate: undefined,
      dependencies: {
        discover: async (input: any) => {
          await input.onCandidateOutcome(candidate);
          return completeIssuerCrawl({ consideredCount: 1, fetchedCount: 1 });
        },
        persistCrawlerCandidate: async () => {
          throw new Error("candidate_persist_failed");
        },
      },
    },
    {
      name: "progress PostgREST",
      failUpdate: (payload: Record<string, any>) =>
        payload.status === undefined && payload.evidence?.outcome_summaries
          ? new Error("progress_postgrest_failed")
          : null,
      dependencies: {
        discover: async (input: any) => {
          await input.onCandidateOutcome(candidate);
          return completeIssuerCrawl({ consideredCount: 1, fetchedCount: 1 });
        },
        persistCrawlerCandidate: async () => ({ outcome: "review" as const }),
      },
    },
    {
      name: "publication",
      failUpdate: undefined,
      dependencies: {
        discover: async () => completeIssuerCrawl(),
        loadKnownIssuerCards: async () => [],
        stageCompleteAbsenceReviews: async () => {
          throw new Error("publication_failed");
        },
      },
    },
    {
      name: "final write",
      failUpdate: (() => {
        let failed = false;
        return (payload: Record<string, any>) => {
          if (!failed && payload.status === "resolved") {
            failed = true;
            return new Error("final_postgrest_failed");
          }
          return null;
        };
      })(),
      dependencies: {
        discover: async () => completeIssuerCrawl(),
        loadKnownIssuerCards: async () => [],
        stageCompleteAbsenceReviews: async () => [],
      },
    },
  ];

  for (const testCase of cases) {
    const store = issuerSchedulerStore({ failUpdate: testCase.failUpdate });
    const claim = await claimIssuerDiscoveryRun(store.db, selected);
    assert(claim.seed, `${testCase.name} run was not claimed`);
    let error: unknown;
    try {
      await runIssuerDiscovery(
        store.db,
        claim.seed,
        Date.now() + 60_000,
        testCase.dependencies,
      );
    } catch (caught) {
      error = caught;
    }
    assert(error instanceof Error, `${testCase.name} did not surface failure`);
    assert(
      store.jobs[0].status === "failed",
      `${testCase.name} exception left a falsely complete run`,
    );
    assert(
      Date.parse(store.jobs[0].next_retry_at) >
        Date.parse(store.jobs[0].updated_at),
      `${testCase.name} exception did not back off`,
    );
  }
});

Deno.test("lease loss returns a harmless lost-lease summary without stale finalization", async () => {
  const store = issuerSchedulerStore({});
  const claim = await claimIssuerDiscoveryRun(store.db, {
    issuer: "Axis Bank",
    canonical_url: "https://www.axis.bank.in/cards/credit-card/neo-credit-card",
  });
  assert(claim.seed, "issuer run was not claimed");
  const liveToken = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
  const summary = await runIssuerDiscovery(
    store.db,
    claim.seed,
    Date.now() + 60_000,
    {
      discover: async (input: any) => {
        await input.onCandidateOutcome({
          candidateKey: "d".repeat(64),
          disposition: "candidate",
          attempted: true,
          classification: {
            kind: "card_product",
            canonicalUrl:
              "https://www.axis.bank.in/cards/credit-card/privilege-credit-card",
            proposedName: "Privilege",
            aliases: ["Axis Privilege Credit Card"],
            confidence: 0.95,
            warnings: [],
            sanitizedEvidence: ["Axis Privilege Credit Card"],
          },
        });
        return completeIssuerCrawl();
      },
      persistCrawlerCandidate: async () => {
        store.jobs[0].evidence = {
          ...store.jobs[0].evidence,
          lease_token: liveToken,
          last_processed_candidate_identity: "b".repeat(64),
        };
        return { outcome: "review" as const };
      },
    },
  );

  assert(summary.status === "lost_lease", "lease loss was not returned");
  assert(
    store.jobs[0].status === "discovering" &&
      store.jobs[0].evidence.lease_token === liveToken,
    "stale holder finalized or overwrote the new lease",
  );
});

Deno.test("one stable issuer anchor is reused across UTC slots with bounded history", async () => {
  const store = issuerSchedulerStore({});
  const selected = {
    issuer: "Axis Bank",
    canonical_url: "https://www.axis.bank.in/cards/credit-card/neo-credit-card",
  };
  const first = await claimIssuerDiscoveryRun(
    store.db,
    selected,
    new Date("2026-08-20T00:00:00.000Z"),
  );
  assert(first.seed, "first UTC slot was not claimed");
  await recordIssuerDiscoveryOutcome(store.db, first.seed, {
    complete: true,
    budgetExhausted: false,
    reasons: [],
    counts: { existing: 1 },
    summaries: [{ candidate_key: "e".repeat(64) }],
    considered: 1,
    fetched: 1,
    resumed: 0,
  });
  const sameDay = await claimIssuerDiscoveryRun(
    store.db,
    selected,
    new Date("2026-08-20T23:59:00.000Z"),
  );
  assert(sameDay.status === "already_completed", "same slot reran");
  const nextDay = await claimIssuerDiscoveryRun(
    store.db,
    selected,
    new Date("2026-08-21T00:00:00.000Z"),
  );

  assert(nextDay.seed, "next UTC slot did not reuse the anchor");
  assert(store.jobs.length === 1, "cross-date duplicate issuer rows remain");
  assert(
    nextDay.seed.rotationJobId === first.seed.rotationJobId,
    "next slot changed the persistent issuer anchor",
  );
  assert(
    nextDay.seed.rotationEvidence.run_date === "2026-08-21" &&
      nextDay.seed.rotationEvidence.rotation_slot === 20_686 &&
      nextDay.seed.rotationEvidence.run_attempt === 1 &&
      (nextDay.seed.rotationEvidence.outcome_summaries as unknown[]).length ===
        0,
    "new slot did not reset and persist its slot, attempt, and cursor",
  );
  const history = nextDay.seed.rotationEvidence.run_history as Array<
    Record<string, unknown>
  >;
  assert(
    history.length === 1 && history[0].run_date === "2026-08-20" &&
      history[0].last_outcome === "complete",
    "prior slot was not retained in bounded history",
  );
});

Deno.test("a reconciled stable anchor still performs one bounded mixed-deployment scan", async () => {
  const store = issuerSchedulerStore({});
  const selected = {
    issuer: "Axis Bank",
    canonical_url: "https://www.axis.bank.in/cards/credit-card/neo-credit-card",
  };
  const first = await claimIssuerDiscoveryRun(
    store.db,
    selected,
    new Date("2026-08-20T00:00:00.000Z"),
  );
  assert(first.seed, "stable anchor was not created");
  store.backlogRanges.length = 0;
  const second = await claimIssuerDiscoveryRun(
    store.db,
    selected,
    new Date("2026-08-20T00:01:00.000Z"),
  );
  assert(second.status === "already_running", "active anchor was not fenced");
  assert(
    JSON.stringify(store.backlogRanges) ===
      JSON.stringify([[0, 99], [0, 99]]),
    "stable claim trusted a permanent reconciliation marker",
  );
});

Deno.test("a late legacy backlog row forces reconciliation despite the stable marker", async () => {
  const store = issuerSchedulerStore({});
  const selected = {
    issuer: "Axis Bank",
    canonical_url: "https://www.axis.bank.in/cards/credit-card/neo-credit-card",
  };
  const first = await claimIssuerDiscoveryRun(
    store.db,
    selected,
    new Date("2026-08-20T00:00:00.000Z"),
  );
  assert(first.seed, "stable anchor was not created");
  await recordIssuerDiscoveryOutcome(store.db, first.seed, {
    complete: true,
    budgetExhausted: false,
    reasons: [],
    counts: {},
    summaries: [],
    considered: 0,
    fetched: 0,
    resumed: 0,
  });
  store.jobs.push({
    id: "late-legacy",
    user_id: null,
    discovery_source: "issuer_crawl",
    issuer: "Axis Bank",
    dedupe_key: "late-dated-key",
    status: "failed",
    attempt_count: 1,
    next_retry_at: "2026-08-20T12:00:00.000Z",
    created_at: "2026-08-20T00:00:00.000Z",
    updated_at: "2026-08-20T12:00:00.000Z",
    evidence: {
      kind: "issuer_directory_run",
      issuer: "Axis Bank",
      canonical_url:
        "https://www.axis.bank.in/cards/credit-card/neo-credit-card",
      run_date: "2026-08-20",
      lease_token: "11111111-1111-4111-8111-111111111111",
    },
  });
  const claim = await loadDiscoverySeed(
    store.db,
    new Date("2026-08-21T00:00:00.000Z"),
    200,
  );
  assert(claim.status === "legacy_conflict", "late legacy work was crawled");
  assert(
    store.jobs.find((row) => row.id === "late-legacy")?.status ===
        "failed" &&
      store.jobs.find((row) => row.id === "late-legacy")?.failure_category ===
        "issuer_discovery_quarantined",
    "late legacy work did not remain a private quarantined producer",
  );
});

Deno.test("new issuer slots sanitize malformed historical counters", async () => {
  const store = issuerSchedulerStore({});
  const selected = {
    issuer: "Axis Bank",
    canonical_url: "https://www.axis.bank.in/cards/credit-card/neo-credit-card",
  };
  const first = await claimIssuerDiscoveryRun(
    store.db,
    selected,
    new Date("2026-08-20T00:00:00.000Z"),
  );
  assert(first.seed, "first slot was not claimed");
  await recordIssuerDiscoveryOutcome(store.db, first.seed, {
    complete: true,
    budgetExhausted: false,
    reasons: [],
    counts: {},
    summaries: [],
    considered: 0,
    fetched: 0,
    resumed: 0,
  });
  store.jobs[0].evidence.considered_count = "malformed";
  store.jobs[0].evidence.fetched_count = -99;
  const next = await claimIssuerDiscoveryRun(
    store.db,
    selected,
    new Date("2026-08-21T00:00:00.000Z"),
  );
  const history = next.seed?.rotationEvidence.run_history as Array<
    Record<string, unknown>
  >;
  assert(
    history[0].considered_count === 0 && history[0].fetched_count === 0,
    "malformed historical counters escaped the bounded run history",
  );
});

Deno.test("issuer run history strips unknown retained fields before carrying slots forward", async () => {
  const store = issuerSchedulerStore({});
  const selected = {
    issuer: "Axis Bank",
    canonical_url: "https://www.axis.bank.in/cards/credit-card/neo-credit-card",
  };
  const first = await claimIssuerDiscoveryRun(
    store.db,
    selected,
    new Date("2026-08-20T00:00:00.000Z"),
  );
  assert(first.seed, "first slot was not claimed");
  await recordIssuerDiscoveryOutcome(store.db, first.seed, {
    complete: true,
    budgetExhausted: false,
    reasons: [],
    counts: {},
    summaries: [],
    considered: 0,
    fetched: 0,
    resumed: 0,
  });
  store.jobs[0].evidence.run_history = [{
    run_date: "2026-08-19",
    last_outcome: "complete",
    secret: "must-not-survive",
  }];
  const next = await claimIssuerDiscoveryRun(
    store.db,
    selected,
    new Date("2026-08-21T00:00:00.000Z"),
  );
  const history = next.seed?.rotationEvidence.run_history as Array<
    Record<string, unknown>
  >;
  assert(history.length === 2, "valid prior run history was discarded");
  assert(
    history.every((entry) => !Object.hasOwn(entry, "secret")),
    "unknown retained history fields escaped the bounded schema",
  );
});

Deno.test("an active legacy dated row fences a new-day claim for the same issuer", async () => {
  const store = issuerSchedulerStore({
    jobs: [{
      id: "legacy-active",
      user_id: null,
      discovery_source: "issuer_crawl",
      issuer: "Axis Bank",
      dedupe_key: "dated-key",
      status: "discovering",
      attempt_count: 1,
      next_retry_at: "2026-08-21T00:05:00.000Z",
      created_at: "2026-08-20T00:00:00.000Z",
      updated_at: "2026-08-20T00:00:00.000Z",
      evidence: {
        kind: "issuer_directory_run",
        issuer: "Axis Bank",
        canonical_url:
          "https://www.axis.bank.in/cards/credit-card/neo-credit-card",
        run_date: "2026-08-20",
        lease_token: "11111111-1111-4111-8111-111111111111",
      },
    }],
  });
  const claim = await claimIssuerDiscoveryRun(
    store.db,
    {
      issuer: "Axis Bank",
      canonical_url:
        "https://www.axis.bank.in/cards/credit-card/neo-credit-card",
    },
    new Date("2026-08-21T00:00:00.000Z"),
  );
  assert(claim.status === "already_running", "new day bypassed legacy lease");
  assert(store.jobs.length === 1, "new day inserted a competing issuer row");
});

Deno.test("unrelated issuer outcome rows cannot hide a legacy issuer lease", async () => {
  const unrelated = Array.from({ length: 200 }, (_, index) => ({
    id: `candidate-${index}`,
    user_id: null,
    discovery_source: "issuer_crawl",
    issuer: "Axis Bank",
    dedupe_key: `candidate-key-${index}`,
    status: "resolved",
    attempt_count: 0,
    created_at: `2026-08-19T00:${
      String(Math.floor(index / 60)).padStart(2, "0")
    }:${String(index % 60).padStart(2, "0")}.000Z`,
    updated_at: "2026-08-19T00:00:00.000Z",
    evidence: { kind: "issuer_candidate_outcome" },
  }));
  const active = {
    id: "legacy-active",
    user_id: null,
    discovery_source: "issuer_crawl",
    issuer: "Axis Bank",
    dedupe_key: "dated-key",
    status: "discovering",
    attempt_count: 1,
    next_retry_at: "2026-08-21T00:05:00.000Z",
    created_at: "2026-08-20T00:00:00.000Z",
    updated_at: "2026-08-20T00:00:00.000Z",
    evidence: {
      kind: "issuer_directory_run",
      issuer: "Axis Bank",
      canonical_url:
        "https://www.axis.bank.in/cards/credit-card/neo-credit-card",
      run_date: "2026-08-20",
      lease_token: "11111111-1111-4111-8111-111111111111",
    },
  };
  const store = issuerSchedulerStore({ jobs: [...unrelated, active] });
  const claim = await claimIssuerDiscoveryRun(
    store.db,
    {
      issuer: "Axis Bank",
      canonical_url:
        "https://www.axis.bank.in/cards/credit-card/neo-credit-card",
    },
    new Date("2026-08-21T00:00:00.000Z"),
  );
  assert(claim.status === "already_running", "legacy lease was hidden");
  assert(store.jobs.length === 201, "a competing stable anchor was inserted");
});

Deno.test("bounded legacy pagination reaches an active lease beyond two pages", async () => {
  const history = Array.from({ length: 200 }, (_, index) => ({
    id: `history-${index}`,
    user_id: null,
    discovery_source: "issuer_crawl",
    issuer: "Axis Bank",
    dedupe_key: `dated-history-${index}`,
    status: "resolved",
    attempt_count: 1,
    created_at: `2025-${String(1 + Math.floor(index / 28)).padStart(2, "0")}-${
      String(1 + (index % 28)).padStart(2, "0")
    }T00:00:00.000Z`,
    updated_at: "2026-08-19T00:00:00.000Z",
    evidence: {
      kind: "issuer_directory_run",
      issuer: "Axis Bank",
      canonical_url:
        "https://www.axis.bank.in/cards/credit-card/neo-credit-card",
      run_date: "2026-08-19",
      last_outcome: "complete",
    },
  }));
  const active = {
    id: "legacy-active-page-three",
    user_id: null,
    discovery_source: "issuer_crawl",
    issuer: "Axis Bank",
    dedupe_key: "dated-active-page-three",
    status: "discovering",
    attempt_count: 1,
    next_retry_at: "2026-08-21T00:05:00.000Z",
    created_at: "2026-08-20T00:00:00.000Z",
    updated_at: "2026-08-20T00:00:00.000Z",
    evidence: {
      kind: "issuer_directory_run",
      issuer: "Axis Bank",
      canonical_url:
        "https://www.axis.bank.in/cards/credit-card/neo-credit-card",
      run_date: "2026-08-20",
      lease_token: "11111111-1111-4111-8111-111111111111",
    },
  };
  const store = issuerSchedulerStore({ jobs: [...history, active] });
  const claim = await claimIssuerDiscoveryRun(
    store.db,
    {
      issuer: "Axis Bank",
      canonical_url:
        "https://www.axis.bank.in/cards/credit-card/neo-credit-card",
    },
    new Date("2026-08-21T00:00:00.000Z"),
  );
  assert(claim.status === "already_running", "page-three lease was hidden");
  assert(store.jobs.length === 201, "pagination inserted a competing anchor");
});

Deno.test("multiple due legacy rows fail closed into exact linked quarantine reviews", async () => {
  const jobs = ["older", "newer"].map((id, index) => ({
    id,
    user_id: null,
    discovery_source: "issuer_crawl",
    issuer: "Axis Bank",
    dedupe_key: `dated-${id}`,
    status: "failed",
    attempt_count: 1,
    next_retry_at: `2026-08-${19 + index}T00:00:00.000Z`,
    created_at: `2026-08-${19 + index}T00:00:00.000Z`,
    updated_at: `2026-08-${19 + index}T00:00:00.000Z`,
    evidence: {
      kind: "issuer_directory_run",
      issuer: "Axis Bank",
      canonical_url:
        "https://www.axis.bank.in/cards/credit-card/neo-credit-card",
      run_date: `2026-08-${19 + index}`,
      lease_token: index === 0
        ? "11111111-1111-4111-8111-111111111111"
        : "22222222-2222-4222-8222-222222222222",
    },
  }));
  const store = issuerSchedulerStore({ jobs });
  const claim = await claimIssuerDiscoveryRun(
    store.db,
    {
      issuer: "Axis Bank",
      canonical_url:
        "https://www.axis.bank.in/cards/credit-card/neo-credit-card",
    },
    new Date("2026-08-21T00:00:00.000Z"),
  );

  assert(claim.status === "legacy_conflict", "duplicate legacy rows crawled");
  assert(store.jobs.length === 4, "conflict did not use separate review jobs");
  const stagedAnchorIds = store.rpcCalls.map((call) =>
    (call.args._source_evidence as any).source_observation.anchor_job_id
  ).sort();
  assert(
    store.rpcCalls.length === 2 &&
      store.rpcCalls.every((call) =>
        call.name === "stage_card_catalog_identity_review" &&
        call.args._discovery_job_id === null &&
        (call.args._validation_warnings as string[]).includes(
          "issuer_discovery_quarantine",
        )
      ) && JSON.stringify(stagedAnchorIds) ===
        JSON.stringify(["newer", "older"]),
    "legacy conflict did not create separate exact-reference Task7 reviews",
  );
  assert(
    (claim as any).reviewSummary?.staged === 2 &&
      (claim as any).reviewSummary?.quarantined === 2 &&
      (claim as any).reviewSummary?.conflicts === 2,
    "legacy conflict summary hid created operator work",
  );
});

Deno.test("legacy conflict quarantine is bounded and drains across invocations", async () => {
  const jobs = Array.from({ length: 25 }, (_, index) => ({
    id: `legacy-${String(index).padStart(2, "0")}`,
    user_id: null,
    discovery_source: "issuer_crawl",
    issuer: "Axis Bank",
    dedupe_key: `dated-legacy-${index}`,
    status: "failed",
    attempt_count: 1,
    next_retry_at: "2026-08-19T00:00:00.000Z",
    created_at: `2026-08-19T00:00:${String(index).padStart(2, "0")}.000Z`,
    updated_at: "2026-08-19T00:00:00.000Z",
    evidence: {
      kind: "issuer_directory_run",
      issuer: "Axis Bank",
      canonical_url:
        "https://www.axis.bank.in/cards/credit-card/neo-credit-card",
      run_date: "2026-08-19",
    },
  }));
  const store = issuerSchedulerStore({ jobs });
  const selected = {
    issuer: "Axis Bank",
    canonical_url: "https://www.axis.bank.in/cards/credit-card/neo-credit-card",
  };
  const first = await claimIssuerDiscoveryRun(
    store.db,
    selected,
    new Date("2026-08-20T00:00:00.000Z"),
  );
  assert(first.status === "legacy_conflict", "legacy conflict was not fenced");
  assert(
    store.rpcCalls.length === 20,
    "one invocation staged an unbounded batch",
  );
  assert(
    (first as any).reviewSummary?.remaining === 5,
    "first bounded batch did not report its exact remaining count",
  );
  const second = await claimIssuerDiscoveryRun(
    store.db,
    selected,
    new Date("2026-08-20T00:01:00.000Z"),
  );
  assert(second.status === "legacy_conflict", "remaining conflict was crawled");
  assert(
    Number(store.rpcCalls.length) === 25,
    "bounded conflict backlog did not drain",
  );
  assert(
    (second as any).reviewSummary?.remaining === 0,
    "drained conflict batch retained a phantom remaining count",
  );
  assert(
    store.jobs.length === 50,
    "conflict drain did not isolate review jobs",
  );
});

Deno.test("one invocation quarantines at most twenty of one thousand corrupt stable anchors", async () => {
  const canonicalUrl =
    "https://www.axis.bank.in/cards/credit-card/neo-credit-card";
  const jobs = Array.from({ length: 1000 }, (_, index) => ({
    id: `corrupt-anchor-${String(index).padStart(4, "0")}`,
    user_id: null,
    discovery_source: "issuer_crawl",
    issuer: "Axis Bank",
    dedupe_key: `corrupt-stable-key-${index}`,
    status: "resolved",
    failure_category: null,
    attempt_count: 1,
    next_retry_at: null,
    created_at: `2026-01-01T00:${String(index % 60).padStart(2, "0")}:00.000Z`,
    updated_at: "2026-08-19T00:00:00.000Z",
    evidence: {
      kind: "issuer_directory_anchor",
      issuer: "Axis Bank",
      canonical_url: canonicalUrl,
      run_date: "2026-08-19",
    },
  }));
  const store = issuerSchedulerStore({ jobs });
  const claim = await claimIssuerDiscoveryRun(
    store.db,
    { issuer: "Axis Bank", canonical_url: canonicalUrl },
    new Date("2026-08-20T00:00:00.000Z"),
  );
  assert(claim.status === "quarantined", "corrupt batch was not fenced");
  assert(claim.seed === null, "corrupt batch returned crawl work");
  assert(store.rpcCalls.length === 20, "quarantine staging exceeded its cap");
  assert(
    (claim as any).reviewSummary?.quarantined === 20 &&
      (claim as any).reviewSummary?.staged === 20 &&
      (claim as any).reviewSummary?.conflicts === 20 &&
      (claim as any).reviewSummary?.remaining === 980,
    "bounded corruption summary hid processed or remaining work",
  );
  assert(
    !store.jobs.some((row) => row.status === "discovering"),
    "seed crawl began after quarantine consumed the invocation batch",
  );
  const second = await claimIssuerDiscoveryRun(
    store.db,
    { issuer: "Axis Bank", canonical_url: canonicalUrl },
    new Date("2026-08-20T00:01:00.000Z"),
  );
  assert(
    Number(store.rpcCalls.length) === 40 &&
      (second as any).reviewSummary?.remaining === 960,
    "the next bounded invocation did not advance past already staged anchors",
  );
});

Deno.test("issuer anchor scan catches producer-shaped key and issuer corruption without guessing from ordinary review rows", async () => {
  const canonicalUrl =
    "https://www.axis.bank.in/cards/credit-card/neo-credit-card";
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode("issuer-directory-anchor:axis bank"),
  );
  const expectedKey = [...new Uint8Array(digest)].map((byte) =>
    byte.toString(16).padStart(2, "0")
  ).join("");
  const fixtures = [
    {
      id: "evidence-issuer-match",
      issuer: "Wrong Bank",
      dedupe_key: "corrupt-key",
      evidence: {
        kind: "issuer_directory_anchor",
        issuer: " Axis   Bank ",
        canonical_url: canonicalUrl,
        run_date: "2026-08-19",
      },
    },
    {
      id: "expected-key-match",
      issuer: "Wrong Bank",
      dedupe_key: expectedKey,
      evidence: {
        kind: "untrusted-kind",
        issuer: "Another Bank",
        canonical_url: canonicalUrl,
        run_date: "2026-08-19",
      },
    },
  ];
  for (const fixture of fixtures) {
    const store = issuerSchedulerStore({
      jobs: [{
        ...fixture,
        user_id: null,
        discovery_source: "issuer_crawl",
        status: "resolved",
        failure_category: null,
        attempt_count: 1,
        next_retry_at: null,
        created_at: "2026-08-19T00:00:00.000Z",
        updated_at: "2026-08-19T00:00:00.000Z",
      }],
    });
    const claim = await claimIssuerDiscoveryRun(
      store.db,
      { issuer: "Axis Bank", canonical_url: canonicalUrl },
      new Date("2026-08-20T00:00:00.000Z"),
    );
    assert(claim.status === "quarantined", `${fixture.id} escaped quarantine`);
    assert(claim.seed === null, `${fixture.id} returned crawl work`);
    assert(
      store.jobs.filter((row) => row.status === "discovering").length === 0,
      `${fixture.id} allowed a replacement stable anchor`,
    );
    assert(
      store.orCalls.length > 0,
      `${fixture.id} skipped the all-field scan`,
    );
  }
});

Deno.test("ordinary Task7 identity lifecycle catalog-review and candidate rows survive an issuer anchor claim unchanged", async () => {
  const canonicalUrl =
    "https://www.axis.bank.in/cards/credit-card/neo-credit-card";
  const ordinaryRows = [{
    id: "identity-review",
    user_id: null,
    discovery_source: "issuer_crawl",
    issuer: "Axis Bank",
    dedupe_key: "identity-review-key",
    status: "review_required",
    review_item_id: "identity-review-item",
    failure_category: null,
    attempt_count: 0,
    next_retry_at: null,
    created_at: "2026-08-18T00:00:00.000Z",
    updated_at: "2026-08-18T00:00:00.000Z",
    evidence: { semantic_product_hash: "a".repeat(64) },
  }, {
    id: "lifecycle-review",
    user_id: null,
    discovery_source: "issuer_crawl",
    issuer: "Axis Bank",
    dedupe_key: "lifecycle-review-key",
    status: "rejected",
    review_item_id: "lifecycle-review-item",
    failure_category: "operator_rejected",
    attempt_count: 0,
    next_retry_at: null,
    created_at: "2026-08-18T00:00:01.000Z",
    updated_at: "2026-08-18T00:00:01.000Z",
    evidence: {
      card_id: "11111111-1111-4111-8111-111111111111",
      lifecycle_state: "discontinued",
    },
  }, {
    id: "catalog-review",
    user_id: null,
    discovery_source: "issuer_crawl",
    issuer: "Axis Bank",
    dedupe_key: "catalog-review-key",
    status: "review_required",
    review_item_id: "catalog-review-item",
    failure_category: null,
    attempt_count: 0,
    next_retry_at: null,
    created_at: "2026-08-18T00:00:02.000Z",
    updated_at: "2026-08-18T00:00:02.000Z",
    evidence: {
      source_observation: {
        kind: "complete_issuer_directory_absence",
      },
    },
  }, {
    id: "candidate-outcome",
    user_id: null,
    discovery_source: "issuer_crawl",
    issuer: "Axis Bank",
    dedupe_key: "candidate-outcome-key",
    status: "rejected",
    review_item_id: null,
    failure_category: "not_a_card",
    attempt_count: 0,
    next_retry_at: null,
    created_at: "2026-08-18T00:00:03.000Z",
    updated_at: "2026-08-18T00:00:03.000Z",
    evidence: { kind: "issuer_candidate_outcome", disposition: "rejected" },
  }];
  const before = structuredClone(ordinaryRows);
  const store = issuerSchedulerStore({ jobs: ordinaryRows });

  const claim = await claimIssuerDiscoveryRun(
    store.db,
    { issuer: "Axis Bank", canonical_url: canonicalUrl },
    new Date("2026-08-20T00:00:00.000Z"),
  );

  assert(claim.status === "claimed" && claim.seed, "anchor was not claimed");
  assert(store.rpcCalls.length === 0, "ordinary Task7 rows were quarantined");
  assert(
    JSON.stringify(store.jobs.slice(0, before.length)) ===
      JSON.stringify(before),
    "an ordinary Task7 row was terminalized or relinked",
  );
  assert(
    store.jobs.filter((row) => row.evidence?.kind === "issuer_directory_anchor")
      .length === 1,
    "claim did not create exactly one durable directory producer",
  );
});

Deno.test("issuer producer scan paginates past one thousand retained anchors", async () => {
  const canonicalUrl =
    "https://www.axis.bank.in/cards/credit-card/neo-credit-card";
  const jobs = Array.from({ length: 1005 }, (_, index) => ({
    id: `combined-corrupt-${String(index).padStart(4, "0")}`,
    user_id: null,
    discovery_source: "issuer_crawl",
    issuer: "Wrong Bank",
    dedupe_key: `corrupt-${index}`,
    status: "resolved",
    failure_category: null,
    attempt_count: 1,
    next_retry_at: null,
    created_at: `2026-01-01T00:${String(index % 60).padStart(2, "0")}:00.000Z`,
    updated_at: "2026-08-19T00:00:00.000Z",
    evidence: {
      kind: "issuer_directory_anchor",
      issuer: "AXIS    BANK",
      canonical_url: canonicalUrl,
      run_date: "2026-08-19",
    },
  }));
  const store = issuerSchedulerStore({ jobs });
  const claim = await claimIssuerDiscoveryRun(
    store.db,
    { issuer: "Axis Bank", canonical_url: canonicalUrl },
    new Date("2026-08-20T00:00:00.000Z"),
  );
  assert(claim.status === "quarantined", "large corrupt scan was not fenced");
  assert(
    (claim as any).reviewSummary?.remaining === 985,
    "scan stopped at the former 1,000-row window",
  );
  assert(
    new Set(store.pageReadIds).size >= 1005,
    "stable producer scan did not read every retained row",
  );
});

Deno.test("issuer producer keyset pages more than one thousand retained rows exactly once during an earlier insert", async () => {
  const canonicalUrl =
    "https://www.axis.bank.in/cards/credit-card/neo-credit-card";
  const originalIds = Array.from(
    { length: 1005 },
    (_, index) =>
      `00000000-0000-4000-8000-${String(index + 1000).padStart(12, "0")}`,
  );
  const jobs = originalIds.map((id, index) => ({
    id,
    user_id: null,
    discovery_source: "issuer_crawl",
    issuer: "Axis Bank",
    dedupe_key: `corrupt-producer-${index}`,
    status: "resolved",
    failure_category: null,
    attempt_count: 1,
    next_retry_at: null,
    created_at: "2026-01-01T00:00:00.000Z",
    updated_at: "2026-08-19T00:00:00.000Z",
    evidence: {
      kind: "issuer_directory_anchor",
      issuer: "Axis Bank",
      canonical_url: canonicalUrl,
      run_date: "2026-08-19",
    },
  }));
  const store = issuerSchedulerStore({
    jobs,
    afterJobRange: ({ rangeIndex, jobs }) => {
      if (rangeIndex !== 0) return;
      jobs.push({
        ...structuredClone(jobs[0]),
        id: "00000000-0000-4000-8000-000000000001",
        dedupe_key: "concurrent-earlier-key",
      });
    },
  });

  await claimIssuerDiscoveryRun(
    store.db,
    { issuer: "Axis Bank", canonical_url: canonicalUrl },
    new Date("2026-08-20T00:00:00.000Z"),
  );

  const originalIdSet = new Set(originalIds);
  const originalReads = store.pageReadIds.filter((id) => originalIdSet.has(id));
  assert(
    originalReads.length === originalIds.length,
    `producer scan returned ${originalReads.length} original rows`,
  );
  assert(
    new Set(originalReads).size === originalIds.length &&
      originalIds.every((id) => originalReads.includes(id)),
    "issuer producer history was skipped or duplicated across pages",
  );
});

Deno.test("issuer anchor scan fails closed when its deadline prevents exhaustive pagination", async () => {
  const canonicalUrl =
    "https://www.axis.bank.in/cards/credit-card/neo-credit-card";
  const jobs = Array.from({ length: 101 }, (_, index) => ({
    id: `deadline-scan-${String(index).padStart(3, "0")}`,
    user_id: null,
    discovery_source: "issuer_crawl",
    issuer: "Axis Bank",
    dedupe_key: `deadline-scan-key-${index}`,
    status: "resolved",
    failure_category: null,
    attempt_count: 1,
    next_retry_at: null,
    created_at: `2026-01-01T00:00:${String(index % 60).padStart(2, "0")}.000Z`,
    updated_at: "2026-08-19T00:00:00.000Z",
    evidence: {
      kind: "untrusted-kind",
      issuer: "Axis Bank",
      canonical_url: canonicalUrl,
      run_date: "2026-08-19",
    },
  }));
  const store = issuerSchedulerStore({ jobs });
  let deadlineChecks = 0;
  let failedClosed = false;
  try {
    await claimIssuerDiscoveryRun(
      store.db,
      { issuer: "Axis Bank", canonical_url: canonicalUrl },
      new Date("2026-08-20T00:00:00.000Z"),
      {
        deadlineAt: 50,
        nowMs: () => deadlineChecks++ === 0 ? 0 : 100,
      },
    );
  } catch (error) {
    failedClosed = String(error).includes(
      "issuer_discovery_stable_scan_exhausted",
    );
  }
  assert(failedClosed, "partial anchor scan continued into a claim");
  assert(store.rpcCalls.length === 0, "partial scan mutated quarantine state");
  assert(
    !store.jobs.some((row) => row.status === "discovering"),
    "partial scan inserted a replacement anchor",
  );
});

Deno.test("a final short issuer-anchor page that crosses the deadline performs no claim or mutation", async () => {
  const canonicalUrl =
    "https://www.axis.bank.in/cards/credit-card/neo-credit-card";
  let nowMs = 0;
  const store = issuerSchedulerStore({
    jobs: [],
    afterJobRange: ({ rangeIndex }) => {
      if (rangeIndex === 0) nowMs = 100;
    },
  });
  let failedClosed = false;
  try {
    await claimIssuerDiscoveryRun(
      store.db,
      { issuer: "Axis Bank", canonical_url: canonicalUrl },
      new Date("2026-08-20T00:00:00.000Z"),
      { deadlineAt: 50, nowMs: () => nowMs },
    );
  } catch (error) {
    failedClosed = String(error).includes(
      "issuer_discovery_stable_scan_exhausted",
    );
  }
  assert(failedClosed, "deadline-crossing short page completed the scan");
  assert(store.jobs.length === 0, "deadline-crossing scan inserted a claim");
  assert(
    store.rpcCalls.length === 0,
    "deadline-crossing scan staged review work",
  );
});

Deno.test("quarantine staging checks the invocation deadline before every transition", async () => {
  const canonicalUrl =
    "https://www.axis.bank.in/cards/credit-card/neo-credit-card";
  const jobs = Array.from({ length: 25 }, (_, index) => ({
    id: `deadline-corrupt-${index}`,
    user_id: null,
    discovery_source: "issuer_crawl",
    issuer: "Axis Bank",
    dedupe_key: `deadline-corrupt-key-${index}`,
    status: "resolved",
    failure_category: null,
    attempt_count: 1,
    next_retry_at: null,
    created_at: `2026-01-01T00:00:${String(index).padStart(2, "0")}.000Z`,
    updated_at: "2026-08-19T00:00:00.000Z",
    evidence: {
      kind: "issuer_directory_anchor",
      issuer: "Axis Bank",
      canonical_url: canonicalUrl,
      run_date: "2026-08-19",
    },
  }));
  let nowMs = 0;
  const store = issuerSchedulerStore({
    jobs,
    failUpdate: (payload) => {
      if (payload.failure_category === "issuer_discovery_quarantined") {
        nowMs = 100;
      }
      return null;
    },
  });
  let deadlineStopped = false;
  try {
    await claimIssuerDiscoveryRun(
      store.db,
      { issuer: "Axis Bank", canonical_url: canonicalUrl },
      new Date("2026-08-20T00:00:00.000Z"),
      { deadlineAt: 50, nowMs: () => nowMs },
    );
  } catch (error) {
    deadlineStopped = String(error).includes(
      "issuer_discovery_deadline_exceeded",
    );
  }
  assert(deadlineStopped, "post-transition deadline was not rechecked");
  assert(store.rpcCalls.length === 0, "deadline allowed review staging");
  assert(
    store.jobs.filter((row) =>
      row.failure_category === "issuer_discovery_quarantined"
    ).length === 1,
    "deadline allowed another producer transition",
  );
});

Deno.test("issuer handler summary reports quarantine work as non-empty", () => {
  const summarize = (batchModule as any).issuerDiscoveryResponseSummary;
  assert(
    typeof summarize === "function",
    "issuer handler has no review-work summary boundary",
  );
  const withReview = summarize({
    status: "legacy_conflict",
    seed: null,
    reviewSummary: { staged: 2, quarantined: 3, conflicts: 3 },
  });
  assert(
    withReview.noWork === false,
    "staged review work was reported no-work",
  );
  assert(
    withReview.staged === 2 && withReview.quarantined === 3 &&
      withReview.conflicts === 3 && withReview.remaining === 0,
    "handler summary hid review/quarantine/conflict counts",
  );
  const empty = summarize({ status: "empty", seed: null });
  assert(
    empty.noWork === true && empty.staged === 0 &&
      empty.quarantined === 0 && empty.conflicts === 0,
    "true empty discovery did not retain zero counts",
  );
});

Deno.test("cross-class crawler URL conflicts become actionable bounded review work", async () => {
  const calls: Array<{ name: string; args: Record<string, unknown> }> = [];
  const db = {
    async rpc(name: string, args: Record<string, unknown>) {
      calls.push({ name, args });
      return {
        data: [{
          job_id: "job-1",
          review_item_id: "review-1",
          resulting_status: "review_required",
          created: true,
        }],
        error: null,
      };
    },
    from() {
      throw new Error("conflict review bypassed the central staging RPC");
    },
  };
  const result = await persistNonProductIssuerOutcome(
    db,
    "Axis Bank",
    {
      candidateKey: "a".repeat(64),
      disposition: "quarantined",
      attempted: true,
      classification: {
        kind: "card_product",
        canonicalUrl:
          "https://www.axis.bank.in/cards/credit-card/privilege-credit-card",
        proposedName: "Privilege",
        aliases: ["Axis Privilege Credit Card"],
        confidence: 0.95,
        warnings: ["conflicting_url_identity"],
        sanitizedEvidence: ["Axis Privilege Credit Card"],
      },
    },
    "conflicting_url_identity",
  );
  assert(result === "quarantined", "conflict review outcome was lost");
  assert(
    calls.length === 1 &&
      calls[0].name === "stage_card_catalog_identity_review" &&
      (calls[0].args._validation_warnings as string[]).includes(
        "conflicting_url_identity",
      ),
    "URL conflict did not reach central actionable review",
  );
});

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
  runMode: "scheduled" | "pilot" = "scheduled",
  unsafeEvidence: boolean | string = false,
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
  const text = typeof unsafeEvidence === "string"
    ? unsafeEvidence
    : unsafeEvidence
    ? "<html><title>Issuer Test Visa Credit Card</title><h1>Issuer Test Visa Credit Card</h1><p>Get 10% cashback on dining spends with access_token=abcdefgh-secret.</p></html>"
    : "<html><title>Issuer Test Visa Credit Card</title><h1>Issuer Test Visa Credit Card</h1><p>Get 10% cashback on dining spends.</p></html>";
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
    card_benefit_mapping: [{
      mapping_id: "22222222-2222-4222-8222-222222222222",
      card_id: cardId,
      benefit_id: "11111111-1111-4111-8111-111111111111",
      display_priority: 1,
      is_primary: true,
      category_codes: ["CASHBACK"],
      retired_at: null,
      created_at: "2026-08-19T00:00:00.000Z",
    }],
    benefits: [{
      benefit_id: "11111111-1111-4111-8111-111111111111",
      dedupe_key: currentProposal.dedupeKey,
      title: currentProposal.title,
      description: currentProposal.description,
      benefit_category: currentProposal.category,
      benefit_type: currentProposal.valueType,
      value_config: currentProposal.valueConfig,
      partners: currentProposal.partners,
      exclusions: currentProposal.exclusions,
      regions: [],
      source_url: currentProposal.sourceUrl,
      valid_from: null,
      valid_until: null,
      is_active: true,
      created_at: "2026-08-19T00:00:00.000Z",
      updated_at: "2026-08-19T00:00:00.000Z",
    }],
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
        limit(limit: number) {
          const rows = (tableRows[table] ?? []).filter((row) =>
            [...filters].every(([column, value]) => row[column] === value)
          );
          return Promise.resolve({ data: rows.slice(0, limit), error: null });
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
      if (name === "card_has_unresolved_catalog_identity") {
        return { data: false, error: null };
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
  let fetchCount = 0;
  const result = await processJob(
    db,
    {
      id: "job-1",
      card_id: cardId,
      issuer: card.bank,
      canonical_url: card.card_url,
      parser_version: "benefits-v6",
      attempt_count: 1,
      run_mode: runMode,
      lease_token: "lease-1",
      staging_id: stagingStatusAtFinalize === null ? null : "stage-old",
      result_summary: {
        ...(runMode === "pilot" ? { pilot_profile: "straightforward" } : {}),
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
      fetchObservation: async () => {
        fetchCount += 1;
        return {
          disposition: "success",
          result: {
            status: 200,
            submittedUrl: card.card_url,
            finalUrl: card.card_url,
            canonicalUrl: card.card_url,
            contentType: "text/html",
            text,
            contentHash: "b".repeat(64),
            sourceIdentityHash: "c".repeat(64),
            finalResourceIdentityHash: "d".repeat(64),
            finalResourceUrl: card.card_url,
            retrievedAt: observedAt,
            notModified: false,
          },
          attempts: [{ status: 200, attemptedAt: observedAt }],
        };
      },
    },
  );
  return {
    result,
    finalization: finalizations[0],
    stageCalls,
    lifecycleCalls,
    stagingReads,
    effectiveFinalStatus,
    fetchCount,
  };
}

Deno.test("pilot processing fetches once and persists computed replay and live-state evidence", async () => {
  const fixture = await stableCanonicalProcessFixture(
    null,
    false,
    false,
    "pilot",
  );
  assert(fixture.fetchCount === 1, "pilot replay performed a second fetch");
  const normalized = fixture.finalization?._normalized_fields as
    | Record<string, unknown>
    | undefined;
  assert(normalized, "pilot finalization omitted normalized evidence");
  const evidence = normalized.pilot_evidence as Record<string, unknown>;
  assert(
    evidence,
    `pilot evidence missing from finalization: ${
      JSON.stringify(fixture.finalization)
    }`,
  );
  const metrics = normalized.operational_metrics as Record<string, unknown>;
  assert(
    normalized.pilot_profile === "straightforward" &&
      evidence.run_mode === "pilot" &&
      evidence.canonical_hash === evidence.repeat_canonical_hash &&
      evidence.deterministic_replay_passed === true &&
      typeof evidence.verification_envelope === "object" &&
      typeof evidence.repeat_verification_envelope === "object" &&
      Array.isArray(evidence.expected_required_source_keys) &&
      evidence.proposal_disposition === "no_change" &&
      evidence.staging_id === null,
    "pilot finalization did not persist deterministic replay proof",
  );
  assert(
    evidence.side_effect_proof_passed === true &&
      evidence.unsafe_mutation_count === 0 &&
      evidence.raw_body_stored === false,
    `pilot finalization did not persist the computed side-effect proof: ${
      JSON.stringify(evidence)
    }`,
  );
  assert(
    metrics.fetch_attempts === 1 && metrics.fetch_success === 1 &&
      metrics.deterministic_replay_passed === true &&
      metrics.side_effect_proof_passed === true,
    "pilot operational metrics were not derived from the executed run",
  );
});

Deno.test("unsafe extracted evidence is rejected before staging and never reaches final payloads", async () => {
  const fixture = await stableCanonicalProcessFixture(
    null,
    true,
    false,
    "pilot",
    true,
  );
  assert(
    fixture.stageCalls.length === 0,
    "unsafe evidence reached the staging RPC",
  );
  assert(
    !JSON.stringify(fixture.finalization).includes("abcdefgh-secret"),
    "unsafe evidence reached the finalizer payload",
  );
});

Deno.test("direct official-source customer and payment probes never reach staging or finalization", async () => {
  for (
    const unsafe of [
      "Email john.doe@example.com for assistance.",
      "Pay with 4111-1111-1111-1111.",
      "Call +91 98765 43210.",
      "Account ID: 1234567890123456.",
      "Customer Name: Rahul Sharma.",
      "Relationship manager Amit Kumar Sharma will call.",
      "Name: John gets 10% cashback.",
      "john gets 10% cashback.",
      "Phone 123.456.7890.",
      "PAN ABCDE1234F receives rewards.",
      "Reference 12345678901234567890 gets rewards.",
      "&#x41;&#x4c;&#x49;&#x43;&#x45; gets 10% cashback.",
      "AL\u200BICE receives rewards.",
      "Ｒａｈｕｌ Ｓｈａｒｍａ gets 10% cashback.",
      "Rаhul Šarma receives rewards.",
      "Email ａｌｉｃｅ＠example.com.",
      "Phone ＋９１ ９８７６５ ４３２１０.",
      "Account ID १२३४५६७८९०१२३४५६.",
      "Cashback for alice smith is 10%.",
      "Reward points to rAhUl shArMa.",
      "10% cashback for ALICE SMITH.",
    ]
  ) {
    const fixture = await stableCanonicalProcessFixture(
      null,
      false,
      false,
      "pilot",
      `<html><title>Issuer Test Visa Credit Card</title><h1>Issuer Test Visa Credit Card</h1><p>Get 10% cashback on dining spends.</p><p>${unsafe}</p></html>`,
    );
    const persisted = JSON.stringify([
      fixture.stageCalls,
      fixture.finalization,
    ]);
    assert(
      fixture.stageCalls.length === 0 &&
        !persisted.includes(unsafe) &&
        !persisted.includes("john.doe@example.com") &&
        !persisted.includes("4111-1111-1111-1111") &&
        !persisted.includes("98765 43210") &&
        !persisted.includes("1234567890123456") &&
        !persisted.includes("Rahul Sharma") &&
        !persisted.includes("Amit Kumar Sharma") &&
        !persisted.includes("Name: John") &&
        !persisted.includes("john gets") &&
        !persisted.includes("123.456.7890") &&
        !persisted.includes("ABCDE1234F") &&
        !persisted.includes("12345678901234567890"),
      `direct official-source private data crossed staging or finalization: ${unsafe}`,
    );
  }
});

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
  const jobs = await Promise.all(
    Array.from({ length: 5 }, (_, index) =>
      withComputedPilotEvidence({
        id: `pilot-${index}`,
        card_id: `card-${index}`,
        parser_version: "benefits-v6",
        run_mode: "scheduled",
        status: "completed",
        job_key: `card-${index}:hash-${index}:benefits-v6`,
        result_summary: { pilot_qualified: true },
      })),
  );
  const calls: Array<{ name: string; args: Record<string, unknown> }> = [];
  let lockedMutationDetected = false;
  const db = {
    from() {
      return {
        select() {
          return this;
        },
        eq() {
          return this;
        },
        limit() {
          return this;
        },
        or() {
          return Promise.resolve({ data: jobs, error: null });
        },
      };
    },
    async rpc(name: string, args: Record<string, unknown>) {
      calls.push({ name, args });
      if (lockedMutationDetected) {
        return { data: null, error: new Error("pilot_not_qualified") };
      }
      return { data: jobs.map((job) => ({ ...job })), error: null };
    },
  };

  const first = await promoteQualifiedPilotJobs(db, "benefits-v6", {
    captureLiveStateSnapshot: pilotSnapshotCapture(jobs),
    readCatalogIdentityConflictCount: async () => 0,
  });
  const repeated = await promoteQualifiedPilotJobs(db, "benefits-v6", {
    captureLiveStateSnapshot: pilotSnapshotCapture(jobs),
    readCatalogIdentityConflictCount: async () => 0,
  });

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
  lockedMutationDetected = true;
  let raceError: unknown;
  try {
    await promoteQualifiedPilotJobs(db, "benefits-v6", {
      captureLiveStateSnapshot: pilotSnapshotCapture(jobs),
      readCatalogIdentityConflictCount: async () => 0,
    });
  } catch (caught) {
    raceError = caught;
  }
  assert(
    raceError instanceof Error && raceError.message === "pilot_not_qualified",
    "locked SQL rejection of a read-to-promotion mutation race was ignored",
  );
});

Deno.test("promoted pilot proof survives later no-change and material scheduled replays", async () => {
  const originalRows = await Promise.all(
    Array.from({ length: 5 }, (_, index) =>
      withComputedPilotEvidence({
        id: `promoted-${index}`,
        card_id: `card-promoted-${index}`,
        parser_version: "benefits-v6",
        run_mode: "scheduled",
        status: "completed",
        result_summary: index === 1
          ? {
            pilot_qualified: true,
            review_status: "approved",
            approved_count: 1,
            retained_count: 0,
            retired_count: 0,
            rejected_count: 0,
            successful_no_change: false,
            proposals: 1,
            proposal_disposition: "material",
          }
          : { pilot_qualified: true },
      })),
  ) as Array<Record<string, any>>;
  const originalStagingRows = pilotStagingRows(originalRows);
  const replayedRows = structuredClone(originalRows);
  replayedRows[0].status = "staged";
  replayedRows[0].staging_id = "44444444-4444-4444-8444-444444444444";
  replayedRows[0].result_summary = {
    pilot_qualified: true,
    unsafe_mutation_count: 0,
    raw_body_stored: false,
    proposals: 1,
    proposal_disposition: "material",
    successful_no_change: false,
  };
  replayedRows[1].status = "completed";
  replayedRows[1].staging_id = null;
  replayedRows[1].result_summary = {
    pilot_qualified: true,
    unsafe_mutation_count: 0,
    raw_body_stored: false,
    proposals: 0,
    proposal_disposition: "no_change",
    successful_no_change: true,
  };
  const jobQuery = {
    select() {
      return this;
    },
    eq() {
      return this;
    },
    limit() {
      return this;
    },
    or() {
      return Promise.resolve({ data: replayedRows, error: null });
    },
  };
  const stagingQuery = {
    selected: [] as string[],
    select() {
      return this;
    },
    in(_column: string, values: string[]) {
      this.selected = values;
      return this;
    },
    limit() {
      return Promise.resolve({
        data: originalStagingRows.filter((row) =>
          this.selected.includes(row.id)
        ),
        error: null,
      });
    },
  };
  const gate = await readPilotStatus(
    {
      from: (table: string) =>
        table === "card_benefits_staging" ? stagingQuery : jobQuery,
    },
    "benefits-v6",
    {
      captureLiveStateSnapshot: pilotSnapshotCapture(replayedRows),
      readCatalogIdentityConflictCount: async () => 0,
    },
  );
  assert(
    gate.status === "passed",
    `scheduled replay invalidated immutable pilot proof: ${gate.blockers}`,
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
  let cohortLimit = 0;
  let orFilter = "";
  const rows = await Promise.all(
    [
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
          status: parserVersion === "benefits-v6" ? "completed" : "staged",
          failure_category: null,
          result_summary: {
            unsafe_mutation_count: 0,
            idempotency_passed: true,
            evidence_passed: true,
            raw_body_stored: false,
            pilot_qualified: parserVersion === "benefits-v6",
          },
        }))
      ).map(withComputedPilotEvidence),
  );
  const query = {
    select() {
      return this;
    },
    eq(column: string, value: unknown) {
      filters.set(column, value);
      return this;
    },
    limit(value: number) {
      cohortLimit = value;
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

  const gate = await readPilotStatus(db, "benefits-v6", {
    captureLiveStateSnapshot: pilotSnapshotCapture(rows),
    readCatalogIdentityConflictCount: async () => 0,
  });

  assert(
    filters.get("parser_version") === "benefits-v6",
    "pilot gate mixed parser generations",
  );
  assert(cohortLimit === 6, "pilot gate read an unbounded cohort");
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
  const rows = await Promise.all(
    Array.from({ length: 5 }, (_, index) =>
      withComputedPilotEvidence({
        id: `pilot-${index}`,
        run_mode: "pilot",
        parser_version: "benefits-v6",
        status: "completed",
        failure_category: null,
        result_summary: {
          unsafe_mutation_count: 0,
          idempotency_passed: true,
          evidence_passed: true,
          raw_body_stored: false,
          successful_no_change: index !== 0,
          proposals: index === 0 ? 1 : 0,
          proposal_disposition: index === 0 ? "material" : "no_change",
          review_status: index === 0 ? "rejected" : undefined,
          approved_count: index === 0 ? 0 : undefined,
          retained_count: index === 0 ? 0 : undefined,
          retired_count: index === 0 ? 0 : undefined,
          rejected_count: index === 0 ? 2 : undefined,
        },
      })),
  );
  const query = {
    select() {
      return this;
    },
    eq() {
      return this;
    },
    limit() {
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
  const stagingRows = pilotStagingRows(rows);
  const stagingQuery = {
    selected: [] as string[],
    select() {
      return this;
    },
    in(_column: string, values: string[]) {
      this.selected = values;
      return this;
    },
    limit() {
      return Promise.resolve({
        data: stagingRows.filter((row) => this.selected.includes(row.id)),
        error: null,
      });
    },
  };
  const db = {
    from: (table: string) =>
      table === "card_benefits_staging" ? stagingQuery : query,
  };
  const gate = await readPilotStatus(db, "benefits-v6", {
    captureLiveStateSnapshot: pilotSnapshotCapture(rows),
    readCatalogIdentityConflictCount: async () => 0,
  });
  assert(
    gate.blockers.includes("pilot_review_rejected"),
    "Task 4 rejection evidence disappeared at the pilot projection",
  );
  rows[0].result_summary.review_status = "unexpected";
  const malformed = await readPilotStatus(db, "benefits-v6", {
    captureLiveStateSnapshot: pilotSnapshotCapture(rows),
    readCatalogIdentityConflictCount: async () => 0,
  });
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
    const rows = await Promise.all(
      Array.from({ length: 5 }, (_, index) =>
        withComputedPilotEvidence({
          id: "pilot-" + index,
          run_mode: "pilot",
          parser_version: "benefits-v6",
          status: "completed",
          failure_category: null,
          result_summary: index === 0 ? summary : {
            unsafe_mutation_count: 0,
            idempotency_passed: true,
            evidence_passed: true,
            raw_body_stored: false,
            successful_no_change: true,
          },
        })),
    );
    const query = {
      select() {
        return this;
      },
      eq() {
        return this;
      },
      limit() {
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
    const stagingRows = pilotStagingRows(rows);
    const stagingQuery = {
      selected: [] as string[],
      select() {
        return this;
      },
      in(_column: string, values: string[]) {
        this.selected = values;
        return this;
      },
      limit() {
        return Promise.resolve({
          data: stagingRows.filter((row) => this.selected.includes(row.id)),
          error: null,
        });
      },
    };
    return await readPilotStatus(
      {
        from: (table: string) =>
          table === "card_benefits_staging" ? stagingQuery : query,
      },
      "benefits-v6",
      {
        captureLiveStateSnapshot: pilotSnapshotCapture(rows),
        readCatalogIdentityConflictCount: async () => 0,
      },
    );
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
    ["publication limit", (summary) => summary.approved_count = 65],
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
    approved_count: 1,
    retained_count: 0,
    retired_count: 0,
  });
  assert(boundary.status === "passed", "bounded safe review sum was rejected");
});

Deno.test("pilot review accepts PostgreSQL UTC microseconds for reviewed decisions", async () => {
  const project = task10BatchModule.projectPilotJobEvidence;
  assert(typeof project === "function", "pilot evidence boundary is missing");
  const row = await withComputedPilotEvidence({
    id: "pilot-reviewed-offset-0",
    card_id: "22222222-2222-4222-8222-222222222222",
    run_mode: "pilot",
    parser_version: "benefits-v6",
    status: "completed",
    result_summary: {
      review_status: "approved",
      approved_count: 1,
      retained_count: 0,
      retired_count: 0,
      rejected_count: 0,
    },
  }) as Record<string, any>;
  const staging = pilotStagingRows([row])[0];
  for (
    const reviewedAt of [
      "2026-08-20 00:01:00.123456+00",
      "2026-08-20T00:01:00.123456+00:00",
      "2026-08-20T00:01:00.123456Z",
      "2026-08-20T05:31:00.123456+05:30",
      "2026-08-19T20:01:00.123456-04:00",
    ]
  ) {
    staging.benefit_decisions[0].reviewed_at = reviewedAt;
    const projected = await project(row, {
      staging,
      currentLiveState: row.normalized_fields.pilot_evidence.live_state_after,
    });
    assert(
      projected.computedEvidenceValid === true,
      `valid PostgreSQL UTC review timestamp was rejected: ${reviewedAt}`,
    );
  }
});

Deno.test("pilot review validates real Task4 resolved proposal pairs and exact reject lanes", async () => {
  const project = task10BatchModule.projectPilotJobEvidence;
  assert(typeof project === "function", "pilot evidence boundary is missing");
  const row = await withComputedPilotEvidence({
    id: "pilot-sql-review-shape-0",
    card_id: "22222222-2222-4222-8222-222222222222",
    run_mode: "pilot",
    parser_version: "benefits-v6",
    status: "completed",
    result_summary: {
      review_status: "approved",
      approved_count: 1,
      retained_count: 0,
      retired_count: 0,
      rejected_count: 1,
    },
  }) as Record<string, any>;
  const staging = pilotStagingRows([row])[0];
  const proposal = staging.extracted_data.proposals[0];
  staging.extracted_data.diff.possibleRemovals = [{
    benefit: { benefitId: "55555555-5555-4555-8555-555555555555" },
  }];
  staging.benefit_decisions = [{
    action: "approve",
    proposal_index: 0,
    benefit_id: "44444444-4444-4444-8444-444444444444",
    dedupe_key: proposal.dedupeKey,
    condition_hash: proposal.conditionHash,
    reviewed_at: "2026-08-20 00:01:00.123456+00",
  }, {
    action: "reject",
    benefit_id: "55555555-5555-4555-8555-555555555555",
    reason: "retain existing terms",
    reviewed_at: "2026-08-20 00:01:00.123456+00",
  }];
  const currentLiveState =
    row.normalized_fields.pilot_evidence.live_state_after;
  const valid = await project(row, { staging, currentLiveState });
  assert(
    valid.computedEvidenceValid === true,
    "actual Task4 approve audit pair plus removal reject lane was rejected",
  );

  const editedPair = structuredClone(staging);
  editedPair.benefit_decisions[0].action = "edit";
  const validEdit = await project(row, {
    staging: editedPair,
    currentLiveState,
  });
  assert(
    validEdit.computedEvidenceValid === true,
    "actual Task4 edit audit pair was rejected",
  );

  const mismatchedPair = structuredClone(staging);
  mismatchedPair.benefit_decisions[0].condition_hash = "0".repeat(64);
  const mismatched = await project(row, {
    staging: mismatchedPair,
    currentLiveState,
  });
  assert(
    mismatched.computedEvidenceValid === false,
    "resolved benefit audit was not bound to its exact staged proposal",
  );

  const wrongLane = structuredClone(staging);
  delete wrongLane.benefit_decisions[1].benefit_id;
  wrongLane.benefit_decisions[1].proposal_index = 0;
  const rejectedWrongLane = await project(row, {
    staging: wrongLane,
    currentLiveState,
  });
  assert(
    rejectedWrongLane.computedEvidenceValid === false,
    "removal reject was accepted in the proposal lane",
  );

  const malformedExtraTarget = structuredClone(staging);
  malformedExtraTarget.benefit_decisions[1].proposal_index = "0";
  const rejectedMalformedExtra = await project(row, {
    staging: malformedExtraTarget,
    currentLiveState,
  });
  assert(
    rejectedMalformedExtra.computedEvidenceValid === false,
    "a live reject accepted a malformed extra proposal target",
  );
});

Deno.test("pilot keep-existing audit resolves the exact paired modification proposal", async () => {
  const project = task10BatchModule.projectPilotJobEvidence;
  assert(typeof project === "function", "pilot evidence boundary is missing");
  const row = await withComputedPilotEvidence({
    id: "pilot-sql-keep-shape-0",
    card_id: "22222222-2222-4222-8222-222222222222",
    run_mode: "pilot",
    parser_version: "benefits-v6",
    status: "completed",
    result_summary: {
      review_status: "approved",
      approved_count: 0,
      retained_count: 1,
      retired_count: 0,
      rejected_count: 0,
    },
  }) as Record<string, any>;
  const staging = pilotStagingRows([row])[0];
  const liveBenefitId = "55555555-5555-4555-8555-555555555555";
  staging.extracted_data.diff = {
    modifications: [{
      current: { liveBenefitId },
      proposed: structuredClone(staging.extracted_data.proposals[0]),
    }],
    possibleRemovals: [],
  };
  staging.benefit_decisions = [{
    action: "keep_existing",
    benefit_id: liveBenefitId,
    reviewed_at: "2026-08-20 00:01:00.123456+00",
  }];
  const projected = await project(row, {
    staging,
    currentLiveState: row.normalized_fields.pilot_evidence.live_state_after,
  });
  assert(
    projected.computedEvidenceValid === true,
    "keep-existing audit did not cover its exact paired modification proposal",
  );
});

Deno.test("pilot review binds extraction state to Task4 pre-mutation and reviewed post-state", async () => {
  const project = task10BatchModule.projectPilotJobEvidence;
  assert(typeof project === "function", "pilot evidence boundary is missing");
  const row = await withComputedPilotEvidence({
    id: "pilot-review-transaction-state-0",
    card_id: "22222222-2222-4222-8222-222222222222",
    run_mode: "pilot",
    parser_version: "benefits-v6",
    status: "completed",
    result_summary: {
      review_status: "approved",
      approved_count: 1,
      retained_count: 0,
      retired_count: 0,
      rejected_count: 0,
    },
  }) as Record<string, any>;
  const staging = pilotStagingRows([row])[0];
  const preMutation = row.normalized_fields.pilot_evidence.live_state_after;
  const reviewedPostState = structuredClone(preMutation);
  reviewedPostState.benefits = { count: 1, row_hash: "a".repeat(64) };
  reviewedPostState.card_benefit_mapping = {
    count: 1,
    row_hash: "b".repeat(64),
  };
  staging.extracted_data.review_pre_live_state = structuredClone(preMutation);
  staging.extracted_data.published_live_state = structuredClone(
    reviewedPostState,
  );
  const valid = await project(row, {
    staging,
    currentLiveState: reviewedPostState,
  });
  assert(
    valid.computedEvidenceValid === true,
    "expected Task4 reviewed mutation did not qualify",
  );

  const unrelatedMutation = structuredClone(staging);
  unrelatedMutation.extracted_data.review_pre_live_state.card_catalog.row_hash =
    "0".repeat(64);
  const raced = await project(row, {
    staging: unrelatedMutation,
    currentLiveState: reviewedPostState,
  });
  assert(
    raced.computedEvidenceValid === false,
    "unrelated pre-review live-state mutation qualified",
  );
});

Deno.test("pilot review requires exactly one known decision for every staged target", async () => {
  const project = task10BatchModule.projectPilotJobEvidence;
  assert(typeof project === "function", "pilot evidence boundary is missing");
  const row = await withComputedPilotEvidence({
    id: "pilot-exact-review-0",
    card_id: "22222222-2222-4222-8222-222222222222",
    run_mode: "pilot",
    parser_version: "benefits-v6",
    status: "completed",
    result_summary: {
      review_status: "approved",
      approved_count: 1,
      retained_count: 0,
      retired_count: 0,
      rejected_count: 0,
    },
  }) as Record<string, any>;
  const staging = pilotStagingRows([row])[0];
  const currentLiveState =
    row.normalized_fields.pilot_evidence.live_state_after;
  const valid = await project(row, { staging, currentLiveState });
  assert(
    valid.computedEvidenceValid,
    "complete exact review fixture did not qualify",
  );
  const pendingCatalogConflict = await project(row, {
    staging,
    currentLiveState,
    catalogIdentityConflictCount: 1,
  });
  assert(
    !pendingCatalogConflict.computedEvidenceValid &&
      Number(pendingCatalogConflict.conflictCount) > 0,
    "authoritative pending catalog identity review did not block qualification",
  );
  const racedLiveState = structuredClone(currentLiveState);
  racedLiveState.card_catalog.row_hash = "0".repeat(64);
  const liveRace = await project(row, {
    staging,
    currentLiveState: racedLiveState,
  });
  assert(
    !liveRace.computedEvidenceValid,
    "post-publication live-state mutation race qualified",
  );
  for (
    const [label, decisions] of [
      ["partial", []],
      ["duplicate", [
        staging.benefit_decisions[0],
        staging.benefit_decisions[0],
      ]],
      ["unknown", [{ ...staging.benefit_decisions[0], proposal_index: 9 }]],
    ] as const
  ) {
    const projected = await project(row, {
      staging: { ...staging, benefit_decisions: structuredClone(decisions) },
      currentLiveState,
    });
    assert(
      !projected.computedEvidenceValid,
      `${label} review target coverage qualified`,
    );
  }
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
      limit() {
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
    const gate = await readPilotStatus({ from: () => query }, "benefits-v6", {
      captureLiveStateSnapshot: pilotSnapshotCapture(rows),
      readCatalogIdentityConflictCount: async () => 0,
    });
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
      limit() {
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
    const gate = await readPilotStatus({ from: () => query }, "benefits-v6", {
      captureLiveStateSnapshot: pilotSnapshotCapture(rows),
      readCatalogIdentityConflictCount: async () => 0,
    });
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

Deno.test("directory absence evidence never suppresses Task6 recurring refresh", async () => {
  const db = scheduledSeederDb(
    [validCatalogCard],
    [],
    [],
    [{
      id: "absence-review",
      status: "pending",
      existing_candidates: [{ card_id: validCatalogCard.id }],
      proposed_fields: {
        card_id: validCatalogCard.id,
        suggested_action: "observe_directory_absence",
      },
      source_evidence: {
        source_observation: { kind: "complete_issuer_directory_absence" },
      },
    }],
  );

  const seeded = await seedScheduledQueueIfAllowed(db, "scheduled", true);

  assert(seeded === 1, "absence observation suppressed recurring refresh");
  assert(db.jobs.size === 1, "absence observation blocked the Task6 job");
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
