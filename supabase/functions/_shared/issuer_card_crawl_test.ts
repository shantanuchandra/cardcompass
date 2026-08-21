import {
  classifyIssuerPage,
  discoverIssuerCardCandidates,
  MAX_CANDIDATE_FETCHES,
} from "./issuer_card_crawl.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

function resource(url: string, text: string, contentType = "text/html") {
  return {
    status: 200,
    submittedUrl: url,
    finalUrl: url,
    canonicalUrl: url,
    submittedResourceUrl: url,
    finalResourceUrl: url,
    contentType,
    bytes: new TextEncoder().encode(text),
    text,
    contentHash: "a".repeat(64),
    retrievedAt: "2026-08-19T00:00:00.000Z",
    notModified: false,
  };
}

Deno.test("issuer crawl checks the absolute deadline immediately before every request", async () => {
  const sitemap = "https://www.axis.bank.in/sitemap.xml";
  const index = "https://www.axis.bank.in/cards/credit-cards";
  const product = "https://www.axis.bank.in/cards/credit-card/privilege";

  for (const mode of ["sitemap", "fallback"] as const) {
    let now = 0;
    const requested: string[] = [];
    await discoverIssuerCardCandidates({
      issuer: "Axis Bank",
      ...(mode === "sitemap"
        ? { sitemapUrls: [sitemap] }
        : { indexUrls: [index] }),
      deadlineAt: 180,
      now: () => now,
      delay: () => {
        now = 180;
      },
      fetchOfficialIssuerResource: async (input) => {
        requested.push(input.url);
        return mode === "sitemap"
          ? resource(
            sitemap,
            `<urlset><url><loc>${product}</loc></url></urlset>`,
            "application/xml",
          )
          : resource(index, `<a href="${product}">Privilege card</a>`);
      },
    });

    assert(requested.length === 1, `${mode} detail request crossed deadline`);
    assert(
      requested[0] === (mode === "sitemap" ? sitemap : index),
      `${mode} first request changed`,
    );
  }
});

Deno.test("issuer classifications retain only validated opaque resource identities", () => {
  const submitted = "b".repeat(64);
  const final = "c".repeat(64);
  const page = classifyIssuerPage({
    issuer: "Axis Bank",
    url: "https://www.axis.bank.in/cards/credit-card/privilege?variant=gold",
    canonicalUrl: "https://www.axis.bank.in/cards/credit-card/privilege",
    html: "<h1>Privilege Credit Card</h1>",
    submittedResourceIdentityHash: submitted,
    finalResourceIdentityHash: final,
  } as never) as unknown as Record<string, unknown>;
  assert(
    page.submittedResourceIdentityHash === submitted &&
      page.finalResourceIdentityHash === final,
    "opaque fetch identities disappeared from classification",
  );
  const invalid = classifyIssuerPage({
    issuer: "Axis Bank",
    url: "https://www.axis.bank.in/cards/credit-card/privilege",
    html: "<h1>Privilege Credit Card</h1>",
    submittedResourceIdentityHash: "not-a-hash",
    finalResourceIdentityHash: "d".repeat(65),
  } as never) as unknown as Record<string, unknown>;
  assert(
    invalid.submittedResourceIdentityHash === undefined &&
      invalid.finalResourceIdentityHash === undefined,
    "invalid opaque identities entered sanitized classification",
  );
});

Deno.test("classification retains approved functional source URL identity artifacts", () => {
  const exact =
    "https://www.axis.bank.in/cards/neo?variant=gold&variant=platinum&lang=en";
  const page = classifyIssuerPage({
    issuer: "Axis Bank",
    url: exact,
    canonicalUrl: exact,
    html: "<title>Neo Credit Card | Axis Bank</title>",
    submittedUrl: exact,
    finalUrl: exact,
    submittedResourceIdentityHash: "a".repeat(64),
    finalResourceIdentityHash: "b".repeat(64),
    contentHash: "c".repeat(64),
    retrievedAt: "2026-08-19T12:00:00.000Z",
    sourceStatus: 200,
  });

  assert(
    page.submittedUrl === exact,
    "submitted functional query was stripped",
  );
  assert(page.finalUrl === exact, "final functional query was stripped");
  assert(page.contentHash === "c".repeat(64), "content hash was dropped");
  assert(
    page.retrievedAt === "2026-08-19T12:00:00.000Z",
    "retrieved time was dropped",
  );
  assert(page.sourceStatus === 200, "source status was dropped");
});

