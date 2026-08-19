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
  const result = assessCrawlCompleteness([attempt()]);

  assert(result.complete, "primary success was not complete");
  assert(result.attempts.length === 1, "primary attempt was not retained");
});

Deno.test("a source with an invalid or local timestamp cannot establish completeness", () => {
  for (const attemptedAt of ["not-a-date", "2026-08-19T00:00:00"]) {
    const result = assessCrawlCompleteness([attempt({ attemptedAt })]);
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
  })]);
  const withCache = assessCrawlCompleteness([attempt({
    status: "not_modified",
    httpStatus: 304,
    parserCacheReusable: true,
  })]);

  assert(!withoutCache.complete, "304 invented reusable parser state");
  assert(withCache.complete, "explicit reusable 304 cache was rejected");
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
    ]);
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
  ]);

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
    })]);

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
  })]);
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
