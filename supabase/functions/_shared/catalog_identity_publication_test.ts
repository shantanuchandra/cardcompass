import {
  canonicalPublicationResource,
  catalogLifecycleSuggestion,
  catalogPublicationBaseline,
  proposeCatalogLifecycleReview,
  publicationFieldsFromFetch,
  publishReviewedCardIdentity,
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
