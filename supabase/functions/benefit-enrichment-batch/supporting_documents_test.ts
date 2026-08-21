import {
  canonicalPilotReplayResourceUrl,
  classifyRequiredReplaySourceKeys,
  collectSupportingBenefitDocuments,
} from "./supporting_documents.ts";
import {
  assessCrawlCompleteness,
  sourceIdentityDigest,
} from "./crawl_policy.ts";
import { extractGroundedBenefitsV6 } from "../_shared/benefit_enrichment.ts";
import { safeHttpsDisplayUrl } from "../_shared/benefit_source_privacy.ts";

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

Deno.test("pilot functional resource bytes allow safe filename escapes only", () => {
  const safe =
    "https://issuer.example/terms.pdf?file=most%20important%20terms.pdf&locale=en-US";
  assert(
    canonicalPilotReplayResourceUrl(safe) === safe,
    "safe functional filename bytes were not preserved exactly",
  );
  for (
    const unsafe of [
      "https://issuer.example/terms.pdf?file=%61ccess_token%3Dsecret",
      "https://issuer.example/terms.pdf?document=%E0%A4%B6%E0%A4%B0%E0%A5%8D%E0%A4%A4%E0%A5%87%E0%A4%82",
      "https://issuer.example/terms.pdf?file=access%5Ftoken",
      "https://issuer.example/terms.pdf?document=customer%20id",
      "https://issuer.example/terms.pdf?file=%73ecret",
      "https://issuer.example/terms.pdf?file=%FF",
      "https://issuer.example/terms.pdf?file=%0A",
      `https://issuer.example/terms.pdf?file=${"%20".repeat(400)}`,
    ]
  ) {
    let rejected = false;
    try {
      canonicalPilotReplayResourceUrl(unsafe);
    } catch {
      rejected = true;
    }
    assert(rejected, `unsafe or non-parity query bytes survived: ${unsafe}`);
  }
  const tracking =
    `${safe}&utm_source=https%3A%2F%2Ftracker.example%2Fcampaign`;
  assert(
    canonicalPilotReplayResourceUrl(tracking) === safe,
    "encoded tracking was validated as functional data instead of dropped",
  );
});

Deno.test("root functional resource has one Edge and SQL byte identity", () => {
  const root = canonicalPilotReplayResourceUrl(
    "https://issuer.example/?locale=en",
  );
  assert(
    root === "https://issuer.example/?locale=en",
    "root functional query lost the WHATWG slash",
  );
  assert(
    sourceIdentityDigest(root) ===
      "2b11cd567b1ddbc93697a59fe4a74f972bf7988553f3d43ca34d039e33aa28a5",
    "root functional resource bytes changed before hashing",
  );
  assert(
    safeHttpsDisplayUrl(root) === "https://issuer.example",
    "root functional resource did not canonicalize to one queryless display",
  );
});

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

Deno.test("required central support links are fetched or retained as decisive failure evidence", async () => {
  const product = "https://www.axis.bank.in/cards/credit-card/privilege";
  const centralTerms = "https://www.axis.bank.in/support/card-terms.pdf";
  const fetched: string[] = [];
  const collected = await collectSupportingBenefitDocuments({
    issuer: "Axis Bank",
    primary: resource(
      product,
      `<h1>Privilege Credit Card</h1><a href="${centralTerms}">Download PDF</a>`,
    ),
    identityLabels: ["Privilege Credit Card"],
    fetchOfficialIssuerResource: async (input) => {
      fetched.push(input.url);
      return resource(
        input.url,
        "Privilege Credit Card terms and fees",
        "application/pdf",
      );
    },
  });
  assert(
    fetched.includes(centralTerms),
    "href-only central terms link was dropped before fetch",
  );
  assert(
    collected.expectedRequiredSourceKeys.includes(
      sourceIdentityDigest(centralTerms),
    ),
    "central terms link was omitted from the required manifest",
  );

  const unsafe = await collectSupportingBenefitDocuments({
    issuer: "Axis Bank",
    primary: resource(
      product,
      `<a href="${product}/application/terms.pdf">Download PDF</a><a href="https://[invalid/fees.pdf">Download</a>`,
    ),
    identityLabels: ["Privilege Credit Card"],
    fetchOfficialIssuerResource: async () => {
      throw new Error("unsafe required link must not be fetched");
    },
  });
  assert(
    unsafe.attempts.some((attempt) =>
      attempt.role === "required_supporting" && attempt.status === "failed"
    ),
    "unsafe or invalid required href disappeared instead of becoming decisive failure evidence",
  );
});

