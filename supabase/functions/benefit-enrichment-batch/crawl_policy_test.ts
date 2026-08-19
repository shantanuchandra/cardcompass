import {
  assessCrawlCompleteness,
  compactSourceAttempts,
  retirementEligibility,
  type SourceAttemptInput,
  sourceIdentityDigest,
} from "./crawl_policy.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

const PRIMARY = "https://issuer.example/cards/aurora";
const OBSERVED_AT = "2026-08-19T00:00:00.000Z";

function attempt(
  overrides: Partial<SourceAttemptInput> = {},
): SourceAttemptInput {
  return {
    requestedUrl: PRIMARY,
    role: "primary",
    status: "success",
    httpStatus: 200,
    contentHash: "a".repeat(64),
    attemptedAt: OBSERVED_AT,
    ...overrides,
  };
}

function attemptWithUntrusted(
  overrides: Partial<SourceAttemptInput>,
  untrusted: Record<string, unknown>,
): SourceAttemptInput {
  return { ...attempt(overrides), ...untrusted } as SourceAttemptInput;
}

Deno.test("a successful primary source is a complete crawl", () => {
  const result = assessCrawlCompleteness([attempt()], OBSERVED_AT);

  assert(result.complete, "primary success was not complete");
  assert(result.attempts.length === 1, "primary attempt was not retained");
});

Deno.test("logical source identity preserves approved duplicate query order", () => {
  const left = sourceIdentityDigest(
    `${PRIMARY}?variant=z&document=mitc&variant=a`,
  );
  const right = sourceIdentityDigest(
    `${PRIMARY}?document=mitc&variant=z&variant=a`,
  );
  assert(left !== right, "query ordering was erased from source identity");
});

Deno.test("an attempted optional identity failure blocks completeness until that source is replaced", () => {
  const optionalUrl = `${PRIMARY}/benefits`;
  const mismatch = attempt({
    requestedUrl: optionalUrl,
    role: "supporting",
    status: "failed",
    httpStatus: 200,
    contentHash: undefined,
    errorCode: "identity_mismatch",
    attemptedAt: "2026-08-19T00:00:01.000Z",
  });
  const failed = assessCrawlCompleteness(
    [attempt(), mismatch],
    "2026-08-19T00:01:00.000Z",
  );
  assert(!failed.complete, "optional identity mismatch enabled removals");
  assert(
    failed.reason === "identity_mismatch",
    "optional identity failure did not retain an explicit reason",
  );

  const recovered = assessCrawlCompleteness([
    attempt(),
    mismatch,
    attempt({
      requestedUrl: optionalUrl,
      role: "supporting",
      attemptedAt: "2026-08-19T00:00:02.000Z",
    }),
  ], "2026-08-19T00:01:00.000Z");
  assert(
    recovered.complete,
    "later exact-identity replacement stayed incomplete",
  );
});

Deno.test("selected query-policy failures are explicit and block absence decisions", () => {
  for (const role of ["required_supporting", "supporting"] as const) {
    const result = assessCrawlCompleteness([
      attempt(),
      attempt({
        requestedUrl: `${PRIMARY}/terms?product=aurora`,
        role,
        status: "failed",
        contentHash: undefined,
        errorCode: "unapproved_query",
        attemptedAt: "2026-08-19T00:00:01.000Z",
      }),
    ], "2026-08-19T00:01:00.000Z");
    assert(!result.complete, `${role} query rejection enabled removals`);
    assert(
      result.attempts.some((item) =>
        item.errorCode === "unapproved_query" && !item.url.includes("?")
      ),
      `${role} rejection was lost or exposed its query`,
    );
  }
});

Deno.test("final resource identities survive compaction and conflicting redirects fail closed", () => {
  const firstFinal = "b".repeat(64);
  const secondFinal = "c".repeat(64);
  const attempts = [
    attemptWithUntrusted({
      status: "failed",
      contentHash: undefined,
      errorCode: "http_5xx",
      attemptedAt: "2026-08-19T00:00:00.000Z",
    }, { finalResourceIdentityHash: firstFinal }),
    attemptWithUntrusted({
      attemptedAt: "2026-08-19T00:00:01.000Z",
    }, { finalResourceIdentityHash: secondFinal }),
  ];
  const result = compactSourceAttempts(
    attempts.map((item) => ({
      ...item,
      url: item.requestedUrl,
      logicalSourceKey: "f".repeat(64),
    })) as never,
    "2026-08-19T00:01:00.000Z",
  );
  const terminal = result.attempts[0] as unknown as Record<string, unknown>;
  const history = terminal.attemptHistory as Array<Record<string, unknown>>;
  assert(
    terminal.finalResourceIdentityHash === secondFinal,
    "terminal final resource identity was dropped",
  );
  assert(
    history.map((item) => item.finalResourceIdentityHash).join(",") ===
      `${firstFinal},${secondFinal}`,
    "redirect identity transition disappeared from retry history",
  );
  assert(
    !result.complete,
    "conflicting final resources established completeness",
  );
  assert(
    result.reason === "final_resource_identity_conflict",
    "final resource conflict reason was not explicit",
  );
});

