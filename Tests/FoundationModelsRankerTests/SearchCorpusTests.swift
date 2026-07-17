import Foundation
import FoundationModelsRanker
import Testing

/// Tests for `SearchCorpus`: the streaming corpus the ranking pipeline
/// queries -- additive `add(items:)`, `remove(ids:)`, and `remove(group:)`
/// with no rebuild of surviving rows, and BM25 corpus-global statistics that
/// stay correct across arbitrary interleavings of the two.
///
/// Every case drives the corpus through the same public `HybridRanker` entry
/// points `Searcher` uses, so "ranks identically" means identical through the
/// real fusion pipeline (BM25 + trigram fused by RRF with the absent-signal
/// rule), not merely identical stored state.
struct SearchCorpusTests {
    // MARK: - Fixtures

    /// Three transcript-entry-shaped items in group `run-a` -- the streaming
    /// consumer's shape: entries append one at a time and evict by run.
    static let runAItems = [
        SearchItem(id: "a1", text: "the parser failed to tokenize the config file", group: "run-a"),
        SearchItem(id: "a2", text: "retrying the network request after a timeout", group: "run-a"),
        SearchItem(id: "a3", text: "wrote the config file back to disk", group: "run-a"),
    ]

    /// Two more items in a second group, so group eviction has something to
    /// leave untouched.
    static let runBItems = [
        SearchItem(id: "b1", text: "the parser emitted a warning about indentation", group: "run-b"),
        SearchItem(id: "b2", text: "compiled the module without errors", group: "run-b"),
    ]

    static var allItems: [SearchItem] { runAItems + runBItems }

    /// The BM25 corpus `HybridRanker` builds per query, over `corpus`'s live
    /// documents -- the globals (`documentCount`, `averageDocumentLength`,
    /// per-term idf) under test.
    ///
    /// - Parameters:
    ///   - corpus: the corpus whose live documents supply the statistics.
    ///   - queryTokens: the tokenized query to track document frequency for.
    /// - Returns: the per-query corpus statistics.
    private func bm25Corpus(over corpus: SearchCorpus, queryTokens: [String]) -> BM25Corpus {
        BM25Corpus(queryTokens: queryTokens, documents: corpus.documents.map { ($0.documentLength, $0.termSet) })
    }

    /// Ranks `corpus` for `query` through the same `HybridRanker` entry point
    /// `Searcher`'s `.retrieval` mode uses.
    ///
    /// - Parameters:
    ///   - corpus: the corpus to rank.
    ///   - query: the search query.
    /// - Returns: the fused, `[0, 1]`-normalized hits, best-first.
    private func rank(_ corpus: SearchCorpus, query: String) -> [Hit] {
        HybridRanker.topMatches(ids: corpus.ids, documents: corpus.documents, query: query, limit: 10)
    }

    // MARK: - Batch vs incremental equivalence

    @Test
    func aCorpusBuiltBySuccessiveAddsRanksIdenticallyToOneBuiltInABatch() {
        let batch = SearchCorpus(items: Self.allItems)

        var incremental = SearchCorpus()
        for item in Self.allItems {
            incremental.add(items: [item])
        }

        #expect(incremental.ids == batch.ids)

        let query = "parser config file"
        let batchHits = rank(batch, query: query)
        let incrementalHits = rank(incremental, query: query)

        #expect(!batchHits.isEmpty)
        #expect(incrementalHits.map(\.id) == batchHits.map(\.id))
        #expect(incrementalHits.map(\.score) == batchHits.map(\.score))
        #expect(incrementalHits.map(\.signals.bm25) == batchHits.map(\.signals.bm25))
        #expect(incrementalHits.map(\.signals.trigram) == batchHits.map(\.signals.trigram))
    }