Deno.test("global navigation terms do not crowd out product-scoped required sources", async () => {
  const product =
    "https://www.hdfc.bank.in/credit-cards/swiggy-hdfc-bank-credit-card";
  const productTerms = `${product}/terms-and-conditions`;
  const centralTerms =
    "https://www.hdfc.bank.in/support/card-terms-and-conditions.pdf";
  const globalLinks = [
    "/education-fees",
    "/fees-and-charges",
    "/life-insurance/terms",
    "/loans/term-loans",
    "/savings-account/fees",
    "/payzapp/fees-and-charges",
    "/merchant-services/charges",
    "/investments/terms",
  ];
  const fetched: string[] = [];
  const html = [
    "<h1>Swiggy HDFC Bank Credit Card</h1>",
    `<a href="${productTerms}">Terms and Conditions</a>`,
    `<a href="${centralTerms}">Download card terms</a>`,
    ...globalLinks.map((href) => `<a href="${href}">Fees and terms</a>`),
  ].join("");

  const collected = await collectSupportingBenefitDocuments({
    issuer: "HDFC Bank",
    primary: resource(product, html),
    identityLabels: ["Swiggy HDFC Bank Credit Card"],
    fetchOfficialIssuerResource: async (input) => {
      fetched.push(input.url);
      return resource(
        input.url,
        "Swiggy HDFC Bank Credit Card terms and fees",
        input.url.endsWith(".pdf") ? "application/pdf" : "text/html",
      );
    },
  });

  assert(
    JSON.stringify(fetched.sort()) ===
      JSON.stringify([centralTerms, productTerms].sort()),
    `unrelated global terms were treated as required: ${fetched.join(",")}`,
  );
  assert(
    collected.requiredSourceSelectionOverflow === false,
    "unrelated global terms manufactured required-source overflow",
  );
  assert(
    collected.expectedRequiredSourceKeys.length === 2,
    "product and central card terms were not the exact required manifest",
  );
  assert(
    classifyRequiredReplaySourceKeys(collected.documents).overflow === false,
    "replay classifier disagreed with the scoped live source selection",
  );
});

Deno.test("issuer-owned card terms supersede external partner terms without manufacturing overflow", async () => {
  const product =
    "https://www.hdfc.bank.in/credit-cards/swiggy-hdfc-bank-credit-card";
  const productTerms =
    `${product}/pdf/terms-and-conditions-swiggy-hdfc-bank-credit-card.pdf`;
  const fees = `${product}/fees-and-charges`;
  const externalPartnerTerms = "https://www.swiggy.com/terms-and-conditions";
  const fetched: string[] = [];
  const maxBytes: number[] = [];
  const collected = await collectSupportingBenefitDocuments({
    issuer: "HDFC Bank",
    primary: resource(
      product,
      `<h1>Swiggy HDFC Bank Credit Card</h1>
       ${"public product details ".repeat(26_000)}
       <p>Swiggy One membership terms are available
         <a href="${externalPartnerTerms}">here</a>.</p>
       <a href="${productTerms}">Card terms and conditions</a>
       <a href="${fees}">Fees and charges</a>`,
    ),
    identityLabels: ["Swiggy", "Swiggy HDFC Bank Credit Card"],
    fetchOfficialIssuerResource: async (input) => {
      fetched.push(input.url);
      maxBytes.push(input.maxBytes ?? 0);
      return resource(
        input.url,
        "Swiggy HDFC Bank Credit Card terms, fees, and membership conditions",
      );
    },
  });

  assert(
    JSON.stringify(fetched.sort()) ===
      JSON.stringify([fees, productTerms].sort()),
    `external partner terms blocked issuer-owned sources: ${fetched.join(",")}`,
  );
  assert(
    maxBytes.length === 2 &&
      maxBytes.every((value) => value === 2 * 1024 * 1024),
    `issuer supporting fetch limit was not the bounded 2 MiB policy: ${
      maxBytes.join(",")
    }`,
  );
  assert(
    !collected.attempts.some((attempt) =>
      attempt.requestedUrl === externalPartnerTerms
    ),
    "external partner terms entered the issuer fetch manifest",
  );
  assert(
    collected.expectedRequiredSourceKeys.length === 2 &&
      collected.expectedRequiredSourceKeys.includes(
        sourceIdentityDigest(productTerms),
      ) &&
      collected.expectedRequiredSourceKeys.includes(sourceIdentityDigest(fees)),
    "issuer-owned terms were not the exact required manifest",
  );
  assert(
    collected.requiredSourceSelectionOverflow === false &&
      classifyRequiredReplaySourceKeys(collected.documents).overflow === false,
    "redundant external terms manufactured required-source overflow",
  );
  assert(
    JSON.stringify(
      classifyRequiredReplaySourceKeys(collected.documents).keys,
    ) === JSON.stringify([...collected.expectedRequiredSourceKeys].sort()),
    "replay reintroduced external terms superseded by issuer-owned evidence",
  );
  assert(
    assessCrawlCompleteness(
      collected.attempts,
      "2026-08-17T00:01:00.000Z",
    ).complete,
    "complete issuer-owned terms did not complete the crawl",
  );
});

