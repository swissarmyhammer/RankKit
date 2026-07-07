---
depends_on:
- 01KWYFYBDKWS53V76XPWMA76JF
position_column: todo
position_ordinal: '8380'
title: 'Port embedding seam: TextEmbedding + RoutedEmbedderAdapter'
---
## What
Copy from FoundationModelsMetadataRegistry (its adapter matches Router `main`'s `embed(_:)` — plan.md §4.3):
- `../FoundationModelsMetadataRegistry/Sources/FoundationModelsMetadataRegistry/Embedding/TextEmbedding.swift` → `Sources/RankKit/TextEmbedding.swift` (protocol `func embed(_ texts: [String]) async throws -> [[Float]]`, unchanged)
- `.../Embedding/RoutedEmbedderAdapter.swift` → `Sources/RankKit/RoutedEmbedderAdapter.swift` (verbatim)

Rewrite doc comments neutrally ("conformers embed a batch of texts; tests substitute a deterministic double"), strip port-attribution headers.

## Acceptance Criteria
- [ ] `TextEmbedding` signature unchanged from both existing copies
- [ ] `RoutedEmbedderAdapter` compiles against FoundationModelsRouter `main` (calls `embed(_:)`, not the stale `embed(texts:)` label)
- [ ] A deterministic `FakeEmbedder` test double exists in the test target

## Tests
- [ ] `Tests/RankKitTests/EmbeddingSeamTests.swift`: port the primitive-level parts of `../CodeContextKit/Tests/CodeContextKitTests/EmbeddingSeamTests.swift` plus a `FakeEmbedder` (model on `../CodeContextKit/Tests/CodeContextKitTests/Support/FakeEmbedder.swift`)
- [ ] Run `swift test` — exits 0 (no GPU, no live Router)

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.