import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import test from "node:test";

import {
  classifyIssuerPage,
  discoverIssuerCardCandidates,
  issuerDiscoveryFallbackUrls,
  persistCrawlerCandidate,
} from "../../supabase/functions/_shared/issuer_card_crawl.ts";

const issuer = "Axis Bank";
const rootSitemap = "https://www.axis.bank.in/sitemap.xml";

function resource(url, text, contentType = "text/html") {
  return {
    status: 200,
    submittedUrl: url,
    finalUrl: url,
    canonicalUrl: url,
    contentType,
    text,
    bytes: new TextEncoder().encode(text),
    contentHash: "a".repeat(64),
    retrievedAt: "2026-08-17T00:00:00.000Z",
    notModified: false,
  };
}

function sitemap(urls, index = false) {
  const tag = index ? "sitemap" : "url";
  return `<?xml version="1.0"?><${index ? "sitemapindex" : "urlset"}>${
    urls
      .map((url) => `<${tag}><loc>${url}</loc></${tag}>`)
      .join("")
  }</${index ? "sitemapindex" : "urlset"}>`;
}

function everyReturnedString(value) {
  if (typeof value === "string") return [value];
  if (Array.isArray(value)) return value.flatMap(everyReturnedString);
  if (value && typeof value === "object") {
    return Object.values(value).flatMap(everyReturnedString);
  }
  return [];
}

test("stops every nested sitemap-index child at depth two without treating it as a product", async () => {
  const depthOne = "https://www.axis.bank.in/sitemaps/one.xml";
  const depthTwo = "https://www.axis.bank.in/sitemaps/two.xml";
  const depthThree = "https://www.axis.bank.in/sitemaps/three.xml";
  const requested = [];
  const result = await discoverIssuerCardCandidates({
    issuer,
    sitemapUrl: rootSitemap,
    fetchOfficialIssuerResource: async (input) => {
      requested.push(input.url);
      if (input.url === rootSitemap) {
        return resource(
          input.url,
          sitemap([depthOne], true),
          "application/xml",
        );
      }
      if (input.url === depthOne) {
        return resource(
          input.url,
          sitemap([depthTwo], true),
          "application/xml",
        );
      }
      if (input.url === depthTwo) {
        return resource(
          input.url,
          sitemap([depthThree], true),
          "application/xml",
        );
      }
      assert.fail(`depth-three child must not be fetched: ${input.url}`);
    },
    delay: async () => {},
  });

  assert.deepEqual(requested, [
    rootSitemap,
    depthOne,
    depthTwo,
  ]);
  assert.equal(result.consideredCount, 0);
  assert.equal(result.fetchedCount, 0);
  assert.equal(result.candidates.length, 0);
  assert.equal(result.complete, false);
  assert.ok(result.incompleteReasons.includes("sitemap_depth_exceeded"));
});

test("builds conventional same-host sitemap and credit-card index fallbacks", () => {
  assert.deepEqual(
    issuerDiscoveryFallbackUrls(
      "https://www.axis.bank.in/cards/credit-card/privilege-credit-card",
    ),
    {
      sitemapUrls: [
        "https://www.axis.bank.in/sitemap.xml",
        "https://www.axis.bank.in/sitemap_index.xml",
        "https://www.axis.bank.in/sitemap-index.xml",
        "https://www.axis.bank.in/sitemaps/sitemap.xml",
      ],
      indexUrls: [
        "https://www.axis.bank.in/cards/credit-card",
        "https://www.axis.bank.in/cards/credit-cards",
        "https://www.axis.bank.in/personal/cards/credit-cards",
      ],
    },
  );
});

test("crawler classifications never expose URL query or encoded heading credentials", () => {
  const classified = classifyIssuerPage({
    issuer,
    url:
      "https://www.axis.bank.in/cards/credit-card/privilege?session=secret#private",
    html:
      "<title>Privilege Credit Card https%253A%252F%252Fuser%253Apass%2540www.axis.bank.in%252Fcard%253Ftoken%253Dsecret</title>",
  });
  const serialized = JSON.stringify(classified);
  assert.equal(
    classified.canonicalUrl,
    "https://www.axis.bank.in/cards/credit-card/privilege",
  );
  assert.doesNotMatch(serialized, /session|secret|user|pass|token|private/i);
});

test("falls back from unavailable sitemaps to same-host credit-card indexes", async () => {
  const product =
    "https://www.axis.bank.in/cards/credit-card/select-credit-card";
  const seeds = issuerDiscoveryFallbackUrls(product);
  const requested = [];
  const result = await discoverIssuerCardCandidates({
    issuer,
    sitemapUrls: seeds.sitemapUrls,
    indexUrls: seeds.indexUrls,
    fetchOfficialIssuerResource: async (input) => {
      requested.push(input.url);
      if (seeds.sitemapUrls.includes(input.url)) throw new Error("unreachable");
      if (input.url === seeds.indexUrls[0]) {
        return resource(input.url, `<a href="${product}">Select card</a>`);
      }
      if (input.url === product) {
        return resource(input.url, "<h1>Axis Select Credit Card</h1>");
      }
      throw new Error("unused fallback");
    },
    delay: async () => {},
  });

  assert.equal(result.candidates[0]?.proposedName, "Select");
  assert.equal(result.fetchedCount, 1);
  assert.deepEqual(requested, [
    ...seeds.sitemapUrls,
    ...seeds.indexUrls,
    product,
  ]);
  assert.equal(result.complete, false);
});