Deno.test("an external required link remains decisive without issuer-owned evidence", () => {
  const primary = "https://issuer.example/card";
  const external = "https://partner.example/card-terms";
  const classified = classifyRequiredReplaySourceKeys([{
    sourceUrl: primary,
    finalUrl: primary,
    contentHash: "a".repeat(64),
    text: "Issuer Example Credit Card",
    replayLinks: [{
      href: external,
      resourceUrl: external,
      anchorText: "Card terms and conditions",
      resourceIdentityHash: sourceIdentityDigest(external),
      queryPolicy: "functional_only",
    }],
  }]);
  assert(
    classified.keys.length === 1 &&
      classified.keys[0] === sourceIdentityDigest(external),
    "an unsupported external required source was silently ignored",
  );
});

Deno.test("card-scoped PDF identity tolerates bounded inter-glyph spacing", async () => {
  const product =
    "https://www.hdfc.bank.in/credit-cards/swiggy-hdfc-bank-credit-card";
  const productTerms =
    `${product}/pdf/terms-and-conditions-swiggy-hdfc-bank-credit-card.pdf`;
  const pdf =
    "%PDF-1.4\nBT (S w i g g y H D F C B a n k C r e d i t C a r d earns 10 percent cashback.) Tj ET\n%%EOF";
  const collected = await collectSupportingBenefitDocuments({
    issuer: "HDFC Bank",
    primary: resource(
      product,
      `<h1>Swiggy HDFC Bank Credit Card</h1>
       <a href="${productTerms}">Card terms and conditions</a>`,
    ),
    identityLabels: ["Swiggy", "Swiggy HDFC Bank Credit Card"],
    fetchOfficialIssuerResource: async () =>
      resource(productTerms, pdf, "application/pdf"),
  });

  const termAttempt = collected.attempts.find((attempt) =>
    attempt.requestedUrl === productTerms
  );
  assert(
    termAttempt?.status === "success",
    `exact card PDF identity was not proven: ${termAttempt?.errorCode}`,
  );
  assert(
    collected.documents.some((document) => document.sourceUrl === productTerms),
    "exact card PDF was not retained after identity validation",
  );
});

Deno.test("an exact-card PDF retains late bounded benefit facts", async () => {
  const product =
    "https://www.hdfc.bank.in/credit-cards/swiggy-hdfc-bank-credit-card";
  const productTerms = `${product}/terms.pdf`;
  const pdf = `%PDF-1.4\nBT (${
    [
      "Swiggy HDFC Bank Credit Card terms and conditions.",
      ...Array.from({ length: 12 }, (_, index) =>
        `General condition ${index + 1} applies to account usage.`),
      "Get 10% cashback on food delivery spends up to Rs. 1,500 per month.",
    ].join(" ")
  }) Tj ET\n%%EOF`;
  const collected = await collectSupportingBenefitDocuments({
    issuer: "HDFC Bank",
    primary: resource(
      product,
      `<h1>Swiggy HDFC Bank Credit Card</h1>
       <a href="${productTerms}">Card terms and conditions</a>`,
    ),
    identityLabels: ["Swiggy", "Swiggy HDFC Bank Credit Card"],
    fetchOfficialIssuerResource: async () =>
      resource(productTerms, pdf, "application/pdf"),
  });

  const supporting = collected.documents.find((document) =>
    document.sourceUrl === productTerms
  );
  assert(
    supporting?.text.includes("10% cashback") === true,
    "late exact-card PDF evidence was silently truncated",
  );
});

