---
depends_on: []
position_column: todo
position_ordinal: '9280'
title: 'CCK: agent-selection mode in search code'
---
## What
In `../CodeContextKit` (plan.md §6 phase 4): give `SearchCode` the selection tier over its RRF candidates — selection is a reranking/pruning stage OVER RRF, never a replacement:
- **Precondition**: RankKit `main` on GitHub contains the generalized `SelectionTier`/`SelectionCatalog`.
- Add a `SearchMode` mirroring FMR's: `.retrieval` (today's behavior, unchanged, stays the DEFAULT), `.selection` (agent picks), `.auto` (selection when a session factory is configured, else retrieval). Thread it through `Ops/SearchCode.swift` and `CodeContext`'s `search code` op (`CodeContext.swift` / `CodeContextState.swift` wiring).
- `CodeContext` accepts an optional `SelectionConfig` (RankKit's — session factory, code-flavored preamble like "you select source-code chunks that answer the question…", `candidateLimit`). Absent one: `.selection` throws (mirror FMR's `SelectionTierUnavailable`), `.auto` degrades loudly to `.retrieval`.
- A code corpus will essentially always be over `capacityCharacterLimit`, so the over-budget path runs: RRF ranks exactly as today, top-`candidateLimit` chunk summaries (from the ChunkSelectionCatalog task) seed a one-off session, the model returns the fewest chunk ids answering the intent, results keep their real fused `score`/`signals`.

## Acceptance Criteria
- [ ] `.retrieval` results byte-identical to before this change (existing `SearchCodeTests` untouched and green)
- [ ] `.selection` with a scripted fake session returns exactly the fake-selected chunks, retrieval scores intact, in model call-order
- [ ] `.selection` without a config throws; `.auto` without a config returns retrieval results and reports the degradation
- [ ] `candidateLimit` default chosen from the measured prefix sizes (ChunkSelectionCatalog task's data), documented in code
- [ ] Downstream dependents of CCK still build (re-run the dependent-build checks from the "Verify downstream dependents" task — this task changes CCK's public surface after that verification first ran)

## Tests
- [ ] `Tests/CodeContextKitTests/SearchCodeSelectionTests.swift`: scripted `AgentSession` fakes over fixture corpora — selection happy path, unknown-id filtering, no-config error, auto degradation
- [ ] One gated live integration test behind an env var (mirror FMR's `METADATA_REGISTRY_INTEGRATION_TESTS` convention)
- [ ] Run `swift test` in `../CodeContextKit` — exits 0 without GPU

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.