    @Test
    func successiveAddsProduceAnIdenticalFullOrdering() {
        let batch = SearchCorpus(items: Self.allItems)

        var incremental = SearchCorpus()
        incremental.add(items: Array(Self.allItems.prefix(2)))
        incremental.add(items: Array(Self.allItems.dropFirst(2)))

        let query = "timeout"
        let batchHits = HybridRanker.fullOrdering(ids: batch.ids, documents: batch.documents, query: query)
        let incrementalHits = HybridRanker.fullOrdering(
            ids: incremental.ids, documents: incremental.documents, query: query
        )

        #expect(batchHits.count == Self.allItems.count)
        #expect(incrementalHits.map(\.id) == batchHits.map(\.id))
        #expect(incrementalHits.map(\.score) == batchHits.map(\.score))
    }

    @Test
    func addingAnAlreadyPresentIDKeepsTheFirstOccurrence() {
        var corpus = SearchCorpus(items: Self.runAItems)
        corpus.add(items: [SearchItem(id: "a1", text: "completely different replacement text")])

        #expect(corpus.ids == ["a1", "a2", "a3"])
        #expect(corpus.block(forID: "a1") == "the parser failed to tokenize the config file")
    }

    // MARK: - BM25 globals under interleaved add/remove

    @Test
    func bm25GlobalsAfterInterleavedAddRemoveMatchAFromScratchBuildOfTheSurvivors() {
        // Interleave adds and removes so the corpus never passes through the
        // survivors' batch shape: add A, drop one of it, add B, drop another.
        var streamed = SearchCorpus()
        streamed.add(items: Self.runAItems)
        streamed.remove(ids: ["a2"])
        streamed.add(items: Self.runBItems)
        streamed.remove(ids: ["b2"])

        let survivors = [Self.runAItems[0], Self.runAItems[2], Self.runBItems[0]]
        let fromScratch = SearchCorpus(items: survivors)

        #expect(streamed.ids == fromScratch.ids)

        let queryTokens = ["parser", "config", "file", "timeout", "module"]
        let streamedStats = bm25Corpus(over: streamed, queryTokens: queryTokens)
        let fromScratchStats = bm25Corpus(over: fromScratch, queryTokens: queryTokens)

        // avgdl and N are whole-corpus values: a removed document must stop
        // contributing its length, and an added one must start.
        #expect(streamedStats.documentCount == 3)
        #expect(streamedStats.documentCount == fromScratchStats.documentCount)
        #expect(streamedStats.averageDocumentLength == fromScratchStats.averageDocumentLength)

        // idf is derived from df(t) over the *surviving* documents.
        for term in queryTokens {
            #expect(streamedStats.documentFrequency(forTerm: term) == fromScratchStats.documentFrequency(forTerm: term))
            #expect(
                streamedStats.inverseDocumentFrequency(forTerm: term)
                    == fromScratchStats.inverseDocumentFrequency(forTerm: term)
            )
        }
    }

    @Test
    func aRemovedDocumentStopsContributingToDocumentFrequency() {
        // "parser" starts in two documents (a1, b1); dropping b1 must take
        // df("parser") from 2 to 1 -- a stale global would keep it at 2.
        var corpus = SearchCorpus(items: Self.allItems)
        #expect(bm25Corpus(over: corpus, queryTokens: ["parser"]).documentFrequency(forTerm: "parser") == 2)

        corpus.remove(ids: ["b1"])

        #expect(bm25Corpus(over: corpus, queryTokens: ["parser"]).documentFrequency(forTerm: "parser") == 1)
    }

    @Test
    func interleavedAddRemoveRanksIdenticallyToAFromScratchBuildOfTheSurvivors() {
        var streamed = SearchCorpus(items: Self.allItems)
        streamed.remove(ids: ["a2"])
        streamed.add(items: [SearchItem(id: "c1", text: "the parser recovered from the config error", group: "run-c")])
        streamed.remove(ids: ["b2"])

        let fromScratch = SearchCorpus(items: [
            Self.runAItems[0],
            Self.runAItems[2],
            Self.runBItems[0],
            SearchItem(id: "c1", text: "the parser recovered from the config error", group: "run-c"),
        ])

        let streamedHits = rank(streamed, query: "parser config")
        let fromScratchHits = rank(fromScratch, query: "parser config")

        #expect(!fromScratchHits.isEmpty)
        #expect(streamedHits.map(\.id) == fromScratchHits.map(\.id))
        #expect(streamedHits.map(\.score) == fromScratchHits.map(\.score))
    }

    // MARK: - Removal

    @Test
    func removingIDsDropsThemFromEveryLookupAndFromRanking() {
        var corpus = SearchCorpus(items: Self.allItems)
        corpus.remove(ids: ["a1", "b2"])

        #expect(corpus.ids == ["a2", "a3", "b1"])
        #expect(corpus.documents.count == 3)
        #expect(corpus.block(forID: "a1") == nil)
        #expect(corpus.summaryBlock(forID: "a1") == nil)
        #expect(corpus.block(forID: "a2") == "retrying the network request after a timeout")

        let hits = rank(corpus, query: "tokenize the config file")
        #expect(!hits.contains { $0.id == "a1" })
    }

    @Test
    func removingAnUnknownIDIsANoOp() {
        var corpus = SearchCorpus(items: Self.runAItems)
        corpus.remove(ids: ["nope"])

        #expect(corpus.ids == ["a1", "a2", "a3"])
        #expect(corpus.documents.count == 3)
    }

    @Test
    func aRemovedIDCanBeAddedBackAfterwards() {
        var corpus = SearchCorpus(items: Self.runAItems)
        corpus.remove(ids: ["a1"])
        corpus.add(items: [SearchItem(id: "a1", text: "a fresh row under a recycled id", group: "run-a")])

        #expect(corpus.ids == ["a2", "a3", "a1"])
        #expect(corpus.block(forID: "a1") == "a fresh row under a recycled id")
    }

    // MARK: - Remove by group

    @Test
    func removingAGroupEvictsEveryMemberAndLeavesOtherGroupsUntouched() {
        var corpus = SearchCorpus(items: Self.allItems)
        corpus.remove(group: "run-a")

        #expect(corpus.ids == ["b1", "b2"])
        for id in Self.runAItems.map(\.id) {
            #expect(corpus.block(forID: id) == nil)
        }

        // The evicted group's content is gone from queries...
        let evictedHits = rank(corpus, query: "tokenize the config file back to disk")
        #expect(evictedHits.allSatisfy { $0.id.hasPrefix("b") })

        // ...while the surviving group ranks exactly as it does on its own.
        let survivorsOnly = SearchCorpus(items: Self.runBItems)
        let query = "parser warning indentation"
        #expect(rank(corpus, query: query).map(\.id) == rank(survivorsOnly, query: query).map(\.id))
        #expect(rank(corpus, query: query).map(\.score) == rank(survivorsOnly, query: query).map(\.score))
    }

    @Test
    func removingAGroupNeverEvictsUngroupedItems() {
        var corpus = SearchCorpus(items: [
            SearchItem(id: "grouped", text: "belongs to a run"),
            SearchItem(id: "ungrouped", text: "belongs to no run"),
        ])
        corpus.add(items: [SearchItem(id: "member", text: "belongs to a run", group: "run-a")])

        corpus.remove(group: "run-a")

        #expect(corpus.ids == ["grouped", "ungrouped"])
    }

    @Test
    func removingAnUnknownGroupIsANoOp() {
        var corpus = SearchCorpus(items: Self.allItems)
        corpus.remove(group: "run-z")

        #expect(corpus.ids == Self.allItems.map(\.id))
    }

    @Test
    func removingTheLastGroupLeavesAnEmptyCorpusThatStillAnswersQueries() {
        var corpus = SearchCorpus(items: Self.runAItems)
        corpus.remove(group: "run-a")

        #expect(corpus.ids.isEmpty)
        #expect(corpus.isEmpty)
        #expect(rank(corpus, query: "parser").isEmpty)
    }

    // MARK: - Catalog conformance

    @Test
    func theCorpusServesTheSelectionCatalogLookupsForEveryLiveRow() {
        let corpus = SearchCorpus(items: [
            SearchItem(id: "tool", text: "the full text that retrieval indexes", summary: "the short selection summary")
        ])

        #expect(corpus.count == 1)
        #expect(corpus.block(forID: "tool") == "the full text that retrieval indexes")
        #expect(corpus.summaryBlock(forID: "tool") == "the short selection summary")
    }
}
