---
depends_on:
- 01KWYFYBDKWS53V76XPWMA76JF
position_column: todo
position_ordinal: 8b80
title: 'Port selection core types: SelectionCatalog, AgentSession, Selection, SelectionConfig'
---
## What
Create `Sources/RankKit/Selection/` (plan.md §6 phase 3), generalized from `../FoundationModelsMetadataRegistry/Sources/FoundationModelsMetadataRegistry/`. **Port = copy. The source repo is read-only reference material — do not modify, delete, or touch anything in `../FoundationModelsMetadataRegistry` or `../CodeContextKit`.**
- `SelectionCatalog.swift` (NEW): the protocol replacing `MetadataIndex<Item>` in the tier — `ids: [String]`, `summaryBlock(forId:) -> String?` (seeds the prefix), `block(forId:) -> String?` (verbatim result payload).
- `AgentSession.swift`: copy of `Session/AgentSession.swift` (protocol + `RoutedAgentSession` + default `fork()`).
- `Selection.swift`: copy of `Selection/Selection.swift` (`@Generable`, ids-only; imports the FoundationModels system framework).
- `SelectionConfig.swift`: copy of `Selection/SelectionConfig.swift`; rename the default preamble constant `.librarianDefault` → `.selectionDefault` with neutral wording (plan.md §6 phase 3): "return ONLY the items needed — fewest that suffice, in call order when order matters; do not invent ids; return an empty list if nothing fits." Keep `capacityCharacterLimit`/`candidateLimit` defaults and clamping.
- `RankDiagnostic.swift` (NEW): small enum with `.retrievalCut(considered:kept:)` and `.unknownSelectedId(id:)` — RankKit's neutral diagnostics channel.

## Acceptance Criteria
- [ ] All types compile; `Selection`'s `@Generable` schema shape unchanged (`properties.ids.items` present)
- [ ] `.selectionDefault` contains no domain language ("items"/"ids", not "functions"/"API librarian")
- [ ] `SelectionConfig` clamps negative limits to 0 (existing behavior)
- [ ] `git status` in `../FoundationModelsMetadataRegistry` and `../CodeContextKit` is untouched by this task

## Tests
- [ ] `Tests/RankKitTests/SelectionConfigTests.swift`: defaults, clamping, preamble default; a scripted fake conforming to `AgentSession` proving the seam compiles and `fork()` default returns self
- [ ] Run `swift test` — exits 0

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.