---
depends_on:
- 01KWYG2CPJ3HAB6968RE8NW4TP
position_column: todo
position_ordinal: 8d80
title: Conform Apple LanguageModelSession to AgentSession
---
## What
Create `Sources/RankKit/Selection/LanguageModelSessionSupport.swift` (plan.md §3a, §6 phase 3): a retroactive conformance (or thin wrapper if retroactive conformance on the FoundationModels class proves unworkable) making Apple's `LanguageModelSession` usable as an `AgentSession`, so any FoundationModels model — `.fast`, `.default`, adapter-loaded — plugs into the selection seam without Router. The selection model is never hardcoded.
- `respond(to:generating:)` maps to the session's native `@Generable` guided generation.
- `fork()`: decide and document — `LanguageModelSession` has no fork; either return a fresh session re-created from the same instructions (preserving cached-root semantics via a factory capture) or accept the default `fork() { self }` with a doc note that transcript accumulates. Prefer the fresh-session factory approach; document the tradeoff either way.

## Acceptance Criteria
- [ ] A closure `{ instructions in LanguageModelSession(model: .fast, instructions: instructions) }` type-checks as a `SelectionConfig.model` factory
- [ ] Same for `.default` — no RankKit code names a specific model outside defaults/docs
- [ ] `fork()` behavior documented and covered by a test (whichever semantics chosen)

## Tests
- [ ] `Tests/RankKitTests/LanguageModelSessionSupportTests.swift`: compile-level conformance test + fork-semantics test using a seam that doesn't require model inference (constructor/transcript behavior only; any test needing live inference goes behind the family's gated env var)
- [ ] Run `swift test` — exits 0 without a GPU/model

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.