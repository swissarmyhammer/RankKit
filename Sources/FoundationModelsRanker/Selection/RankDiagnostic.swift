// New to FoundationModelsRanker (plan.md §6 phase 3) -- generalizes the two selection-tier
// cases of FoundationModelsMetadataRegistry's own
// `Sources/FoundationModelsMetadataRegistry/Catalog/Diagnostics.swift`
// (`MetadataDiagnostic`) into a neutral channel with no default logger:
// unlike `MetadataDiagnostic.log(_:)`, consumers map `RankDiagnostic` into
// their own diagnostics or logging rather than FoundationModelsRanker logging on their
// behalf.
//
// `.embeddingUnavailable` is added by the `Searcher` facade task (plan.md
// §3a): the retrieval-tier counterpart to `MetadataDiagnostic
// .embeddingUnavailable`, reported whenever `Searcher` degrades the cosine
// signal to keyword-only.

/// FoundationModelsRanker's neutral diagnostics channel: graceful-degradation events a
/// selection tier or the `Searcher` facade reports, never silently.
///
/// Consumers map these into their own diagnostics or logging surface --
/// FoundationModelsRanker itself never logs on a caller's behalf.
public enum RankDiagnostic: Sendable, Equatable {
    /// The over-budget capacity fallback cut the candidate set from
    /// `considered` items down to `kept` before seeding a one-off
    /// selection session.
    case retrievalCut(considered: Int, kept: Int)

    /// The selection model returned an id absent from the current
    /// candidate set. Structurally unreachable given grammar-constrained
    /// output, but defended against anyway.
    case unknownSelectedId(id: String)

    /// No embedder is configured for the cosine signal (or embedding the
    /// query itself failed), so retrieval degraded to keyword-only (BM25 +
    /// trigram) for this search.
    case embeddingUnavailable
}