test("caps sitemap URLs at 200 and candidate page requests at 40", async () => {
  const urls = Array.from(
    { length: 201 },
    (_, index) =>
      `https://www.axis.bank.in/cards/credit-card/card-${index + 1}`,
  );
  const requested = [];
  const result = await discoverIssuerCardCandidates({
    issuer,
    sitemapUrl: rootSitemap,
    fetchOfficialIssuerResource: async (input) => {
      requested.push(input.url);
      if (input.url === rootSitemap) {
        return resource(input.url, sitemap(urls), "application/xml");
      }
      return resource(
        input.url,
        `<h1>Axis Card ${input.url.match(/card-\d+/)?.[0]}</h1>`,
      );
    },
    delay: async () => {},
  });

  assert.equal(result.consideredCount, 200);
  assert.equal(result.fetchedCount, 40);
  assert.equal(requested.length, 41);
  assert.equal(requested.at(-1), urls[39]);
});

test("never fetches more than 200 sitemap documents from a sitemap index", async () => {
  const nested = Array.from(
    { length: 201 },
    (_, index) => `https://www.axis.bank.in/sitemaps/cards-${index + 1}.xml`,
  );
  const requested = [];
  await discoverIssuerCardCandidates({
    issuer,
    sitemapUrl: rootSitemap,
    fetchOfficialIssuerResource: async (input) => {
      requested.push(input.url);
      return resource(
        input.url,
        input.url === rootSitemap ? sitemap(nested, true) : sitemap([]),
        "application/xml",
      );
    },
    delay: async () => {},
  });

  assert.equal(requested.length, 200);
  assert.equal(requested.at(-1), nested[198]);
});

test("caps caller-provided sitemap roots at 200 too", async () => {
  const roots = Array.from(
    { length: 201 },
    (_, index) => `https://www.axis.bank.in/sitemaps/root-${index + 1}.xml`,
  );
  const requested = [];
  await discoverIssuerCardCandidates({
    issuer,
    sitemapUrls: roots,
    fetchOfficialIssuerResource: async (input) => {
      requested.push(input.url);
      return resource(input.url, sitemap([]), "application/xml");
    },
    delay: async () => {},
  });

  assert.equal(requested.length, 200);
  assert.equal(requested.at(-1), roots[199]);
});

test("canonical duplicates collapse and all injected requests and delays are sequential", async () => {
  const first =
    "https://www.axis.bank.in/cards/credit-card/privilege-credit-card?utm_source=mail";
  const duplicate =
    "https://www.axis.bank.in/cards//credit-card/privilege-credit-card/#details";
  const second =
    "https://www.axis.bank.in/cards/credit-card/select-credit-card";
  let active = 0;
  let maxActive = 0;
  const order = [];
  const result = await discoverIssuerCardCandidates({
    issuer,
    sitemapUrl: rootSitemap,
    fetchOfficialIssuerResource: async (input) => {
      active += 1;
      maxActive = Math.max(maxActive, active);
      order.push(`fetch:${input.url}`);
      await Promise.resolve();
      active -= 1;
      if (input.url === rootSitemap) {
        return resource(
          input.url,
          sitemap([first, duplicate, second]),
          "application/xml",
        );
      }
      return resource(input.url, "<h1>Axis Credit Card</h1>");
    },
    delay: async () => {
      assert.equal(active, 0);
      order.push("delay");
    },
  });

  assert.equal(maxActive, 1);
  assert.equal(result.consideredCount, 2);
  assert.equal(result.fetchedCount, 2);
  assert.deepEqual(order, [
    `fetch:${rootSitemap}`,
    "delay",
    "fetch:https://www.axis.bank.in/cards/credit-card/privilege-credit-card",
    "delay",
    `fetch:${second}`,
  ]);
});

test("scores product, benefit, fee, rewards, terms, and MITC pages positively", () => {
  const positives = [
    [
      "https://www.axis.bank.in/cards/credit-card/privilege-credit-card",
      "card_product",
    ],
    [
      "https://www.axis.bank.in/cards/privilege/benefits",
      "supporting_document",
    ],
    [
      "https://www.axis.bank.in/cards/privilege/fees-and-charges",
      "supporting_document",
    ],
    ["https://www.axis.bank.in/cards/privilege/rewards", "supporting_document"],
    [
      "https://www.axis.bank.in/cards/privilege/terms-and-conditions",
      "supporting_document",
    ],
    [
      "https://www.axis.bank.in/cards/privilege/mitc.pdf",
      "supporting_document",
    ],
  ];

  for (const [url, kind] of positives) {
    const page = classifyIssuerPage({
      issuer,
      url,
      html: "<h1>Axis Privilege Credit Card</h1>",
    });
    assert.equal(page.kind, kind, url);
    assert.ok(page.confidence >= 0.7, url);
  }
});

test("quarantines known invalid Axis, HDFC, Kotak, and generic PNB pages without retaining sensitive evidence", () => {
  const invalids = [
    ["Axis Bank", "https://www.axis.bank.in/login"],
    [
      "HDFC Bank",
      "https://www.hdfcbank.com/personal/resources/learning-centre",
    ],
    [
      "Kotak Bank",
      "https://www.kotak.com/en/digital-banking/net-banking/login.html",
    ],
    [
      "Punjab National Bank",
      "https://www.pnbcard.in/types5.html?tracking=1234567890123456",
    ],
    ["Punjab National Bank", "https://www.pnbindia.in/protection.html"],
  ];

  for (const [pageIssuer, url] of invalids) {
    const page = classifyIssuerPage({
      issuer: pageIssuer,
      url,
      html: "<title>Generic account help 1234567890123456</title>",
    });
    assert.ok(["not_a_card", "ambiguous"].includes(page.kind), url);
    assert.ok(page.warnings.length > 0, url);
    assert.ok(
      page.sanitizedEvidence.every((value) => !/\d{4,}/.test(value)),
      url,
    );
    assert.ok(
      page.sanitizedEvidence.every((value) => value.length <= 300),
      url,
    );
  }
});

