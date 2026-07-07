---
depends_on:
- 01KWYG1850D1654Z6WSQXTHA1B
- 01KWYG2WCHH0FZJM34C4CB4K02
- 01KWYG34SCCF71GYAFR2GK4K4R
- 01KWYFZDHMWWBQT94WFH8D7X1R
position_column: todo
position_ordinal: '8e80'
title: Build Searcher one-call facade
---
## What
Create `Sources/RankKit/Searcher.swift` + `Sources/RankKit/SearchItem.swift` per plan.md §3a — the package's front door where "a list of things to search, then a query" is the whole API:
- `SearchItem`: `id` + `text` (+ optional `summary`, defaults to `text`, seeds the selection prefix). A `Searchable` protocol lets richer types participate without wrapping.
- `Searcher(items)`: full monty with zero config — BM25 + trigram retrieval fused by RRF, agent final selection on the on-device system model `.fast` (the shipped default — guidance, not a requirement).
- All knobs optional: `embedder:` (any `TextEmbedding` — adds the cosine signal; items embedded once at init), `session:` (`(String) -> any AgentSession` — any `LanguageModelSession` model or `RoutedAgentSession`; never hardcoded), `weights:`, `preamble:` (default `.selectionDefault`), `candidateLimit:`, `mode:` (`.retrieval`/`.selection`/`.auto`, default `.auto`).
- `search(_ query: String, limit: Int = 20)` → results with `id`, `block`, `score`, per-signal `signals`.
- Internally thin: composes `HybridRanker` (retrieval) + `SelectionTier` (selection) over an in-memory `SelectionCatalog` built from the items.
- Graceful degradation, never silent: no embedder → keyword-only + diagnostic; `mode: .selection` with no session available → loud error (mirror FMR's `SelectionTierUnavailable`); `.auto` degrades to retrieval.

## Acceptance Criteria
- [ ] `try await Searcher(items)` then `try await searcher.search("…")` works with a scripted fake standing in for the system model in tests
- [ ] Swapping `session:` swaps the model — no code path names a specific model outside the default
- [ ] A custom type conforming to `Searchable` (not wrapped in `SearchItem`) works end-to-end through `Searcher` and `search(...)`
- [ ] Degradation cases reported via the `RankDiagnostic`/diagnostic callback, never silently

## Tests
- [ ] `Tests/RankKitTests/SearcherTests.swift`: end-to-end over a fixture item list with `FakeEmbedder` + scripted `AgentSession` — retrieval-only mode, selection mode (under- and over-budget), `.auto` resolution both ways, degradation diagnostics, and a `Searchable`-conformer case
- [ ] Run `swift test` — exits 0 (no GPU, no live model)

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.