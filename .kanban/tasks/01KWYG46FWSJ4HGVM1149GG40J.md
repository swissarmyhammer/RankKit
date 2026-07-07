---
depends_on:
- 01KWYG3S45GN3CAR9K0NAVJCS9
position_column: todo
position_ordinal: 8f80
title: 'FullMonty example: runnable end-to-end demo'
---
## What
Create `Examples/FullMontyCore/` (library) + `Examples/FullMonty/` (thin executable) per plan.md §3a, following FMR's example pattern (`exampleCoreTarget`/`exampleExecutableTarget` in `../FoundationModelsMetadataRegistry/Package.swift`):
- Fixture catalog of ~50 `SearchItem`s, a handful of queries, printed matches with per-signal scores and the model's final selection.
- Default path: runs out of the box on the on-device system model (`.fast`); `--model default` flag shows the one-argument swap to `.default`.
- `--no-model`: degraded keyword-only path printing the diagnostic — this is the CI-safe path.
- Behind the gated env var (mirror FMR's `METADATA_REGISTRY_INTEGRATION_TESTS` convention, e.g. `RANKKIT_INTEGRATION_TESTS`): resolve a live Router + tiny mlx-community model for both embedder and selection session (reuse FMR's `LiveRouterSupport` pattern).
- Example-only MLX/Hugging Face product dependencies attach to the example targets in `Package.swift`, never the library target.

## Acceptance Criteria
- [ ] `swift run FullMonty --no-model` exits 0 and prints keyword-only results + degradation diagnostic
- [ ] `swift build` compiles all targets in CI without GPU/model downloads
- [ ] Library target's dependency list unchanged (no MLX/HF leakage)

## Tests
- [ ] `Tests/RankKitTests/ExamplesSmokeTests.swift`: invoke `FullMontyCore`'s GPU-free entry directly (FMR's smoke-test pattern) asserting on returned/printed results for the `--no-model` path and, with a scripted fake session, the selection path
- [ ] Run `swift test` — exits 0

## Workflow
- Use `/tdd` — write the smoke tests against FullMontyCore first, then the executable wrapper.