---
position_column: todo
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