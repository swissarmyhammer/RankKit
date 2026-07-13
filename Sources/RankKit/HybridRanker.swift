// Extracted from CodeContextKit's `Sources/CodeContextKit/Ops/SearchCode.swift`
// (`SearchWeights`, `SearchCode.fuseRankings`, `computeBM25Ranking`,
// `computeTrigramRanking`, `computeCosineRanking`, `rankingOfPositiveScores`)
// and FoundationModelsMetadataRegistry's `Sources/
// FoundationModelsMetadataRegistry/MetadataSearcher.swift` (`Weights`,
// `retrievalSearch`, `rankEntireCatalog`, `computeSignals`,
// `fuseAndNormalize`, `sortByNormalizedScore`, `buildMatches`) — the two
// repos' structurally-duplicated fusion pipeline (plan.md §1, §6 phase 2).
// No behavior changes; field names follow RankKit's domain-neutral
// convention (plan.md §4).

/// Per-signal fusion weights `HybridRanker` gives the BM25, trigram, and
/// cosine rankings when fusing them via `RRF.fuse(rankedLists:weights:k:)`.
///
/// A weight of `0.0` excludes that signal from the fused ranking entirely —
/// its ranked list (and weight) are left out of `RRF.fuse`/
/// `RRF.normalize`'s inputs altogether, rather than included at zero, so the
/// normalization ceiling never counts a signal that couldn't have scored
/// anything (the absent-signal rule: `HybridRanker` applies it identically
/// whenever a signal's ranking is empty, whether because its weight is zero
/// or because nothing in the corpus matched it at all).
public struct SignalWeights: Sendable, Equatable {
    /// The weight applied to the BM25 keyword-ranking signal.
    public var bm25: Double

    /// The weight applied to the trigram fuzzy-ranking signal.
    public var trigram: Double

    /// The weight applied to the cosine semantic-ranking signal. Only takes
    /// effect when `HybridRanker` is called with non-`nil` `cosineScores` —
    /// without them, cosine never ranks anything regardless of this weight.
    public var cosine: Double

    /// Creates a set of per-signal fusion weights.
    ///
    /// - Parameters:
    ///   - bm25: the weight applied to the BM25 signal. Defaults to `1.0`.
    ///   - trigram: the weight applied to the trigram signal. Defaults to
    ///     `1.0`.
    ///   - cosine: the weight applied to the cosine signal. Defaults to
    ///     `1.0`.
    public init(bm25: Double = 1.0, trigram: Double = 1.0, cosine: Double = 1.0) {
        self.bm25 = bm25
        self.trigram = trigram
        self.cosine = cosine
    }
}

/// The shared hybrid-search fusion pipeline: BM25 + trigram + (optional)
/// cosine rankings, fused via `RRF.fuse(rankedLists:weights:k:)` and
/// normalized to `[0, 1]` via `RRF.normalize(fused:weights:k:)` (plan.md §1,
/// §6 phase 2). Encodes, once, the pipeline structurally duplicated between
/// CodeContextKit's `SearchCode.run` and FoundationModelsMetadataRegistry's
/// `MetadataSearcher.retrievalSearch`/`rankEntireCatalog`.
///
/// `HybridRanker` never embeds anything itself: callers precompute each
/// document's `RankedDocument` (BM25/trigram statistics) once and reuse it
/// across queries, and — for the cosine signal — embed the query and score
/// it against their own corpus representation (e.g. `CosineScoring`),
/// passing the raw per-document results in as `cosineScores`. Every call
/// re-tokenizes `query` and rescans `documents` for BM25/trigram, same as
/// both source implementations; the per-query fusion itself is cheap
/// relative to tokenizing/trigramming a whole corpus.
public enum HybridRanker {
    /// Fuses `documents` against `query`, returning only documents at least
    /// one signal ranked, best-first, capped at `limit` (CodeContextKit's
    /// `SearchCode.fuseRankings` shape).
    ///
    /// - Parameters:
    ///   - ids: one id per document, positionally aligned with `documents`.
    ///   - documents: the precomputed per-document statistics to score,
    ///     positionally aligned with `ids`.
    ///   - query: the search query, tokenized and trigrammed once per call
    ///     for the BM25 and trigram signals.
    ///   - cosineScores: one raw cosine-similarity score per document,
    ///     positionally aligned with `documents`, or `nil` (the default) to
    ///     skip the cosine signal entirely — graceful degradation to
    ///     keyword-only ranking.
    ///   - weights: the per-signal fusion weights. Defaults to `1.0` for
    ///     every signal.
    ///   - limit: the maximum number of hits to return. `limit <= 0` yields
    ///     an empty result rather than throwing or crashing.
    /// - Precondition: `ids.count == documents.count`, and
    ///   `cosineScores?.count == documents.count` when `cosineScores` is
    ///   non-`nil`.
    /// - Returns: the fused, `[0, 1]`-normalized hits, ordered descending by
    ///   score with an ascending-index tie-break, capped at `limit`. Only
    ///   documents at least one signal ranked are included — a document
    ///   absent from every signal contributes nothing, per the absent-signal
    ///   rule.
    public static func topMatches(
        ids: [String],
        documents: [RankedDocument],
        query: String,
        cosineScores: [Double]? = nil,
        weights: SignalWeights = SignalWeights(),
        limit: Int
    ) -> [Hit] {
        validateInputs(ids: ids, documents: documents, cosineScores: cosineScores)
        guard limit > 0, !documents.isEmpty else { return [] }

        let signals = computeSignals(documents: documents, query: query, cosineScores: cosineScores)
        let normalized = fuseAndNormalize(signals: signals, weights: weights)
        let orderedIndices = sortByNormalizedScore(Array(normalized.keys), using: normalized)

        return buildHits(documentIndices: Array(orderedIndices.prefix(limit)), ids: ids, normalized: normalized, signals: signals)
    }

