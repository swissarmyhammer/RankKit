---
depends_on:
- 01KWYFYBDKWS53V76XPWMA76JF
position_column: todo
position_ordinal: '8180'
title: 'Port identical search primitives: Trigram, Tokenizer, RRF, Hit'
---
## What
Copy the four byte-identical files (plan.md §1 table) into `Sources/RankKit/`, taking the FoundationModelsMetadataRegistry copies as source:
- `../FoundationModelsMetadataRegistry/Sources/FoundationModelsMetadataRegistry/Search/Trigram.swift` → `Sources/RankKit/Trigram.swift`
- `.../Search/Tokenizer.swift` → `Sources/RankKit/Tokenizer.swift`
- `.../Search/RRF.swift` → `Sources/RankKit/RRF.swift`
- `.../Search/Hit.swift` → `Sources/RankKit/Hit.swift` (contains `Hit` + `Signals`)

Strip the "Ported from CodeContextKit's …" header comments; replace with one attribution note (lineage: Rust `swissarmyhammer-search` → CodeContextKit → RankKit, per plan.md §3). No logic changes — public API stays exactly as-is.

## Acceptance Criteria
- [ ] All four files compile in RankKit with public API identical to the FMR copies (same type/member names and signatures)
- [ ] No domain language (chunks/symbols/catalogs/metadata) in doc comments
- [ ] Ported tests pass unchanged except for imports/suite names

## Tests
- [ ] Port `../FoundationModelsMetadataRegistry/Tests/FoundationModelsMetadataRegistryTests/TrigramTests.swift` and `RRFTests.swift` to `Tests/RankKitTests/`
- [ ] Port the trigram/tokenizer/RRF cases from `../CodeContextKit/Tests/CodeContextKitTests/RankerTests.swift` (keep overlapping cases — they encode each repo's edge-case history, plan.md §5)
- [ ] Run `swift test` — exits 0

## Workflow
- Use `/tdd` — port the tests first (failing), then the source files to make them pass.