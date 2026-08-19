import { assertEquals, assertRejects } from "jsr:@std/assert";
import {
  resolveFeedbackContext,
  resolveRecommendationCatalog,
} from "./context.ts";
import { executeEvalCase } from "../ai-eval-runner/executors.ts";

function fakeDb(rows: Record<string, Record<string, unknown>[]>) {
  const selects: string[] = [];
  return {
    selects,
    from(table: string) {
      let filtered = [...(rows[table] ?? [])];
      const query: any = {
        select(columns: string) {
          selects.push(`${table}:${columns}`);
          return query;
        },
        eq(column: string, value: unknown) {
          filtered = filtered.filter((row) => row[column] === value);
          return query;
        },
        in(column: string, values: unknown[]) {
          filtered = filtered.filter((row) => values.includes(row[column]));
          return query;
        },
        async maybeSingle() {
          return { data: filtered[0] ?? null, error: null };
        },
        then(resolve: (value: unknown) => unknown) {
          return Promise.resolve({ data: filtered, error: null }).then(resolve);
        },
      };
      return query;
    },
  };
}

Deno.test("resolver rejects every foreign persisted output and selects no raw/source fields", async () => {
  const cases = [
    [
      "transactions",
      "statement_processing",
      "transaction",
      "id,user_card_id,amount,currency,merchant_name,category,transaction_type,transaction_date,statement_id",
    ],
    [
      "statements",
      "statement_processing",
      "statement",
      "id,user_card_id,statement_date,due_date,total_amount,minimum_payment,closing_balance,fees_charged,processed,transaction_count",
    ],
    [
      "user_cards",
      "card_data",
      "user_card",
      "id,catalog_card_id,last_four_digits,is_active,created_at,updated_at",
    ],
  ] as const;
  for (const [table, feature, refType, columns] of cases) {
    const db = fakeDb({
      [table]: [{
        id: "target",
        user_id: "other",
        catalog_card_id: "catalog",
        metadata: { raw: "secret" },
        description: "raw statement line",
        file_path: "/secret.pdf",
        card_number: "4111",
      }],
    });
    await assertRejects(
      () => resolveFeedbackContext(db, "owner", feature, refType, "target"),
      Error,
      "not_found",
    );
    assertEquals(db.selects, [`${table}:${columns}`]);
  }
});

Deno.test("trace fixture copies authoritative facts and rejects foreign or expired traces", async () => {
  const future = new Date(Date.now() + 60_000).toISOString();
  const base = {
    id: "trace",
    user_id: "owner",
    feature_key: "recommendation",
    safe_input_context: { spend: 500 },
    output_snapshot: { provenance: "client_reported" },
    authoritative_context: {
      cards: [{ id: "card" }],
      benefits: [{ benefit_id: "benefit" }],
    },
    engine_version: "engine-v1",
    model: "m",
    prompt_version: "p",
    expires_at: future,
  };
  const resolved = await resolveFeedbackContext(
    fakeDb({ ai_output_traces: [base] }),
    "owner",
    "recommendation",
    "recommendation_trace",
    "trace",
  );
  assertEquals(resolved.authoritativeContext, base.authoritative_context);
  assertEquals(resolved.safeInputContext, {
    ...base.safe_input_context,
    task: "explain_fixed_selection",
  });
  assertEquals(
    JSON.stringify(resolved.safeInputContext).includes("client_reported"),
    false,
  );
  assertEquals(resolved.metadata.engine_version, "engine-v1");
  await assertRejects(
    () =>
      resolveFeedbackContext(
        fakeDb({ ai_output_traces: [base] }),
        "other",
        "recommendation",
        "recommendation_trace",
        "trace",
      ),
    Error,
    "not_found",
  );
  await assertRejects(
    () =>
      resolveFeedbackContext(
        fakeDb({
          ai_output_traces: [{
            ...base,
            expires_at: new Date(0).toISOString(),
          }],
        }),
        "owner",
        "recommendation",
        "recommendation_trace",
        "trace",
      ),
    Error,
    "not_found",
  );
});

Deno.test("recommendation catalog requires every card and benefit to remain active", async () => {
  const db = fakeDb({
    card_catalog: [{ id: "card", is_discontinued: false }],
    benefits: [{ benefit_id: "benefit", is_active: false }],
  });
  await assertRejects(
    () => resolveRecommendationCatalog(db, ["card"], ["benefit"]),
    Error,
    "not_found",
  );
});

