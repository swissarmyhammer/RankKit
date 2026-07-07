---
depends_on:
- 01KWYFZ70DH9VZR2CRJNFJTDNE
- 01KWYFZDHMWWBQT94WFH8D7X1R
position_column: todo
position_ordinal: '8580'
title: Migrate CodeContextKit onto RankKit
---
## What
In `../CodeContextKit` (plan.md §6 phase 1 step 5):
- **Precondition**: the ported primitives are pushed to RankKit's `main` on GitHub (plan.md §6 phase 1 step 3) — the remote dep below can't resolve otherwise.
- Add the RankKit dependency to `Package.swift` (`https://github.com/swissarmyhammer/RankKit`, `branch: "main"`).
- Delete `Sources/CodeContextKit/Search/{BM25,Trigram,Tokenizer,RRF,Hit}.swift` and `Sources/CodeContextKit/Embedding/` (both files). **Keep** `Sources/CodeContextKit/Search/SearchCorpus.swift` — it's storage, not primitives.
- Add `@_exported import RankKit` (or typealiases) so `SearchCodeMatch.hit`, `Signals`, and the `TextEmbedding` seams stay source-compatible.
- Rename call sites: `BM25.symbolPathFieldWeight` → `BM25.primaryFieldWeight` in `Search/SearchCorpus.swift` (`preprocessRow`) and `Ops/SearchCode.swift` (`computeTrigramRanking`). `bodyFieldWeight` keeps its name.
- Adopting RankKit's adapter fixes CCK's stale `embed(texts:)` Router call — if other Router API drift surfaces (plan.md §7), fix it here, not in RankKit.
- Remove the trigram/tokenizer/RRF/BM25 cases from `Tests/CodeContextKitTests/RankerTests.swift` that moved to RankKit (keep any pipeline-level cases).

## Acceptance Criteria
- [ ] `swift package resolve` in CCK pulls RankKit `main` from GitHub successfully
- [ ] The five primitive files and `Embedding/` no longer exist in CCK
- [ ] CCK full test suite green with no test-body edits other than imports, constant renames, and removal of test cases that moved to RankKit
- [ ] `SearchCorpus.swift` unchanged except the constant rename

## Tests
- [ ] Run `swift test` in `../CodeContextKit` — exits 0

## Workflow
- Use `/tdd` — the existing CCK suite is the failing-test harness; make it green.