---
depends_on:
- 01KXQYCNC9J4AQEG4Q7XQRBQ19
position_column: todo
position_ordinal: '8180'
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