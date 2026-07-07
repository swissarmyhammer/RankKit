---
depends_on:
- 01KWYG1850D1654Z6WSQXTHA1B
- 01KWYG02NSB135TJPQ0EA8BXXT
position_column: todo
position_ordinal: 8a80
title: Refactor CCK SearchCode onto HybridRanker
---
## What
In `../CodeContextKit/Sources/CodeContextKit/Ops/SearchCode.swift` (plan.md §6 phase 2): replace the private per-signal pipeline (`computeBM25Ranking`, `computeTrigramRanking`, `computeCosineRanking`, `rankingOfPositiveScores`, `fuseRankings`) with a thin mapping from `SearchCorpusSnapshot` into RankKit's `HybridRanker`. Keep the vDSP cosine path: `SearchCorpusSnapshot.cosineScores(queryVector:)` keeps producing the cosine score array (or moves onto `CosineScoring.matvecScores`), which feeds `HybridRanker` as the precomputed cosine signal. Keep `SearchWeights` as a deprecated typealias of `SignalWeights` or migrate the public name — keep CCK's public API source-compatible. `IndexingProgress` behavior unchanged.

**Precondition**: RankKit `main` on GitHub contains `HybridRanker`/`SignalWeights`/`CosineScoring` (push after that task is green; `swift package update` here pulls it).

## Acceptance Criteria
- [ ] All duplicated per-signal/fusion private helpers deleted from `SearchCode.swift`
- [ ] CCK's `SearchCodeTests` pass unmodified (identical ordering, scores, and `indexingProgress`)
- [ ] `SearchCorpusSnapshot` continues one-`vDSP_mmul` cosine scoring (no per-row scalar regression)

## Tests
- [ ] Run `swift test` in `../CodeContextKit` — exits 0, no test-body edits

## Workflow
- Use `/tdd` — the existing CCK suite is the harness; refactor until green.