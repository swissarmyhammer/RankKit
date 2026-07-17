---
comments:
- actor: claude-code
  id: 01kxqyqp8xnp4736sx1h9qzk3x
  text: 'Picked up by /finish (scoped-batch, no filter). Iteration 1: dispatching /implement. This card is BLOCKING two others (^c79yg0f actor confinement, ^rayd7bq incremental embed), so landing it unblocks both.'
  timestamp: 2026-07-17T11:52:35.357316+00:00
- actor: claude-code
  id: 01kxqz1bngq28aa36csxb59567
  text: |-
    Research done. Key finding that decides the "fiddly part": BM25 globals are ALREADY recomputed at query time — `BM25Corpus(queryTokens:documents:)` is constructed per query inside `HybridRanker.computeBM25Ranking` in a single pass over the live `documents`, and df is tracked only for the query's terms. So under add/remove the globals are correct by construction; there is no cached global state to invalidate. Decision: keep query-time recomputation (documented on BM25Corpus), do NOT maintain an incremental df table — a whole-vocabulary df map would cost memory and per-mutation work for statistics no query reads, and would add a staleness failure mode where today there is none.

    Design: new public value type `SearchCorpus` (Sources/FoundationModelsRanker/SearchCorpus.swift) = the queryable corpus: parallel `ids`/`documents` arrays (ready for HybridRanker without a per-query rebuild) + id->row dictionary for text/summary/group. `init(items:)` delegates to `add(items:)`, so batch and incremental share one preprocessing path by construction. Conforms to SelectionCatalog. Replaces `Searcher`'s private `ItemCatalog` (which duplicated the same first-occurrence-id-wins storage) so the corpus really is the thing the ranking pipeline queries, not an orphan type.

    Group key: chose an explicit group over id-prefix (prefix is fragile). Adding `Searchable.group: String?` with a `nil` default extension — mirrors exactly how `summary` already defaults, so every existing conformer is source-compatible, and a consumer's own transcript-entry type exposes its runID directly instead of being forced into homogeneous per-call batches.

    Deliberately OUT of scope here (belongs to ^rayd7bq): embed-on-add. `add(items:)` stays lexical-only precompute (weighted tf, doc length, trigram sets), exactly as this card enumerates.
  timestamp: 2026-07-17T11:57:52.176862+00:00
- actor: wballard
  id: 01kxqz41pymf3ds9zn9k9gd78w
  text: 'Second consumer: FoundationModelsCodeContext. Its SearchCorpus is generation-invalidated wholesale reload today — one file re-index reloads and re-tokenizes the entire corpus. With this API, a file edit becomes remove-by-group(filePath) + add(re-parsed chunks): O(file) instead of O(corpus). Design implication: the group key must be generic (session id for FoundationModelsAgents transcripts, file path for CCK), not session-flavored. Note CCK''s packed vDSP cosine matrix stays wholesale-repacked on its side (cheap memcpy of already-persisted vectors) — the lexical corpus is what mutates additively; the matrix seam is the reserved CosineScoring phase-2 item.'
  timestamp: 2026-07-17T11:59:20.286716+00:00
position_column: doing
position_ordinal: '80'
title: 'Streaming corpus: additive add/remove with incremental BM25 globals'
---
## What
The planned corpus is construct-once: `Searcher(items)` takes the full item set, and mutation lives in consumers as `update(items:)` wholesale rebuilds (the MetadataIndex pattern). The consumer `../FoundationModelsAgents` (plan.md §10 item 4, decision #21) needs a **streaming corpus** for its `search agent` op over transcript entries: items append continuously (one per recorder-chokepoint event) and evict by group (run release). Rebuild-per-append is the wrong shape.

Add additive mutation to the corpus the ranking pipeline queries:
- `add(items: [SearchItem])` — per-item precompute at add time (weighted term-frequency map, document length, canonical trigram sets), reusing the exact batch-build preprocessing; no rebuild of existing rows.
- `remove(ids: [String])` plus remove-by-group (id-prefix or an explicit group key) so a consumer can evict all entries of one session in one call.
- **BM25 corpus-global statistics** (document-frequency table, average document length) kept correct under interleaved add/remove — either incrementally maintained or cheaply recomputed at query time; decide, document the choice, and test it. This is the fiddly part: idf/avgdl are whole-corpus values.
- Query path unchanged: BM25 + trigram (+ cosine when present) fused by RRF with the absent-signal rule, served from the live corpus without rebuild.

Storage stays out of scope: the Ranker remains storage-free (in-memory precompute only); persistence, when a consumer wants it, is that consumer's corpus concern — exactly the existing CCK/FMR split.

## Acceptance Criteria
- [ ] `add(items:)` and `remove(ids:)` / remove-by-group exist on the queryable corpus
- [ ] Ranking equivalence: a corpus built by N successive `add` calls ranks identically to the same items built in one batch construction
- [ ] BM25 globals are correct after interleaved add/remove (idf and avgdl match a from-scratch build of the surviving items)
- [ ] Remove-by-group evicts every item of the group; queries afterward return no matches for evicted content

## Tests
- [ ] Batch-vs-incremental equivalence test (same items, same query, identical ranking and scores)
- [ ] Interleaved add/remove followed by a from-scratch rebuild comparison of BM25 globals
- [ ] Evict-group then query: empty for that group, unchanged results for others

## Workflow
- Use /tdd — write failing tests first, then implement to make them pass.