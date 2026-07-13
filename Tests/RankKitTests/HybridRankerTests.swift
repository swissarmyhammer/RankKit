import RankKit
import Testing

/// `SignalWeights` + `HybridRanker` fusion-pipeline tests (plan.md §6 phase
/// 2), ported/adapted from FoundationModelsMetadataRegistry's
/// `RetrievalSearchTests.swift` (golden primary-field-weighted ranking,
/// limit handling, empty-query/no-hits, weights configuration, first-seen
/// tie-break) and CodeContextKit's `SearchCodeTests.swift` fusion coverage
/// (keyword-only vs. semantic-only golden hits, fused-ordering primary-field
/// dominance) — adapted from each repo's corpus/storage-specific fixtures to
/// plain `RankedDocument` arrays, since `HybridRanker` is corpus-agnostic
/// (plan.md §6 phase 2).
struct HybridRankerTests {
    // MARK: - Fixtures

    private struct Item {
        let id: String
        let primary: String
        let body: String
    }

    /// A small ops-command catalog mirroring FoundationModelsMetadataRegistry's
    /// `RetrievalSearchTests.catalog`: none of the blocks repeat their own id
    /// verbatim, so an id-only match (e.g. "deploy") can only be found
    /// through `BM25.primaryFieldWeight`, never by coincidence with the body
    /// text.
    private static let catalog: [Item] = [
        Item(id: "deploy", primary: "deploy", body: "ships containers to a kubernetes cluster"),
        Item(id: "rollback", primary: "rollback", body: "reverts the last release"),
        Item(id: "status", primary: "status", body: "reports current release health"),
        Item(id: "restart", primary: "restart", body: "cycles the running service"),
        Item(id: "scale", primary: "scale", body: "adjusts running instance count for a service"),
    ]

    private static func ranked(_ items: [Item]) -> (ids: [String], documents: [RankedDocument]) {
        (items.map(\.id), items.map { RankedDocument(primaryText: $0.primary, bodyText: $0.body) })
    }

    // MARK: - SignalWeights

    @Test
    func signalWeightsDefaultsToOneForEverySignal() {
        let weights = SignalWeights()
        #expect(weights.bm25 == 1.0)
        #expect(weights.trigram == 1.0)
        #expect(weights.cosine == 1.0)
    }

    @Test
    func signalWeightsStoresCustomValues() {
        let weights = SignalWeights(bm25: 2.0, trigram: 0.5, cosine: 0.0)
        #expect(weights.bm25 == 2.0)
        #expect(weights.trigram == 0.5)
        #expect(weights.cosine == 0.0)
    }

    @Test
    func signalWeightsEquatableComparesAllFields() {
        #expect(SignalWeights() == SignalWeights(bm25: 1.0, trigram: 1.0, cosine: 1.0))
        #expect(SignalWeights(bm25: 2.0) != SignalWeights())
    }

    @Test
    func signalWeightsIsSendable() {
        func requireSendable(_: some Sendable) {}
        requireSendable(SignalWeights())
    }

    // MARK: - Golden ranking: primary-field weighting

    @Test
    func deployQueryRanksTheDeployItemFirstViaPrimaryFieldWeightingAlone() {
        let (ids, documents) = Self.ranked(Self.catalog)
        let hits = HybridRanker.topMatches(ids: ids, documents: documents, query: "deploy", limit: 5)
        #expect(hits.first?.id == "deploy")
    }

    @Test
    func matchScoreIsNormalizedAndSignalsCarryRawBm25AndTrigramWithCosineAbsent() {
        let (ids, documents) = Self.ranked(Self.catalog)
        let hits = HybridRanker.topMatches(ids: ids, documents: documents, query: "deploy", limit: 5)

        guard let first = hits.first else {
            Issue.record("expected at least one hit")
            return
        }
        #expect(first.score >= 0.0 && first.score <= 1.0)
        #expect(first.signals.bm25 > 0.0)
        #expect(first.signals.trigram > 0.0)
        #expect(first.signals.cosine == 0.0)
    }

    // MARK: - Limit handling

    @Test
    func searchTruncatesResultsToLimit() {
        // "release" appears in both `rollback`'s and `status`'s bodies.
        let (ids, documents) = Self.ranked(Self.catalog)
        let unlimited = HybridRanker.topMatches(ids: ids, documents: documents, query: "release", limit: 5)
        #expect(unlimited.count == 2)

        let limited = HybridRanker.topMatches(ids: ids, documents: documents, query: "release", limit: 1)
        #expect(limited.count == 1)
        #expect(limited.first?.id == unlimited.first?.id)
    }

