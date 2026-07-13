---
comments:
- actor: claude-code
  id: 01kxear75fsjp5nnwdd7bh8ep9
  text: |-
    Implemented the `Searcher` one-call facade per plan.md §3a.

    **New files:**
    - `Sources/RankKit/SearchItem.swift`: `Searchable` protocol (`id`, `text`, `summary` defaulting to `text` via extension) and `SearchItem` (the trivial conformer).
    - `Sources/RankKit/Searcher.swift`: `Searcher` struct (`Sendable`), nested `Searcher.Mode` (`.retrieval`/`.selection`/`.auto`), `SelectionTierUnavailable` error (mirrors FMR's), plus private `RetrievalEngine` (bundles catalog/documents/itemEmbeddings/embedder/weights/onDiagnostic and drives `HybridRanker.topMatches`/`fullOrdering`) and private `ItemCatalog: SelectionCatalog` (first-occurrence-id-wins, built from any `[Item: Searchable]`).
    - `Tests/RankKitTests/SearcherTests.swift`: 18 tests.

    **Design decisions worth flagging:**
    - `session:` defaults to `Searcher.defaultSessionFactory` (a `public static let` closure building `LanguageModelSession(model: .default, instructions:)`) rather than `nil`. Passing `session: nil` **explicitly** is how a caller opts out of selection entirely (`.selection` then throws `SelectionTierUnavailable`; `.auto` degrades to retrieval) — this is what makes plan.md's "zero-config full monty" default (`Searcher(items)` uses on-device selection) and the "no session available" error path both independently reachable from the same optional parameter, since Swift can't otherwise distinguish "omitted" from "explicit nil" on a single default.
    - SDK finding (same as prior task ^2gk4k4r): the installed macOS 27 SDK has no `SystemLanguageModel.fast`, only `.default`. Used `.default` in the zero-config default factory, documented at length in the file header, per the established precedent in `LanguageModelSessionSupport.swift`.
    - `Searcher` doesn't expose `capacityCharacterLimit:` (plan.md §3a's knob list explicitly omits it) — the over-budget selection test forces the path with a bulk 40-item fixture whose assembled `summary` content naturally exceeds `SelectionConfig.defaultCapacityCharacterLimit` (32,000 chars), keeping `text` (what `HybridRanker` actually scores) short and query-relevant.
    - Added `RankDiagnostic.embeddingUnavailable` (new case on the existing public enum) — the retrieval-tier counterpart to FMR's `MetadataDiagnostic.embeddingUnavailable`, reported whenever cosine was wanted (`weights.cosine > 0`) but couldn't contribute (no embedder, or the query embed failed). A caller-zeroed `weights.cosine` is treated as a deliberate opt-out, not a degradation, so it reports nothing — mirrors FMR's `MetadataSearcher.computeSignals`'s "a zero weight means the caller doesn't want the signal" rule. Confirmed via callgraph this isn't source-breaking (no exhaustive `switch` over `RankDiagnostic` anywhere in the tree, only `if case` matches).

    **Adversarial double-check (via really-done):** first pass returned REVISE — two doc comments (struct-level and `RetrievalEngine.cosineScores`) incorrectly claimed a zero `weights.cosine` reports `.embeddingUnavailable`, when the code (correctly, matching FMR precedent) reports nothing for that case; also flagged missing test coverage for zero-cosine-weight, duplicate-id dedup, and `limit <= 0`. Fixed both doc comments (code was correct, docs were wrong) and added 4 tests: `zeroCosineWeightOptsOutOfTheSignalWithoutReportingADiagnosticEvenWithNoEmbedder`, `nonPositiveLimitReturnsEmptyInRetrievalMode`, `nonPositiveLimitReturnsEmptyInSelectionModeWithoutCreatingASession`, `duplicateItemIdKeepsTheFirstOccurrenceAndDropsLaterOnes`. Re-spawned double-check once more: PASS.

    **Verification:** `swift build` and `swift test` both green — 181/181 tests across 15 suites (163 pre-existing + 18 new), zero warnings, zero failures. TDD followed throughout: watched SearcherTests.swift fail to compile first (`cannot find 'Searcher'/'SearchItem' in scope`), then implemented to green.
  timestamp: 2026-07-13T18:10:11.247751+00:00
depends_on:
- 01KWYG1850D1654Z6WSQXTHA1B
- 01KWYG2WCHH0FZJM34C4CB4K02
- 01KWYG34SCCF71GYAFR2GK4K4R
- 01KWYFZDHMWWBQT94WFH8D7X1R
position_column: doing
position_ordinal: '80'
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