test("quarantines calculator URLs even when their headings contain credit-card product signals", async () => {
  const calculator =
    "https://www.axis.bank.in/calculators/balance-on-emi-credit-card-calculator";
  const requested = [];
  const result = await discoverIssuerCardCandidates({
    issuer,
    sitemapUrl: rootSitemap,
    fetchOfficialIssuerResource: async (input) => {
      requested.push(input.url);
      if (input.url === rootSitemap) {
        return resource(input.url, sitemap([calculator]), "application/xml");
      }
      return resource(
        input.url,
        "<title>Balance on EMI Credit Card Calculator</title><h1>Axis Bank Credit Card Calculator</h1>",
      );
    },
    delay: async () => {},
  });

  assert.equal(result.consideredCount, 1);
  assert.equal(result.fetchedCount, 0);
  assert.equal(result.candidates.length, 0);
  assert.equal(result.quarantined[0]?.kind, "not_a_card");
  assert.deepEqual(requested, [rootSitemap]);
});

test("redacts long digit sequences from every returned result string", async () => {
  const product =
    "https://www.axis.bank.in/cards/credit-card/privilege-credit-card?account=1234567890123456";
  const result = await discoverIssuerCardCandidates({
    issuer,
    sitemapUrl: rootSitemap,
    fetchOfficialIssuerResource: async (input) => {
      if (input.url === rootSitemap) {
        return resource(input.url, sitemap([product]), "application/xml");
      }
      return resource(
        input.url,
        "<h1>Axis Privilege 9876543210987654 Credit Card</h1><title>Member 1234567890123456</title>",
      );
    },
    delay: async () => {},
  });

  for (const value of everyReturnedString(result)) {
    assert.doesNotMatch(value, /\d{4,}/, value);
  }
});

test("ranks positives before the 40 fetch cap and quarantines hard-negative links without fetching them", async () => {
  const negatives = Array.from(
    { length: 40 },
    (_, index) =>
      `https://www.axis.bank.in/login?tracking=${index + 1000000000000000}`,
  );
  const product =
    "https://www.axis.bank.in/cards/credit-card/privilege-credit-card";
  const requested = [];
  const result = await discoverIssuerCardCandidates({
    issuer,
    sitemapUrl: rootSitemap,
    fetchOfficialIssuerResource: async (input) => {
      requested.push(input.url);
      if (input.url === rootSitemap) {
        return resource(
          input.url,
          sitemap([...negatives, product]),
          "application/xml",
        );
      }
      assert.equal(input.url, product);
      return resource(input.url, "<h1>Axis Privilege Credit Card</h1>");
    },
    delay: async () => {},
  });

  assert.equal(result.consideredCount, 41);
  assert.equal(result.fetchedCount, 1);
  assert.equal(result.candidates[0]?.canonicalUrl, product);
  assert.equal(result.quarantined.length, 40);
  assert.deepEqual(requested, [rootSitemap, product]);
});

test("anchors sitemap-index children and returned directory URLs to the initial approved hostname", async () => {
  const crossHostSitemap = "https://www.axisbank.com/sitemap.xml";
  const crossHostCandidate =
    "https://www.axisbank.com/cards/credit-card/privilege-credit-card";
  const localProduct =
    "https://www.axis.bank.in/cards/credit-card/select-credit-card";
  const requested = [];
  const result = await discoverIssuerCardCandidates({
    issuer,
    sitemapUrl: rootSitemap,
    fetchOfficialIssuerResource: async (input) => {
      requested.push(input.url);
      if (input.url === rootSitemap) {
        return resource(
          input.url,
          sitemap([crossHostSitemap, crossHostCandidate, localProduct], true),
          "application/xml",
        );
      }
      assert.equal(input.url, localProduct);
      return {
        ...resource(input.url, "<h1>Axis Select Credit Card</h1>"),
        finalUrl: crossHostCandidate,
        canonicalUrl: crossHostCandidate,
      };
    },
    delay: async () => {},
  });

  assert.deepEqual(requested, [rootSitemap, localProduct]);
  assert.equal(result.candidates.length, 0);
  assert.equal(result.quarantined.length, 0);
  assert.equal(result.complete, false);
  assert.ok(result.incompleteReasons.includes("directory_source_cross_host"));
});

test("same-host candidate redirects stay bound to the discovered card identity", async () => {
  const privilege =
    "https://www.axis.bank.in/cards/credit-card/privilege-credit-card";
  const regalia =
    "https://www.axis.bank.in/cards/credit-card/regalia-credit-card";
  for (
    const [finalUrl, body, accepted] of [
      [
        `${privilege}/benefits`,
        "<h1>Privilege Credit Card Benefits</h1>",
        true,
      ],
      [regalia, "<h1>Regalia Credit Card</h1>", false],
      [
        "https://www.axis.bank.in/cards/credit-card",
        "<h1>Credit Cards</h1>",
        false,
      ],
    ]
  ) {
    const result = await discoverIssuerCardCandidates({
      issuer,
      sitemapUrl: rootSitemap,
      fetchOfficialIssuerResource: async (input) =>
        input.url === rootSitemap
          ? resource(input.url, sitemap([privilege]), "application/xml")
          : { ...resource(finalUrl, body), submittedUrl: privilege },
      delay: async () => {},
    });
    assert.equal(
      result.candidates.length > 0,
      accepted,
      `redirect identity binding failed for ${finalUrl}`,
    );
    if (!accepted) {
      assert.equal(
        result.quarantined[0]?.warnings.includes("redirect_identity_mismatch"),
        true,
      );
    }
  }
});

