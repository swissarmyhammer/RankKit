import RankKit
import Testing

/// Tests for `SelectionConfig`'s defaults, budget clamping, and the
/// `.selectionDefault` preamble's neutral wording (plan.md §6 phase 3) —
/// plus a scripted `AgentSession` fake proving the seam compiles end to end
/// and its default `fork()` returns `self` unchanged.
struct SelectionConfigTests {
    // MARK: - Defaults

    @Test
    func defaultCapacityAndCandidateLimitsMatchTheNamedConstants() {
        let config = SelectionConfig(model: { _ in ScriptedAgentSession() })

        #expect(config.capacityCharacterLimit == SelectionConfig.defaultCapacityCharacterLimit)
        #expect(config.candidateLimit == SelectionConfig.defaultCandidateLimit)
    }

    @Test
    func defaultPreambleIsSelectionDefault() {
        let config = SelectionConfig(model: { _ in ScriptedAgentSession() })

        #expect(config.preamble == .selectionDefault)
    }

    // MARK: - Clamping (existing behavior, ported verbatim)

    @Test
    func negativeCapacityCharacterLimitClampsToZero() {
        let config = SelectionConfig(model: { _ in ScriptedAgentSession() }, capacityCharacterLimit: -1)

        #expect(config.capacityCharacterLimit == 0)
    }

    @Test
    func negativeCandidateLimitClampsToZero() {
        let config = SelectionConfig(model: { _ in ScriptedAgentSession() }, candidateLimit: -5)

        #expect(config.candidateLimit == 0)
    }

    @Test
    func positiveLimitsPassThroughUnclamped() {
        let config = SelectionConfig(
            model: { _ in ScriptedAgentSession() },
            capacityCharacterLimit: 1_234,
            candidateLimit: 7
        )

        #expect(config.capacityCharacterLimit == 1_234)
        #expect(config.candidateLimit == 7)
    }

    // MARK: - `.selectionDefault` neutral wording

    @Test
    func selectionDefaultUsesNeutralItemAndIdLanguage() {
        let preamble = String.selectionDefault

        #expect(preamble.contains("items"))
        #expect(preamble.contains("ids"))
    }

    @Test
    func selectionDefaultContainsNoDomainSpecificLanguage() {
        let preamble = String.selectionDefault.lowercased()

        #expect(!preamble.contains("function"))
        #expect(!preamble.contains("librarian"))
        #expect(!preamble.contains("api"))
    }

    // MARK: - `AgentSession` seam compiles + default `fork()`

    @Test
    func scriptedFakeRespondsWithItsCannedResponse() async throws {
        let session = ScriptedAgentSession(response: "hello")

        let response = try await session.respond(to: "prompt")

        #expect(response == "hello")
    }

    @Test
    func defaultForkReturnsSelfUnchanged() async throws {
        let session = ScriptedAgentSession(response: "hello")

        let forked = try await session.fork()

        #expect((forked as? ScriptedAgentSession) === session)
    }

    // MARK: - `respond(to:generating:)` round-trip decode

    @Test
    func respondGeneratingDecodesScriptedJSONIntoASelection() async throws {
        let session = ScriptedAgentSession(response: #"{"ids":["a","b"]}"#)

        let selection = try await session.respond(to: "prompt", generating: Selection.self)

        #expect(selection.ids == ["a", "b"])
    }
}

/// A minimal scripted `AgentSession` fake: always returns the same canned
/// response, and relies on the protocol's default `fork()` (returns `self`)
/// rather than overriding it — proving that default holds for a conformer
/// with no real KV cache to fork from.
private final class ScriptedAgentSession: AgentSession {
    private let response: String

    init(response: String = "") {
        self.response = response
    }

    func respond(to prompt: String) async throws -> String {
        response
    }
}
