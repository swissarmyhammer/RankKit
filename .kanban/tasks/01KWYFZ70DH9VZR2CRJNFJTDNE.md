---
comments:
- actor: claude-code
  id: 01kxdx1rrwytvgj1v1hf3zaw0r
  text: |-
    Implemented via TDD:

    - Wrote `Tests/RankKitTests/BM25Tests.swift` first (RED — `BM25`/`BM25Corpus` not in scope, confirmed via `swift test` compile failure), containing two structs: `BM25Tests` ported verbatim from FoundationModelsMetadataRegistry's `BM25Tests.swift`, and `BM25RankerTests` ported from CodeContextKit's `RankerTests.swift` BM25 section plus its golden-ordering fused-BM25+trigram case — both repos' cases kept per plan.md §5, only constant names/imports changed (test method names left as in source, only the renamed constants themselves and the two-field-weight prose were neutralized).
    - Wrote `Sources/RankKit/BM25.swift` (GREEN) — `BM25Corpus`/`score(...)` are byte-identical logic to both source copies; only the two field-weight constants are renamed to `BM25.primaryFieldWeight` (5.0) and `BM25.bodyFieldWeight` (1.0), doc comments rewritten neutrally (no ids/blocks/symbol paths).
    - `swift test`: 67 tests, 5 suites, all green, 0 failures.
    - Ran adversarial double-check (subagent). Verdict: REVISE with one low-severity, documentation-only finding — the attribution header cited an invented `plan.md §3 "Port, don't depend"` quote that doesn't match plan.md's actual §3 heading ("Package design") or the sibling ported files' simpler `(plan.md §3)` citation style. Fixed by dropping the invented quote to match sibling convention (`Trigram.swift`, `Hit.swift`). Re-ran `swift test` after the fix — still 67/67 green.

    All acceptance criteria met: `BM25.primaryFieldWeight == 5.0`, `BM25.bodyFieldWeight == 1.0` (asserted in `fieldWeightConstantsMatchPlanSpec`), scoring behavior identical to both existing copies, no domain language in doc comments (verified by grep for chunk/symbol/catalog/metadata — none found).

    Leaving in `doing` for review per /implement workflow — not moving to review myself.
  timestamp: 2026-07-13T14:10:44.124828+00:00
depends_on:
- 01KWYFYV2BQ968Y1RHQXRSP6NQ
position_column: doing
position_ordinal: '80'
title: Port BM25 with neutral field-weight names
---
## What
Copy `../FoundationModelsMetadataRegistry/Sources/FoundationModelsMetadataRegistry/Search/BM25.swift` → `Sources/RankKit/BM25.swift`, applying the one deliberate rename (plan.md §4.1):
- `idFieldWeight` → `primaryFieldWeight` (value stays `5.0`)
- `blockFieldWeight` → `bodyFieldWeight` (value stays `1.0`)

Rewrite the constants' doc comments neutrally ("primary field" / "body field" — no ids, blocks, symbol paths). Strip the port-attribution header like the other files. `BM25Corpus` and `score(...)` stay byte-identical.

After this and the other two port tasks are green, push RankKit `main` to GitHub so consumers can resolve the remote dependency when they migrate (their migration is planned separately, in their own repos).

## Acceptance Criteria
- [x] `BM25.primaryFieldWeight == 5.0`, `BM25.bodyFieldWeight == 1.0`
- [x] Scoring behavior identical to both existing copies (ported tests pass unmodified apart from constant names/imports)
- [x] No domain language in doc comments

## Tests
- [x] Port the BM25 cases from `../CodeContextKit/Tests/CodeContextKitTests/RankerTests.swift` AND from `../FoundationModelsMetadataRegistry/Tests/FoundationModelsMetadataRegistryTests/BM25Tests.swift` to `Tests/RankKitTests/BM25Tests.swift` (keep both repos' cases — they encode each repo's edge-case history, plan.md §5), updating only constant names/imports
- [x] Run `swift test` — exits 0

## Workflow
- Use `/tdd` — port the tests first (failing), then the source file to make them pass.