Deno.test("classification binds the primary product heading before related-card chrome", () => {
  for (
    const fixture of [
      {
        issuer: "Axis Bank",
        url:
          "https://www.axis.bank.in/cards/credit-card/indianoil-axis-bank-credit-card",
        html:
          '<title>Fuel Credit Card - Apply for Indian Oil Credit Card | Axis Bank</title><h1>IndianOil Axis Bank Credit Card</h1><section><div class="section-title">Explore Neo Credit Card and My Zone Credit Card</div></section>',
        expected: "Indian Oil",
      },
      {
        issuer: "HDFC Bank",
        url:
          "https://www.hdfc.bank.in/credit-cards/swiggy-hdfc-bank-credit-card",
        html:
          '<title>Swiggy Credit Card - Get Cashbacks on Swiggy App | HDFC Bank</title><h1>Swiggy HDFC Bank Credit Card</h1><h2 class="section-title">Other Credit Card Services</h2>',
        expected: "Swiggy",
      },
      {
        issuer: "IDFC FIRST Bank",
        url: "https://www.idfcfirst.bank.in/credit-card/wealth",
        html:
          "<title>Wealth Credit Card - Apply for Low Forex Markup Credit Card | IDFC FIRST Bank</title><h1>Lifetime-free card with premium benefits</h1>",
        expected: "Wealth",
      },
    ]
  ) {
    const page = classifyIssuerPage(fixture);
    assert(page.kind === "card_product", `${fixture.issuer} stayed ambiguous`);
    assert(
      page.proposedName === fixture.expected,
      `${fixture.issuer} primary product identity changed`,
    );
  }
});

Deno.test("issuer traversal carries exact functional fetch resources into publication evidence", async () => {
  const sitemap = "https://www.axis.bank.in/sitemap.xml";
  const exact =
    "https://www.axis.bank.in/cards/credit-card/privilege-credit-card?variant=gold&variant=platinum&lang=en";
  const display =
    "https://www.axis.bank.in/cards/credit-card/privilege-credit-card";
  const result = await discoverIssuerCardCandidates({
    issuer: "Axis Bank",
    sitemapUrls: [sitemap],
    delay: () => {},
    fetchOfficialIssuerResource: async (input) => {
      if (input.url === sitemap) {
        return resource(
          sitemap,
          `<urlset><url><loc>${
            exact.replaceAll("&", "&amp;")
          }</loc></url></urlset>`,
          "application/xml",
        );
      }
      return {
        ...resource(
          display,
          "<title>Privilege Credit Card | Axis Bank</title>",
        ),
        submittedResourceUrl: exact,
        finalResourceUrl: exact,
        sourceIdentityHash: "d".repeat(64),
        finalResourceIdentityHash: "e".repeat(64),
      };
    },
  });
  assert(result.candidates.length === 1, "query-selected product was lost");
  assert(
    result.candidates[0].submittedUrl === exact &&
      result.candidates[0].finalUrl === exact,
    "exact functional resources were replaced by display URLs",
  );
});

Deno.test("directory completeness requires every selected sitemap source to terminate positively", async () => {
  const first = "https://www.axis.bank.in/sitemap.xml";
  const second = "https://www.axis.bank.in/cards-sitemap.xml";
  const product = "https://www.axis.bank.in/cards/credit-card/neo-credit-card";
  const result = await discoverIssuerCardCandidates({
    issuer: "Axis Bank",
    sitemapUrls: [first, second],
    delay: () => {},
    fetchOfficialIssuerResource: async (input) => {
      if (input.url === second) throw new Error("timeout");
      if (input.url === first) {
        return resource(
          first,
          `<urlset><url><loc>${product}</loc></url></urlset>`,
          "application/xml",
        );
      }
      return resource(product, "<h1>Axis Neo Credit Card</h1>");
    },
  });
  assert(!result.complete, "one successful sitemap masked another failure");
  assert(
    result.incompleteReasons.includes("directory_source_fetch_failed"),
    "the failed selected source reason was not retained",
  );
});

