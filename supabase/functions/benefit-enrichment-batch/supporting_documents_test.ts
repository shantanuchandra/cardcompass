import { collectSupportingBenefitDocuments } from "./supporting_documents.ts";
import { assessCrawlCompleteness } from "./crawl_policy.ts";
import { extractGroundedBenefitsV6 } from "../_shared/benefit_enrichment.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

function resource(
  url: string,
  text: string,
  contentType = "text/html",
) {
  return {
    status: 200,
    submittedUrl: url,
    finalUrl: url,
    canonicalUrl: url,
    contentType,
    bytes: new TextEncoder().encode(text),
    text: contentType === "application/pdf" ? "" : text,
    contentHash: "a".repeat(64),
    retrievedAt: "2026-08-17T00:00:00.000Z",
    notModified: false,
  };
}

Deno.test("supporting redirects remain bound to the expected card identity", async () => {
  const privilege = "https://www.axis.bank.in/cards/credit-card/privilege";
  const terms = `${privilege}/terms`;
  for (
    const fixture of [
      {
        label: "same card",
        finalUrl: terms,
        body: "Privilege Credit Card terms and fee waiver",
        complete: true,
      },
      {
        label: "different card",
        finalUrl: "https://www.axis.bank.in/cards/credit-card/regalia/terms",
        body: "Regalia Credit Card terms and benefits",
        complete: false,
      },
      {
        label: "generic redirect",
        finalUrl: "https://www.axis.bank.in/cards/credit-card/terms",
        body: "Generic credit card terms and conditions",
        complete: false,
      },
    ]
  ) {
    const primary = resource(
      privilege,
      `<h1>Privilege Credit Card</h1><a href="${terms}">Terms</a>`,
    );
    const collected = await collectSupportingBenefitDocuments({
      issuer: "Axis Bank",
      primary,
      identityLabels: ["Privilege Credit Card"],
      fetchOfficialIssuerResource: async () => ({
        ...resource(fixture.finalUrl, fixture.body),
        submittedUrl: terms,
        finalUrl: fixture.finalUrl,
        canonicalUrl: fixture.finalUrl,
      }),
    });
    const assessed = assessCrawlCompleteness(
      collected.attempts,
      "2026-08-17T00:01:00.000Z",
    );
    assert(
      assessed.complete === fixture.complete,
      `${fixture.label} identity result was not conservative`,
    );
    if (!fixture.complete) {
      assert(
        collected.attempts.some((attempt) =>
          attempt.errorCode === "identity_mismatch"
        ),
        `${fixture.label} did not retain identity mismatch evidence`,
      );
    }
  }
});

Deno.test("supporting identity reconciles conflicting strong labels and ignores ordinary partner prose", async () => {
  const privilege = "https://www.axis.bank.in/cards/credit-card/privilege";
  const benefits = `${privilege}/benefits`;
  for (
    const [body, expectedComplete] of [
      [
        "<title>Privilege Credit Card</title><h1>Regalia Gold Credit Card</h1>",
        false,
      ],
      [
        "<title>Privilege Credit Card</title><h1>Privilege Visa Infinite Credit Card</h1><p>Offer at the Regalia Gold hotel partner.</p>",
        true,
      ],
    ] as const
  ) {
    const collected = await collectSupportingBenefitDocuments({
      issuer: "Axis Bank",
      primary: resource(
        privilege,
        `<h1>Privilege Credit Card</h1><a href="${benefits}">Benefits</a>`,
      ),
      identityLabels: ["Privilege Credit Card"],
      fetchOfficialIssuerResource: async () => resource(benefits, body),
    });
    const assessment = assessCrawlCompleteness(
      collected.attempts,
      "2026-08-17T00:01:00.000Z",
    );
    assert(
      assessment.complete === expectedComplete,
      `reconciled supporting identity was ${assessment.reason}`,
    );
  }
});

