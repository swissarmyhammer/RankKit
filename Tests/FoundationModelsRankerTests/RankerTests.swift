import FoundationModelsRanker
import Testing

/// Golden-ordering and formula tests for the tokenizer, trigram-Dice, and
/// RRF primitives, ported from CodeContextKit's `RankerTests.swift`
/// (Tokenizer, Trigram Dice, RRF, and Hit/Signals sections only — the BM25
/// sections are out of scope here and stay in CodeContextKit), which itself
/// ports `crates/swissarmyhammer-search`'s `tokenize.rs`/`score.rs` test
/// suites (see plan.md §5 "Search"). Kept alongside `TrigramTests.swift`/
/// `RRFTests.swift` (ported from FoundationModelsMetadataRegistry) even
/// where cases overlap — each repo's suite encodes its own edge-case
/// history (plan.md §5).
struct RankerTests {
    // MARK: - Tokenizer

    @Test
    func camelCaseSplitsLowercased() {
        #expect(Tokenizer.tokenize(text: "getUserById") == ["get", "user", "by", "id"])
    }

    @Test
    func snakeCaseSplits() {
        #expect(Tokenizer.tokenize(text: "get_user_by_id") == ["get", "user", "by", "id"])
    }

    @Test
    func acronymRunSplits() {
        #expect(Tokenizer.tokenize(text: "getHTTPResponse") == ["get", "http", "response"])
    }

    @Test
    func digitBoundaryExcludedKeepsSha256Whole() {
        #expect(Tokenizer.tokenize(text: "sha256_hash") == ["sha256", "hash"])
    }

    @Test
    func digitBoundaryExcludedKeepsUtf8Whole() {
        #expect(Tokenizer.tokenize(text: "utf8") == ["utf8"])
    }

    @Test
    func punctuationStrippedNoEmptyStrings() {
        #expect(Tokenizer.tokenize(text: "fn parse_config() -> Result") == ["fn", "parse", "config", "result"])
    }

    @Test
    func termFrequencyPreservedDuplicatesNotDeduped() {
        #expect(Tokenizer.tokenize(text: "foo foo bar") == ["foo", "foo", "bar"])
    }

    @Test
    func emptyInputYieldsNoTokens() {
        #expect(Tokenizer.tokenize(text: "").isEmpty)
    }

    @Test
    func periodBetweenLettersGluesRunLikeUnicodeWordsMidNumLet() {
        // Mirrors Rust's `unicode_words()`, which treats `.` as `MidNumLet`
        // and glues a letter-flanked period into one word rather than
        // breaking on it; `.` is not an identifier boundary, so the glued
        // run stays a single token.
        #expect(Tokenizer.tokenize(text: "foo.bar") == ["foo.bar"])
    }

    @Test
    func apostropheBetweenLettersGluesContraction() {
        #expect(Tokenizer.tokenize(text: "don't") == ["don't"])
    }

    @Test
    func leadingAndTrailingPeriodsAreStrippedNotGlued() {
        // A `.`/`'` only glues when flanked by a letter/digit on *both*
        // sides; at the start/end of the text there is no flanking
        // character, so it behaves like ordinary punctuation.
        #expect(Tokenizer.tokenize(text: ".foo.") == ["foo"])
    }

    @Test
    func charTrigramsSlidingWindowsLowercased() {
        #expect(Tokenizer.charTrigrams(text: "get_user") == ["get", "et_", "t_u", "_us", "use", "ser"])
    }

    @Test
    func charTrigramsLowercasesInput() {
        #expect(Tokenizer.charTrigrams(text: "ABCD") == ["abc", "bcd"])
    }

    @Test
    func charTrigramsShortStringIsEmpty() {
        #expect(Tokenizer.charTrigrams(text: "").isEmpty)
        #expect(Tokenizer.charTrigrams(text: "a").isEmpty)
        #expect(Tokenizer.charTrigrams(text: "ab").isEmpty)
        #expect(Tokenizer.charTrigrams(text: "abc") == ["abc"])
    }

    // MARK: - Trigram Dice