Deno.test("an empty successful directory cannot mask a timed-out selected source", async () => {
  const first = "https://www.axis.bank.in/sitemap.xml";
  const second = "https://www.axis.bank.in/cards-sitemap.xml";
  const result = await discoverIssuerCardCandidates({
    issuer: "Axis Bank",
    sitemapUrls: [first, second],
    delay: () => {},
    fetchOfficialIssuerResource: async (input) => {
      if (input.url === second) throw new Error("timeout");
      return resource(first, "<urlset></urlset>", "application/xml");
    },
  });
  assert(!result.complete, "empty success hid a selected-source timeout");
});

Deno.test("a selected card-like candidate must classify positively for directory completeness", async () => {
  const sitemap = "https://www.axis.bank.in/sitemap.xml";
  const product = "https://www.axis.bank.in/cards/credit-card/neo-credit-card";
  const result = await discoverIssuerCardCandidates({
    issuer: "Axis Bank",
    sitemapUrls: [sitemap],
    delay: () => {},
    fetchOfficialIssuerResource: async (input) =>
      input.url === sitemap
        ? resource(
          sitemap,
          `<urlset><url><loc>${product}</loc></url></urlset>`,
          "application/xml",
        )
        : resource(product, "<h1>Compare all credit cards</h1>"),
  });
  assert(!result.complete, "quarantined candidate established completeness");
  assert(
    result.incompleteReasons.includes("candidate_not_positive"),
    "quarantined candidate reason was not retained",
  );
});

Deno.test("candidate cap overflow is explicit incomplete evidence", async () => {
  const sitemap = "https://www.axis.bank.in/sitemap.xml";
  const products = Array.from(
    { length: MAX_CANDIDATE_FETCHES + 1 },
    (_, index) =>
      `https://www.axis.bank.in/cards/credit-card/card-${index + 1}`,
  );
  const result = await discoverIssuerCardCandidates({
    issuer: "Axis Bank",
    sitemapUrls: [sitemap],
    delay: () => {},
    fetchOfficialIssuerResource: async (input) =>
      input.url === sitemap
        ? resource(
          sitemap,
          `<urlset>${
            products.map((url) => `<url><loc>${url}</loc></url>`).join("")
          }</urlset>`,
          "application/xml",
        )
        : resource(
          input.url,
          `<h1>Axis ${
            new URL(input.url).pathname.split("/").at(-1)
          } Credit Card</h1>`,
        ),
  });
  assert(!result.complete, "unattempted candidate overflow was complete");
  assert(
    result.incompleteReasons.includes("candidate_fetch_cap_exceeded"),
    "candidate cap reason was not retained",
  );
});

Deno.test("fallback completeness evaluates every selected index source", async () => {
  const first = "https://www.axis.bank.in/cards/credit-cards";
  const second = "https://www.axis.bank.in/personal/cards/credit-cards";
  const product = "https://www.axis.bank.in/cards/credit-card/neo-credit-card";
  const result = await discoverIssuerCardCandidates({
    issuer: "Axis Bank",
    indexUrls: [first, second],
    delay: () => {},
    fetchOfficialIssuerResource: async (input) => {
      if (input.url === first) {
        return resource(first, `<a href="${product}">Neo</a>`);
      }
      if (input.url === second) throw new Error("timeout");
      return resource(product, "<h1>Axis Neo Credit Card</h1>");
    },
  });
  assert(!result.complete, "one fallback index masked another partial source");
  assert(
    result.incompleteReasons.includes("directory_source_fetch_failed"),
    "fallback failure reason was not retained",
  );
});