Deno.test("card-scoped PDF evidence excludes remote rival product sections", async () => {
  const product =
    "https://www.hdfc.bank.in/credit-cards/swiggy-hdfc-bank-credit-card";
  const productTerms = `${product}/terms.pdf`;
  const pdf =
    "%PDF-1.4\nBT (Axis Privilege Credit Card earns 5% cashback. General issuer prose. More general issuer prose. Another unrelated section. Swiggy HDFC Bank Credit Card earns 10% cashback on food orders. The Swiggy cashback cap is 1500 per month.) Tj ET\n%%EOF";
  const collected = await collectSupportingBenefitDocuments({
    issuer: "HDFC Bank",
    primary: resource(
      product,
      `<h1>Swiggy HDFC Bank Credit Card</h1>
       <a href="${productTerms}">Card terms</a>`,
    ),
    identityLabels: ["Swiggy", "Swiggy HDFC Bank Credit Card"],
    fetchOfficialIssuerResource: async () =>
      resource(productTerms, pdf, "application/pdf"),
  });

  const supporting = collected.documents.find((document) =>
    document.sourceUrl === productTerms
  );
  assert(
    supporting?.text.includes("Swiggy HDFC Bank Credit Card") === true &&
      !supporting.text.includes("Axis Privilege Credit Card"),
    `remote rival PDF section survived product scoping: ${supporting?.text}`,
  );
});

Deno.test("an exact-family PDF cannot waive a sibling product ambiguity", async () => {
  const product =
    "https://www.hdfc.bank.in/credit-cards/swiggy-hdfc-bank-credit-card";
  const upgrade = `${product}/faq-swiggy-card-upgrade.pdf`;
  const fetched: string[] = [];
  const collected = await collectSupportingBenefitDocuments({
    issuer: "HDFC Bank",
    primary: resource(
      product,
      `<h1>Swiggy HDFC Bank Credit Card</h1>
       <a href="${upgrade}">Swiggy card FAQ</a>`,
    ),
    identityLabels: ["Swiggy", "Swiggy HDFC Bank Credit Card"],
    fetchOfficialIssuerResource: async (input) => {
      fetched.push(input.url);
      return resource(
        input.url,
        "%PDF-1.4\nBT (Swiggy HDFC Bank Credit Card terms. If you opt for the Swiggy BLCK Card, different fees apply.) Tj ET\n%%EOF",
        "application/pdf",
      );
    },
  });

  assert(
    collected.documents.every((document) => document.sourceUrl !== upgrade),
    "a sibling-product PDF entered target benefit evidence",
  );
  assert(
    fetched.length === 0 &&
      collected.attempts.every((attempt) => attempt.requestedUrl !== upgrade),
    "a related upgrade document consumed the target benefit crawl budget",
  );
});

Deno.test("card-specific required terms supersede redundant generic issuer MITC", async () => {
  const product =
    "https://www.hdfc.bank.in/credit-cards/swiggy-hdfc-bank-credit-card";
  const productTerms =
    `${product}/pdf/terms-and-conditions-swiggy-hdfc-bank-credit-card.pdf`;
  const genericMitc =
    "https://www.hdfc.bank.in/credit-cards/personal-mitc/mitc-in-english.pdf";
  const collected = await collectSupportingBenefitDocuments({
    issuer: "HDFC Bank",
    primary: resource(
      product,
      `<h1>Swiggy HDFC Bank Credit Card</h1>
       <a href="${genericMitc}">Most Important Terms and Conditions</a>
       <a href="${productTerms}">Card terms and conditions</a>`,
    ),
    identityLabels: ["Swiggy", "Swiggy HDFC Bank Credit Card"],
    fetchOfficialIssuerResource: async (input) =>
      resource(
        input.url,
        input.url === productTerms
          ? "Swiggy HDFC Bank Credit Card terms and conditions"
          : "HDFC Bank general credit card terms",
      ),
  });

  const genericAttempt = collected.attempts.find((attempt) =>
    attempt.requestedUrl === genericMitc
  );
  assert(
    genericAttempt === undefined,
    `redundant generic MITC was still fetched: ${
      JSON.stringify(genericAttempt)
    }`,
  );
  assert(
    collected.expectedRequiredSourceKeys.length === 1 &&
      collected.expectedRequiredSourceKeys[0] ===
        sourceIdentityDigest(productTerms),
    "generic MITC remained in the exact required-source manifest",
  );
  assert(
    assessCrawlCompleteness(
      collected.attempts,
      "2026-08-17T00:01:00.000Z",
    ).complete,
    "optional generic MITC failure made the card-specific crawl incomplete",
  );
});