Deno.test("attempt compaction is idempotent and preserves existing retry history", () => {
  const attempts = [
    attempt({
      status: "failed",
      httpStatus: 503,
      errorCode: "http_5xx",
      contentHash: undefined,
      attemptedAt: "2026-08-19T00:00:00.000Z",
    }),
    attempt({
      status: "failed",
      httpStatus: 503,
      errorCode: "http_5xx",
      contentHash: undefined,
      attemptedAt: "2026-08-19T00:00:01.000Z",
    }),
    attempt({ attemptedAt: "2026-08-19T00:00:02.000Z" }),
  ].map((item) => ({
    ...item,
    url: item.requestedUrl,
    logicalSourceKey: "f".repeat(64),
  }));
  const first = compactSourceAttempts(
    attempts as never,
    "2026-08-19T00:01:00.000Z",
  );
  const second = compactSourceAttempts(
    first.attempts,
    "2026-08-19T00:01:00.000Z",
  );
  assert(
    first.attempts[0].attemptHistory?.map((entry) => entry.httpStatus).join(
      ",",
    ) === "503,503,200",
    "initial compaction did not preserve the retry sequence",
  );
  assert(
    JSON.stringify(second.attempts) === JSON.stringify(first.attempts),
    "recompaction erased or duplicated existing history",
  );
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

Deno.test("global compaction keeps the logical source retry status sequence", () => {
  const attempts = [
    attempt({
      status: "failed",
      httpStatus: 404,
      contentHash: undefined,
      errorCode: "http_404",
      attemptedAt: "2026-08-19T00:00:00.000Z",
    }),
    attempt({ attemptedAt: "2026-08-19T00:00:01.000Z" }),
    ...Array.from({ length: 9 }, (_, index) =>
      attempt({
        requestedUrl: `${PRIMARY}/optional-${index}`,
        role: "supporting",
        attemptedAt: `2026-08-19T00:01:${String(index).padStart(2, "0")}.000Z`,
      })),
  ];
  const result = assessCrawlCompleteness(
    attempts,
    "2026-08-19T00:02:00.000Z",
  );
  const primary = result.attempts.find((item) => item.role === "primary");
  assert(result.complete, "compaction lost the successful terminal retry");
  assert(
    primary?.attemptHistory?.map((item) => item.status).join(",") ===
      "failed,success",
    "404 to 200 history could not be reconstructed after compaction",
  );
});

Deno.test("overflowing one logical retry history is explicitly incomplete", () => {
  const result = assessCrawlCompleteness(
    Array.from({ length: 8 }, (_, index) =>
      attempt({
        status: index === 7 ? "success" : "failed",
        contentHash: index === 7 ? "a".repeat(64) : undefined,
        errorCode: index === 7 ? undefined : "http_5xx",
        attemptedAt: `2026-08-19T00:00:0${index}.000Z`,
      })),
    "2026-08-19T00:01:00.000Z",
  );
  assert(!result.complete, "overflowed retry history established completeness");
  assert(
    result.reason === "attempt_history_overflow",
    "retry history overflow was not explicit",
  );
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
      requestedUrl: required,
      role: "required_supporting",
      status: "failed",
      contentHash: undefined,
      errorCode: "http_404",
      attemptedAt: "2026-08-19T00:01:00.000Z",
    }),
    attempt({
      requestedUrl: required,
      finalUrl: `${required}?retry=1`,
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
    attempt({ requestedUrl: `${PRIMARY}?submitted=1` }),
    attempt({
      requestedUrl: `${PRIMARY}?submitted=2`,
      finalUrl: `${PRIMARY}/other`,
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
        requestedUrl: `${PRIMARY}/terms.pdf`,
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
      requestedUrl: `${PRIMARY}/optional-benefits`,
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

Deno.test("an unreadable selected PDF keeps the crawl incomplete even when its link was optional", () => {
  const result = assessCrawlCompleteness([
    attempt(),
    attempt({
      requestedUrl: `${PRIMARY}/benefits.pdf`,
      role: "supporting",
      status: "failed",
      errorCode: "corrupt_pdf",
    }),
  ], OBSERVED_AT);
  assert(!result.complete, "outstanding PDF fallback was treated as complete");
  assert(result.reason === "corrupt_pdf", "PDF fallback reason was lost");
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
  const result = assessCrawlCompleteness(
    [attemptWithUntrusted({
      requestedUrl:
        "https://user:secret@issuer.example/cards/aurora?session=cookie#private",
      status: "failed",
      contentHash: undefined,
      errorCode: "Authorization: Bearer secret-cookie-value",
    }, { logicalSourceKey: "Authorization: Bearer secret-cookie-value" })],
    OBSERVED_AT,
  );
  const persisted = result.attempts[0];

  assert(
    persisted.url === "invalid-source",
    "credential-bearing source was represented as valid evidence",
  );
  assert(
    persisted.errorCode === "invalid_source_url",
    "unsanitized error text survived as an error code",
  );
  assert(
    !JSON.stringify(persisted).includes("secret"),
    "secret material survived bounded attempt evidence",
  );
});

Deno.test("invalid successful primary URLs cannot establish completeness", () => {
  for (
    const url of [
      "%%%",
      "http://issuer.example/cards/aurora",
      "https://user:secret@issuer.example/cards/aurora",
    ]
  ) {
    const result = assessCrawlCompleteness(
      [attempt({ requestedUrl: url })],
      OBSERVED_AT,
    );
    assert(!result.complete, `invalid primary source was accepted: ${url}`);
    assert(
      result.attempts[0].url === "invalid-source",
      "invalid source was mapped to a shared valid placeholder",
    );
    assert(
      !JSON.stringify(result.attempts[0]).includes("secret"),
      "invalid source evidence retained credentials",
    );
  }
  assert(
    assessCrawlCompleteness([attempt()], OBSERVED_AT).complete,
    "valid HTTPS primary source stopped establishing completeness",
  );
});

Deno.test("distinct required query sources cannot mask one another", () => {
  const result = assessCrawlCompleteness([
    attempt(),
    attempt({
      requestedUrl: `${PRIMARY}/terms?card=alpha`,
      role: "required_supporting",
      status: "failed",
      contentHash: undefined,
      errorCode: "http_404",
      attemptedAt: "2026-08-19T00:01:00.000Z",
    }),
    attempt({
      requestedUrl: `${PRIMARY}/terms?card=beta`,
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
    attemptWithUntrusted({
      requestedUrl: `${PRIMARY}/documents/alpha`,
      role: "required_supporting",
      status: "failed",
      contentHash: undefined,
      errorCode: "http_404",
      attemptedAt: "2026-08-19T00:01:00.000Z",
    }, { logicalSourceKey: "source-1dwsp5w-ogr" }),
    attemptWithUntrusted({
      requestedUrl: `${PRIMARY}/documents/beta`,
      role: "required_supporting",
      attemptedAt: "2026-08-19T00:02:00.000Z",
    }, { logicalSourceKey: "source-1xm3hyf-13xs" }),
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
    attemptWithUntrusted({
      requestedUrl: required,
      role: "required_supporting",
      status: "failed",
      contentHash: undefined,
      errorCode: "http_404",
      attemptedAt: "2026-08-19T00:01:00.000Z",
    }, { logicalSourceKey: "submitted" }),
    attemptWithUntrusted({
      requestedUrl: required,
      role: "required_supporting",
      attemptedAt: "2026-08-19T00:02:00.000Z",
    }, { logicalSourceKey: "unconditional" }),
  ], "2026-08-19T00:03:00.000Z");

  assert(result.complete, "retry labels split one required source");
});

Deno.test("a valid-looking digest cannot merge two different required URLs", () => {
  const attackerChosenDigest = "f".repeat(64);
  const result = assessCrawlCompleteness([
    attempt(),
    attemptWithUntrusted({
      requestedUrl: `${PRIMARY}/terms?card=alpha`,
      role: "required_supporting",
      status: "failed",
      contentHash: undefined,
      errorCode: "http_404",
      attemptedAt: "2026-08-19T00:01:00.000Z",
    }, { logicalSourceKey: attackerChosenDigest }),
    attemptWithUntrusted({
      requestedUrl: `${PRIMARY}/terms?card=beta`,
      role: "required_supporting",
      attemptedAt: "2026-08-19T00:02:00.000Z",
    }, { logicalSourceKey: attackerChosenDigest }),
  ], "2026-08-19T00:03:00.000Z");

  assert(!result.complete, "unproven digest masked a required-source failure");
  assert(
    result.attempts[1].logicalSourceKey !== attackerChosenDigest,
    "caller-controlled digest survived as authoritative identity",
  );
});

Deno.test("caller source identity cannot merge distinct required URLs", () => {
  const attackerChosenIdentity = `${PRIMARY}/terms?card=alpha`;
  const result = assessCrawlCompleteness([
    attempt(),
    attemptWithUntrusted({
      requestedUrl: `${PRIMARY}/terms?card=alpha`,
      role: "required_supporting",
      status: "failed",
      contentHash: undefined,
      errorCode: "http_404",
      attemptedAt: "2026-08-19T00:01:00.000Z",
    }, { sourceIdentity: attackerChosenIdentity }),
    attemptWithUntrusted({
      requestedUrl: `${PRIMARY}/terms?card=beta`,
      role: "required_supporting",
      attemptedAt: "2026-08-19T00:02:00.000Z",
    }, { sourceIdentity: attackerChosenIdentity }),
  ], "2026-08-19T00:03:00.000Z");

  assert(
    !result.complete,
    "caller-controlled source identity masked a required failure",
  );
  assert(
    result.attempts[1].logicalSourceKey !==
      result.attempts[2].logicalSourceKey,
    "distinct requested URLs inherited caller grouping",
  );
});

Deno.test("trusted requested URL groups redirects without persisting queries", () => {
  const requestedUrl = `${PRIMARY}/terms?card=alpha`;
  const result = assessCrawlCompleteness([
    attempt(),
    {
      ...attempt({
        requestedUrl,
        finalUrl: `${PRIMARY}/terms`,
        role: "required_supporting",
        status: "failed",
        contentHash: undefined,
        errorCode: "http_404",
        attemptedAt: "2026-08-19T00:01:00.000Z",
      }),
    },
    {
      ...attempt({
        requestedUrl,
        finalUrl: `${PRIMARY}/terms?retry=unconditional`,
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

Deno.test("malformed runtime attempts fail closed without leaking input", () => {
  const assessRuntime = assessCrawlCompleteness as (
    attempts: unknown,
    assessmentTime: string,
  ) => ReturnType<typeof assessCrawlCompleteness>;
  const malformedInputs: unknown[] = [
    null,
    undefined,
    "https://user:secret@issuer.example/?token=private",
    5,
    { requestedUrl: PRIMARY, role: "primary" },
  ];
  for (const malformed of malformedInputs) {
    const result = assessRuntime([attempt(), malformed], OBSERVED_AT);
    assert(!result.complete, "malformed attempt allowed completeness");
    assert(result.reason === "invalid_attempt", "wrong malformed reason");
    assert(result.attempts.length <= 9, "malformed evidence exceeded bound");
    const serialized = JSON.stringify(result.attempts);
    assert(serialized.includes("invalid_attempt"), "missing invalid marker");
    assert(!serialized.includes("secret"), "malformed input leaked a secret");
    assert(!serialized.includes("private"), "malformed query leaked");
  }

  for (const malformedRoot of [null, undefined, "corrupt", 5, {}]) {
    const result = assessRuntime(malformedRoot, OBSERVED_AT);
    assert(!result.complete, "malformed attempt root allowed completeness");
    assert(result.reason === "invalid_attempt", "root failure was ambiguous");
    assert(result.attempts.length === 1, "root marker was not bounded");
  }
});

Deno.test("runtime attempt bounding cannot omit a decisive required source", () => {
  const optional = Array.from({ length: 8 }, (_, index) =>
    attempt({
      requestedUrl: `${PRIMARY}/benefits-${index}`,
      role: "supporting",
      attemptedAt: `2026-08-19T00:0${index + 1}:00.000Z`,
    }));
  const result = assessCrawlCompleteness([
    attempt(),
    ...optional,
    attempt({
      requestedUrl: `${PRIMARY}/terms`,
      role: "required_supporting",
      status: "failed",
      contentHash: undefined,
      errorCode: "http_404",
      attemptedAt: "2026-08-19T00:09:00.000Z",
    }),
  ], "2026-08-19T00:10:00.000Z");

  assert(!result.complete, "bounded assessment omitted required failure");
  assert(
    result.attempts.length <= 9,
    "assessment evidence exceeded hard bound",
  );
  assert(
    result.attempts.some((item) => item.role === "required_supporting"),
    "decisive required evidence was dropped",
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