    @Test
    func searchWithZeroLimitReturnsNoMatches() {
        let (ids, documents) = Self.ranked(Self.catalog)
        let hits = HybridRanker.topMatches(ids: ids, documents: documents, query: "deploy", limit: 0)
        #expect(hits.isEmpty)
    }

    @Test
    func searchWithNegativeLimitReturnsNoMatchesRatherThanCrashing() {
        let (ids, documents) = Self.ranked(Self.catalog)
        let hits = HybridRanker.topMatches(ids: ids, documents: documents, query: "deploy", limit: -1)
        #expect(hits.isEmpty)
    }

    // MARK: - Empty query / no hits

    @Test
    func emptyQueryReturnsNoMatches() {
        let (ids, documents) = Self.ranked(Self.catalog)
        let hits = HybridRanker.topMatches(ids: ids, documents: documents, query: "", limit: 5)
        #expect(hits.isEmpty)
    }

    @Test
    func queryWithNoLexicalOrFuzzyOverlapReturnsNoMatches() {
        let (ids, documents) = Self.ranked(Self.catalog)
        let hits = HybridRanker.topMatches(ids: ids, documents: documents, query: "qxjklmzvbwq", limit: 5)
        #expect(hits.isEmpty)
    }

    @Test
    func emptyCorpusReturnsNoMatchesForTopMatchesAndFullOrdering() {
        let topMatches = HybridRanker.topMatches(ids: [], documents: [], query: "anything", limit: 5)
        #expect(topMatches.isEmpty)

        let fullOrdering = HybridRanker.fullOrdering(ids: [], documents: [], query: "anything")
        #expect(fullOrdering.isEmpty)
    }

    // MARK: - Weights configuration

    @Test
    func zeroWeightedTrigramSignalIsExcludedFromFusion() {
        // "kubernetess" (typo, extra "s") has no exact BM25 token match
        // anywhere in the catalog, but fuzzily trigram-matches `deploy`'s
        // body text ("... kubernetes cluster"). With default weights it
        // should surface `deploy`; with trigram damped to zero, `deploy`
        // must not appear at all -- the absent-signal rule pushed to the
        // weight-zero case.
        let (ids, documents) = Self.ranked(Self.catalog)

        let withTrigram = HybridRanker.topMatches(ids: ids, documents: documents, query: "kubernetess", limit: 5)
        #expect(withTrigram.contains { $0.id == "deploy" })

        let withoutTrigram = HybridRanker.topMatches(
            ids: ids, documents: documents, query: "kubernetess", weights: SignalWeights(trigram: 0.0), limit: 5
        )
        #expect(withoutTrigram.isEmpty)
    }

    @Test
    func normalizationCeilingIgnoresAZeroWeightSignal() {
        // With trigram damped to zero, `deploy` ranking rank-0 on BM25 alone
        // must normalize to exactly 1.0 -- not divided by a ceiling that
        // still counts trigram's unreachable share.
        let (ids, documents) = Self.ranked(Self.catalog)
        let hits = HybridRanker.topMatches(
            ids: ids, documents: documents, query: "deploy", weights: SignalWeights(trigram: 0.0), limit: 1
        )

        guard let first = hits.first else {
            Issue.record("expected at least one hit")
            return
        }
        #expect(abs(first.score - 1.0) < 1e-9)
        // The raw trigram signal is still reported for explainability even
        // though a zero weight excludes it from fusion -- it's the fusion
        // and normalization ceiling that ignore it, not `Signals` itself.
        #expect(first.signals.trigram > 0.0)
    }

    @Test
    func singleSignalPerfectMatchNormalizesToOne() {
        // Only BM25 carries weight; trigram and cosine are both zeroed out.
        // A rank-0 BM25 match must normalize to exactly 1.0, proving the
        // absent-signal rule keeps the excluded signals' unreachable share
        // out of the ceiling.
        let (ids, documents) = Self.ranked(Self.catalog)
        let hits = HybridRanker.topMatches(
            ids: ids, documents: documents, query: "deploy",
            weights: SignalWeights(bm25: 1.0, trigram: 0.0, cosine: 0.0), limit: 1
        )

        guard let first = hits.first else {
            Issue.record("expected at least one hit")
            return
        }
        #expect(abs(first.score - 1.0) < 1e-9)
    }

    // MARK: - Tie-break: ascending index order