Deno.test("primary product scope excludes global header navigation from links and benefits", async () => {
  const product = "https://www.axis.bank.in/credit-cards/ace-credit-card";
  const productTerms = `${product}/terms-and-conditions`;
  const unrelatedTerms =
    "https://www.axis.bank.in/credit-cards/airtel-credit-card/terms-and-conditions";
  const fetched: string[] = [];
  const collected = await collectSupportingBenefitDocuments({
    issuer: "Axis Bank",
    primary: resource(
      product,
      `<header>
        <h2>Airtel Axis Bank Credit Card</h2>
        <p>Get 25% cashback on Airtel spends.</p>
        <a href="${unrelatedTerms}">Terms and Conditions</a>
      </header>
      <main>
        <h1>ACE Credit Card</h1>
        <p>Get 5% cashback on utility bill payments.</p>
        <a href="${productTerms}">Card terms and conditions</a>
      </main>
      <footer>Magnus Credit Card offers unlimited lounge visits.</footer>`,
    ),
    identityLabels: ["ACE Credit Card"],
    fetchOfficialIssuerResource: async (input) => {
      fetched.push(input.url);
      return resource(
        input.url,
        "ACE Credit Card terms and conditions. Get 5% cashback on utility bill payments.",
      );
    },
  });

  const retainedPrimary = collected.documents[0]?.text ?? "";
  assert(
    retainedPrimary.includes("ACE Credit Card") &&
      retainedPrimary.includes("5% cashback"),
    "target product content was not retained",
  );
  assert(
    !retainedPrimary.includes("Airtel") &&
      !retainedPrimary.includes("25% cashback") &&
      !retainedPrimary.includes("Magnus"),
    "global header/footer content leaked into the product evidence",
  );
  assert(
    JSON.stringify(fetched) === JSON.stringify([productTerms]),
    `global navigation link was fetched: ${fetched.join(",")}`,
  );

  const proposals = await extractGroundedBenefitsV6(
    collected.documents,
    "benefits-v6",
    "00000000-0000-4000-8000-000000000001",
  );
  assert(
    proposals.some((proposal) => JSON.stringify(proposal).includes("5%")),
    "target product benefit was not extracted",
  );
  assert(
    proposals.every((proposal) =>
      !JSON.stringify(proposal).includes("25%") &&
      !JSON.stringify(proposal).includes("Airtel") &&
      !JSON.stringify(proposal).includes("Magnus")
    ),
    "global navigation benefit was extracted for the target card",
  );
});

Deno.test("a title-only main shell does not hide product sections outside main", async () => {
  const product =
    "https://www.sbicard.com/en/personal/credit-cards/air-india-sbi-platinum-card.html";
  const collected = await collectSupportingBenefitDocuments({
    issuer: "SBI Card",
    primary: resource(
      product,
      `<header><p>SimplySAVE SBI Card earns 10X reward points.</p></header>
       <main><h1>Air India SBI Platinum Credit Card</h1></main>
       <section><h2>Card benefits</h2>
         <p>Earn 2 reward points for every Rs. 100 spent.</p>
         <p>Get 5 reward points for every Rs. 100 spent on Air India tickets.</p>
       </section>
       <footer>Explore more SBI cards.</footer>`,
    ),
    identityLabels: ["Air India SBI Platinum Credit Card"],
    maximumLinks: 0,
  });

  const retainedPrimary = collected.documents[0]?.text ?? "";
  assert(
    retainedPrimary.includes("Earn 2 reward points") &&
      retainedPrimary.includes("Air India tickets"),
    "product sections outside the title-only main shell were discarded",
  );
  assert(
    !retainedPrimary.includes("SimplySAVE") &&
      !retainedPrimary.includes("Explore more SBI cards"),
    "fallback product scope reintroduced global chrome",
  );
});

