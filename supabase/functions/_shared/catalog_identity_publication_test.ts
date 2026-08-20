import {
  appendCatalogObservationHistory,
  boundedCatalogSourceObservation,
  boundedReviewedCatalogFields,
  canonicalPublicationResource,
  cardDiscontinuationEvidence,
  catalogLifecycleObservationAction,
  catalogLifecycleSuggestion,
  catalogPublicationBaseline,
  proposeCatalogLifecycleReview,
  publicationFieldsFromFetch,
  publishReviewedCardIdentity,
  semanticCatalogSourceObservation,
  semanticProductEnvelopeHash,
  stageCatalogIdentityReview,
} from "./catalog_identity_publication.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

Deno.test("publication URL identity preserves functional query bytes and removes only tracking and fragments", async () => {
  const first = await canonicalPublicationResource(
    "Axis Bank",
    "https://www.axis.bank.in/card?variant=gold&variant=platinum&utm_source=x&lang=en#fees",
  );
  const reordered = await canonicalPublicationResource(
    "Axis Bank",
    "https://www.axis.bank.in/card?lang=en&variant=gold&variant=platinum",
  );
  assert(
    first.canonicalUrl ===
      "https://www.axis.bank.in/card?variant=gold&variant=platinum&lang=en",
    `functional query bytes changed: ${first.canonicalUrl}`,
  );
  assert(
    first.urlHash !== reordered.urlHash,
    "query order lost resource identity",
  );

  const encoded = await canonicalPublicationResource(
    "Axis Bank",
    "https://www.axis.bank.in/card?document=terms%2Fgold&document=fees%20and%20charges",
  );
  assert(
    encoded.canonicalUrl.endsWith(
      "?document=terms%2Fgold&document=fees%20and%20charges",
    ),
    "approved duplicate/encoding bytes were normalized",
  );

  const encodedKeyAndDotPath = await canonicalPublicationResource(
    "Axis Bank",
    "https://www.axis.bank.in/cards/./credit/../neo?%76ariant=gold&utm_medium=email#top",
  );
  assert(
    encodedKeyAndDotPath.canonicalUrl ===
      "https://www.axis.bank.in/cards/neo?%76ariant=gold",
    `encoded key/dot-path parity changed: ${encodedKeyAndDotPath.canonicalUrl}`,
  );
});

Deno.test("publication URL identity rejects credentials and non-approved functional parameters", async () => {
  for (
    const url of [
      "https://user:pass@www.axis.bank.in/card?variant=gold",
      "https://www.axis.bank.in/card?product=gold",
    ]
  ) {
    let error: unknown;
    try {
      await canonicalPublicationResource("Axis Bank", url);
    } catch (caught) {
      error = caught;
    }
    assert(error instanceof Error, `${url} was accepted`);
  }
});

Deno.test("publication URL identity rejects empty query separators consistently with SQL", async () => {
  for (
    const url of [
      "https://www.axis.bank.in/card?",
      "https://www.axis.bank.in/card?variant=gold&",
      "https://www.axis.bank.in/card?&variant=gold",
      "https://www.axis.bank.in/card?variant=gold&&lang=en",
    ]
  ) {
    let error: unknown;
    try {
      await canonicalPublicationResource("Axis Bank", url);
    } catch (caught) {
      error = caught;
    }
    assert(
      error instanceof Error && error.message === "unapproved_query",
      `empty query separator was accepted: ${url}`,
    );
  }
});

Deno.test("fetch artifacts carry submitted/final identity, content hash, retrieval time, and source status", () => {
  const fields = publicationFieldsFromFetch({
    submittedUrl: "https://www.axis.bank.in/card",
    finalUrl: "https://www.axis.bank.in/card",
    submittedResourceUrl: "https://www.axis.bank.in/card?variant=gold",
    finalResourceUrl: "https://www.axis.bank.in/card?variant=gold",
    sourceIdentityHash: "a".repeat(64),
    finalResourceIdentityHash: "b".repeat(64),
    contentHash: "c".repeat(64),
    retrievedAt: "2026-08-19T12:00:00.000Z",
    status: 200,
  });
  assert(
    typeof fields.submitted_url === "string" &&
      fields.submitted_url.includes("variant=gold"),
    "submitted URL lost",
  );
  assert(
    typeof fields.final_url === "string" &&
      fields.final_url.includes("variant=gold"),
    "final URL lost",
  );
  assert(fields.submitted_url_hash === "a".repeat(64), "submitted hash lost");
  assert(fields.final_url_hash === "b".repeat(64), "final hash lost");
  assert(fields.content_hash === "c".repeat(64), "content hash lost");
  assert(
    fields.retrieved_at === "2026-08-19T12:00:00.000Z",
    "retrieval time lost",
  );
  assert(fields.source_status === 200, "source status lost");
});

