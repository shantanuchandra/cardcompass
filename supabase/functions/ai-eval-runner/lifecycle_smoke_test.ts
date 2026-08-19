import { assertEquals } from "jsr:@std/assert@1";
import {
  handleAiEvalRunnerRequest,
  type RunnerDependencies,
  scheduleAiEvalContinuation,
} from "./index.ts";

// Opt-in because this creates and drops a disposable database on a loopback PostgreSQL server.
const adminUrl = Deno.env.get("CONTEXTUAL_EVAL_TEST_ADMIN_URL");

Deno.test({
  name:
    "real PostgreSQL lifecycle and real worker process more than five cases exactly once",
  ignore: !adminUrl,
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const url = new URL(adminUrl!);
    if (!["localhost", "127.0.0.1", "[::1]"].includes(url.hostname)) {
      throw new Error("integration_database_must_be_loopback");
    }
    const database = `cardcompass_worker_smoke_${Deno.pid}_${Date.now()}`;
    const adminDatabase = url.pathname.slice(1) || "postgres";
    const baseEnv = pgEnv(url, adminDatabase);
    const dbEnv = pgEnv(url, database);
    const roles = ["anon", "authenticated", "service_role"];
    const createdRoles: string[] = [];
    try {
      for (const role of roles) {
        if (
          runPsql(
            baseEnv,
            `select exists(select 1 from pg_roles where rolname='${role}');`,
          ) !== "t"
        ) {
          runPsql(baseEnv, `create role ${role} nologin;`);
          createdRoles.push(role);
        }
      }
      runPsql(baseEnv, `create database "${database}";`);
      const [foundation, feedback, evals] = await Promise.all([
        Deno.readTextFile(
          new URL(
            "../../migrations/20260819090000_admin_operator_foundation.sql",
            import.meta.url,
          ),
        ),
        Deno.readTextFile(
          new URL(
            "../../migrations/20260819090400_contextual_ai_feedback.sql",
            import.meta.url,
          ),
        ),
        Deno.readTextFile(
          new URL(
            "../../migrations/20260819090500_contextual_ai_eval_runs.sql",
            import.meta.url,
          ),
        ),
      ]);
      runPsql(
        dbEnv,
        `create extension if not exists pgcrypto; create schema auth; create table auth.users(id uuid primary key); ${foundation}\n${feedback}\n${evals}`,
      );
      seedCases(dbEnv);

      const dispatch = continuationCapture();
      const deps = postgresDependencies(dbEnv, dispatch);
      for (
        const [feature, config, expectedCases] of [
          ["statement_processing", "gemini-3.6-flash-statement-v1", 7],
          ["card_data", "gemini-3.6-flash-card-data-v1", 1],
          ["recommendation", "gemini-3.6-flash-recommendation-v1", 1],
        ] as const
      ) {
        const requestId = crypto.randomUUID();
        const receipt = queryJson(
          dbEnv,
          `select public.admin_create_ai_eval_run('10000000-0000-4000-8000-000000000001','${requestId}',1,'captured-production-v1','${config}','gemini-3.6-flash-blind-judge-v1',100,1.0,25000);`,
        );
        const runId = String(receipt.run_id);
        let response = await handleAiEvalRunnerRequest(
          workerRequest(runId),
          deps,
        );
        if (expectedCases > 5) {
          assertEquals(response.status, 202);
          assertEquals((await response.json()).continuation_required, true);
          await Promise.all(dispatch.background.splice(0));
          assertEquals(dispatch.requests.length, 1);
          const continued = dispatch.requests.shift()!;
          assertEquals(
            continued.url,
            "http://local.supabase/functions/v1/ai-eval-runner",
          );
          assertEquals(
            continued.headers.get("authorization"),
            "Bearer service-role-secret-that-is-long-enough",
          );
          assertEquals(await continued.clone().json(), { run_id: runId });
          response = await handleAiEvalRunnerRequest(
            continued,
            deps,
          );
        }
        assertEquals(response.status, 200);
        assertEquals((await response.json()).status, "completed");
        assertEquals(
          Number(
            runPsql(
              dbEnv,
              `select count(*) from public.ai_eval_results where run_id='${runId}';`,
            ),
          ),
          expectedCases,
        );
        assertEquals(
          Number(
            runPsql(
              dbEnv,
              `select count(*) from public.ai_eval_results where run_id='${runId}' and attempt_count<>1;`,
            ),
          ),
          0,
        );
        const summary = queryJson(
          dbEnv,
          `select jsonb_build_object('status',status,'metrics',aggregate_metrics,'tokens',token_usage,'cost',estimated_cost_usd) from public.ai_eval_runs where id='${runId}';`,
        );
        const judge = feature === "recommendation" ? 1 : 0;
        const perCaseCost = feature === "statement_processing"
          ? 0.000008
          : feature === "card_data"
          ? 0.000016
          : 0.000032;
        const expectedCost = perCaseCost * expectedCases;
        assertEquals(summary.status, "completed");
        assertEquals(summary.metrics, {
          case_count: expectedCases,
          succeeded: expectedCases,
          failed: 0,
          missing: 0,
          failure_categories: {},
          regressions: 0,
          severe_regressions: 0,
          average_latency_ms: feature === "recommendation" ? 29 : 17,
        });
        assertEquals(summary.tokens, {
          baseline_input: 0,
          baseline_output: 0,
          candidate_input: expectedCases * 7 + judge * 5,
          candidate_output: expectedCases * 3 + judge * 2,
        });
        assertEquals(summary.cost, expectedCost);
        assertEquals(
          queryJson(
            dbEnv,
            `select jsonb_build_object('count',count(*),'baseline_input',sum(baseline_input_tokens),'baseline_output',sum(baseline_output_tokens),'candidate_input',sum(candidate_input_tokens),'candidate_output',sum(candidate_output_tokens),'baseline_latency',sum(baseline_latency_ms),'candidate_latency',sum(candidate_latency_ms),'cost',sum(estimated_cost_usd),'min_cost',min(estimated_cost_usd),'max_cost',max(estimated_cost_usd),'attempts',sum(attempt_count)) from public.ai_eval_results where run_id='${runId}';`,
          ),
          {
            count: expectedCases,
            baseline_input: 0,
            baseline_output: 0,
            candidate_input: expectedCases * 7 + judge * 5,
            candidate_output: expectedCases * 3 + judge * 2,
            baseline_latency: 0,
            candidate_latency: expectedCases * 17 + judge * 12,
            cost: expectedCost,
            min_cost: perCaseCost,
            max_cost: perCaseCost,
            attempts: expectedCases,
          },
        );
        if (feature === "recommendation") {
          assertEquals(config.includes("recommendation"), true);
        }
        if (feature === "statement_processing") {
          assertEquals(
            Number(
              runPsql(
                dbEnv,
                `select count(*) from public.ai_eval_results where run_id='${runId}' and requires_review;`,
              ),
            ),
            0,
          );
          assertEquals(
            Number(
              runPsql(
                dbEnv,
                `select count(*) from public.ai_eval_results r cross join lateral jsonb_array_elements(r.deterministic_assertions) a where r.run_id='${runId}' and (a->>'baselinePassed')::boolean=false and (a->>'candidatePassed')::boolean=true;`,
              ),
            ) >= expectedCases,
            true,
          );
        }
        assertEquals(dispatch.requests.length, 0);
        assertEquals(dispatch.background.length, 0);
      }

      seedPassingStatementRevision(dbEnv);
      const severeReceipt = queryJson(
        dbEnv,
        `select public.admin_create_ai_eval_run('10000000-0000-4000-8000-000000000001','${crypto.randomUUID()}',2,'captured-production-v1','gemini-3.6-flash-statement-v1','gemini-3.6-flash-blind-judge-v1',100,1.0,25000);`,
      );
      const severeRunId = String(severeReceipt.run_id);
      const severeDispatch = continuationCapture();
      const severeDeps = postgresDependencies(
        dbEnv,
        severeDispatch,
        "regress",
      );
      let severeResponse = await handleAiEvalRunnerRequest(
        workerRequest(severeRunId),
        severeDeps,
      );
      assertEquals(severeResponse.status, 202);
      await Promise.all(severeDispatch.background.splice(0));
      assertEquals(severeDispatch.requests.length, 1);
      severeResponse = await handleAiEvalRunnerRequest(
        severeDispatch.requests.shift()!,
        severeDeps,
      );
      assertEquals((await severeResponse.json()).status, "completed");
      const severeSummary = queryJson(
        dbEnv,
        `select jsonb_build_object('metrics',aggregate_metrics,'tokens',token_usage,'cost',estimated_cost_usd) from public.ai_eval_runs where id='${severeRunId}';`,
      );
      assertEquals(severeSummary, {
        metrics: {
          case_count: 7,
          succeeded: 7,
          failed: 0,
          missing: 0,
          failure_categories: {},
          regressions: 7,
          severe_regressions: 7,
          average_latency_ms: 17,
        },
        tokens: {
          baseline_input: 0,
          baseline_output: 0,
          candidate_input: 49,
          candidate_output: 21,
        },
        cost: 0.000056,
      });
      assertEquals(
        queryJson(
          dbEnv,
          `select jsonb_build_object('count',count(*),'baseline_input',sum(baseline_input_tokens),'baseline_output',sum(baseline_output_tokens),'candidate_input',sum(candidate_input_tokens),'candidate_output',sum(candidate_output_tokens),'baseline_latency',sum(baseline_latency_ms),'candidate_latency',sum(candidate_latency_ms),'cost',sum(estimated_cost_usd),'min_cost',min(estimated_cost_usd),'max_cost',max(estimated_cost_usd),'attempts',sum(attempt_count)) from public.ai_eval_results where run_id='${severeRunId}';`,
        ),
        {
          count: 7,
          baseline_input: 0,
          baseline_output: 0,
          candidate_input: 49,
          candidate_output: 21,
          baseline_latency: 0,
          candidate_latency: 119,
          cost: 0.000056,
          min_cost: 0.000008,
          max_cost: 0.000008,
          attempts: 7,
        },
      );
      assertEquals(
        Number(
          runPsql(
            dbEnv,
            `select count(*) from public.ai_eval_results where run_id='${severeRunId}' and requires_review;`,
          ),
        ),
        7,
      );
      assertEquals(severeDispatch.requests.length, 0);
      assertEquals(severeDispatch.background.length, 0);
    } finally {
      try {
        runPsql(baseEnv, `drop database if exists "${database}" with (force);`);
      } finally {
        for (const role of createdRoles.reverse()) {
          runPsql(baseEnv, `drop role if exists ${role};`);
        }
      }
    }
  },
});