Deno.test("related-product cards below the target section never enter primary evidence", async () => {
  const product =
    "https://www.axis.bank.in/cards/credit-card/indianoil-axis-bank-credit-card";
  const collected = await collectSupportingBenefitDocuments({
    issuer: "Axis Bank",
    primary: resource(
      product,
      `<main>
        <h1>IndianOil Axis Bank Credit Card</h1>
        <p>Enjoy 1% fuel surcharge waiver on fuel transactions.</p>
        <section id="allCards" class="cards-for-you">
          <h2>Related Products</h2>
          <article><h3>Fibe Axis Bank Credit Card</h3>
            <p>Get up to 3% cashback on every transaction.</p>
          </article>
        </section>
      </main>`,
    ),
    identityLabels: ["IndianOil Axis Bank Credit Card"],
    maximumLinks: 0,
  });

  const retained = collected.documents[0]?.text ?? "";
  assert(
    retained.includes("1% fuel surcharge waiver"),
    "target evidence was lost",
  );
  assert(
    !retained.includes("Fibe") && !retained.includes("3% cashback"),
    "related-product evidence survived target scoping",
  );
  const proposals = await extractGroundedBenefitsV6(
    collected.documents,
    "benefits-v6",
    "00000000-0000-4000-8000-000000000001",
  );
  assert(
    proposals.length === 1 && proposals[0].category === "fuel",
    "a related card manufactured a target benefit",
  );
});

Deno.test("Sitefinity cache-buster queries are discarded before required PDF fetch", async () => {
  const product =
    "https://www.axis.bank.in/cards/credit-card/indianoil-axis-bank-credit-card";
  const terms =
    "https://www.axis.bank.in/docs/default-source/default-document-library/credit-cards/terms-and-conditions-indian-oil-credit-card.pdf";
  const fetched: string[] = [];
  const collected = await collectSupportingBenefitDocuments({
    issuer: "Axis Bank",
    primary: resource(
      product,
      `<h1>IndianOil Axis Bank Credit Card</h1>
       <a href="${terms}?sfvrsn=213fdc9a_1">Terms and Conditions</a>`,
    ),
    identityLabels: ["IndianOil Axis Bank Credit Card"],
    fetchOfficialIssuerResource: async (input) => {
      fetched.push(input.url);
      return resource(
        input.url,
        "IndianOil Axis Bank Credit Card terms. Enjoy 1% fuel surcharge waiver.",
        "application/pdf",
      );
    },
  });

  assert(
    fetched.length === 1 && fetched[0] === terms,
    `cache buster was preserved or terms were not fetched: ${
      fetched.join(",")
    }`,
  );
  assert(
    !collected.requiredSourceSelectionOverflow,
    "a public cache-buster manufactured required-source overflow",
  );
});

Deno.test("official embedded product JSON is discovered and retained as benefit evidence", async () => {
  const product =
    "https://www.sbicard.com/en/personal/credit-cards/sbi-card-elite.html";
  const productJson =
    "https://www.sbicard.com/json/templatedata/product/card/data/en/personal/sbi-card-elite.json";
  const collected = await collectSupportingBenefitDocuments({
    issuer: "SBI Card",
    primary: resource(
      product,
      `<main><h1>SBI Card ELITE</h1>
       <div data-component="productDetail"
            data-path="/templatedata/product/card/data/en/personal/sbi-card-elite.json"></div>
       </main>`,
    ),
    identityLabels: ["SBI Card ELITE"],
    fetchOfficialIssuerResource: async (input) => {
      assert(
        input.url === productJson,
        `unexpected product JSON URL ${input.url}`,
      );
      return resource(
        input.url,
        JSON.stringify({
          title: "SBI Card ELITE",
          benefits: [
            "5X Reward Points on dining, departmental stores and grocery spends",
            "1% Fuel Surcharge Waiver across all petrol pumps",
            "2 complimentary domestic airport lounge visits every quarter",
          ],
        }),
        "application/json",
      );
    },
  });

  assert(
    collected.documents.some((document) => document.sourceUrl === productJson),
    "the official product JSON was not retained",
  );
  const proposals = await extractGroundedBenefitsV6(
    collected.documents,
    "benefits-v6",
    "00000000-0000-4000-8000-000000000001",
  );
  assert(
    ["fuel", "points", "travel"].every((category) =>
      proposals.some((proposal) => proposal.category === category)
    ),
    `embedded product benefits were not extracted: ${
      proposals.map((item) => item.category).join(",")
    }`,
  );
});

