// Ported from FoundationModelsMetadataRegistry's
// `Sources/FoundationModelsMetadataRegistry/Embedding/RoutedEmbedderAdapter.swift`.
// Lineage: CodeContextKit -> FoundationModelsMetadataRegistry -> FoundationModelsRanker
// (plan.md §3, §4.3). The call-site label is ported from CodeContextKit's
// copy (`embed(texts:)`), not FMR's (`embed(_:)`): plan.md §1/§4.3 recorded
// FMR's `embed(_:)` as matching FoundationModelsRouter `main` as of
// 2026-07-07, but Router `main` as resolved today (commit `a3d8c04`, pinned
// in this package's `Package.resolved`) exposes `RoutedEmbedder.embed(texts:
// [String])` throughout -- the same labeled form CodeContextKit already
// used. That premise has gone stale since the plan was written; this port
// follows the verified current Router API so the adapter actually compiles
// against `main`, preserving the plan's intent (compile against Router
// `main`) over its now-incorrect label description.

import FoundationModelsRouter

/// Adapts FoundationModelsRouter's `RoutedEmbedder` to the `TextEmbedding`
/// seam.
///
/// `RoutedEmbedder` (a `RoutedModel<any LoadedEmbeddingContainer>`) already
/// exposes `dimension: Int` and `embed(texts:) async throws -> [[Float]]`
/// with exactly `TextEmbedding`'s shape and semantics -- one
/// `dimension`-length vector per input string, in order, with any
/// embedder-container error rethrown unchanged. No batching or error
/// bridging is needed: this type is a pure pass-through, forwarding both
/// members straight to the wrapped handle.
///
/// One side effect rides along with that pass-through: `RoutedEmbedder`'s
/// own `embed(texts:)` best-effort-records one transcript event per call,
/// containing every input text joined together. That recording is the
/// wrapped handle's existing behavior, not something this adapter adds or
/// can opt out of -- worth knowing when reasoning about transcript volume
/// during a bulk embedding pass.
public struct RoutedEmbedderAdapter: TextEmbedding {
    private let routedEmbedder: RoutedEmbedder

    /// Wraps a resolved `RoutedEmbedder` handle as a `TextEmbedding`.
    ///
    /// - Parameter routedEmbedder: The resolved embedding model handle to
    ///   wrap.
    public init(routedEmbedder: RoutedEmbedder) {
        self.routedEmbedder = routedEmbedder
    }

    /// The length of every embedding vector this embedder produces,
    /// forwarded from the wrapped `RoutedEmbedder`.
    public var dimension: Int { routedEmbedder.dimension }

    /// Embeds each input string into a `dimension`-length vector, in order,
    /// forwarded straight to the wrapped `RoutedEmbedder`.
    ///
    /// - Parameter texts: The strings to embed.
    /// - Returns: One `dimension`-length vector per input, in the same
    ///   order as `texts`.
    /// - Throws: Whatever `RoutedEmbedder.embed(texts:)` throws.
    public func embed(_ texts: [String]) async throws -> [[Float]] {
        try await routedEmbedder.embed(texts: texts)
    }
}
