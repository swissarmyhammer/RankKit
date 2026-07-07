---
depends_on:
- 01KWYG2CPJ3HAB6968RE8NW4TP
position_column: todo
position_ordinal: 8c80
title: Generalize SelectionTier over SelectionCatalog
---
## What
Port `../FoundationModelsMetadataRegistry/Sources/FoundationModelsMetadataRegistry/Selection/SelectionTier.swift` → `Sources/RankKit/Selection/SelectionTier.swift`, generalized (plan.md §6 phase 3):
- Replace `MetadataIndex<Item>` with `any SelectionCatalog` (the tier only used `index.ids`, `item(forId:)`, `block(forId:)`, `renderSummaryBlock()` — map to `ids`/`summaryBlock(forId:)`/`block(forId:)`).
- Replace `Match<Item>` in `retrievalRanking`/results with a RankKit-level result carrying `id`, `block`, `score`, `signals` (reuse `Hit`/`Signals` plus block; consumers wrap into their own `Match`).
- Replace `MetadataDiagnostic` with `RankDiagnostic` (`.retrievalCut`, `.unknownSelectedId`).
- Keep semantics verbatim: under-budget cached-root + `fork()`-per-call, over-budget retrieval top-M into a fresh one-off session, ids-only output, first-seen dedup, `allowedIds` filtering, prefix assembly (`preamble` + `# Candidates` + summary blocks), `idEnumGrammar(ids:)` (Router `Grammar`, xgrammar id-enum + `uniqueItems`).

## Acceptance Criteria
- [ ] Under-budget path: root session created once, forked per call (assert via scripted fake counting sessions/forks)
- [ ] Over-budget path: `.retrievalCut` reported, one-off session seeded with top-M candidate summaries, results keep retrieval score/signals
- [ ] Unknown/duplicate selected ids filtered exactly as FMR's tier does today (`.unknownSelectedId` per unknown, silent dedup for repeats)

## Tests
- [ ] Port `../FoundationModelsMetadataRegistry/Tests/FoundationModelsMetadataRegistryTests/SelectionTests.swift` and `OverBudgetTests.swift` to `Tests/RankKitTests/`, adapting only the catalog fixture (a simple in-memory `SelectionCatalog` conformer) and diagnostic enum names
- [ ] Run `swift test` — exits 0 (scripted fakes, no GPU)

## Workflow
- Use `/tdd` — port the tests first (failing), then generalize the tier to make them pass.