Deno.test("supporting documents require body identity even on nested or curated URLs", async () => {
  const privilege = "https://www.axis.bank.in/cards/credit-card/privilege";
  const nestedTerms = `${privilege}/terms`;
  const nested = await collectSupportingBenefitDocuments({
    issuer: "Axis Bank",
    primary: resource(
      privilege,
      `<h1>Privilege Credit Card</h1><a href="${nestedTerms}">Terms</a>`,
    ),
    identityLabels: ["Privilege Credit Card"],
    fetchOfficialIssuerResource: async () =>
      resource(nestedTerms, "Generic credit card fees and terms"),
  });
  assert(
    nested.attempts.some((attempt) =>
      attempt.requestedUrl === nestedTerms &&
      attempt.errorCode === "identity_mismatch"
    ),
    "nested path was accepted without document identity",
  );

  const elite = "https://www.sbicard.com/en/personal/credit-cards/elite";
  const curated = await collectSupportingBenefitDocuments({
    issuer: "SBI Card",
    primary: resource(elite, "<h1>SBI Elite Credit Card</h1>"),
    identityLabels: ["Elite"],
    fetchOfficialIssuerResource: async (input) =>
      resource(input.url, "Generic SBI campaign terms and fees"),
  });
  assert(
    curated.attempts.some((attempt) =>
      attempt.errorCode === "identity_mismatch"
    ),
    "curated unchanged URL was accepted without document identity",
  );
});

Deno.test("supporting functional query keys are explicitly approved without persistence", async () => {
  const privilege = "https://www.axis.bank.in/cards/credit-card/privilege";
  const terms = `${privilege}/terms?document=mitc`;
  let fetchInput: Record<string, unknown> | undefined;
  const collected = await collectSupportingBenefitDocuments({
    issuer: "Axis Bank",
    primary: resource(
      privilege,
      `<h1>Privilege Credit Card</h1><a href="${terms}">MITC</a>`,
    ),
    identityLabels: ["Privilege Credit Card"],
    fetchOfficialIssuerResource: async (input) => {
      fetchInput = input as unknown as Record<string, unknown>;
      return resource(terms, "Privilege Credit Card MITC and fees");
    },
  });
  assert(
    (fetchInput?.allowedQueryParameters as string[] | undefined)?.includes(
      "document",
    ) === true,
    "linked functional query was not explicitly approved",
  );
  assert(
    collected.documents.some((document) =>
      document.finalUrl === `${privilege}/terms`
    ),
    "queryless display provenance was not retained",
  );
  assert(
    !JSON.stringify({
      finalUrls: collected.documents.map((document) => document.finalUrl),
      attempts: assessCrawlCompleteness(
        collected.attempts,
        "2026-08-17T00:01:00.000Z",
      ).attempts,
    }).includes("document=mitc"),
    "functional query value entered persisted supporting evidence",
  );
});

Deno.test("supporting crawl follows relevant official links to depth two and retains PDF provenance", async () => {
  const product = "https://www.axis.bank.in/cards/credit-card/privilege";
  const benefits = `${product}/benefits`;
  const terms = `${product}/terms-and-conditions`;
  const pdf = `${product}/mitc.pdf`;
  const rewards = `${product}/rewards`;
  const depthThree = `${product}/rewards/depth-three`;
  const primary = resource(
    product,
    `
    <h1>Privilege Credit Card</h1>
    <a href="${benefits}">Benefits</a>
    <a href="${terms}">Terms</a>
    <a href="https://evil.example/fees">Off domain</a>
    <a href="/login">Login</a>
  `,
  );
  const requested: string[] = [];
  const { documents, attempts } = await collectSupportingBenefitDocuments({
    issuer: "Axis Bank",
    primary,
    identityLabels: ["Privilege"],
    fetchOfficialIssuerResource: async (input) => {
      requested.push(input.url);
      if (input.url === benefits) {
        return resource(
          benefits,
          `<h1>Privilege Credit Card Benefits</h1><p>Get 10% cashback on dining.</p><a href="${pdf}">MITC</a>`,
        );
      }
      if (input.url === terms) {
        return resource(
          terms,
          `<h1>Privilege Credit Card Terms</h1><p>Fee waiver on annual spend.</p><a href="${rewards}">Rewards</a>`,
        );
      }
      if (input.url === pdf) {
        return resource(
          pdf,
          "%PDF-1.4\nstream\nBT (Privilege Credit Card MITC. Get 2 lounge visits per quarter.) Tj ET\nendstream\n%%EOF",
          "application/pdf",
        );
      }
      if (input.url === rewards) {
        return resource(
          rewards,
          `<h1>Privilege Credit Card Rewards</h1><p>Earn 5 points.</p><a href="${depthThree}">More rewards</a>`,
        );
      }
      if (input.url === depthThree) return resource(depthThree, "never");
      throw new Error(`unexpected URL ${input.url}`);
    },
  });

  assert(
    requested.join(",") === [terms, benefits, pdf, rewards].join(","),
    "crawl exceeded relevant depth-two links",
  );
  assert(documents.length === 5, "primary/supporting evidence was lost");
  assert(attempts.length === 5, "successful source attempts were not retained");
  const pdfDocument = documents.find((document) => document.sourceUrl === pdf);
  assert(
    pdfDocument?.text.includes("2 lounge visits per quarter"),
    "PDF text was not included",
  );
  assert(
    pdfDocument?.contentHash === "a".repeat(64),
    "PDF hash provenance was lost",
  );
});

