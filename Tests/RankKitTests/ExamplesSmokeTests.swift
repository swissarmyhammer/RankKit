import FullMontyCore
import RankKit
import Testing

/// Smoke tests for the `FullMonty` example (plan.md §3a).
///
/// `FullMontyCore` factors its entry logic into callable functions living in
/// a plain library target, the same shape as
/// FoundationModelsMetadataRegistry's own `ExamplesSmokeTests` drives its
/// `*Core` targets through. These tests import `FullMontyCore` directly and
/// assert on real output — no `swift run` subprocess spawning — covering
/// every GPU-free path: `--no-model` (`runNoModelDemo`) and the selection
/// tier driven by a scripted `AgentSession` fake
/// (`Support/ScriptedAgentSession.swift`, already shared by `SearcherTests`
/// and the selection-tier suites). `FullMontyCore`'s default (on-device
/// system model) and gated (`RANKKIT_INTEGRATION_TESTS`, live Router) paths
/// touch a real model/network/GPU and are exercised only by `swift run
/// FullMonty` locally, never here.
@Suite("FullMonty example smoke tests")
struct ExamplesSmokeTests {
    // MARK: - Fixtures

    /// Locates the `FullMontyResult` matching the given substring in its query.
    ///
    /// Avoids re-typing `demoQueries`' exact wording in every assertion.
    private func result(containing substring: String, in results: [FullMontyResult]) throws -> FullMontyResult {
        try #require(results.first { $0.query.contains(substring) })
    }

    // MARK: - `--no-model`: keyword-only retrieval, GPU-free (acceptance criterion)

    @Test("--no-model exits cleanly and answers every demo query")
    func noModelDemoAnswersEveryDemoQuery() async throws {
        let results = try await runNoModelDemo()

        #expect(results.count == demoQueries.count)
        for result in results {
            #expect(!result.matches.isEmpty)
        }
    }

    @Test("--no-model ranks the commit query's near-verbatim overlap to \"commit\", with real per-signal scores")
    func noModelDemoRanksTheCommitQueryToCommit() async throws {
        let results = try await runNoModelDemo()

        let commitResult = try result(containing: "staged changes", in: results)
        let first = try #require(commitResult.matches.first)
        #expect(first.id == "commit")
        let signals = try #require(first.signals)
        #expect(signals.bm25 > 0.0)
        // No embedder is configured in this path -- cosine never ranks
        // anything (plan.md §3a absent-signal rule).
        #expect(signals.cosine == 0.0)
    }

    @Test("--no-model ranks the stash query's near-verbatim overlap to \"stash\"")
    func noModelDemoRanksTheStashQueryToStash() async throws {
        let results = try await runNoModelDemo()

        let stashResult = try result(containing: "switch tasks", in: results)
        #expect(stashResult.matches.first?.id == "stash")
    }

    @Test("--no-model reports embeddingUnavailable on every query, since no embedder is configured")
    func noModelDemoReportsEmbeddingUnavailableDiagnostic() async throws {
        let recorder = DiagnosticRecorder()

        _ = try await runNoModelDemo(onDiagnostic: { recorder.record($0) })

        #expect(recorder.diagnostics.contains(.embeddingUnavailable))
    }

    @Test("--no-model's formatter renders rank, id, score, and every signal")
    func noModelDemoFormatsMatches() async throws {
        let results = try await runNoModelDemo()

        let commitResult = try result(containing: "staged changes", in: results)
        let formatted = formattedMatches(commitResult.matches)

        #expect(formatted.contains("1. commit"))
        #expect(formatted.contains("bm25="))
        #expect(formatted.contains("trigram="))
        #expect(formatted.contains("cosine="))
    }

    @Test("printCatalog and printResults run over the full ~50-item catalog without crashing")
    func printingHelpersRunWithoutCrashing() async throws {
        printCatalog()
        let results = try await runNoModelDemo()
        printResults(results)

        #expect(toolCatalog.count >= 50)
    }

    // MARK: - Selection path, driven by a scripted fake session (acceptance criterion)

    @Test("A scripted selection session answers every demo query with its own scripted selection")
    func scriptedSelectionSessionAnswersEveryQuery() async throws {
        let session = ScriptedAgentSession(demoQueries.map { _ in #"{"ids":["grep"]}"# })

        let results = try await runFullMontyDemo(embedder: nil, session: { _ in session }, mode: .selection)

        #expect(results.count == demoQueries.count)
        for result in results {
            #expect(result.matches.map(\.id) == ["grep"])
            // Pure selection (no retrieval ranking under budget): the fixed
            // 1.0 sentinel, no per-signal breakdown.
            #expect(result.matches.first?.score == 1.0)
            #expect(result.matches.first?.signals == nil)
        }
    }

    @Test("Swapping the scripted session's answer swaps the selected id, proving the model is never hardcoded")
    func swappingTheScriptedSessionsAnswerSwapsTheSelectedId() async throws {
        let results = try await runFullMontyDemo(
            embedder: nil,
            session: { _ in ScriptedAgentSession(demoQueries.map { _ in #"{"ids":["stash"]}"# }) },
            mode: .selection
        )

        for result in results {
            #expect(result.matches.map(\.id) == ["stash"])
        }
    }
}
