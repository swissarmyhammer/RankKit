// Extracted from CodeContextKit's `Sources/CodeContextKit/Search/SearchCorpus.swift`
// (`SearchCorpus.preprocessRow`) and FoundationModelsMetadataRegistry's
// `Sources/FoundationModelsMetadataRegistry/Catalog/MetadataIndex.swift` build
// step — the two repos' structurally-duplicated per-document precompute
// (plan.md §1, §6 phase 2). Field names follow RankKit's domain-neutral
// "primary"/"body" convention (plan.md §4.1) rather than either source's
// corpus-specific naming (`symbolPath`/`text`, `id`/`block`). No behavior
// changes.

/// One document's precomputed BM25/trigram statistics, ready for the
/// per-signal scorers to consume without re-tokenizing on every query.
///
/// Built once per document (`init(primaryText:bodyText:)`) — tokenizing and
/// trigramming is the expensive part of scoring, so both source
/// implementations precompute it per document rather than per query. A
/// consumer builds one `RankedDocument` per item in its corpus and reuses it
/// across every `Searcher`/`HybridRanker` call.
///
/// Pure and dependency-free: no storage, corpus, or query state — only the
/// two input strings feed the precompute, so identical inputs always
/// produce identical output.
public struct RankedDocument: Sendable, Equatable {
    /// This document's field-weighted term frequency: `primaryText`'s
    /// tokens weighted `BM25.primaryFieldWeight`, `bodyText`'s tokens
    /// weighted `BM25.bodyFieldWeight`, summed per term across both fields
    /// and all occurrences. This is the `tf` `BM25Corpus.score` consumes.
    public let weightedTermFrequency: [String: Double]

    /// This document's distinct term set — `Set(weightedTermFrequency.keys)`
    /// — cached separately so a corpus doesn't need to rebuild it from
    /// `weightedTermFrequency` on every query (e.g. for
    /// `BM25Corpus.init(queryTokens:documents:)`'s per-document term
    /// presence check).
    public let termSet: Set<String>

    /// This document's unweighted token count across both fields — `|D|`,
    /// the length `BM25Corpus.score(weightedTermFrequency:documentLength:queryTokens:)`
    /// needs for length normalization. Unlike `weightedTermFrequency`, this
    /// count is *not* field-weighted.
    public let documentLength: Int

    /// This document's canonical trigram set for `primaryText`, from
    /// `Trigram.canonicalTrigramSet(text:)`.
    public let primaryTrigramSet: Set<String>

    /// This document's canonical trigram set for `bodyText`, from
    /// `Trigram.canonicalTrigramSet(text:)`.
    public let bodyTrigramSet: Set<String>

    /// Precompute one document's BM25/trigram statistics from its two
    /// fields.
    ///
    /// - Parameters:
    ///   - primaryText: the document's primary field (e.g. a title, symbol
    ///     path, or id) — weighted `BM25.primaryFieldWeight` in
    ///     `weightedTermFrequency`.
    ///   - bodyText: the document's body field (e.g. full text or a content
    ///     block) — weighted `BM25.bodyFieldWeight` in
    ///     `weightedTermFrequency`.
    public init(primaryText: String, bodyText: String) {
        let primaryTokens = Tokenizer.tokenize(text: primaryText)
        let bodyTokens = Tokenizer.tokenize(text: bodyText)

        var weightedTermFrequency: [String: Double] = [:]
        for token in primaryTokens {
            weightedTermFrequency[token, default: 0.0] += BM25.primaryFieldWeight
        }
        for token in bodyTokens {
            weightedTermFrequency[token, default: 0.0] += BM25.bodyFieldWeight
        }

        self.weightedTermFrequency = weightedTermFrequency
        termSet = Set(weightedTermFrequency.keys)
        documentLength = primaryTokens.count + bodyTokens.count
        primaryTrigramSet = Trigram.canonicalTrigramSet(text: primaryText)
        bodyTrigramSet = Trigram.canonicalTrigramSet(text: bodyText)
    }
}