Deno.test("primary logical identity uses submitted URL across redirects", async () => {
  const submitted =
    "https://www.axis.bank.in/cards/credit-card/privilege?variant=alpha";
  const final =
    "https://www.axis.bank.in/cards/credit-card/privilege/landing?session=secret";
  const primary = {
    ...resource(final, "<p>Get 10% cashback on dining.</p>"),
    submittedUrl: submitted,
    finalUrl: final,
    canonicalUrl: final,
  };
  const { documents, attempts } = await collectSupportingBenefitDocuments({
    issuer: "Axis Bank",
    primary,
    identityLabels: ["Privilege"],
    maximumLinks: 0,
  });

  assert(
    documents[0].sourceUrl === submitted,
    "primary redirect target replaced submitted logical identity",
  );
  assert(
    documents[0].finalUrl ===
      "https://www.axis.bank.in/cards/credit-card/privilege/landing",
    "primary redirect provenance was not retained",
  );
  assert(
    attempts[0].requestedUrl === submitted && attempts[0].finalUrl === final,
    "primary attempt did not split requested and final URLs",
  );
});

Deno.test("source extraction keeps anchor labels but never injects href secrets", async () => {
  const product = "https://www.axis.bank.in/cards/credit-card/privilege";
  const secret = "rotating-private-token";
  const supporting = `${product}/terms?session=${secret}#private`;
  const primary = resource(
    product,
    `<h1>Privilege Credit Card</h1><a href="${supporting}">Most Important Terms and Conditions</a>`,
  );
  const collected = await collectSupportingBenefitDocuments({
    issuer: "Axis Bank",
    primary,
    identityLabels: ["Privilege"],
    fetchOfficialIssuerResource: async (input) =>
      resource(
        input.url,
        `<p>Get 10% cashback on dining.</p><a href="//user:pass@www.axis.bank.in/private?token=${secret}">Private</a>`,
      ),
  });
  const persisted = assessCrawlCompleteness(
    collected.attempts,
    "2026-08-17T00:01:00.000Z",
  ).attempts;
  const serialized = JSON.stringify({
    text: collected.documents.map((document) => document.text),
    persisted,
  });
  assert(!serialized.includes(secret), "href query entered source evidence");
  assert(
    !serialized.includes("user:pass"),
    "href credentials entered source evidence",
  );
  assert(
    serialized.includes("Most Important Terms and Conditions") ||
      collected.attempts.some((attempt) =>
        attempt.role === "required_supporting"
      ),
    "safe anchor classification signal was discarded",
  );
});

Deno.test("supporting redirect identity follows requested candidate", async () => {
  const product = "https://www.axis.bank.in/cards/credit-card/privilege";
  const alpha = `${product}/offers?variant=alpha`;
  const beta = `${product}/offers?variant=beta`;
  const final = `${product}/offers/current?session=private`;
  const { documents, attempts } = await collectSupportingBenefitDocuments({
    issuer: "Axis Bank",
    identityLabels: ["Privilege"],
    primary: resource(
      product,
      `<a href="${alpha}">Benefits</a><a href="${beta}">Benefits</a>`,
    ),
    fetchOfficialIssuerResource: async (input) => ({
      ...resource(final, "Privilege Credit Card: Get 10% cashback on dining."),
      submittedUrl: input.url,
      finalUrl: final,
      canonicalUrl: final,
    }),
  });
  const supporting = documents.slice(1);
  assert(supporting.length === 2, "query-distinct redirect sources collapsed");
  assert(
    new Set(supporting.map((document) => document.sourceUrl)).size === 2,
    "supporting logical identities followed one redirect target",
  );
  assert(
    new Set(attempts.slice(1).map((attempt) => attempt.requestedUrl)).size ===
      2,
    "supporting attempts lost requested identity",
  );
});

