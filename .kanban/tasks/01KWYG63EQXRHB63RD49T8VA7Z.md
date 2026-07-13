---
comments:
- actor: claude-code
  id: 01kxeh82dgvyan258z74fwdf38
  text: |-
    Fixed the outstanding review finding: Tests/RankKitTests/ReadmeExampleTests.swift's leadExampleFindsGrepForATodoCommentsQuery now uses `SearcherTests.toolItems` instead of a duplicated inline grep/glob/watch SearchItem array. No access-level changes were needed (both types are internal, same test target). The other two tests' 2-item arrays were left untouched — not identical to toolItems, out of scope.

    Verification: swift build exit 0. swift test 193/193 passed (full suite), swift test --filter ReadmeExampleTests 3/3 passed. Adversarial double-check agent reviewed the change and returned PASS.

    Checklist item flipped to [x]. Leaving task in doing per /implement workflow — ready for /review to pull it back into review.
  timestamp: 2026-07-13T20:03:42.128346+00:00
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

`.fast` doesn't exist in the installed SDK (only `SystemLanguageModel.default`, per `Searcher.swift`'s header note and the adaptation carried from ^navjcs9 / ^49gg40j), so there's no `.fast`→`.default` swap to demonstrate. The README's zero-config lead example uses `Searcher(items)` as-is (which already defaults to `.default` internally via `Searcher.defaultSessionFactory`), and the "swap the session" example shows the explicit `LanguageModelSession(model: .default, instructions:)` form that default already is — proving the seam is a plain argument, never hardcoded, without claiming a nonexistent model variant.

Wrote `Tests/RankKitTests/ReadmeExampleTests.swift` first (3 cases covering the lead zero-config example, the explicit session swap, and the embedder+session full-monty shape), all passing against the already-shipped `Searcher`/`SearchItem` API before writing `README.md`, then wrote the README to match.

Two rounds of adversarial double-check review caught and fixed real inaccuracies before landing:
1. The lead example's comment claimed "`.score` and per-signal `.signals` attached", but `Searcher(items)` with the default session and `.auto` mode resolves to the selection tier's under-budget pure-pick path for a 3-item list, which returns the `score: 1.0`/`signals: nil` sentinel, not fused retrieval signals. Fixed the comment and tightened the pinning test to assert the real sentinel values.
2. The follow-up "Modes" section then claimed `.selection` *always* returns the `1.0`/`nil` sentinel, missing that `SelectionTier`'s over-budget fallback returns real fused `score`/`signals` from its retrieval candidates. Fixed to describe both paths, matching `Searcher.swift`'s own doc comment.

Final state: `swift build` exit 0, `swift test` 193/193 passed (fresh run).

## Review Findings (2026-07-13 14:57)

- [x] `Tests/RankKitTests/ReadmeExampleTests.swift:37` — Recreates SearchItem array (grep, glob, watch) that is identical to SearcherTests.toolItems, rather than reusing the shared test fixture already defined in the same test target. Use SearcherTests.toolItems directly: `let items = SearcherTests.toolItems`.

## Review fix (2026-07-13, round 2)

Replaced the inline `[grep, glob, watch]` `SearchItem` literal in `leadExampleFindsGrepForATodoCommentsQuery` with `SearcherTests.toolItems` (no access-level change needed — both types are internal/default access in the same test target). The other two tests in the file use a different 2-item (grep/glob only) array that is not identical to `toolItems`, so they were left as-is — out of scope for this finding.

`swift build`: exit 0. `swift test`: 193/193 passed, including `swift test --filter ReadmeExampleTests` (3/3). Adversarial double-check agent reviewed the diff and returned PASS.