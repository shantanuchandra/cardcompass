import {
  classifyIssuerPage,
  discoverIssuerCardCandidates,
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
