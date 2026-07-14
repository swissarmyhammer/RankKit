import Foundation
import FoundationModelsRouter
import Testing

@testable import FoundationModelsRanker

/// Tests for the selection tier's under-budget path (plan.md §6 phase 3): a
/// cached root session seeded once with the assembled prefix, `fork()` per
/// `search()` call, the summary-vs-full block separation
/// (`summaryBlock(forId:)` seeds the prefix; `block(forId:)` is what a
/// `SelectionMatch` carries back verbatim), ids-only decoding, verbatim
/// lookup by id, unknown-id filtering + diagnostic, and the id-enum
/// grammar's contents.
///
/// Ported from FoundationModelsMetadataRegistry's
/// `Tests/FoundationModelsMetadataRegistryTests/SelectionTests.swift`, driven
/// directly against `SelectionTier` (rather than through a
/// `MetadataSearcher`-equivalent facade, which doesn't exist yet in FoundationModelsRanker —
/// that's the separate `Searcher` facade task) — driven entirely against the
/// internal `AgentSession` seam via scripted fakes
/// (`Support/ScriptedAgentSession.swift`) over a `FixtureSelectionCatalog`
/// (`Support/FixtureSelectionCatalog.swift`) — zero GPU, no Router
/// dependency. The over-budget path is covered in `OverBudgetTests`.
struct SelectionTests {
    // MARK: - Fixtures

    static let catalog = FixtureSelectionCatalog([
        .init(id: "deploy", block: "ships containers to a kubernetes cluster"),
        .init(id: "rollback", block: "reverts the last release"),
    ])

    /// An under-budget config's `retrievalRanking` is never invoked, so an
    /// empty stub proves the point if it ever is.
    private static func neverCalledRetrievalRanking(_ intent: String) async -> [SelectionMatch] {
        Issue.record("retrievalRanking should not run under budget")
        return []
    }

    // MARK: - Cached root + fork-per-call

    @Test
    func eachSearchCallForksTheCachedRootSessionExactlyOnce() async throws {
        let root = RootSessionRespondCalledDirectlySession(forkResponses: [
            #"{"ids":["deploy"]}"#,
            #"{"ids":["rollback"]}"#,
        ])
        let factoryCallCount = CallCounter()
        let config = SelectionConfig(model: { _, _ in
            factoryCallCount.increment()
            return root
        })
        let tier = SelectionTier(
            catalog: Self.catalog,
            config: config,
            onDiagnostic: { _ in },
            retrievalRanking: Self.neverCalledRetrievalRanking
        )

        let first = try await tier.search(intent: "first task", limit: 5)
        let second = try await tier.search(intent: "second task", limit: 5)

        #expect(root.forkCount == 2)
        // The session factory ran exactly once -- the root is created and
        // cached on the first call, never rebuilt on the second.
        #expect(factoryCallCount.count == 1)
        #expect(first.map(\.id) == ["deploy"])
        #expect(second.map(\.id) == ["rollback"])
    }

    // MARK: - Summary vs full block separation