test("candidate body identity must match the requested product even when the URL is unchanged", async () => {
  const privilege =
    "https://www.axis.bank.in/cards/credit-card/privilege-credit-card";
  const result = await discoverIssuerCardCandidates({
    issuer,
    sitemapUrl: rootSitemap,
    fetchOfficialIssuerResource: async (input) =>
      input.url === rootSitemap
        ? resource(input.url, sitemap([privilege]), "application/xml")
        : resource(
          privilege,
          "<title>Privilege Credit Card | Axis Bank</title><h1>Regalia Gold Credit Card</h1>",
        ),
    delay: async () => {},
  });
  assert.equal(result.candidates.length, 0);
  assert.equal(
    result.quarantined.some((item) =>
      item.warnings.includes("redirect_identity_mismatch")
    ),
    true,
  );
});

test("issuer crawl approves linked functional query names and enforces delay deadlines before sleep", async () => {
  const terms =
    "https://www.axis.bank.in/cards/credit-card/privilege/terms?document=mitc";
  const received = [];
  let now = 500;
  let sleeps = 0;
  const result = await discoverIssuerCardCandidates({
    issuer,
    sitemapUrl: rootSitemap,
    deadlineAt: 1_000,
    now: () => now,
    delayMs: 1_000,
    delay: async (milliseconds) => {
      sleeps += 1;
      now += milliseconds;
    },
    fetchOfficialIssuerResource: async (input) => {
      received.push(input);
      if (input.url === rootSitemap) {
        return resource(input.url, sitemap([terms]), "application/xml");
      }
      return resource(terms, "<h1>Privilege Credit Card Terms</h1>");
    },
  });
  assert.equal(sleeps, 0);
  assert.equal(received.length, 1);
  assert.equal(result.candidates.length, 0);

  const queryInputs = [];
  await discoverIssuerCardCandidates({
    issuer,
    sitemapUrl: rootSitemap,
    delay: async () => {},
    fetchOfficialIssuerResource: async (input) => {
      queryInputs.push(input);
      return input.url === rootSitemap
        ? resource(input.url, sitemap([terms]), "application/xml")
        : resource(terms, "<h1>Privilege Credit Card Terms</h1>");
    },
  });
  assert.equal(
    queryInputs[1].allowedQueryParameters.includes("document"),
    true,
  );
  assert.equal(queryInputs[0].robotsCache, queryInputs[1].robotsCache);
});

test("issuer crawl preserves approved sitemap query bytes through the request boundary", async () => {
  const exact =
    "https://www.axis.bank.in/cards/credit-card/privilege/terms?variant=z&variant=a&document=mitc%2F2026";
  const requested = [];
  await discoverIssuerCardCandidates({
    issuer,
    sitemapUrl: rootSitemap,
    delay: async () => {},
    fetchOfficialIssuerResource: async (input) => {
      requested.push(input.url);
      return input.url === rootSitemap
        ? resource(input.url, sitemap([exact]), "application/xml")
        : resource(input.url, "<h1>Privilege Credit Card Terms</h1>");
    },
  });

  assert.deepEqual(requested, [rootSitemap, exact]);
});

test("issuer index discovery quarantines unknown query resources without fetching a different URL", async () => {
  const index = "https://www.axis.bank.in/credit-cards";
  const unsafe =
    "https://www.axis.bank.in/cards/credit-card/privilege?session=private";
  const requested = [];
  const result = await discoverIssuerCardCandidates({
    issuer,
    sitemapUrl: rootSitemap,
    indexUrls: [index],
    delay: async () => {},
    fetchOfficialIssuerResource: async (input) => {
      requested.push(input.url);
      if (input.url === rootSitemap) throw new Error("missing sitemap");
      if (input.url === index) {
        return resource(input.url, `<a href="${unsafe}">Privilege card</a>`);
      }
      assert.fail(`unsafe query resource was fetched: ${input.url}`);
    },
  });

  assert.deepEqual(requested, [rootSitemap, index]);
  assert.equal(result.consideredCount, 1);
  assert.equal(
    result.quarantined.some((item) =>
      item.warnings.includes("unapproved_query")
    ),
    true,
  );
});

test("requires product-specific identity context before classifying generic listings or sitewide documents positively", () => {
  const genericListing = classifyIssuerPage({
    issuer,
    url: "https://www.axis.bank.in/cards/credit-cards",
    html: "<h1>Credit Cards</h1>",
  });
  const sitewideTerms = classifyIssuerPage({
    issuer,
    url: "https://www.axis.bank.in/terms-and-conditions",
    html: "<h1>Terms and Conditions</h1>",
  });

  assert.equal(genericListing.kind, "ambiguous");
  assert.equal(sitewideTerms.kind, "ambiguous");
});

test("rejects generic navigation and legal pages whose headings merely mention credit cards", () => {
  const genericPages = [
    [
      "https://www.axis.bank.in/cards/credit-card/all",
      "<h1>Compare Credit Card Options</h1>",
    ],
    [
      "https://www.axis.bank.in/cards/credit-card/overview",
      "<h1>Explore Our Credit Card Range</h1>",
    ],
    [
      "https://www.axis.bank.in/legal/terms-and-conditions",
      "<h1>Axis Bank Credit Card Terms and Conditions</h1>",
    ],
  ];

  for (const [url, html] of genericPages) {
    const page = classifyIssuerPage({ issuer, url, html });
    assert.equal(page.kind, "ambiguous", url);
  }
});

