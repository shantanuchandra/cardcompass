import { collectSupportingBenefitDocuments } from "./supporting_documents.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

function resource(
  url: string,
  text: string,
  contentType = "text/html",
) {
  return {
    submittedUrl: url,
    finalUrl: url,
    canonicalUrl: url,
    contentType,
    bytes: new TextEncoder().encode(text),
    text: contentType === "application/pdf" ? "" : text,
    contentHash: `hash:${url}`,
    retrievedAt: "2026-08-17T00:00:00.000Z",
  };
}

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
  const documents = await collectSupportingBenefitDocuments({
    issuer: "Axis Bank",
    primary,
    identityLabels: ["Privilege"],
    fetchOfficialIssuerResource: async (input) => {
      requested.push(input.url);
      if (input.url === benefits) {
        return resource(
          benefits,
          `<p>Get 10% cashback on dining.</p><a href="${pdf}">MITC</a>`,
        );
      }
      if (input.url === terms) {
        return resource(
          terms,
          `<p>Fee waiver on annual spend.</p><a href="${rewards}">Rewards</a>`,
        );
      }
      if (input.url === pdf) {
        return resource(
          pdf,
          "%PDF-1.4\nstream\nBT (Get 2 lounge visits per quarter.) Tj ET\nendstream\n%%EOF",
          "application/pdf",
        );
      }
      if (input.url === rewards) {
        return resource(
          rewards,
          `<p>Earn 5 points.</p><a href="${depthThree}">More rewards</a>`,
        );
      }
      if (input.url === depthThree) return resource(depthThree, "never");
      throw new Error(`unexpected URL ${input.url}`);
    },
  });

  assert(
    requested.join(",") === [benefits, terms, pdf, rewards].join(","),
    "crawl exceeded relevant depth-two links",
  );
  assert(documents.length === 5, "primary/supporting evidence was lost");
  const pdfDocument = documents.find((document) => document.sourceUrl === pdf);
  assert(
    pdfDocument?.text.includes("2 lounge visits per quarter"),
    "PDF text was not included",
  );
  assert(
    pdfDocument?.contentHash === `hash:${pdf}`,
    "PDF hash provenance was lost",
  );
});

Deno.test("supporting crawl fetches at most eight relevant links", async () => {
  const product = "https://www.axis.bank.in/cards/credit-card/privilege";
  const links = Array.from(
    { length: 10 },
    (_, index) => `${product}/benefits-${index}`,
  );
  let fetches = 0;
  const documents = await collectSupportingBenefitDocuments({
    issuer: "Axis Bank",
    identityLabels: ["Privilege"],
    primary: resource(
      product,
      links.map((url) => `<a href="${url}">Benefit</a>`).join(""),
    ),
    fetchOfficialIssuerResource: async (input) => {
      fetches += 1;
      return resource(input.url, `<p>Benefit ${fetches}</p>`);
    },
  });

  assert(fetches === 8, "supporting fetch budget exceeded eight");
  assert(documents.length === 9, "bounded supporting documents were omitted");
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
  await collectSupportingBenefitDocuments({
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

  assert(requested.length === 8, "failed requests did not consume the budget");
  assert(!requested.includes(other), "cross-card supporting link was fetched");
});

Deno.test("SBI Card ELITE receives its exact official campaign terms before generic links", async () => {
  const product =
    "https://www.sbicard.com/en/personal/credit-cards/sbi-card-elite.html";
  const campaign = "https://www.sbicard.com/en/eapply/sbicampaign.page";
  const genericTerms =
    "https://www.sbicard.com/en/most-important-terms-and-conditions.page";
  const requested: string[] = [];
  const documents = await collectSupportingBenefitDocuments({
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
        "Free movie tickets worth Rs. 6,000 every year. Maximum discount is Rs. 250 per ticket.",
      );
    },
  });

  assert(
    requested.join(",") === campaign,
    "the exact ELITE source did not receive the bounded supporting slot",
  );
  assert(documents.length === 2, "the ELITE campaign evidence was omitted");
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
