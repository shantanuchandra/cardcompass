import {
  assessCrawlCompleteness,
  retirementEligibility,
  type SourceAttempt,
} from "./crawl_policy.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

const PRIMARY = "https://issuer.example/cards/aurora";
const OBSERVED_AT = "2026-08-19T00:00:00.000Z";

function attempt(
  overrides: Partial<SourceAttempt> = {},
): SourceAttempt {
  return {
    url: PRIMARY,
    role: "primary",
    status: "success",
    httpStatus: 200,
    contentHash: "a".repeat(64),
    attemptedAt: OBSERVED_AT,
    ...overrides,
  };
}

Deno.test("a successful primary source is a complete crawl", () => {
  const result = assessCrawlCompleteness([attempt()], OBSERVED_AT);

  assert(result.complete, "primary success was not complete");
  assert(result.attempts.length === 1, "primary attempt was not retained");
});

Deno.test("a source with an invalid or local timestamp cannot establish completeness", () => {
  for (const attemptedAt of ["not-a-date", "2026-08-19T00:00:00"]) {
    const result = assessCrawlCompleteness(
      [attempt({ attemptedAt })],
      OBSERVED_AT,
    );
    assert(
      !result.complete,
      `unsafe attempt timestamp was accepted: ${attemptedAt}`,
    );
  }
});

Deno.test("a primary 304 is complete only with reusable same-parser cache evidence", () => {
  const withoutCache = assessCrawlCompleteness([attempt({
    status: "not_modified",
    httpStatus: 304,
    contentHash: undefined,
    parserCacheReusable: false,
  })], OBSERVED_AT);
  const withCache = assessCrawlCompleteness([attempt({
    status: "not_modified",
    httpStatus: 304,
    parserCacheReusable: true,
  })], OBSERVED_AT);

  assert(!withoutCache.complete, "304 invented reusable parser state");
  assert(withCache.complete, "explicit reusable 304 cache was rejected");
});

Deno.test("latest successful retry completes one logical primary source", () => {
  const result = assessCrawlCompleteness([
    attempt({
      status: "failed",
      httpStatus: 404,
      contentHash: undefined,
      errorCode: "http_404",
      attemptedAt: "2026-08-19T00:00:00.000Z",
    }),
    attempt({ attemptedAt: "2026-08-19T00:01:00.000Z" }),
  ], "2026-08-19T00:02:00.000Z");
  assert(result.complete, "404 followed by 200 stayed incomplete");
  assert(result.attempts.length === 2, "retry evidence was discarded");
});

Deno.test("latest failed retry keeps one logical primary source incomplete", () => {
  const result = assessCrawlCompleteness([
    attempt({ attemptedAt: "2026-08-19T00:00:00.000Z" }),
    attempt({
      status: "failed",
      contentHash: undefined,
      errorCode: "timeout",
      attemptedAt: "2026-08-19T00:01:00.000Z",
    }),
  ], "2026-08-19T00:02:00.000Z");
  assert(!result.complete, "200 followed by failure became complete");
});

Deno.test("unusable 304 followed by unconditional 200 becomes complete", () => {
  const result = assessCrawlCompleteness([
    attempt({
      status: "not_modified",
      httpStatus: 304,
      contentHash: undefined,
      parserCacheReusable: false,
      attemptedAt: "2026-08-19T00:00:00.000Z",
    }),
    attempt({ attemptedAt: "2026-08-19T00:01:00.000Z" }),
  ], "2026-08-19T00:02:00.000Z");
  assert(result.complete, "unconditional retry did not recover unusable 304");
});

Deno.test("required retries resolve by logical URL and latest result", () => {
  const required = `${PRIMARY}/terms`;
  const result = assessCrawlCompleteness([
    attempt(),
    attempt({
      url: required,
      role: "required_supporting",
      status: "failed",
      contentHash: undefined,
      errorCode: "http_404",
      sourceIdentity: required,
      attemptedAt: "2026-08-19T00:01:00.000Z",
    }),
    attempt({
      url: `${required}?retry=1`,
      sourceIdentity: required,
      role: "required_supporting",
      attemptedAt: "2026-08-19T00:02:00.000Z",
    }),
  ], "2026-08-19T00:03:00.000Z");
  assert(result.complete, "required source retry stayed incomplete");
});

