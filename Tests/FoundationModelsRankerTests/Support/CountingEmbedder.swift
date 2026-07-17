import Foundation
import FoundationModelsRanker
import os

/// A `TextEmbedding` test double that counts how many times `embed(_:)` is
/// called, wrapping `FakeEmbedder` for deterministic vectors underneath.
///
/// Exists for `StreamingSearchCorpus`'s incremental-embed economy (^rayd7bq):
/// "each added item is embedded exactly once, at add time" and "only the
/// query string is embedded per search" are both claims about *how many
/// times* `embed(_:)` runs, not just what it returns -- `FakeEmbedder` alone
/// has no way to assert that. A test drives calls in a known order (adds,
/// then searches) and reads `callCount` before/after each phase to assert the
/// expected delta.
final class CountingEmbedder: TextEmbedding, Sendable {
    let dimension: Int

    private let fake: FakeEmbedder
    private let callCountBox = OSAllocatedUnfairLock<Int>(initialState: 0)

    /// Creates a counting embedder that deterministically hashes text into
    /// vectors of `dimension` length, exactly like `FakeEmbedder`.
    ///
    /// - Parameter dimension: the length of every vector this embedder
    ///   produces.
    init(dimension: Int) {
        self.dimension = dimension
        fake = FakeEmbedder(dimension: dimension)
    }

    /// The number of times `embed(_:)` has been called so far.
    var callCount: Int { callCountBox.withLock { $0 } }

    /// Increments the call count and returns embeddings from the wrapped
    /// embedder.
    func embed(_ texts: [String]) async throws -> [[Float]] {
        callCountBox.withLock { $0 += 1 }
        return try await fake.embed(texts)
    }
}
