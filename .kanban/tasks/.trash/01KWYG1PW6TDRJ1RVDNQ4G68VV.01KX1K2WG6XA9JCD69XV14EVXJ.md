---
depends_on:
- 01KWYG1850D1654Z6WSQXTHA1B
position_column: todo
position_ordinal: '8980'
title: Refactor FMR MetadataSearcher onto HybridRanker
---
## What
In `../FoundationModelsMetadataRegistry/Sources/FoundationModelsMetadataRegistry/MetadataSearcher.swift` (plan.md §6 phase 2): replace the private per-signal pipeline (`computeSignals`, `computeBM25Ranking`, `computeTrigramRanking`, `computeCosineRanking`, `fuseAndNormalize`, `rankingOfPositiveScores`, `sortByNormalizedScore`, `cosineSimilarity`, `zeroScoresArray`) with a thin mapping from `MetadataIndex` into RankKit's `HybridRanker`/`SignalWeights`/`CosineScoring`. `retrievalSearch(intent:limit:)` uses the top-K mode; `rankEntireCatalog(...)` uses the full-ordering mode. Keep `Weights` as a deprecated typealias of `SignalWeights` or migrate the public name — pick one and keep FMR's public API source-compatible.

**Precondition**: RankKit `main` on GitHub contains `HybridRanker`/`SignalWeights`/`CosineScoring` (push after that task is green; `swift package update` here pulls it).

## Acceptance Criteria
- [ ] All duplicated per-signal/fusion private helpers deleted from `MetadataSearcher.swift`
- [ ] FMR's `RetrievalSearchTests` and `OverBudgetTests` pass unmodified (behavior identical)
- [ ] Diagnostics behavior unchanged (`.embeddingUnavailable` still reported on every degraded search)

## Tests
- [ ] Run `swift test` in `../FoundationModelsMetadataRegistry` — exits 0, no test-body edits

## Workflow
- Use `/tdd` — the existing FMR suite is the harness; refactor until green.