Deno.test("large primary pages stop before supporting fetches once required evidence is invalid", async () => {
  const product = "https://www.idfcfirst.bank.in/credit-card/wealth";
  let fetchCount = 0;
  const collected = await collectSupportingBenefitDocuments({
    issuer: "IDFC FIRST Bank",
    primary: resource(
      product,
      `<h1>FIRST Wealth Credit Card</h1>${
        "public navigation ".repeat(40_000)
      }` +
        `<a href="https://www.visameetandgreet.com/terms-and-conditions">Terms</a>`,
    ),
    identityLabels: ["Wealth", "FIRST Wealth Credit Card"],
    fetchOfficialIssuerResource: async (input) => {
      fetchCount += 1;
      return resource(input.url, "FIRST Wealth Credit Card terms");
    },
  });

  assert(fetchCount === 0, "decisively incomplete large page kept fetching");
  assert(
    collected.requiredSourceSelectionOverflow,
    "invalid required evidence did not fail the bounded selection",
  );
  assert(
    collected.attempts.some((attempt) =>
      attempt.role === "required_supporting" &&
      attempt.errorCode === "invalid_source_url"
    ),
    "invalid required source evidence was dropped by the fail-fast path",
  );
});

Deno.test("a late required anchor hint is classified without prefix slicing", async () => {
  const product = "https://www.axis.bank.in/cards/credit-card/privilege";
  const required = "https://www.axis.bank.in/support/document.pdf";
  let fetchCount = 0;
  const collected = await collectSupportingBenefitDocuments({
    issuer: "Axis Bank",
    primary: resource(
      product,
      `<h1>Privilege Credit Card</h1><a href="${required}">${
        "general information ".repeat(24)
      }Terms and Conditions</a>`,
    ),
    identityLabels: ["Privilege Credit Card"],
    fetchOfficialIssuerResource: async () => {
      fetchCount += 1;
      return resource(required, "Privilege Credit Card terms and fees");
    },
  });
  assert(fetchCount === 1, "late required anchor hint was silently sliced");
  assert(
    collected.attempts.some((attempt) =>
      attempt.requestedUrl === required &&
      attempt.role === "required_supporting" && attempt.status === "success"
    ),
    "late required anchor did not become decisive evidence",
  );
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
        "<title>Privilege Credit Card</title><h1>Privilege Credit Card</h1><p>Offer at the Regalia Gold hotel partner.</p>",
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

Deno.test("supporting functional query keys retain exact replay resources but not attempt URLs", async () => {
  const privilege = "https://www.axis.bank.in/cards/credit-card/privilege";
  const terms =
    `${privilege}/terms?document=mitc.pdf&locale=en&version=2&locale=hi&utm_source=campaign`;
  const canonicalTerms =
    `${privilege}/terms?document=mitc.pdf&locale=en&version=2&locale=hi`;
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
      return resource(canonicalTerms, "Privilege Credit Card MITC and fees");
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
      document.finalUrl === `${privilege}/terms` &&
      document.finalResourceUrl === canonicalTerms
    ),
    "exact functional resource provenance was not retained in memory",
  );
  const replayLink = collected.documents[0].replayLinks?.[0] as
    | Record<string, unknown>
    | undefined;
  assert(
    replayLink?.href === `${privilege}/terms` &&
      replayLink.anchorText === "mitc" &&
      replayLink.resourceUrl === canonicalTerms &&
      replayLink.resourceIdentityHash ===
        sourceIdentityDigest(canonicalTerms) &&
      replayLink.queryPolicy === "functional_only",
    "live collection did not retain exact approved functional replay identity",
  );
  assert(
    !JSON.stringify(
      assessCrawlCompleteness(
        collected.attempts,
        "2026-08-17T00:01:00.000Z",
      ).attempts,
    ).includes("document=mitc"),
    "functional query value entered persisted source attempts",
  );
});

Deno.test("linked query rejections remain bounded evidence and approved entity selectors are fetched exactly", async () => {
  const product = "https://www.axis.bank.in/cards/credit-card/privilege";
  const approved = `${product}/terms?document=mitc&variant=entity`;
  const fetched: string[] = [];
  const collected = await collectSupportingBenefitDocuments({
    issuer: "Axis Bank",
    primary: resource(
      product,
      `<h1>Privilege Credit Card</h1>
       <a href="${product}/terms?product=privilege">Terms product selector</a>
       <a href="${product}/fees?token=private-secret">Fees</a>
       <a href="${product}/terms?document=%E0%A4%A">Malformed terms selector</a>
       <a href="https://[invalid/mitc">MITC</a>
       <a href="${product}/terms?document=mitc&amp;variant=entity">MITC entity selector</a>`,
    ),
    identityLabels: ["Privilege Credit Card"],
    fetchOfficialIssuerResource: async (input) => {
      fetched.push(input.url);
      return resource(input.url, "Privilege Credit Card MITC and fees");
    },
  });
  assert(
    fetched.join(",") === approved,
    `approved selector was not preserved exactly: ${fetched.join(",")}`,
  );
  const rejected = collected.attempts.filter((item) =>
    item.errorCode === "unapproved_query" ||
    item.errorCode === "invalid_source_url"
  );
  assert(rejected.length === 4, "rejected required candidates vanished");
  assert(
    rejected.every((item) => item.role === "required_supporting"),
    "required anchor metadata was lost on rejection",
  );
  const assessment = assessCrawlCompleteness(
    collected.attempts,
    "2026-08-20T00:00:00.000Z",
  );
  assert(!assessment.complete, "required rejected query enabled removals");
  const persisted = JSON.stringify(assessment.attempts);
  assert(!persisted.includes("private-secret"), "query secret was persisted");
  assert(!persisted.includes("?"), "query value entered persisted evidence");
});

