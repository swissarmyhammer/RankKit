import FoundationModelsRanker
import Testing

/// Reciprocal Rank Fusion and `Hit`/`Signals` plumbing tests, ported from
/// FoundationModelsMetadataRegistry's `RRFTests.swift` (which itself adapted
/// CodeContextKit's `RankerTests.swift` "RRF" and "Hit / Signals" sections,
/// porting the Rust `swissarmyhammer-search` crate's `score.rs`/`lib.rs`
/// test suites; see plan.md §5 "Search"). Covers the RRF acceptance
/// criteria for this port: `k = 60`, 0-based ranks, an absent signal
/// contributing nothing (never zero-filled), and normalized scores staying
/// in `[0, 1]`.
struct RRFTests {
    // MARK: - Fusion ordering (table-driven)

    struct FusionOrderingCase: Sendable {
        let name: String
        let rankedLists: [[Int]]
        let weights: [Double]
        let winner: Int
        let loser: Int
    }

    static let fusionOrderingCases: [FusionOrderingCase] = [
        FusionOrderingCase(
            name: "doc ranked in two signals beats a doc ranked in only one",
            rankedLists: [[0, 1], [0, 2], [1, 0]],
            weights: [1.0, 1.0, 1.0],
            winner: 0,
            loser: 1
        ),
        FusionOrderingCase(
            name: "a higher weight on one signal breaks a tie toward its rank-0 doc",
            rankedLists: [[0], [1]],
            weights: [2.0, 1.0],
            winner: 0,
            loser: 1
        ),
        FusionOrderingCase(
            name: "rank-0 in every list beats rank-0 in only one",
            rankedLists: [[0, 1], [0, 1]],
            weights: [1.0, 1.0],
            winner: 0,
            loser: 1
        ),
    ]

    @Test(arguments: fusionOrderingCases)
    func fusionOrdering(testCase: FusionOrderingCase) {
        let fused = RRF.fuse(rankedLists: testCase.rankedLists, weights: testCase.weights)
        #expect(fused[testCase.winner]! > fused[testCase.loser]!, "\(testCase.name)")
    }

    @Test
    func fusionMatchesHandComputedAtDefaultK() {
        let fused = RRF.fuse(rankedLists: [[0, 1], [1, 0]], weights: [1.0, 1.0], k: 60.0)
        // doc0: 1/60 + 1/61 ; doc1: 1/61 + 1/60 -> equal.
        let want = 1.0 / 60.0 + 1.0 / 61.0
        #expect(abs(fused[0]! - want) < 1e-6)
        #expect(abs(fused[1]! - want) < 1e-6)
    }

    @Test
    func fusionUsesZeroBasedRanks() {
        // Rank 0 (first position) must score strictly higher than rank 1
        // for the same list/weight, proving ranks are 0-based rather than
        // 1-based (which would instead read 1/(k+1) for the leader).
        let fused = RRF.fuse(rankedLists: [[0, 1]], weights: [1.0], k: 60.0)
        #expect(abs(fused[0]! - 1.0 / 60.0) < 1e-6)
        #expect(abs(fused[1]! - 1.0 / 61.0) < 1e-6)
    }

    // MARK: - Absent signal contributes nothing

    @Test
    func fusionAbsentSignalContributesNothingNotZeroFilled() {
        // doc 0 appears only in list 0, doc 1 only in list 1. If an absent
        // signal were zero-filled rather than skipped, both docs would sum
        // an extra 0.0 term and the result would be unchanged here — so
        // this test alone doesn't distinguish the two. What it does pin
        // down is that a doc absent from a list is not penalized beyond
        // simply not receiving that list's contribution.
        let fused = RRF.fuse(rankedLists: [[0], [1]], weights: [1.0, 1.0], k: 60.0)
        #expect(abs(fused[0]! - 1.0 / 60.0) < 1e-6)
        #expect(abs(fused[1]! - 1.0 / 60.0) < 1e-6)
        #expect(fused.count == 2)
    }

    @Test
    func fusionOnlyIncludesDocumentsPresentInAtLeastOneList() {
        let fused = RRF.fuse(rankedLists: [[0, 2], [1]], weights: [1.0, 1.0])
        #expect(Set(fused.keys) == Set([0, 1, 2]))
    }

    // MARK: - Weight = 0 exclusion

    @Test
    func fuseWithZeroWeightSignalExcludesItsContribution() {
        // A zero-weight signal must behave as if it weren't present at
        // all: a doc ranked only in the zero-weight list gets a
        // contribution of exactly 0.0, not some small non-zero fraction.
        let fused = RRF.fuse(rankedLists: [[0], [1]], weights: [1.0, 0.0])
        #expect(abs(fused[0]! - 1.0 / 60.0) < 1e-6)
        #expect(fused[1] == 0.0)
    }

    // MARK: - Normalization bounds

    @Test
    func normalizeRankZeroInEverySignalIsExactlyOne() {
        // "best" (doc 0) is rank-0 in both signals -> the maximum
        // achievable score, so normalization lands exactly at 1.0.
        let fused = RRF.fuse(rankedLists: [[0, 1], [0, 1]], weights: [1.0, 1.0])
        let normalized = RRF.normalize(fused: fused, weights: [1.0, 1.0])
        #expect(abs(normalized[0]! - 1.0) < 1e-6)
        #expect(normalized[0]! > normalized[1]!)
    }

    @Test
    func normalizeStaysWithinZeroToOneBounds() {
        let fused = RRF.fuse(rankedLists: [[0, 1, 2], [2, 1, 0]], weights: [1.0, 1.0])
        let normalized = RRF.normalize(fused: fused, weights: [1.0, 1.0])
        for value in normalized.values {
            #expect(value >= 0.0 && value <= 1.0)
        }
    }

    @Test
    func normalizeWithAllZeroWeightsIsZeroEverywhere() {
        let fused = RRF.fuse(rankedLists: [[0]], weights: [0.0])
        let normalized = RRF.normalize(fused: fused, weights: [0.0])
        #expect(normalized[0] == 0.0)
    }

    // MARK: - Hit / Signals

    @Test
    func signalsAndHitStoreConstructorArguments() {
        let signals = Signals(bm25: 1.5, trigram: 0.75, cosine: 0.9)
        #expect(signals.bm25 == 1.5)
        #expect(signals.trigram == 0.75)
        #expect(signals.cosine == 0.9)

        let hit = Hit(id: "tool-name", score: 0.42, signals: signals)
        #expect(hit.id == "tool-name")
        #expect(hit.score == 0.42)
        #expect(hit.signals == signals)
    }
}
