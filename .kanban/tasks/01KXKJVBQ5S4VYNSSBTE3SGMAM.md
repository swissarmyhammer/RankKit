---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01kxkmhcnx5g01d65vj0kfae3c
  text: 'Picked up by /finish (scoped-batch, iteration 1). Baseline: working tree clean at 06a239a, full suite green (194 tests / 17 suites). Delegating /implement.'
  timestamp: 2026-07-15T19:37:25.437411+00:00
- actor: claude-code
  id: 01kxkmvmfz1qjxp8zvgkz161gv
  text: 'Picked up by /implement. Research done: verified card facts against code. Under-budget branch of SelectionTier.search calls matches(forIds:limit:) with default empty retrievalMatches -> 1.0/nil sentinel via `retrievalMatch?.score ?? 1.0`. Plan: (RED) update sentinel assertions in SelectionTests (~94-95, 115), SearcherTests (~95-96, 205-206 + rename), ReadmeExampleTests (~49-50 + doc), ExamplesSmokeTests (~106-109); replace SelectionTests.neverCalledRetrievalRanking with a scripted fixture ranking (kept only for the limit<=0 short-circuit test); add zero-tail regression test in SearcherTests (query "qqqq" shares no token/trigram with toolItems -> whole catalog is zero tail; scripted pick must carry 0.0/all-zero Signals). (GREEN) under-budget branch awaits retrievalRanking(intent) after the model call and passes retrievalMatches; drop the [:] default on matches(...) and fold the retrievalMatches lookup into the resolution guard (removes the 1.0 sentinel entirely; miss is structurally unreachable for both callers and treated like an unknown id). Doc updates: SelectionTier class/search/matches/retrievalRanking docs, Searcher.search returns-doc + cost note (one query-embedding call per selection search when embedder configured), RetrievalEngine.fullOrdering doc, SelectionMatch score/signals docs, README front-example comment + Modes bullet, stale test comments in OverBudgetTests/SearcherTests.'
  timestamp: 2026-07-15T19:43:01.119928+00:00
- actor: claude-code
  id: 01kxkndxvsknjakg0s3f07z3b6
  text: |-
    TDD cycle complete. RED: updated sentinel assertions + new zero-tail regression test failed with exactly 15 expectation failures (score/signals still 1.0/nil), all for the right reason. GREEN: implemented SelectionTier under-budget change; `swift test` now passes 195 tests / 17 suites (was 194 at baseline; +1 is the new zero-tail test). Acceptance grep clean: `grep -rn "1.0" Sources/ README.md` shows only math constants/weight defaults/range docs, no sentinel; no "pure-selection"/"sentinel" references remain in Sources/ or README.

    Implementation notes for the next agent:
    - SelectionTier.search under-budget branch awaits retrievalRanking(intent) AFTER the model call (comment in code: a throwing session never pays the retrieval/query-embed cost) and passes the full ordering as retrievalMatches. No .retrievalCut emitted (OverBudgetTests.underBudgetSearchNeverFiresRetrievalCut still green).
    - Went slightly beyond the card's "consider dropping the [:] default": dropped it AND folded the retrievalMatches lookup into the resolution guard (miss -> .unknownSelectedId, structurally unreachable for both callers since fullOrdering covers every catalog id and over-budget allowedIds == candidate keys). This removes the `?? 1.0` sentinel from the code entirely, which the acceptance grep criterion effectively requires.
    - SelectionTests.neverCalledRetrievalRanking kept only for the limit<=0 short-circuit test (redocumented); other under-budget tests use a new scripted rankedCatalog fixture (deploy 0.9 / rollback 0.3 with distinct Signals).
    - SearcherTests: renamed under-budget test asserts score/signals equality against a `.retrieval`-mode Searcher for the same query (topMatches and fullOrdering share computeAndSortSignals, so scores are identical); same pattern in the .auto test and ReadmeExampleTests. Zero-tail test uses query "qqqq" (no shared token/trigram with toolItems) with scripted pick "watch" -> 0.0 / all-zero Signals.
    - Also updated: SelectionMatch score/signals docs, Searcher.search returns-doc + cost note (one query-embedding call per selection search when embedder configured), RetrievalEngine.fullOrdering doc, SelectionTier class/init docs, README front-example comment + Modes bullet, OverBudgetTests test rename (overBudgetResultsCarryTheRealRetrievalScoreAndSignalsOfThisRoundsCandidates) and stale test comments.
    - Pre-existing (not from this change) build warnings: unused swift-jinja dependency, mlx-swift bundle "missing creator for mutated node".

    Awaiting double-check agent verdict (really-done advisory gate). No commit/push per instructions.
  timestamp: 2026-07-15T19:53:00.537144+00:00
