// New to RankKit (plan.md §6 phase 3) -- generalizes the two selection-tier
// cases of FoundationModelsMetadataRegistry's own
// `Sources/FoundationModelsMetadataRegistry/Catalog/Diagnostics.swift`
// (`MetadataDiagnostic`) into a neutral channel with no default logger:
// unlike `MetadataDiagnostic.log(_:)`, consumers map `RankDiagnostic` into
// their own diagnostics or logging rather than RankKit logging on their
// behalf.

/// RankKit's neutral diagnostics channel: graceful-degradation events a
/// selection tier reports, never silently.
///
/// Consumers map these into their own diagnostics or logging surface --
/// RankKit itself never logs on a caller's behalf.
public enum RankDiagnostic: Sendable, Equatable {
    /// The over-budget capacity fallback cut the candidate set from
    /// `considered` items down to `kept` before seeding a one-off
    /// selection session.
    case retrievalCut(considered: Int, kept: Int)

    /// The selection model returned an id absent from the current
    /// candidate set. Structurally unreachable given grammar-constrained
    /// output, but defended against anyway.
    case unknownSelectedId(id: String)
}