Deno.test("central helper enforces source authority and calls exactly one publication RPC", async () => {
  const calls: Array<{ name: string; args: Record<string, unknown> }> = [];
  const db = {
    async rpc(name: string, args: Record<string, unknown>) {
      calls.push({ name, args });
      return {
        data: [{
          card_id: "card-1",
          job_id: "job-1",
          resulting_status: "approved",
        }],
        error: null,
      };
    },
  };

  const result = await publishReviewedCardIdentity(db, {
    discoveryJobId: "11111111-1111-4111-8111-111111111111",
    reviewItemId: "22222222-2222-4222-8222-222222222222",
    actorId: "33333333-3333-4333-8333-333333333333",
    action: "edit_approve",
    reviewedFields: { issuer: "Axis Bank", cardName: "Privilege" },
    reason: "Verified against issuer page",
    parserVersion: "benefits-v6",
  });
  assert(result.cardId === "card-1", "RPC result was not normalized");
  assert(calls.length === 1, "publication was not one transactional call");
  assert(calls[0].name === "publish_card_catalog_identity", "wrong RPC called");
  assert(calls[0].args._parser_version === "benefits-v6", "v6 parser lost");

  for (
    const invalid of [
      {
        discoveryJobId: "11111111-1111-4111-8111-111111111111",
        action: "approve",
        reviewedFields: {},
        parserVersion: "benefits-v6",
      },
      {
        discoveryJobId: "11111111-1111-4111-8111-111111111111",
        reviewItemId: "22222222-2222-4222-8222-222222222222",
        actorId: "33333333-3333-4333-8333-333333333333",
        action: "retry",
        reviewedFields: {},
        parserVersion: "benefits-v6",
      },
      {
        discoveryJobId: "11111111-1111-4111-8111-111111111111",
        reviewItemId: "22222222-2222-4222-8222-222222222222",
        actorId: "33333333-3333-4333-8333-333333333333",
        action: "resolve_verified",
        reviewedFields: {},
        parserVersion: "benefits-v6",
      },
    ]
  ) {
    let error: unknown;
    try {
      await publishReviewedCardIdentity(db, invalid as never);
    } catch (caught) {
      error = caught;
    }
    assert(
      error instanceof Error,
      "invalid source/action authority was accepted",
    );
  }
  assert(calls.length === 1, "invalid request reached the database");
});

Deno.test("review staging delegates job creation, CAS refresh, and atomic link to one RPC", async () => {
  const calls: Array<{ name: string; args: Record<string, unknown> }> = [];
  const db = {
    async rpc(name: string, args: Record<string, unknown>) {
      calls.push({ name, args });
      return {
        data: [{
          job_id: "11111111-1111-4111-8111-111111111111",
          review_item_id: "22222222-2222-4222-8222-222222222222",
          resulting_status: "review_required",
          created: true,
        }],
        error: null,
      };
    },
  };
  const result = await stageCatalogIdentityReview(db, {
    discoveryJobId: null,
    discoverySource: "issuer_crawl",
    userId: null,
    issuer: "Axis Bank",
    proposedProduct: "Privilege Infinite",
    dedupeKey: "a".repeat(64),
    semanticHash: "b".repeat(64),
    proposedFields: { issuer: "Axis Bank", cardName: "Privilege Infinite" },
    sourceEvidence: {
      content_hash: "c".repeat(64),
      retrieved_at: "2026-08-20T00:00:00.000Z",
    },
    existingCandidates: [],
    validationWarnings: ["authenticated_source_requires_admin_review"],
    confidence: 0.91,
    expectedJobStatus: null,
    expectedJobUpdatedAt: null,
  });
  assert(calls.length === 1, "review staging was split across calls");
  assert(
    calls[0].name === "stage_card_catalog_identity_review",
    "wrong transactional review boundary",
  );
  assert(
    calls[0].args._semantic_hash === "b".repeat(64) &&
      calls[0].args._expected_job_status === null &&
      calls[0].args._expected_job_updated_at === null,
    "semantic identity or CAS token was dropped",
  );
  assert(
    result.created && result.resultingStatus === "review_required",
    "RPC outcome was inferred",
  );
});

