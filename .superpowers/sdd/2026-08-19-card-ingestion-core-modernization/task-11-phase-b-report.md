# Task 11 Phase B — Lifecycle semantics and issuer discovery state

## Scope and safety

This slice implements only Phase B items 1–8 from `task-11-brief.md`. The task's
original baseline is `5d4c10f`; this scoped working diff was completed after the
shared Phase A commit `3c2ead8`. It did not use Docker, a local or linked
database, the network, function serving, issuer crawling, or any production
action. The Task 7 migration was amended only as a locally unapplied input and
was not executed by this slice.

No business table, column, constraint, or index changed. The minimum persistence
change is confined to the existing `card_discovery_jobs.evidence` JSON fence and
the existing review source-observation JSON: each quarantine occurrence now
carries a bounded integer `episode` and an opaque `episode_identity`. A live
issuer-scan plan is deliberately deferred; no speculative index was added.

## Closure matrix

| Item                             | Closure                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        | Proof                                                                                                                                                                                                        |
| -------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 1. Lifecycle transport semantics | TypeScript and SQL recursively normalize key spelling and strip content hashes, ETag, last-modified, not-modified, timestamps, transport envelopes, bare/suffixed URLs, URL hashes, and resource/source identity hashes from lifecycle meaning. Branches made empty solely by stripping transport data are removed, so a changed number of fetch attempts cannot create work; explicitly empty semantic containers remain preserved. The separately supplied source URL hash remains part of lifecycle review staging authority. Meaning changes still create distinct semantics.                                                                              | Shared behavioral transport-churn/change test with differing attempt counts; executable Task 7 migration assertion over nested snake/camel/hyphen keys, bare/suffixed identities, and transport-only arrays. |
| 2. Foreign card subjects         | Explicit subjects for another card remain foreign when wrapped in ASCII/Unicode quotes, brackets, or parentheses. Neutral target-specific wording remains eligible for target lifecycle evidence.                                                                                                                                                                                                                                                                                                                                                                                                                                                              | Shared behavioral subject matrix covering quoted/bracketed sibling cards and neutral controls.                                                                                                               |
| 3. Exact producer shape          | Stable scans accept only the exact deterministic dedupe key or `issuer_directory_anchor` evidence with matching issuer identity. Legacy scans accept only `issuer_directory_run`. Ordinary identity, lifecycle, catalog-review, and candidate-outcome Task 7 rows are never swept into producer reconciliation. SQL locks only explicit producer kinds; before Retry can make a producer claimable it additionally validates issuer, canonical official URL, run date, attempt bound, and the current-anchor deterministic key. Reject remains available for intentionally quarantined corrupt evidence.                                                       | Behavioral ordinary-row immutability and corrupt-producer controls; Task 7 Retry shape binding.                                                                                                              |
| 4. Deadline fences               | Approved-catalog, due-backlog, stable-anchor, and legacy scans share the invocation budget and check it before and after every awaited query, including every final short page. Candidate selection, claim, migration, insert, fence transition, clearing, and review staging paths recheck before mutation/completion and after awaited database work.                                                                                                                                                                                                                                                                                                        | Behavioral final-short-page catalog/backlog/anchor no-selection or no-mutation tests and post-transition staging-stop test.                                                                                  |
| 5. Deterministic paging          | Stable and legacy producer history uses primary-key keyset paging (`id > cursor`) over true producer rows, with cursor monotonicity guards and exact-ID deduplication. The scan has no OFFSET and no speculative index.                                                                                                                                                                                                                                                                                                                                                                                                                                        | Behavioral 1,005-row scan with an earlier concurrent insertion proves each original row is read exactly once.                                                                                                |
| 6. Quarantine episodes           | The producer fence persists a monotonic integer episode and semantic identity for new occurrences. Same-occurrence concurrency shares one review dedupe identity; admin Retry leaves the prior terminal review/audit immutable, and the next failure advances the episode and stages exactly one new pending review. A recoverable pre-episode item is normalized coherently to the SQL compatibility shape: legacy semantic identity with a null producer episode and null review episode identity. That preserves the legacy dedupe job, remains Retry/Reject-actionable, and replays without another write. New occurrences require the versioned identity. | Behavioral Retry → re-quarantine concurrency, recoverable/terminal legacy single-item replay, exact TS-to-SQL action shape, and Task 7 full-fence binding.                                                   |
| 7. Persisted conflict counts     | Response conflict accounting is derived from the reason on the persisted winning fence, never the caller's stale pre-fence classification.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     | Behavioral caller/persisted reason-disagreement test.                                                                                                                                                        |
| 8. Later-task closures           | Exact functional resource identity, current/legacy URL conflict handling, nested sitemap incompleteness, fair issuer rotation, microsecond review timestamps, and paginated quarantine review behavior remain in the affected suites.                                                                                                                                                                                                                                                                                                                                                                                                                          | Full affected Deno and Node gates below.                                                                                                                                                                     |

