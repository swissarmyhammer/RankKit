import Foundation
import FoundationModelsRanker
import Testing

/// Tests for `StreamingSearchCorpus`: the actor-confined wrapper around
/// `SearchCorpus` for the producer/consumer streaming case (^c79yg0f) --
/// a producer appending/evicting items while a consumer queries, from
/// arbitrary, unsynchronized tasks.
///
/// Two concerns, two groups of tests: single-threaded equivalence (the
/// actor surface must rank identically to the plain value type it wraps,
/// per the "deterministic single-thread behavior unchanged" acceptance
/// criterion), and genuine concurrent stress (every match a concurrent
/// search returns must correspond to some fully-added item, never a torn
/// mid-`add` read).
struct StreamingSearchCorpusTests {
    // MARK: - Fixtures

    static let runAItems = [
        SearchItem(id: "a1", text: "the parser failed to tokenize the config file", group: "run-a"),
        SearchItem(id: "a2", text: "retrying the network request after a timeout", group: "run-a"),
        SearchItem(id: "a3", text: "wrote the config file back to disk", group: "run-a"),
    ]

    static let runBItems = [
        SearchItem(id: "b1", text: "the parser emitted a warning about indentation", group: "run-b"),
        SearchItem(id: "b2", text: "compiled the module without errors", group: "run-b"),
    ]

    static var allItems: [SearchItem] { runAItems + runBItems }

    // MARK: - Single-threaded equivalence through the actor surface

    @Test
    func theActorInitializedWithItemsRanksIdenticallyToThePlainCorpus() async {
        let plain = SearchCorpus(items: Self.allItems)
        let actorCorpus = StreamingSearchCorpus(items: Self.allItems)

        let query = "parser config file"
        let expectedHits = HybridRanker.topMatches(ids: plain.ids, documents: plain.documents, query: query, limit: 10)
        let actorMatches = await actorCorpus.search(query, limit: 10)

        #expect(!expectedHits.isEmpty)
        #expect(actorMatches.map(\.id) == expectedHits.map(\.id))
        #expect(actorMatches.map(\.score) == expectedHits.map(\.score))
        for match in actorMatches {
            #expect(match.block == plain.block(forID: match.id))
        }
    }

    @Test
    func successiveActorAddsRankIdenticallyToABatchBuiltPlainCorpus() async {
        let batch = SearchCorpus(items: Self.allItems)

        let actorCorpus = StreamingSearchCorpus()
        for item in Self.allItems {
            await actorCorpus.add(items: [item])
        }

        let query = "timeout"
        let expectedHits = HybridRanker.topMatches(ids: batch.ids, documents: batch.documents, query: query, limit: 10)
        let actorMatches = await actorCorpus.search(query, limit: 10)

        #expect(actorMatches.map(\.id) == expectedHits.map(\.id))
        #expect(actorMatches.map(\.score) == expectedHits.map(\.score))
    }

    @Test
    func removingIDsThroughTheActorDropsThemFromSearchAndLookups() async {
        let actorCorpus = StreamingSearchCorpus(items: Self.allItems)
        await actorCorpus.remove(ids: ["a1", "b2"])

        let count = await actorCorpus.count
        #expect(count == 3)
        let a1Block = await actorCorpus.block(forID: "a1")
        #expect(a1Block == nil)

        let hits = await actorCorpus.search("tokenize the config file", limit: 10)
        #expect(!hits.contains { $0.id == "a1" })
    }

    @Test
    func removingAGroupThroughTheActorEvictsEveryMemberAndLeavesOtherGroupsUntouched() async {
        let actorCorpus = StreamingSearchCorpus(items: Self.allItems)
        await actorCorpus.remove(group: "run-a")

        let isEmpty = await actorCorpus.isEmpty
        #expect(!isEmpty)
        for id in Self.runAItems.map(\.id) {
            let block = await actorCorpus.block(forID: id)
            #expect(block == nil)
        }

        let hits = await actorCorpus.search("tokenize the config file back to disk", limit: 10)
        #expect(hits.allSatisfy { $0.id.hasPrefix("b") })
    }

    @Test
    func anEmptyActorCorpusAnswersSearchWithNoResultsRatherThanCrashing() async {
        let actorCorpus = StreamingSearchCorpus()
        let hits = await actorCorpus.search("anything", limit: 10)
        #expect(hits.isEmpty)
    }

    // MARK: - Concurrent stress

    /// Many concurrent producers (add-then-evict a group) and many
    /// concurrent consumers (search) run against one actor at once. The
    /// invariant under test: every `SelectionMatch` any search ever
    /// returns must correspond to some item that was, at some point,
    /// *fully* added -- never a partial row (an id present without its
    /// text, or a block that doesn't match the text that id was added
    /// with). That would only be observable if the actor let a search
    /// interleave partway through an `add`/`remove`, which actor
    /// confinement rules out.
    @Test
    func concurrentAddSearchAndRemoveNeverReturnsATornOrPartialMatch() async {
        let actorCorpus = StreamingSearchCorpus()

        let groupCount = 20
        let itemsPerGroup = 5
        var expectedText: [String: String] = [:]
        var evictedGroups: [[SearchItem]] = []
        for g in 0..<groupCount {
            let items = (0..<itemsPerGroup).map { i -> SearchItem in
                let id = "g\(g)-i\(i)"
                let text = "streamed item \(id) about parsing config files and retrying network requests"
                expectedText[id] = text
                return SearchItem(id: id, text: text, group: "run-\(g)")
            }
            evictedGroups.append(items)
        }

        let survivors = (0..<50).map { SearchItem(id: "surv-\($0)", text: "surviving item about parsing config") }
        for item in survivors {
            expectedText[item.id] = item.text
        }

        await withTaskGroup(of: [SelectionMatch].self) { group in
            // Producers that add a group's items, then immediately evict
            // that same group -- the streaming producer's add-then-evict
            // shape (SearchCorpus.swift's own motivating scenario).
            for items in evictedGroups {
                group.addTask {
                    await actorCorpus.add(items: items)
                    await actorCorpus.remove(group: items[0].group!)
                    return []
                }
            }

            // A producer whose items are never evicted, so later searches
            // (and the post-group sanity check) have something to find.
            group.addTask {
                await actorCorpus.add(items: survivors)
                return []
            }

            // Consumers racing every producer above.
            for _ in 0..<200 {
                group.addTask {
                    await actorCorpus.search("parsing config network", limit: 50)
                }
            }

            for await matches in group {
                for match in matches {
                    let text = expectedText[match.id]
                    #expect(text != nil, "match id \(match.id) was never a known added item")
                    #expect(match.block == text, "match block for \(match.id) doesn't match its added text -- torn read")
                }
            }
        }

        // Once every producer/consumer above has finished, the
        // never-evicted survivors are still live and queryable, and every
        // evicted group's items are gone for good.
        let finalMatches = await actorCorpus.search("surviving item parsing config", limit: 1000)
        #expect(!finalMatches.isEmpty)
        for match in finalMatches {
            #expect(match.id.hasPrefix("surv-"))
        }
        let finalCount = await actorCorpus.count
        #expect(finalCount == survivors.count)
    }
}
