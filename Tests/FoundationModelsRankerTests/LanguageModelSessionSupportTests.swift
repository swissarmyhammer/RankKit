import FoundationModelsRouter
import FoundationModels
import Testing

@testable import FoundationModelsRanker

/// Tests for the retroactive `LanguageModelSession: AgentSession`
/// conformance (plan.md §3a, §6 phase 3): compile-level proofs that any
/// FoundationModels model constructs a valid `AgentSession` factory for both
/// the seam that exists today (`SelectionConfig.model`, `@Sendable (String,
/// Grammar) -> any AgentSession`) and the simpler seam plan.md §3a's
/// still-unbuilt `Searcher` facade documents (`(String) -> any
/// AgentSession`), plus a fork-semantics test -- all exercised without live
/// inference (construction and `fork()` only; no `respond(to:)` call, so no
/// GPU/model needed), per this task's Tests scope.
///
/// SDK note (plan.md §7 risk): the installed macOS 27 SDK's
/// `FoundationModels.swiftinterface` exposes only `SystemLanguageModel
/// .default` -- no `.fast` static member -- so these tests use `.default`.
/// Nothing here assumes `.fast` exists; this conformance is generic over
/// `some LanguageModel`, not tied to a specific static member.
struct LanguageModelSessionSupportTests {
    // MARK: - Compile-level conformance

    @Test
    func languageModelSessionFactoryClosureTypeChecksAsAnAgentSessionFactory() {
        let factory: @Sendable (String) -> any AgentSession = { instructions in
            LanguageModelSession(model: SystemLanguageModel.default, instructions: instructions)
        }

        let session = factory("selection guidance")

        #expect(session is LanguageModelSession)
    }

    @Test
    func languageModelSessionFactoryClosureTypeChecksAsASelectionConfigModelFactory() {
        // `SelectionConfig.model`'s real, current seam takes a `Grammar`
        // alongside the instructions text (SelectionConfig.swift's own
        // 2026-07-13 review-finding header) -- a plain `LanguageModelSession`
        // factory ignores it, relying instead on the session's native guided
        // generation via `respond(to:generating:)` above.
        let config = SelectionConfig(model: { instructions, _ in
            LanguageModelSession(model: SystemLanguageModel.default, instructions: instructions)
        })

        let session = config.model("selection guidance", try! SelectionTier.idEnumGrammar(ids: ["a"]))

        #expect(session is LanguageModelSession)
    }

    // MARK: - `fork()` semantics: returns `self`, unchanged (transcript accumulates)

    @Test
    func forkReturnsTheSameSessionInstanceUnchanged() async throws {
        let session = LanguageModelSession(model: SystemLanguageModel.default, instructions: "instructions")

        let forked = try await session.fork()

        #expect((forked as? LanguageModelSession) === session)
    }
}