Deno.test("duplicate or malformed retry timestamps remain incomplete", () => {
  for (const attemptedAt of [OBSERVED_AT, "not-a-date"]) {
    const result = assessCrawlCompleteness([
      attempt(),
      attempt({ attemptedAt, status: "failed", contentHash: undefined }),
    ], "2026-08-19T00:02:00.000Z");
    assert(
      !result.complete,
      `unsafe retry timestamp was accepted: ${attemptedAt}`,
    );
  }
});

Deno.test("explicitly distinct logical primary sources remain incomplete", () => {
  const result = assessCrawlCompleteness([
    attempt({ sourceIdentity: `${PRIMARY}?submitted=1` }),
    attempt({
      url: `${PRIMARY}/other`,
      sourceIdentity: `${PRIMARY}?submitted=2`,
      attemptedAt: "2026-08-19T00:01:00.000Z",
    }),
  ], "2026-08-19T00:02:00.000Z");
  assert(
    !result.complete,
    "distinct primary sources bypassed multiplicity guard",
  );
});

Deno.test("a missing or corrupt required PDF makes the crawl incomplete", () => {
  for (
    const [httpStatus, errorCode] of [[404, "http_404"], [
      200,
      "corrupt_pdf",
    ]] as const
  ) {
    const result = assessCrawlCompleteness([
      attempt(),
      attempt({
        url: `${PRIMARY}/terms.pdf`,
        role: "required_supporting",
        status: "failed",
        httpStatus,
        contentHash: undefined,
        errorCode,
      }),
    ], OBSERVED_AT);
    assert(
      !result.complete,
      `${errorCode} required PDF was treated as complete`,
    );
    assert(result.attempts.length === 2, `${errorCode} attempt was dropped`);
  }
});

Deno.test("an optional supporting failure is retained without making the crawl incomplete", () => {
  const result = assessCrawlCompleteness([
    attempt(),
    attempt({
      url: `${PRIMARY}/optional-benefits`,
      role: "supporting",
      status: "failed",
      httpStatus: 503,
      contentHash: undefined,
      errorCode: "unreachable",
    }),
  ], OBSERVED_AT);

  assert(result.complete, "optional failure blocked a complete primary crawl");
  assert(result.attempts.length === 2, "optional failed attempt was dropped");
  assert(
    result.attempts[1].errorCode === "unreachable",
    "optional failure code was not retained",
  );
});

for (
  const fixture of [
    { label: "JS challenge", httpStatus: 403, errorCode: "js_challenge" },
    { label: "timeout", httpStatus: undefined, errorCode: "timeout" },
    { label: "403", httpStatus: 403, errorCode: "http_403" },
    { label: "404", httpStatus: 404, errorCode: "http_404" },
    { label: "410", httpStatus: 410, errorCode: "http_410" },
    {
      label: "redirect outside issuer",
      httpStatus: 302,
      errorCode: "redirect_rejected",
    },
  ] as const
) {
  Deno.test(`a primary ${fixture.label} is incomplete`, () => {
    const result = assessCrawlCompleteness([attempt({
      status: "failed",
      httpStatus: fixture.httpStatus,
      contentHash: undefined,
      errorCode: fixture.errorCode,
    })], OBSERVED_AT);

    assert(!result.complete, `${fixture.label} enabled absence decisions`);
  });
}

Deno.test("attempt evidence strips credentials and bounds unsanitized failure data", () => {
  const result = assessCrawlCompleteness([attempt({
    url:
      "https://user:secret@issuer.example/cards/aurora?session=cookie#private",
    status: "failed",
    contentHash: undefined,
    errorCode: "Authorization: Bearer secret-cookie-value",
    logicalSourceKey: "Authorization: Bearer secret-cookie-value",
  })], OBSERVED_AT);
  const persisted = result.attempts[0];

  assert(
    persisted.url === "https://issuer.example/cards/aurora",
    "credentials or query secrets survived URL sanitization",
  );
  assert(
    persisted.errorCode === "unreachable",
    "unsanitized error text survived as an error code",
  );
  assert(
    !JSON.stringify(persisted).includes("secret"),
    "secret material survived bounded attempt evidence",
  );
});