## Red → green record

The required behavior was first exercised as failing behavioral tests:

- Nested transport churn versus a real lifecycle change failed because embedded
  transport keys survived semantic projection.
- A changed number of nested transport-only attempt objects left different empty
  array shells after field stripping and still changed lifecycle identity.
- Wrapped foreign card subjects failed because opening punctuation prevented the
  sibling-card subject match.
- Ordinary same-issuer Task 7 rows prevented a clean producer claim.
- A final short producer page crossed its deadline and still completed.
- Final short approved-catalog and due-backlog pages crossed the deadline and
  still advanced toward issuer selection.
- A 1,005-row producer history with an earlier concurrent insertion duplicated
  an original row under OFFSET paging.
- Retry followed by a later concurrent failure reused the first episode.
- A pre-episode pending review computed a different review-job dedupe key and
  would have been duplicated during mixed deployment.
- Review found that a normally terminal pre-episode pending item could not pass
  the new SQL episode validation.
- Consolidated review found that recoverable pre-episode state mixed a derived
  integer episode with the unsuffixed legacy identity, which neither the next
  TypeScript read nor Task 7 Retry/Reject accepts.
- Caller/persisted quarantine-reason disagreement reported the caller's conflict
  count.

After implementation, the fresh affected gates passed:

- `index_test.ts` + catalog publication + issuer crawl: **207/207**.
- Cross-slice shared + batch + supporting integration: **210/210**.
- Issuer discovery/crawl rules + Task 7 migration tests: **108/108**.
- Task 7 migration-only suite: **35/35**.
- Deno production type check: **3/3 files**.
- Deno format check: **8/8 files**.
- `git diff --check`: pass.

The migration regex test is supplemental. PostgreSQL-executable migration
assertions compare transport-only replay semantics against a material lifecycle
change and inspect the source-identity and quarantine-episode bindings.

## Independent review

The initial scoped review found three Important gaps: terminal pre-episode admin
compatibility, missing catalog/backlog post-query deadline fences, and
insufficient Retry-time producer validation. Fix round 1 closed all three,
including the deliberate distinction that Reject must remain available for
corrupt nonretryable producer evidence. The same reviewer returned **Ready —
Yes**, with no remaining Critical, Important, or Minor findings. A later
consolidated review found one Important mixed-deployment compatibility bug. The
follow-up red/green regression now proves that recovery writes one coherent
legacy/null producer and review shape accepted by Task 7, retains the exact
Retry policy binding, and performs no restaging or rewrite on replay.

## Migration hash

- `20260819231435_publish_reviewed_card_identity.sql`:
  `bc4518cd4ba5ca1e9000ad07cf36cb7b2a667bedba520eee8efaf2d17f2b0dc9`

This is a local source hash, not a remote migration-history claim.

## Exact durable producer and episode contracts

A current issuer-directory producer has all of these properties:

- `user_id IS NULL` and `discovery_source = 'issuer_crawl'`;
- deterministic issuer anchor `dedupe_key`, or producer evidence kind
  `issuer_directory_anchor` with the same normalized issuer;
- bounded producer evidence containing the issuer, canonical URL, run date, and
  lease/run state.

Only `issuer_directory_run` is accepted by the bounded legacy reconciliation
lane. Review/candidate evidence shapes are not inferred from issuer, status,
attempt count, or review linkage.

The persisted quarantine fence binds `anchor_job_id`, normalized issuer,
classification, reason, retry policy, episode, and semantic identity. New
identities have the form
`issuer-discovery-quarantine-v1:<anchor UUID>:<episode>`. A pre-episode legacy
identity is accepted only as derived episode one. Recovery preserves its legacy
review dedupe identity and normalizes both sides of Task 7's compatibility
branch: the producer episode and review `episode_identity` are null while the
fence semantic identity remains unsuffixed. Episode two and later require the
new form.

## Deferred verification

Real PostgreSQL parsing/apply assertions, role execution, two-session episode
and claim concurrency, linked migration-history/hash validation, hosted cleanup,
and representative live `EXPLAIN (ANALYZE, BUFFERS)` remain in Task 11's guarded
hosted phases. This slice makes no live database or performance claim.
