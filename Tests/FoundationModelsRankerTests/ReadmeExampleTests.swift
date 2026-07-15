import Foundation
import Testing

@testable import FoundationModelsRanker

/// Exercises the exact shape of `README.md`'s code examples -- the trivial
/// `SearchItem` list, the zero-config `Searcher(items)` call, the explicit
/// session override, and the `embedder:` + `session:` "full monty" variant
/// -- against scripted `AgentSession`/`TextEmbedding` fakes (never a live
/// on-device model or Router), so a change to `Searcher`'s public surface
/// breaks this test before it breaks a reader pasting the README into their
/// own project.
///
/// Reuses `SearcherTests.toolItems`'s grep/glob/watch fixture -- the same
/// three-item list `README.md`'s lead example itself lists -- and the same
/// `ScriptedAgentSession`/`FakeEmbedder` doubles every other suite in this
/// target substitutes for the real model (`Support/ScriptedAgentSession.swift`,
/// `Support/FakeEmbedder.swift`).
@Suite("README example")
struct ReadmeExampleTests {
    /// README's lead example: a `SearchItem` list, `Searcher(items)`, one
    /// `search(...)` call.
    ///
    /// The README's own zero-config call omits `session:`, which defaults
    /// to `Searcher.defaultSessionFactory` (a real on-device model session)
    /// -- unusable here without Apple Intelligence, so this test supplies a
    /// scripted fake in its place, exercising the identical initializer and
    /// `search(_:limit:)` call shape the README documents.
    ///
    /// A session is configured and `mode` is left at its `.auto` default
    /// (as the README's own call does), so this resolves to `.selection`;
    /// this three-item list stays comfortably under
    /// `SelectionConfig.defaultCapacityCharacterLimit`, so it's an
    /// under-budget pick that carries the real fused `score` and per-signal
    /// `signals` retrieval reports for the query (the same behavior
    /// `SearcherTests
    /// .selectionModeUnderBudgetUsesTheConfiguredSessionAndAttachesRealRetrievalScoreAndSignals`
    /// pins), matching plan.md §3a's ".score and per-signal .signals
    /// attached" promise. Pinned here so the README's "Modes" section,
    /// which documents this exact shape, can't drift.
    @Test("The lead example's SearchItem list and Searcher(items).search(...) call find grep first")
    func leadExampleFindsGrepForATodoCommentsQuery() async throws {
        let items = SearcherTests.toolItems

        let searcher = try await Searcher(items, session: { _ in ScriptedAgentSession([#"{"ids":["grep"]}"#]) })

        let hits = try await searcher.search("how do I find TODO comments in my code")

        let first = try #require(hits.first)
        #expect(first.id == "grep")
        // The pick carries the same real fused score and per-signal
        // breakdown `.retrieval` mode reports for it -- never a fixed
        // sentinel.
        let retrievalSearcher = try await Searcher(items, session: nil, mode: .retrieval)
        let retrievalHits = try await retrievalSearcher.search("how do I find TODO comments in my code")
        let expected = try #require(retrievalHits.first { $0.id == "grep" })
        #expect(first.score == expected.score)
        #expect(first.signals == expected.signals)
    }

    /// README's explicit session override -- "any `LanguageModelSession`
    /// works, the model is never hardcoded" -- proves the `session:` seam
    /// accepts a plain `(String) -> any AgentSession` closure and that
    /// swapping it swaps which session answers `search(_:limit:)`.
    @Test("An explicit session: closure swaps which session answers selection")
    func explicitSessionClosureSwapsTheAnsweringSession() async throws {
        let items = [
            SearchItem(id: "grep", text: "Search file contents with regular expressions"),
            SearchItem(id: "glob", text: "Find files by name pattern, sorted by mtime"),
        ]

        let searcher = try await Searcher(items, session: { _ in ScriptedAgentSession([#"{"ids":["glob"]}"#]) })

        let hits = try await searcher.search("find files by name")

        #expect(hits.first?.id == "glob")
    }

    /// README's "full monty" variant -- `embedder:` joins the cosine signal
    /// alongside a custom `session:` -- still just two more arguments,
    /// proven here with `FakeEmbedder` standing in for
    /// `RoutedEmbedderAdapter` (which needs a live Router to construct).
    @Test("Configuring embedder: alongside session: adds the cosine signal without reporting a degradation diagnostic")
    func embedderAndSessionArgumentsBothThreadThrough() async throws {
        let items = [
            SearchItem(id: "grep", text: "Search file contents with regular expressions"),
            SearchItem(id: "glob", text: "Find files by name pattern, sorted by mtime"),
        ]
        let recorder = DiagnosticRecorder()

        let searcher = try await Searcher(
            items,
            embedder: FakeEmbedder(dimension: 8),
            session: { _ in ScriptedAgentSession([#"{"ids":["grep"]}"#]) },
            mode: .retrieval,
            onDiagnostic: { recorder.record($0) }
        )

        let hits = try await searcher.search("search file contents with a regular expression")

        #expect(hits.first?.id == "grep")
        #expect(!recorder.diagnostics.contains(.embeddingUnavailable))
    }
}
