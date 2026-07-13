// Ported from CodeContextKit's `Sources/CodeContextKit/Search/SearchCorpus.swift`
// (`SearchCorpusSnapshot.matvecCosineScores`/`multiplyMatrixByVector`) and
// FoundationModelsMetadataRegistry's `Sources/FoundationModelsMetadataRegistry/
// MetadataSearcher.swift` (`MetadataSearcher.cosineSimilarity`) — plan.md §1
// "Genuinely different (stays put)": the two repos' cosine-scoring
// strategies are kept side by side here rather than unified, so either
// consumer can adopt whichever fits its corpus representation (§6 phase 2).
// No behavior changes.

import Accelerate

/// Cosine-similarity scoring, in the two forms CodeContextKit and
/// FoundationModelsMetadataRegistry each carry today:
///
/// - `matvecScores(matrix:rowCount:dimension:queryVector:)`: a single
///   `vDSP_mmul` matrix–vector product over a contiguous row-major matrix of
///   L2-normalized rows, where cosine similarity reduces to a plain dot
///   product. Suits a corpus that keeps its embeddings packed into one
///   contiguous buffer (CodeContextKit's `SearchCorpusSnapshot`).
/// - `cosineSimilarity(_:_:)`: the scalar per-vector `(a · b) / (|a| |b|)`
///   form, which works on un-normalized vectors and handles length
///   mismatches. Suits a corpus that stores embeddings as separate arrays
///   (FoundationModelsMetadataRegistry's `MetadataIndex`).
///
/// `import Accelerate` is Apple-only — fine at RankKit's macOS 27 floor.
public enum CosineScoring {
    /// Scores every row of `matrix` against `queryVector` with one
    /// `vDSP_mmul` matrix–vector product.
    ///
    /// `vDSP_mmul` multiplies `matrix` (treated as `rowCount × dimension`)
    /// by `queryVector` (treated as `dimension × 1`), producing the
    /// `rowCount × 1` result in one call — the vDSP counterpart to
    /// `cblas_sgemv`, chosen over the CBLAS entry point because
    /// `cblas_sgemv` is deprecated on this platform in favor of an ILP64
    /// interface not otherwise needed here.
    ///
    /// Both `matrix`'s rows and `queryVector` must already be L2-normalized
    /// for the result to be a cosine similarity — on normalized inputs, the
    /// dot product this computes *is* cosine similarity, so no separate
    /// magnitude division is needed (unlike `cosineSimilarity(_:_:)`).
    ///
    /// - Parameters:
    ///   - matrix: a row-major `rowCount × dimension` matrix; `matrix.count`
    ///     must equal `rowCount * dimension`.
    ///   - rowCount: the number of rows in `matrix`.
    ///   - dimension: the number of columns in `matrix`, and the required
    ///     length of `queryVector`.
    ///   - queryVector: the vector to score every row of `matrix` against.
    /// - Returns: one score per row, in row order; every score is `0.0` if
    ///   `rowCount` or `dimension` is `0`, or `queryVector.count !=
    ///   dimension`.
    public static func matvecScores(matrix: [Float], rowCount: Int, dimension: Int, queryVector: [Float]) -> [Float] {
        guard rowCount > 0, dimension > 0, queryVector.count == dimension else {
            return [Float](repeating: 0.0, count: rowCount)
        }

        var result = [Float](repeating: 0.0, count: rowCount)
        matrix.withUnsafeBufferPointer { matrixBuffer in
            queryVector.withUnsafeBufferPointer { queryBuffer in
                result.withUnsafeMutableBufferPointer { resultBuffer in
                    multiplyMatrixByVector(
                        matrixBuffer: matrixBuffer,
                        queryBuffer: queryBuffer,
                        resultBuffer: resultBuffer,
                        rowCount: rowCount,
                        dimension: dimension
                    )
                }
            }
        }
        return result
    }

    /// Calls `vDSP_mmul` over three already-`withUnsafe(Mutable)BufferPointer`-bound
    /// buffers, or does nothing if any of them has no base address (an empty
    /// backing array).
    ///
    /// Factored out of `matvecScores(matrix:rowCount:dimension:queryVector:)`'s
    /// triple nested `withUnsafeBufferPointer` calls so that unavoidable
    /// nesting doesn't also have to carry the pointer-validation `guard`
    /// inline, one level deeper still.
    ///
    /// - Parameters:
    ///   - matrixBuffer: the bound buffer over the row-major `rowCount ×
    ///     dimension` matrix.
    ///   - queryBuffer: the bound buffer over the length-`dimension` query
    ///     vector.
    ///   - resultBuffer: the bound mutable buffer `vDSP_mmul` writes the
    ///     `rowCount` scores into.
    ///   - rowCount: the number of rows in `matrixBuffer`.
    ///   - dimension: the number of columns in `matrixBuffer`, and the
    ///     length of `queryBuffer`.
    private static func multiplyMatrixByVector(
        matrixBuffer: UnsafeBufferPointer<Float>,
        queryBuffer: UnsafeBufferPointer<Float>,
        resultBuffer: UnsafeMutableBufferPointer<Float>,
        rowCount: Int,
        dimension: Int
    ) {
        guard
            let matrixBase = matrixBuffer.baseAddress,
            let queryBase = queryBuffer.baseAddress,
            let resultBase = resultBuffer.baseAddress
        else {
            return
        }
        vDSP_mmul(
            matrixBase, 1,
            queryBase, 1,
            resultBase, 1,
            vDSP_Length(rowCount), 1, vDSP_Length(dimension)
        )
    }

    /// Cosine similarity between two equal-length vectors: `(a · b) / (|a|
    /// |b|)`.
    ///
    /// Unlike `matvecScores`, this scalar form works on un-normalized
    /// vectors — it divides out both magnitudes itself — at the cost of one
    /// dot-product-and-two-magnitudes loop per call, so it suits a corpus
    /// that scores rows one at a time rather than as a packed matrix.
    ///
    /// - Parameters:
    ///   - query: the first vector to compare.
    ///   - target: the second vector to compare.
    /// - Returns: the similarity in `[-1.0, 1.0]`, or `0.0` if the vectors
    ///   differ in length, either is empty, or either has zero magnitude
    ///   (orthogonal-by-convention, matching "either side lacks a usable
    ///   embedding").
    public static func cosineSimilarity(_ query: [Float], _ target: [Float]) -> Double {
        guard query.count == target.count, !query.isEmpty else { return 0.0 }

        var dotProduct: Float = 0.0
        var queryMagnitudeSquared: Float = 0.0
        var targetMagnitudeSquared: Float = 0.0
        for index in query.indices {
            dotProduct += query[index] * target[index]
            queryMagnitudeSquared += query[index] * query[index]
            targetMagnitudeSquared += target[index] * target[index]
        }

        guard queryMagnitudeSquared > 0.0, targetMagnitudeSquared > 0.0 else { return 0.0 }
        return Double(dotProduct / (queryMagnitudeSquared.squareRoot() * targetMagnitudeSquared.squareRoot()))
    }
}
