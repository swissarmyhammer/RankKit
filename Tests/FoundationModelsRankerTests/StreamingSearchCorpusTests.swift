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

    /// Three transcript-entry-shaped items in group `run-a` -- the same
    /// fixture shape `SearchCorpusTests` uses for the plain `SearchCorpus`,
    /// so the two suites' equivalence assertions line up.
    static let runAItems = [
        SearchItem(id: "a1", text: "the parser failed to tokenize the config file", group: "run-a"),
        SearchItem(id: "a2", text: "retrying the network request after a timeout", group: "run-a"),
        SearchItem(id: "a3", text: "wrote the config file back to disk", group: "run-a"),
    ]

    /// Two more items in a second group, so group eviction through the
    /// actor has something to leave untouched.
    static let runBItems = [
        SearchItem(id: "b1", text: "the parser emitted a warning about indentation", group: "run-b"),
        SearchItem(id: "b2", text: "compiled the module without errors", group: "run-b"),
    ]

    static var allItems: [SearchItem] { runAItems + runBItems }

    // MARK: - Single-threaded equivalence through the actor surface

    @Test
    func theActorInitializedWithItemsRanksIdenticallyToThePlainCorpus() async {
        let plain = SearchCorpus(items: Self.allItems)
        let actorCorpus = await StreamingSearchCorpus(items: Self.allItems)

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
        let actorCorpus = await StreamingSearchCorpus(items: Self.allItems)
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
        let actorCorpus = await StreamingSearchCorpus(items: Self.allItems)
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
    /// concurrent consumers (search) run against one actor at once.
    ///
    /// The invariant under test: every `SelectionMatch` any search ever
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

    // MARK: - Incremental embed on the add path (^rayd7bq)

    @Test
    func eachAddedItemIsEmbeddedExactlyOnceAtAddTimeAndOnlyTheQueryIsEmbeddedPerSearch() async {
        let embedder = CountingEmbedder(dimension: 8)
        let actorCorpus = StreamingSearchCorpus(embedder: embedder)

        await actorCorpus.add(items: [Self.runAItems[0]])
        await actorCorpus.add(items: [Self.runAItems[1]])
        await actorCorpus.add(items: [Self.runAItems[2]])
        #expect(embedder.callCount == 3)

        // Re-adding an id that's already live is a dropped duplicate --
        // nothing new to embed, so no additional embed call happens.
        await actorCorpus.add(items: [Self.runAItems[0]])
        #expect(embedder.callCount == 3)

        _ = await actorCorpus.search("parser config file", limit: 5)
        _ = await actorCorpus.search("timeout", limit: 5)
        #expect(embedder.callCount == 5)
    }

    @Test
    func cosineParticipatesInRankingImmediatelyAfterAddWithAnEmbedderConfigured() async throws {
        let embedder = FakeEmbedder(dimension: 8)
        let actorCorpus = StreamingSearchCorpus(embedder: embedder)
        await actorCorpus.add(items: Self.runAItems)

        let query = "the parser failed to tokenize the config file"
        let matches = await actorCorpus.search(query, limit: 10)

        #expect(!matches.isEmpty)
        let queryVector = try await embedder.embed([query])[0]
        for match in matches {
            let item = try #require(Self.runAItems.first { $0.id == match.id })
            let itemVector = try await embedder.embed([item.text])[0]
            let expectedCosine = CosineScoring.cosineSimilarity(queryVector, itemVector)
            #expect(match.signals?.cosine == expectedCosine)
        }
    }

    @Test
    func removingAnItemDropsItsEmbeddingSoALaterCompleteReembedIsUnaffectedByItsStaleVector() async throws {
        let embedder = FakeEmbedder(dimension: 8)
        let actorCorpus = StreamingSearchCorpus(embedder: embedder)
        await actorCorpus.add(items: Self.runAItems)
        await actorCorpus.remove(ids: ["a1"])

        // "a1" is gone; the surviving two items must still carry real,
        // independently-recomputable cosine scores -- nothing about removing
        // one row's embedding should disturb the others.
        let query = "retrying the network request after a timeout"
        let matches = await actorCorpus.search(query, limit: 10)

        #expect(!matches.contains { $0.id == "a1" })
        let queryVector = try await embedder.embed([query])[0]
        for match in matches {
            let item = try #require(Self.runAItems.first { $0.id == match.id })
            let itemVector = try await embedder.embed([item.text])[0]
            #expect(match.signals?.cosine == CosineScoring.cosineSimilarity(queryVector, itemVector))
        }
    }

    @Test
    func removingThenReAddingAnIDIsEmbeddedAgainRatherThanTreatedAsAnUnchangedDuplicate() async throws {
        // A recycled id is a fresh row (`SearchCorpus.add(items:)`'s own
        // rule), never treated as an unchanged duplicate -- it must be
        // embedded again, and the stored vector must reflect the fresh
        // text. (This is the sequential-happy-path case: each `add`/
        // `remove` call here runs to full completion before the next
        // starts, so it does not by itself exercise the async
        // stale-write race `ifTextMatches:` guards against -- see
        // `aStaleInFlightEmbedForAResurrectedIDNeverOverwritesItsFreshVector`
        // for that.)
        let embedder = CountingEmbedder(dimension: 8)
        let actorCorpus = StreamingSearchCorpus(embedder: embedder)
        let originalText = "original text about parsing config"
        let freshText = "a completely different replacement about network requests"

        await actorCorpus.add(items: [SearchItem(id: "x", text: originalText)])
        #expect(embedder.callCount == 1)

        await actorCorpus.remove(ids: ["x"])
        await actorCorpus.add(items: [SearchItem(id: "x", text: freshText)])
        #expect(embedder.callCount == 2)

        let query = "network requests"
        let matches = await actorCorpus.search(query, limit: 5)
        let match = try #require(matches.first { $0.id == "x" })

        let queryVector = try await embedder.embed([query])[0]
        let freshVector = try await embedder.embed([freshText])[0]
        let staleVector = try await embedder.embed([originalText])[0]
        let expectedCosine = CosineScoring.cosineSimilarity(queryVector, freshVector)
        #expect(match.signals?.cosine == expectedCosine)
        #expect(CosineScoring.cosineSimilarity(queryVector, staleVector) != expectedCosine)
    }

    /// The genuine async-race regression: unlike the sequential test above,
    /// this deliberately keeps a stale embed call *in flight* while the row
    /// underneath it changes, using `GatedEmbedder` to hold both calls open
    /// until the interleaving is set up exactly as intended.
    ///
    /// Sequence: id `"x"`'s first `add(items:)` (text `originalText`)
    /// starts embedding and parks *before* its embed call resolves. While
    /// parked, `"x"` is removed and re-added with `freshText` -- that
    /// second `add`'s own embed call also parks (same gated embedder).
    /// Only then are both released together. The first call's write-back
    /// (`ifTextMatches: originalText`) must lose against `"x"`'s
    /// already-updated live text and be dropped; the second call's
    /// write-back (`ifTextMatches: freshText`) must win. Without the
    /// `ifTextMatches` guard (liveness-only), the first call's write would
    /// instead silently overwrite the row with `originalText`'s vector,
    /// corrupting cosine for `"x"` from then on with no diagnostic.
    @Test
    func aStaleInFlightEmbedForAResurrectedIDNeverOverwritesItsFreshVector() async throws {
        let embedder = GatedEmbedder(dimension: 8)
        let actorCorpus = StreamingSearchCorpus(embedder: embedder)
        let originalText = "original text about parsing config"
        let freshText = "a completely different replacement about network requests"

        // Call #1: "x" / originalText. Starts, embeds, parks.
        let staleAdd = Task {
            await actorCorpus.add(items: [SearchItem(id: "x", text: originalText)])
        }
        await embedder.waitUntilEntered(callNumber: 1)

        // While call #1 is still parked mid-embed, a concurrent producer
        // removes "x" and re-adds it under the same id with different
        // text. Call #2: "x" / freshText. Starts, embeds, also parks.
        await actorCorpus.remove(ids: ["x"])
        let freshAdd = Task {
            await actorCorpus.add(items: [SearchItem(id: "x", text: freshText)])
        }
        await embedder.waitUntilEntered(callNumber: 2)

        // Release both parked embed calls together, then let both `add`
        // calls' write-backs land in whatever order the runtime schedules.
        embedder.release()
        _ = await staleAdd.value
        _ = await freshAdd.value

        let query = "network requests"
        let matches = await actorCorpus.search(query, limit: 5)
        let match = try #require(matches.first { $0.id == "x" })

        // A plain (ungated) embedder produces identical vectors -- same
        // deterministic hash, same dimension -- without re-parking.
        let plainEmbedder = FakeEmbedder(dimension: 8)
        let queryVector = try await plainEmbedder.embed([query])[0]
        let freshVector = try await plainEmbedder.embed([freshText])[0]
        let staleVector = try await plainEmbedder.embed([originalText])[0]
        let expectedCosine = CosineScoring.cosineSimilarity(queryVector, freshVector)

        #expect(match.signals?.cosine == expectedCosine)
        #expect(CosineScoring.cosineSimilarity(queryVector, staleVector) != expectedCosine)
    }

    /// The error path in `add(items:)`: when its embed call returns a
    /// mismatched vector count (or throws), the newly added items are left
    /// with no stored embedding, but `add` itself still succeeds. This
    /// drives the follow-up `search(_:limit:)` call and confirms it
    /// degrades gracefully to keyword-only ranking and reports
    /// `.embeddingUnavailable`, rather than crashing or silently treating
    /// the missing embeddings as zero similarity without a diagnostic.
    ///
    /// Uses `MismatchedCountEmbedder`, which only fails the batched
    /// multi-item call `add(items:)` makes here, leaving every one of
    /// `runAItems`' three rows without a stored embedding. `search(_:limit:)`'s
    /// per-row embedding-completeness check (in `cosineScores`) finds the
    /// first of those missing rows and reports `.embeddingUnavailable`
    /// before it would ever reach a query embed call -- so the resulting
    /// diagnostic and degradation are attributable specifically to
    /// `add(items:)`'s error path having left rows unembedded, not to any
    /// separate query-embed failure.
    @Test
    func addWithAMismatchedVectorCountEmbedderLeavesItemsUnembeddedSoSearchDegradesToKeywordOnlyWithDiagnostic() async {
        let recorder = DiagnosticRecorder()
        let embedder = MismatchedCountEmbedder(dimension: 8)
        let actorCorpus = StreamingSearchCorpus(embedder: embedder, onDiagnostic: { recorder.record($0) })

        await actorCorpus.add(items: Self.runAItems)

        let matches = await actorCorpus.search("the parser failed to tokenize the config file", limit: 10)

        #expect(!matches.isEmpty)
        #expect(matches.allSatisfy { $0.signals?.cosine == 0.0 })
        #expect(recorder.diagnostics.contains(.embeddingUnavailable))
    }

    @Test
    func noEmbedderDegradesToKeywordOnlyRetrievalAndReportsADiagnosticOnEveryStreamingSearch() async {
        let recorder = DiagnosticRecorder()
        let actorCorpus = StreamingSearchCorpus(onDiagnostic: { recorder.record($0) })
        await actorCorpus.add(items: Self.runAItems)

        let matches = await actorCorpus.search("the parser failed to tokenize the config file", limit: 10)

        #expect(!matches.isEmpty)
        #expect(matches.allSatisfy { $0.signals?.cosine == 0.0 })
        #expect(recorder.diagnostics.contains(.embeddingUnavailable))
    }

    /// With an embedder configured, `add(items:)`/`search(_:limit:)` each
    /// suspend at an `await embedder.embed(_:)` call -- unlike every other
    /// method here, which never suspends. A concurrent `remove`/`add` can
    /// therefore run during that gap. This is the regression case for that:
    /// without `search(_:limit:)`'s pre-suspension snapshot (see its
    /// documentation), a concurrent mutation between snapshotting
    /// `corpus.ids` for the cosine array and re-reading `corpus.ids`/
    /// `corpus.documents` for `HybridRanker.topMatches` could desync the two
    /// and trip its alignment precondition -- a crash under real concurrent
    /// traffic. This drives exactly that interleaving and asserts it
    /// neither crashes nor returns a torn match.
    @Test
    func concurrentAddSearchAndRemoveWithAnEmbedderConfiguredNeverCrashesOrReturnsATornMatch() async {
        let embedder = FakeEmbedder(dimension: 8)
        let actorCorpus = StreamingSearchCorpus(embedder: embedder)

        let groupCount = 10
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

        let survivors = (0..<20).map { SearchItem(id: "surv-\($0)", text: "surviving item about parsing config") }
        for item in survivors {
            expectedText[item.id] = item.text
        }

        await withTaskGroup(of: [SelectionMatch].self) { group in
            for items in evictedGroups {
                group.addTask {
                    await actorCorpus.add(items: items)
                    await actorCorpus.remove(group: items[0].group!)
                    return []
                }
            }
            group.addTask {
                await actorCorpus.add(items: survivors)
                return []
            }
            for _ in 0..<100 {
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

        let finalMatches = await actorCorpus.search("surviving item parsing config", limit: 1000)
        #expect(!finalMatches.isEmpty)
        for match in finalMatches {
            #expect(match.id.hasPrefix("surv-"))
        }
    }
}