test("keeps a real product when it contains generic card words alongside a meaningful shared token", () => {
  const page = classifyIssuerPage({
    issuer,
    url: "https://www.axis.bank.in/cards/credit-card/select-credit-card",
    html: "<h1>Axis Select Credit Card</h1>",
  });

  assert.equal(page.kind, "card_product");
  assert.equal(page.proposedName, "Select");
});

test("does not self-validate generic identities using their own heading tokens", () => {
  const genericPages = [
    [
      "https://www.axis.bank.in/cards/credit-card/all",
      "<h1>Find the Right Credit Card</h1>",
    ],
    [
      "https://www.axis.bank.in/cards/credit-card/overview",
      "<h1>Best Credit Card Offers</h1>",
    ],
    [
      "https://www.axis.bank.in/legal/fees-and-charges",
      "<h1>Credit Card Fees and Charges Guide</h1>",
    ],
  ];

  for (const [url, html] of genericPages) {
    assert.equal(
      classifyIssuerPage({ issuer, url, html }).kind,
      "ambiguous",
      url,
    );
  }
});

test("matches meaningful identity tokens only against real product URL paths", () => {
  const pages = [
    [
      "https://www.axis.bank.in/cards/credit-card/select-credit-card",
      "<h1>Axis Select Credit Card</h1>",
      "card_product",
    ],
    [
      "https://www.axis.bank.in/cards/credit-card/flipkart-axis-bank-credit-card",
      "<h1>Flipkart Axis Bank Credit Card</h1>",
      "card_product",
    ],
    [
      "https://www.axis.bank.in/cards/privilege/benefits",
      "<h1>Axis Privilege Credit Card</h1>",
      "supporting_document",
    ],
  ];

  for (const [url, html, kind] of pages) {
    assert.equal(classifyIssuerPage({ issuer, url, html }).kind, kind, url);
  }
});

test("classifies pilot product pages that expose identity only in an ordinary title", () => {
  const pages = [
    [
      "Axis Bank",
      "https://www.axis.bank.in/cards/credit-card/privilege-credit-card",
      "<title>Privilege Credit Card with Unlimited Benefits | Axis Bank</title>",
    ],
    [
      "Kotak Bank",
      "https://www.kotak.com/en/personal-banking/cards/credit-cards/white-reserve-credit-card.html",
      "<title>White Reserve Credit Card | Kotak</title>",
    ],
  ];

  for (const [pageIssuer, url, html] of pages) {
    assert.equal(
      classifyIssuerPage({ issuer: pageIssuer, url, html }).kind,
      "card_product",
      url,
    );
  }
});

test("does not match a title marketing suffix against an unrelated product URL token", () => {
  const html =
    "<title>Privilege Credit Card with Unlimited Benefits | Axis Bank</title>";
  const marketingPath = classifyIssuerPage({
    issuer,
    url: "https://www.axis.bank.in/cards/credit-card/unlimited-benefits",
    html,
  });
  const productPath = classifyIssuerPage({
    issuer,
    url: "https://www.axis.bank.in/cards/credit-card/privilege-credit-card",
    html,
  });

  assert.equal(marketingPath.kind, "ambiguous");
  assert.equal(productPath.kind, "card_product");
  assert.equal(productPath.proposedName, "Privilege");
});

test("uses authoritative title metadata over navigation tiles while URL context rejects generic titles", () => {
  const liveHtml = `
    <div class="title">E-Debit Card</div>
    <title>Apply for PRIVILEGE Credit Card with unlimited benefits | Axis Bank</title>
    <h1>PRIVILEGE Credit Card</h1>
  `;
  const product = classifyIssuerPage({
    issuer,
    url: "https://www.axis.bank.in/cards/credit-card/privilege-credit-card",
    html: liveHtml,
  });
  const generic = classifyIssuerPage({
    issuer,
    url: "https://www.axis.bank.in/cards/credit-card/all",
    html: "<title>Compare Credit Card Options | Axis Bank</title>",
  });

  assert.equal(product.kind, "card_product");
  assert.equal(product.proposedName, "Privilege");
  assert.equal(generic.kind, "ambiguous");
});

test("falls back from issuer service-portal metadata to a product h1", () => {
  const page = classifyIssuerPage({
    issuer,
    url: "https://www.axis.bank.in/cards/credit-card/privilege-credit-card",
    html: `
      <title>Axis Bank Credit Card Services Portal</title>
      <h1>Axis Privilege Credit Card</h1>
    `,
  });

  assert.equal(page.kind, "card_product");
  assert.equal(page.proposedName, "Privilege");
});

test("passes a nonzero production default delay to an injected delay function", async () => {
  const delays = [];
  await discoverIssuerCardCandidates({
    issuer,
    sitemapUrl: rootSitemap,
    fetchOfficialIssuerResource: async (input) =>
      input.url === rootSitemap
        ? resource(
          input.url,
          sitemap([
            "https://www.axis.bank.in/cards/credit-card/privilege-credit-card",
          ]),
          "application/xml",
        )
        : resource(input.url, "<h1>Axis Privilege Credit Card</h1>"),
    delay: async (milliseconds) => delays.push(milliseconds),
  });

  assert.equal(delays.length, 1);
  assert.ok(delays[0] > 0);
});

