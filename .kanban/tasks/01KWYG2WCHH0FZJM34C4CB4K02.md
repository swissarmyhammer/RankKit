---
comments:
- actor: claude-code
  id: 01kxe5eds0ajm76w0dtda3hxmv
  text: |-
    Picked back up for the review finding on SelectionTier.swift's respond() not applying idEnumGrammar. Investigated: `AgentSession.respond(to:)` has no grammar parameter at all (protocol only has `respond(to: String) -> String` plus a default `respond(to:generating:)` extension that decodes over the plain `respond(to:)`). Per the doc comments and the FMR source this was ported from (../FoundationModelsMetadataRegistry/Sources/FoundationModelsMetadataRegistry/Selection/SelectionTier.swift, and Examples/LiveRouterSupport/LiveRouterSupport.swift's buildSelectionConfig), grammar constraint is meant to be baked in at *session creation* time (via `RoutedLLM.makeGuidedSession(grammar:instructions:)`), not passed per-call into respond(). `idEnumGrammar` is exposed as a public utility for the `SelectionConfig.model` closure's builder to use. Confirmed same gap exists verbatim in the FMR source (idEnumGrammar has zero production callers there either) -- the live wiring lives in the Examples layer, external to SelectionTier itself, and only handles a static id set (doesn't handle the over-budget path's per-call candidate-set grammar).

    Dispatched a research agent to confirm FoundationModelsRouter's actual RoutedSession/RoutedLLM API shape before deciding whether the fix is: (a) thread a Grammar parameter through SelectionConfig.model so SelectionTier can pass Self.idEnumGrammar(ids:) into session creation (root fix, but changes model's public signature and touches every test that builds a SelectionConfig), or (b) something narrower.
  timestamp: 2026-07-13T16:37:27.456515+00:00
- actor: claude-code
  id: 01kxe604kd9x779xxvj7e4tt8b
  text: 'Review finding resolved. Root cause: AgentSession.respond(to:) has no grammar parameter at all (verified against both the RankKit protocol and the real FoundationModelsRouter package) -- grammar can only be applied at session-creation time, never injected into an individual respond() call. Fix: widened SelectionConfig.model to (String, Grammar) -> any AgentSession and had SelectionTier compute+pass Self.idEnumGrammar(ids:) at both session-creation call sites -- catalog.ids for the cached-root path, candidateIds (scoped to just that round''s top-M) for the over-budget path. Added two TDD regression tests proving the grammar is actually wired (watched both fail against a placeholder grammar first, then confirmed they pass with the real fix). swift build exit 0; swift test 160/160 across 3 consecutive runs. Sibling read-only repos (../FoundationModelsMetadataRegistry, ../CodeContextKit) confirmed untouched. Adversarial double-check: PASS on the code change; its only finding was the kanban checklist/notes not yet reflecting the fix, which this comment and the description update close out. Checklist item flipped to [x]. Left in doing for /review.'
  timestamp: 2026-07-13T16:47:07.885509+00:00
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

## Review Findings (2026-07-13 11:29)

- [x] `Sources/RankKit/Selection/SelectionTier.swift:125` — The `respond()` call in `search()` does not apply the id-constraint grammar that `idEnumGrammar()` generates (line 232) — the paired operations are unpaired, with grammar generation implemented and tested but constraint application missing. Wire the generated grammar into the respond() call: verify the respond() API accepts a grammar parameter and pass `Self.idEnumGrammar(ids: catalog.ids)` to constrain generation rather than relying on fallback filtering.

## Fix Notes (2026-07-13, review finding above)

- Root-caused: `AgentSession.respond(to:)` has **no** grammar parameter at all (protocol only has `respond(to: String) -> String`, plus a default `respond(to:generating:)` extension decoding over that same call) — confirmed by reading `Sources/RankKit/Selection/AgentSession.swift` and cross-checking the real `FoundationModelsRouter` package (`.build/checkouts/FoundationModelsRouter`): `RoutedSession.grammar: Grammar?` is a read-only property fixed only at session creation via `RoutedModel.makeGuidedSession(grammar:instructions:workingDirectory:)`, and merely inherited by `fork()`. So a grammar can only ever be applied at session construction, never injected into an individual `respond()` call — the literal fix the finding described isn't possible against the real API.
- Actual fix: `SelectionConfig.model`'s closure signature widened from `@Sendable (String) -> any AgentSession` to `@Sendable (String, Grammar) -> any AgentSession` (`Sources/RankKit/Selection/SelectionConfig.swift`, now imports `FoundationModelsRouter`). `SelectionTier` (`Sources/RankKit/Selection/SelectionTier.swift`) now computes and passes the grammar at both session-creation call sites: `cachedRootSession()` passes `Self.idEnumGrammar(ids: catalog.ids)` (whole catalog, computed once since it's only reached on cache-miss); `overBudgetSearch(intent:limit:)` passes `Self.idEnumGrammar(ids: candidateIds)` scoped to *that round's* top-M candidates only, not the whole catalog — correctly narrower than a statically pre-baked grammar could ever be, since the over-budget candidate set differs per call.
- Test fixtures updated to match: `Tests/RankKitTests/Support/ScriptedAgentSession.swift`'s `RecordingSessionFactory.makeSession(instructions:grammar:)` now records both instructions and grammar (`receivedGrammars`); all inline `SelectionConfig(model: { _ in ... })` closures across `SelectionConfigTests.swift`/`SelectionTests.swift`/`OverBudgetTests.swift` mechanically updated to the 2-arg `{ _, _ in ... }` shape.
- New regression tests (TDD: watched both fail first against a temporary `Grammar.jsonSchema("{}")` placeholder, then restored the real fix and watched them pass): `SelectionTests.cachedRootSessionIsConstrainedToTheWholeCatalogsIdEnumGrammar` and `OverBudgetTests.overBudgetSessionIsConstrainedToOnlyTheTopMCandidatesIdEnumGrammarNotTheWholeCatalog`. Both compare the received grammar structurally (decode the JSON schema, check `properties.ids.items.enum`) rather than via `Grammar`'s raw-string `Equatable` — `JSONSerialization.data(withJSONObject:)` doesn't guarantee stable dictionary key order across separate encodes of an equivalent schema, which made a first draft of these tests intermittently flake on exact-string comparison.
- Verification: `swift build` exit 0; `swift test` — 160 tests, 13 suites, 0 failures, run 3× consecutively with no flakes. `git status --porcelain` in `../FoundationModelsMetadataRegistry` and `../CodeContextKit` both empty (untouched). Adversarial `double-check` review of this fix: independently re-verified the `FoundationModelsRouter` API claims, grepped repo-wide for other `SelectionConfig`/`AgentSession` consumers (none found outside `Sources/RankKit/Selection` and the listed test files), and confirmed the 160/160 test count — PASS on the code change itself; its only REVISE finding was this kanban checklist/notes gap, now closed by this update.
- Left in `doing` per the implement workflow — ready for `/review`.