Deno.test("supporting crawl fetches at most eight relevant links", async () => {
  const product = "https://www.axis.bank.in/cards/credit-card/privilege";
  const links = Array.from(
    { length: 10 },
    (_, index) => `${product}/benefits-${index}`,
  );
  let fetches = 0;
  const { documents, attempts } = await collectSupportingBenefitDocuments({
    issuer: "Axis Bank",
    identityLabels: ["Privilege"],
    primary: resource(
      product,
      links.map((url) => `<a href="${url}">Benefit</a>`).join(""),
    ),
    fetchOfficialIssuerResource: async (input) => {
      fetches += 1;
      return resource(
        input.url,
        `<h1>Privilege Credit Card Benefit</h1><p>Benefit ${fetches}</p>`,
      );
    },
  });

  assert(fetches === 8, "supporting fetch budget exceeded eight");
  assert(documents.length === 9, "bounded supporting documents were omitted");
  assert(attempts.length === 9, "bounded successful attempts were omitted");
});

Deno.test("a required ninth initial link outranks eight optional links", async () => {
  const product = "https://www.axis.bank.in/cards/credit-card/privilege";
  const optional = Array.from(
    { length: 8 },
    (_, index) => `${product}/benefits-${index}`,
  );
  const required = `${product}/terms-and-conditions`;
  const requested: string[] = [];
  const { attempts } = await collectSupportingBenefitDocuments({
    issuer: "Axis Bank",
    identityLabels: ["Privilege"],
    primary: resource(
      product,
      [...optional, required].map((url) => `<a href="${url}">Details</a>`)
        .join(""),
    ),
    fetchOfficialIssuerResource: async (input) => {
      requested.push(input.url);
      return resource(input.url, "Official details");
    },
  });

  assert(requested[0] === required, "required ninth link was not prioritized");
  assert(requested.includes(required), "required ninth link was omitted");
  assert(
    attempts.some((item) =>
      item.requestedUrl === required && item.role === "required_supporting"
    ),
    "required ninth link lost its necessity classification",
  );
});

Deno.test("opaque PDF remains required but incomplete without body identity", async () => {
  const product = "https://www.axis.bank.in/cards/credit-card/privilege";
  const opaque = `${product}/documents/abc123.pdf`;
  const requested: string[] = [];
  const { attempts } = await collectSupportingBenefitDocuments({
    issuer: "Axis Bank",
    identityLabels: ["Privilege"],
    primary: resource(
      product,
      `<a href="${opaque}">Most Important Terms and Conditions</a>`,
    ),
    fetchOfficialIssuerResource: async (input) => {
      requested.push(input.url);
      return resource(
        input.url,
        "%PDF-1.4\nstream\nBT (Official terms.) Tj ET\nendstream\n%%EOF",
        "application/pdf",
      );
    },
  });

  assert(requested.join(",") === opaque, "opaque MITC source was not fetched");
  assert(
    attempts.some((item) =>
      item.requestedUrl === opaque && item.role === "required_supporting" &&
      item.status === "failed" && item.errorCode === "identity_mismatch"
    ),
    "opaque MITC anchor was treated as optional",
  );
});

Deno.test("a later stronger duplicate anchor cannot downgrade required evidence", async () => {
  const product = "https://www.axis.bank.in/cards/credit-card/privilege";
  const opaque = `${product}/documents/abc123.pdf`;
  for (
    const anchors of [
      [
        `<a href="${opaque}">Benefits</a>`,
        `<a href="${opaque}">Most Important Terms and Conditions</a>`,
      ],
      [
        `<a href="${opaque}">Most Important Terms and Conditions</a>`,
        `<a href="${opaque}">Benefits</a>`,
      ],
    ]
  ) {
    const { attempts } = await collectSupportingBenefitDocuments({
      issuer: "Axis Bank",
      identityLabels: ["Privilege"],
      primary: resource(product, anchors.join("")),
      fetchOfficialIssuerResource: async () => {
        throw new Error("http_404");
      },
    });
    const supporting = attempts.find((attempt) =>
      attempt.requestedUrl === opaque
    );
    assert(
      supporting?.role === "required_supporting",
      "duplicate anchor order downgraded MITC necessity",
    );
    const assessment = assessCrawlCompleteness(
      attempts,
      "2026-08-20T00:00:00.000Z",
    );
    assert(
      !assessment.complete,
      "failed duplicate MITC source stayed complete",
    );
  }
});