Deno.test("trusted existing-card observations use the same publication boundary without admin authority", async () => {
  const calls: Array<{ name: string; args: Record<string, unknown> }> = [];
  const db = {
    async rpc(name: string, args: Record<string, unknown>) {
      calls.push({ name, args });
      return {
        data: [{
          card_id: "11111111-1111-4111-8111-111111111111",
          job_id: "22222222-2222-4222-8222-222222222222",
          resulting_status: "resolved",
        }],
        error: null,
      };
    },
  };

  const result = await publishReviewedCardIdentity(db, {
    discoveryJobId: "22222222-2222-4222-8222-222222222222",
    action: "observe_existing",
    reviewedFields: {
      card_id: "11111111-1111-4111-8111-111111111111",
      issuer: "Axis Bank",
      cardName: "Privilege Visa Infinite",
      network: "Visa",
      submitted_url: "https://www.axis.bank.in/card?variant=infinite",
      final_url: "https://www.axis.bank.in/card?variant=infinite",
      submitted_url_hash: "a".repeat(64),
      final_url_hash: "a".repeat(64),
      content_hash: "b".repeat(64),
      retrieved_at: "2026-08-20T00:00:00.000Z",
      source_status: 200,
      source_type: "official_html",
      source_observation: {
        kind: "strong_existing_official_card",
        identity_validated: true,
        source_status: 200,
      },
    },
  });

  assert(result.resultingStatus === "resolved", "observation was not resolved");
  assert(calls.length === 1, "observation bypassed or duplicated publication");
  assert(calls[0].args._action === "observe_existing", "action was changed");
  assert(
    calls[0].args._actor_id === null,
    "trusted observation forged an admin",
  );
  assert(
    calls[0].args._review_item_id === null,
    "trusted observation forged a review",
  );
  let weakObservation: unknown;
  try {
    await publishReviewedCardIdentity(db, {
      discoveryJobId: "22222222-2222-4222-8222-222222222222",
      action: "observe_existing",
      reviewedFields: {
        card_id: "11111111-1111-4111-8111-111111111111",
        source_type: "official_html",
        source_observation: {
          kind: "strong_existing_official_card",
          identity_validated: true,
          source_status: 404,
        },
      },
    });
  } catch (error) {
    weakObservation = error;
  }
  assert(
    weakObservation instanceof Error &&
      weakObservation.message === "invalid_existing_observation_authority",
    "weak HTTP absence reached the trusted observation boundary",
  );
});

Deno.test("catalog lifecycle suggestions require strong evidence and exact reappearance", () => {
  assert(
    catalogLifecycleSuggestion({
      isDiscontinued: false,
      httpStatus: 410,
      identityValidated: false,
      explicitDiscontinuation: false,
    }) === "mark_discontinued",
    "410 did not create bounded lifecycle work",
  );
  assert(
    catalogLifecycleSuggestion({
      isDiscontinued: false,
      httpStatus: 404,
      identityValidated: false,
      explicitDiscontinuation: false,
    }) === null,
    "404 alone suggested discontinuation",
  );
  assert(
    catalogLifecycleSuggestion({
      isDiscontinued: false,
      httpStatus: 302,
      identityValidated: false,
      explicitDiscontinuation: false,
    }) === null,
    "redirect alone suggested discontinuation",
  );
  assert(
    catalogLifecycleSuggestion({
      isDiscontinued: false,
      httpStatus: 200,
      identityValidated: true,
      explicitDiscontinuation: true,
    }) === "mark_discontinued",
    "explicit issuer discontinuation was ignored",
  );
  assert(
    catalogLifecycleSuggestion({
      isDiscontinued: true,
      httpStatus: 200,
      identityValidated: true,
      explicitDiscontinuation: false,
    }) === "reactivate",
    "exact discontinued-card reappearance was ignored",
  );
  assert(
    catalogLifecycleSuggestion({
      isDiscontinued: true,
      httpStatus: 200,
      identityValidated: true,
      explicitDiscontinuation: true,
    }) === null,
    "current explicit discontinuation was overridden by weak reactivation precedence",
  );
});