test("a rejected nested sitemap child makes the directory observation incomplete", async () => {
  const rejectedChild =
    "https://www.axis.bank.in/sitemap.xml?session=not-approved";
  const result = await discoverIssuerCardCandidates({
    issuer,
    sitemapUrl: rootSitemap,
    fetchOfficialIssuerResource: async (input) => {
      assert.equal(input.url, rootSitemap);
      return resource(
        input.url,
        sitemap([rejectedChild], true),
        "application/xml",
      );
    },
    delay: async () => {},
  });

  assert.equal(result.complete, false);
  assert.ok(result.incompleteReasons.includes("directory_source_invalid"));
});

test("only wholly positive directory sources allow an empty inventory to be complete", async () => {
  const productDirectory =
    "https://www.axis.bank.in/cards/credit-card/sitemap.xml";
  const secondRoot = "https://www.axis.bank.in/sitemap-cards.xml";
  const empty = await discoverIssuerCardCandidates({
    issuer,
    sitemapUrl: productDirectory,
    fetchOfficialIssuerResource: async (input) =>
      resource(input.url, sitemap([]), "application/xml"),
    delay: async () => {},
  });
  assert.equal(empty.complete, true);
  assert.equal(empty.consideredCount, 0);

  const partial = await discoverIssuerCardCandidates({
    issuer,
    sitemapUrls: [productDirectory, secondRoot],
    fetchOfficialIssuerResource: async (input) => {
      if (input.url === secondRoot) throw new Error("timeout");
      return resource(input.url, sitemap([]), "application/xml");
    },
    delay: async () => {},
  });
  assert.equal(partial.complete, false);
  assert.ok(
    partial.incompleteReasons.includes("directory_source_fetch_failed"),
  );
});

test("supporting-document-only listings persist evidence but cannot prove product inventory", async () => {
  const productDirectory =
    "https://www.axis.bank.in/cards/credit-card/sitemap.xml";
  const terms =
    "https://www.axis.bank.in/cards/credit-card/privilege/terms-and-conditions";
  const outcomes = [];
  const result = await discoverIssuerCardCandidates({
    issuer,
    sitemapUrl: productDirectory,
    fetchOfficialIssuerResource: async (input) =>
      input.url === productDirectory
        ? resource(input.url, sitemap([terms]), "application/xml")
        : resource(
          input.url,
          "<h1>Axis Privilege Credit Card Terms and Conditions</h1>",
        ),
    delay: async () => {},
    onCandidateOutcome: async (outcome) => outcomes.push(outcome),
  });

  assert.equal(outcomes.length, 1);
  assert.equal(outcomes[0].classification.kind, "supporting_document");
  assert.equal(result.candidates[0].kind, "supporting_document");
  assert.equal(result.complete, false);
  assert.ok(result.incompleteReasons.includes("product_inventory_unproven"));
});

test("a mixed product and supporting document inventory remains complete", async () => {
  const productDirectory =
    "https://www.axis.bank.in/cards/credit-card/sitemap.xml";
  const product =
    "https://www.axis.bank.in/cards/credit-card/privilege-credit-card";
  const terms =
    "https://www.axis.bank.in/cards/credit-card/privilege/terms-and-conditions";
  const result = await discoverIssuerCardCandidates({
    issuer,
    sitemapUrl: productDirectory,
    fetchOfficialIssuerResource: async (input) => {
      if (input.url === productDirectory) {
        return resource(
          input.url,
          sitemap([product, terms]),
          "application/xml",
        );
      }
      return resource(
        input.url,
        input.url === product
          ? "<h1>Axis Privilege Credit Card</h1>"
          : "<h1>Axis Privilege Credit Card Terms and Conditions</h1>",
      );
    },
    delay: async () => {},
  });

  assert.deepEqual(
    result.candidates.map((candidate) => candidate.kind).sort(),
    ["card_product", "supporting_document"],
  );
  assert.equal(result.complete, true);
});

test("only an explicitly product-scoped empty source proves empty inventory", async () => {
  const productDirectory =
    "https://www.axis.bank.in/cards/credit-card/sitemap.xml";
  const fetchOfficialIssuerResource = async (input) =>
    resource(input.url, sitemap([]), "application/xml");
  const generic = await discoverIssuerCardCandidates({
    issuer,
    sitemapUrl: rootSitemap,
    fetchOfficialIssuerResource,
    delay: async () => {},
  });
  const explicit = await discoverIssuerCardCandidates({
    issuer,
    sitemapUrl: productDirectory,
    fetchOfficialIssuerResource,
    delay: async () => {},
  });

  assert.equal(generic.complete, false);
  assert.ok(generic.incompleteReasons.includes("product_inventory_unproven"));
  assert.equal(explicit.complete, true);
  assert.deepEqual(explicit.incompleteReasons, []);
});

test("a malformed nested sitemap prevents directory absence review", async () => {
  const child = "https://www.axis.bank.in/sitemaps/cards.xml";
  const result = await discoverIssuerCardCandidates({
    issuer,
    sitemapUrl: rootSitemap,
    fetchOfficialIssuerResource: async (input) =>
      input.url === rootSitemap
        ? resource(input.url, sitemap([child], true), "application/xml")
        : resource(input.url, "<urlset><url>", "application/xml"),
    delay: async () => {},
  });
  assert.equal(result.complete, false);
  assert.ok(result.incompleteReasons.includes("directory_source_malformed"));
});

