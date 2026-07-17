// New to FoundationModelsRanker (plan.md §6 phase 3) -- generalizes
// FoundationModelsMetadataRegistry's own
// `Sources/FoundationModelsMetadataRegistry/Catalog/Match.swift`
// (`Match<Item>`) by dropping the generic catalog item: a `SelectionTier`
// only ever needs a matched id, its verbatim catalog block, and the score/
// signals that produced the match -- never the catalog's own item type,
// which FoundationModelsRanker's narrow `SelectionCatalog` protocol never exposes.
// Consumers wrap `SelectionMatch` into their own richer result types when
// they need the original item back.

/// One retrieval or selection result over a `SelectionCatalog` (plan.md §6):
/// the catalog's own id and verbatim block, plus the fused score and the raw
/// per-signal scores that produced it.
public struct SelectionMatch: Sendable, Equatable {
    /// The matched id.
    public let id: String

    /// The matched id's block, **verbatim from the catalog** --
    /// `SelectionCatalog.block(forID:)`'s output, never re-derived and never
    /// model output (plan.md §1 "Verbatim by construction, not by prompt").
    public let block: String

    /// The fused score, normalized to `[0, 1]` -- `0.0` for an id every
    /// retrieval signal missed (the zero-scored tail of a full-catalog
    /// ordering).
    public let score: Double

    /// The raw per-signal scores that produced `score`, or `nil` when no
    /// per-signal breakdown accompanies the match.
    public let signals: Signals?

    /// Creates one retrieval or selection result.
    ///
    /// - Parameters:
    ///   - id: the matched id.
    ///   - block: the matched id's block, verbatim from the catalog.
    ///   - score: the fused score, in `[0, 1]`.
    ///   - signals: the raw per-signal scores, or `nil` when no per-signal
    ///     breakdown accompanies the match.
    public init(id: String, block: String, score: Double, signals: Signals?) {
        self.id = id
        self.block = block
        self.score = score
        self.signals = signals
    }
}
