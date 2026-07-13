import RankKit
import Testing

/// `RankedDocument` precompute tests (plan.md §6 phase 2).
///
/// `RankedDocument.init(primaryText:bodyText:)` must produce the same
/// weighted term frequencies, term sets, document lengths, and trigram sets
/// as CodeContextKit's `SearchCorpus.preprocessRow` (and FMR's equivalent
/// `MetadataIndex` build step) for identical inputs — both are
/// `primaryTokens`/`bodyTokens` folded through `BM25.primaryFieldWeight` /
/// `BM25.bodyFieldWeight` into one weighted term-frequency map, plus
/// `Trigram.canonicalTrigramSet(text:)` over each field, verbatim. Expected
/// values below are hand-traced through `Tokenizer.tokenize(text:)` and
/// `Tokenizer.charTrigrams(text:)`, matching the small-fixture style of
/// `TrigramTests` and `RankerTests`' `BM25Corpus` literals, so a bug in
/// `RankedDocument`'s own folding logic (wrong weight, dropped occurrence,
/// mixed-up field) shows up as a literal mismatch rather than passing by
/// construction.
struct RankedDocumentTests {
    @Test
    func weightedTermFrequencyAppliesPrimaryAndBodyFieldWeights() {
        // tokenize("cat") == ["cat"], tokenize("dog") == ["dog"].
        let document = RankedDocument(primaryText: "cat", bodyText: "dog")
        #expect(document.weightedTermFrequency == ["cat": BM25.primaryFieldWeight, "dog": BM25.bodyFieldWeight])
    }

    @Test
    func weightedTermFrequencySumsOverlappingTermAcrossFieldsAndOccurrences() {
        // tokenize("cat cat") == ["cat", "cat"] (two primary-field
        // occurrences), tokenize("cat") == ["cat"] (one body-field
        // occurrence) — the three occurrences sum: 2*primaryFieldWeight +
        // 1*bodyFieldWeight.
        let document = RankedDocument(primaryText: "cat cat", bodyText: "cat")
        #expect(document.weightedTermFrequency == ["cat": 2 * BM25.primaryFieldWeight + BM25.bodyFieldWeight])
    }

    @Test
    func termSetIsTheDistinctKeysOfWeightedTermFrequency() {
        let document = RankedDocument(primaryText: "cat cat", bodyText: "cat dog")
        #expect(document.termSet == Set(document.weightedTermFrequency.keys))
        #expect(document.termSet == ["cat", "dog"])
    }

    @Test
    func documentLengthCountsUnweightedTokensAcrossBothFields() {
        // tokenize("foo bar") has 2 tokens, tokenize("bar baz") has 2 —
        // documentLength is the unweighted sum, unlike weightedTermFrequency
        // which is field-weighted.
        let document = RankedDocument(primaryText: "foo bar", bodyText: "bar baz")
        #expect(document.documentLength == 4)
        #expect(document.weightedTermFrequency == [
            "foo": BM25.primaryFieldWeight,
            "bar": BM25.primaryFieldWeight + BM25.bodyFieldWeight,
            "baz": BM25.bodyFieldWeight,
        ])
    }

    @Test
    func trigramSetsAreCanonicalPerField() {
        // canonicalTrigramSet("cat") == charTrigrams("cat") == {"cat"}
        // (single word, single 3-character window).
        let document = RankedDocument(primaryText: "cat", bodyText: "dog")
        #expect(document.primaryTrigramSet == ["cat"])
        #expect(document.bodyTrigramSet == ["dog"])
    }

    @Test
    func trigramSetCanonicalizesThroughTokenizerLikeMultiWordText() {
        // tokenize("cat cat") == ["cat", "cat"], re-joined "cat cat" (7
        // chars) windows to: cat, at , t c,  ca, cat -> distinct set of 4.
        let document = RankedDocument(primaryText: "cat cat", bodyText: "cat")
        #expect(document.primaryTrigramSet == ["cat", "at ", "t c", " ca"])
        #expect(document.bodyTrigramSet == ["cat"])
    }

    @Test
    func emptyPrimaryTextOnlyCountsBodyTokensAndTrigrams() {
        let document = RankedDocument(primaryText: "", bodyText: "hello world")
        #expect(document.weightedTermFrequency == ["hello": BM25.bodyFieldWeight, "world": BM25.bodyFieldWeight])
        #expect(document.termSet == ["hello", "world"])
        #expect(document.documentLength == 2)
        #expect(document.primaryTrigramSet.isEmpty)
        #expect(!document.bodyTrigramSet.isEmpty)
    }

    @Test
    func emptyBodyTextOnlyCountsPrimaryTokensAndTrigrams() {
        // tokenize("hello") == ["hello"]; charTrigrams("hello") == ["hel",
        // "ell", "llo"].
        let document = RankedDocument(primaryText: "hello", bodyText: "")
        #expect(document.weightedTermFrequency == ["hello": BM25.primaryFieldWeight])
        #expect(document.termSet == ["hello"])
        #expect(document.documentLength == 1)
        #expect(document.primaryTrigramSet == ["hel", "ell", "llo"])
        #expect(document.bodyTrigramSet.isEmpty)
    }

    @Test
    func emptyBothFieldsYieldsAllEmptyPrecompute() {
        let document = RankedDocument(primaryText: "", bodyText: "")
        #expect(document.weightedTermFrequency.isEmpty)
        #expect(document.termSet.isEmpty)
        #expect(document.documentLength == 0)
        #expect(document.primaryTrigramSet.isEmpty)
        #expect(document.bodyTrigramSet.isEmpty)
    }

    @Test
    func unicodeTextTokenizesAsOneRunAndTrigramsByGraphemeCluster() {
        // "héllo" is one letter-only run, so tokenize keeps it whole; its
        // canonical trigram set windows over 5 `Character`s (grapheme
        // clusters, "é" counts as one), matching Tokenizer.charTrigrams'
        // documented Unicode-safety.
        let document = RankedDocument(primaryText: "héllo", bodyText: "")
        #expect(document.weightedTermFrequency == ["héllo": BM25.primaryFieldWeight])
        #expect(document.termSet == ["héllo"])
        #expect(document.documentLength == 1)
        #expect(document.primaryTrigramSet == ["hél", "éll", "llo"])
    }

    @Test
    func isSendable() {
        func requireSendable(_: some Sendable) {}
        requireSendable(RankedDocument(primaryText: "cat", bodyText: "dog"))
    }
}
