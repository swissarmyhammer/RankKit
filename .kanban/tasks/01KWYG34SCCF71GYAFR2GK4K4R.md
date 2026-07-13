---
comments:
- actor: claude-code
  id: 01kxe80r9tdgh2xntkpee845qb
  text: |-
    Implemented `Sources/RankKit/Selection/LanguageModelSessionSupport.swift`: a retroactive `extension LanguageModelSession: AgentSession` (not a wrapper — the class is `final` but extension conformance on a final class works fine).

    - `respond(to:)` forwards to the native `respond(to:)`, unwrapping `Response<String>.content`.
    - `respond<T: Generable>(to:generating:)` is overridden (not left to `AgentSession`'s default JSON-parse fallback) to forward to the session's own native guided `respond(to:generating:)`, since a plain `LanguageModelSession` enforces the schema at the model level — more robust than parsing free text as JSON.
    - `fork()`: kept the protocol's default (`return self`) rather than the "fresh-session factory" alternative. Investigated the actual macOS 27 SDK (`FoundationModels.swiftinterface`): `LanguageModelSession` exposes `transcript` but never the opaque `some LanguageModel` or the original `instructions` text it was constructed with, so there is no way to reconstruct an equivalent fresh session generically from inside the conformance without either (a) capturing extra state the class gives no hook to attach, or (b) hardcoding a substitute model at fork time — which would violate the "model never hardcoded" rule. Documented this tradeoff at length on the `fork()` declaration (transcript accumulates across calls on a plain `LanguageModelSession`; callers needing true per-call isolation should pass a `session:` factory that builds a fresh session per top-level call, or use `RoutedAgentSession`).

    SDK finding worth flagging for later tasks: the installed Xcode-beta macOS 27 SDK's `FoundationModels.swiftinterface` has **no `.fast` static member** on `SystemLanguageModel` — only `.default` (plus adapter-based inits). The acceptance criteria's `.fast` example doesn't compile against this SDK snapshot. Adapted the implementation/tests to use `.default` throughout; the conformance itself is generic over `some LanguageModel` so this doesn't block anything, but the future "Build Searcher one-call facade" task (^navjcs9, currently blocked on this one) and its plan.md §3a doc examples reference `.fast` as "the shipped default" and will need the same adaptation (or to revisit once/if a future SDK ships `.fast`).

    Tests: `Tests/RankKitTests/LanguageModelSessionSupportTests.swift` — compile-level test (a `@Sendable (String) -> any AgentSession` closure constructing `LanguageModelSession(model: SystemLanguageModel.default, instructions:)`) and a fork-semantics test (`fork()` returns the identical instance). Both run without GPU/model — construction only, no `respond(to:)` call. TDD followed: watched both fail to compile first (`unable to infer closure type`, `has no member 'fork'`), then implemented to green.

    `swift build` and `swift test` both green: 162/162 tests passing across 14 suites, no regressions, no new warnings.
  timestamp: 2026-07-13T17:22:25.210645+00:00
- actor: claude-code
  id: 01kxe8gkxe8y6pjnkytfzabjs9
  text: |-
    Adversarial double-check (via really-done) returned REVISE with two findings, both fixed:

    1. The doc comment and single test only proved a `(String) -> any AgentSession` factory, but `SelectionConfig.model`'s real, current seam is two-arg (`@Sendable (String, Grammar) -> any AgentSession`, per that file's own 2026-07-13 review-finding header). Added `languageModelSessionFactoryClosureTypeChecksAsASelectionConfigModelFactory()`, which assigns `{ instructions, _ in LanguageModelSession(model: .default, instructions: instructions) }` directly to a real `SelectionConfig(model:)` and calls `config.model(...)`, proving the conformance actually plugs into today's seam (ignoring the grammar arg, since a plain `LanguageModelSession` relies on its own native guided generation instead — documented in `respond(to:generating:)`). Rewrote the file's header comment to describe both seams accurately: `SelectionConfig.model`'s current two-arg shape, and the simpler one-arg shape plan.md §3a's still-unbuilt `Searcher` facade will expose.

    2. The `fork()` doc comment overstated the SDK limitation, claiming neither the model nor the original instructions were recoverable post-construction. Verified against the SDK: `Transcript.Entry.instructions(Transcript.Instructions)` does carry the original instructions text back via `session.transcript`. Only the opaque `some LanguageModel` is genuinely unrecoverable. Corrected the doc comment to state this precisely — the model, not the instructions, is the actual blocker to a "fresh session" fork.

    Re-verified: `swift build` and `swift test` both green, 163/163 tests across 14 suites (one net-new test from the fix), no regressions, no warnings.
  timestamp: 2026-07-13T17:31:05.006925+00:00
depends_on:
- 01KWYG2CPJ3HAB6968RE8NW4TP
position_column: doing
position_ordinal: '80'
title: Conform Apple LanguageModelSession to AgentSession
---
## What
Create `Sources/RankKit/Selection/LanguageModelSessionSupport.swift` (plan.md §3a, §6 phase 3): a retroactive conformance (or thin wrapper if retroactive conformance on the FoundationModels class proves unworkable) making Apple's `LanguageModelSession` usable as an `AgentSession`, so any FoundationModels model — `.fast`, `.default`, adapter-loaded — plugs into the selection seam without Router. The selection model is never hardcoded.
- `respond(to:generating:)` maps to the session's native `@Generable` guided generation.
- `fork()`: decide and document — `LanguageModelSession` has no fork; either return a fresh session re-created from the same instructions (preserving cached-root semantics via a factory capture) or accept the default `fork() { self }` with a doc note that transcript accumulates. Prefer the fresh-session factory approach; document the tradeoff either way.

## Acceptance Criteria
- [x] A closure `{ instructions in LanguageModelSession(model: .fast, instructions: instructions) }` type-checks as a `SelectionConfig.model` factory — **adapted**: the installed macOS 27 SDK has no `.fast` static member on `SystemLanguageModel` (only `.default`); proved with `.default` instead for both the one-arg `(String) -> any AgentSession` seam and `SelectionConfig.model`'s real two-arg `(String, Grammar) -> any AgentSession` seam (the closure ignores the grammar arg). See kanban comments for the full SDK finding.
- [x] Same for `.default` — no RankKit code names a specific model outside defaults/docs
- [x] `fork()` behavior documented and covered by a test (whichever semantics chosen) — kept `AgentSession`'s default (`return self`); documented why a fresh-session factory isn't implementable from within the conformance (the opaque `some LanguageModel` isn't recoverable post-construction, even though `instructions` is via `transcript`), and the resulting transcript-accumulation tradeoff.

## Tests
- [x] `Tests/RankKitTests/LanguageModelSessionSupportTests.swift`: compile-level conformance test + fork-semantics test using a seam that doesn't require model inference (constructor/transcript behavior only; any test needing live inference goes behind the family's gated env var)
- [x] Run `swift test` — exits 0 without a GPU/model (163/163 tests, 14 suites)

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.

## Implementation notes (2026-07-13)
- New file: `Sources/RankKit/Selection/LanguageModelSessionSupport.swift` — `extension LanguageModelSession: AgentSession`.
- SDK finding: the installed Xcode-beta macOS 27 SDK's `FoundationModels.swiftinterface` has no `.fast` static member on `SystemLanguageModel`, only `.default`. Follow-on tasks referencing `.fast` (e.g. the Searcher facade, ^navjcs9) will need the same adaptation.
- Passed adversarial double-check (via really-done) after one revision round; see task comments for full detail.