test("every sitemap-index child is parsed as a directory source even without a sitemap-looking path", async () => {
  const child = "https://www.axis.bank.in/directory-feed";
  const purposes = [];
  const result = await discoverIssuerCardCandidates({
    issuer,
    sitemapUrl: rootSitemap,
    fetchOfficialIssuerResource: async (input) => {
      purposes.push([input.url, input.contentPurpose]);
      return input.url === rootSitemap
        ? resource(input.url, sitemap([child], true), "application/xml")
        : resource(input.url, "<directory>truncated", "application/xml");
    },
    delay: async () => {},
  });
  assert.deepEqual(purposes, [
    [rootSitemap, "sitemap"],
    [child, "sitemap"],
  ]);
  assert.equal(result.complete, false);
  assert.ok(result.incompleteReasons.includes("directory_source_malformed"));
});

test("candidate outcomes finish persisting before the next candidate fetch starts", async () => {
  const first =
    "https://www.axis.bank.in/cards/credit-card/privilege-credit-card";
  const second =
    "https://www.axis.bank.in/cards/credit-card/select-credit-card";
  const events = [];
  let firstPersisted = false;
  const result = await discoverIssuerCardCandidates({
    issuer,
    sitemapUrl: rootSitemap,
    fetchOfficialIssuerResource: async (input) => {
      events.push(`fetch:${input.url}`);
      if (input.url === rootSitemap) {
        return resource(input.url, sitemap([first, second]), "application/xml");
      }
      if (input.url === second) {
        assert.equal(
          firstPersisted,
          true,
          "second fetch started before the first outcome was durable",
        );
      }
      return resource(
        input.url,
        `<h1>Axis ${
          input.url === first ? "Privilege" : "Select"
        } Credit Card</h1>`,
      );
    },
    delay: async () => {},
    onCandidateOutcome: async (outcome) => {
      events.push(`persist:${outcome.classification.proposedName}`);
      await Promise.resolve();
      if (outcome.classification.proposedName === "Privilege") {
        firstPersisted = true;
      }
    },
  });

  assert.equal(result.complete, true);
  assert.deepEqual(events, [
    `fetch:${rootSitemap}`,
    `fetch:${first}`,
    "persist:Privilege",
    `fetch:${second}`,
    "persist:Select",
  ]);
});

test("deadline exhaustion stops before another network request and leaves resumable work incomplete", async () => {
  const first =
    "https://www.axis.bank.in/cards/credit-card/privilege-credit-card";
  const second =
    "https://www.axis.bank.in/cards/credit-card/select-credit-card";
  const requested = [];
  let now = 100;
  const result = await discoverIssuerCardCandidates({
    issuer,
    sitemapUrl: rootSitemap,
    deadlineAt: 1_000,
    now: () => now,
    fetchOfficialIssuerResource: async (input) => {
      requested.push(input.url);
      if (input.url === rootSitemap) {
        return resource(input.url, sitemap([first, second]), "application/xml");
      }
      assert.equal(input.url, first);
      return resource(input.url, "<h1>Axis Privilege Credit Card</h1>");
    },
    delay: async () => {},
    onCandidateOutcome: async () => {
      now = 1_000;
    },
  });

  assert.deepEqual(requested, [rootSitemap, first]);
  assert.equal(result.budgetExhausted, true);
  assert.equal(result.complete, false);
  assert.ok(result.incompleteReasons.includes("candidate_unattempted"));
});

test("a deadline raised by an in-flight candidate fetch persists that attempted outcome", async () => {
  const product =
    "https://www.axis.bank.in/cards/credit-card/privilege-credit-card";
  const outcomes = [];
  const result = await discoverIssuerCardCandidates({
    issuer,
    sitemapUrl: rootSitemap,
    deadlineAt: 1_000,
    now: () => 100,
    fetchOfficialIssuerResource: async (input) => {
      if (input.url === rootSitemap) {
        return resource(input.url, sitemap([product]), "application/xml");
      }
      throw new Error("deadline_exceeded");
    },
    delay: async () => {},
    onCandidateOutcome: async (outcome) => outcomes.push(outcome),
  });

  assert.equal(result.budgetExhausted, true);
  assert.equal(result.fetchedCount, 1);
  assert.equal(outcomes.length, 1);
  assert.equal(outcomes[0].attempted, true);
  assert.ok(
    outcomes[0].classification.warnings.includes("candidate_fetch_failed"),
  );
});

test("bounded persisted outcome keys resume beyond one 40-request candidate budget", async () => {
  const urls = Array.from(
    { length: 81 },
    (_, index) => `https://www.axis.bank.in/cards/credit-card/product-${index}`,
  );
  const completedCandidateOutcomes = urls.slice(0, 80).map((url, index) => ({
    candidateKey: createHash("sha256").update(url).digest("hex"),
    disposition: "candidate",
    attempted: true,
    classification: {
      kind: "card_product",
      canonicalUrl: url,
      proposedName: `Product ${index}`,
      aliases: [`Axis Product ${index} Credit Card`],
      confidence: 0.95,
      warnings: [],
      sanitizedEvidence: [`Axis Product ${index} Credit Card`],
    },
  }));
  const requested = [];
  const result = await discoverIssuerCardCandidates({
    issuer,
    sitemapUrl: rootSitemap,
    completedCandidateOutcomes,
    fetchOfficialIssuerResource: async (input) => {
      requested.push(input.url);
      return input.url === rootSitemap
        ? resource(input.url, sitemap(urls), "application/xml")
        : resource(input.url, "<h1>Axis Product 80 Credit Card</h1>");
    },
    delay: async () => {},
  });

  assert.deepEqual(requested, [rootSitemap, urls[80]]);
  assert.equal(result.resumedCount, 80);
  assert.equal(result.fetchedCount, 1);
  assert.equal(result.candidates.length, 81);
  assert.equal(result.complete, true);
});