Deno.test("transaction and statement fixtures contain bounded reproducible fields, not histories", async () => {
  const transaction = {
    id: "txn-1",
    user_id: "owner",
    user_card_id: "uc-1",
    statement_id: "st-1",
    amount: 1249,
    currency: "INR",
    merchant_name: "  Big Bazaar  ",
    category: "shopping",
    transaction_type: "debit",
    transaction_date: "2026-08-01",
    description: "secret raw line",
  };
  const resolved = await resolveFeedbackContext(
    fakeDb({ transactions: [transaction] }),
    "owner",
    "statement_processing",
    "transaction",
    "txn-1",
  );
  assertEquals(resolved.safeInputContext, {
    kind: "transaction",
    transaction: {
      id: "txn-1",
      user_card_id: "uc-1",
      statement_id: "st-1",
      amount: 1249,
      currency: "INR",
      merchant_name: "Big Bazaar",
      transaction_date: "2026-08-01",
    },
  });
  assertEquals(JSON.stringify(resolved).includes("secret raw line"), false);
  assertEquals(resolved.outputSnapshot.category, "shopping");
  assertEquals(resolved.outputSnapshot.transaction_type, "debit");
  assertEquals(
    JSON.stringify(resolved.safeInputContext).includes("shopping"),
    false,
  );

  const statement = await resolveFeedbackContext(
    fakeDb({
      statements: [{
        id: "st-1",
        user_id: "owner",
        user_card_id: "uc-1",
        statement_date: "2026-08-01",
        due_date: "2026-08-20",
        total_amount: 1000,
        minimum_payment: 100,
        closing_balance: 1000,
        fees_charged: 0,
        processed: true,
        transaction_count: 4,
      }],
    }),
    "owner",
    "statement_processing",
    "statement",
    "st-1",
  );
  assertEquals(statement.safeInputContext, {
    kind: "statement_requires_review",
    statement_id: "st-1",
  });
});

Deno.test("card fixture carries authoritative current identity facts", async () => {
  const resolved = await resolveFeedbackContext(
    fakeDb({
      user_cards: [{
        id: "uc-1",
        user_id: "owner",
        catalog_card_id: "card-1",
        last_four_digits: "1234",
        is_active: true,
        created_at: "x",
        updated_at: "y",
      }],
      card_catalog: [{
        id: "card-1",
        card_name: "Regalia Gold",
        bank: "HDFC",
        network: "Visa",
        card_type: "credit",
        annual_fee: 2500,
        joining_fee: 2500,
        is_discontinued: false,
        updated_at: "z",
      }],
      card_benefit_mapping: [{
        card_id: "card-1",
        benefit: {
          benefit_id: "benefit-1",
          title: "Lounge",
          description: "Four visits",
          benefit_category: "travel",
          value_config: { limit: 4 },
          valid_from: "2026-01-01",
          valid_until: null,
          updated_at: "z",
        },
      }],
    }),
    "owner",
    "card_data",
    "user_card",
    "uc-1",
  );
  assertEquals(resolved.safeInputContext, {
    kind: "card_requires_review",
    user_card_id: "uc-1",
    last_four_digits: "1234",
  });
  assertEquals((resolved.authoritativeContext.benefits as unknown[]).length, 1);
});

Deno.test("real provenance-shaped card feedback becomes a runnable immutable eval fixture", async () => {
  const rows = {
    user_cards: [{
      id: "uc-1",
      user_id: "owner",
      catalog_card_id: "card-1",
      last_four_digits: "1234",
      is_active: true,
    }],
    card_catalog: [{
      id: "card-1",
      card_name: "Regalia Gold",
      bank: "HDFC",
      network: "Visa",
      card_type: "credit",
      annual_fee: 2500,
      joining_fee: 2500,
      is_discontinued: false,
      updated_at: "2026-08-01",
    }],
    card_benefit_mapping: [],
    card_catalog_provenance: [{
      id: "source-1",
      card_id: "card-1",
      source_url: "https://hdfc.example/regalia",
      source_type: "official_html",
      extracted_fields: {
        issuer: "HDFC",
        cardName: "Regalia Gold",
        network: "Visa",
        aliases: ["Regalia Gold", "HDFC Regalia Gold"],
      },
      source_evidence: { excerpt: "Official Regalia Gold fees" },
    }],
  };
  const context = await resolveFeedbackContext(
    fakeDb(rows),
    "owner",
    "card_data",
    "user_card",
    "uc-1",
  );
  assertEquals(context.safeInputContext.kind, "card_data");
  assertEquals(
    context.safeInputContext.evaluation_mode,
    "catalog_identity_validation",
  );
  const result = await executeEvalCase(
    {
      caseId: "case-1",
      revision: 1,
      featureKey: "card_data",
      inputFixture: {
        safe_input_context: context.safeInputContext,
        authoritative_context: context.authoritativeContext,
      },
      capturedOutput: context.outputSnapshot,
    },
    "gemini-3.6-flash-card-data-v1",
    {
      generate: async () => ({
        model: "gemini-3.6-flash",
        inputTokens: 1,
        outputTokens: 1,
        latencyMs: 1,
        response: {
          mode: "identity",
          card: {
            id: "card-1",
            name: "Regalia Gold",
            bank: "HDFC",
            network: "Visa",
            annual_fee: 2500,
            joining_fee: 2500,
          },
          sources: [{
            id: "source-1",
            field_paths: [
              "facts.catalog_reference.id",
              "facts.provenance_claims.card_name",
              "facts.provenance_claims.issuer",
              "facts.provenance_claims.network",
              "facts.catalog_reference.annual_fee",
              "facts.catalog_reference.joining_fee",
            ],
          }],
        },
      }),
    },
  );
  assertEquals(result.executionStatus, "succeeded");
});
