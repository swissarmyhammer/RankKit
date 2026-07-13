// New to RankKit (plan.md §3a, §6 phase 3) -- no source file to port: neither
// CodeContextKit nor FoundationModelsMetadataRegistry ever drove
// `LanguageModelSession` directly through a selection seam (plan.md §1: FMR's
// own selection tier only ever wraps FoundationModelsRouter's
// `RoutedSession`). This is the retroactive conformance §3a promises: any
// FoundationModels model -- `.default`, an adapter-loaded model, or a future
// preset -- plugs into `AgentSession` without a Router dependency, so a
// `LanguageModelSession(model:instructions:)` call type-checks anywhere an
// `AgentSession` is expected. Concretely, that's two call shapes:
//   - `SelectionConfig.model`'s current seam, `@Sendable (String, Grammar) ->
//     any AgentSession` -- a plain `LanguageModelSession` factory ignores the
//     grammar argument (it relies on its own native guided generation
//     instead, via `respond(to:generating:)` below), e.g.
//     `{ instructions, _ in LanguageModelSession(model: .default,
//     instructions: instructions) }`.
//   - the simpler `(String) -> any AgentSession` seam plan.md §3a's
//     `Searcher` facade documents (`session:`) -- e.g.
//     `{ instructions in LanguageModelSession(model: .default, instructions:
//     instructions) }` -- for whenever that facade lands (plan.md §6 phase 3,
//     tracked separately) and adapts a one-arg factory into
//     `SelectionConfig.model`'s two-arg shape.
// Either way, the selection model is never hardcoded (plan.md §2 "neutral
// naming" / §3a).
//
// SDK verification (plan.md §7 risk -- "the .fast/.default model spellings
// ... must be verified against the macOS 27 SDK in phase 3"): the installed
// Xcode-beta macOS 27 SDK's `FoundationModels.swiftinterface` exposes only
// `SystemLanguageModel.default` (plus adapter-based initializers) -- there is
// no `.fast` static member in this snapshot. Nothing here, or in this file's
// tests, assumes `.fast` exists; both use `.default`. This conformance is
// generic over `some LanguageModel`, not tied to a specific static member, so
// a future SDK shipping `.fast` needs no changes here.

import FoundationModels

extension LanguageModelSession: AgentSession {
    /// Sends `prompt` to this session and returns its complete text
    /// response.
    ///
    /// Forwards to the session's own native `respond(to:)`, unwrapping
    /// `Response<String>.content` -- the same text a caller driving
    /// `LanguageModelSession` directly would get back.
    ///
    /// - Parameter prompt: the prompt to respond to.
    /// - Returns: the session's complete text response.
    /// - Throws: whatever the underlying `LanguageModelSession.respond(to:)`
    ///   throws.
    public func respond(to prompt: String) async throws -> String {
        try await respond(to: prompt).content
    }

    /// Sends `prompt` to this session and decodes its response as a
    /// `Generable` type.
    ///
    /// Overrides `AgentSession`'s default (call `respond(to:)` for plain
    /// text, then manually decode `GeneratedContent(json:)`) with the
    /// session's own native guided generation
    /// (`respond(to:generating:)`) instead: a plain `LanguageModelSession`
    /// enforces `T`'s schema at the model level via its own constrained
    /// decoding, so routing through that typed API is both more direct and
    /// more robust than parsing free text as JSON after the fact -- the
    /// plain-`LanguageModelSession` half of plan.md §3a's "grammar
    /// enforcement follows the session" rule (Router-guided sessions get the
    /// external id-enum grammar; plain sessions rely on this typed output
    /// instead).
    ///
    /// - Parameters:
    ///   - prompt: the prompt to respond to.
    ///   - type: the `Generable` type to decode the response into.
    /// - Returns: the decoded value.
    /// - Throws: whatever the underlying
    ///   `LanguageModelSession.respond(to:generating:)` throws.
    public func respond<T: Generable>(to prompt: String, generating type: T.Type) async throws -> T {
        try await respond(to: prompt, generating: type).content
    }

    /// Forks this session for a new call.
    ///
    /// `LanguageModelSession` has no native fork/branch primitive to mirror
    /// `RoutedSession.fork(workingDirectory:)`'s KV-cache-copy semantics
    /// (plan.md §7 risk), and there is no way to reconstruct an equivalent
    /// fresh session generically from within this conformance. The original
    /// `instructions` text *is* recoverable after construction -- it's the
    /// first `.instructions` entry in `session.transcript` -- but the opaque
    /// `some LanguageModel` the session was built with is not: nothing on
    /// `LanguageModelSession` or `Transcript` hands it back. Recreating "the
    /// same session" therefore needs either capturing extra state this class
    /// offers no hook to attach (the model reference itself), or silently
    /// substituting a hardcoded model at fork time -- exactly the hardcoding
    /// plan.md §3a forbids. This conformance therefore keeps `AgentSession`'s
    /// own default explicitly: `fork()` returns `self`, unchanged.
    ///
    /// Tradeoff: every `fork()` on a plain `LanguageModelSession` shares one
    /// running transcript, so repeated `SelectionTier` calls against the
    /// same cached root accumulate turns rather than branching into
    /// isolated children -- unlike `RoutedAgentSession`, whose `fork()`
    /// really does copy a prefilled KV cache per call. Long-running,
    /// high-call-volume selection over a plain `LanguageModelSession` will
    /// eventually grow its context. Callers who need true per-call isolation
    /// should either pass a `session:` factory that constructs a **fresh**
    /// `LanguageModelSession` per top-level call (accepting the re-prefill
    /// cost `RoutedSession.fork(workingDirectory:)` exists to avoid), or use
    /// `RoutedAgentSession` for real fork semantics.
    ///
    /// - Returns: `self`.
    public func fork() async throws -> any AgentSession {
        self
    }
}