Deno.test("every authoritative lifecycle observation advances an explicit current-state action", () => {
  const cases = [
    {
      input: {
        isDiscontinued: false,
        httpStatus: 200,
        identityValidated: true,
        explicitDiscontinuation: false,
      },
      expected: "observe_current",
    },
    {
      input: {
        isDiscontinued: true,
        httpStatus: 200,
        identityValidated: true,
        explicitDiscontinuation: true,
      },
      expected: "observe_current",
    },
    {
      input: {
        isDiscontinued: true,
        httpStatus: 410,
        identityValidated: false,
        explicitDiscontinuation: false,
      },
      expected: "observe_current",
    },
  ] as const;
  for (const { input, expected } of cases) {
    assert(
      catalogLifecycleObservationAction(input) === expected,
      `${JSON.stringify(input)} did not advance current lifecycle evidence`,
    );
  }
  assert(
    catalogLifecycleObservationAction({
      isDiscontinued: false,
      httpStatus: 404,
      identityValidated: false,
      explicitDiscontinuation: false,
    }) === null,
    "weak absence advanced authoritative lifecycle state",
  );
});

Deno.test("catalog source observations are recursively private and structurally bounded", () => {
  const observation = boundedCatalogSourceObservation({
    kind: "catalog_conflict",
    nested: {
      source: "https://user:pass@www.axis.bank.in/card?token=secret#private",
      oversized: "x".repeat(20_000),
      entries: Array.from({ length: 100 }, (_, index) => ({ index })),
    },
  });
  const serialized = JSON.stringify(observation);
  assert(
    !/user:pass|token=secret|#private/.test(serialized),
    "URL secrets survived",
  );
  assert(
    serialized.length <= 16_384,
    "source observation exceeded its SQL envelope",
  );
  assert(
    Array.isArray((observation.nested as Record<string, unknown>).entries) &&
      ((observation.nested as Record<string, unknown>).entries as unknown[])
          .length <= 32,
    "recursive array bound was not enforced",
  );
});

Deno.test("semantic lifecycle identity excludes transport time while bounded history deduplicates and caps newest", () => {
  const first = semanticCatalogSourceObservation({
    kind: "exact_card_reappearance",
    source_status: 200,
    identity_validated: true,
    retrieved_at: "2026-08-20T00:00:00.000Z",
    transport: { attempted_at: "2026-08-20T00:00:01.000Z", duration_ms: 20 },
  });
  const replay = semanticCatalogSourceObservation({
    kind: "exact_card_reappearance",
    source_status: 200,
    identity_validated: true,
    retrieved_at: "2026-08-20T01:00:00.000Z",
    transport: { attempted_at: "2026-08-20T01:00:01.000Z", duration_ms: 90 },
  });
  assert(
    JSON.stringify(first) === JSON.stringify(replay),
    "transport timestamps changed semantic lifecycle identity",
  );

  let history: unknown[] = [];
  for (let index = 0; index < 30; index += 1) {
    history = appendCatalogObservationHistory(history, {
      semantic_hash: index === 29 ? "same" : `hash-${index}`,
      observed_at: `2026-08-${
        String(index + 1).padStart(2, "0")
      }T00:00:00.000Z`,
      retrieved_at: `2026-08-${
        String(index + 1).padStart(2, "0")
      }T00:00:00.000Z`,
    });
  }
  history = appendCatalogObservationHistory(history, {
    semantic_hash: "same",
    observed_at: "2026-08-30T00:00:00.000Z",
    retrieved_at: "2026-08-30T00:00:00.000Z",
  });
  assert(history.length === 24, `history retained ${history.length} entries`);
  assert(
    history.filter((entry) =>
      (entry as Record<string, unknown>).semantic_hash === "same"
    ).length === 1,
    "exact semantic replay duplicated observation history",
  );
  assert(
    (history[0] as Record<string, unknown>).observed_at ===
      "2026-08-30T00:00:00.000Z",
    "history did not retain newest evidence first",
  );
});

