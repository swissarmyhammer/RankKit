import Foundation
import FoundationModelsRouter
import Testing

@testable import FoundationModelsRanker

/// Tests for `Searcher` (plan.md §3a): the package's one-call facade --
/// "a list of things to search, then a query" -- composing `HybridRanker`
/// (retrieval) with `SelectionTier` (agent selection) over an in-memory
/// catalog built from the caller's items.
///
/// Driven entirely against scripted `AgentSession` fakes
/// (`Support/ScriptedAgentSession.swift`) and `FakeEmbedder`
/// (`Support/FakeEmbedder.swift`) -- zero GPU, no live system model, no
/// Router dependency, matching every other selection-tier suite in this
/// target.
struct SearcherTests {
    // MARK: - Fixtures

    /// The plan.md §3a "grep/glob/watch" example catalog: three tools, only
    /// one of which lexically/fuzzily overlaps with the queries this suite
    /// uses.
    static let toolItems = [
        SearchItem(id: "grep", text: "Search file contents with regular expressions"),
        SearchItem(id: "glob", text: "Find files by name pattern, sorted by mtime"),
        SearchItem(id: "watch", text: "Watch a directory and stream change events"),
    ]

    /// A large catalog whose assembled selection prefix exceeds
    /// `SelectionConfig.defaultCapacityCharacterLimit` (32,000 characters) --
    /// `Searcher` doesn't expose `capacityCharacterLimit` as a knob (plan.md
    /// §3a's knob list omits it), so the over-budget path is forced here by
    /// bulk `summary` content instead of a tiny forced limit
    /// (`OverBudgetTests`'s approach against `SelectionTier` directly).
    /// `text` (which `HybridRanker` actually scores) stays short and
    /// query-relevant only for "alpha"; `summary` (which only pads the
    /// assembled prefix) is deliberately long filler for every entry so the
    /// budget is blown regardless of which items match.
    static let bulkItems: [SearchItem] = {
        let filler = String(repeating: "padding text that inflates the assembled selection prefix past budget. ", count: 12)
        return (0..<40).map { index in
            let id = index == 0 ? "alpha" : "filler\(index)"
            let text = index == 0 ? "alpha handles the urgent alpha task" : "unrelated filler content, no overlap"
            return SearchItem(id: id, text: text, summary: "SUMMARY_\(id) \(filler)")
        }
    }()

    // MARK: - `.retrieval` mode: no session touched, real signals attached

    @Test
    func retrievalModeRanksTheLexicallyClosestItemFirstWithRealSignals() async throws {
        let searcher = try await Searcher(Self.toolItems, session: nil, mode: .retrieval)

        let matches = try await searcher.search("search file contents with a regular expression", limit: 5)

        let first = try #require(matches.first)
        #expect(first.id == "grep")
        #expect(first.block == "Search file contents with regular expressions")
        #expect(first.score > 0.0)
        let signals = try #require(first.signals)
        #expect(signals.bm25 > 0.0)
    }

