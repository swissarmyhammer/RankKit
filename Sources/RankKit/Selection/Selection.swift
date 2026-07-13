// Ported from FoundationModelsMetadataRegistry's
// `Sources/FoundationModelsMetadataRegistry/Selection/Selection.swift`
// (plan.md §6 phase 3). No behavior or shape changes -- the same
// `@Generable`, ids-only output. Doc comment updated to reference
// `SelectionConfig.selectionDefault` (this package's neutral rename of
// `.librarianDefault`) and to drop the FoundationModelsMetadataRegistry-
// specific `MetadataSearcher`/`Match` cross-references.

import FoundationModels

/// The selection tier's guided-generation output: **ids only, never
/// blocks** -- the model picks from the current candidate id enum (a
/// grammar the selection tier constrains structurally), and the tier maps
/// the returned ids back through its catalog to verbatim results
/// afterward. The model is never asked to reproduce a block, only to
/// choose among ids.
@Generable
public struct Selection: Sendable, Equatable {
    /// The selected ids -- fewest that suffice, in call order when order
    /// matters (the selection guidance's own phrasing,
    /// `SelectionConfig.selectionDefault`); empty when nothing in the
    /// candidate set fits the intent.
    @Guide(
        description: "the selected ids, fewest that suffice, in call order when order "
            + "matters; empty if nothing in the candidate set fits the intent."
    )
    public var ids: [String]

    /// Creates a selection result.
    ///
    /// Explicit for the same reason as this package's other public struct
    /// initializers: a `public` struct's synthesized memberwise initializer
    /// is only `internal`-accessible.
    ///
    /// - Parameter ids: the selected ids.
    public init(ids: [String]) {
        self.ids = ids
    }
}