function workerRequest(runId: string) {
  return new Request("http://localhost/ai-eval-runner", {
    method: "POST",
    headers: {
      authorization: "Bearer service-role-secret-that-is-long-enough",
      "content-type": "application/json",
    },
    body: JSON.stringify({ run_id: runId }),
  });
}

function postgresDependencies(
  env: Record<string, string>,
  dispatch: ReturnType<typeof continuationCapture>,
  mode: "improve" | "regress" = "improve",
): RunnerDependencies {
  const rpc: RunnerDependencies["rpc"] = (name, args) => {
    const calls: Record<string, string> = {
      claim_ai_eval_run_batch: `select public.claim_ai_eval_run_batch(${
        literal(args._run_id)
      },${Number(args._batch_limit)});`,
      record_ai_eval_result: `select public.record_ai_eval_result(${
        literal(args._run_id)
      },${literal(args._lease_token)},${literal(args._case_id)},${
        Number(args._case_revision)
      },${literal(JSON.stringify(args._result))}::jsonb);`,
      yield_ai_eval_run: `select public.yield_ai_eval_run(${
        literal(args._run_id)
      },${literal(args._lease_token)});`,
      finish_ai_eval_run: `select public.finish_ai_eval_run(${
        literal(args._run_id)
      },${literal(args._lease_token)});`,
    };
    return Promise.resolve(queryJson(env, calls[name]));
  };
  return {
    serviceRoleSecret: "service-role-secret-that-is-long-enough",
    rpc,
    loadCase: (id, revision) =>
      Promise.resolve(
        queryJson(
          env,
          `select jsonb_build_object('caseId',id,'revision',revision,'featureKey',feature_key,'inputFixture',input_fixture,'capturedOutput',captured_output,'expectedOutput',expected_output,'operatorFeedback',operator_feedback,'scoringRubric',scoring_rubric,'severeFailureConditions',severe_failure_conditions) from public.ai_eval_cases where id=${
            literal(id)
          } and revision=${revision};`,
        ) as any,
      ),
    readRunState: (id) =>
      Promise.resolve(
        queryJson(
          env,
          `select jsonb_build_object('status',status,'leaseToken',lease_token) from public.ai_eval_runs where id=${
            literal(id)
          };`,
        ) as any,
      ),
    generate: async (input) => {
      const system = String(
        (input.payload as any).systemInstruction.parts[0].text,
      );
      if (system.startsWith("Blindly compare")) {
        const text = String((input.payload as any).contents[0].parts[0].text);
        const a = JSON.parse(
          text.match(
            /BEGIN_UNTRUSTED_OUTPUT_A\n(.+)\nEND_UNTRUSTED_OUTPUT_A/,
          )![1],
        );
        const winner = a.includes("Clear candidate") ? "A" : "B";
        return {
          model: input.model,
          response: {
            winner,
            confidence: 0.95,
            explanation: "Candidate is clearer within fixed-selection scope.",
          },
          inputTokens: 5,
          outputTokens: 2,
          latencyMs: 12,
        };
      }
      const text = String((input.payload as any).contents[0].parts[0].text);
      const fixture = JSON.parse(
        text.match(
          /BEGIN_UNTRUSTED_INPUT_FIXTURE\n(.+)\nEND_UNTRUSTED_INPUT_FIXTURE/,
        )![1],
      );
      let response: Record<string, unknown>;
      if (fixture.safe_input_context.kind === "transaction") {
        response = {
          ...fixture.safe_input_context.transaction,
          category: mode === "regress" ? "travel" : "shopping",
          transaction_type: "debit",
        };
      } else if (fixture.safe_input_context.kind === "card_data") {
        const source = fixture.safe_input_context.official_sources[0];
        const reference = source.facts.catalog_reference;
        response = {
          mode: "identity",
          card: {
            id: reference.id,
            name: reference.name,
            bank: reference.bank,
            network: reference.network,
            annual_fee: reference.annual_fee,
            joining_fee: reference.joining_fee,
          },
          sources: [{
            id: source.id,
            field_paths: [
              "facts.catalog_reference.id",
              "facts.provenance_claims.card_name",
              "facts.provenance_claims.issuer",
              "facts.catalog_reference.network",
              "facts.catalog_reference.annual_fee",
              "facts.catalog_reference.joining_fee",
            ],
          }],
        };
      } else {
        response = {
          selected_card_id: "card-1",
          selected_benefit_id: "benefit-1",
          savings: 200,
          final_amount: 600,
          explanation:
            "Clear candidate explanation: save INR 200 on the fixed selection.",
        };
      }
      return {
        model: input.model,
        response,
        inputTokens: 7,
        outputTokens: 3,
        latencyMs: 17,
      };
    },
    scheduleContinuation: (id) =>
      scheduleAiEvalContinuation(
        "http://local.supabase",
        "service-role-secret-that-is-long-enough",
        id,
        async (input, init) => {
          dispatch.requests.push(new Request(input, init));
          return Response.json({ accepted: true }, { status: 202 });
        },
      ),
    waitUntil: (promise) => dispatch.background.push(promise),
  };
}

