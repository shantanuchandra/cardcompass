export type SafeContext = Readonly<
  {
    safeInputContext: Record<string, unknown>;
    outputSnapshot: Record<string, unknown>;
    authoritativeContext: Record<string, unknown>;
    metadata: Record<string, unknown>;
  }
>;

async function one(
  db: any,
  table: string,
  columns: string,
  id: string,
  userId?: string,
) {
  let query = db.from(table).select(columns).eq("id", id);
  if (userId) query = query.eq("user_id", userId);
  const { data, error } = await query.maybeSingle();
  if (error) throw new Error("request_failed");
  if (!data) throw Object.assign(new Error("not_found"), { status: 404 });
  return data;
}

export async function resolveFeedbackContext(
  db: any,
  userId: string,
  feature: string,
  refType: string,
  refId: string,
): Promise<SafeContext> {
  if (refType === "transaction") {
    const row = await one(
      db,
      "transactions",
      "id,user_card_id,amount,currency,merchant_name,category,transaction_type,transaction_date,statement_id",
      refId,
      userId,
    );
    const transaction = {
      id: row.id,
      user_card_id: row.user_card_id,
      statement_id: row.statement_id,
      amount: row.amount,
      currency: row.currency,
      merchant_name: boundedText(row.merchant_name, 200),
      transaction_date: row.transaction_date,
    };
    return {
      safeInputContext: { kind: "transaction", transaction },
      outputSnapshot: {
        ...transaction,
        category: row.category,
        transaction_type: row.transaction_type,
      },
      authoritativeContext: {},
      metadata: { parser_version: "persisted_transaction_v1" },
    };
  }
  if (refType === "statement") {
    const row = await one(
      db,
      "statements",
      "id,user_card_id,statement_date,due_date,total_amount,minimum_payment,closing_balance,fees_charged,processed,transaction_count",
      refId,
      userId,
    );
    const statement = {
      id: row.id,
      user_card_id: row.user_card_id,
      statement_date: row.statement_date,
      due_date: row.due_date,
      total_amount: row.total_amount,
      minimum_payment: row.minimum_payment,
      closing_balance: row.closing_balance,
      fees_charged: row.fees_charged,
      processed: row.processed,
      transaction_count: row.transaction_count,
    };
    return {
      safeInputContext: {
        kind: "statement_requires_review",
        statement_id: row.id,
      },
      outputSnapshot: statement,
      authoritativeContext: {},
      metadata: { parser_version: "persisted_statement_v1" },
    };
  }
  if (refType === "user_card") {
    const row = await one(
      db,
      "user_cards",
      "id,catalog_card_id,last_four_digits,is_active,created_at,updated_at",
      refId,
      userId,
    );
    const catalog = await one(
      db,
      "card_catalog",
      "id,card_name,bank,network,card_type,annual_fee,joining_fee,is_discontinued,updated_at",
      row.catalog_card_id,
    );
    const { data: mappings, error: benefitsError } = await db
      .from("card_benefit_mapping")
      .select(
        "benefit:benefits(benefit_id,title,description,benefit_category,value_config,valid_from,valid_until,updated_at)",
      )
      .eq("card_id", row.catalog_card_id);
    if (benefitsError) throw new Error("request_failed");
    const benefits = (mappings ?? []).slice(0, 50)
      .map((entry: Record<string, unknown>) => entry.benefit)
      .filter((entry: unknown) => entry && typeof entry === "object");
    return {
      safeInputContext: {
        kind: "card_requires_review",
        user_card_id: row.id,
        last_four_digits: boundedText(row.last_four_digits, 4),
      },
      outputSnapshot: { user_card: row, catalog_card: catalog },
      authoritativeContext: { catalog_card: catalog, benefits },
      metadata: { parser_version: "persisted_card_match_v1" },
    };
  }
  if (feature === "recommendation" && refType === "recommendation_trace") {
    const trace = await one(
      db,
      "ai_output_traces",
      "id,user_id,feature_key,safe_input_context,output_snapshot,authoritative_context,engine_version,model,prompt_version,expires_at",
      refId,
      userId,
    );
    if (
      trace.feature_key !== "recommendation" ||
      new Date(trace.expires_at).getTime() <= Date.now()
    ) throw Object.assign(new Error("not_found"), { status: 404 });
    return {
      safeInputContext: {
        ...trace.safe_input_context,
        task: "explain_fixed_selection",
      },
      outputSnapshot: trace.output_snapshot,
      authoritativeContext: trace.authoritative_context,
      metadata: {
        trace_id: trace.id,
        engine_version: trace.engine_version,
        model: trace.model,
        prompt_version: trace.prompt_version,
      },
    };
  }
  throw new Error("invalid_request");
}

function boundedText(value: unknown, maximum: number): string | null {
  if (typeof value !== "string") return null;
  return value.trim().slice(0, maximum);
}

export async function resolveRecommendationCatalog(
  db: any,
  cardIds: string[],
  benefitIds: string[],
) {
  const cards = cardIds.length
    ? await db.from("card_catalog").select(
      "id,card_name,bank,network,annual_fee,joining_fee,updated_at",
    ).in("id", cardIds).eq("is_discontinued", false)
    : { data: [], error: null };
  const benefits = benefitIds.length
    ? await db.from("benefits").select(
      "benefit_id,title,description,benefit_category,value_config,valid_from,valid_until,updated_at",
    ).in("benefit_id", benefitIds).eq("is_active", true)
    : { data: [], error: null };
  if (cards.error || benefits.error) throw new Error("request_failed");
  if (
    (cards.data?.length ?? 0) !== new Set(cardIds).size ||
    (benefits.data?.length ?? 0) !== new Set(benefitIds).size
  ) throw Object.assign(new Error("not_found"), { status: 404 });
  return { cards: cards.data ?? [], benefits: benefits.data ?? [] };
}