    /// Two documents engineered so BM25 and trigram rank them in *opposite*
    /// order (one is BM25-rank-0/trigram-rank-1, the other the reverse).
    /// Under equal default weights, `RRF.fuse` sums `1/60 + 1/61` for both
    /// -- an exact tie -- so the only thing that can order them is
    /// `HybridRanker`'s tie-break. Repeating "twinword" in `crossoverOne`'s
    /// body boosts its weighted BM25 term frequency (a `Set`-backed trigram
    /// set is unaffected by repetition) past `crossoverTwo`'s primary-field
    /// match, while `crossoverTwo`'s primary field *is* "twinword" verbatim,
    /// giving it the stronger trigram match.
    private static let crossoverOne = Item(
        id: "twin-one",
        primary: "twin-one",
        body: Array(repeating: "twinword", count: 20).joined(separator: " ") + " filler"
    )
    private static let crossoverTwo = Item(id: "twinword", primary: "twinword", body: "distinct filler text only")

    @Test
    func tieBreakFavorsAscendingIndexOrder() {
        let (firstIds, firstDocuments) = Self.ranked([Self.crossoverOne, Self.crossoverTwo])
        let firstHits = HybridRanker.topMatches(ids: firstIds, documents: firstDocuments, query: "twinword", limit: 2)

        #expect(firstHits.map(\.id) == ["twin-one", "twinword"])
        #expect(firstHits.count == 2)
        if firstHits.count == 2 {
            #expect(abs(firstHits[0].score - firstHits[1].score) < 1e-9)
        }

        // Reversing input order with everything else unchanged must flip the
        // winner -- proving the tie-break follows ascending array index
        // rather than, say, id string ordering (which would pick
        // "twin-one" either way) or some fixed/accidental array position.
        let (secondIds, secondDocuments) = Self.ranked([Self.crossoverTwo, Self.crossoverOne])
        let secondHits = HybridRanker.topMatches(ids: secondIds, documents: secondDocuments, query: "twinword", limit: 2)

        #expect(secondHits.map(\.id) == ["twinword", "twin-one"])
        #expect(secondHits.count == 2)
        if secondHits.count == 2 {
            #expect(abs(secondHits[0].score - secondHits[1].score) < 1e-9)
        }
    }

    // MARK: - Fused-ordering primary-field dominance (ported from CodeContextKit)

    @Test
    func primaryFieldMatchOutranksBodyOnlyMatchInFusedOrdering() {
        let query = "retryBackoffStrategy"

        // Strong: the query term appears in the *primary field* (BM25 field
        // weight x5, plus an exact trigram match) as well as the body.
        let strong = RankedDocument(
            primaryText: "Network.retryBackoffStrategy",
            bodyText: "func retryBackoffStrategy() { compute the retry backoff strategy }"
        )
        // Mediocre: the query term appears only once, in the body.
        let mediocre = RankedDocument(
            primaryText: "Helpers.doWork",
            bodyText: "this helper mentions retryBackoffStrategy once in passing"
        )

        let hits = HybridRanker.topMatches(
            ids: ["strong", "mediocre"], documents: [strong, mediocre], query: query, limit: 2
        )

        let strongIndex = hits.firstIndex { $0.id == "strong" }
        let mediocreIndex = hits.firstIndex { $0.id == "mediocre" }
        guard let strongIndex, let mediocreIndex else {
            Issue.record("expected both documents to match")
            return
        }
        #expect(strongIndex < mediocreIndex)
        #expect(hits[strongIndex].score > hits[mediocreIndex].score)
    }

    // MARK: - Cosine signal (ported from CodeContextKit)

    @Test
    func cosineOnlyDocumentIsFoundDespiteNoLexicalOrFuzzyOverlap() {
        let query = "retry backoff strategy"
        // Digit-only tokens share no characters at all with `query`'s
        // letters, so they can't accidentally pick up a stray trigram
        // overlap the way two English words sometimes do.
        let primary = "n000111.n222333"
        let body = "444555 666777 888999"
        #expect(Set(Tokenizer.tokenize(text: query)).isDisjoint(with: Tokenizer.tokenize(text: primary + " " + body)))
        #expect(Trigram.dice(query: query, target: primary + " " + body) == 0.0)

        let document = RankedDocument(primaryText: primary, bodyText: body)
        let hits = HybridRanker.topMatches(
            ids: ["unrelated"], documents: [document], query: query, cosineScores: [1.0], limit: 5
        )

        guard let first = hits.first else {
            Issue.record("expected the cosine-only document to be found")
            return
        }
        #expect(first.id == "unrelated")
        #expect(first.signals.bm25 == 0.0)
        #expect(first.signals.trigram == 0.0)
        #expect(first.signals.cosine == 1.0)
        #expect(abs(first.score - 1.0) < 1e-9)
    }