function continuationCapture() {
  return {
    requests: [] as Request[],
    background: [] as Promise<unknown>[],
  };
}

function seedCases(env: Record<string, string>) {
  const statementFixture = (i: number) => ({
    safe_input_context: {
      kind: "transaction",
      transaction: {
        id: `txn-${i}`,
        user_card_id: "uc-1",
        statement_id: "st-1",
        amount: 100 + i,
        currency: "INR",
        merchant_name: "Store",
        transaction_date: "2026-08-01",
      },
    },
    authoritative_context: {},
  });
  const statementOutput = (i: number, category: string) => ({
    id: `txn-${i}`,
    user_card_id: "uc-1",
    statement_id: "st-1",
    amount: 100 + i,
    currency: "INR",
    merchant_name: "Store",
    category,
    transaction_type: "debit",
    transaction_date: "2026-08-01",
  });
  const cardFixture = {
    safe_input_context: {
      kind: "card_data",
      evaluation_mode: "catalog_identity_validation",
      identifiers: {
        entered_name: "Regalia Gold",
        issuer_hint: "HDFC",
        last_four_digits: "1234",
      },
      official_sources: [{
        id: "source-1",
        url: "https://bank.example/card",
        snippet: "Regalia Gold",
        facts: {
          evaluation_mode: "catalog_identity_validation",
          provenance_claims: {
            issuer: "HDFC",
            card_name: "Regalia Gold",
            network: "Visa",
            aliases: ["Regalia Gold"],
          },
          catalog_reference: {
            id: "card-1",
            name: "Regalia Gold",
            bank: "HDFC",
            network: "Visa",
            annual_fee: 2500,
            joining_fee: 2500,
          },
        },
      }],
    },
    authoritative_context: {},
  };
  const cardCaptured = {
    user_card: {
      id: "uc-1",
      catalog_card_id: "card-1",
      last_four_digits: "1234",
      is_active: true,
      created_at: "x",
      updated_at: "y",
    },
    catalog_card: {
      id: "card-1",
      card_name: "Regalia Gold",
      bank: "HDFC",
      network: "Visa",
      card_type: "credit",
      annual_fee: 2500,
      joining_fee: 2500,
      is_discontinued: false,
      updated_at: "2026-08-01",
    },
  };
  const recommendationFixture = {
    safe_input_context: {
      number_of_tickets: 2,
      price_per_ticket: 400,
      task: "explain_fixed_selection",
    },
    authoritative_context: {
      cards: [{ id: "card-1" }],
      benefits: [{
        benefit_id: "benefit-1",
        value_config: {
          discount_percent: 25,
          max_discount_per_transaction: 200,
        },
      }],
      owned_card_ids: ["card-1"],
    },
  };
  runPsql(
    env,
    `insert into auth.users values ('10000000-0000-4000-8000-000000000001');`,
  );
  for (let i = 1; i <= 7; i++) {
    insertCase(
      env,
      "statement_processing",
      i,
      statementFixture(i),
      statementOutput(i, "other"),
      statementOutput(i, "shopping"),
      {
        assertions: [{
          key: "category",
          path: "$.category",
          operator: "equals",
          expectedPath: "$.category",
        }],
      },
      { assertionKeys: ["category"] },
    );
  }
  insertCase(env, "card_data", 20, cardFixture, cardCaptured, {
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
        "facts.catalog_reference.network",
        "facts.catalog_reference.annual_fee",
        "facts.catalog_reference.joining_fee",
      ],
    }],
  }, {
    assertions: [{
      key: "catalog",
      path: "$.card.id",
      operator: "catalog_id",
      expectedPath: "$.card.id",
    }],
  }, { assertionKeys: ["catalog"] });
  insertCase(env, "recommendation", 30, recommendationFixture, {
    selected_card_id: "card-1",
    selected_benefit_id: "benefit-1",
    savings: 200,
    final_amount: 600,
    explanation: "Baseline explanation.",
  }, {
    selected_card_id: "card-1",
    selected_benefit_id: "benefit-1",
    savings: 200,
    final_amount: 600,
    explanation: "Expected.",
  }, {
    assertions: [{
      key: "savings",
      path: "$.savings",
      operator: "money",
      expectedPath: "$.savings",
    }],
    explanationCriteria: [
      "Explain fixed-selection savings; do not claim ranking.",
    ],
  }, { assertionKeys: ["savings"] });
}

