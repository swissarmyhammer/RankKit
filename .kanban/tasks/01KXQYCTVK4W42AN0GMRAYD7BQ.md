---
comments:
- actor: claude-code
  id: 01kxrf2ccbt0qr98ydzfqk7wce
  text: |-
    Picked up by /finish (scoped-batch, no filter), now that ^xqrbq19 and ^c79yg0f are both done. Iteration 1: dispatching /implement.

    Note from ^xqrbq19: Searcher still holds `itemEmbeddings` as an array positionally aligned with `corpus.ids`, safe today only because Searcher never mutates its corpus (a `let` on a value type). This task making add(items:) embed will desync that array unless the embedding moves onto the row (or an equivalent fix) — implementer should read that constraint before designing.
  timestamp: 2026-07-17T16:38:02.891748+00:00
- actor: claude-code
  id: 01kxrnd4kd6as09zagdnym4jjn
  text: |-
    Implemented via TDD, driven to green. `swift test`: 230 tests / 19 suites passing, exit 0 (up from 216 baseline; +14 new tests). Left in `doing` per /implement workflow — not moved to review.

    **Design.** Embeddings are now stored on `SearchCorpus`'s row, keyed by id (`Row.embedding: [Float]?`), not a parallel positional array — per the constraint flagged by ^xqrbq19: `Searcher`'s `RetrievalEngine.itemEmbeddings` array is only safe because `Searcher` never mutates its corpus after init, which no longer holds once `add(items:)` streams. `SearchCorpus.add(items:)` now returns `[String]` (`@discardableResult`) — exactly the newly-added ids, excluding dropped duplicates — so a caller knows precisely what to embed. New `embedding(forID:)` getter and `setEmbedding(_:forID:ifTextMatches:)` setter round out the storage API.

    `StreamingSearchCorpus` gained `embedder: (any TextEmbedding)?` and `onDiagnostic` stored properties (both inits). `add(items:)` is now `async`: embeds exactly the ids `corpus.add(items:)` reports as new, in one batched `embedder.embed(_:)` call; a no-new-items or no-embedder add never calls the embedder at all. `search(_:limit:)` is now `async`: embeds only the query, fusing cosine into `HybridRanker.topMatches` when the corpus is fully embedded, else reports `.embeddingUnavailable` and degrades to keyword-only.

    **Two real bugs found and fixed along the way (via the mandatory adversarial double-check, not by inspection alone):**
    1. Since `add`/`search` now suspend at the embed call, `search`'s original implementation could desync `cosineScores`'s array (built from `corpus.ids` at one instant) against `corpus.ids`/`documents` re-read after the suspension — tripping `HybridRanker`'s alignment precondition (a crash) under concurrent add/remove. Fixed by snapshotting the whole `corpus` value (cheap COW) once, synchronously, before the suspension, and ranking/resolving entirely from that snapshot.
    2. `setEmbedding`'s original liveness-only check couldn't detect an id removed-and-re-added-with-different-text while its embed call was still in flight — it would silently attach a stale vector to the wrong row's text, no diagnostic, no way to detect it later. Fixed by changing the write to `setEmbedding(_:forID:ifTextMatches:)`, guarded on the row's *current* text still matching what was embedded (mirrors `FoundationModelsMetadataRegistry.MetadataIndex.mergingEmbeddings`'s block-hash guard against the identical race shape).

    Both fixes are covered by tests that fail under mutation-testing (reverted the guard, confirmed the specific new test fails for the right reason, restored, confirmed green) — including a genuine concurrency-injecting regression (`aStaleInFlightEmbedForAResurrectedIDNeverOverwritesItsFreshVector` in StreamingSearchCorpusTests.swift) built on a new `GatedEmbedder` test double (Tests/.../Support/GatedEmbedder.swift) that deterministically parks an embed call mid-flight so the race can be reproduced without hoping `withTaskGroup` stress happens to hit it.

    **Files touched:**
    - `Sources/FoundationModelsRanker/SearchCorpus.swift` — `Row.embedding`, `add(items:)` returns `[String]`, `embedding(forID:)`, `setEmbedding(_:forID:ifTextMatches:)`.
    - `Sources/FoundationModelsRanker/StreamingSearchCorpus.swift` — `embedder`/`onDiagnostic` properties, both inits (batch init now `async`), async `add(items:)`, async `search(_:limit:)` with snapshot fix, private `cosineScores(forQuery:snapshot:)`.
    - `Tests/FoundationModelsRankerTests/SearchCorpusTests.swift` — 6 new tests (add-return-value, embedding get/set/no-op/remove/recycled-id, stale-text-rejected).
    - `Tests/FoundationModelsRankerTests/StreamingSearchCorpusTests.swift` — 3 existing `init(items:)` call sites updated to `await`; 6 new tests (embed-call-count economy, cosine-participates, remove-drops-embedding, recycled-id-reembeds, no-embedder diagnostic, the genuine race regression, plus an embedder-configured concurrent stress test).
    - NEW `Tests/FoundationModelsRankerTests/Support/CountingEmbedder.swift`, NEW `Tests/FoundationModelsRankerTests/Support/GatedEmbedder.swift`.

    Did NOT run `swift format` (known dead end per ^xqrbq19's notes); hand-verified zero tabs in every touched/new file. `Package.resolved` churn from the environment was reverted each time before finishing (`git checkout -- Package.resolved`), and the final `git status` shows no `Package.resolved` diff.

    Acceptance criteria and Tests section (task description) all checked off — see the exact test names above for the "N adds → N item-embed calls / re-add doesn't re-embed / M searches → M query-embed calls" and "no-embedder path" requirements specifically.
  timestamp: 2026-07-17T18:28:46.829951+00:00
- actor: claude-code
  id: 01kxrne7b0ttwv1dp65r1ethcv
  text: |-
    Iteration 1 — /implement landed green in `doing`. `swift test` → 230 tests / 19 suites (baseline 216, +14 new).

    Design: embeddings moved onto the row (`Row.embedding: [Float]?` in SearchCorpus.swift), keyed by id, NOT a parallel positional array — directly addresses the desync risk flagged from ^xqrbq19. `SearchCorpus.add(items:)` now `@discardableResult` returns the ids actually added (excluding dropped duplicates). New `embedding(forID:)` / `setEmbedding(_:forID:ifTextMatches:)`. `StreamingSearchCorpus` gained `embedder`/`onDiagnostic`; `add(items:)` and `search(_:limit:)` are now `async` — add embeds exactly the newly-added ids in one batched call, search embeds only the query and fuses cosine when the corpus is fully embedded, else reports `.embeddingUnavailable` and degrades to keyword-only.

    **Two real concurrency bugs found by adversarial double-check (not the implementer's own inline review) and fixed:**
    1. search's cosine array could desync from corpus.ids/documents across its new suspension point under concurrent add/remove, tripping HybridRanker's alignment precondition (a crash). Fixed by snapshotting the whole corpus value once before the suspension point.
    2. setEmbedding's liveness-only guard couldn't detect an id removed-and-re-added-with-different-text while its embed was in flight — would silently corrupt the new row with a stale vector. Fixed with ifTextMatches guard (mirrors MetadataIndex.mergingEmbeddings's block-hash guard in the sibling package).

    Both proven via mutation-tested regressions, including a genuine concurrency-injecting test using a new `GatedEmbedder` test double that deterministically parks an embed call mid-flight to reproduce the race rather than hoping stress testing hits it.

    Files: SearchCorpus.swift, StreamingSearchCorpus.swift, SearchCorpusTests.swift, StreamingSearchCorpusTests.swift, new Support/CountingEmbedder.swift, new Support/GatedEmbedder.swift.
  timestamp: 2026-07-17T18:29:22.400962+00:00
depends_on:
- 01KXQYCNC9J4AQEG4Q7XQRBQ19
position_column: doing
position_ordinal: '80'
title: Incremental embed on the streaming add path
---
## What
Incremental embedding is currently planned only inside `update(items:)` (re-embed items whose rendered text changed). The streaming corpus (see the additive add/remove task this depends on) needs the same economy on its add path:
- `add(items:)` with an embedder configured embeds exactly the newly added items, at add time — existing embeddings are never touched, and nothing embeds at query time except the query string itself.
- `add(items:)` without an embedder stays lexical-only and the existing keyword-only diagnostic behavior is unchanged.
- Removal drops the item's embedding with the item.

## Acceptance Criteria
- [ ] With an embedder: each added item is embedded exactly once, at add time; cosine participates in RRF for those items immediately
- [ ] Per query, only the query string is embedded (one embed call per search)
- [ ] Without an embedder: adds succeed, retrieval is keyword-only, the reported diagnostic still fires — never silent

## Tests
- [ ] Counting fake embedder: N adds → exactly N item-embed calls; M searches → exactly M query-embed calls; re-adding an unchanged id does not re-embed
- [ ] No-embedder path: add + search yields BM25/trigram-only results plus the diagnostic

## Workflow
- Use /tdd — write failing tests first, then implement to make them pass.