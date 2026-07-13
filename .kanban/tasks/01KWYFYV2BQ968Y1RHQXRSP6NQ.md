---
comments:
- actor: claude-code
  id: 01kxdw3jm5wdry70zb605g7bk3
  text: |-
    Implemented via TDD:

    - RED: wrote Tests/RankKitTests/TrigramTests.swift and RRFTests.swift (ported verbatim from FoundationModelsMetadataRegistry's TrigramTests.swift/RRFTests.swift, only `@testable import FoundationModelsMetadataRegistry` -> `import RankKit`), plus Tests/RankKitTests/RankerTests.swift (ported from CodeContextKit's RankerTests.swift — Tokenizer/Trigram-Dice/RRF/Hit-Signals sections only; BM25 sections excluded since BM25.swift is a separate, still-blocked kanban task "Port BM25 with neutral field-weight names"). Confirmed `swift test` failed to build (cannot find 'Trigram'/'Tokenizer'/'RRF'/'Hit' in scope) — correct RED.
    - GREEN: added Sources/RankKit/{Trigram,Tokenizer,RRF,Hit}.swift, ported verbatim from FoundationModelsMetadataRegistry's Search/ copies (confirmed byte-identical to both FMR and CodeContextKit originals modulo header comments via diff). Replaced the "Ported from CodeContextKit's …" header with a single attribution note per plan.md §3. Two body doc-comment references to "chunk" (in Trigram.swift and RRF.swift) were reworded to "document" to satisfy the "no domain language" acceptance criterion — the only textual deviation from the FMR source. `swift test` now green: 51 tests across 4 suites (TrigramTests, RRFTests, RankerTests, PackageTests), exit 0. `swift build` also green.
    - Deliberately dropped (not adapted) CodeContextKit's `fusedBm25AndTrigramSignalsRankSymbolPathMatchFirst` golden test — it fuses BM25 with trigram, and BM25 isn't ported yet (separate task). Left an explanatory comment in RankerTests.swift instead of inventing a substitute test.
    - Renamed one test literal id from "chunk-1" to "doc-1" in the ported Hit/Signals test for the same neutral-naming reason.
    - really-done: ran `swift build` and `swift test` fresh (both exit 0), then spawned the `double-check` adversarial reviewer — verdict PASS, no findings (diff scoped only to the 4 new Sources files + 3 new Tests files, no Package.swift changes, no domain-language leakage in Sources/).

    Task left in `doing`, ready for `/review`.
  timestamp: 2026-07-13T13:54:14.789800+00:00
depends_on:
- 01KWYFYBDKWS53V76XPWMA76JF
position_column: doing
position_ordinal: '80'
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
- [x] All four files compile in RankKit with public API identical to the FMR copies (same type/member names and signatures)
- [x] No domain language (chunks/symbols/catalogs/metadata) in doc comments
- [x] Ported tests pass unchanged except for imports/suite names

## Tests
- [x] Port `../FoundationModelsMetadataRegistry/Tests/FoundationModelsMetadataRegistryTests/TrigramTests.swift` and `RRFTests.swift` to `Tests/RankKitTests/`
- [x] Port the trigram/tokenizer/RRF cases from `../CodeContextKit/Tests/CodeContextKitTests/RankerTests.swift` (keep overlapping cases — they encode each repo's edge-case history, plan.md §5)
- [x] Run `swift test` — exits 0

## Workflow
- Use `/tdd` — port the tests first (failing), then the source files to make them pass.