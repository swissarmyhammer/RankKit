---
depends_on:
- 01KWYFYBDKWS53V76XPWMA76JF
position_column: todo
position_ordinal: 8b80
title: 'Move selection core types: SelectionCatalog, AgentSession, Selection, SelectionConfig'
---
## What
Create `Sources/RankKit/Selection/` (plan.md §6 phase 3), generalized from `../FoundationModelsMetadataRegistry/Sources/FoundationModelsMetadataRegistry/`:
- `SelectionCatalog.swift` (NEW): the protocol replacing `MetadataIndex<Item>` in the tier — `ids: [String]`, `summaryBlock(forId:) -> String?` (seeds the prefix), `block(forId:) -> String?` (verbatim result payload).
- `AgentSession.swift`: port `Session/AgentSession.swift` verbatim (protocol + `RoutedAgentSession` + default `fork()`).
- `Selection.swift`: port `Selection/Selection.swift` verbatim (`@Generable`, ids-only; imports the FoundationModels system framework).
- `SelectionConfig.swift`: port `Selection/SelectionConfig.swift`; rename the default preamble constant `.librarianDefault` → `.selectionDefault` with neutral wording (plan.md §6 phase 3): "return ONLY the items needed — fewest that suffice, in call order when order matters; do not invent ids; return an empty list if nothing fits." Keep `capacityCharacterLimit`/`candidateLimit` defaults and clamping.
- `RankDiagnostic.swift` (NEW): small enum with `.retrievalCut(considered:kept:)` and `.unknownSelectedId(id:)` — RankKit's neutral diagnostics channel (consumers map into their own enums/logging).

## Acceptance Criteria
- [ ] All types compile; `Selection`'s `@Generable` schema shape unchanged (`properties.ids.items` present)
- [ ] `.selectionDefault` contains no domain language ("items"/"ids", not "functions"/"API librarian")
- [ ] `SelectionConfig` clamps negative limits to 0 (existing behavior)

## Tests
- [ ] `Tests/RankKitTests/SelectionConfigTests.swift`: defaults, clamping, preamble default; a scripted fake conforming to `AgentSession` proving the seam compiles and `fork()` default returns self
- [ ] Run `swift test` — exits 0

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.