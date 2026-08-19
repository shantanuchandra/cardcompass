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
  const { documents, attempts } = await collectSupportingBenefitDocuments({
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
  const { documents, attempts } = await collectSupportingBenefitDocuments({
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
      item.url === required && item.role === "required_supporting"
    ),
    "required ninth link lost its necessity classification",
  );
});

Deno.test("opaque PDF anchor metadata can establish a required MITC source", async () => {
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
      item.url === opaque && item.role === "required_supporting"
    ),
    "opaque MITC anchor was treated as optional",
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
      item.url === requiredHtml && item.role === "required_supporting"
    ),
    "terms HTML was not classified required",
  );
  assert(
    !attempts.some((item) =>
      item.url === optionalPdf && item.role === "required_supporting"
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
        item.url === url && item.role === "required_supporting" &&
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
      resource(benefits, `<a href="${required}">Terms</a>`),
  });

  assert(
    attempts.some((item) =>
      item.url === required && item.role === "required_supporting" &&
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
      resource(optional[0], `<a href="${required}">Fees</a>`),
  });

  assert(
    attempts.some((item) =>
      item.url === required && item.role === "required_supporting" &&
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
          ? `<a href="${required}">Most Important Terms and Conditions</a>`
          : "Optional details",
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
      attempt.url === pdf && attempt.role === "required_supporting" &&
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
    attempts.filter((attempt) => requested.includes(attempt.url)).every(
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
        "Free movie tickets worth Rs. 6,000 every year. Maximum discount is Rs. 250 per ticket.",
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
