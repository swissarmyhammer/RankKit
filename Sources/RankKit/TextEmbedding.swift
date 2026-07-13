// Ported from CodeContextKit's
// `Sources/CodeContextKit/Embedding/TextEmbedding.swift`. Lineage: Rust
// `swissarmyhammer-search` crate -> CodeContextKit -> RankKit (plan.md §3,
// §4.2). No behavior changes; the signature is byte-identical to both
// existing copies.

/// A seam for converting text into fixed-length embedding vectors.
///
/// Abstracts over the concrete embedding backend so callers depend on this
/// narrow protocol rather than a specific implementation: conformers embed
/// a batch of texts; tests substitute a deterministic double.
/// `RoutedEmbedderAdapter` wraps FoundationModelsRouter's `RoutedEmbedder`
/// for production use.
public protocol TextEmbedding: Sendable {
    /// The length of every embedding vector this embedder produces.
    var dimension: Int { get }

    /// Embeds each input string into a `dimension`-length vector, in order.
    ///
    /// - Parameter texts: The strings to embed.
    /// - Returns: One `dimension`-length vector per input, in the same
    ///   order as `texts`.
    /// - Throws: If the underlying embedding computation fails.
    func embed(_ texts: [String]) async throws -> [[Float]]
}