    @Test
    func trigramDiceIdenticalIsOne() {
        #expect(Trigram.dice(query: "get_user", target: "get_user") == 1.0)
    }

    @Test
    func trigramDiceTypoRescueAboveThreshold() {
        #expect(Trigram.dice(query: "getUsr", target: "get_user") > 0.4)
    }

    @Test
    func trigramDiceDisjointIsZero() {
        #expect(Trigram.dice(query: "abcdef", target: "uvwxyz") == 0.0)
    }

    @Test
    func trigramDiceNoTrigramsIsZero() {
        #expect(Trigram.dice(query: "ab", target: "get_user") == 0.0)
        #expect(Trigram.dice(query: "get_user", target: "") == 0.0)
    }

    // MARK: - RRF

    @Test
    func rrfTwoListsBeatOne() {
        // doc 0 is rank-0 in lists 0 and 1; doc 1 is rank-0 only in list 2.
        let fused = RRF.fuse(
            rankedLists: [[0, 1], [0, 2], [1, 0]],
            weights: [1.0, 1.0, 1.0]
        )
        #expect(fused[0]! > fused[1]!)
    }

    @Test
    func rrfMatchesHandComputed() {
        let fused = RRF.fuse(rankedLists: [[0, 1], [1, 0]], weights: [1.0, 1.0], k: 60.0)
        // doc0: 1/60 + 1/61 ; doc1: 1/61 + 1/60 -> equal.
        let want = 1.0 / 60.0 + 1.0 / 61.0
        #expect(abs(fused[0]! - want) < 1e-6)
        #expect(abs(fused[1]! - want) < 1e-6)
    }

    @Test
    func rrfMissingDocContributesNothing() {
        let fused = RRF.fuse(rankedLists: [[0], [1]], weights: [1.0, 1.0], k: 60.0)
        #expect(abs(fused[0]! - 1.0 / 60.0) < 1e-6)
        #expect(abs(fused[1]! - 1.0 / 60.0) < 1e-6)
    }

    @Test
    func rrfWeightEffect() {
        let fused = RRF.fuse(rankedLists: [[0], [1]], weights: [2.0, 1.0], k: 60.0)
        #expect(fused[0]! > fused[1]!)
        #expect(abs(fused[0]! - 2.0 / 60.0) < 1e-6)
    }

    @Test
    func rrfNormalizeRankZeroEverywhereIsOne() {
        // "best" (doc 0) is rank-0 in both signals -> the maximum
        // achievable score, so normalization lands exactly at 1.0.
        let fused = RRF.fuse(rankedLists: [[0, 1], [0, 1]], weights: [1.0, 1.0])
        let normalized = RRF.normalize(fused: fused, weights: [1.0, 1.0])
        #expect(abs(normalized[0]! - 1.0) < 1e-6)
        #expect(normalized[0]! > normalized[1]!)
    }

    @Test
    func rrfNormalizeWithNoWeightsIsZeroEverywhere() {
        let fused = RRF.fuse(rankedLists: [[0]], weights: [0.0])
        let normalized = RRF.normalize(fused: fused, weights: [0.0])
        #expect(normalized[0] == 0.0)
    }

    // MARK: - Hit / Signals

    // Note: CodeContextKit's `fusedBm25AndTrigramSignalsRankSymbolPathMatchFirst`
    // golden-ordering test is not ported here — it fuses BM25 with trigram,
    // and BM25 is a separate, not-yet-ported primitive (kanban task
    // "Port BM25 with neutral field-weight names"). It belongs with that
    // port, not this one.

    @Test
    func signalsAndHitStoreConstructorArguments() {
        let signals = Signals(bm25: 1.5, trigram: 0.75, cosine: 0.9)
        #expect(signals.bm25 == 1.5)
        #expect(signals.trigram == 0.75)
        #expect(signals.cosine == 0.9)

        let hit = Hit(id: "doc-1", score: 0.42, signals: signals)
        #expect(hit.id == "doc-1")
        #expect(hit.score == 0.42)
        #expect(hit.signals == signals)
    }
}
