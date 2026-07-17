import Foundation
import FoundationModelsRanker

/// A `TextEmbedding` test double whose `embed(_:)` returns one vector
/// short for any multi-text (batched) call, but embeds a single text
/// correctly.
///
/// Exists to exercise `StreamingSearchCorpus.add(items:)`'s
/// mismatched-vector-count error path (^rayd7bq): `add(items:)` embeds
/// its newly-added items in one batched call (more than one text
/// whenever more than one item is added at once), so failing only
/// multi-text calls reproduces "add's embed call returns the wrong
/// number of vectors, so no embedding is stored for any of the newly
/// added items" without this double being unusable for any other test
/// that also needs a normal, correctly-counted single-text embed (e.g.
/// a query embed elsewhere in the same corpus). In the specific
/// `add`-then-`search` regression this backs, `search(_:limit:)`'s
/// per-row embedding-completeness check (in `cosineScores`) finds the
/// first added row missing its embedding and reports
/// `.embeddingUnavailable` before ever reaching the query embed call --
/// so that regression's result is attributable to `add(items:)`'s error
/// path alone, and the single-text passthrough here is a correctness
/// property of this double (not exercised by that particular test).
final class MismatchedCountEmbedder: TextEmbedding, Sendable {
    /// The length of every vector this embedder produces.
    let dimension: Int

    private let fake: FakeEmbedder

    /// Creates a mismatched-count embedder that deterministically hashes
    /// text into vectors of `dimension` length, exactly like
    /// `FakeEmbedder`, whenever it returns the correct count.
    ///
    /// - Parameter dimension: the length of every vector this embedder
    ///   produces.
    init(dimension: Int) {
        self.dimension = dimension
        fake = FakeEmbedder(dimension: dimension)
    }

    /// Embeds `texts` normally (deterministically, via `FakeEmbedder`) for
    /// a single-text call; for any call embedding more than one text,
    /// drops the last vector so the result's count no longer matches
    /// `texts.count`.
    func embed(_ texts: [String]) async throws -> [[Float]] {
        let vectors = try await fake.embed(texts)
        return texts.count > 1 ? Array(vectors.dropLast()) : vectors
    }
}