Deno.test("duplicate anchor metadata is replay-stable", async () => {
  const product = "https://www.axis.bank.in/cards/credit-card/privilege";
  const opaque = `${product}/documents/abc123.pdf`;
  const collect = (html: string) =>
    collectSupportingBenefitDocuments({
      issuer: "Axis Bank",
      identityLabels: ["Privilege"],
      primary: resource(product, html),
      fetchOfficialIssuerResource: async () =>
        resource(opaque, "Official MITC"),
    });
  const forward = await collect(
    `<a href="${opaque}">Benefits</a>` +
      `<a href="${opaque}">Most Important Terms and Conditions</a>`,
  );
  const reverse = await collect(
    `<a href="${opaque}">Most Important Terms and Conditions</a>` +
      `<a href="${opaque}">Benefits</a>`,
  );
  const stable = (attempts: typeof forward.attempts) =>
    attempts.map(({ attemptedAt: _attemptedAt, ...attempt }) => attempt);
  assert(
    JSON.stringify(stable(forward.attempts)) ===
      JSON.stringify(stable(reverse.attempts)),
    "duplicate metadata order changed bounded attempt evidence",
  );
});

Deno.test("cross-page MITC discovery upgrades queued and fetched failures", async () => {
  const product = "https://www.axis.bank.in/cards/credit-card/privilege";
  const pageA = `${product}/benefits/a`;
  const pageB = `${product}/rewards/z`;
  const document = `${product}/benefits/abc123.pdf`;
  for (const alreadyFetched of [false, true]) {
    const primaryLinks = alreadyFetched
      ? `<a href="${document}">Benefits</a><a href="${pageB}">Rewards</a>`
      : `<a href="${pageA}">Benefits</a><a href="${pageB}">Rewards</a>`;
    const { attempts } = await collectSupportingBenefitDocuments({
      issuer: "Axis Bank",
      identityLabels: ["Privilege"],
      primary: resource(product, primaryLinks),
      fetchOfficialIssuerResource: async (input) => {
        if (input.url === document) throw new Error("http_404");
        if (input.url === pageA) {
          return resource(
            pageA,
            `<h1>Privilege Credit Card Benefits</h1><a href="${document}">Benefits</a>`,
          );
        }
        if (input.url === pageB) {
          return resource(
            pageB,
            `<h1>Privilege Credit Card Rewards</h1><a href="${document}">Most Important Terms and Conditions</a>`,
          );
        }
        throw new Error(`unexpected URL ${input.url}`);
      },
    });
    const documentAttempt = attempts.find((attempt) =>
      attempt.requestedUrl === document
    );
    assert(
      documentAttempt?.role === "required_supporting",
      `cross-page MITC did not upgrade ${
        alreadyFetched ? "fetched" : "queued"
      } evidence`,
    );
    assert(
      !assessCrawlCompleteness(
        attempts,
        "2026-08-20T00:00:00.000Z",
      ).complete,
      "upgraded failed MITC evidence left crawl complete",
    );
  }
});

Deno.test("collector keeps transient requested URLs and v6 persists only identities", async () => {
  const product = "https://www.axis.bank.in/cards/credit-card/privilege";
  const alpha = `${product}/terms?variant=alpha`;
  const beta = `${product}/terms?variant=beta`;
  const { documents, attempts } = await collectSupportingBenefitDocuments({
    issuer: "Axis Bank",
    identityLabels: ["Privilege"],
    primary: resource(
      product,
      `<a href="${alpha}">Terms</a><a href="${beta}">Terms</a>`,
    ),
    fetchOfficialIssuerResource: async (input) =>
      resource(
        input.url,
        `Privilege Credit Card: Get ${
          new URL(input.url).searchParams.get("variant") === "alpha" ? 10 : 20
        }% cashback on dining spends.`,
      ),
  });
  const supporting = documents.slice(1);
  assert(supporting.length === 2, "query-selected documents collapsed");
  assert(
    new Set(supporting.map((document) => document.sourceUrl)).size === 2,
    "collector collapsed transient requested URLs",
  );
  const proposals = await extractGroundedBenefitsV6(
    supporting,
    "benefits-v6",
    "card-1",
  );
  assert(
    proposals.every((proposal) =>
      /^[0-9a-f]{64}$/.test(proposal.sourceIdentity ?? "") &&
      !proposal.sourceUrl.includes("?")
    ),
    "v6 proposal exposed a query or omitted derived identity",
  );
  const persisted = assessCrawlCompleteness(
    attempts,
    "2026-08-20T00:00:00.000Z",
  ).attempts;
  assert(
    !JSON.stringify(persisted).includes("card="),
    "attempt query persisted",
  );
});

