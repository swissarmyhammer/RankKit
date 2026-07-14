import FoundationModelsRanker
import Testing

/// Tokenizer and character-trigram Sørensen-Dice tests, ported from
/// FoundationModelsMetadataRegistry's `TrigramTests.swift` (which itself
/// adapted CodeContextKit's `RankerTests.swift` "Tokenizer" and "Trigram
/// Dice" sections, porting the Rust `swissarmyhammer-search` crate's
/// `tokenize.rs`/`score.rs` test suites; see plan.md §5 "Search"). `Trigram`
/// canonicalizes through `Tokenizer.tokenize(text:)`, so both are exercised
/// here.
struct TrigramTests {
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
    func kebabCaseSplits() {
        #expect(Tokenizer.tokenize(text: "deploy-k8s") == ["deploy", "k8s"])
    }

    @Test
    func digitBoundaryExcludedKeepsSha256Whole() {
        #expect(Tokenizer.tokenize(text: "sha256_hash") == ["sha256", "hash"])
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
    func charTrigramsSlidingWindowsLowercased() {
        #expect(Tokenizer.charTrigrams(text: "get_user") == ["get", "et_", "t_u", "_us", "use", "ser"])
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
    func diceIdenticalIsOne() {
        #expect(Trigram.dice(query: "get_user", target: "get_user") == 1.0)
    }

    @Test
    func diceDisjointIsZero() {
        #expect(Trigram.dice(query: "abcdef", target: "uvwxyz") == 0.0)
    }

    @Test
    func diceNoTrigramsIsZero() {
        #expect(Trigram.dice(query: "ab", target: "get_user") == 0.0)
        #expect(Trigram.dice(query: "get_user", target: "") == 0.0)
    }

    @Test
    func diceCamelCaseVsSnakeCaseTypoRescueAboveThreshold() {
        #expect(Trigram.dice(query: "getUsr", target: "get_user") > 0.4)
    }

    @Test
    func diceBoundsStayWithinZeroToOneAcrossPairs() {
        let pairs: [(query: String, target: String)] = [
            ("get_user", "get_user"),
            ("get_user", "getUsr"),
            ("abcdef", "uvwxyz"),
            ("kuberntes deploy", "deploy-k8s"),
            ("", "anything"),
        ]
        for pair in pairs {
            let score = Trigram.dice(query: pair.query, target: pair.target)
            #expect(score >= 0.0 && score <= 1.0)
        }
    }

    @Test
    func typoAndDelimiterStyleToleranceKubernetesDeployScoresAgainstDeployK8s() {
        // "kuberntes" is a typo of "kubernetes" (missing the second "e") and
        // uses a space delimiter, while the target uses a hyphen and the
        // abbreviation "k8s" — a literal substring match would see very
        // little overlap. Canonicalizing through `Tokenizer.tokenize` first
        // normalizes both to word-delimited form, so the shared "deploy"
        // word's trigrams overlap: canonical "kuberntes deploy" (14
        // trigrams) vs canonical "deploy k8s" (8 trigrams) share exactly
        // the 4 trigrams of "deploy" (dep/epl/plo/loy), for Dice
        // 2*4/(14+8) = 8/22.
        let score = Trigram.dice(query: "kuberntes deploy", target: "deploy-k8s")
        #expect(abs(score - 8.0 / 22.0) < 1e-9)
        #expect(score > 0.0)
    }
}
