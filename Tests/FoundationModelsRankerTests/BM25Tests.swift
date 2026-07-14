import Foundation
import FoundationModelsRanker
import Testing

/// BM25F-lite scoring tests, ported from FoundationModelsMetadataRegistry's
/// `BM25Tests.swift` (which adapted CodeContextKit's `RankerTests.swift`
/// "BM25" section, itself a port of the Rust `swissarmyhammer-search`
/// crate's `score.rs` test suite; see plan.md §5 "Search"). The two
/// field-weight constants are ported here to FoundationModelsRanker's neutral
/// `BM25.primaryFieldWeight` / `BM25.bodyFieldWeight` (plan.md §4.1). Kept
/// alongside `BM25RankerTests` (ported from CodeContextKit) even where
/// cases overlap — each repo's suite encodes its own edge-case history
/// (plan.md §5).
struct BM25Tests {
    /// Reference Okapi BM25 term contribution, for hand-comparison against
    /// `BM25Corpus.score`.
    private func referenceTerm(
        n: Double, df: Double, tf: Double, documentLength: Double, averageDocumentLength: Double
    ) -> Double {
        let idf = log(1.0 + (n - df + 0.5) / (df + 0.5))
        let lengthNorm = BM25.k1 * (1.0 - BM25.b + BM25.b * documentLength / averageDocumentLength)
        return idf * tf * (BM25.k1 + 1.0) / (tf + lengthNorm)
    }

    @Test
    func singleTermMatchesHandComputed() {
        // 3-doc corpus, query "foo". doc lens 4, 2, 6 -> avgdl = 4.0.
        // "foo" appears in docs 0 and 1 -> df = 2, N = 3.
        let query = ["foo"]
        let corpus = BM25Corpus(
            queryTokens: query,
            documents: [
                (4, Set(["foo"])),
                (2, Set(["foo"])),
                (6, Set()),
            ]
        )
        let got = corpus.score(weightedTermFrequency: ["foo": 1.0], documentLength: 4, queryTokens: query)
        let want = referenceTerm(n: 3.0, df: 2.0, tf: 1.0, documentLength: 4.0, averageDocumentLength: 4.0)
        #expect(abs(got - want) < 1e-4)
    }

    @Test
    func twoTermMatchesHandComputed() {
        // Query "foo bar". df(foo)=2, df(bar)=1, N=3, avgdl=4.0.
        let query = ["foo", "bar"]
        let corpus = BM25Corpus(
            queryTokens: query,
            documents: [
                (4, Set(["foo", "bar"])),
                (2, Set(["foo"])),
                (6, Set()),
            ]
        )
        let got = corpus.score(
            weightedTermFrequency: ["foo": 1.0, "bar": 1.0], documentLength: 4, queryTokens: query
        )
        let want =
            referenceTerm(n: 3.0, df: 2.0, tf: 1.0, documentLength: 4.0, averageDocumentLength: 4.0)
            + referenceTerm(n: 3.0, df: 1.0, tf: 1.0, documentLength: 4.0, averageDocumentLength: 4.0)
        #expect(abs(got - want) < 1e-4)
    }

    @Test
    func rarerTermScoresHigher() {
        // Same tf/doc_len, but "rare" has df 1 vs "common" df 3.
        let query = ["rare", "common"]
        let corpus = BM25Corpus(
            queryTokens: query,
            documents: [
                (4, Set(["rare", "common"])),
                (4, Set(["common"])),
                (4, Set(["common"])),
            ]
        )
        let rare = corpus.score(weightedTermFrequency: ["rare": 1.0], documentLength: 4, queryTokens: ["rare"])
        let common = corpus.score(
            weightedTermFrequency: ["common": 1.0], documentLength: 4, queryTokens: ["common"]
        )
        #expect(rare > common)
    }

    @Test
    func higherWeightedTermFrequencyScoresHigher() {
        // Identical corpus and doc_len; only the weighted tf differs.
        let query = ["foo"]
        let corpus = BM25Corpus(queryTokens: query, documents: [(4, Set(["foo"])), (4, Set(["foo"]))])
        let high = corpus.score(weightedTermFrequency: ["foo": 3.0], documentLength: 4, queryTokens: query)
        let low = corpus.score(weightedTermFrequency: ["foo": 1.0], documentLength: 4, queryTokens: query)
        #expect(high > low)
    }

