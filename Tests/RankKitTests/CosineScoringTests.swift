import Foundation
import RankKit
import Testing

/// `CosineScoring` tests (plan.md §1 "Genuinely different (stays put)", §6
/// phase 2): the two cosine-scoring strategies CodeContextKit and
/// FoundationModelsMetadataRegistry each carry today, side by side in one
/// shared utility.
///
/// `matvecScores` cases are ported from CodeContextKit's
/// `SearchCorpusMatvecTests` (`Tests/CodeContextKitTests/SearchCodeTests.swift`)
/// — the `vDSP_mmul`-backed matvec against a scalar dot-product reference,
/// plus its documented degenerate-input behavior. `cosineSimilarity` cases
/// encode FoundationModelsMetadataRegistry's `MetadataSearcher.cosineSimilarity`
/// doc comment: `(a · b) / (|a| |b|)` in `[-1.0, 1.0]`, `0.0` for
/// mismatched lengths or either vector having zero magnitude.
struct CosineScoringTests {
    // MARK: - matvecScores

    @Test
    func matvecScoresMatchesScalarDotProductReferenceWithinTolerance() {
        let rowCount = 37
        let dimension = 13
        let matrixRows = (0..<rowCount).map { _ in normalized((0..<dimension).map { _ in Float.random(in: -1...1) }) }
        let matrix = matrixRows.flatMap { $0 }
        let queryVector = normalized((0..<dimension).map { _ in Float.random(in: -1...1) })

        let matvecScores = CosineScoring.matvecScores(
            matrix: matrix, rowCount: rowCount, dimension: dimension, queryVector: queryVector
        )

        #expect(matvecScores.count == rowCount)
        for rowIndex in 0..<rowCount {
            let scalarDotProduct = zip(matrixRows[rowIndex], queryVector).reduce(Float(0)) { $0 + $1.0 * $1.1 }
            #expect(abs(matvecScores[rowIndex] - scalarDotProduct) < 1e-5)
        }
    }

    @Test
    func matvecScoresIsZeroWhenQueryDimensionDoesNotMatch() {
        let matrix: [Float] = [1, 0, 0, 0, 1, 0]
        let scores = CosineScoring.matvecScores(matrix: matrix, rowCount: 2, dimension: 3, queryVector: [1, 0])
        #expect(scores == [0.0, 0.0])
    }

    @Test
    func matvecScoresIsEmptyForZeroRows() {
        let scores = CosineScoring.matvecScores(matrix: [], rowCount: 0, dimension: 3, queryVector: [1, 0, 0])
        #expect(scores.isEmpty)
    }

    @Test
    func matvecScoresIsZeroFilledForZeroDimension() {
        let scores = CosineScoring.matvecScores(matrix: [], rowCount: 3, dimension: 0, queryVector: [])
        #expect(scores == [0.0, 0.0, 0.0])
    }

    // MARK: - cosineSimilarity

    @Test
    func cosineSimilarityOfIdenticalNormalizedVectorsIsOne() {
        let vector: [Float] = [1, 0, 0]
        #expect(abs(CosineScoring.cosineSimilarity(vector, vector) - 1.0) < 1e-9)
    }

    @Test
    func cosineSimilarityOfOppositeVectorsIsNegativeOne() {
        let a: [Float] = [1, 0, 0]
        let b: [Float] = [-1, 0, 0]
        #expect(abs(CosineScoring.cosineSimilarity(a, b) - (-1.0)) < 1e-9)
    }

    @Test
    func cosineSimilarityOfOrthogonalVectorsIsZero() {
        let a: [Float] = [1, 0]
        let b: [Float] = [0, 1]
        #expect(CosineScoring.cosineSimilarity(a, b) == 0.0)
    }

    @Test
    func cosineSimilarityReturnsZeroForMismatchedLengths() {
        let a: [Float] = [1, 0, 0]
        let b: [Float] = [1, 0]
        #expect(CosineScoring.cosineSimilarity(a, b) == 0.0)
    }

    @Test
    func cosineSimilarityReturnsZeroForEmptyVectors() {
        #expect(CosineScoring.cosineSimilarity([], []) == 0.0)
    }

    @Test
    func cosineSimilarityReturnsZeroWhenQueryHasZeroMagnitude() {
        let a: [Float] = [0, 0, 0]
        let b: [Float] = [1, 2, 3]
        #expect(CosineScoring.cosineSimilarity(a, b) == 0.0)
    }

    @Test
    func cosineSimilarityReturnsZeroWhenTargetHasZeroMagnitude() {
        let a: [Float] = [1, 2, 3]
        let b: [Float] = [0, 0, 0]
        #expect(CosineScoring.cosineSimilarity(a, b) == 0.0)
    }

    @Test
    func cosineSimilarityIsWithinExpectedRange() {
        for _ in 0..<25 {
            let a = (0..<8).map { _ in Float.random(in: -5...5) }
            let b = (0..<8).map { _ in Float.random(in: -5...5) }
            let similarity = CosineScoring.cosineSimilarity(a, b)
            #expect(similarity >= -1.0 - 1e-6)
            #expect(similarity <= 1.0 + 1e-6)
        }
    }

    @Test
    func cosineSimilarityMatchesMatvecScoresForL2NormalizedVectors() {
        // On L2-normalized inputs, cosine similarity reduces to a plain dot
        // product — the invariant that lets `matvecScores` skip the
        // magnitude division `cosineSimilarity` performs (plan.md "Search",
        // "Where the cosines happen").
        let dimension = 6
        let a = normalized((0..<dimension).map { _ in Float.random(in: -1...1) })
        let b = normalized((0..<dimension).map { _ in Float.random(in: -1...1) })

        let scalar = CosineScoring.cosineSimilarity(a, b)
        let matvec = CosineScoring.matvecScores(matrix: a, rowCount: 1, dimension: dimension, queryVector: b)

        #expect(abs(Float(scalar) - matvec[0]) < 1e-5)
    }
}

/// L2-normalizes `vector`, or returns it unchanged if its magnitude is `0`.
private func normalized(_ vector: [Float]) -> [Float] {
    let magnitude = sqrt(vector.reduce(Float(0)) { $0 + $1 * $1 })
    guard magnitude > 0 else { return vector }
    return vector.map { $0 / magnitude }
}