    /// Fuses `documents` against `query`, returning exactly `documents.count`
    /// hits: documents any signal ranked come first, ordered exactly like
    /// `topMatches(ids:documents:query:cosineScores:weights:limit:)`; every
    /// other document follows in input order, scored `0.0` with all-absent
    /// `Signals` (FoundationModelsMetadataRegistry's
    /// `MetadataSearcher.rankEntireCatalog` shape) — the full, always-
    /// `documents.count`-long ordering an over-budget selection path needs,
    /// never fewer just because a query's signal overlap with the corpus
    /// happens to be sparse.
    ///
    /// - Parameters:
    ///   - ids: one id per document, positionally aligned with `documents`.
    ///   - documents: the precomputed per-document statistics to score,
    ///     positionally aligned with `ids`.
    ///   - query: the search query, tokenized and trigrammed once per call
    ///     for the BM25 and trigram signals.
    ///   - cosineScores: one raw cosine-similarity score per document,
    ///     positionally aligned with `documents`, or `nil` (the default) to
    ///     skip the cosine signal entirely.
    ///   - weights: the per-signal fusion weights. Defaults to `1.0` for
    ///     every signal.
    /// - Precondition: `ids.count == documents.count`, and
    ///   `cosineScores?.count == documents.count` when `cosineScores` is
    ///   non-`nil`.
    /// - Returns: exactly `documents.count` hits, best-first.
    public static func fullOrdering(
        ids: [String],
        documents: [RankedDocument],
        query: String,
        cosineScores: [Double]? = nil,
        weights: SignalWeights = SignalWeights()
    ) -> [Hit] {
        validateInputs(ids: ids, documents: documents, cosineScores: cosineScores)
        guard !documents.isEmpty else { return [] }

        let signals = computeSignals(documents: documents, query: query, cosineScores: cosineScores)
        let normalized = fuseAndNormalize(signals: signals, weights: weights)

        let rankedIndices = sortByNormalizedScore(Array(normalized.keys), using: normalized)
        let unrankedIndices = documents.indices.filter { normalized[$0] == nil }

        return buildHits(documentIndices: rankedIndices + unrankedIndices, ids: ids, normalized: normalized, signals: signals)
    }

    // MARK: - Input validation

    /// Validates the shared precondition both `topMatches(ids:documents:
    /// query:cosineScores:weights:limit:)` and `fullOrdering(ids:documents:
    /// query:cosineScores:weights:)` require of their positionally-aligned
    /// array arguments.
    ///
    /// - Parameters:
    ///   - ids: one id per document, checked against `documents`' length.
    ///   - documents: the documents `ids` and `cosineScores` must align with.
    ///   - cosineScores: one raw cosine-similarity score per document, or
    ///     `nil` to skip the cosine signal; checked against `documents`'
    ///     length when non-`nil`.
    private static func validateInputs(ids: [String], documents: [RankedDocument], cosineScores: [Double]?) {
        precondition(ids.count == documents.count, "HybridRanker: ids and documents must be the same length")
        precondition(
            cosineScores == nil || cosineScores?.count == documents.count,
            "HybridRanker: cosineScores must be the same length as documents"
        )
    }

    // MARK: - Per-signal computation

