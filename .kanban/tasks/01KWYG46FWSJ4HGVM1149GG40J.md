---
comments:
- actor: claude-code
  id: 01kxedyg4rhbrk7sj70hzeddrz
  text: |-
    Implemented and green.

    **What landed:**
    - `Examples/FullMontyCore/` library target: `Catalog.swift` (50-item developer-CLI-tool `SearchItem` fixture catalog + 4 demo queries, each worded to overlap heavily with exactly one target item so `--no-model` shows a clean top-1 match), `Demo.swift` (`runFullMontyDemo`/`runNoModelDemo`/`runDefaultDemo` plus `formattedMatches`/`printCatalog`/`printResults`/`printDiagnostic`), `LiveRouter.swift` (gated real-model path: `RANKKIT_INTEGRATION_TESTS` env var, `resolveLiveFullMontyProfile()` resolves a live `Router` + tiny `mlx-community/SmolLM-135M-Instruct-4bit` + `mlx-community/bge-small-en-v1.5-4bit` models, `runLiveFullMontyDemo` wires the embedder + a grammar-constrained selection session via `SelectionTier.idEnumGrammar(ids:)` — reused directly rather than reimplemented, since it's already `public`).
    - `Examples/FullMonty/main.swift`: thin executable, three-way gated dispatch (`RANKKIT_INTEGRATION_TESTS` > `--no-model` > default).
    - `Tests/RankKitTests/ExamplesSmokeTests.swift`: 8 tests covering the `--no-model` GPU-free path (per-query ranking, diagnostic reporting, formatting, catalog size) and the selection path driven by `ScriptedAgentSession` fakes (multi-query scripted selection, proving the model is swappable).
    - `Package.swift`: added `mlx-swift-lm` (branch `foundationmodels-fixes`), `swift-huggingface`, `swift-transformers`, and a pinned `swift-jinja` range — mirroring FMR's own pins verbatim — plus a `liveRouterProductDependencies` constant attached only to `FullMontyCore`. The `RankKit` library target's own declaration is untouched (verified via `git diff`).

    **Adaptation (expected, not a defect):** per the documented SDK constraint from ^2gk4k4r/^navjcs9, the installed SDK has no `.fast`, so `Searcher.defaultSessionFactory` already uses `.default`. That leaves no second value for a `--model default` flag to demonstrate, so `FullMonty` omits that flag; `Demo.swift`'s `runDefaultDemo` doc comment records why.

    **Verification:**
    - `swift build` (clean, `.build` removed first): succeeds. Only pre-existing/benign warnings (`swift-jinja` unused-target pin warning, third-party mlx-swift C++ warnings) — identical warnings reproduced in FMR's own `swift build`, confirmed side-by-side.
    - `swift test`: 190/190 tests pass across 16 suites, including all 8 new `ExamplesSmokeTests`.
    - `swift run FullMonty --no-model`: exits 0, prints `[diagnostic] embeddingUnavailable` once per query plus keyword-only ranked results (grep/commit/branch/stash each rank #1 for their respective demo query).
    - Adversarial double-check (subagent, independent `swift build`/`swift test` run): PASS, no functional/correctness/completeness defects found.

    Left in `doing` for `/review`.
  timestamp: 2026-07-13T19:06:02.776513+00:00
depends_on:
- 01KWYG3S45GN3CAR9K0NAVJCS9
position_column: doing
position_ordinal: '80'
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
- [x] `swift run FullMonty --no-model` exits 0 and prints keyword-only results + degradation diagnostic
- [x] `swift build` compiles all targets in CI without GPU/model downloads
- [x] Library target's dependency list unchanged (no MLX/HF leakage)

## Tests
- [x] `Tests/RankKitTests/ExamplesSmokeTests.swift`: invoke `FullMontyCore`'s GPU-free entry directly (FMR's smoke-test pattern) asserting on returned/printed results for the `--no-model` path and, with a scripted fake session, the selection path
- [x] Run `swift test` — exits 0

## Workflow
- Use `/tdd` — write the smoke tests against FullMontyCore first, then the executable wrapper.

## Adaptation note (SDK constraint, carried from ^2gk4k4r / ^navjcs9)
The installed SDK's `SystemLanguageModel` exposes only `.default`, not `.fast`. `Searcher.defaultSessionFactory` (from ^navjcs9) already uses `.default` in `.fast`'s place, so there is no longer a second value for a `--model default` flag to swap to — `FullMonty` ships no `--model` flag; `Demo.swift`'s `runDefaultDemo` doc comment documents this explicitly. Everything else in the acceptance criteria/tests is implemented as specified.