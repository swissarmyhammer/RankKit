---
assignees:
- claude-code
position_column: todo
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
- [ ] Under-budget selection matches carry the same `score` and non-nil `signals` that `.retrieval` mode (`RetrievalEngine.fullOrdering`) reports for the same query, catalog, and weights — no `1.0`/`nil` sentinel anywhere
- [ ] An under-budget selected id from the zero-scored tail carries that tail entry's real (zero) score, not `1.0`
- [ ] Result ordering is still the model's call order, and the over-budget path's behavior and diagnostics are unchanged
- [ ] No stale doc comments or README text describing the `1.0` sentinel remain (`grep -rn "1.0" Sources/ README.md` shows no sentinel references)

## Tests
- [ ] Update `Tests/FoundationModelsRankerTests/SelectionTests.swift` (the `score == 1.0` / `signals == nil` assertions) to assert the real fused score/signals from the fixture's `retrievalRanking`
- [ ] Update `Tests/FoundationModelsRankerTests/SearcherTests.swift` (`selectionModeUnderBudgetUsesTheConfiguredSessionAndReturnsPureSelectionMatches` and the `.auto` under-budget test) to assert score/signals match what `.retrieval` mode returns for the same query — rename the test to match the new behavior
- [ ] Update `Tests/FoundationModelsRankerTests/ReadmeExampleTests.swift` and `Tests/FoundationModelsRankerTests/ExamplesSmokeTests.swift` sentinel assertions the same way
- [ ] New regression test: scripted under-budget session selects an id retrieval ranks in the zero-scored tail → the match carries the tail entry's score/signals, not `1.0`/`nil`
- [ ] Run `swift test` — exits 0

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.