- actor: claude-code
  id: 01kxknwftpf74emkxjf21r26st
  text: 'Double-check verdict: REVISE with two LOW documentation-level findings (implementation, tests, and all card constraints verified correct by the critic, who independently re-ran swift test green). Both findings fixed: (1) dropped stale "over-budget"-only wording from Searcher.engine property doc and the RetrievalEngine struct header (retrievalRanking now runs on every selection search); (2) documented the newly-visible degradation — a selection search without an embedder now reports .embeddingUnavailable per query, same as retrieval — in the Searcher.search cost note, and pinned it with a new test selectionModeUnderBudgetWithNoEmbedderReportsEmbeddingUnavailable in SearcherTests'' degradation section. Fresh full run after fixes: swift test — 196 tests / 17 suites, all passed, exit 0. Bounded re-check was dispatched to the same double-check agent; per really-done''s contract (one re-check max, advisory gate), proceeding — findings were doc-level, both applied verbatim as suggested, and the hard verification gate is green. Work complete; task stays in doing for /review. Not committed, not pushed, per instructions.'
  timestamp: 2026-07-15T20:00:57.686153+00:00
- actor: claude-code
  id: 01kxkqre6vcywj1ncn0y45w6n7
  text: '/test verified independently: 196 tests / 17 suites, 0 failures, warm run and full clean rebuild both green. Only warning is the documented deliberate swift-jinja pin (family convention, also present in FoundationModelsMetadataRegistry). Proceeding to checkpoint /commit, then /review HEAD~1..HEAD.'
  timestamp: 2026-07-15T20:33:42.107312+00:00
- actor: claude-code
  id: 01kxkrfgd0nnmwf8s0f3x0y95s
  text: |-
    Review finding fixed (RetrievalEngine duplication in Searcher.swift). Pulled task review -> doing, refactored, flipped the finding to [x], left task in doing.

    Refactor shape: extracted a private helper `rankedMatches(forQuery:rank:)` on RetrievalEngine parameterized by a `([Double]?) -> [Hit]` closure. The helper owns the shared pipeline once — empty-catalog guard, single `cosineScores(forQuery:)` await, and the Hit -> SelectionMatch mapping (the old single-caller `matches(forHits:)` was folded into it, so no vestigial helper remains). `topMatches` keeps only its own `limit > 0` short-circuit and binds `HybridRanker.topMatches(...limit:)`; `fullOrdering` binds `HybridRanker.fullOrdering(...)`. Behavior byte-identical: both short-circuits still return [] before awaiting cosineScores, so no .embeddingUnavailable is emitted from them; diagnostic emission otherwise unchanged.

    Verification: `swift test` fresh run — 196 tests / 17 suites, 0 failures, exit 0 (same count as pre-refactor baseline; pure refactor, no test changes needed). really-done double-check agent verdict: PASS — independently confirmed behavior identity, ran swift test itself (196/17 green), confirmed `find duplicates` reports zero intra-file pairs in Searcher.swift (topMatches <-> fullOrdering no longer pair), no stale doc references (`forHits` grep empty), and diff scope is exactly Searcher.swift + this card's kanban bookkeeping. Not committed, not pushed, per instructions.
  timestamp: 2026-07-15T20:46:18.016679+00:00