test("resume skips a previously persisted rejected candidate without writing it again", async () => {
  const rejected =
    "https://www.axis.bank.in/cards/credit-card/eligibility-calculator";
  const classification = classifyIssuerPage({ issuer, url: rejected });
  assert.equal(classification.kind, "not_a_card");
  const requested = [];
  const persisted = [];
  const result = await discoverIssuerCardCandidates({
    issuer,
    sitemapUrl: rootSitemap,
    completedCandidateOutcomes: [{
      candidateKey: createHash("sha256").update(rejected).digest("hex"),
      disposition: "rejected",
      attempted: false,
      classification,
    }],
    fetchOfficialIssuerResource: async (input) => {
      requested.push(input.url);
      return resource(input.url, sitemap([rejected]), "application/xml");
    },
    delay: async () => {},
    onCandidateOutcome: async (outcome) => persisted.push(outcome),
  });

  assert.deepEqual(requested, [rootSitemap]);
  assert.deepEqual(persisted, []);
  assert.equal(result.resumedCount, 1);
  assert.equal(result.quarantined.length, 1);
  assert.equal(result.complete, false);
});

test("resume retries a durably recorded fetch failure instead of treating it as complete", async () => {
  const product =
    "https://www.axis.bank.in/cards/credit-card/privilege-credit-card";
  const priorFailure = {
    candidateKey: createHash("sha256").update(product).digest("hex"),
    disposition: "quarantined",
    attempted: true,
    classification: {
      kind: "ambiguous",
      canonicalUrl: product,
      aliases: [],
      confidence: 0,
      warnings: ["candidate_fetch_failed"],
      sanitizedEvidence: [],
    },
  };
  const requested = [];
  const result = await discoverIssuerCardCandidates({
    issuer,
    sitemapUrl: rootSitemap,
    completedCandidateOutcomes: [priorFailure],
    fetchOfficialIssuerResource: async (input) => {
      requested.push(input.url);
      return input.url === rootSitemap
        ? resource(input.url, sitemap([product]), "application/xml")
        : resource(input.url, "<h1>Axis Privilege Credit Card</h1>");
    },
    delay: async () => {},
  });

  assert.deepEqual(requested, [rootSitemap, product]);
  assert.equal(result.resumedCount, 0);
  assert.equal(result.fetchedCount, 1);
  assert.equal(result.complete, true);
});

test("normal availability headings remain inside the target product discontinuation scope", () => {
  const current = classifyIssuerPage({
    issuer,
    url: "https://www.axis.bank.in/cards/credit-card/privilege-credit-card",
    html: `<h1>Axis Privilege Credit Card</h1>
      <h2>Availability</h2>
      <p>This credit card has been discontinued and is no longer issued.</p>`,
  });
  const sibling = classifyIssuerPage({
    issuer,
    url: "https://www.axis.bank.in/cards/credit-card/privilege-credit-card",
    html: `<h1>Axis Privilege Credit Card</h1>
      <h2>Axis MyZone Credit Card</h2>
      <p>This credit card has been discontinued.</p>`,
  });

  assert.equal(current.explicitDiscontinuation, true);
  assert.match(
    current.matchedDiscontinuationExcerpt ?? "",
    /privilege.*discontinued/i,
  );
  assert.notEqual(current.matchedDiscontinuationExcerpt, null);
  assert.equal(sibling.explicitDiscontinuation, undefined);
});

test("crawler identity reconciliation fails closed across exact and legacy display URL bindings", async () => {
  const exact =
    "https://www.axis.bank.in/cards/credit-card/privilege?variant=infinite";
  const display = "https://www.axis.bank.in/cards/credit-card/privilege";
  const digest = (value) => createHash("sha256").update(value).digest("hex");
  const exactHash = digest(exact);
  const displayHash = digest(display);
  const db = {
    from(table) {
      if (
        !["card_catalog_url_keys", "card_catalog_provenance"].includes(table)
      ) {
        throw new Error("unexpected_non_identity_query");
      }
      let hash = "";
      const query = {
        select() {
          return this;
        },
        eq(column, value) {
          assert.equal(column, "url_hash");
          hash = value;
          return this;
        },
        or(filter) {
          hash = filter.match(/\.eq\.([0-9a-f]{64})/)?.[1] ?? "";
          return this;
        },
        then(resolve) {
          const data = table === "card_catalog_provenance"
            ? []
            : hash === exactHash
            ? [{ card_id: "00000000-0000-4000-8000-000000000001" }]
            : hash === displayHash
            ? [{ card_id: "00000000-0000-4000-8000-000000000002" }]
            : [];
          return Promise.resolve({ data, error: null }).then(resolve);
        },
      };
      return query;
    },
  };
  await assert.rejects(
    persistCrawlerCandidate(db, issuer, {
      kind: "card_product",
      canonicalUrl: display,
      submittedUrl: exact,
      finalUrl: exact,
      submittedResourceIdentityHash: exactHash,
      finalResourceIdentityHash: exactHash,
      proposedName: "Privilege Infinite",
      aliases: ["Axis Privilege Infinite Credit Card"],
      network: "Visa",
      confidence: 0.95,
      warnings: [],
      sanitizedEvidence: ["Axis Privilege Infinite Credit Card"],
      contentHash: "c".repeat(64),
      retrievedAt: "2026-08-20T00:00:00.000Z",
      sourceStatus: 200,
    }),
    /identity_conflict/,
  );
});