Deno.test("supporting queue preserves approved query bytes through the fetch boundary", async () => {
  const product = "https://www.axis.bank.in/cards/credit-card/privilege";
  const exact = `${product}/terms?variant=z&variant=a&document=mitc%2F2026`;
  const reordered = `${product}/terms?document=mitc%2F2026&variant=z&variant=a`;
  const requested: string[] = [];
  const collected = await collectSupportingBenefitDocuments({
    issuer: "Axis Bank",
    identityLabels: ["Privilege"],
    primary: resource(
      product,
      `<h1>Privilege Credit Card</h1><a href="${exact}">Terms</a><a href="${exact}">Duplicate Terms</a><a href="${reordered}">Terms variant</a>`,
    ),
    fetchOfficialIssuerResource: async (input) => {
      requested.push(input.url);
      return resource(input.url, "Privilege Credit Card terms and conditions");
    },
  });

  assert(
    requested.length === 2 && requested.includes(exact) &&
      requested.includes(reordered),
    `query bytes/order changed or exact duplicate was not deduped: ${
      JSON.stringify(requested)
    }`,
  );
  assert(
    collected.documents.slice(1).map((document) => document.sourceUrl)
      .every((url) => url === exact || url === reordered) &&
      collected.documents.length === 3,
    "transient source identity did not preserve distinct query resources",
  );
});

Deno.test("required terms HTML outranks an optional PDF when one fetch remains", async () => {
  const product = "https://www.axis.bank.in/cards/credit-card/privilege";
  const optionalPdf = `${product}/benefits.pdf`;
  const requiredHtml = `${product}/terms-and-conditions`;
  const requested: string[] = [];
  const { attempts } = await collectSupportingBenefitDocuments({
    issuer: "Axis Bank",
    identityLabels: ["Privilege"],
    primary: resource(
      product,
      `<a href="${optionalPdf}">Benefits</a><a href="${requiredHtml}">Terms</a>`,
    ),
    maximumLinks: 1,
    fetchOfficialIssuerResource: async (input) => {
      requested.push(input.url);
      return resource(input.url, "Official terms");
    },
  });

  assert(
    requested.join(",") === requiredHtml,
    "required HTML was not prioritized",
  );
  assert(
    attempts.some((item) =>
      item.requestedUrl === requiredHtml && item.role === "required_supporting"
    ),
    "terms HTML was not classified required",
  );
  assert(
    !attempts.some((item) =>
      item.requestedUrl === optionalPdf && item.role === "required_supporting"
    ),
    "benefits PDF was incorrectly required",
  );
});

Deno.test("budget exhaustion records every discovered required source", async () => {
  const product = "https://www.axis.bank.in/cards/credit-card/privilege";
  const required = [`${product}/mitc`, `${product}/fees-and-charges`];
  const { attempts } = await collectSupportingBenefitDocuments({
    issuer: "Axis Bank",
    identityLabels: ["Privilege"],
    primary: resource(
      product,
      required.map((url) => `<a href="${url}">Required</a>`).join(""),
    ),
    maximumLinks: 0,
  });

  for (const url of required) {
    assert(
      attempts.some((item) =>
        item.requestedUrl === url && item.role === "required_supporting" &&
        item.errorCode === "fetch_budget_exhausted"
      ),
      `budget omission was not retained for ${url}`,
    );
  }
});