    @Test
    func retrievalModeNeverConsultsASessionEvenWhenOneIsConfigured() async throws {
        let session = ScriptedAgentSession([#"{"ids":["glob"]}"#])
        let searcher = try await Searcher(Self.toolItems, session: { _ in session }, mode: .retrieval)

        _ = try await searcher.search("search file contents with a regular expression", limit: 5)

        #expect(session.callCount == 0)
    }

    // MARK: - `.selection` mode, under budget: cached root + fork-per-call

    @Test
    func selectionModeUnderBudgetUsesTheConfiguredSessionAndReturnsPureSelectionMatches() async throws {
        let root = RootSessionRespondCalledDirectlySession(forkResponses: [#"{"ids":["glob"]}"#])
        let factoryCallCount = CallCounter()
        let searcher = try await Searcher(
            Self.toolItems,
            session: { _ in
                factoryCallCount.increment()
                return root
            },
            mode: .selection
        )

        let matches = try await searcher.search("find files by name", limit: 5)

        #expect(matches.map(\.id) == ["glob"])
        #expect(matches.first?.block == "Find files by name pattern, sorted by mtime")
        // Pure selection (no retrieval ranking under budget): score is the
        // fixed 1.0 sentinel, no per-signal breakdown.
        #expect(matches.first?.score == 1.0)
        #expect(matches.first?.signals == nil)
        // Cached-root + fork-per-call: the session factory ran exactly once.
        #expect(factoryCallCount.count == 1)
        #expect(root.forkCount == 1)
    }

    @Test
    func swappingTheSessionFactorySwapsWhichModelAnswersSelection() async throws {
        // Two entirely different scripted sessions standing in for two
        // different models -- proving the model is a plain argument, never
        // hardcoded, by getting each configuration's own scripted answer
        // back verbatim.
        let searcherA = try await Searcher(
            Self.toolItems,
            session: { _ in ScriptedAgentSession([#"{"ids":["grep"]}"#]) },
            mode: .selection
        )
        let searcherB = try await Searcher(
            Self.toolItems,
            session: { _ in ScriptedAgentSession([#"{"ids":["watch"]}"#]) },
            mode: .selection
        )

        let matchesA = try await searcherA.search("anything", limit: 5)
        let matchesB = try await searcherB.search("anything", limit: 5)

        #expect(matchesA.map(\.id) == ["grep"])
        #expect(matchesB.map(\.id) == ["watch"])
    }

    // MARK: - `.selection` mode, over budget: retrieval top-M + one-off session

    @Test
    func selectionModeOverBudgetSeedsAOneOffSessionFromRetrievalTopCandidates() async throws {
        let factoryCallCount = CallCounter()
        let searcher = try await Searcher(
            Self.bulkItems,
            session: { _ in
                factoryCallCount.increment()
                return ScriptedAgentSession([#"{"ids":["alpha"]}"#])
            },
            mode: .selection
        )

        let matches = try await searcher.search("urgent alpha task", limit: 5)

        #expect(matches.map(\.id) == ["alpha"])
        // Retrieval genuinely ran to rank "alpha" first -- the over-budget
        // path's results carry real fused score/signals, unlike the
        // under-budget path's pure-selection 1.0/nil sentinel.
        #expect(matches.first?.score ?? 0.0 > 0.0)
        #expect(matches.first?.signals != nil)
        // One-off session per call: calling search() twice re-invokes the
        // factory, unlike the cached-root under-budget path.
        _ = try await searcher.search("urgent alpha task", limit: 5)
        #expect(factoryCallCount.count == 2)
    }

    @Test
    func selectionModeOverBudgetReportsARetrievalCutDiagnostic() async throws {
        final class DiagnosticBox: @unchecked Sendable {
            private let lock = NSLock()
            private var recorded: [RankDiagnostic] = []
            func record(_ diagnostic: RankDiagnostic) {
                lock.lock()
                defer { lock.unlock() }
                recorded.append(diagnostic)
            }
            var diagnostics: [RankDiagnostic] {
                lock.lock()
                defer { lock.unlock() }
                return recorded
            }
        }
        let box = DiagnosticBox()
        let searcher = try await Searcher(
            Self.bulkItems,
            session: { _ in ScriptedAgentSession([#"{"ids":["alpha"]}"#]) },
            mode: .selection,
            onDiagnostic: { box.record($0) }
        )

        _ = try await searcher.search("urgent alpha task", limit: 5)

        #expect(
            box.diagnostics.contains {
                if case .retrievalCut = $0 { return true }
                return false
            }
        )
    }

    // MARK: - `.auto` mode resolution, both ways

    @Test
    func autoModeResolvesToSelectionWhenASessionIsConfigured() async throws {
        // Retrieval alone would rank "grep" first for this query (lexical
        // overlap with "search"/"regular expression"); scripting the
        // session to hand back "watch" instead proves `.auto` actually
        // drove the selection tier, not a retrieval fallback.
        let searcher = try await Searcher(
            Self.toolItems,
            session: { _ in ScriptedAgentSession([#"{"ids":["watch"]}"#]) },
            mode: .auto
        )

        let matches = try await searcher.search("search file contents with a regular expression", limit: 5)

        #expect(matches.map(\.id) == ["watch"])
        #expect(matches.first?.score == 1.0)
        #expect(matches.first?.signals == nil)
    }

    @Test
    func autoModeDegradesToRetrievalWhenNoSessionIsConfigured() async throws {
        let searcher = try await Searcher(Self.toolItems, session: nil, mode: .auto)

        let matches = try await searcher.search("search file contents with a regular expression", limit: 5)

        let first = try #require(matches.first)
        #expect(first.id == "grep")
        // Retrieval's real fused score/signals, not selection's 1.0/nil
        // sentinel -- proves `.auto` actually fell back rather than
        // silently returning nothing.
        #expect(first.score > 0.0)
        #expect(first.signals != nil)
    }

    // MARK: - Degradation: no embedder, reported never silently

    @Test
    func noEmbedderDegradesToKeywordOnlyRetrievalAndReportsADiagnostic() async throws {
        let recorder = DiagnosticRecorder()
        let searcher = try await Searcher(
            Self.toolItems,
            embedder: nil,
            session: nil,
            mode: .retrieval,
            onDiagnostic: { recorder.record($0) }
        )

        let matches = try await searcher.search("search file contents with a regular expression", limit: 5)

        #expect(matches.first?.id == "grep")
        #expect(matches.first?.signals?.cosine == 0.0)
        #expect(recorder.diagnostics.contains(.embeddingUnavailable))
    }

    @Test
    func configuringAnEmbedderSuppressesTheNoEmbedderDiagnostic() async throws {
        let recorder = DiagnosticRecorder()
        let searcher = try await Searcher(
            Self.toolItems,
            embedder: FakeEmbedder(dimension: 8),
            session: nil,
            mode: .retrieval,
            onDiagnostic: { recorder.record($0) }
        )

        _ = try await searcher.search("search file contents with a regular expression", limit: 5)

        #expect(!recorder.diagnostics.contains(.embeddingUnavailable))
    }

    @Test
    func zeroCosineWeightOptsOutOfTheSignalWithoutReportingADiagnosticEvenWithNoEmbedder() async throws {
        let recorder = DiagnosticRecorder()
        let searcher = try await Searcher(
            Self.toolItems,
            embedder: nil,
            session: nil,
            weights: SignalWeights(cosine: 0.0),
            mode: .retrieval,
            onDiagnostic: { recorder.record($0) }
        )

        let matches = try await searcher.search("search file contents with a regular expression", limit: 5)

        #expect(matches.first?.id == "grep")
        // A deliberately zeroed weight is an opt-out, not a degradation --
        // unlike `noEmbedderDegradesToKeywordOnlyRetrievalAndReportsADiagnostic`
        // (default weights, `.embeddingUnavailable` fires every search),
        // this must report nothing.
        #expect(!recorder.diagnostics.contains(.embeddingUnavailable))
    }

    // MARK: - `limit <= 0` short-circuits to an empty result

    @Test
    func nonPositiveLimitReturnsEmptyInRetrievalMode() async throws {
        let searcher = try await Searcher(Self.toolItems, session: nil, mode: .retrieval)

        let matches = try await searcher.search("search file contents with a regular expression", limit: 0)

        #expect(matches.isEmpty)
    }

    @Test
    func nonPositiveLimitReturnsEmptyInSelectionModeWithoutCreatingASession() async throws {
        let factoryCallCount = CallCounter()
        let searcher = try await Searcher(
            Self.toolItems,
            session: { _ in
                factoryCallCount.increment()
                return ScriptedAgentSession([#"{"ids":["grep"]}"#])
            },
            mode: .selection
        )

        let matches = try await searcher.search("anything", limit: -1)

        #expect(matches.isEmpty)
        #expect(factoryCallCount.count == 0)
    }

    @Test
    func nonPositiveLimitReturnsEmptyInAutoModeWithoutCreatingASession() async throws {
        let factoryCallCount = CallCounter()
        let searcher = try await Searcher(
            Self.toolItems,
            session: { _ in
                factoryCallCount.increment()
                return ScriptedAgentSession([#"{"ids":["grep"]}"#])
            },
            mode: .auto
        )

        let matches = try await searcher.search("anything", limit: 0)

        #expect(matches.isEmpty)
        #expect(factoryCallCount.count == 0)
    }

    // MARK: - Duplicate ids: first occurrence wins, never a crash

    @Test
    func duplicateItemIdKeepsTheFirstOccurrenceAndDropsLaterOnes() async throws {
        let items = [
            SearchItem(id: "grep", text: "the first, real grep description mentioning regular expressions"),
            SearchItem(id: "grep", text: "a later duplicate that should never be indexed"),
        ]
        let searcher = try await Searcher(items, session: nil, mode: .retrieval)

        let matches = try await searcher.search("regular expressions", limit: 5)

        #expect(matches.map(\.id) == ["grep"])
        #expect(matches.first?.block == "the first, real grep description mentioning regular expressions")
    }

    // MARK: - Degradation: `.selection` requested with no session configured

    @Test
    func selectionModeWithNoSessionConfiguredThrowsSelectionTierUnavailable() async throws {
        let searcher = try await Searcher(Self.toolItems, session: nil, mode: .selection)

        await #expect(throws: SelectionTierUnavailable.self) {
            try await searcher.search("anything", limit: 5)
        }
    }

    // MARK: - A `Searchable` conformer, not wrapped in `SearchItem`

    /// A richer type participating directly through `Searchable`, proving
    /// the protocol -- not just `SearchItem` -- is the real seam `Searcher`
    /// drives (plan.md §3a "A `Searchable` protocol lets richer types
    /// participate without wrapping").
    private struct FixtureTool: Searchable {
        let id: String
        let text: String
        // `summary` uses `Searchable`'s default (`text`).
    }

    @Test
    func aSearchableConformerNotWrappedInSearchItemWorksEndToEnd() async throws {
        let tools = [
            FixtureTool(id: "deploy", text: "ships containers to a kubernetes cluster"),
            FixtureTool(id: "rollback", text: "reverts the last release"),
        ]
        let searcher = try await Searcher(tools, session: nil, mode: .retrieval)

        let matches = try await searcher.search("roll back the last release", limit: 5)

        #expect(matches.first?.id == "rollback")
        #expect(matches.first?.block == "reverts the last release")
    }

    // MARK: - `SearchItem.summary` defaults to `text`

    @Test
    func searchItemSummaryDefaultsToTextWhenOmitted() {
        let item = SearchItem(id: "id", text: "the text")
        #expect(item.summary == "the text")
    }

    @Test
    func searchItemSummaryUsesTheExplicitValueWhenProvided() {
        let item = SearchItem(id: "id", text: "the text", summary: "a short summary")
        #expect(item.summary == "a short summary")
    }
}