    /// One (ranking, scores) pair per retrieval signal — the shared input
    /// both `topMatches(ids:documents:query:cosineScores:weights:limit:)`
    /// and `fullOrdering(ids:documents:query:cosineScores:weights:)` fuse and
    /// order differently.
    private struct RetrievalSignals {
        let bm25Ranking: [Int]
        let bm25Scores: [Double]
        let trigramRanking: [Int]
        let trigramScores: [Double]
        let cosineRanking: [Int]
        let cosineScores: [Double]
    }

    /// Computes the BM25, trigram, and cosine signals for `query` over
    /// `documents` — the one piece of per-signal computation both output
    /// shapes share. Every signal's raw scores are computed unconditionally
    /// (even a zero-weighted one), so `Hit.signals` always reports the real
    /// per-signal value for explainability; only `fuseAndNormalize` consults
    /// `weights` to decide what enters the fused ranking.
    private static func computeSignals(
        documents: [RankedDocument],
        query: String,
        cosineScores: [Double]?
    ) -> RetrievalSignals {
        let (bm25Ranking, bm25Scores) = computeBM25Ranking(documents: documents, query: query)
        let (trigramRanking, trigramScores) = computeTrigramRanking(documents: documents, query: query)
        let (cosineRanking, cosineScoresOut) = computeCosineRanking(documents: documents, cosineScores: cosineScores)
        return RetrievalSignals(
            bm25Ranking: bm25Ranking,
            bm25Scores: bm25Scores,
            trigramRanking: trigramRanking,
            trigramScores: trigramScores,
            cosineRanking: cosineRanking,
            cosineScores: cosineScoresOut
        )
    }

    /// Computes the BM25 keyword-ranking signal: `query`'s tokens scored
    /// against every document's precomputed weighted term frequency.
    ///
    /// - Returns: the matching document indices ranked descending by score
    ///   (see `rankingOfPositiveScores(scores:)`), and the full-length,
    ///   positionally aligned raw score for every document.
    private static func computeBM25Ranking(documents: [RankedDocument], query: String) -> (ranking: [Int], scores: [Double]) {
        let queryTokens = Tokenizer.tokenize(text: query)
        guard !documents.isEmpty, !queryTokens.isEmpty else {
            return ([], zeroScores(count: documents.count))
        }

        let corpus = BM25Corpus(queryTokens: queryTokens, documents: documents.map { ($0.documentLength, $0.termSet) })
        let scores = documents.map { document in
            corpus.score(
                weightedTermFrequency: document.weightedTermFrequency,
                documentLength: document.documentLength,
                queryTokens: queryTokens
            )
        }
        return (rankingOfPositiveScores(scores: scores), scores)
    }

    /// Computes the trigram fuzzy-ranking signal: `query`'s canonical
    /// trigram set scored against each document's primary (weighted
    /// `BM25.primaryFieldWeight`) and body (weighted `BM25.bodyFieldWeight`)
    /// trigram sets.
    ///
    /// - Returns: the matching document indices ranked descending by score
    ///   (see `rankingOfPositiveScores(scores:)`), and the full-length,
    ///   positionally aligned raw score for every document.
    private static func computeTrigramRanking(documents: [RankedDocument], query: String) -> (ranking: [Int], scores: [Double]) {
        guard !documents.isEmpty else { return ([], []) }

        let querySet = Trigram.canonicalTrigramSet(text: query)
        let scores = documents.map { document in
            BM25.primaryFieldWeight * Trigram.dice(querySet: querySet, targetSet: document.primaryTrigramSet)
                + BM25.bodyFieldWeight * Trigram.dice(querySet: querySet, targetSet: document.bodyTrigramSet)
        }
        return (rankingOfPositiveScores(scores: scores), scores)
    }

    /// Computes the cosine semantic-ranking signal from an already-computed
    /// `cosineScores` array. `HybridRanker` never embeds anything itself;
    /// callers embed the query and score it against their own corpus
    /// representation and pass the raw per-document results in.
    ///
    /// - Returns: an empty ranking and a full-length, all-zero `scores` array
    ///   when `cosineScores` is `nil` — the "no cosine signal available"
    ///   degradation, matching `Signals.cosine`'s documented `0.0` for "the
    ///   doc lacks an embedding". Otherwise, the positively-scored document
    ///   indices ranked descending (see `rankingOfPositiveScores(scores:)`)
    ///   alongside `cosineScores` verbatim.
    private static func computeCosineRanking(
        documents: [RankedDocument],
        cosineScores: [Double]?
    ) -> (ranking: [Int], scores: [Double]) {
        guard let cosineScores else {
            return ([], zeroScores(count: documents.count))
        }
        return (rankingOfPositiveScores(scores: cosineScores), cosineScores)
    }