    @Test
    func primaryFieldMatchOutranksBodyOnlyMatchForSameTerm() {
        // Same corpus, same doc length; one doc's weighted tf comes from a
        // primary-field occurrence (x5), the other's from a body-field-only
        // occurrence (x1) of the same term. This is the acceptance
        // criterion for BM25.swift's two-field weighting.
        let query = ["parse"]
        let corpus = BM25Corpus(queryTokens: query, documents: [(4, Set(["parse"])), (4, Set(["parse"]))])
        let primaryFieldMatch = corpus.score(
            weightedTermFrequency: ["parse": BM25.primaryFieldWeight],
            documentLength: 4,
            queryTokens: query
        )
        let bodyOnlyMatch = corpus.score(
            weightedTermFrequency: ["parse": BM25.bodyFieldWeight],
            documentLength: 4,
            queryTokens: query
        )
        #expect(primaryFieldMatch > bodyOnlyMatch)
    }

    @Test
    func repeatedQueryTermNotDoubleCounted() {
        let query = ["foo", "foo"]
        let corpus = BM25Corpus(queryTokens: query, documents: [(4, Set(["foo"])), (4, Set())])
        let got = corpus.score(weightedTermFrequency: ["foo": 1.0], documentLength: 4, queryTokens: query)
        let want = referenceTerm(n: 2.0, df: 1.0, tf: 1.0, documentLength: 4.0, averageDocumentLength: 4.0)
        #expect(abs(got - want) < 1e-4)
    }

    @Test
    func emptyCorpusIsZero() {
        let query = ["foo"]
        let corpus = BM25Corpus(queryTokens: query, documents: [(Int, Set<String>)]())
        #expect(corpus.score(weightedTermFrequency: ["foo": 1.0], documentLength: 0, queryTokens: query) == 0.0)
    }

    @Test
    func fieldWeightConstantsMatchPlanSpec() {
        // plan.md §4.1's ×5 primary-field / ×1 body-field weighting.
        #expect(BM25.primaryFieldWeight == 5.0)
        #expect(BM25.bodyFieldWeight == 1.0)
        #expect(BM25.primaryFieldWeight == BM25.bodyFieldWeight * 5.0)
    }
}

/// BM25 formula and golden-ordering tests, ported from CodeContextKit's
/// `RankerTests.swift` "BM25" section and its "Golden ordering: fused BM25 +
/// trigram ranking" section (which port the Rust `swissarmyhammer-search`
/// crate's `score.rs` test suite; see plan.md §5 "Search"). Kept alongside
/// `BM25Tests` (ported from FoundationModelsMetadataRegistry) even where
/// cases overlap — each repo's suite encodes its own edge-case history
/// (plan.md §5).
struct BM25RankerTests {
    /// Reference Okapi BM25 term contribution, for hand-comparison against
    /// `BM25Corpus.score`.
    private func referenceTerm(
        n: Double, df: Double, tf: Double, documentLength: Double, averageDocumentLength: Double
    ) -> Double {
        let idf = log(1.0 + (n - df + 0.5) / (df + 0.5))
        let lengthNorm = BM25.k1 * (1.0 - BM25.b + BM25.b * documentLength / averageDocumentLength)
        return idf * tf * (BM25.k1 + 1.0) / (tf + lengthNorm)
    }

    @Test
    func bm25SingleTermMatchesHandComputed() {
        // 3-doc corpus, query "foo". doc lens 4, 2, 6 -> avgdl = 4.0.
        // "foo" appears in docs 0 and 1 -> df = 2, N = 3.
        let query = ["foo"]
        let corpus = BM25Corpus(
            queryTokens: query,
            documents: [
                (4, Set(["foo"])),
                (2, Set(["foo"])),
                (6, Set()),
            ]
        )
        let got = corpus.score(weightedTermFrequency: ["foo": 1.0], documentLength: 4, queryTokens: query)
        let want = referenceTerm(n: 3.0, df: 2.0, tf: 1.0, documentLength: 4.0, averageDocumentLength: 4.0)
        #expect(abs(got - want) < 1e-4)
    }

    @Test
    func bm25TwoTermMatchesHandComputed() {
        // Query "foo bar". df(foo)=2, df(bar)=1, N=3, avgdl=4.0.
        let query = ["foo", "bar"]
        let corpus = BM25Corpus(
            queryTokens: query,
            documents: [
                (4, Set(["foo", "bar"])),
                (2, Set(["foo"])),
                (6, Set()),
            ]
        )
        let got = corpus.score(
            weightedTermFrequency: ["foo": 1.0, "bar": 1.0], documentLength: 4, queryTokens: query
        )
        let want =
            referenceTerm(n: 3.0, df: 2.0, tf: 1.0, documentLength: 4.0, averageDocumentLength: 4.0)
            + referenceTerm(n: 3.0, df: 1.0, tf: 1.0, documentLength: 4.0, averageDocumentLength: 4.0)
        #expect(abs(got - want) < 1e-4)
    }

