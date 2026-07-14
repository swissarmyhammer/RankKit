// The seam generalizing FoundationModelsMetadataRegistry's
// `MetadataIndex<Item>` for FoundationModelsRanker's selection tier (plan.md §6 phase 3).
// New to FoundationModelsRanker -- there is no direct source file to port; this protocol
// captures the three operations `SelectionTier` actually used from
// `MetadataIndex`: the full candidate id set, each id's rendered summary
// (`SearchableMetadata.renderSummaryBlock()`), and each id's verbatim block
// (`MetadataIndex.block(forId:)`).

/// The catalog contract FoundationModelsRanker's selection tier drives its assembled prefix
/// and verbatim result lookup through.
///
/// The coupling is narrow: a selection tier only ever needs the full
/// candidate id set, a (typically shorter) summary per id to seed the
/// prefix it hands the model, and the full verbatim block per id to hand
/// back as a result payload once the model picks that id. Any index or
/// snapshot type -- FoundationModelsRanker's own future retrieval types, or a consumer's
/// bespoke catalog -- conforms trivially by forwarding to its existing
/// lookups; nothing here requires adopting a particular storage shape.
public protocol SelectionCatalog: Sendable {
    /// The catalog's ids, in the order candidates should be considered --
    /// the full candidate set under budget, or the set a selection tier
    /// ranks from over budget.
    var ids: [String] { get }

    /// A (typically shorter) summary of `id`'s item, used to seed the
    /// selection tier's assembled prefix instead of the full
    /// `block(forId:)` -- the seam `SearchableMetadata.renderSummaryBlock()`
    /// filled in the source tier, generalized here to a per-id lookup.
    ///
    /// - Parameter forId: the id to look up.
    /// - Returns: the id's summary text, or `nil` if `id` isn't in this
    ///   catalog.
    func summaryBlock(forId id: String) -> String?

    /// `id`'s full, verbatim result payload -- what a model-selected id
    /// resolves to in the tier's returned results, never re-derived from
    /// the model's own output.
    ///
    /// - Parameter forId: the id to look up.
    /// - Returns: the id's verbatim block, or `nil` if `id` isn't in this
    ///   catalog.
    func block(forId id: String) -> String?
}