Deno.test("semantic product envelope ignores transport churn but versions identity, field, and lifecycle changes", async () => {
  const base = {
    issuer: "Axis Bank",
    cardName: "Privilege Infinite",
    network: "Visa",
    fields: { annual_fee: 1500 },
    lifecycle: { explicit_discontinuation: false },
    retrieved_at: "2026-08-20T00:00:00.000Z",
    transport: { nonce: "first", footer: "generated at midnight" },
  };
  const first = await semanticProductEnvelopeHash(base);
  const churn = await semanticProductEnvelopeHash({
    ...base,
    retrieved_at: "2026-08-20T01:00:00.000Z",
    transport: { nonce: "second", footer: "generated at one" },
  });
  const fieldChange = await semanticProductEnvelopeHash({
    ...base,
    fields: { annual_fee: 2000 },
  });
  const lifecycleChange = await semanticProductEnvelopeHash({
    ...base,
    lifecycle: { explicit_discontinuation: true },
  });
  assert(first === churn, "nonce/footer churn versioned product review work");
  assert(
    first !== fieldChange,
    "catalog field change reused stale review work",
  );
  assert(
    first !== lifecycleChange,
    "lifecycle change reused stale review work",
  );
});

Deno.test("explicit discontinuation evidence is target scoped and retains its matched excerpt", () => {
  const unrelated = cardDiscontinuationEvidence(
    "<h1>Axis Neo Credit Card</h1><aside>Axis MyZone Credit Card has been discontinued</aside>",
    "Axis Bank",
    "Neo",
  );
  assert(!unrelated.explicit, "another product discontinued the target card");
  const targeted = cardDiscontinuationEvidence(
    "<h1>Axis Neo Credit Card</h1><p>This credit card has been discontinued and is no longer issued.</p>",
    "Axis Bank",
    "Neo",
  );
  assert(targeted.explicit, "targeted discontinuation was missed");
  assert(
    typeof targeted.matchedExcerpt === "string" &&
      /discontinued/i.test(targeted.matchedExcerpt) &&
      targeted.matchedExcerpt.length <= 512,
    "decisive excerpt was not retained safely",
  );
});

Deno.test("discontinuation scope stops at sibling products and accepts only target-specific structured status", () => {
  const adjacent = cardDiscontinuationEvidence(
    `<h2>Axis Neo Credit Card</h2>
     <h3>Axis MyZone Credit Card</h3>
     <p>This card has been discontinued.</p>`,
    "Axis Bank",
    "Neo",
  );
  assert(!adjacent.explicit, "a sibling h3 notice leaked into the target h2");

  const table = cardDiscontinuationEvidence(
    `<table><tr><th>Axis Neo Credit Card</th><td>Status</td><td>Discontinued</td></tr>
     <tr><th>Axis MyZone Credit Card</th><td>Status</td><td>Available</td></tr></table>`,
    "Axis Bank",
    "Neo",
  );
  assert(table.explicit, "target-specific table status was not recognized");
  assert(
    table.matchedExcerpt !== null &&
      /neo.*discontinued/i.test(table.matchedExcerpt),
    "structured evidence did not retain the target and decisive status",
  );

  const card = cardDiscontinuationEvidence(
    `<div class="product-card"><h3>Axis Neo Credit Card</h3>
       <div class="status">No longer available</div></div>
     <div class="product-card"><h3>Axis MyZone Credit Card</h3>
       <div class="status">Available</div></div>`,
    "Axis Bank",
    "Neo",
  );
  assert(card.explicit, "target-specific card status was not recognized");

  const generic = cardDiscontinuationEvidence(
    `<h2>Axis Neo Credit Card</h2><p>Axis Bank has discontinued selected cards.</p>`,
    "Axis Bank",
    "Neo",
  );
  assert(!generic.explicit, "issuer-generic prose discontinued one product");

  const successor = cardDiscontinuationEvidence(
    `<h2>Axis Neo Credit Card</h2>
     <p>Meet MyZone, the successor to Rewards Credit Card. This card has been discontinued.</p>`,
    "Axis Bank",
    "Neo",
  );
  assert(
    !successor.explicit,
    "successor prose attributed another card's notice to Neo",
  );
});

