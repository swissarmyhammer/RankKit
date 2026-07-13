@testable import RankKit

/// A simple in-memory `SelectionCatalog` conformer for `SelectionTier` tests
/// (plan.md §6 phase 3) — adapted from the source repo's `FixtureItem:
/// SearchableMetadata` fixtures (`SelectionTests`/`OverBudgetTests`), which
/// wrapped items in a `MetadataIndex`. RankKit's `SelectionCatalog` is
/// id-keyed directly, so this fixture holds ids and per-id block/summary
/// lookups instead of a list of catalog items.
struct FixtureSelectionCatalog: SelectionCatalog {
    /// One fixture entry: an id, its verbatim block, and an optional summary
    /// (defaults to `block` when omitted, mirroring the source fixtures'
    /// `renderSummaryBlock() { summary ?? block }`).
    struct Item {
        let id: String
        let block: String
        let summary: String?

        init(id: String, block: String, summary: String? = nil) {
            self.id = id
            self.block = block
            self.summary = summary
        }
    }

    let ids: [String]
    private let items: [String: Item]

    /// Creates a catalog from `items`, preserving their order as `ids`.
    ///
    /// - Parameter items: this catalog's entries, in candidate order.
    init(_ items: [Item]) {
        self.ids = items.map(\.id)
        self.items = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
    }

    func summaryBlock(forId id: String) -> String? {
        guard let item = items[id] else { return nil }
        return item.summary ?? item.block
    }

    func block(forId id: String) -> String? {
        items[id]?.block
    }
}