position_column: doing
position_ordinal: '80'
title: Attach real fused score/signals to under-budget selection matches
---
## What
Plan.md §3a promises the facade's easiest call returns hits "with .score and per-signal .signals attached", but the under-budget selection path returns a fake sentinel instead: `SelectionTier.search(intent:limit:)` resolves matches through `matches(forIds:limit:)` with the default empty `retrievalMatches`, so every under-budget `SelectionMatch` carries `score: 1.0` and `signals: nil`. The over-budget path already does this right — it awaits `retrievalRanking(intent)` and passes the ranked candidates in as `retrievalMatches`, so its matches carry the real fused score and per-signal breakdown.

Fix in `Sources/FoundationModelsRanker/Selection/SelectionTier.swift`: make the under-budget branch of `search(intent:limit:)` also compute `let ranked = await retrievalRanking(intent)` and pass `retrievalMatches: Dictionary(uniqueKeysWithValues: ranked.map { ($0.id, $0) })` to `matches(forIds:limit:)`. The tier already holds `retrievalRanking`; `Searcher` wires it to `RetrievalEngine.fullOrdering`, which returns the full-catalog ordering including the zero-scored tail, so every catalog id resolves to a real entry. Selection semantics stay verbatim: same cached-root + fork-per-call, same whole-catalog grammar, model call-order still decides result order — only the `score`/`signals` enrichment changes. Do NOT emit `.retrievalCut` from the under-budget path (no cut happens; the whole catalog remains selectable).

Doc/comment updates required in the same change:
- `SelectionTier.search(intent:limit:)` returns-doc and the `matches(forIds:limit:allowedIds:retrievalMatches:)` parameter doc (both currently describe the pure-selection `1.0`/`nil` default). Consider dropping the `retrievalMatches: [:]` default entirely since both callers will now pass it.
- `Searcher.search(_:limit:)` returns-doc in `Sources/FoundationModelsRanker/Searcher.swift` (currently: "score `1.0`, `signals` `nil`, under budget").
- README.md front-example comment (currently "the agent's pick from the top candidates" — can now honestly say the pick carries its real fused score and per-signal breakdown, matching plan §3a).
- Note the cost tradeoff in the `search` doc: under-budget selection now runs retrieval per query, which includes one query-embedding call when an embedder is configured.

## Acceptance Criteria
- [x] Under-budget selection matches carry the same `score` and non-nil `signals` that `.retrieval` mode (`RetrievalEngine.fullOrdering`) reports for the same query, catalog, and weights — no `1.0`/`nil` sentinel anywhere
- [x] An under-budget selected id from the zero-scored tail carries that tail entry's real (zero) score, not `1.0`
- [x] Result ordering is still the model's call order, and the over-budget path's behavior and diagnostics are unchanged
- [x] No stale doc comments or README text describing the `1.0` sentinel remain (`grep -rn "1.0" Sources/ README.md` shows no sentinel references)

## Tests
- [x] Update `Tests/FoundationModelsRankerTests/SelectionTests.swift` (the `score == 1.0` / `signals == nil` assertions) to assert the real fused score/signals from the fixture's `retrievalRanking`
- [x] Update `Tests/FoundationModelsRankerTests/SearcherTests.swift` (`selectionModeUnderBudgetUsesTheConfiguredSessionAndReturnsPureSelectionMatches` and the `.auto` under-budget test) to assert score/signals match what `.retrieval` mode returns for the same query — rename the test to match the new behavior
- [x] Update `Tests/FoundationModelsRankerTests/ReadmeExampleTests.swift` and `Tests/FoundationModelsRankerTests/ExamplesSmokeTests.swift` sentinel assertions the same way
- [x] New regression test: scripted under-budget session selects an id retrieval ranks in the zero-scored tail → the match carries the tail entry's score/signals, not `1.0`/`nil`
- [x] Run `swift test` — exits 0

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.

## Review Findings (2026-07-15 15:34)

- [x] `Sources/FoundationModelsRanker/Searcher.swift:265` — topMatches and fullOrdering in RetrievalEngine are near-verbatim copies—both guard on documents.isEmpty, await cosineScores, call a HybridRanker method, and map results through matches(). Differ only in which HybridRanker method is called and whether limit is passed. Two blocks differing only by method name/arguments should be one parameterized function. Extract a private helper method parameterized by the HybridRanker closure (topMatches/fullOrdering), or refactor one to call the other with a bound method reference.