    @Test
    func sessionPrefixUsesSummaryBlockWhileMatchesCarryTheFullBlock() async throws {
        let catalog = FixtureSelectionCatalog([
            .init(id: "deploy", block: "the full, long rendered block text", summary: "short summary")
        ])
        let factory = RecordingSessionFactory(responses: [#"{"ids":["deploy"]}"#])
        let config = SelectionConfig(model: factory.makeSession)
        let tier = SelectionTier(
            catalog: catalog,
            config: config,
            onDiagnostic: { _ in },
            retrievalRanking: Self.neverCalledRetrievalRanking
        )

        let matches = try await tier.search(intent: "task", limit: 5)

        let seededInstructions = try #require(factory.receivedInstructions.first)
        #expect(seededInstructions.contains("short summary"))
        #expect(!seededInstructions.contains("the full, long rendered block text"))

        let match = try #require(matches.first)
        #expect(match.block == "the full, long rendered block text")
        #expect(match.score == 1.0)
        #expect(match.signals == nil)
    }

    // MARK: - Ids-only decode + verbatim lookup identity

    @Test
    func selectionDecodesIdsOnlyAndMatchesCarryVerbatimCatalogBlocks() async throws {
        let factory = RecordingSessionFactory(responses: [#"{"ids":["rollback","deploy"]}"#])
        let config = SelectionConfig(model: factory.makeSession)
        let tier = SelectionTier(
            catalog: Self.catalog,
            config: config,
            onDiagnostic: { _ in },
            retrievalRanking: Self.neverCalledRetrievalRanking
        )

        let matches = try await tier.search(intent: "roll back the last deploy", limit: 5)

        #expect(matches.map(\.id) == ["rollback", "deploy"])
        #expect(matches.map(\.block) == ["reverts the last release", "ships containers to a kubernetes cluster"])
        #expect(matches.allSatisfy { $0.score == 1.0 && $0.signals == nil })
    }

    @Test
    func selectionResultsAreTruncatedToLimit() async throws {
        let factory = RecordingSessionFactory(responses: [#"{"ids":["rollback","deploy"]}"#])
        let config = SelectionConfig(model: factory.makeSession)
        let tier = SelectionTier(
            catalog: Self.catalog,
            config: config,
            onDiagnostic: { _ in },
            retrievalRanking: Self.neverCalledRetrievalRanking
        )

        let matches = try await tier.search(intent: "roll back the last deploy", limit: 1)

        #expect(matches.map(\.id) == ["rollback"])
    }

    // MARK: - Duplicate id handling: first occurrence wins, no diagnostic

    @Test
    func duplicateIdFromAMisbehavingFakeIsDeduplicatedWithoutADiagnostic() async throws {
        let recorder = DiagnosticRecorder()
        let factory = RecordingSessionFactory(responses: [#"{"ids":["deploy","deploy","rollback"]}"#])
        let config = SelectionConfig(model: factory.makeSession)
        let tier = SelectionTier(
            catalog: Self.catalog,
            config: config,
            onDiagnostic: { recorder.record($0) },
            retrievalRanking: Self.neverCalledRetrievalRanking
        )

        let matches = try await tier.search(intent: "task", limit: 5)

        #expect(matches.map(\.id) == ["deploy", "rollback"])
        #expect(recorder.diagnostics.isEmpty)
    }

    @Test
    func duplicateIdDoesNotConsumeALimitSlotAndCrowdOutALaterLegitimateMatch() async throws {
        // A tight `limit` of 2 against 3 model-returned ids (one a repeat):
        // if the duplicate consumed a slot the way an unfiltered append
        // would, this would truncate to just ["deploy"]. Deduplication must
        // let "rollback" through instead.
        let factory = RecordingSessionFactory(responses: [#"{"ids":["deploy","deploy","rollback"]}"#])
        let config = SelectionConfig(model: factory.makeSession)
        let tier = SelectionTier(
            catalog: Self.catalog,
            config: config,
            onDiagnostic: { _ in },
            retrievalRanking: Self.neverCalledRetrievalRanking
        )

        let matches = try await tier.search(intent: "task", limit: 2)

        #expect(matches.map(\.id) == ["deploy", "rollback"])
    }

    // MARK: - Zero-ids model response ("nothing fits")

    @Test
    func emptyIdsModelResponseReturnsEmptyMatchesWithNoDiagnostic() async throws {
        let recorder = DiagnosticRecorder()
        let factory = RecordingSessionFactory(responses: [#"{"ids":[]}"#])
        let config = SelectionConfig(model: factory.makeSession)
        let tier = SelectionTier(
            catalog: Self.catalog,
            config: config,
            onDiagnostic: { recorder.record($0) },
            retrievalRanking: Self.neverCalledRetrievalRanking
        )

        let matches = try await tier.search(intent: "nothing matches this", limit: 5)

        #expect(matches.isEmpty)
        #expect(recorder.diagnostics.isEmpty)
    }

    // MARK: - Empty catalog

    @Test
    func emptyCatalogSearchReturnsNoMatchesWithoutCrashing() async throws {
        let factory = RecordingSessionFactory(responses: [#"{"ids":[]}"#])
        let config = SelectionConfig(model: factory.makeSession)
        let tier = SelectionTier(
            catalog: FixtureSelectionCatalog([]),
            config: config,
            onDiagnostic: { _ in },
            retrievalRanking: Self.neverCalledRetrievalRanking
        )

        let matches = try await tier.search(intent: "anything", limit: 5)

        #expect(matches.isEmpty)
    }

    // MARK: - Unknown id filtering + diagnostic

    @Test
    func unknownIdFromAMisbehavingFakeIsFilteredAndReportedAsADiagnostic() async throws {
        let recorder = DiagnosticRecorder()
        let factory = RecordingSessionFactory(responses: [#"{"ids":["deploy","not-a-real-id"]}"#])
        let config = SelectionConfig(model: factory.makeSession)
        let tier = SelectionTier(
            catalog: Self.catalog,
            config: config,
            onDiagnostic: { recorder.record($0) },
            retrievalRanking: Self.neverCalledRetrievalRanking
        )

        let matches = try await tier.search(intent: "task", limit: 5)

        #expect(matches.map(\.id) == ["deploy"])
        #expect(recorder.diagnostics == [.unknownSelectedId(id: "not-a-real-id")])
    }

    // MARK: - `limit <= 0` short-circuits without touching the session

    @Test
    func nonPositiveLimitReturnsEmptyWithoutCreatingASession() async throws {
        let factoryCallCount = CallCounter()
        let config = SelectionConfig(model: { _, _ in
            factoryCallCount.increment()
            return ScriptedAgentSession([#"{"ids":["deploy"]}"#])
        })
        let tier = SelectionTier(
            catalog: Self.catalog,
            config: config,
            onDiagnostic: { _ in },
            retrievalRanking: Self.neverCalledRetrievalRanking
        )

        let matches = try await tier.search(intent: "task", limit: 0)

        #expect(matches.isEmpty)
        #expect(factoryCallCount.count == 0)
    }

    // MARK: - Grammar id-set contents

    @Test
    func idEnumGrammarContainsExactlyTheCatalogsCurrentIds() throws {
        let grammar = try SelectionTier.idEnumGrammar(ids: Self.catalog.ids)

        guard case .jsonSchema(let source) = grammar else {
            Issue.record("expected a .jsonSchema grammar")
            return
        }
        let data = try #require(source.data(using: .utf8))
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let properties = try #require(root["properties"] as? [String: Any])
        let idsSchema = try #require(properties["ids"] as? [String: Any])
        let itemsSchema = try #require(idsSchema["items"] as? [String: Any])
        let enumValues = try #require(itemsSchema["enum"] as? [String])

        #expect(Set(enumValues) == Set(Self.catalog.ids))
    }

    @Test
    func idEnumGrammarMarksIdsAsUniqueItems() throws {
        let grammar = try SelectionTier.idEnumGrammar(ids: Self.catalog.ids)

        guard case .jsonSchema(let source) = grammar else {
            Issue.record("expected a .jsonSchema grammar")
            return
        }
        let data = try #require(source.data(using: .utf8))
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let properties = try #require(root["properties"] as? [String: Any])
        let idsSchema = try #require(properties["ids"] as? [String: Any])

        #expect(idsSchema["uniqueItems"] as? Bool == true)
    }

    @Test
    func idEnumGrammarReflectsAnEmptyCatalogAsAnEmptyEnum() throws {
        let grammar = try SelectionTier.idEnumGrammar(ids: [])

        guard case .jsonSchema(let source) = grammar else {
            Issue.record("expected a .jsonSchema grammar")
            return
        }
        let data = try #require(source.data(using: .utf8))
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let properties = try #require(root["properties"] as? [String: Any])
        let idsSchema = try #require(properties["ids"] as? [String: Any])
        let itemsSchema = try #require(idsSchema["items"] as? [String: Any])
        let enumValues = try #require(itemsSchema["enum"] as? [String])

        #expect(enumValues.isEmpty)
    }

    // MARK: - Grammar actually constrains the created session (review finding, 2026-07-13)

    @Test
    func cachedRootSessionIsConstrainedToTheWholeCatalogsIdEnumGrammar() async throws {
        let factory = RecordingSessionFactory(responses: [#"{"ids":["deploy"]}"#])
        let config = SelectionConfig(model: factory.makeSession)
        let tier = SelectionTier(
            catalog: Self.catalog,
            config: config,
            onDiagnostic: { _ in },
            retrievalRanking: Self.neverCalledRetrievalRanking
        )

        _ = try await tier.search(intent: "task", limit: 5)

        // Compared structurally, not via `Grammar`'s raw-string `Equatable`:
        // `JSONSerialization.data(withJSONObject:)` doesn't guarantee stable
        // key order across separate encodes of an equivalent
        // `idEnumGrammar(ids:)` call, so two semantically-identical grammars
        // can legitimately differ byte-for-byte.
        let receivedGrammar = try #require(factory.receivedGrammars.first)
        #expect(try GrammarTestSupport.enumIds(in: receivedGrammar) == Set(Self.catalog.ids))
    }
}
