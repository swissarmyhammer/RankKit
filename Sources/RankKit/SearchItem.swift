// New to RankKit (plan.md §3a) -- the trivial unit `Searcher` (Searcher.swift)
// answers `search(_:limit:)` calls over: "a list of things to search, then a
// query" is the whole API, and the things to search need only an id and the
// text that describes them. No source file to port -- neither CodeContextKit
// nor FoundationModelsMetadataRegistry exposes a bare id+text seam this
// shape; FMR's own `SearchableMetadata` protocol is the closest structural
// precedent (an id-keyed conformer rendering its own block/summary), but it
// requires a richer "render a block" shape RankKit's facade doesn't need.

/// A richer type's seam into `Searcher` without wrapping it in `SearchItem`
/// (plan.md §3a): an id, the text `Searcher` indexes for retrieval, and a
/// summary that seeds the selection prefix.
///
/// `SearchItem` is the trivial conformer for callers with nothing richer to
/// offer; a consumer's own domain type (a tool descriptor, a catalog entry,
/// a document) conforms directly instead of copying its fields into a
/// `SearchItem` first.
public protocol Searchable: Sendable {
    /// This item's id -- what `Searcher.search(_:limit:)` results are keyed
    /// by, and (BM25-field-weighted as the primary field, `BM25
    /// .primaryFieldWeight`) part of what retrieval scores against the
    /// query.
    var id: String { get }

    /// This item's full text -- the retrieval body field (`BM25
    /// .bodyFieldWeight`) scored against the query, and (when an embedder
    /// is configured) what gets embedded for the cosine signal.
    var text: String { get }

    /// A (typically shorter) summary of this item, used to seed the
    /// selection tier's assembled prefix instead of the full `text` --
    /// `SelectionCatalog.summaryBlock(forId:)`'s source. Defaults to
    /// `text`.
    var summary: String { get }
}

extension Searchable {
    /// The default summary: `text` itself, verbatim -- a conformer with
    /// nothing shorter to offer the selection prefix.
    public var summary: String { text }
}

/// The trivial `Searchable` conformer (plan.md §3a): an id, the text that
/// describes it, and an optional summary.
///
/// ```swift
/// let items = [
///     SearchItem(id: "grep", text: "Search file contents with regular expressions"),
///     SearchItem(id: "glob", text: "Find files by name pattern, sorted by mtime"),
/// ]
/// let searcher = try await Searcher(items)
/// ```
public struct SearchItem: Searchable, Sendable, Equatable {
    /// This item's id.
    public let id: String

    /// This item's full text.
    public let text: String

    /// This item's summary, seeding the selection prefix. Defaults to
    /// `text` when `init(id:text:summary:)` receives no explicit value.
    public let summary: String

    /// Creates a search item.
    ///
    /// - Parameters:
    ///   - id: this item's id.
    ///   - text: this item's full text.
    ///   - summary: this item's summary, seeding the selection prefix.
    ///     Defaults to `text` when `nil` (the default).
    public init(id: String, text: String, summary: String? = nil) {
        self.id = id
        self.text = text
        self.summary = summary ?? text
    }
}
