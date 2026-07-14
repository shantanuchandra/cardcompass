# Evidence-grounded benefit repair pass

## Objective

After the first LLM extraction, run a narrowly scoped second LLM call only for
material, source-backed claims that were omitted or whose qualifiers were lost.
The second pass must create review candidates only; it must never alter active
benefit mappings or the database schema.

## Guardrails

- Keep `benefits` as the canonical benefit catalogue and
  `card_benefit_mapping` as the only card-to-benefit relationship.
- Do not create tables or change schema.
- Do not auto-approve or apply any repaired candidate.
- Give the repair model only deterministic evidence targets, require verbatim
  evidence, and reject output that cannot be tied to a target.
- Preserve the source text for review and validate repaired candidates through
  the existing grounding validator before staging.

## Tasks

1. Add evidence segmentation tests that retain monetary abbreviations such as
   `Rs.` and preserve the complete source clause used for grounding.
2. Implement the evidence segmenter and use it for source-coverage validation.
3. Add tests for selecting only material missing/incomplete claims as repair
   targets, excluding headings and generic text.
4. Implement a repair service that produces scoped targets, merges only
   grounded repair candidates, and records repair metadata in the staged JSON.
5. Add a typed second-pass LLM prompt and response parser to the existing AI
   provider path, so Gemini/Ollama use the same configured provider.
6. Wire the repair pass after the initial extraction and before staging;
   revalidate the merged data and gracefully retain the first-pass result if
   the repair call fails.
7. Show repaired candidates as clearly labelled items in the existing review
   flow, retaining individual and bulk decisions.
8. Run focused tests, then a web build. Do not use Docker or change database
   schema/data.
