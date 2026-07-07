---
depends_on:
- 01KWYG0EARADAZ0ADAK2Q73PSJ
- 01KWYG0NKKDA8X7GGT0KPE713N
position_column: todo
position_ordinal: '8880'
title: Add SignalWeights + HybridRanker fusion pipeline
---
## What
Create `Sources/RankKit/HybridRanker.swift` (plan.md §6 phase 2) encoding the pipeline currently duplicated between `../CodeContextKit/Sources/CodeContextKit/Ops/SearchCode.swift` and `../FoundationModelsMetadataRegistry/Sources/FoundationModelsMetadataRegistry/MetadataSearcher.swift`:
- `SignalWeights` struct: `bm25`/`trigram`/`cosine`, all default `1.0`, `Sendable`+`Equatable` (replaces CCK `SearchWeights` and FMR `Weights`).
- `HybridRanker`: given per-document `RankedDocument`s, a query, optional cosine scores, and `SignalWeights`, produce the fused `[0,1]`-normalized, tie-broken ranking plus per-document raw `Signals`. Must encode once:
  - `rankingOfPositiveScores(scores:)` (verbatim-identical in both repos today)
  - the absent-signal rule: only signals with positive weight AND a non-empty ranking enter `RRF.fuse`/`RRF.normalize`
  - two-field trigram scoring (`primaryFieldWeight` × primary Dice + `bodyFieldWeight` × body Dice)
  - deterministic descending-score sort with ascending-index tie-break
  - both output shapes: top-K matches-only (CCK `retrievalSearch` style) and full-catalog ordering with zero-scored tail (FMR `rankEntireCatalog` style, needed by the over-budget selection path)

## Acceptance Criteria
- [ ] On a shared fixture corpus, output ordering and normalized scores match what `MetadataSearcher.retrievalSearch` produces today (verify by porting 2–3 of FMR's `RetrievalSearchTests` expectations)
- [ ] Full-ordering mode always returns exactly N results for an N-document corpus
- [ ] Zero-weight and empty-ranking signals are excluded from the normalization ceiling (single-signal perfect match normalizes to 1.0)

## Tests
- [ ] `Tests/RankKitTests/HybridRankerTests.swift`: fusion cases ported/adapted from FMR's `RetrievalSearchTests.swift` and CCK's `SearchCodeTests.swift` fusion coverage; absent-signal rule cases; tie-break determinism case
- [ ] Run `swift test` — exits 0

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.