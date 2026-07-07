---
depends_on:
- 01KWYG2WCHH0FZJM34C4CB4K02
- 01KWYG02NSB135TJPQ0EA8BXXT
position_column: todo
position_ordinal: '9180'
title: 'CCK: SelectionCatalog view over SearchCorpusSnapshot'
---
## What
In `../CodeContextKit` (plan.md §6 phase 4): create a `SelectionCatalog` conformance over `SearchCorpusSnapshot` (new file, e.g. `Sources/CodeContextKit/Search/ChunkSelectionCatalog.swift`):
- **Precondition**: RankKit `main` on GitHub contains `SelectionCatalog` (push after the selection-tier tasks are green).
- `ids`: chunk ids as strings (`String(chunkIds[i])`)
- `summaryBlock(forId:)`: TERSE — symbol path + kind + `filePath:startLine-endLine` only, NOT chunk text (plan.md §7: at `candidateLimit ≈ 24` the one-off prefix must stay inside the context window)
- `block(forId:)`: the chunk's full source text
- Add a test-only (or debug) measurement of assembled-prefix size for a realistic top-24 candidate set — the data phase-4 defaults get picked from (plan.md §7 last risk)

## Acceptance Criteria
- [ ] Conformance resolves ids round-trip: every id in `ids` has a non-nil summary and block
- [ ] Summary blocks contain no chunk body text
- [ ] Prefix-size measurement exists and is asserted under a sane ceiling for a 24-candidate fixture (e.g. < `SelectionConfig.defaultCapacityCharacterLimit`)

## Tests
- [ ] `Tests/CodeContextKitTests/ChunkSelectionCatalogTests.swift`: fixture snapshot → id round-trip, summary format, prefix-size assertion
- [ ] Run `swift test` in `../CodeContextKit` — exits 0

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.