Deno.test("supporting attempts retain opaque final resource identity", async () => {
  const product = "https://www.axis.bank.in/cards/credit-card/privilege";
  const terms = `${product}/terms?document=mitc`;
  const suppliedHash = "d".repeat(64);
  const finalHash = sourceIdentityDigest(terms);
  const collected = await collectSupportingBenefitDocuments({
    issuer: "Axis Bank",
    primary: resource(
      product,
      `<h1>Privilege Credit Card</h1><a href="${terms}">MITC</a>`,
    ),
    identityLabels: ["Privilege Credit Card"],
    fetchOfficialIssuerResource: async () => ({
      ...resource(terms, "Privilege Credit Card MITC"),
      finalResourceIdentityHash: suppliedHash,
    }),
  });
  const persisted = assessCrawlCompleteness(
    collected.attempts,
    "2026-08-20T00:00:00.000Z",
  ).attempts.find((item) =>
    item.role === "required_supporting"
  ) as unknown as Record<string, unknown>;
  assert(
    persisted.finalResourceIdentityHash === finalHash &&
      persisted.finalResourceIdentityHash !== suppliedHash,
    "supporting final identity was not recomputed from the exact resource",
  );
  const retained = collected.documents.find((document) =>
    document.sourceUrl === terms
  );
  assert(
    retained?.requestedResourceIdentityHash === sourceIdentityDigest(terms) &&
      retained.finalResourceIdentityHash === finalHash,
    "retained parser document lost exact requested/final resource identities",
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
  assert(
    attempts.length === 5 &&
      attempts.slice(1).every((attempt) =>
        attempt.status === "success" &&
        !attempt.requestedUrl.startsWith("https://evil.example/")
      ),
    "issuer-owned successes were lost or a redundant external link entered the manifest",
  );
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

Deno.test("primary replay identity preserves an approved functional query", async () => {
  const display = "https://www.axis.bank.in/cards/credit-card/privilege";
  const resourceUrl = `${display}?document=mitc.pdf&locale=en`;
  const primary = {
    ...resource(display, "<p>Get 10% cashback on dining.</p>"),
    submittedUrl: display,
    submittedResourceUrl: resourceUrl,
    finalResourceUrl: resourceUrl,
  };
  const { documents } = await collectSupportingBenefitDocuments({
    issuer: "Axis Bank",
    primary,
    identityLabels: ["Privilege"],
    maximumLinks: 0,
  });

  assert(
    documents[0].requestedResourceUrl === resourceUrl,
    "primary requested functional query was replaced by its display URL",
  );
  assert(
    documents[0].requestedResourceIdentityHash ===
      sourceIdentityDigest(resourceUrl),
    "primary replay hash no longer binds the exact submitted resource",
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
  const { attempts, expectedRequiredSourceKeys } =
    await collectSupportingBenefitDocuments({
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

  assert(
    expectedRequiredSourceKeys.join(",") ===
      sourceIdentityDigest(required),
    "required selection was derived only from the later attempt list",
  );

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
  const { attempts, requiredSourceSelectionOverflow } =
    await collectSupportingBenefitDocuments({
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
  const { attempts, requiredSourceSelectionOverflow } =
    await collectSupportingBenefitDocuments({
      issuer: "Axis Bank",
      identityLabels: ["Privilege"],
      primary: resource(
        product,
        [...ownLinks, other].map((url) => `<a href="${url}">Terms</a>`).join(
          "",
        ),
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
    requiredSourceSelectionOverflow,
    "initial required selection overflow was not independently retained",
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
  assert(
    classifyRequiredReplaySourceKeys(documents).keys.includes(
      sourceIdentityDigest(campaign),
    ),
    "curated source context could not be reclassified from replay input",
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