function seedPassingStatementRevision(env: Record<string, string>) {
  for (let i = 1; i <= 7; i++) {
    const prior = `50000000-0000-4000-8000-${String(i).padStart(12, "0")}`;
    const revised = `70000000-0000-4000-8000-${String(i).padStart(12, "0")}`;
    const captured = {
      id: `txn-${i}`,
      user_card_id: "uc-1",
      statement_id: "st-1",
      amount: 100 + i,
      currency: "INR",
      merchant_name: "Store",
      category: "shopping",
      transaction_type: "debit",
      transaction_date: "2026-08-01",
    };
    runPsql(
      env,
      `insert into public.ai_eval_cases(id,source_feedback_id,feature_key,revision,supersedes_case_id,input_fixture,captured_output,expected_output,operator_feedback,scoring_rubric,severe_failure_conditions,status,approved_in_dataset_version,created_by) select '${revised}',source_feedback_id,feature_key,2,'${prior}',input_fixture,${
        literal(JSON.stringify(captured))
      }::jsonb,expected_output,operator_feedback,scoring_rubric,severe_failure_conditions,'approved',2,created_by from public.ai_eval_cases where id='${prior}';`,
    );
  }
}

function insertCase(
  env: Record<string, string>,
  feature: string,
  n: number,
  fixture: unknown,
  captured: unknown,
  expected: unknown,
  rubric: unknown,
  severe: unknown,
) {
  const feedback = `30000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
  const caseId = `50000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
  const request = `40000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
  runPsql(
    env,
    `insert into public.ai_feedback(id,user_id,feature_key,output_ref_type,output_ref_id,feedback_text,request_id) values('${feedback}','10000000-0000-4000-8000-000000000001','${feature}','${
      feature === "card_data"
        ? "user_card"
        : feature === "recommendation"
        ? "recommendation_trace"
        : "transaction"
    }','ref-${n}','bounded feedback','${request}'); insert into public.ai_eval_cases(id,source_feedback_id,feature_key,revision,input_fixture,captured_output,expected_output,operator_feedback,scoring_rubric,severe_failure_conditions,status,approved_in_dataset_version,created_by) values('${caseId}','${feedback}','${feature}',1,${
      literal(JSON.stringify(fixture))
    }::jsonb,${literal(JSON.stringify(captured))}::jsonb,${
      literal(JSON.stringify(expected))
    }::jsonb,'bounded feedback',${literal(JSON.stringify(rubric))}::jsonb,${
      literal(JSON.stringify(severe))
    }::jsonb,'approved',1,'10000000-0000-4000-8000-000000000001');`,
  );
}

function literal(value: unknown) {
  return `'${String(value).replaceAll("'", "''")}'`;
}
function queryJson(env: Record<string, string>, sql: string): any {
  return JSON.parse(runPsql(env, sql));
}
function pgEnv(url: URL, database: string) {
  const env: Record<string, string> = {
    PATH: Deno.env.get("PATH") ?? "",
    PGHOST: url.hostname,
    PGPORT: url.port || "5432",
    PGDATABASE: database,
    PGPASSFILE: "/dev/null",
    PGSERVICEFILE: "/dev/null",
  };
  if (url.username) env.PGUSER = decodeURIComponent(url.username);
  if (url.password) env.PGPASSWORD = decodeURIComponent(url.password);
  return env;
}
function runPsql(env: Record<string, string>, sql: string) {
  const input = Deno.makeTempFileSync({
    prefix: "cardcompass-eval-",
    suffix: ".sql",
  });
  try {
    Deno.writeTextFileSync(input, sql);
    const { code, stdout, stderr } = new Deno.Command("psql", {
      args: ["-X", "-A", "-t", "--set", "ON_ERROR_STOP=1", "--file", input],
      env,
      stdout: "piped",
      stderr: "piped",
    }).outputSync();
    if (code !== 0) {
      throw new Error(
        new TextDecoder().decode(stderr).replaceAll(
          Deno.env.get("CONTEXTUAL_EVAL_TEST_ADMIN_URL") ?? "",
          "[REDACTED]",
        ),
      );
    }
    return new TextDecoder().decode(stdout).trim();
  } finally {
    Deno.removeSync(input);
  }
}
