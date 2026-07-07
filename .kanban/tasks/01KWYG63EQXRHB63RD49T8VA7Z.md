---
depends_on:
- 01KWYG3S45GN3CAR9K0NAVJCS9
- 01KWYG46FWSJ4HGVM1149GG40J
position_column: todo
position_ordinal: '9380'
title: Write RankKit README with the one-call example
---
## What
Replace the scaffold's `README.md` stub with the real library README (use the `/make-readme` skill, `library` mode — no logo, leads with an inline runnable usage example). The lead example is plan.md §3a's: a `SearchItem` list, `Searcher(items)` on the `.fast` default, one `search(...)` call; then the `.default` swap and the Router/embedder full-monty variant. Document graceful degradation and the `.retrieval`/`.selection`/`.auto` modes in one short section. Link `Examples/FullMonty`.

## Acceptance Criteria
- [ ] README's lead code block compiles when pasted into `Examples/FullMontyCore` context (verified by keeping it in sync with `ExamplesSmokeTests` fixtures)
- [ ] No domain language (chunks/catalogs/metadata) — items and queries only
- [ ] States macOS 27 floor and the FoundationModelsRouter dependency

## Tests
- [ ] Add a `ReadmeExampleTests.swift` case that exercises the exact README snippet shape (fixture items + fake session) so the documented API can't drift silently
- [ ] Run `swift test` — exits 0

## Workflow
- Use `/tdd` — write the README-snippet test first, then the README.