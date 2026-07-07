---
depends_on:
- 01KWYFYBDKWS53V76XPWMA76JF
position_column: todo
position_ordinal: '8780'
title: Add CosineScoring utility (vDSP matrix + scalar)
---
## What
Create `Sources/RankKit/CosineScoring.swift` (plan.md §6 phase 2) carrying both existing cosine strategies side by side:
- `matvecScores(matrix:rowCount:dimension:queryVector:)` — the contiguous row-major `vDSP_mmul` matrix–vector product, ported from `../CodeContextKit/Sources/CodeContextKit/Search/SearchCorpus.swift` (`matvecCosineScores` + `multiplyMatrixByVector`), including the zero-fill guards. Requires L2-normalized rows/query (dot product == cosine).
- `cosineSimilarity(_:_:)` — the scalar per-row form ported from `MetadataSearcher.cosineSimilarity` in FMR (handles un-normalized vectors, length mismatch → 0.0, zero magnitude → 0.0).

`import Accelerate` is Apple-only — fine at the macOS 27 floor.

## Acceptance Criteria
- [ ] vDSP path matches a scalar dot-product reference on synthetic fixtures (the existing CCK test approach)
- [ ] Scalar path matches FMR's documented edge cases (mismatched lengths → 0.0, zero magnitude → 0.0, range [-1, 1])

## Tests
- [ ] `Tests/RankKitTests/CosineScoringTests.swift`: port the matvec-vs-scalar reference cases from CCK's tests; add scalar edge-case coverage from FMR's behavior
- [ ] Run `swift test` — exits 0

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.