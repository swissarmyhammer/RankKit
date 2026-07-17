// Ported from CodeContextKit's `Sources/CodeContextKit/Search/BM25.swift`,
// which itself ports the Rust `swissarmyhammer-search` crate's `score.rs`
// (plan.md §3). The two field-weight constants are renamed to
// domain-neutral names (plan.md §4.1): CodeContextKit's
// `symbolPathFieldWeight` / FoundationModelsMetadataRegistry's
// `idFieldWeight` -> `primaryFieldWeight`; `bodyFieldWeight` /
// `blockFieldWeight` -> `bodyFieldWeight` (name unchanged, same value). No
// other behavior changes.

import Foundation

/// BM25 scoring constants: term-frequency saturation (`k1`), length
/// normalization (`b`), and the two field weights used to build a
/// document's weighted term frequency (see plan.md "Search"). Ported from
/// the Rust crate's `score.rs`.
public enum BM25 {
    /// Term-frequency saturation parameter `k1`.
    public static let k1: Double = 1.2

    /// Length-normalization parameter `b`.
    public static let b: Double = 0.75

    /// Field weight applied to a document's primary-field occurrences when
    /// computing its weighted term frequency — five times
    /// `bodyFieldWeight`, so a primary-field match dominates a
    /// body-field-only match for the same term.
    public static let primaryFieldWeight: Double = 5.0

    /// Field weight applied to a document's body-field occurrences when
    /// computing its weighted term frequency; the baseline weight.
    public static let bodyFieldWeight: Double = 1.0
}

/// Precomputed corpus statistics for a single BM25 query.
///
/// Built once per query in a single corpus pass (`init(queryTokens:
/// documents:)`) and then consumed by
/// `score(weightedTermFrequency:documentLength:queryTokens:)` for every
/// document. It captures only the statistics BM25 needs: the document
/// frequency of each query term, the total document count, and the mean
/// *unweighted* token count.
///
/// **Per query, never cached across queries.** `df`/`idf` and `avgdl` are
/// whole-corpus values, so a copy held across mutations of the corpus that
/// produced it would be wrong the moment a document is added or removed.
/// Deriving them fresh from the caller's live documents on every query is what
/// keeps them correct under a corpus that streams (`SearchCorpus`), and it is
/// free in practice: the pass this initializer makes is the same pass the
/// scorer already makes over the same documents, and `df` is tracked only for
/// the terms this query actually asks about.
public struct BM25Corpus: Sendable {
    /// `df(t)`: number of documents containing query term `t` in any
    /// field. Tracked only for the query terms this corpus was built with;
    /// read through `documentFrequency(forTerm:)`.
    private let termDocumentFrequency: [String: Int]

    /// `N`: total number of documents in the corpus.
    public let documentCount: Int

    /// `avgdl`: mean unweighted token count across all documents -- `0.0`
    /// for an empty corpus, which has no meaningful length normalization.
    public let averageDocumentLength: Double

    /// Build corpus statistics in a single pass over `documents`.
    ///
    /// - Parameters:
    ///   - queryTokens: the tokenized query. Document frequency is tracked
    ///     only for these terms (duplicates collapse to one entry each).
    ///   - documents: one entry per document: its unweighted token count
    ///     (`|D|`, across all fields) paired with the set of query terms
    ///     present in any of its fields.
    public init(queryTokens: [String], documents: some Sequence<(Int, Set<String>)>) {
        var frequency = Dictionary(queryTokens.map { ($0, 0) }, uniquingKeysWith: { first, _ in first })
        var count = 0
        var totalLength = 0
        for (tokenCount, presentTerms) in documents {
            count += 1
            totalLength += tokenCount
            for term in presentTerms where frequency[term] != nil {
                frequency[term, default: 0] += 1
            }
        }
        termDocumentFrequency = frequency
        documentCount = count
        averageDocumentLength = count == 0 ? 0.0 : Double(totalLength) / Double(count)
    }

    /// `df(t)`: how many of this corpus's documents contain `term` in any
    /// field.
    ///
    /// - Parameter term: the term to look up. Only the query terms this
    ///   corpus was built with are tracked; any other term reports `0`,
    ///   indistinguishable from a tracked term no document contains.
    /// - Returns: the document frequency of `term`.
    public func documentFrequency(forTerm term: String) -> Int {
        termDocumentFrequency[term] ?? 0
    }

    /// `IDF(t) = ln(1 + (N − df(t) + 0.5) / (df(t) + 0.5))`: how much a match
    /// on `term` is worth, given how many of this corpus's documents contain
    /// it -- the whole-corpus factor weighting every term's contribution to
    /// `score(weightedTermFrequency:documentLength:queryTokens:)`.
    ///
    /// - Parameter term: the term to weight. See `documentFrequency(forTerm:)`
    ///   for how an untracked term reports.
    /// - Returns: the inverse document frequency of `term` -- larger the rarer
    ///   `term` is across the corpus.
    public func inverseDocumentFrequency(forTerm term: String) -> Double {
        let df = Double(documentFrequency(forTerm: term))
        return log(1.0 + (Double(documentCount) - df + 0.5) / (df + 0.5))
    }

    /// Score a single document with weighted-tf Okapi BM25 ("BM25F-lite").
    ///
    /// Implements `Σ_t IDF(t)·tf·(k1+1) / (tf + k1·(1 − b + b·|D|/avgdl))`
    /// over the distinct query terms, where `IDF(t) = ln(1 + (N − df(t) +
    /// 0.5) / (df(t) + 0.5))` and `tf` is the document's *weighted* term
    /// frequency for `t` — the sum of field weights (e.g.
    /// `BM25.primaryFieldWeight` / `BM25.bodyFieldWeight`) over each
    /// occurrence of `t` across all fields.
    ///
    /// - Parameters:
    ///   - weightedTermFrequency: per-term weighted term frequency for this
    ///     document; a term missing from this map is treated as `0.0`.
    ///   - documentLength: the document's unweighted token count (`|D|`).
    ///   - queryTokens: the tokenized query; deduplicated internally so a
    ///     repeated query term is not double-counted.
    /// - Returns: the BM25 score — always finite, `0.0` when no query term
    ///   matches or the corpus is empty.
    public func score(
        weightedTermFrequency: [String: Double],
        documentLength: Int,
        queryTokens: [String]
    ) -> Double {
        // An empty corpus has no meaningful length normalization.
        guard averageDocumentLength > 0 else { return 0.0 }
        let lengthNorm = BM25.k1 * (1.0 - BM25.b + BM25.b * Double(documentLength) / averageDocumentLength)

        let distinctTerms = Set(queryTokens)
        return distinctTerms.reduce(0.0) { total, term in
            guard let termFrequency = weightedTermFrequency[term], termFrequency != 0.0 else { return total }
            let idf = inverseDocumentFrequency(forTerm: term)
            return total + idf * termFrequency * (BM25.k1 + 1.0) / (termFrequency + lengthNorm)
        }
    }
}