Deno.test("a depth-discovered required source is retained after budget exhaustion", async () => {
  const product = "https://www.axis.bank.in/cards/credit-card/privilege";
  const benefits = `${product}/benefits`;
  const required = `${product}/terms`;
  const { attempts } = await collectSupportingBenefitDocuments({
    issuer: "Axis Bank",
    identityLabels: ["Privilege"],
    primary: resource(product, `<a href="${benefits}">Benefits</a>`),
    maximumLinks: 1,
    fetchOfficialIssuerResource: async () =>
      resource(
        benefits,
        `<h1>Privilege Credit Card Benefits</h1><a href="${required}">Terms</a>`,
      ),
  });

  assert(
    attempts.some((item) =>
      item.requestedUrl === required && item.role === "required_supporting" &&
      item.errorCode === "fetch_budget_exhausted"
    ),
    "depth-discovered required source disappeared at the budget boundary",
  );
});

Deno.test("depth-discovered required evidence displaces optional queue overflow", async () => {
  const product = "https://www.axis.bank.in/cards/credit-card/privilege";
  const optional = Array.from(
    { length: 8 },
    (_, index) => `${product}/benefits-${index}`,
  );
  const required = `${product}/fees-and-charges`;
  const { attempts } = await collectSupportingBenefitDocuments({
    issuer: "Axis Bank",
    identityLabels: ["Privilege"],
    primary: resource(
      product,
      optional.map((url) => `<a href="${url}">Benefit</a>`).join(""),
    ),
    maximumLinks: 1,
    fetchOfficialIssuerResource: async () =>
      resource(
        optional[0],
        `<h1>Privilege Credit Card Benefits</h1><a href="${required}">Fees</a>`,
      ),
  });

  assert(
    attempts.some((item) =>
      item.requestedUrl === required && item.role === "required_supporting" &&
      item.errorCode === "fetch_budget_exhausted"
    ),
    "required depth evidence was crowded out by optional links",
  );
  assert(attempts.length <= 9, "bounded source evidence overflowed");
});

Deno.test("required evidence discovered by the last optional page records overflow", async () => {
  const product = "https://www.axis.bank.in/cards/credit-card/privilege";
  const optional = Array.from(
    { length: 8 },
    (_, index) => `${product}/benefits-${index}`,
  );
  const required = `${product}/documents/late-terms`;
  const { attempts } = await collectSupportingBenefitDocuments({
    issuer: "Axis Bank",
    identityLabels: ["Privilege"],
    primary: resource(
      product,
      optional.map((url) => `<a href="${url}">Benefit</a>`).join(""),
    ),
    fetchOfficialIssuerResource: async (input) =>
      resource(
        input.url,
        input.url === optional[7]
          ? `<h1>Privilege Credit Card Benefits</h1><a href="${required}">Most Important Terms and Conditions</a>`
          : "Privilege Credit Card optional details",
      ),
  });

  assert(
    attempts.some((item) =>
      item.role === "required_supporting" &&
      item.errorCode === "required_source_overflow"
    ),
    "last-page required discovery was silently dropped",
  );
  assert(attempts.length <= 9, "overflow evidence exceeded the hard bound");
});

Deno.test("supporting crawl records required work blocked by the invocation deadline", async () => {
  const product = "https://www.axis.bank.in/cards/credit-card/privilege";
  const pdf = `${product}/terms.pdf`;
  let fetches = 0;
  const { attempts } = await collectSupportingBenefitDocuments({
    issuer: "Axis Bank",
    identityLabels: ["Privilege"],
    primary: resource(product, `<a href="${pdf}">Terms</a>`),
    requestDeadlineAt: 0,
    fetchOfficialIssuerResource: async () => {
      fetches += 1;
      return resource(pdf, "unused", "application/pdf");
    },
  });

  assert(fetches === 0, "supporting request started after the deadline");
  assert(
    attempts.some((attempt) =>
      attempt.requestedUrl === pdf && attempt.role === "required_supporting" &&
      attempt.errorCode === "deadline_exceeded"
    ),
    "deadline-blocked required source was not retained",
  );
});