Deno.test("distinct required query sources cannot mask one another", () => {
  const result = assessCrawlCompleteness([
    attempt(),
    attempt({
      url: `${PRIMARY}/terms?card=alpha`,
      role: "required_supporting",
      status: "failed",
      contentHash: undefined,
      errorCode: "http_404",
      attemptedAt: "2026-08-19T00:01:00.000Z",
    }),
    attempt({
      url: `${PRIMARY}/terms?card=beta`,
      role: "required_supporting",
      attemptedAt: "2026-08-19T00:02:00.000Z",
    }),
  ], "2026-08-19T00:03:00.000Z");

  assert(!result.complete, "query-distinct required sources collided");
  assert(
    result.attempts.every((item) => !item.url.includes("?")),
    "private query data survived persisted evidence",
  );
});

Deno.test("known 32-bit opaque-key collisions cannot merge distinct sources", () => {
  const result = assessCrawlCompleteness([
    attempt(),
    attempt({
      url: `${PRIMARY}/documents/alpha`,
      logicalSourceKey: "source-1dwsp5w-ogr",
      role: "required_supporting",
      status: "failed",
      contentHash: undefined,
      errorCode: "http_404",
      attemptedAt: "2026-08-19T00:01:00.000Z",
    }),
    attempt({
      url: `${PRIMARY}/documents/beta`,
      logicalSourceKey: "source-1xm3hyf-13xs",
      role: "required_supporting",
      attemptedAt: "2026-08-19T00:02:00.000Z",
    }),
  ], "2026-08-19T00:03:00.000Z");

  assert(!result.complete, "colliding opaque keys merged required sources");
  assert(
    result.attempts[1].logicalSourceKey !==
      result.attempts[2].logicalSourceKey,
    "derived source identities inherited the caller collision",
  );
});

Deno.test("arbitrary retry labels cannot split one logical required source", () => {
  const required = `${PRIMARY}/terms`;
  const result = assessCrawlCompleteness([
    attempt(),
    attempt({
      url: required,
      logicalSourceKey: "submitted",
      role: "required_supporting",
      status: "failed",
      contentHash: undefined,
      errorCode: "http_404",
      attemptedAt: "2026-08-19T00:01:00.000Z",
    }),
    attempt({
      url: required,
      logicalSourceKey: "unconditional",
      role: "required_supporting",
      attemptedAt: "2026-08-19T00:02:00.000Z",
    }),
  ], "2026-08-19T00:03:00.000Z");

  assert(result.complete, "retry labels split one required source");
});

Deno.test("a valid-looking digest cannot merge two different required URLs", () => {
  const attackerChosenDigest = "f".repeat(64);
  const result = assessCrawlCompleteness([
    attempt(),
    attempt({
      url: `${PRIMARY}/terms?card=alpha`,
      logicalSourceKey: attackerChosenDigest,
      role: "required_supporting",
      status: "failed",
      contentHash: undefined,
      errorCode: "http_404",
      attemptedAt: "2026-08-19T00:01:00.000Z",
    }),
    attempt({
      url: `${PRIMARY}/terms?card=beta`,
      logicalSourceKey: attackerChosenDigest,
      role: "required_supporting",
      attemptedAt: "2026-08-19T00:02:00.000Z",
    }),
  ], "2026-08-19T00:03:00.000Z");

  assert(!result.complete, "unproven digest masked a required-source failure");
  assert(
    result.attempts[1].logicalSourceKey !== attackerChosenDigest,
    "caller-controlled digest survived as authoritative identity",
  );
});

Deno.test("trusted full-source identity groups retry stages without persisting queries", () => {
  const sourceIdentity = `${PRIMARY}/terms?card=alpha`;
  const result = assessCrawlCompleteness([
    attempt(),
    {
      ...({ sourceIdentity } as Record<string, unknown>),
      ...attempt({
        url: `${PRIMARY}/terms`,
        role: "required_supporting",
        status: "failed",
        contentHash: undefined,
        errorCode: "http_404",
        attemptedAt: "2026-08-19T00:01:00.000Z",
      }),
    },
    {
      ...({ sourceIdentity } as Record<string, unknown>),
      ...attempt({
        url: `${PRIMARY}/terms?retry=unconditional`,
        role: "required_supporting",
        attemptedAt: "2026-08-19T00:02:00.000Z",
      }),
    },
  ], "2026-08-19T00:03:00.000Z");

  assert(result.complete, "trusted retry stages did not group");
  const serialized = JSON.stringify(result.attempts);
  assert(!serialized.includes("card=alpha"), "raw source identity persisted");
  assert(!serialized.includes("retry="), "raw query persisted in display URL");
  assert(
    result.attempts[1].logicalSourceKey ===
      result.attempts[2].logicalSourceKey,
    "trusted retry identity did not produce one persisted digest",
  );
  assert(
    result.attempts[1].logicalSourceKey ===
      "b034e9f2fbc97510f3d28b27b262e23fa1a55bb1dba834da417f613fa4ecc310",
    "persisted identity is not SHA-256 of the canonical full source",
  );
});

