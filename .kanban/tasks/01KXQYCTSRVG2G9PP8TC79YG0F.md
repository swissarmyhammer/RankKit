---
comments:
- actor: claude-code
  id: 01kxrb01bwm27hnawfd0fvq5kh
  text: 'Picked up by /finish (scoped-batch, no filter), now that ^xqrbq19 landed in done and unblocked this. Iteration 1: dispatching /implement.'
  timestamp: 2026-07-17T15:26:51.772836+00:00
- actor: claude-code
  id: 01kxrch4qynggkm9wa7kap4qs6
  text: |-
    Implemented via TDD.

    Design decision: added a new `public actor StreamingSearchCorpus` (Sources/FoundationModelsRanker/StreamingSearchCorpus.swift) wrapping `SearchCorpus` directly as `private var corpus: SearchCorpus`. Considered and rejected two alternatives (documented in the file header):
    - Turning `SearchCorpus` itself into an actor — rejected because it's a plain value type whose synchronous API is load-bearing for `Searcher`'s fixed-corpus (never-mutated-after-init) use and the existing SearchCorpusTests equivalence suite, which drives it synchronously through `HybridRanker`.
    - Wrapping `Searcher`'s private `RetrievalEngine` — rejected because that struct bundles Searcher-specific concerns (embedder, fusion weights, onDiagnostic) this task's scope never asked for, and it's `private` to Searcher.swift.

    Confinement mechanism: every `add`/`remove`/`search` method body has zero internal `await`/suspension points, so each actor call runs to completion atomically relative to every other call on the same actor — a concurrent `search` either sees a corpus state entirely before or entirely after a racing `add`/`remove`, never mid-mutation. Snapshot-at-entry semantics per the acceptance criteria. `search(_:limit:)` returns `[SelectionMatch]` via `HybridRanker.topMatches` (no cosine/embedder — out of scope for this bare streaming wrapper).

    TDD: wrote Tests/FoundationModelsRankerTests/StreamingSearchCorpusTests.swift first (6 tests) referencing the not-yet-existing `StreamingSearchCorpus` type; confirmed RED via `swift build --build-tests` (compile failure: "cannot find 'StreamingSearchCorpus' in scope" — feature missing, not a typo). Implemented the actor; reran — GREEN, no other regressions.

    Tests added: single-threaded equivalence (actor surface ranks identically to a plain SearchCorpus built/mutated the same way), remove(ids:)/remove(group:) through the actor, empty-corpus search, and one concurrent stress test (~20 concurrent add+evict-group producers, 1 producer adding 50 never-removed survivors, 200 concurrent searchers in one `withTaskGroup`) asserting every returned `SelectionMatch.block` exactly matches the known text for its id (torn/partial-read detector) and that post-stress state is exactly the survivors.

    Verification:
    - `swift test`: 216 tests / 19 suites, all green (baseline was 210/18; net +6 tests, +1 suite, zero regressions).
    - `swift test --sanitize=thread --filter StreamingSearchCorpusTests`: clean, exit 0, no TSan warnings.
    - `swift test --sanitize=thread` (full suite): clean, exit 0, no TSan warnings — satisfies the "TSan clean under stress" acceptance criterion directly (this toolchain, Apple Swift 6.4, supports `--sanitize=thread` natively).
    - Adversarial double-check (subagent) returned PASS after independently re-reading both files, confirming no `await` inside actor method bodies (so the "atomic per call" claim is literally true, not just documented), confirming Sendable soundness across the actor boundary, confirming no scope creep (RetrievalEngine/Searcher/SearchCorpus untouched — `git get changes` shows only the two new files plus kanban bookkeeping), and independently re-running the full suite and the TSan suite.

    No blockers. Leaving task in `doing` per /implement workflow — not moving to review or committing.
  timestamp: 2026-07-17T15:53:40.862353+00:00
- actor: claude-code
  id: 01kxrchrzy0w21h886z0wnvdpr
  text: |-
    Iteration 1 — /implement landed green in `doing`. New `public actor StreamingSearchCorpus` (Sources/FoundationModelsRanker/StreamingSearchCorpus.swift) wraps `SearchCorpus` directly rather than turning SearchCorpus itself into an actor or wrapping Searcher's private RetrievalEngine. Rationale: SearchCorpus stays a plain value type since its synchronous API is load-bearing for Searcher's fixed-corpus never-mutated-after-init use and the existing SearchCorpusTests equivalence suite; RetrievalEngine is Searcher-specific and private, wrapping it would drag in irrelevant knobs. Confinement works because every method body has zero internal `await` — each actor call runs to completion atomically, so search always ranks against a complete, never-torn snapshot.

    New Tests/FoundationModelsRankerTests/StreamingSearchCorpusTests.swift — 6 tests including a concurrent stress test (20 add-then-evict producers, 1 survivor producer, 200 concurrent searchers).

    `swift test` → 216 tests / 19 suites (baseline 210/18, net +6/+1, zero regressions). `swift test --sanitize=thread` (full suite) → clean, exit 0, no TSan warnings — directly satisfies the acceptance criterion, no substitute needed (Apple Swift 6.4 toolchain supports it natively).

    TDD followed: test file written first, confirmed RED via build failure ("cannot find StreamingSearchCorpus in scope"), then implemented to GREEN.
  timestamp: 2026-07-17T15:54:01.598902+00:00
depends_on:
- 01KXQYCNC9J4AQEG4Q7XQRBQ19
position_column: doing
position_ordinal: '80'
title: Actor confinement for the mutable streaming corpus
---
## What
The streaming corpus (see the additive add/remove task this depends on) is mutated by a producer while queried concurrently: in `../FoundationModelsAgents`, the recorder chokepoint appends transcript entries while `search agent` tool calls query. The planned Ranker types are value snapshots with no concurrency posture.

Give the mutable streaming corpus a safe one:
- Wrap it in an actor (or document and enforce an explicit confinement rule — decide which, actor preferred for the family style).
- Queries see a consistent corpus: a search never observes a torn mid-add state (snapshot-at-entry semantics are fine).
- add/remove/search are all safe to call from arbitrary tasks.

## Acceptance Criteria
- [ ] Concurrent add + search + remove is data-race free (Swift 6 strict concurrency clean; TSan clean under stress)
- [ ] A query returns results consistent with some complete corpus state (never a partially added item)
- [ ] The confinement choice is documented on the type

## Tests
- [ ] Stress test: many concurrent adds and searches under TSan, assert no crashes and every returned match corresponds to a fully added item
- [ ] Deterministic single-thread behavior unchanged (existing equivalence tests still pass through the actor surface)

## Workflow
- Use /tdd — write failing tests first, then implement to make them pass.