Deno.test("supporting crawl rejects another card variant and counts failed attempts", async () => {
  const product = "https://www.axis.bank.in/cards/credit-card/privilege";
  const ownLinks = Array.from(
    { length: 10 },
    (_, index) => `${product}/benefits-${index}`,
  );
  const other =
    "https://www.axis.bank.in/cards/credit-card/regalia-gold/benefits";
  const requested: string[] = [];
  const { attempts } = await collectSupportingBenefitDocuments({
    issuer: "Axis Bank",
    identityLabels: ["Privilege"],
    primary: resource(
      product,
      [...ownLinks, other].map((url) => `<a href="${url}">Terms</a>`).join(""),
    ),
    fetchOfficialIssuerResource: async (input) => {
      requested.push(input.url);
      throw new Error("blocked");
    },
  });

  assert(
    requested.length === 7,
    "overflow marker did not reserve bounded attempt evidence",
  );
  assert(!requested.includes(other), "cross-card supporting link was fetched");
  assert(attempts.length === 9, "failed attempts were dropped");
  assert(
    attempts.some((attempt) =>
      attempt.errorCode === "required_source_overflow"
    ),
    "initial required overflow was not recorded",
  );
  assert(
    attempts.filter((attempt) => requested.includes(attempt.requestedUrl))
      .every(
        (attempt) =>
          attempt.status === "failed" && attempt.errorCode === "unreachable",
      ),
    "failed attempts retained unsanitized thrown errors",
  );
});

Deno.test("SBI Card ELITE receives its exact official campaign terms before generic links", async () => {
  const product =
    "https://www.sbicard.com/en/personal/credit-cards/sbi-card-elite.html";
  const campaign = "https://www.sbicard.com/en/eapply/sbicampaign.page";
  const genericTerms =
    "https://www.sbicard.com/en/most-important-terms-and-conditions.page";
  const requested: string[] = [];
  const { documents, attempts } = await collectSupportingBenefitDocuments({
    issuer: "SBI Card",
    identityLabels: ["Elite"],
    maximumLinks: 1,
    primary: resource(
      product,
      `<h1>SBI Card ELITE</h1><a href="${genericTerms}">Terms</a>`,
    ),
    fetchOfficialIssuerResource: async (input) => {
      requested.push(input.url);
      return resource(
        input.url,
        "SBI Card ELITE: Free movie tickets worth Rs. 6,000 every year. Maximum discount is Rs. 250 per ticket.",
      );
    },
  });

  assert(
    requested.join(",") === campaign,
    "the exact ELITE source did not receive the bounded supporting slot",
  );
  assert(documents.length === 2, "the ELITE campaign evidence was omitted");
  assert(
    attempts[1]?.role === "required_supporting",
    "curated required terms were not marked required",
  );
});

Deno.test("curated SBI ELITE terms do not leak to another SBI card variant", async () => {
  const product =
    "https://www.sbicard.com/en/personal/credit-cards/simplyclick-sbi-card.html";
  const requested: string[] = [];
  await collectSupportingBenefitDocuments({
    issuer: "SBI Card",
    identityLabels: ["SimplyCLICK"],
    maximumLinks: 1,
    primary: resource(product, "<h1>SimplyCLICK SBI Card</h1>"),
    fetchOfficialIssuerResource: async (input) => {
      requested.push(input.url);
      return resource(input.url, "unexpected");
    },
  });

  assert(requested.length === 0, "ELITE evidence leaked across SBI variants");
});

Deno.test("a corrupt linked PDF is retained as a required failed attempt without body text", async () => {
  const product = "https://www.axis.bank.in/cards/credit-card/privilege";
  const pdf = `${product}/terms.pdf`;
  const { documents, attempts } = await collectSupportingBenefitDocuments({
    issuer: "Axis Bank",
    identityLabels: ["Privilege"],
    primary: resource(product, `<a href="${pdf}">Terms PDF</a>`),
    fetchOfficialIssuerResource: async () =>
      resource(pdf, "not-a-pdf", "application/pdf"),
  });

  assert(documents.length === 1, "corrupt PDF became a source document");
  assert(attempts.length === 2, "corrupt PDF attempt was dropped");
  assert(attempts[1].role === "required_supporting", "PDF was optionalized");
  assert(attempts[1].status === "failed", "corrupt PDF looked successful");
  assert(attempts[1].errorCode === "corrupt_pdf", "wrong PDF failure code");
  assert(
    !Object.hasOwn(attempts[1] as object, "text") &&
      !Object.hasOwn(attempts[1] as object, "bytes"),
    "raw body material leaked into persisted attempt evidence",
  );
});
