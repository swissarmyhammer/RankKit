---
depends_on:
- 01KWYFZVZJ47QGJ7ZSY79TFD0K
- 01KWYG02NSB135TJPQ0EA8BXXT
position_column: todo
position_ordinal: '9480'
title: Verify downstream dependents build against migrated CCK and FMR
---
## What
Plan.md §7 risk: the module moves change which module public types live in, which can break dependents of CodeContextKit and FoundationModelsMetadataRegistry. After both migrations land, build each repo's dependents and fix any `@_exported import`/typealias gaps in CCK/FMR (fixes belong in the consumer repos, not the dependents):
- `../swissarmyhammer` (the sah MCP server consuming CodeContextKit — confirm via its Package/Cargo manifest which package consumes CCK)
- `../FoundationModelsMultitool` (consumes FMR/Router family)
- Any other repo in `~/github/swissarmyhammer/` whose `Package.swift` references CodeContextKit or FoundationModelsMetadataRegistry (grep for the package names to enumerate)

## Acceptance Criteria
- [ ] Enumerated list of dependent repos recorded in the task comments (grep evidence)
- [ ] Each dependent builds green against the migrated CCK/FMR (`swift build` / repo-appropriate build command)
- [ ] Any required source-compat shims added to CCK/FMR, not to dependents

## Tests
- [ ] Build command per dependent recorded and exit 0 (e.g. `cd ../FoundationModelsMultitool && swift build`)
- [ ] Re-run `swift test` in CCK and FMR after any shim changes — exits 0

## Workflow
- Use `/tdd` where shims are needed — a failing dependent build is the red; the shim makes it green.