    /// The indices of every positive score, descending by score — the
    /// "graceful degradation, no zero-fill" ranked-list shape
    /// `RRF.fuse(rankedLists:weights:k:)` expects: a document that scored
    /// `0.0` (no match at all for this signal) is simply absent from the
    /// list, exactly as if it weren't in the corpus for this signal.
    private static func rankingOfPositiveScores(scores: [Double]) -> [Int] {
        scores.indices.filter { scores[$0] > 0.0 }.sorted { scores[$0] > scores[$1] }
    }

    /// A `count`-long array of `0.0` scores — the "signal couldn't be
    /// computed" placeholder BM25/cosine ranking returns alongside an empty
    /// ranking when their guard fails (empty query, no cosine scores
    /// supplied).
    private static func zeroScores(count: Int) -> [Double] {
        [Double](repeating: 0.0, count: count)
    }

    // MARK: - Fusion

    /// Fuses `signals` via `RRF.fuse(rankedLists:weights:k:)` and normalizes
    /// to `[0, 1]` via `RRF.normalize(fused:weights:k:)`, excluding any
    /// signal whose weight is `0.0` or whose ranking is empty from both the
    /// fusion and the normalization ceiling (the absent-signal rule).
    ///
    /// - Parameters:
    ///   - signals: the per-signal rankings to fuse.
    ///   - weights: the per-signal fusion weights.
    /// - Returns: document index -> normalized `[0, 1]` fused score, for
    ///   every document any included signal ranked.
    private static func fuseAndNormalize(signals: RetrievalSignals, weights: SignalWeights) -> [Int: Double] {
        let rankedSignals: [(ranking: [Int], weight: Double)] = [
            (signals.bm25Ranking, weights.bm25),
            (signals.trigramRanking, weights.trigram),
            (signals.cosineRanking, weights.cosine),
        ]

        var rankedLists: [[Int]] = []
        var listWeights: [Double] = []
        // Only signals with a positive configured weight AND at least one
        // matching document enter RRF's inputs: an empty ranking would
        // contribute nothing to `fuse` regardless, but leaving its weight
        // out of `normalize`'s ceiling too keeps a perfect single-signal
        // match normalizing to 1.0 instead of being capped below it by an
        // unreachable share.
        for (ranking, weight) in rankedSignals where weight > 0.0 && !ranking.isEmpty {
            rankedLists.append(ranking)
            listWeights.append(weight)
        }

        let fused = RRF.fuse(rankedLists: rankedLists, weights: listWeights)
        return RRF.normalize(fused: fused, weights: listWeights)
    }

    /// Sorts document indices by descending normalized fused score, breaking
    /// ties by ascending index for deterministic, first-seen-order output —
    /// the shared ordering both `topMatches(ids:documents:query:
    /// cosineScores:weights:limit:)` and `fullOrdering(ids:documents:query:
    /// cosineScores:weights:)` apply to `normalized`'s keys.
    ///
    /// - Parameters:
    ///   - indices: the document indices to sort.
    ///   - normalized: document index -> normalized `[0, 1]` fused score.
    /// - Returns: `indices`, ordered descending by score.
    private static func sortByNormalizedScore(_ indices: [Int], using normalized: [Int: Double]) -> [Int] {
        indices.sorted { left, right in
            let leftScore = normalized[left] ?? 0.0
            let rightScore = normalized[right] ?? 0.0
            guard leftScore != rightScore else {
                // Deterministic tie-break: ascending array index.
                return left < right
            }
            return leftScore > rightScore
        }
    }

    /// Maps document indices back through `ids` to `Hit`s, carrying
    /// `normalized`'s fused score (`0.0` if absent) and `signals`' raw
    /// per-signal breakdown for each — the shared "build a `Hit`" step both
    /// output shapes apply to differently-ordered/truncated
    /// `documentIndices`.
    ///
    /// - Parameters:
    ///   - documentIndices: the document indices (into `ids`) to map, in the
    ///     order the result should preserve.
    ///   - ids: the ids to look each document index up in.
    ///   - normalized: document index -> normalized `[0, 1]` fused score.
    ///   - signals: the raw per-signal scores every document was computed
    ///     against.
    /// - Returns: one `Hit` per document index, in order.
    private static func buildHits(
        documentIndices: [Int],
        ids: [String],
        normalized: [Int: Double],
        signals: RetrievalSignals
    ) -> [Hit] {
        documentIndices.map { documentIndex in
            Hit(
                id: ids[documentIndex],
                score: normalized[documentIndex] ?? 0.0,
                signals: Signals(
                    bm25: signals.bm25Scores[documentIndex],
                    trigram: signals.trigramScores[documentIndex],
                    cosine: signals.cosineScores[documentIndex]
                )
            )
        }
    }
}