    @Test
    func bm25RarerTermScoresHigher() {
        // Same tf/doc_len, but "rare" has df 1 vs "common" df 3.
        let query = ["rare", "common"]
        let corpus = BM25Corpus(
            queryTokens: query,
            documents: [
                (4, Set(["rare", "common"])),
                (4, Set(["common"])),
                (4, Set(["common"])),
            ]
        )
        let rare = corpus.score(weightedTermFrequency: ["rare": 1.0], documentLength: 4, queryTokens: ["rare"])
        let common = corpus.score(
            weightedTermFrequency: ["common": 1.0], documentLength: 4, queryTokens: ["common"]
        )
        #expect(rare > common)
    }

    @Test
    func bm25HighWeightFieldScoresHigher() {
        // Identical corpus and doc_len; only the weighted tf differs.
        let query = ["foo"]
        let corpus = BM25Corpus(queryTokens: query, documents: [(4, Set(["foo"])), (4, Set(["foo"]))])
        let high = corpus.score(weightedTermFrequency: ["foo": 3.0], documentLength: 4, queryTokens: query)
        let low = corpus.score(weightedTermFrequency: ["foo": 1.0], documentLength: 4, queryTokens: query)
        #expect(high > low)
    }

    @Test
    func bm25PrimaryFieldMatchOutranksBodyOnlyMatchForSameTerm() {
        // Same corpus, same doc length; one doc's weighted tf comes from a
        // primary-field occurrence (x5), the other's from a body-field-only
        // occurrence (x1) of the same term. This is the acceptance
        // criterion for BM25.swift's two-field weighting.
        let query = ["parse"]
        let corpus = BM25Corpus(queryTokens: query, documents: [(4, Set(["parse"])), (4, Set(["parse"]))])
        let primaryFieldMatch = corpus.score(
            weightedTermFrequency: ["parse": BM25.primaryFieldWeight],
            documentLength: 4,
            queryTokens: query
        )
        let bodyOnlyMatch = corpus.score(
            weightedTermFrequency: ["parse": BM25.bodyFieldWeight],
            documentLength: 4,
            queryTokens: query
        )
        #expect(primaryFieldMatch > bodyOnlyMatch)
    }

    @Test
    func bm25RepeatedQueryTermNotDoubleCounted() {
        let query = ["foo", "foo"]
        let corpus = BM25Corpus(queryTokens: query, documents: [(4, Set(["foo"])), (4, Set())])
        let got = corpus.score(weightedTermFrequency: ["foo": 1.0], documentLength: 4, queryTokens: query)
        let want = referenceTerm(n: 2.0, df: 1.0, tf: 1.0, documentLength: 4.0, averageDocumentLength: 4.0)
        #expect(abs(got - want) < 1e-4)
    }

    @Test
    func bm25EmptyCorpusIsZero() {
        let query = ["foo"]
        let corpus = BM25Corpus(queryTokens: query, documents: [(Int, Set<String>)]())
        #expect(corpus.score(weightedTermFrequency: ["foo": 1.0], documentLength: 0, queryTokens: query) == 0.0)
    }

    // MARK: - Golden ordering: fused BM25 + trigram ranking

    @Test
    func fusedBm25AndTrigramSignalsRankPrimaryFieldMatchFirst() {
        // Two documents share the query term "parse" in their body field,
        // but only "strong" also has it in the primary field (weight x5)
        // and an exact-identifier trigram match; RRF fusion of the BM25 and
        // trigram rankings puts "strong" first, mirroring the Rust crate's
        // `strong_high_weight_lexical_beats_mediocre` golden case.
        let query = ["parse"]
        let corpus = BM25Corpus(queryTokens: query, documents: [(6, Set(["parse"])), (6, Set(["parse"]))])
        let strongBm25 = corpus.score(
            weightedTermFrequency: ["parse": BM25.primaryFieldWeight + BM25.bodyFieldWeight],
            documentLength: 6,
            queryTokens: query
        )
        let mediocreBm25 = corpus.score(
            weightedTermFrequency: ["parse": BM25.bodyFieldWeight],
            documentLength: 6,
            queryTokens: query
        )
        let strongTrigram = Trigram.dice(query: "parse", target: "parse")
        let mediocreTrigram = Trigram.dice(query: "parse", target: "the config value is read lazily later on")

        // Assert the per-signal claim directly, so this golden-ordering
        // test is self-evidently testing what it claims — not just
        // inferring it from the ranking arrays built below.
        #expect(strongBm25 > mediocreBm25)
        #expect(strongTrigram > mediocreTrigram)

        let bm25Ranking = [0, 1]
        let trigramRanking = [0, 1]

        let fused = RRF.fuse(rankedLists: [bm25Ranking, trigramRanking], weights: [1.0, 1.0])
        #expect(fused[0]! > fused[1]!)
    }
}