    @Test
    func nilCosineScoresSkipsTheCosineSignalEntirely() {
        let (ids, documents) = Self.ranked(Self.catalog)
        let hits = HybridRanker.topMatches(ids: ids, documents: documents, query: "deploy", cosineScores: nil, limit: 5)

        #expect(hits.allSatisfy { $0.signals.cosine == 0.0 })
    }

    @Test
    func zeroWeightedCosineStillReportsRawSignalButIsExcludedFromFusion() {
        // Unlike FMR's `MetadataSearcher.computeSignals`, which skips
        // computing cosine entirely when its weight is <= 0 (an optimization
        // that avoids embedding the query, which doesn't apply here since
        // `cosineScores` is already precomputed by the caller), HybridRanker
        // always reports the raw cosine score for explainability -- exactly
        // like trigram's zero-weight behavior above -- and only excludes it
        // from the fused ranking and normalization ceiling.
        let query = "retry backoff strategy"
        let primary = "n000111.n222333"
        let body = "444555 666777 888999"
        let document = RankedDocument(primaryText: primary, bodyText: body)

        let hits = HybridRanker.topMatches(
            ids: ["unrelated"], documents: [document], query: query,
            cosineScores: [1.0], weights: SignalWeights(cosine: 0.0), limit: 5
        )

        // No BM25/trigram overlap and cosine excluded by its zero weight ->
        // no signal ranked this document at all, so it's absent from the
        // matches-only result entirely.
        #expect(hits.isEmpty)

        // The raw cosine score is still visible via the full-catalog shape,
        // which reports `Signals` for every document regardless of ranking.
        let fullOrdering = HybridRanker.fullOrdering(
            ids: ["unrelated"], documents: [document], query: query,
            cosineScores: [1.0], weights: SignalWeights(cosine: 0.0)
        )
        let only = fullOrdering.first
        #expect(only?.signals.cosine == 1.0)
        // Excluded from fusion -> no signal contributed, so score is 0.0.
        #expect(only?.score == 0.0)
    }

    @Test
    func zeroWeightedCosineDoesNotDilutePerfectSingleSignalNormalization() {
        // A BM25/trigram-only rank-0 match must still normalize to exactly
        // 1.0 even when a zero-weighted cosine score is supplied alongside
        // it -- the zero-weighted signal's unreachable share must not enter
        // the normalization ceiling, matching the trigram case above.
        let (ids, documents) = Self.ranked(Self.catalog)
        let cosineScores = [Double](repeating: 0.5, count: documents.count)

        let hits = HybridRanker.topMatches(
            ids: ids, documents: documents, query: "deploy",
            cosineScores: cosineScores, weights: SignalWeights(bm25: 1.0, trigram: 0.0, cosine: 0.0), limit: 1
        )

        guard let first = hits.first else {
            Issue.record("expected at least one hit")
            return
        }
        #expect(abs(first.score - 1.0) < 1e-9)
        // Raw cosine is still reported even though its weight excluded it.
        #expect(first.signals.cosine == 0.5)
    }

    // MARK: - Full-catalog ordering

    @Test
    func fullOrderingAlwaysReturnsExactlyNResultsForAnNDocumentCorpus() {
        let (ids, documents) = Self.ranked(Self.catalog)
        let hits = HybridRanker.fullOrdering(ids: ids, documents: documents, query: "deploy")

        #expect(hits.count == Self.catalog.count)
        #expect(Set(hits.map(\.id)) == Set(ids))
    }

    @Test
    func fullOrderingPlacesRankedDocumentsFirstAndUnrankedTailInOriginalOrder() {
        let (ids, documents) = Self.ranked(Self.catalog)
        let hits = HybridRanker.fullOrdering(ids: ids, documents: documents, query: "deploy")

        #expect(hits.first?.id == "deploy")
        let tail = Array(hits.dropFirst())
        #expect(tail.map(\.id) == ["rollback", "status", "restart", "scale"])
        #expect(tail.allSatisfy { $0.score == 0.0 })
        #expect(tail.allSatisfy { $0.signals == Signals(bm25: 0.0, trigram: 0.0, cosine: 0.0) })
    }

    @Test
    func fullOrderingWithNoQueryOverlapReturnsAllDocumentsInOriginalOrderZeroScored() {
        let (ids, documents) = Self.ranked(Self.catalog)
        let hits = HybridRanker.fullOrdering(ids: ids, documents: documents, query: "qxjklmzvbwq")

        #expect(hits.map(\.id) == ids)
        #expect(hits.allSatisfy { $0.score == 0.0 })
    }
}
