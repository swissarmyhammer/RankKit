---
comments:
- actor: claude-code
  id: 01kxdyk3a0mwavb0qn50q9k2f1
  text: |-
    Implemented via TDD:

    - `Sources/RankKit/TextEmbedding.swift` (new) — `TextEmbedding` protocol, signature byte-identical to both existing copies (verified by direct comparison). Doc comment neutralized per plan.md §4.2.
    - `Sources/RankKit/RoutedEmbedderAdapter.swift` (new) — adapts `RoutedEmbedder` to `TextEmbedding`.
    - `Tests/RankKitTests/Support/FakeEmbedder.swift` (new) — deterministic hash-based `TextEmbedding` test double, ported verbatim (logic-wise) from CodeContextKit's `Tests/CodeContextKitTests/Support/FakeEmbedder.swift`.
    - `Tests/RankKitTests/EmbeddingSeamTests.swift` (new) — ported the primitive-level cases from CodeContextKit's `EmbeddingSeamTests.swift` (determinism, distinctness, L2-normalization/dimension, failure injection). The `TreeSitterWorker`/GRDB integration cases were intentionally not ported — they're CodeContextKit's corpus/storage-specific, out of scope per the task's "primitive-level parts" instruction.

    **Deviation from the literal acceptance criteria, verified and documented**: the task says RoutedEmbedderAdapter should "compile against FoundationModelsRouter `main` (calls `embed(_:)`, not the stale `embed(texts:)` label)", based on plan.md §1/§4.3's claim (dated 2026-07-07) that Router main matches FMR's `embed(_:)` copy. I froze-cloned `FoundationModelsRouter` main fresh and grepped every `func embed` in `Sources/` — **every** embed method, including `RoutedEmbedder.embed(texts:)` itself, uses the labeled form `embed(texts: [String])`. There is no `embed(_:)` anywhere in current main (commit `a3d8c04e4a7598d9c261d818ef891cfffd51bcc9`, which is exactly what's pinned in this repo's own `Package.resolved` — i.e. what `swift build`/`swift test` here actually links against). So Router's API reverted or the plan's premise was simply wrong; either way it's stale now. I implemented `RoutedEmbedderAdapter.embed(_:)` to call `routedEmbedder.embed(texts: texts)` (CodeContextKit's original labeling) so the adapter actually compiles against the real dependency, and documented the discrepancy at length in the file's header comment, citing the commit hash and the grep evidence.

    Bonus finding from the adversarial double-check: both sibling repos' *own current source* already call `embed(texts:)` in their `RoutedEmbedderAdapter` implementations — only FMR's doc comment still claimed `embed(_:)`. So this port's doc comment is now more accurate than FMR's own, not a new drift.

    **plan.md itself is stale on this one point** (§1's table and §3's file listing both assert FMR's `embed(_:)` copy is canonical) — worth a follow-up correction to plan.md so future phases (the `Searcher` facade in §3a shows `RoutedEmbedderAdapter(embedder: router.embedder)` — separate concern, not affected) don't re-inherit the wrong assumption.

    Verification: `swift build` clean (0 errors), `swift test` — 82 tests, 7 suites, 0 failures, 0 warnings from new code. Adversarial `double-check` agent independently re-cloned Router at the pinned commit, re-verified the API claim, re-ran build+test, confirmed protocol byte-identity against both source repos, and confirmed FakeEmbedder fidelity. Verdict: PASS, no findings.

    All acceptance criteria met (with the one documented, verified correction). Leaving in `doing` for `/review`.
  timestamp: 2026-07-13T14:37:40.544823+00:00
depends_on:
- 01KWYFYBDKWS53V76XPWMA76JF
position_column: done
position_ordinal: '8480'
title: 'Port embedding seam: TextEmbedding + RoutedEmbedderAdapter'
---
## What
Copy from FoundationModelsMetadataRegistry (its adapter matches Router `main`'s `embed(_:)` — plan.md §4.3):
- `../FoundationModelsMetadataRegistry/Sources/FoundationModelsMetadataRegistry/Embedding/TextEmbedding.swift` → `Sources/RankKit/TextEmbedding.swift` (protocol `func embed(_ texts: [String]) async throws -> [[Float]]`, unchanged)
- `.../Embedding/RoutedEmbedderAdapter.swift` → `Sources/RankKit/RoutedEmbedderAdapter.swift` (verbatim)

Rewrite doc comments neutrally ("conformers embed a batch of texts; tests substitute a deterministic double"), strip port-attribution headers.

**Note (see task comments): plan.md's premise that Router `main` exposes `embed(_:)` is stale.** A fresh clone of FoundationModelsRouter `main` (commit `a3d8c04`, matching this repo's own `Package.resolved` pin) shows every `embed` method, including `RoutedEmbedder`'s, uses the labeled `embed(texts:)` form — the same label CodeContextKit's copy already used. `RoutedEmbedderAdapter` was implemented to call `embed(texts:)` so it actually compiles against the real dependency; the discrepancy is documented in the file's header comment and verified by an adversarial double-check.

## Acceptance Criteria
- [x] `TextEmbedding` signature unchanged from both existing copies
- [x] `RoutedEmbedderAdapter` compiles against FoundationModelsRouter `main` (calls `embed(texts:)` — verified to be the actual current label; see note above and task comments)
- [x] A deterministic `FakeEmbedder` test double exists in the test target

## Tests
- [x] `Tests/RankKitTests/EmbeddingSeamTests.swift`: port the primitive-level parts of `../CodeContextKit/Tests/CodeContextKitTests/EmbeddingSeamTests.swift` plus a `FakeEmbedder` (model on `../CodeContextKit/Tests/CodeContextKitTests/Support/FakeEmbedder.swift`)
- [x] Run `swift test` — exits 0 (no GPU, no live Router)

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.