Deno.test("discontinuation scope derives product headings without treating ordinary sections as siblings", () => {
  const siblingWithoutCard = cardDiscontinuationEvidence(
    `<h2>Axis Neo Credit Card</h2>
     <h3>My Zone</h3>
     <p>This card has been discontinued.</p>`,
    "Axis Bank",
    "Neo",
  );
  assert(
    !siblingWithoutCard.explicit,
    "a sibling product heading without the word card leaked into Neo",
  );

  const sectionHeadings = cardDiscontinuationEvidence(
    `<h2>Axis Neo Credit Card</h2>
     <h3>Benefits</h3><p>Welcome rewards.</p>
     <h3>Availability</h3>
     <h4>Status</h4><p>This credit card is no longer issued.</p>`,
    "Axis Bank",
    "Neo",
  );
  assert(
    sectionHeadings.explicit,
    "normal benefit/availability/status sections ended the target scope",
  );

  const excludedSiblingFallback = cardDiscontinuationEvidence(
    `<h2>Axis Neo Credit Card</h2>
     <h2>My Zone Credit Card</h2>
     <p>Axis Neo Credit Card has been discontinued.</p>`,
    "Axis Bank",
    "Neo",
  );
  assert(
    !excludedSiblingFallback.explicit,
    "global fallback crossed an excluded sibling product section",
  );

  const relatedInTargetSection = cardDiscontinuationEvidence(
    `<h2>Axis Neo Credit Card</h2>
     <p>Related product: My Zone Credit Card. This card has been discontinued.</p>`,
    "Axis Bank",
    "Neo",
  );
  assert(
    !relatedInTargetSection.explicit,
    "related-product anaphora became Neo lifecycle evidence",
  );
});

Deno.test("no-heading discontinuation requires one exact target-only sentence", () => {
  const exact = cardDiscontinuationEvidence(
    "<p>Axis Neo Credit Card has been discontinued and is no longer issued.</p>",
    "Axis Bank",
    "Neo",
  );
  assert(exact.explicit, "exact no-heading target sentence was missed");

  const competing = cardDiscontinuationEvidence(
    `<p>Axis Neo Credit Card has been discontinued while My Zone Credit Card remains available.</p>`,
    "Axis Bank",
    "Neo",
  );
  assert(
    !competing.explicit,
    "a no-heading sentence with competing product context was accepted",
  );

  const related = cardDiscontinuationEvidence(
    `<p>For the related My Zone Credit Card, Neo has been discontinued as a campaign name.</p>`,
    "Axis Bank",
    "Neo",
  );
  assert(!related.explicit, "related-card prose became target lifecycle proof");
});

