---
depends_on:
- 01KWYG2CPJ3HAB6968RE8NW4TP
position_column: doing
position_ordinal: '80'
title: Generalize SelectionTier over SelectionCatalog
---
## What
Port (copy) `../FoundationModelsMetadataRegistry/Sources/FoundationModelsMetadataRegistry/Selection/SelectionTier.swift` → `Sources/RankKit/Selection/SelectionTier.swift`, generalized (plan.md §6 phase 3). **The source repo is read-only reference material — do not modify, delete, or touch anything in `../FoundationModelsMetadataRegistry` or `../CodeContextKit`.**
- Replace `MetadataIndex<Item>` with `any SelectionCatalog` (the tier only used `index.ids`, `item(forId:)`, `block(forId:)`, `renderSummaryBlock()` — map to `ids`/`summaryBlock(forId:)`/`block(forId:)`).
- Replace `Match<Item>` in `retrievalRanking`/results with a RankKit-level result carrying `id`, `block`, `score`, `signals` (reuse `Hit`/`Signals` plus block; consumers wrap into their own result types).
- Replace `MetadataDiagnostic` with `RankDiagnostic` (`.retrievalCut`, `.unknownSelectedId`).
- Keep semantics verbatim: under-budget cached-root + `fork()`-per-call, over-budget retrieval top-M into a fresh one-off session, ids-only output, first-seen dedup, `allowedIds` filtering, prefix assembly (`preamble` + `# Candidates` + summary blocks), `idEnumGrammar(ids:)` (Router `Grammar`, xgrammar id-enum + `uniqueItems`).

## Acceptance Criteria
- [x] Under-budget path: root session created once, forked per call (assert via scripted fake counting sessions/forks)
- [x] Over-budget path: `.retrievalCut` reported, one-off session seeded with top-M candidate summaries, results keep retrieval score/signals
- [x] Unknown/duplicate selected ids filtered exactly as the source tier does (`.unknownSelectedId` per unknown, silent dedup for repeats)
- [x] `git status` in `../FoundationModelsMetadataRegistry` and `../CodeContextKit` is untouched by this task

## Tests
- [x] Port (copy) `../FoundationModelsMetadataRegistry/Tests/FoundationModelsMetadataRegistryTests/SelectionTests.swift` and `OverBudgetTests.swift` to `Tests/RankKitTests/`, adapting only the catalog fixture (a simple in-memory `SelectionCatalog` conformer) and diagnostic enum names
- [x] Run `swift test` — exits 0 (scripted fakes, no GPU)

## Workflow
- Use `/tdd` — port the tests first (failing), then generalize the tier to make them pass.

## Implementation Notes (2026-07-13)

- `Sources/RankKit/Selection/SelectionTier.swift`: `public actor SelectionTier` (non-generic, over `any SelectionCatalog`), ported verbatim from FMR's `SelectionTier<Item>` with the documented type swaps. `SelectionSchemaShapeError` made `public` (was internal in the source) for API completeness now that `idEnumGrammar` is public.
- `Sources/RankKit/Selection/SelectionMatch.swift` (new): replaces `Match<Item>` minus the generic catalog item — `id`, `block`, `score`, `signals: Signals?`, `Sendable, Equatable`.
- Tests: `Tests/RankKitTests/SelectionTests.swift` and `OverBudgetTests.swift` ported, driven directly against `SelectionTier` (no `Searcher`/`MetadataSearcher`-equivalent facade exists yet — separate blocked task). Over-budget tests script `retrievalRanking` as a canned closure (alpha gets real BM25-like signals, others zeroed) instead of driving a real BM25 tier. Two source tests were intentionally NOT ported (`selectionModeWithNoConfigStillThrowsSelectionTierUnavailable`, the two `.auto`-mode resolution tests) — they exercise a `mode:` facade concept that belongs to the not-yet-built `Searcher` facade task, not `SelectionTier` itself.
- New shared test doubles: `Tests/RankKitTests/Support/ScriptedAgentSession.swift` (multi-response scripted session + fork/call counting, `RootSessionRespondCalledDirectlySession`, `RecordingSessionFactory`, `CallCounter`, `DiagnosticRecorder` for `RankDiagnostic`) and `Tests/RankKitTests/Support/FixtureSelectionCatalog.swift` (simple in-memory `SelectionCatalog` conformer).
- `Tests/RankKitTests/SelectionConfigTests.swift` edited: its old file-private minimal `ScriptedAgentSession` was replaced — other tests now use the shared, richer `Support/ScriptedAgentSession.swift`; `defaultForkReturnsSelfUnchanged` now uses a new `MinimalAgentSession` fixture that deliberately does NOT override `fork()`, so it still proves `AgentSession`'s protocol-default `fork()` (the shared `ScriptedAgentSession` overrides `fork()` for call-counting, which would have made that test vacuous otherwise).
- Verification: `swift build` exit 0; `swift test` — 158 tests, 13 suites, 0 failures. `git status --porcelain` in `../FoundationModelsMetadataRegistry` and `../CodeContextKit` both empty. Adversarial `double-check` review: PASS, no findings.
- Left in `doing` per the implement workflow — ready for `/review`.