Deno.test("far-future terminal evidence is conservatively incomplete", () => {
  const result = assessCrawlCompleteness([
    attempt({
      status: "failed",
      contentHash: undefined,
      errorCode: "timeout",
      attemptedAt: "2026-08-19T00:01:00.000Z",
    }),
    attempt({ attemptedAt: "9999-12-31T23:59:59.999Z" }),
  ], "2026-08-19T00:02:00.000Z");

  assert(!result.complete, "far-future success dominated real failure");
  assert(
    result.reason === "primary_incomplete",
    "wrong future evidence reason",
  );
});

Deno.test("small explicit clock skew is accepted", () => {
  const result = assessCrawlCompleteness([
    attempt({ attemptedAt: "2026-08-19T00:04:59.999Z" }),
  ], OBSERVED_AT);
  assert(result.complete, "bounded clock skew was rejected");
});

Deno.test("two complete observations less than seven days apart are ineligible", () => {
  const result = retirementEligibility({
    completeAbsenceObservedAt: [
      "2026-08-12T00:00:00.001Z",
      "2026-08-19T00:00:00.000Z",
    ],
    now: "2026-08-19T00:00:00.000Z",
  });

  assert(!result.eligible, "sub-seven-day observations allowed retirement");
});

Deno.test("two independent complete observations at least seven 24-hour periods apart are eligible", () => {
  const result = retirementEligibility({
    completeAbsenceObservedAt: [
      "2026-08-12T00:00:00.000Z",
      "2026-08-19T00:00:00.000Z",
    ],
    now: "2026-08-19T00:00:00.000Z",
  });

  assert(result.eligible, "seven-day independent observations were rejected");
  assert(result.reason === "two_complete_observations", "wrong policy reason");
});

Deno.test("an explicit issuer end date must be a valid past UTC date", () => {
  const past = retirementEligibility({
    explicitEndDate: "2026-08-18",
    completeAbsenceObservedAt: [],
    now: "2026-08-19T00:00:00.000Z",
  });
  const today = retirementEligibility({
    explicitEndDate: "2026-08-19",
    completeAbsenceObservedAt: [],
    now: "2026-08-19T23:59:59.999Z",
  });
  const future = retirementEligibility({
    explicitEndDate: "2026-08-20",
    completeAbsenceObservedAt: [
      "2026-08-12T00:00:00.000Z",
      "2026-08-19T23:59:59.999Z",
    ],
    now: "2026-08-19T23:59:59.999Z",
  });

  assert(past.eligible, "past issuer end date was rejected");
  assert(!today.eligible, "current UTC date was considered past");
  assert(!future.eligible, "future issuer end date was considered past");
});

Deno.test("invalid, rolled, local-time, offset, and future observation dates are ineligible", () => {
  for (
    const dates of [
      ["2026-02-30T00:00:00.000Z", "2026-08-19T00:00:00.000Z"],
      ["2026-08-12T00:00:00", "2026-08-19T00:00:00.000Z"],
      ["2026-08-12T05:30:00+05:30", "2026-08-19T00:00:00.000Z"],
      ["2026-08-12T00:00:00.000Z", "2026-08-20T00:00:00.000Z"],
    ]
  ) {
    const result = retirementEligibility({
      completeAbsenceObservedAt: dates,
      now: "2026-08-19T00:00:00.000Z",
    });
    assert(!result.eligible, `unsafe date pair was accepted: ${dates}`);
  }
});

Deno.test("UTC midnight governs explicit-date retirement regardless of host timezone", () => {
  const beforeMidnight = retirementEligibility({
    explicitEndDate: "2026-08-19",
    completeAbsenceObservedAt: [],
    now: "2026-08-19T23:59:59.999Z",
  });
  const afterMidnight = retirementEligibility({
    explicitEndDate: "2026-08-19",
    completeAbsenceObservedAt: [],
    now: "2026-08-20T00:00:00.000Z",
  });

  assert(!beforeMidnight.eligible, "issuer date ended before UTC midnight");
  assert(afterMidnight.eligible, "issuer date did not end at UTC midnight");
});
