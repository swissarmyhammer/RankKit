---
depends_on:
- 01KWYFZ70DH9VZR2CRJNFJTDNE
- 01KWYFZDHMWWBQT94WFH8D7X1R
position_column: todo
position_ordinal: '8480'
title: Migrate FoundationModelsMetadataRegistry onto RankKit
---
## What
In `../FoundationModelsMetadataRegistry` (plan.md §6 phase 1 step 4):
- **Precondition**: the ported primitives are pushed to RankKit's `main` on GitHub (plan.md §6 phase 1 step 3) — the remote dep below can't resolve otherwise.
- Add the RankKit dependency to `Package.swift` (`https://github.com/swissarmyhammer/RankKit`, `branch: "main"`).
- Delete `Sources/FoundationModelsMetadataRegistry/Search/` (all 5 files) and `Sources/FoundationModelsMetadataRegistry/Embedding/` (both files).
- Add `@_exported import RankKit` (or plain import + local typealiases — decide at migration, plan.md §4.4) so `Hit`/`Signals`/`TextEmbedding` stay reachable through FMR's public API (`Match.signals`, `init(embedder:)` seams).
- Rename call sites: `BM25.idFieldWeight` → `BM25.primaryFieldWeight`, `BM25.blockFieldWeight` → `BM25.bodyFieldWeight` in `MetadataIndex.swift` and `MetadataSearcher.swift`.
- Remove the now-duplicated `TrigramTests.swift`, `RRFTests.swift`, and `BM25Tests.swift` from FMR's test target (their cases moved to RankKit) — no duplicated maintenance.

## Acceptance Criteria
- [ ] `swift package resolve` in FMR pulls RankKit `main` from GitHub successfully
- [ ] `Sources/.../Search/` and `Sources/.../Embedding/` no longer exist in FMR
- [ ] FMR full test suite green with no test-body edits other than imports, constant renames, and removal of test files/cases that moved to RankKit
- [ ] FMR examples (`swift build` all targets) still compile

## Tests
- [ ] Run `swift test` in `../FoundationModelsMetadataRegistry` — exits 0
- [ ] Run `swift build` in `../FoundationModelsMetadataRegistry` — all example targets compile

## Workflow
- Use `/tdd` — the existing FMR suite is the failing-test harness; make it green.