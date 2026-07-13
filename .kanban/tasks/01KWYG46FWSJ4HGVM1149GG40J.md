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
- actor: claude-code
  id: 01kxefhfwtfyhe8s5e31qr7g3j
  text: |-
    Fixed all 11 cited review findings (doc-comment first line missing a period) plus 8 additional un-cited instances of the same pattern in the same 4 files, root-caused as a project-wide convention rather than one-off fixes:

    - Examples/FullMontyCore/Catalog.swift: 2 doc comments fixed (toolCatalog, demoQueries).
    - Examples/FullMontyCore/Demo.swift: 8 doc comments fixed (FullMontyResult typealias, runFullMontyDemo, runNoModelDemo, runDefaultDemo, printCatalog, formattedMatches, printDiagnostic — printResults' doc was already correct).
    - Examples/FullMontyCore/LiveRouter.swift: 5 doc comments fixed (rankKitIntegrationEnvVar, LiveDemoModels, resolveLiveFullMontyProfile, runLiveFullMontyDemo — isRankKitIntegrationEnabled's doc was already correct).
    - Tests/RankKitTests/ExamplesSmokeTests.swift: 2 doc comments fixed (suite-level doc, result(containing:in:) helper).

    Fix pattern: for every multi-line doc comment whose first line didn't end in a period, added a condensed one-sentence summary line ending in a period, followed by a `///` blank separator line, then kept the original detailed text verbatim as a following paragraph. No content was removed, only a proper period-terminated summary line was prepended. Used the reviewer's exact suggested summary text where a finding was cited; wrote analogous condensed summaries for the un-cited instances following the same style.

    Verification:
    - Grep-based scan (awk over `///` blocks) of all 4 files: zero doc comments remain whose first line lacks a trailing period.
    - `mcp__sah__review review file` re-run against each of the 4 files individually: 0 findings on all four (was 11 findings before the fix).
    - `swift build`: succeeds, only pre-existing benign warnings (swift-jinja unused-target pin, third-party mlx-swift C++ warnings) — same as before this change.
    - `swift test`: 190/190 tests pass across 16 suites.

    Checklist items flipped to [x]. Left in `doing` for `/review`.
  timestamp: 2026-07-13T19:33:53.690409+00:00
- actor: claude-code
  id: 01kxefmavwfqxb14zja85d1wpw
  text: |-
    Adversarial double-check (subagent, independent review): PASS, no defects found.

    - Verified `git diff` is comment-only across the 4 files (91 insertions / 35 deletions), no production code touched.
    - Confirmed all 11 originally-cited findings fixed, matching reviewer-suggested summary text.
    - Independently swept all `///` blocks in the 4 files: 17 total doc-comment blocks, all now end their first line in a period, including previously-compliant ones left untouched (printResults, isRankKitIntegrationEnabled).
    - Confirmed no content lost — each edit is "prepend condensed summary + blank `///` + original detail" verbatim.
    - Fresh `swift build` → Build complete (only pre-existing unrelated warnings). Fresh `swift test` → 190/190 tests pass, 16 suites.

    Task is green. Left in `doing` for `/review`.
  timestamp: 2026-07-13T19:35:26.844735+00:00
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

## Review Findings (2026-07-13 14:08)

- [x] `Examples/FullMontyCore/Catalog.swift:17` — First line of doc comment doesn't end with a period — doc comment summary must be a complete sentence ending with period on the first line. Move the summary onto a single first line ending with a period: `/// A fixture catalog of ~50 common command-line tools, each an id and one-line description.`.
- [x] `Examples/FullMontyCore/Catalog.swift:32` — First line of doc comment doesn't end with a period — doc comment summary must be a complete sentence ending with period on the first line. Condense the summary onto the first line ending with period: `/// Demo queries that overlap with catalog items to show keyword-only retrieval working well.`.
- [x] `Examples/FullMontyCore/Demo.swift:9` — First line of doc comment doesn't end with a period — doc comment summary must be a complete sentence ending with period on the first line. Condense opening to: `/// Runs all demo queries against the catalog through a Searcher built from provided ingredients.` Then continue with expanded detail on subsequent paragraphs.
- [x] `Examples/FullMontyCore/Demo.swift:43` — First line of doc comment doesn't end with a period — doc comment summary must be a complete sentence ending with period on the first line. Condense opening: `/// The default path: keyword-only retrieval with real agent selection on the on-device system model.` Then expand on next paragraph.
- [x] `Examples/FullMontyCore/Demo.swift:62` — First line of doc comment doesn't end with a period — doc comment summary must be a complete sentence ending with period on the first line. Condense to: `/// Prints the tool catalog, one line per item.` Then expand with detail on next paragraph.
- [x] `Examples/FullMontyCore/Demo.swift:70` — First line of doc comment doesn't end with a period — doc comment summary must be a complete sentence ending with period on the first line. Condense opening: `/// Formats matches into lines with rank, id, score, and signal breakdown.` Then expand on next paragraph.
- [x] `Examples/FullMontyCore/Demo.swift:88` — First line of doc comment doesn't end with a period — doc comment summary must be a complete sentence ending with period on the first line. Condense opening: `/// Prints a single diagnostic emitted by Searcher or its selection tier.` Then expand on next paragraph.
- [x] `Examples/FullMontyCore/LiveRouter.swift:14` — First line of doc comment doesn't end with a period — doc comment summary must be a complete sentence ending with period on the first line. Condense opening: `/// Environment variable enabling FullMonty's real-model path (name: `rankKitIntegrationEnvVar`).` Then expand on next paragraph.
- [x] `Examples/FullMontyCore/LiveRouter.swift:26` — First line of doc comment doesn't end with a period — doc comment summary must be a complete sentence ending with period on the first line. Condense opening: `/// Resolves a real, on-device model profile through a live Router.` Then expand on next paragraph.
- [x] `Examples/FullMontyCore/LiveRouter.swift:33` — First line of doc comment doesn't end with a period — doc comment summary must be a complete sentence ending with period on the first line. Condense opening: `/// Runs the full demo over a live Router-resolved profile with embedding and selection.` Then expand on next paragraph.
- [x] `Tests/RankKitTests/ExamplesSmokeTests.swift:22` — First line of doc comment doesn't end with a period — documentation comment summary must be a complete sentence ending with period on the first line, even for private declarations. Condense to: `/// Locates the FullMontyResult matching the given substring in its query.` Then expand with detail on next paragraph.