Deno.test("reviewed catalog fields enforce a strict private bounded whole-envelope contract", () => {
  const valid = boundedReviewedCatalogFields({
    issuer: "Axis Bank",
    cardName: "Privilege Infinite",
    network: "Visa",
    aliases: ["Axis Privilege Visa Infinite Credit Card"],
    submitted_url:
      "https://www.axis.bank.in/card?variant=infinite&utm_source=ignored",
    final_url: "https://www.axis.bank.in/card?variant=infinite",
    submitted_url_hash: "a".repeat(64),
    final_url_hash: "b".repeat(64),
    content_hash: "c".repeat(64),
    retrieved_at: "2026-08-20T00:00:00.000Z",
    source_status: 200,
    source_type: "official_html",
    source_observation: {
      kind: "reviewed_identity",
      note: "issuer product page verified",
    },
  });
  const serialized = JSON.stringify(valid);
  assert(!/user:pass|token=secret|#private/.test(serialized), serialized);
  assert(
    valid.submitted_url ===
      "https://www.axis.bank.in/card?variant=infinite&utm_source=ignored",
    "validated resource identity was redacted instead of preserved",
  );

  for (
    const invalid of [
      { issuer: "Axis Bank", raw_body: "issuer HTML" },
      { issuer: "Axis Bank", aliases: ["x".repeat(513)] },
      { issuer: "Axis Bank", aliases: ["é".repeat(300)] },
      {
        issuer: "Axis Bank",
        catalog_baseline: { ["k".repeat(65)]: true },
      },
      {
        issuer: "Axis Bank",
        catalog_baseline: { ["é".repeat(33)]: true },
      },
      {
        issuer: "Axis Bank",
        source_observation: { ["https://evil.example/?token=secret"]: true },
      },
      {
        issuer: "Axis Bank",
        source_observation: {
          nested:
            "https%253A%252F%252Fuser%253Apass%2540evil.example%252Fcard%253Ftoken%253Dsecret",
        },
      },
    ]
  ) {
    let error: unknown;
    try {
      boundedReviewedCatalogFields(invalid);
    } catch (caught) {
      error = caught;
    }
    assert(
      error instanceof Error,
      `invalid envelope was accepted: ${JSON.stringify(invalid)}`,
    );
  }
});

Deno.test("lifecycle proposal delegates one bounded exact-card review RPC", async () => {
  const calls: Array<{ name: string; args: Record<string, unknown> }> = [];
  const db = {
    async rpc(name: string, args: Record<string, unknown>) {
      calls.push({ name, args });
      return {
        data: "33333333-3333-4333-8333-333333333333",
        error: null,
      };
    },
  };
  const reviewId = await proposeCatalogLifecycleReview(db, {
    cardId: "11111111-1111-4111-8111-111111111111",
    suggestedAction: "mark_discontinued",
    sourceUrl: "https://www.axis.bank.in/card?variant=infinite",
    sourceUrlHash: "a".repeat(64),
    contentHash: "b".repeat(64),
    sourceObservation: {
      kind: "strong_gone_observation",
      source_status: 410,
      identity_validated: false,
    },
  });
  assert(
    reviewId === "33333333-3333-4333-8333-333333333333",
    "lifecycle review id was lost",
  );
  assert(calls.length === 1, "lifecycle proposal was not one transaction");
  assert(
    calls[0].name === "stage_card_catalog_lifecycle_review",
    "wrong lifecycle boundary",
  );
  assert(
    calls[0].args._parser_version === "benefits-v6" &&
      calls[0].args._suggested_action === "mark_discontinued",
    "lifecycle authority metadata was lost",
  );
});

Deno.test("catalog baseline preserves every reviewed mutable and lifecycle authority value", () => {
  const baseline = catalogPublicationBaseline({
    id: "11111111-1111-4111-8111-111111111111",
    card_name: "Privilege",
    network: "Visa",
    annual_fee: 1500,
    joining_fee: null,
    apr: 42,
    card_url: "https://www.axis.bank.in/card?variant=infinite",
    is_discontinued: false,
    updated_at: "2026-08-20T00:00:00.000Z",
  });
  assert(
    JSON.stringify(baseline) === JSON.stringify({
      card_id: "11111111-1111-4111-8111-111111111111",
      card_name: "Privilege",
      network: "Visa",
      annual_fee: 1500,
      joining_fee: null,
      apr: 42,
      card_url: "https://www.axis.bank.in/card?variant=infinite",
      is_discontinued: false,
      updated_at: "2026-08-20T00:00:00.000Z",
    }),
    "baseline omitted stale-review authority",
  );
  assert(
    catalogPublicationBaseline({
      id: "11111111-1111-4111-8111-111111111111",
      card_name: "Legacy Privilege",
      network: null,
      annual_fee: null,
      joining_fee: null,
      apr: null,
      card_url: null,
      is_discontinued: false,
      updated_at: null,
    }).updated_at === null,
    "legacy nullable timestamp could not be bound by its full field snapshot",
  );
  assert(
    catalogPublicationBaseline({
      id: "11111111-1111-4111-8111-111111111111",
      card_name: "Legacy Privilege",
      network: null,
      annual_fee: null,
      joining_fee: null,
      apr: null,
      card_url: null,
      is_discontinued: false,
      updated_at: null,
      retrieved_at: "2026-08-20T01:02:03.000Z",
    }).version_observed_at === "2026-08-20T01:02:03.000Z",
    "nullable legacy version lost the safe source retrieval fallback",
  );
});

Deno.test("central helper rejects malformed or partial publication outcomes", async () => {
  for (
    const data of [[], [{
      card_id: null,
      job_id: "job-1",
      resulting_status: "approved",
    }], [
      { card_id: "card-1", job_id: "job-1", resulting_status: "approved" },
      { card_id: "card-2", job_id: "job-1", resulting_status: "approved" },
    ]]
  ) {
    const db = { rpc: async () => ({ data, error: null }) };
    let error: unknown;
    try {
      await publishReviewedCardIdentity(db, {
        discoveryJobId: "11111111-1111-4111-8111-111111111111",
        reviewItemId: "22222222-2222-4222-8222-222222222222",
        actorId: "33333333-3333-4333-8333-333333333333",
        action: "approve",
        reviewedFields: {},
        parserVersion: "benefits-v6",
      });
    } catch (caught) {
      error = caught;
    }
    assert(error instanceof Error, "partial publication reported success");
  }
});
