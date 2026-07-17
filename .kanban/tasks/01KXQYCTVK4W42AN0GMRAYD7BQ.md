---
depends_on:
- 01KXQYCNC9J4AQEG4Q7XQRBQ19
position_column: todo
position_ordinal: '8280'
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