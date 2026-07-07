---
position_column: todo
position_ordinal: '80'
title: Scaffold RankKit Swift package
---
## What
Create the SwiftPM skeleton per plan.md §3:
- `Package.swift`: swift-tools 6.1, `platforms: [.macOS("27.0")]`, one library product/target `RankKit` at `Sources/RankKit/`, test target `RankKitTests` at `Tests/RankKitTests/`. One dependency: `.package(url: "https://github.com/swissarmyhammer/FoundationModelsRouter", branch: "main")` (remote URL, family CI convention — no local path deps). Use named constants for repeated identifiers, mirroring `../FoundationModelsMetadataRegistry/Package.swift`.
- `Sources/RankKit/RankKit.swift`: placeholder doc-comment file so the target compiles.
- `README.md`: short stub (name + one-paragraph purpose; full README comes later).
- CI workflow calling the family's shared `swift-ci.yaml` reusable workflow — copy the pattern from `../FoundationModelsMetadataRegistry/.github/workflows/`.

## Acceptance Criteria
- [ ] `swift build` succeeds on macOS 27 toolchain
- [ ] `swift test` runs (green, with the package smoke test below)
- [ ] CI workflow file present and references the shared family workflow
- [ ] `Package.resolved` committed (pins Router branch dep, per family convention)

## Tests
- [ ] `Tests/RankKitTests/PackageTests.swift`: a trivial smoke test that imports `RankKit` and asserts a placeholder symbol exists (mirror `../FoundationModelsMetadataRegistry/Tests/.../PackageTests.swift`)
- [ ] Run `swift test` — exits 0

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.