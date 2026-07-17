// New to FoundationModelsRanker (plan.md §3a) -- the trivial unit `Searcher` (Searcher.swift)
// answers `search(_:limit:)` calls over: "a list of things to search, then a
// query" is the whole API, and the things to search need only an id and the
// text that describes them. No source file to port -- neither CodeContextKit
// nor FoundationModelsMetadataRegistry exposes a bare id+text seam this
// shape; FMR's own `SearchableMetadata` protocol is the closest structural
// precedent (an id-keyed conformer rendering its own block/summary), but it
// requires a richer "render a block" shape FoundationModelsRanker's facade doesn't need.

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
    /// by, and the identity `SearchCorpus` dedups on. Identity only: it
    /// seeds `primaryText`'s default, but a conformer that overrides
    /// `primaryText` keeps `id` as an opaque key that never itself enters
    /// retrieval scoring.
    var id: String { get }

    /// This item's primary retrieval field -- BM25-field-weighted as the
    /// primary field (`BM25.primaryFieldWeight`) and trigrammed as the
    /// primary trigram set, the higher-weighted half of what retrieval
    /// scores against the query (`text` is the lower-weighted body half).
    ///
    /// Defaults to `id`, so a conformer with nothing more salient than its
    /// id to rank on need not override it -- and every existing conformer
    /// keeps its prior behavior, in which the id *was* the primary field.
    /// A conformer whose ranking should key on a distinct salient field --
    /// a title, a symbol path -- returns that here while keeping `id` as a
    /// separate opaque identity. Decoupling the two also lifts `id`'s
    /// uniqueness requirement off that field: two items may share a
    /// `primaryText` while carrying distinct ids, where collapsing both
    /// roles onto `id` would have dropped the second as a duplicate.
    var primaryText: String { get }

    /// This item's full text -- the retrieval body field (`BM25
    /// .bodyFieldWeight`) scored against the query, and (when an embedder
    /// is configured) what gets embedded for the cosine signal.
    var text: String { get }

    /// A (typically shorter) summary of this item, used to seed the
    /// selection tier's assembled prefix instead of the full `text` --
    /// `SelectionCatalog.summaryBlock(forID:)`'s source. Defaults to
    /// `text`.
    var summary: String { get }

    /// The eviction group this item belongs to -- `SearchCorpus
    /// .remove(group:)`'s key, and nothing else: `group` never enters
    /// retrieval, is never scored, and never reaches the selection prefix.
    ///
    /// Exists for the streaming case, where items arrive one at a time but
    /// leave in cohorts: a producer appending entries for a long-running
    /// session tags each with that session's identifier, then evicts the
    /// whole session in one call when it ends. Defaults to `nil` -- an
    /// ungrouped item, which no `remove(group:)` can ever evict.
    var group: String? { get }
}

extension Searchable {
    /// The default primary field: `id` itself -- the pre-`primaryText`
    /// behavior, in which a conformer's id doubled as its primary retrieval
    /// field. A conformer with a more salient field to weight (a title, a
    /// symbol path) overrides this.
    public var primaryText: String { id }

    /// The default summary: `text` itself, verbatim -- a conformer with
    /// nothing shorter to offer the selection prefix.
    public var summary: String { text }

    /// The default group: none -- a conformer whose items are never evicted
    /// in cohorts, only individually by id (if at all).
    public var group: String? { nil }
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

    /// This item's primary retrieval field, weighted `BM25
    /// .primaryFieldWeight`. Defaults to `id` when
    /// `init(id:text:primaryText:summary:group:)` receives no explicit
    /// value -- the pre-`primaryText` behavior, where the id was the
    /// primary field.
    public let primaryText: String

    /// This item's full text.
    public let text: String

    /// This item's summary, seeding the selection prefix. Defaults to
    /// `text` when `init(id:text:primaryText:summary:group:)` receives no
    /// explicit value.
    public let summary: String

    /// This item's eviction group, or `nil` (the default) for an ungrouped
    /// item -- `SearchCorpus.remove(group:)`'s key.
    public let group: String?

    /// Creates a search item.
    ///
    /// - Parameters:
    ///   - id: this item's id.
    ///   - text: this item's full text.
    ///   - primaryText: this item's primary retrieval field, weighted
    ///     `BM25.primaryFieldWeight`. Defaults to `id` when `nil` (the
    ///     default) -- the pre-`primaryText` behavior.
    ///   - summary: this item's summary, seeding the selection prefix.
    ///     Defaults to `text` when `nil` (the default).
    ///   - group: this item's eviction group. Defaults to `nil` -- an
    ///     ungrouped item, which no `SearchCorpus.remove(group:)` evicts.
    public init(id: String, text: String, primaryText: String? = nil, summary: String? = nil, group: String? = nil) {
        self.id = id
        self.primaryText = primaryText ?? id
        self.text = text
        self.summary = summary ?? text
        self.group = group
    }
}
