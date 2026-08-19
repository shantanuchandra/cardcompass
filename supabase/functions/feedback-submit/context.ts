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
    return {
      safeInputContext: { transaction_id: row.id },
      outputSnapshot: row,
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
    return {
      safeInputContext: { statement_id: row.id },
      outputSnapshot: row,
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
    return {
      safeInputContext: { user_card_id: row.id },
      outputSnapshot: { user_card: row, catalog_card: catalog },
      authoritativeContext: { catalog_card: catalog },
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
      safeInputContext: trace.safe_input_context,
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
