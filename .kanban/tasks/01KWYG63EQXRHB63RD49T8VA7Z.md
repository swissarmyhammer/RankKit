---
depends_on:
- 01KWYG3S45GN3CAR9K0NAVJCS9
- 01KWYG46FWSJ4HGVM1149GG40J
position_column: doing
position_ordinal: '80'
title: Write RankKit README with the one-call example
---
## What
Replace the scaffold's `README.md` stub with the real library README (use the `/make-readme` skill, `library` mode — no logo, leads with an inline runnable usage example). The lead example is plan.md §3a's: a `SearchItem` list, `Searcher(items)` on the `.fast` default, one `search(...)` call; then the `.default` swap and the Router/embedder full-monty variant. Document graceful degradation and the `.retrieval`/`.selection`/`.auto` modes in one short section. Link `Examples/FullMonty`.

## Acceptance Criteria
- [x] README's lead code block compiles when pasted into `Examples/FullMontyCore` context (verified by keeping it in sync with `ExamplesSmokeTests` fixtures)
- [x] No domain language (chunks/catalogs/metadata) — items and queries only
- [x] States macOS 27 floor and the FoundationModelsRouter dependency

## Tests
- [x] Add a `ReadmeExampleTests.swift` case that exercises the exact README snippet shape (fixture items + fake session) so the documented API can't drift silently
- [x] Run `swift test` — exits 0

## Workflow
- Use `/tdd` — write the README-snippet test first, then the README.

## Implementation notes (2026-07-13)

`.fast` doesn't exist in the installed SDK (only `SystemLanguageModel.default`,
per `Searcher.swift`'s header note and the adaptation carried from ^navjcs9 /
^49gg40j), so there's no `.fast`→`.default` swap to demonstrate. The README's
zero-config lead example uses `Searcher(items)` as-is (which already defaults
to `.default` internally via `Searcher.defaultSessionFactory`), and the
"swap the session" example shows the explicit `LanguageModelSession(model:
.default, instructions:)` form that default already is — proving the seam
is a plain argument, never hardcoded, without claiming a nonexistent model
variant.

Wrote `Tests/RankKitTests/ReadmeExampleTests.swift` first (3 cases covering
the lead zero-config example, the explicit session swap, and the
embedder+session full-monty shape), all passing against the already-shipped
`Searcher`/`SearchItem` API before writing `README.md`, then wrote the
README to match.

Two rounds of adversarial double-check review caught and fixed real
inaccuracies before landing:
1. The lead example's comment claimed "`.score` and per-signal `.signals`
   attached", but `Searcher(items)` with the default session and `.auto`
   mode resolves to the selection tier's under-budget pure-pick path for a
   3-item list, which returns the `score: 1.0`/`signals: nil` sentinel, not
   fused retrieval signals. Fixed the comment and tightened the pinning
   test to assert the real sentinel values.
2. The follow-up "Modes" section then claimed `.selection` *always* returns
   the `1.0`/`nil` sentinel, missing that `SelectionTier`'s over-budget
   fallback returns real fused `score`/`signals` from its retrieval
   candidates. Fixed to describe both paths, matching `Searcher.swift`'s
   own doc comment.

Final state: `swift build` exit 0, `swift test` 193/193 passed (fresh run).