---
comments:
- actor: claude-code
  id: 01kxe23n9bs4190439a3603g99
  text: |-
    Implemented via /tdd + /implement.

    Added Sources/RankKit/Selection/: SelectionCatalog.swift (new protocol: `ids`, `summaryBlock(forId:)`, `block(forId:)`), AgentSession.swift (ported from FMR's Session/AgentSession.swift verbatim — protocol, default fork()/respond(generating:), RoutedAgentSession), Selection.swift (ported `@Generable` ids-only struct), SelectionConfig.swift (ported; default preamble renamed `.librarianDefault` → `.selectionDefault` with neutral item/id wording, `max(0, ...)` clamping preserved verbatim for both budgets), RankDiagnostic.swift (new 2-case enum: `.retrievalCut(considered:kept:)`, `.unknownSelectedId(id:)`, no default logger — consumers map it themselves per plan.md §6).

    Tests (RED-first, confirmed compile failure before implementation): Tests/RankKitTests/SelectionConfigTests.swift (defaults, clamping, preamble default + neutral-wording assertions, scripted AgentSession fake proving default fork() returns self) and SelectionCoreTests.swift (Selection's `@Generable` schema has `properties.ids.items`, SelectionCatalog conformance via a fixture incl. unknown-id nil path, RankDiagnostic Equatable).

    Verified: `swift build` exit 0; `swift test` exit 0, 133 tests / 11 suites, 0 failures. `git status --porcelain` in ../FoundationModelsMetadataRegistry and ../CodeContextKit both clean — untouched.

    Adversarial double-check (subagent): PASS. One FYI it flagged for the next task (Generalize SelectionTier over SelectionCatalog, ^4cb4k02): SelectionCatalog deliberately has no `item(forId:)`/generic Item accessor, only rendered text (`summaryBlock`/`block`) — matches plan.md §6's spec for the protocol exactly (RankKit drops the generic Item type param FMR's MetadataIndex<Item> carried), not a gap in this task.

    Leaving in `doing` for /review per the implement skill contract.
  timestamp: 2026-07-13T15:39:08.971948+00:00
depends_on:
- 01KWYFYBDKWS53V76XPWMA76JF
position_column: doing
position_ordinal: '80'
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