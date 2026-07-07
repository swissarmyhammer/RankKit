---
depends_on:
- 01KWYG2WCHH0FZJM34C4CB4K02
- 01KWYG1PW6TDRJ1RVDNQ4G68VV
position_column: todo
position_ordinal: '9080'
title: FMR adopts RankKit selection tier
---
## What
In `../FoundationModelsMetadataRegistry` (plan.md §6 phase 3): delete the now-duplicated selection copy and consume RankKit's:
- **Precondition**: RankKit `main` on GitHub contains the generalized `SelectionTier`/`SelectionCatalog` (push after that task is green).
- Delete `Sources/FoundationModelsMetadataRegistry/Selection/` (SelectionTier.swift, SelectionConfig.swift, Selection.swift) and `Sources/.../Session/AgentSession.swift`.
- Conform `MetadataIndex` to RankKit's `SelectionCatalog` (`ids`, `summaryBlock(forId:)` → `item.renderSummaryBlock()`, `block(forId:)`).
- `MetadataSearcher` wires RankKit's `SelectionTier`; map `RankDiagnostic` cases into `MetadataDiagnostic` (`.retrievalCut`, `.unknownSelectedId`) so FMR's diagnostics API is unchanged.
- Pass FMR's API-librarian preamble explicitly via `preamble:` so the model-visible prompt stays byte-identical (plan.md §6 phase 3 — RankKit's default is now the neutral `.selectionDefault`).
- Keep public API source-compatible (`SelectionConfig` re-export or typealias; `.librarianDefault` stays available in FMR).

## Acceptance Criteria
- [ ] `Sources/.../Selection/` and `Sources/.../Session/` no longer exist in FMR
- [ ] FMR's `SelectionTests`/`OverBudgetTests` (the wiring-level remainder) pass; assembled prefix for the librarian catalog is byte-identical to before (add an assertion comparing against a golden prefix fixture)
- [ ] Diagnostics still surface as `MetadataDiagnostic` cases
- [ ] Downstream dependents of FMR still build (re-run the dependent-build checks from the "Verify downstream dependents" task — this task changes FMR's public surface after that verification first ran)

## Tests
- [ ] Run `swift test` in `../FoundationModelsMetadataRegistry` — exits 0
- [ ] Golden-prefix test proving the model-visible prompt didn't change

## Workflow
- Use `/tdd` — write the golden-prefix test first, then migrate until the suite is green.